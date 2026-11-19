//! 输入法中英文切换监听。
//!
//! 轮询前台焦点控件的键盘布局与 IME 转换模式，模式变化时推送 `ime.changed`。
//! 输入法窗口属于前台线程，转换模式通过带超时的 `WM_IME_CONTROL` 读取，
//! 避免跨进程取输入上下文失败。这里只读取状态，不安装键鼠钩子。

use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::Duration;

use serde_json::{json, Value};
use windows::Win32::Foundation::{GetLastError, SetLastError, ERROR_SUCCESS, HWND, LPARAM, WPARAM};
use windows::Win32::UI::Input::Ime::ImmGetDefaultIMEWnd;
use windows::Win32::UI::Input::KeyboardAndMouse::GetKeyboardLayout;
use windows::Win32::UI::WindowsAndMessaging::{
    GetForegroundWindow, GetGUIThreadInfo, GetWindowThreadProcessId, SendMessageTimeoutW,
    GUITHREADINFO, SMTO_ABORTIFHUNG, SMTO_ERRORONEXIT, WM_IME_CONTROL,
};

use crate::rpc;

/// 中英文切换要即时反馈，250ms 的轮询足以跟上快捷键。
const POLL_INTERVAL: Duration = Duration::from_millis(250);

const IMC_GETCONVERSIONMODE: usize = 0x0001;
const IMC_GETOPENSTATUS: usize = 0x0005;

/// 键盘布局低 10 位是主语言 ID。
const LANG_CHINESE: u16 = 0x0004;

/// 一次采样：前台窗口与焦点控件用于区分“切换输入法”和“切换窗口”。
#[derive(Clone, Copy, PartialEq, Eq)]
struct Sample {
    context: (usize, usize),
    mode: &'static str,
}

pub fn start(state: Arc<rpc::State>, tx: Sender<Value>) {
    let _ = std::thread::Builder::new()
        .name("ime-watcher".into())
        .spawn(move || {
            let mut last: Option<Sample> = None;
            loop {
                if let Some(current) = read_sample() {
                    let mode_changed = last.is_some_and(|previous| previous.mode != current.mode);
                    let context_changed =
                        last.is_some_and(|previous| previous.context != current.context);
                    // 首次采样只写入缓存，让 `ime.get` 能立即返回当前模式。
                    if last.is_none() || mode_changed {
                        set_cached_mode(&state, current.mode);
                    }
                    if mode_changed && last.is_some() {
                        // 换窗口或换焦点只同步状态，不提示输入法切换。
                        let _ = tx.send(rpc::event(json!({
                            "type": "ime.changed",
                            "mode": current.mode,
                            "banner": !context_changed,
                        })));
                    }
                    last = Some(current);
                }
                std::thread::sleep(POLL_INTERVAL);
            }
        });
}

/// 按需读取当前输入法模式，供客户端在连接后初始化常驻标识。
pub fn current_mode() -> Option<&'static str> {
    read_sample().map(|sample| sample.mode)
}

fn set_cached_mode(state: &rpc::State, mode: &'static str) {
    if let Ok(mut value) = state.ime.lock() {
        *value = Some(mode);
    }
}

fn read_sample() -> Option<Sample> {
    unsafe {
        let foreground = GetForegroundWindow();
        if foreground.0.is_null() {
            return None;
        }
        let thread = GetWindowThreadProcessId(foreground, None);
        let mut info = GUITHREADINFO {
            cbSize: std::mem::size_of::<GUITHREADINFO>() as u32,
            ..Default::default()
        };
        let focus = if GetGUIThreadInfo(thread, &mut info).is_ok() && !info.hwndFocus.0.is_null() {
            info.hwndFocus
        } else {
            foreground
        };
        let layout = GetKeyboardLayout(GetWindowThreadProcessId(focus, None)).0 as usize;
        let language = layout as u16 & 0x03FF;
        let native = if language == LANG_CHINESE {
            native_mode(focus)
        } else {
            None
        };
        // 查询期间前台已经切走，样本作废，避免把新模式记到旧窗口上。
        if GetForegroundWindow() != foreground {
            return None;
        }
        Some(Sample {
            context: (foreground.0 as usize, focus.0 as usize),
            mode: mode_label(language, native),
        })
    }
}

/// `native` 为 IME 的中文（本地语言）模式；读取失败时保持中文布局的默认判断。
fn mode_label(language: u16, native: Option<bool>) -> &'static str {
    if language != LANG_CHINESE {
        return "en";
    }
    match native {
        Some(false) => "en",
        _ => "zh",
    }
}

fn native_mode(focus: HWND) -> Option<bool> {
    unsafe {
        let ime = ImmGetDefaultIMEWnd(focus);
        if ime.0.is_null() {
            return None;
        }
        // IME 关闭时直接是英文；个别输入法不响应 OPENSTATUS，再查转换模式。
        if let Some(open) = query_ime(ime, IMC_GETOPENSTATUS) {
            if open == 0 {
                return Some(false);
            }
        }
        query_ime(ime, IMC_GETCONVERSIONMODE).map(|mode| mode & 1 != 0)
    }
}

fn query_ime(window: HWND, command: usize) -> Option<usize> {
    let mut result = 0usize;
    let _ = unsafe { SetLastError(ERROR_SUCCESS) };
    let ok = unsafe {
        SendMessageTimeoutW(
            window,
            WM_IME_CONTROL,
            WPARAM(command),
            LPARAM(0),
            SMTO_ABORTIFHUNG | SMTO_ERRORONEXIT,
            40,
            Some(&mut result),
        )
    };
    if ok.0 != 0 {
        return Some(result);
    }
    // 消息结果本身可能为 0，用 LastError 区分合法零值和超时。
    (unsafe { GetLastError() } == ERROR_SUCCESS).then_some(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chinese_layout_uses_ime_conversion_mode() {
        assert_eq!(mode_label(LANG_CHINESE, Some(true)), "zh");
        assert_eq!(mode_label(LANG_CHINESE, Some(false)), "en");
        assert_eq!(mode_label(LANG_CHINESE, None), "zh");
    }

    #[test]
    fn non_chinese_layout_is_english() {
        assert_eq!(mode_label(0x0009, Some(true)), "en");
    }

    #[test]
    #[ignore = "读取当前前台窗口的输入法状态，不发送按键"]
    fn live_reads_ime_state() {
        for _ in 0..8 {
            match read_sample() {
                Some(sample) => println!("ime context={:?} mode={}", sample.context, sample.mode),
                None => println!("ime sample unavailable"),
            }
            std::thread::sleep(POLL_INTERVAL);
        }
    }
}
