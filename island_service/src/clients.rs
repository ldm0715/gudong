//! 消息客户端的前台识别与打开。

use std::time::{Duration, Instant};

use windows::{
    core::PWSTR,
    Win32::{
        Foundation::{BOOL, CloseHandle, HWND, LPARAM, RECT, WPARAM},
        System::Threading::{
            OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
            PROCESS_QUERY_LIMITED_INFORMATION,
        },
        UI::WindowsAndMessaging::{
            EnumWindows, GetClassNameW, GetForegroundWindow, GetWindow, GetWindowLongW,
            GetWindowRect, GetWindowThreadProcessId, IsIconic, IsWindow, IsWindowVisible,
            IsZoomed,
            PostMessageW, SetForegroundWindow, ShowWindowAsync, GWL_EXSTYLE, GWL_STYLE, GW_OWNER,
            SW_RESTORE, WM_LBUTTONDBLCLK, WM_LBUTTONDOWN, WM_LBUTTONUP, WS_CAPTION,
            WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_MINIMIZEBOX, WS_SYSMENU, WS_THICKFRAME,
        },
    },
};

pub fn foreground_client() -> Option<(&'static str, u32)> {
    unsafe {
        let window = GetForegroundWindow();
        if window.0.is_null() {
            return None;
        }
        let pid = window_pid(window);
        if pid == 0 {
            return None;
        }
        let image = process_image(pid)?;
        let name = image.rsplit('\\').next().unwrap_or(&image).to_ascii_lowercase();
        match name.as_str() {
            "weixin.exe" | "wechat.exe" => Some(("wechat", pid)),
            "qq.exe" => Some(("qq", pid)),
            _ => None,
        }
    }
}

/// 当前前台窗口是否最大化。前台是 gudong 自己的窗口时返回 None，保持上一次状态。
pub fn foreground_maximized() -> Option<bool> {
    unsafe {
        let window = GetForegroundWindow();
        if window.0.is_null() {
            return None;
        }
        let pid = window_pid(window);
        if pid == 0 {
            return None;
        }
        if let Some(image) = process_image(pid) {
            let name = image
                .rsplit('\\')
                .next()
                .unwrap_or(&image)
                .to_ascii_lowercase();
            if name == "island_app.exe" || name == "island_service.exe" {
                return None;
            }
        }
        Some(IsZoomed(window).as_bool())
    }
}

/// 打开客户端：可见窗口切前台，最小化窗口还原；缩在托盘时模拟点击它自己的托盘图标。
/// 不直接 ShowWindow / SC_RESTORE 隐藏窗口（Qt / Electron 会卡死），也不启动新实例。
pub fn open_client_at(source: &str, account: u32, saved: i64) -> Result<i64, String> {
    let supplied = if saved == 0 {
        None
    } else {
        let window = HWND(saved as *mut _);
        unsafe { IsWindow(window).as_bool().then_some(window) }
    };
    let window = supplied.or_else(|| select(source, account));
    if let Some(window) = window {
        unsafe {
            if IsWindowVisible(window).as_bool() {
                if IsIconic(window).as_bool() {
                    let _ = ShowWindowAsync(window, SW_RESTORE);
                }
                let _ = SetForegroundWindow(window);
                return Ok(window.0 as isize as i64);
            }
        }
    }
    let target = if source == "wechat" {
        crate::wechat_tray::click(account)
    } else if source == "qq" {
        qq_tray_click(account)
    } else {
        None
    };
    if let Some(window) = target {
        return Ok(window.0 as isize as i64);
    }
    Err(format!(
        "{}在托盘里，未能自动唤出，请从托盘打开",
        source_name(source)
    ))
}

/// QQ 缩在托盘时没有主窗口。按下它自己的托盘图标，让 QQ 自己显示主窗口。
fn qq_tray_click(account: u32) -> Option<HWND> {
    unsafe {
        struct Search {
            account: u32,
            hosts: Vec<HWND>,
        }
        unsafe extern "system" fn visit(hwnd: HWND, data: LPARAM) -> BOOL {
            let search = &mut *(data.0 as *mut Search);
            if class_name(hwnd) != "Electron_NotifyIconHostWindow" {
                return true.into();
            }
            let pid = window_pid(hwnd);
            if (search.account != 0 && pid != search.account) || !process_matches("qq", pid) {
                return true.into();
            }
            search.hosts.push(hwnd);
            true.into()
        }
        let mut search = Search {
            account,
            hosts: Vec::new(),
        };
        let _ = EnumWindows(
            Some(visit),
            LPARAM((&mut search as *mut Search) as isize),
        );
        for host in search.hosts {
            let icons: Vec<u32> = (0..=256u32)
                .filter(|id| crate::wechat_tray::tray_rect(host, *id).is_some())
                .collect();
            let Some(id) = icons.first() else {
                continue;
            };
            for event in [WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK, WM_LBUTTONUP] {
                let _ = PostMessageW(
                    host,
                    0x8000 + 1,
                    WPARAM(*id as usize),
                    LPARAM(event as isize),
                );
            }
            let until = Instant::now() + Duration::from_secs(2);
            while Instant::now() < until {
                if let Some(window) = visible_main_window("qq", account) {
                    return Some(window);
                }
                std::thread::sleep(Duration::from_millis(80));
            }
        }
        None
    }
}

pub(crate) fn visible_main_window(source: &str, account: u32) -> Option<HWND> {
    let window = select(source, account)?;
    unsafe { IsWindowVisible(window).as_bool().then_some(window) }
}

/// 给系统通知条目补充客户端主窗口句柄，点击时可以直接恢复正确的窗口。
pub fn preferred_window(source: &str) -> i64 {
    select(source, 0)
        .map(|window| window.0 as isize as i64)
        .unwrap_or(0)
}

fn source_name(source: &str) -> &'static str {
    if source == "qq" {
        "QQ"
    } else {
        "微信"
    }
}

struct Search<'a> {
    source: &'a str,
    pid: u32,
    list: Vec<Candidate>,
}

struct Candidate {
    hwnd: HWND,
    visible: bool,
    area: i64,
}

fn select(source: &str, pid: u32) -> Option<HWND> {
    let mut search = Search {
        source,
        pid,
        list: Vec::new(),
    };
    unsafe {
        let _ = EnumWindows(Some(visit), LPARAM((&mut search as *mut Search) as isize));
    }
    search
        .list
        .sort_by(|left, right| right.visible.cmp(&left.visible).then(right.area.cmp(&left.area)));
    search.list.first().map(|candidate| candidate.hwnd)
}

unsafe extern "system" fn visit(hwnd: HWND, data: LPARAM) -> BOOL {
    let search = &mut *(data.0 as *mut Search);
    let pid = window_pid(hwnd);
    if pid == 0 || (search.pid != 0 && pid != search.pid) {
        return true.into();
    }
    let class = class_name(hwnd);
    let main = match search.source {
        "wechat" => is_wechat_class(&class),
        "qq" => is_qq_class(&class),
        _ => false,
    };
    if !main || GetWindow(hwnd, GW_OWNER).is_ok() {
        return true.into();
    }
    let style = GetWindowLongW(hwnd, GWL_STYLE) as u32;
    let extended = GetWindowLongW(hwnd, GWL_EXSTYLE) as u32;
    let frame = (WS_SYSMENU | WS_MINIMIZEBOX).0;
    let resizable = (WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX).0;
    let main_frame = (style & frame == frame
        || (class.starts_with("Qt") || class == "Chrome_WidgetWin_1")
            && style & resizable == resizable)
        && extended & (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE).0 == 0;
    if !main_frame {
        return true.into();
    }
    if !process_matches(search.source, pid) {
        return true.into();
    }
    let mut rect = RECT::default();
    let area = if GetWindowRect(hwnd, &mut rect).is_ok() {
        i64::from(rect.right - rect.left) * i64::from(rect.bottom - rect.top)
    } else {
        0
    };
    // 过小的辅助窗口不参与选择，但最小化的主窗口仍保留。
    if area > 0 && area < 20_000 {
        return true.into();
    }
    search.list.push(Candidate {
        hwnd,
        visible: IsWindowVisible(hwnd).as_bool() && !IsIconic(hwnd).as_bool(),
        area,
    });
    true.into()
}

pub(crate) fn process_matches(source: &str, pid: u32) -> bool {
    process_image(pid).is_some_and(|path| process_matches_path(source, &path))
}

fn process_name_matches(source: &str, name: &str) -> bool {
    let name = name.to_ascii_lowercase();
    match source {
        "wechat" => matches!(name.as_str(), "weixin.exe" | "wechat.exe"),
        "qq" => name == "qq.exe",
        _ => false,
    }
}

fn process_matches_path(source: &str, path: &str) -> bool {
    let name = path.rsplit('\\').next().unwrap_or(path);
    process_name_matches(source, name)
}

fn is_wechat_class(class: &str) -> bool {
    class == "WeChatMainWndForPC" || (class.starts_with("Qt") && class.ends_with("QWindowIcon"))
}

fn is_qq_class(class: &str) -> bool {
    class == "Chrome_WidgetWin_1" || class == "TXGuiFoundation"
}

fn window_pid(window: HWND) -> u32 {
    let mut pid = 0;
    unsafe {
        GetWindowThreadProcessId(window, Some(&mut pid));
    }
    pid
}

fn class_name(window: HWND) -> String {
    let mut buffer = [0u16; 256];
    let length = unsafe { GetClassNameW(window, &mut buffer) };
    String::from_utf16_lossy(&buffer[..length.max(0) as usize])
}

fn process_image(pid: u32) -> Option<String> {
    unsafe {
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut path = [0u16; 32768];
        let mut length = path.len() as u32;
        let result =
            QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, PWSTR(path.as_mut_ptr()), &mut length);
        let _ = CloseHandle(process);
        result.ok()?;
        Some(String::from_utf16_lossy(&path[..length as usize]))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_window_classes_are_matched_without_guessing() {
        assert!(is_wechat_class("WeChatMainWndForPC"));
        assert!(is_wechat_class("Qt51515QWindowIcon"));
        assert!(!is_wechat_class("Chrome_WidgetWin_1"));
        assert!(is_qq_class("Chrome_WidgetWin_1"));
        assert!(is_qq_class("TXGuiFoundation"));
        assert!(!is_qq_class("WeChatMainWndForPC"));
    }

    #[test]
    #[ignore = "会切换 QQ 到前台"]
    fn live_open_qq() {
        println!("open qq: {:?}", open_client_at("qq", 0, 0));
    }
}
