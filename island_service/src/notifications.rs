//! 读取 Windows 通知中心里微信 / QQ 的系统通知，提取联系人与消息预览。
//!
//! 只读通知，不碰客户端进程；通知从通知中心消失（用户划掉或点开）时同步清除提醒。

use std::collections::HashMap;
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::Duration;

use serde_json::Value;
use windows::core::HSTRING;
use windows::Foundation::Collections::IVectorView;
use windows::UI::Notifications::Management::{
    UserNotificationListener, UserNotificationListenerAccessStatus,
};
use windows::UI::Notifications::{AdaptiveNotificationText, NotificationKinds, UserNotification};
use windows::Win32::System::WinRT::{RoInitialize, RoUninitialize, RO_INIT_MULTITHREADED};

use crate::rpc::{self, State};

const POLL_INTERVAL: Duration = Duration::from_secs(1);
const MAX_TEXT_CHARS: usize = 200;

#[derive(Clone, PartialEq, Eq)]
struct Tracked {
    created: i64,
    source: &'static str,
    contact: Option<String>,
    preview: Option<String>,
    count: u32,
}

pub fn start(state: Arc<State>, tx: Sender<Value>) -> Result<(), String> {
    std::thread::Builder::new()
        .name("notifications".into())
        .spawn(move || {
            if let Err(error) = run(&state, &tx) {
                let message = format!("系统通知读取失败：{}", error.code());
                let _ = tx.send(rpc::emit_status(&state, "notifications", false, &message));
            }
        })
        .map_err(|error| format!("无法启动通知监听线程：{error}"))?;
    Ok(())
}

fn run(state: &State, tx: &Sender<Value>) -> windows::core::Result<()> {
    unsafe {
        RoInitialize(RO_INIT_MULTITHREADED)?;
    }
    struct Apartment;
    impl Drop for Apartment {
        fn drop(&mut self) {
            unsafe { RoUninitialize() }
        }
    }
    let _apartment = Apartment;

    let listener = UserNotificationListener::Current()?;
    let access = listener.RequestAccessAsync()?.get()?;
    if access != UserNotificationListenerAccessStatus::Allowed {
        let message = match access {
            UserNotificationListenerAccessStatus::Denied => {
                "Windows 未授予通知读取权限，请在系统设置中允许后重新启动 Guduo"
            }
            _ => "通知读取权限尚未授予，请重新打开 Guduo 并允许读取通知",
        };
        let _ = tx.send(rpc::emit_status(state, "notifications", false, message));
        return Ok(());
    }
    let _ = tx.send(rpc::emit_status(
        state,
        "notifications",
        true,
        "微信 / QQ 系统通知监听中",
    ));

    let mut previous: HashMap<u32, Tracked> = HashMap::new();
    let mut primed = false;
    // 启动时补报最近 5 分钟内的未读通知，避免应用关闭期间到达的消息被漏掉。
    let recent_cutoff = now_filetime() - 5 * 60 * 10_000_000;

    loop {
        if listener.GetAccessStatus()? != UserNotificationListenerAccessStatus::Allowed {
            let _ = tx.send(rpc::emit_status(
                state,
                "notifications",
                false,
                "通知读取权限已被关闭",
            ));
            return Ok(());
        }
        let notifications = listener
            .GetNotificationsAsync(NotificationKinds::Toast)?
            .get()?;
        let count = notifications.Size()?;
        let mut current: HashMap<u32, Tracked> = HashMap::new();
        let mut events = Vec::new();
        let mut complete = true;
        let foreground = crate::clients::foreground_client().map(|(source, _)| source);

        for index in 0..count {
            let Ok(notification) = notifications.GetAt(index) else {
                complete = false;
                continue;
            };
            let (Ok(number), Ok(created)) = (notification.Id(), notification.CreationTime()) else {
                complete = false;
                continue;
            };
            let Some(source) = source_of(&notification) else {
                continue;
            };
            let (contact, preview) = toast_text(&notification);
            let created = created.UniversalTime;
            let (changed, count) = match previous.get(&number) {
                Some(old) => {
                    let changed =
                        old.created != created || old.contact != contact || old.preview != preview;
                    (changed, if changed { old.count + 1 } else { old.count })
                }
                None => (true, 1),
            };
            // 客户端已经在前台时，用户正在看消息，不再提醒。
            let emit = if primed {
                changed
            } else {
                created > recent_cutoff
            };
            if emit && foreground != Some(source) {
                // 微信同时闪任务栏和发通知时，用带预览的通知替换任务栏提醒。
                rpc::remove_taskbar_items(state, source);
                let item = rpc::UnreadInfo {
                    id: format!("{source}:n{number}"),
                    source: source.into(),
                    account: 0,
                    window: crate::clients::preferred_window(source),
                    count,
                    time: rpc::now_text(),
                    kind: "toast".into(),
                    contact: contact.clone(),
                    preview: preview.clone(),
                };
                events.push(rpc::emit_unread(state, item));
            }
            current.insert(
                number,
                Tracked {
                    created,
                    source,
                    contact,
                    preview,
                    count,
                },
            );
        }

        if primed && complete {
            for (number, tracked) in &previous {
                if !current.contains_key(number) {
                    let id = format!("{}:n{number}", tracked.source);
                    let (event, _) = rpc::emit_cleared(state, Some(&id), None, None);
                    events.push(event);
                }
            }
        }

        previous = current;
        primed |= complete;
        for event in events {
            let _ = tx.send(event);
        }
        std::thread::sleep(POLL_INTERVAL);
    }
}

fn now_filetime() -> i64 {
    let elapsed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    ((elapsed.as_secs() as i128 + 11_644_473_600i128) * 10_000_000
        + (elapsed.subsec_nanos() as i128 / 100)) as i64
}

fn source_of(notification: &UserNotification) -> Option<&'static str> {    let info = notification.AppInfo().ok()?;
    let aumid = info
        .AppUserModelId()
        .map(|value| value.to_string())
        .unwrap_or_default();
    let display = info
        .DisplayInfo()
        .ok()
        .and_then(|info| info.DisplayName().ok())
        .map(|value| value.to_string())
        .unwrap_or_default();
    source_from(&aumid, &display)
}

fn source_from(aumid: &str, display: &str) -> Option<&'static str> {
    let id = aumid.trim().to_ascii_lowercase();
    if id == "wechat"
        || id == "weixin"
        || id.starts_with("tencent.wechat")
        || id.starts_with("tencent.weixin")
    {
        return Some("wechat");
    }
    if id == "qq" || id == "tencent.qq" {
        return Some("qq");
    }
    let name = display.trim().to_ascii_lowercase();
    match name.as_str() {
        "微信" | "wechat" | "weixin" => Some("wechat"),
        "qq" => Some("qq"),
        _ => None,
    }
}

/// Toast 的第 1 段是联系人 / 群名，其余是消息预览。
fn toast_text(notification: &UserNotification) -> (Option<String>, Option<String>) {
    let Some(texts) = toast_text_elements(notification) else {
        return (None, None);
    };
    let mut parts = Vec::new();
    for index in 0..texts.Size().unwrap_or(0).min(8) {
        let Ok(text) = texts.GetAt(index) else {
            continue;
        };
        let Ok(text) = text.Text() else {
            continue;
        };
        let text: String = text.to_string().trim().chars().take(MAX_TEXT_CHARS).collect();
        if !text.is_empty() {
            parts.push(text);
        }
    }
    let contact = parts.first().cloned();
    let preview = (parts.len() > 1).then(|| parts[1..].join(" "));
    (contact, preview)
}

fn toast_text_elements(
    notification: &UserNotification,
) -> Option<IVectorView<AdaptiveNotificationText>> {
    let visual = notification.Notification().ok()?.Visual().ok()?;
    for template in ["ToastGeneric", "Toast"] {
        if let Ok(binding) = visual.GetBinding(&HSTRING::from(template)) {
            if let Ok(texts) = binding.GetTextElements() {
                return Some(texts);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_identity_maps_only_wechat_and_qq() {
        assert_eq!(source_from("Weixin", ""), Some("wechat"));
        assert_eq!(source_from("Tencent.WeChat", ""), Some("wechat"));
        assert_eq!(source_from("", "微信"), Some("wechat"));
        assert_eq!(source_from("QQ", ""), Some("qq"));
        assert_eq!(source_from("", "QQ"), Some("qq"));
        assert_eq!(source_from("Tencent.QQMusic", "QQ音乐"), None);
        assert_eq!(source_from("QQMusic", ""), None);
        assert_eq!(source_from("Unknown", "微信助手"), None);
    }

    /// 只打印应用标识和是否存在正文，不输出通知内容。
    #[test]
    #[ignore = "需要本机通知中心里有微信或 QQ 的通知"]
    fn live_notifications_are_readable() {
        let initialized = unsafe { RoInitialize(RO_INIT_MULTITHREADED) }.is_ok();
        let listener = UserNotificationListener::Current().unwrap();
        let request = listener.RequestAccessAsync().unwrap().get().unwrap();
        assert_eq!(request, UserNotificationListenerAccessStatus::Allowed);
        let items = listener
            .GetNotificationsAsync(NotificationKinds::Toast)
            .unwrap()
            .get()
            .unwrap();
        println!("toast count = {}", items.Size().unwrap());
        for index in 0..items.Size().unwrap() {
            let notification = items.GetAt(index).unwrap();
            let info = notification.AppInfo().ok();
            let aumid = info
                .as_ref()
                .and_then(|info| info.AppUserModelId().ok())
                .map(|value| value.to_string())
                .unwrap_or_default();
            let display = info
                .as_ref()
                .and_then(|info| info.DisplayInfo().ok())
                .and_then(|info| info.DisplayName().ok())
                .map(|value| value.to_string())
                .unwrap_or_default();
            let (contact, preview) = toast_text(&notification);
            let source = source_from(&aumid, &display);
            let created = notification
                .CreationTime()
                .map(|time| time.UniversalTime)
                .unwrap_or_default();
            println!(
                "#{} created={created} app={aumid:?} display={display:?} mapped={:?} contact={} preview={}",
                notification.Id().unwrap(),
                source,
                contact.is_some(),
                preview.is_some()
            );
            if source.is_some() {
                println!(
                    "   contact=({}) preview=({})",
                    contact.unwrap_or_default(),
                    preview.unwrap_or_default()
                );
            }
        }
        if initialized {
            unsafe { RoUninitialize() }
        }
    }
}
