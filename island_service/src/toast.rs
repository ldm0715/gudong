//! Windows 托盘气泡通知。
//!
//! 使用独立的隐藏窗口临时注册一个托盘图标，弹出气泡后 10 秒删除。
//! 这样不对现有托盘图标产生依赖，也不需要在宿主机上注册 AUMID。

use std::sync::mpsc::{self, Receiver, Sender};
use std::time::Duration;

pub struct Toast {
    pub title: String,
    pub body: String,
}

pub fn start() -> Sender<Toast> {
    let (tx, rx) = mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("toast".into())
        .spawn(move || run(rx));
    if let Err(error) = spawned {
        crate::log(&format!("toast: 线程启动失败: {error}"));
    }
    tx
}

#[cfg(windows)]
fn run(receiver: Receiver<Toast>) {
    use std::sync::mpsc::RecvTimeoutError;
    use std::time::Instant;

    use windows::core::w;
    use windows::Win32::UI::Shell::{
        Shell_NotifyIconW, NIF_ICON, NIF_INFO, NIF_TIP, NIIF_INFO, NIM_ADD, NIM_DELETE, NIM_MODIFY,
        NOTIFYICONDATAW,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DestroyWindow, LoadIconW, IDI_INFORMATION, WS_EX_TOOLWINDOW, WS_POPUP,
    };

    unsafe {
        let Ok(hwnd) = CreateWindowExW(
            WS_EX_TOOLWINDOW,
            w!("STATIC"),
            w!("GudongToastWindow"),
            WS_POPUP,
            0,
            0,
            0,
            0,
            None,
            None,
            None,
            None,
        ) else {
            crate::log("toast: 无法创建通知窗口");
            return;
        };
        let mut data = NOTIFYICONDATAW::default();
        data.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        data.hWnd = hwnd;
        data.uID = 1;
        data.hIcon = LoadIconW(None, IDI_INFORMATION).unwrap_or_default();
        set_text(&mut data.szTip, "gudong");

        // 通知期间临时显示托盘图标，10 秒后删除，避免常驻第二个图标。
        let mut registered = false;
        let mut hide_at: Option<Instant> = None;
        loop {
            let next = match hide_at {
                Some(deadline) => {
                    let wait = deadline.saturating_duration_since(Instant::now());
                    match receiver.recv_timeout(wait) {
                        Ok(toast) => Some(toast),
                        Err(RecvTimeoutError::Timeout) => {
                            if registered {
                                let _ = Shell_NotifyIconW(NIM_DELETE, &data);
                                registered = false;
                            }
                            hide_at = None;
                            None
                        }
                        Err(RecvTimeoutError::Disconnected) => break,
                    }
                }
                None => match receiver.recv() {
                    Ok(toast) => Some(toast),
                    Err(_) => break,
                },
            };
            let Some(toast) = next else { continue };
            if !registered {
                data.uFlags = NIF_ICON | NIF_TIP;
                if !Shell_NotifyIconW(NIM_ADD, &data).as_bool() {
                    crate::log("toast: 无法注册通知图标");
                    hide_at = None;
                    continue;
                }
                registered = true;
            }
            set_text(&mut data.szInfoTitle, &toast.title);
            set_text(&mut data.szInfo, &toast.body);
            data.uFlags = NIF_ICON | NIF_TIP | NIF_INFO;
            data.dwInfoFlags = NIIF_INFO;
            let _ = Shell_NotifyIconW(NIM_MODIFY, &data);
            hide_at = Some(Instant::now() + Duration::from_secs(10));
        }

        if registered {
            let _ = Shell_NotifyIconW(NIM_DELETE, &data);
        }
        let _ = DestroyWindow(hwnd);
    }
}

#[cfg(not(windows))]
fn run(receiver: Receiver<Toast>) {
    for _ in receiver {}
}

/// 复制到固定长度的 UTF-16 缓冲区，保底留一个 0 结尾。
#[cfg(windows)]
fn set_text(buffer: &mut [u16], text: &str) {
    buffer.fill(0);
    let limit = buffer.len().saturating_sub(1);
    let mut written = 0;
    for character in text.chars() {
        let mut utf16 = [0u16; 2];
        let encoded = character.encode_utf16(&mut utf16);
        if written + encoded.len() > limit {
            break;
        }
        buffer[written..written + encoded.len()].copy_from_slice(encoded);
        written += encoded.len();
    }
}
