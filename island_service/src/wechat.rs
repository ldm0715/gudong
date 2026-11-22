//! 微信任务栏闪烁监听：从岛仔 `wechat.rs` 抽出，去掉 egui 依赖后按事件推给 IPC。
//!
//! 只关心两件事：闪动窗口是否属于微信，以及该账号是否正在前台。
//! 联系人和消息预览由 `notifications.rs` 从系统通知读取。

use std::cell::RefCell;
use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::Value;
use windows::{
    core::{w, PCWSTR, PWSTR},
    Win32::{
        Foundation::{CloseHandle, HWND, LPARAM, LRESULT, WPARAM},
        Storage::FileSystem::{
            GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW,
        },
        System::{
            Registry::{RegGetValueW, HKEY_CLASSES_ROOT, HKEY_CURRENT_USER, RRF_RT_REG_SZ},
            Threading::{
                OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
                PROCESS_QUERY_LIMITED_INFORMATION,
            },
        },
        UI::{
            Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass},
            WindowsAndMessaging::*,
        },
    },
};

use crate::rpc::{self, State};

const SUBCLASS_ID: usize = 0x4755_4455;
const HSHELL_FLASH: usize = 0x8006;

/// 启动监听线程。返回时确认消息窗口已注册，失败时给出可展示的原因。
pub fn start(state: Arc<State>, tx: Sender<Value>) -> Result<(), String> {
    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<(), String>>();
    std::thread::Builder::new()
        .name("wechat-listener".into())
        .spawn(move || unsafe {
            let result = run(state, tx, &ready_tx);
            if let Err(error) = result {
                let _ = ready_tx.send(Err(error));
            }
        })
        .map_err(|error| format!("无法启动监听线程：{error}"))?;
    ready_rx
        .recv_timeout(Duration::from_secs(3))
        .map_err(|_| "监听线程启动超时".to_string())?
}

unsafe fn run(
    state: Arc<State>,
    tx: Sender<Value>,
    ready_tx: &std::sync::mpsc::Sender<Result<(), String>>,
) -> Result<(), String> {
    let paths = installed_paths();
    if paths.is_empty() {
        let message = "未找到微信安装路径，请安装微信后重新启动".to_string();
        let _ = ready_tx.send(Err(message.clone()));
        let _ = tx.send(rpc::emit_status(&state, "wechat", false, &message));
        return Ok(());
    }

    let message = RegisterWindowMessageW(w!("SHELLHOOK"));
    if message == 0 {
        let text = "无法注册微信提醒事件".to_string();
        let _ = ready_tx.send(Err(text.clone()));
        let _ = tx.send(rpc::emit_status(&state, "wechat", false, &text));
        return Ok(());
    }
    let taskbar_created = RegisterWindowMessageW(w!("TaskbarCreated"));
    let hwnd = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        w!("STATIC"),
        w!("GudongWechatListener"),
        WS_POPUP,
        0,
        0,
        0,
        0,
        None,
        None,
        None,
        None,
    )
    .map_err(|_| "无法创建微信监听窗口".to_string())?;

    // 以管理员身份运行时，系统会拦下资源管理器发来的窗口事件。
    for allowed in [message, taskbar_created] {
        let _ = ChangeWindowMessageFilterEx(hwnd, allowed, MSGFLT_ALLOW, None);
    }

    let listener_state = Box::new(RefCell::new(StateData {
        message,
        taskbar_created,
        registered: true,
        paths,
        burst: Vec::new(),
        state: state.clone(),
        tx: tx.clone(),
    }));
    let data = (&*listener_state as *const RefCell<StateData>) as usize;

    if SetWindowSubclass(hwnd, Some(subclass), SUBCLASS_ID, data)
        .ok()
        .is_err()
    {
        let _ = DestroyWindow(hwnd);
        let text = "无法接入微信提醒事件".to_string();
        let _ = ready_tx.send(Err(text.clone()));
        let _ = tx.send(rpc::emit_status(&state, "wechat", false, &text));
        return Ok(());
    }
    if RegisterShellHookWindow(hwnd).ok().is_err() {
        let _ = RemoveWindowSubclass(hwnd, Some(subclass), SUBCLASS_ID);
        let _ = DestroyWindow(hwnd);
        let text = "无法监听微信任务栏提醒".to_string();
        let _ = ready_tx.send(Err(text.clone()));
        let _ = tx.send(rpc::emit_status(&state, "wechat", false, &text));
        return Ok(());
    }

    {
        let mut status = state.listener_ok.lock().unwrap_or_else(|e| e.into_inner());
        *status = true;
    }
    {
        let mut status = state
            .listener_message
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        *status = "listening".into();
    }
    let _ = ready_tx.send(Ok(()));
    let _ = tx.send(rpc::emit_status(&state, "wechat", true, "listening"));

    // 消息循环必须留在创建窗口的线程上。
    let mut msg = MSG::default();
    while GetMessageW(&mut msg, None, 0, 0).as_bool() {
        let _ = TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    let _ = DeregisterShellHookWindow(hwnd);
    let _ = RemoveWindowSubclass(hwnd, Some(subclass), SUBCLASS_ID);
    let _ = DestroyWindow(hwnd);
    Ok(())
}

struct Burst {
    last: Option<Instant>,
    window: isize,
}

impl Default for Burst {
    fn default() -> Self {
        Self {
            last: None,
            window: 0,
        }
    }
}

impl Burst {
    fn attention(&mut self, now: Instant, window: isize) -> bool {
        let changed = self.window != window;
        self.window = window;
        self.last
            .replace(now)
            .is_none_or(|last| now.duration_since(last) >= Duration::from_secs(5))
            || changed
    }
}

struct StateData {
    message: u32,
    taskbar_created: u32,
    registered: bool,
    paths: Vec<String>,
    burst: Vec<(u32, Burst)>,
    state: Arc<State>,
    tx: Sender<Value>,
}

impl StateData {
    fn attention(&mut self, pid: u32, window: isize, now: Instant) -> Option<u32> {
        if !self.burst.iter().any(|(account, _)| *account == pid) {
            self.burst.push((pid, Burst::default()));
        }
        let burst = self
            .burst
            .iter_mut()
            .find(|(account, _)| *account == pid)
            .unwrap();
        if !burst.1.attention(now, window) {
            return None;
        }
        let items = self.state.unread.lock().unwrap_or_else(|e| e.into_inner());
        let count = items
            .get(&flash_id(pid))
            .map(|item| item.count + 1)
            .unwrap_or(1);
        Some(count)
    }

    fn clear(&mut self, pid: u32) {
        self.burst.retain(|(account, _)| *account != pid);
        // 除了删内存，还要发事件，否则客户端列表会一直保留这条提醒。
        let id = flash_id(pid);
        let (event, _) = rpc::emit_cleared(&self.state, Some(&id), None, None);
        let _ = self.tx.send(event);
    }
}

fn flash_id(pid: u32) -> String {
    format!("wechat:flash:{pid}")
}

unsafe extern "system" fn subclass(
    hwnd: HWND,
    message: u32,
    wp: WPARAM,
    lp: LPARAM,
    _: usize,
    data: usize,
) -> LRESULT {
    if message == WM_NCDESTROY {
        let _ = DeregisterShellHookWindow(hwnd);
        let _ = RemoveWindowSubclass(hwnd, Some(subclass), SUBCLASS_ID);
        return DefSubclassProc(hwnd, message, wp, lp);
    }
    if data != 0 {
        let slot = &*(data as *const RefCell<StateData>);
        if let Ok(mut state) = slot.try_borrow_mut() {
            if message == state.taskbar_created && message != 0 {
                state.registered = RegisterShellHookWindow(hwnd).as_bool();
            }
            if message == state.message && matches!(wp.0, HSHELL_FLASH | 4 | 0x8004) {
                let target = HWND(lp.0 as *mut _);
                if matches(target, &state.paths) {
                    let pid = window_pid(target);
                    if pid != 0 {
                        let foreground = foreground_pid(&state.paths);
                        // 激活微信（主窗口或独立会话窗口）说明用户已查看消息；
                        // 微信在前台时新的闪动也直接忽略。
                        if wp.0 != HSHELL_FLASH || foreground == Some(pid) {
                            state.clear(pid);
                        } else if !rpc::has_toast(&state.state, "wechat") {
                            let now = Instant::now();
                            if let Some(count) = state.attention(pid, target.0 as isize, now) {
                                let item = rpc::UnreadInfo {
                                    id: flash_id(pid),
                                    source: "wechat".into(),
                                    account: pid,
                                    window: target.0 as isize as i64,
                                    count,
                                    time: rpc::now_text(),
                                    kind: "taskbar".into(),
                                    contact: None,
                                    preview: None,
                                };
                                let event = rpc::emit_unread(&state.state, item);
                                let _ = state.tx.send(event);
                            }
                        }
                    }
                }
            }
        }
    }
    DefSubclassProc(hwnd, message, wp, lp)
}

fn installed_paths() -> Vec<String> {
    let mut paths = Vec::new();
    for (key, exe) in [
        (w!("Software\\Tencent\\Weixin"), "Weixin.exe"),
        (w!("Software\\Tencent\\WeChat"), "WeChat.exe"),
    ] {
        if let Some(folder) = registry_string(HKEY_CURRENT_USER, key, w!("InstallPath")) {
            paths.push(PathBuf::from(folder).join(exe));
        }
    }
    if let Some(path) = registry_string(HKEY_CLASSES_ROOT, w!("weixin\\shell\\open\\command"), PCWSTR::null())
        .and_then(|cmd| protocol_executable(&cmd))
    {
        paths.push(path);
    }
    let mut paths: Vec<String> = paths
        .into_iter()
        .filter(|p| p.is_absolute() && p.is_file())
        .filter_map(|p| p.canonicalize().ok())
        .map(|p| normalized(&p.to_string_lossy()))
        .collect();
    // 注册表路径可能过期（升级、换目录、双开、绿色版）：再认文件名相同、且由腾讯发布的程序。
    paths.extend(["*weixin.exe".to_string(), "*wechat.exe".to_string()]);
    paths
}

fn protocol_executable(command: &str) -> Option<PathBuf> {
    let command = command.trim();
    let exe = if let Some(quoted) = command.strip_prefix('"') {
        quoted.split_once('"')?.0
    } else {
        command
            .strip_suffix(" \"%1\"")
            .or_else(|| command.strip_suffix(" %1"))
            .unwrap_or(command)
    };
    let path = PathBuf::from(exe);
    let name = path.file_name()?.to_str()?;
    (path.is_absolute()
        && (name.eq_ignore_ascii_case("Weixin.exe") || name.eq_ignore_ascii_case("WeChat.exe")))
    .then_some(path)
}

fn normalized(path: &str) -> String {
    path.trim_start_matches(r"\\?\")
        .replace('/', "\\")
        .to_lowercase()
}

fn registry_string(root: windows::Win32::System::Registry::HKEY, key: PCWSTR, name: PCWSTR) -> Option<String> {
    let mut data = [0u16; 2048];
    let mut size = (data.len() * 2) as u32;
    unsafe {
        RegGetValueW(
            root,
            key,
            name,
            RRF_RT_REG_SZ,
            None,
            Some(data.as_mut_ptr().cast()),
            Some(&mut size),
        )
    }
    .ok()
    .ok()?;
    let length = data.iter().position(|c| *c == 0).unwrap_or(data.len());
    Some(String::from_utf16_lossy(&data[..length]))
}

fn company_name(path: &str) -> String {
    unsafe {
        (|| -> Option<String> {
            let wide: Vec<u16> = path.encode_utf16().chain(Some(0)).collect();
            let size = GetFileVersionInfoSizeW(PCWSTR(wide.as_ptr()), None);
            if size == 0 {
                return None;
            }
            let mut data = vec![0u8; size as usize];
            GetFileVersionInfoW(PCWSTR(wide.as_ptr()), 0, size, data.as_mut_ptr().cast()).ok()?;
            let mut pointer = std::ptr::null_mut();
            let mut length = 0u32;
            if !VerQueryValueW(
                data.as_ptr().cast(),
                w!("\\VarFileInfo\\Translation"),
                &mut pointer,
                &mut length,
            )
            .as_bool()
                || length < 4
            {
                return None;
            }
            let translation = *(pointer as *const [u16; 2]);
            let key: Vec<u16> =
                format!(
                    "\\StringFileInfo\\{:04x}{:04x}\\CompanyName",
                    translation[0], translation[1]
                )
                .encode_utf16()
                .chain(Some(0))
                .collect();
            if !VerQueryValueW(
                data.as_ptr().cast(),
                PCWSTR(key.as_ptr()),
                &mut pointer,
                &mut length,
            )
            .as_bool()
                || length == 0
            {
                return None;
            }
            let text = std::slice::from_raw_parts(pointer as *const u16, length as usize);
            Some(
                String::from_utf16_lossy(text)
                    .trim_end_matches('\0')
                    .to_string(),
            )
        })()
    }
    .unwrap_or_default()
}

fn path_allowed(image: &str, paths: &[String]) -> bool {
    if paths.iter().any(|p| p == image) {
        return true;
    }
    let file = image.rsplit('\\').next().unwrap_or(image);
    paths.iter().any(|p| {
        p.strip_prefix('*')
            .is_some_and(|name| name == file)
            && company_name(image).to_lowercase().contains("tencent")
    }) && (file.eq_ignore_ascii_case("Weixin.exe") || file.eq_ignore_ascii_case("WeChat.exe"))
}

unsafe fn matches(hwnd: HWND, paths: &[String]) -> bool {
    if hwnd.0.is_null() {
        return false;
    }
    let mut pid = 0;
    GetWindowThreadProcessId(hwnd, Some(&mut pid));
    pid_matches(pid, paths)
}

unsafe fn pid_matches(pid: u32, paths: &[String]) -> bool {
    if pid == 0 {
        return false;
    }
    let Ok(process) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else {
        return false;
    };
    let mut path = [0u16; 32768];
    let mut length = path.len() as u32;
    let result = QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, PWSTR(path.as_mut_ptr()), &mut length);
    let _ = CloseHandle(process);
    result.is_ok()
        && path_allowed(
            &normalized(&String::from_utf16_lossy(&path[..length as usize])),
            paths,
        )
}

fn window_pid(hwnd: HWND) -> u32 {
    let mut pid = 0;
    unsafe {
        if !hwnd.0.is_null() {
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
        }
    }
    pid
}

/// 前台窗口是否属于微信。独立会话窗口也算，不要求是主窗口。
fn foreground_pid(paths: &[String]) -> Option<u32> {
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.0.is_null() || !matches(hwnd, paths) {
            return None;
        }
        Some(window_pid(hwnd))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clear_removes_flash_item_and_emits_event() {
        let state = Arc::new(State::default());
        let (tx, rx) = std::sync::mpsc::channel();
        let id = flash_id(7);
        state
            .unread
            .lock()
            .unwrap()
            .insert(
                id.clone(),
                rpc::UnreadInfo {
                    id: id.clone(),
                    source: "wechat".into(),
                    account: 7,
                    window: 0,
                    count: 1,
                    time: rpc::now_text(),
                    kind: "taskbar".into(),
                    contact: None,
                    preview: None,
                },
            );
        let mut data = StateData {
            message: 0,
            taskbar_created: 0,
            registered: true,
            paths: Vec::new(),
            burst: Vec::new(),
            state: state.clone(),
            tx,
        };
        data.clear(7);
        assert!(!state.unread.lock().unwrap().contains_key(&id));
        let event = rx.try_recv().expect("cleared event");
        assert_eq!(event["params"]["type"], "message.cleared");
        assert_eq!(event["params"]["id"], id);
    }
}
