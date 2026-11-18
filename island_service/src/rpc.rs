//! stdio JSON-RPC 2.0 的最小实现：按行收发，只依赖 serde_json。

use serde::Serialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Instant;

pub const API_VERSION: u32 = 1;

/// 一条未读提醒。`id` 是稳定键：任务栏提醒按账号，系统通知按通知编号。
#[derive(Clone, Serialize)]
pub struct UnreadInfo {
    pub id: String,
    pub source: String,
    pub account: u32,
    pub window: i64,
    pub count: u32,
    pub time: String,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contact: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
}

pub struct State {
    started: Instant,
    pub unread: Mutex<HashMap<String, UnreadInfo>>,
    pub listener_ok: Mutex<bool>,
    pub listener_message: Mutex<String>,
    pub notifications_ok: Mutex<bool>,
    pub notifications_message: Mutex<String>,
}

impl Default for State {
    fn default() -> Self {
        Self {
            started: Instant::now(),
            unread: Mutex::new(HashMap::new()),
            listener_ok: Mutex::new(false),
            listener_message: Mutex::new("starting".into()),
            notifications_ok: Mutex::new(false),
            notifications_message: Mutex::new("starting".into()),
        }
    }
}

pub struct RpcError {
    pub code: i64,
    pub message: String,
}

impl RpcError {
    fn new(code: i64, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}

pub enum Action {
    Respond(Value),
    Shutdown(Value),
}

pub fn handle(state: &State, method: &str, params: &Value) -> Result<Action, RpcError> {
    match method {
        "app.hello" => {
            let client_api = params.get("apiVersion").and_then(Value::as_u64).unwrap_or(0);
            if client_api != API_VERSION as u64 {
                return Err(RpcError::new(
                    -32000,
                    format!("apiVersion mismatch: client {client_api}, service {API_VERSION}"),
                ));
            }
            Ok(Action::Respond(json!({
                "version": env!("CARGO_PKG_VERSION"),
                "apiVersion": API_VERSION,
                "capabilities": [
                    "wechat.unread",
                    "qq.unread",
                    "messages.preview",
                    "messages.clear",
                    "messages.list",
                    "messages.open",
                ],
            })))
        }
        "app.ping" => Ok(Action::Respond(json!({
            "pong": true,
            "uptimeMs": state.started.elapsed().as_millis() as u64,
        }))),
        "messages.list" => {
            let mut items: Vec<UnreadInfo> = state
                .unread
                .lock()
                .map(|items| items.values().cloned().collect())
                .unwrap_or_default();
            items.sort_by(|left, right| {
                left.time
                    .cmp(&right.time)
                    .then_with(|| left.id.cmp(&right.id))
            });
            let (ok, message) = listener_status(state);
            let (notifications_ok, notifications_message) = notification_status(state);
            Ok(Action::Respond(json!({
                "items": items,
                "listener": { "ok": ok, "message": message },
                "notifications": { "ok": notifications_ok, "message": notifications_message },
            })))
        }
        "messages.seen" => {
            let id = params.get("id").and_then(Value::as_str);
            let source = params.get("source").and_then(Value::as_str);
            let account = params
                .get("account")
                .and_then(Value::as_u64)
                .map(|value| value as u32)
                .filter(|value| *value != 0);
            let removed = clear_items(state, id, source, account);
            Ok(Action::Respond(json!({ "ok": true, "removed": removed })))
        }
        "messages.open" => open_message(state, params),
        "media.get" => Ok(Action::Respond(json!({
            "title": null,
            "artist": null,
            "position": 0,
            "playing": false,
            "available": false,
        }))),
        "settings.get" => Ok(Action::Respond(json!({}))),
        "settings.set" => Ok(Action::Respond(json!({ "ok": true }))),
        "app.shutdown" => Ok(Action::Shutdown(json!({ "ok": true }))),
        other => Err(RpcError::new(-32601, format!("method not found: {other}"))),
    }
}

fn listener_status(state: &State) -> (bool, String) {
    (
        state.listener_ok.lock().map(|v| *v).unwrap_or(false),
        state
            .listener_message
            .lock()
            .map(|v| v.clone())
            .unwrap_or_default(),
    )
}

fn notification_status(state: &State) -> (bool, String) {
    (
        state
            .notifications_ok
            .lock()
            .map(|v| *v)
            .unwrap_or(false),
        state
            .notifications_message
            .lock()
            .map(|v| v.clone())
            .unwrap_or_default(),
    )
}

#[cfg(windows)]
fn open_message(state: &State, params: &Value) -> Result<Action, RpcError> {
    let id = params.get("id").and_then(Value::as_str);
    let source = params.get("source").and_then(Value::as_str);
    let account = params
        .get("account")
        .and_then(Value::as_u64)
        .map(|value| value as u32);
    let item = {
        let items = match state.unread.lock() {
            Ok(items) => items,
            Err(poisoned) => poisoned.into_inner(),
        };
        match (id, source, account) {
            (Some(id), _, _) => items.get(id).cloned(),
            (None, Some(source), Some(account)) => items
                .values()
                .find(|item| item.source == source && item.account == account)
                .cloned(),
            _ => None,
        }
    };
    let Some(item) = item else {
        return Ok(Action::Respond(
            json!({ "ok": false, "message": "提醒已失效" }),
        ));
    };
    match crate::clients::open_client_at(&item.source, item.account, item.window) {
        Ok(window) => {
            clear_items(state, Some(&item.id), None, None);
            Ok(Action::Respond(json!({ "ok": true, "window": window })))
        }
        Err(message) => Ok(Action::Respond(json!({ "ok": false, "message": message }))),
    }
}

#[cfg(not(windows))]
fn open_message(_: &State, _: &Value) -> Result<Action, RpcError> {
    Ok(Action::Respond(
        json!({ "ok": false, "message": "仅支持 Windows" }),
    ))
}

pub fn response(id: &Value, result: Value) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "result": result })
}

pub fn error(id: &Value, error: RpcError) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": error.code, "message": error.message },
    })
}

pub fn event(params: Value) -> Value {
    json!({ "jsonrpc": "2.0", "method": "event", "params": params })
}

pub fn now_text() -> String {
    chrono::Local::now().format("%H:%M:%S").to_string()
}

pub fn emit_unread(state: &State, item: UnreadInfo) -> Value {
    let mut items = match state.unread.lock() {
        Ok(items) => items,
        Err(poisoned) => poisoned.into_inner(),
    };
    items.insert(item.id.clone(), item.clone());
    drop(items);
    let mut value = serde_json::to_value(&item).unwrap_or(Value::Null);
    if let Value::Object(ref mut object) = value {
        object.insert("type".into(), json!("message.unread"));
    }
    event(value)
}

/// 清除提醒并返回事件。`id` 优先，其次 `source` + `account`，只给 `source` 时清空该来源。
pub fn emit_cleared(
    state: &State,
    id: Option<&str>,
    source: Option<&str>,
    account: Option<u32>,
) -> (Value, usize) {
    let removed = clear_items(state, id, source, account);
    let mut payload = json!({ "type": "message.cleared" });
    if let Some(id) = id {
        payload["id"] = json!(id);
    }
    if let Some(source) = source {
        payload["source"] = json!(source);
    }
    if let Some(account) = account.filter(|value| *value != 0) {
        payload["account"] = json!(account);
    }
    (event(payload), removed)
}

pub fn clear_items(
    state: &State,
    id: Option<&str>,
    source: Option<&str>,
    account: Option<u32>,
) -> usize {
    let mut items = match state.unread.lock() {
        Ok(items) => items,
        Err(poisoned) => poisoned.into_inner(),
    };
    let before = items.len();
    match (id, source, account) {
        (Some(id), _, _) => {
            items.remove(id);
        }
        (None, Some(source), Some(account)) => {
            items.retain(|_, item| !(item.source == source && item.account == account));
        }
        (None, Some(source), None) => {
            items.retain(|_, item| item.source != source);
        }
        (None, None, Some(account)) => {
            items.retain(|_, item| item.account != account);
        }
        (None, None, None) => items.clear(),
    }
    before - items.len()
}

/// 微信同时有任务栏闪动和系统通知时，以能带预览的通知为准，避免出现两条。
pub fn has_toast(state: &State, source: &str) -> bool {
    state
        .unread
        .lock()
        .map(|items| {
            items
                .values()
                .any(|item| item.source == source && item.kind == "toast")
        })
        .unwrap_or(false)
}

pub fn remove_taskbar_items(state: &State, source: &str) -> usize {
    let mut items = match state.unread.lock() {
        Ok(items) => items,
        Err(poisoned) => poisoned.into_inner(),
    };
    let before = items.len();
    items.retain(|_, item| !(item.source == source && item.kind == "taskbar"));
    before - items.len()
}

pub fn emit_status(state: &State, component: &str, ok: bool, message: &str) -> Value {
    if component == "notifications" {
        if let Ok(mut value) = state.notifications_ok.lock() {
            *value = ok;
        }
        if let Ok(mut value) = state.notifications_message.lock() {
            *value = message.to_string();
        }
    } else {
        if let Ok(mut value) = state.listener_ok.lock() {
            *value = ok;
        }
        if let Ok(mut value) = state.listener_message.lock() {
            *value = message.to_string();
        }
    }
    event(json!({
        "type": "system.status",
        "component": component,
        "ok": ok,
        "message": message,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str, source: &str, account: u32, kind: &str) -> UnreadInfo {
        UnreadInfo {
            id: id.into(),
            source: source.into(),
            account,
            window: 0,
            count: 1,
            time: "12:00:00".into(),
            kind: kind.into(),
            contact: None,
            preview: None,
        }
    }

    fn state() -> State {
        let state = State::default();
        let mut items = state.unread.lock().unwrap();
        items.insert(
            "wechat:flash:100".into(),
            item("wechat:flash:100", "wechat", 100, "taskbar"),
        );
        items.insert(
            "wechat:n1".into(),
            item("wechat:n1", "wechat", 0, "toast"),
        );
        items.insert("qq:n2".into(), item("qq:n2", "qq", 0, "toast"));
        drop(items);
        state
    }

    #[test]
    fn clearing_prefers_item_then_source_then_account() {
        let state = state();
        assert_eq!(clear_items(&state, Some("qq:n2"), None, None), 1);
        assert!(!state.unread.lock().unwrap().contains_key("qq:n2"));

        assert_eq!(clear_items(&state, None, Some("wechat"), None), 2);
        assert!(state.unread.lock().unwrap().is_empty());

        let state = self::state();
        assert_eq!(clear_items(&state, None, None, Some(100)), 1);
        assert_eq!(state.unread.lock().unwrap().len(), 2);

        assert_eq!(clear_items(&state, None, None, None), 2);
        assert!(state.unread.lock().unwrap().is_empty());
    }

    #[test]
    fn toast_items_replace_taskbar_items_and_all_seen_clears_everything() {
        let state = state();
        assert!(has_toast(&state, "wechat"));
        assert!(has_toast(&state, "qq"));
        assert_eq!(remove_taskbar_items(&state, "wechat"), 1);
        assert_eq!(state.unread.lock().unwrap().len(), 2);
        assert!(has_toast(&state, "wechat"));
        assert_eq!(clear_items(&state, None, None, None), 2);
    }
}
