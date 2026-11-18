//! 微信 4.x 缩在托盘时的唤起。
//!
//! 参考岛仔 `wechat.rs` 的做法：不 ShowWindow / 不 SC_RESTORE / 不启动新实例，
//! 而是通过 UI Automation 按下微信自己的托盘按钮。图标在折叠区时，先展开折叠区
//! 再按，因此托盘被收起也能唤起主窗口。

use std::time::{Duration, Instant};

use windows::{
    core::{w, PCWSTR},
    Win32::{
        Foundation::{BOOL, HWND, LPARAM, RECT},
        System::Com::{
            CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED,
        },
        UI::{
            Accessibility::{
                CUIAutomation8, IUIAutomation, IUIAutomationElement,
                IUIAutomationInvokePattern, UIA_ButtonControlTypeId, UIA_InvokePatternId,
                TreeScope_Descendants,
            },
            HiDpi::{SetThreadDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2},
            Shell::{Shell_NotifyIconGetRect, NOTIFYICONIDENTIFIER},
            WindowsAndMessaging::{
                EnumWindows, FindWindowExW, FindWindowW, GetClassNameW, GetWindowThreadProcessId,
                IsWindowVisible,
            },
        },
    },
};

use crate::clients;

pub fn click(account: u32) -> Option<HWND> {
    unsafe {
        let _ = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        let hosts = tray_hosts(account);
        let icon = hosts.iter().find_map(|(pid, host)| {
            let icons = host_icons(*host, *pid);
            match icons.as_slice() {
                [one] => Some(*one),
                _ => None,
            }
        })?;
        let (host, id) = icon;
        let icon_rect = tray_rect(host, id)?;
        let ui: IUIAutomation =
            CoCreateInstance(&CUIAutomation8, None, CLSCTX_INPROC_SERVER).ok()?;
        let all = ui.CreateTrueCondition().ok()?;
        let button_at = |window: HWND, icon: RECT| -> Option<IUIAutomationElement> {
            let items = ui
                .ElementFromHandle(window)
                .ok()?
                .FindAll(TreeScope_Descendants, &all)
                .ok()?;
            let mut best: Option<(i64, IUIAutomationElement)> = None;
            for index in 0..items.Length().unwrap_or(0) {
                let Ok(item) = items.GetElement(index) else {
                    continue;
                };
                if !item.CurrentIsEnabled().is_ok_and(|value| value.as_bool())
                    || !item.CurrentIsOffscreen().is_ok_and(|value| !value.as_bool())
                {
                    continue;
                }
                let Ok(rect) = item.CurrentBoundingRectangle() else {
                    continue;
                };
                if !button_sized(icon, rect) {
                    continue;
                }
                if item
                    .GetCurrentPatternAs::<IUIAutomationInvokePattern>(UIA_InvokePatternId)
                    .is_err()
                {
                    continue;
                }
                let area = i64::from(rect.right - rect.left) * i64::from(rect.bottom - rect.top);
                if best.as_ref().is_none_or(|(old, _)| area < *old) {
                    best = Some((area, item));
                }
            }
            best.map(|(_, item)| item)
        };
        let invoke = |element: &IUIAutomationElement| -> bool {
            element
                .GetCurrentPatternAs::<IUIAutomationInvokePattern>(UIA_InvokePatternId)
                .and_then(|pattern| pattern.Invoke())
                .is_ok()
        };
        let overflow_open = || {
            [w!("TopLevelWindowForOverflowXamlIsland"), w!("NotifyIconOverflowWindow")]
                .into_iter()
                .find_map(|class| {
                    FindWindowW(class, PCWSTR::null())
                        .ok()
                        .filter(|window| IsWindowVisible(*window).as_bool())
                })
        };
        if let Some(overflow) = overflow_open() {
            if let Some(button) = button_at(overflow, icon_rect) {
                if invoke(&button) {
                    return wait_visible(account);
                }
            }
        }
        let taskbar = FindWindowW(w!("Shell_TrayWnd"), PCWSTR::null()).ok()?;
        if let Some(button) = button_at(taskbar, icon_rect) {
            if invoke(&button) {
                std::thread::sleep(Duration::from_millis(250));
                if let Some(overflow) = overflow_open() {
                    if let Some(inner) = button_at(overflow, tray_rect(host, id)?) {
                        let _ = invoke(&inner);
                    }
                }
                return wait_visible(account);
            }
        }
        let chevron = tray_overflow_button(&ui, taskbar)?;
        if !invoke(&chevron) {
            return None;
        }
        let started = Instant::now();
        while started.elapsed() < Duration::from_millis(1500) {
            std::thread::sleep(Duration::from_millis(80));
            let Some(overflow) = overflow_open() else {
                continue;
            };
            let rect = tray_rect(host, id).unwrap_or(icon_rect);
            if let Some(button) = button_at(overflow, rect) {
                if invoke(&button) {
                    return wait_visible(account);
                }
            }
        }
        None
    }
}

fn wait_visible(account: u32) -> Option<HWND> {
    let until = Instant::now() + Duration::from_secs(2);
    while Instant::now() < until {
        if let Some(window) = clients::visible_main_window("wechat", account) {
            return Some(window);
        }
        std::thread::sleep(Duration::from_millis(80));
    }
    None
}

fn tray_hosts(account: u32) -> Vec<(u32, HWND)> {
    struct Search {
        account: u32,
        hosts: Vec<(u32, HWND)>,
    }
    unsafe extern "system" fn visit(hwnd: HWND, data: LPARAM) -> BOOL {
        let search = &mut *(data.0 as *mut Search);
        if !class_name(hwnd).contains("TrayIcon") {
            return true.into();
        }
        let pid = window_pid(hwnd);
        if !clients::process_matches("wechat", pid) {
            return true.into();
        }
        if search.account == 0 || search.account == pid {
            search.hosts.push((pid, hwnd));
        }
        true.into()
    }
    let mut search = Search {
        account,
        hosts: Vec::new(),
    };
    unsafe {
        let _ = EnumWindows(
            Some(visit),
            LPARAM((&mut search as *mut Search) as isize),
        );
    }
    search.hosts
}

fn host_icons(host: HWND, _pid: u32) -> Vec<(HWND, u32)> {
    (0..=256u32)
        .filter_map(|id| tray_rect(host, id).map(|_| (host, id)))
        .collect()
}

pub(crate) fn tray_rect(host: HWND, id: u32) -> Option<RECT> {
    unsafe {
        let icon = NOTIFYICONIDENTIFIER {
            cbSize: std::mem::size_of::<NOTIFYICONIDENTIFIER>() as u32,
            hWnd: host,
            uID: id,
            ..Default::default()
        };
        Shell_NotifyIconGetRect(&icon).ok()
    }
}

fn button_sized(icon: RECT, button: RECT) -> bool {
    let (width, height) = (
        (icon.right - icon.left).max(16),
        (icon.bottom - icon.top).max(16),
    );
    let (center_x, center_y) = ((icon.left + icon.right) / 2, (icon.top + icon.bottom) / 2);
    button.right > button.left
        && button.bottom > button.top
        && center_x >= button.left
        && center_x < button.right
        && center_y >= button.top
        && center_y < button.bottom
        && button.right - button.left <= width * 3
        && button.bottom - button.top <= height * 3
}

unsafe fn tray_overflow_button(
    ui: &IUIAutomation,
    taskbar: HWND,
) -> Option<IUIAutomationElement> {
    let usable = |item: &IUIAutomationElement| {
        item.CurrentIsEnabled().is_ok_and(|value| value.as_bool())
            && item
                .CurrentIsOffscreen()
                .is_ok_and(|value| !value.as_bool())
            && item.CurrentBoundingRectangle().is_ok_and(|rect| {
                rect.right > rect.left
                    && rect.bottom > rect.top
                    && rect.right - rect.left <= 200
                    && rect.bottom - rect.top <= 200
            })
            && item
                .GetCurrentPatternAs::<IUIAutomationInvokePattern>(UIA_InvokePatternId)
                .is_ok()
    };
    let legacy = FindWindowExW(taskbar, None, w!("TrayNotifyWnd"), PCWSTR::null())
        .ok()
        .and_then(|tray| FindWindowExW(tray, None, w!("Button"), PCWSTR::null()).ok())
        .and_then(|button| ui.ElementFromHandle(button).ok());
    if let Some(button) = legacy.filter(usable) {
        return Some(button);
    }
    let items = ui
        .ElementFromHandle(taskbar)
        .ok()?
        .FindAll(TreeScope_Descendants, &ui.CreateTrueCondition().ok()?)
        .ok()?;
    let mut found = None;
    for index in 0..items.Length().ok()? {
        let Ok(item) = items.GetElement(index) else {
            continue;
        };
        if item.CurrentControlType().ok() != Some(UIA_ButtonControlTypeId) {
            continue;
        }
        let name = item
            .CurrentName()
            .ok()
            .map(|name| name.to_string().trim().to_ascii_lowercase())
            .unwrap_or_default();
        if !matches!(
            name.as_str(),
            "显示隐藏的图标" | "顯示隱藏的圖示" | "show hidden icons"
        ) {
            continue;
        }
        if !usable(&item) {
            continue;
        }
        if let Some(previous) = &found {
            if !ui.CompareElements(previous, &item).ok()?.as_bool() {
                return None;
            }
        }
        found = Some(item);
    }
    found
}

fn class_name(hwnd: HWND) -> String {
    let mut buffer = [0u16; 256];
    let length = unsafe { GetClassNameW(hwnd, &mut buffer) };
    String::from_utf16_lossy(&buffer[..length.max(0) as usize])
}

fn window_pid(hwnd: HWND) -> u32 {
    let mut pid = 0;
    unsafe {
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
    }
    pid
}
