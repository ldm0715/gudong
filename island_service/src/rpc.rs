//! stdio JSON-RPC 2.0 的最小实现：按行收发，只依赖 serde_json。

use serde::Serialize;
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Instant;

pub const API_VERSION: u32 = 1;

pub const ERR_PARSE: i64 = -32700;
pub const ERR_INVALID_REQUEST: i64 = -32600;
pub const ERR_METHOD_NOT_FOUND: i64 = -32601;
pub const ERR_INVALID_PARAMS: i64 = -32602;
pub const ERR_INTERNAL: i64 = -32603;
pub const ERR_VERSION_MISMATCH: i64 = -32000;

/// 能力声明的唯一来源，`service.ready` 事件与 `app.hello` 都读这里。
pub const CAPABILITIES: &[&str] = &[
    "wechat.unread",
    "qq.unread",
    "messages.preview",
    "messages.clear",
    "messages.list",
    "messages.open",
    "media.current",
    "media.control",
    "media.lyrics",
    "weather.current",
    "weather.search",
    "ime.status",
    "translate.text",
    "translate.models",
    "system.openUrl",
    "settings.persist",
    "mail.accounts",
    "mail.list",
    "mail.read",
    "mail.markSeen",
    "quota.get",
    "quota.refresh",
    "quota.setSecret",
    "schedule.list",
    "schedule.add",
    "schedule.update",
    "schedule.remove",
    "schedule.clearExpired",
    "anniversary.list",
    "anniversary.add",
    "anniversary.update",
    "anniversary.remove",
];

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
    pub media: Mutex<Option<crate::media::MediaSnapshot>>,
    pub lyrics: Mutex<Option<crate::lyrics::LyricsSnapshot>>,
    pub lyrics_pending: Mutex<bool>,
    pub lyrics_sequence: Mutex<u64>,
    pub weather: Mutex<Option<crate::weather::WeatherSnapshot>>,
    pub weather_status: Mutex<String>,
    /// 天气刷新与搜索命令队列。
    pub weather_tx: Mutex<Option<std::sync::mpsc::Sender<crate::weather::Command>>>,
    /// 最近一次读到的输入法模式：`zh` / `en`，采样前为 `None`。
    pub ime: Mutex<Option<&'static str>>,
    pub config: crate::config::Config,
    /// 翻译任务队列。网络请求在线程里跑，主循环只负责入队。
    pub translate_tx: Mutex<Option<std::sync::mpsc::Sender<crate::translate::Job>>>,
    /// 邮件任务队列。账号同步与缓存都在独立线程维护。
    pub mail_tx: Mutex<Option<std::sync::mpsc::Sender<crate::mail::Job>>>,
    /// 最近一次额度快照，顺序与 `quotaOrder` 一致。
    pub quota: Mutex<Vec<crate::quota::QuotaProvider>>,
    /// 额度刷新命令队列。
    pub quota_tx: Mutex<Option<std::sync::mpsc::Sender<crate::quota::Command>>>,
    /// 日程读写与到点检查队列。
    pub schedule_tx: Mutex<Option<std::sync::mpsc::Sender<crate::schedule::Command>>>,
    /// 倒计时与纪念日读写队列。
    pub anniversary_tx: Mutex<Option<std::sync::mpsc::Sender<crate::anniversary::Command>>>,
}

impl Default for State {
    fn default() -> Self {
        Self::with_config(crate::config::Config::in_memory())
    }
}

impl State {
    pub fn with_config(config: crate::config::Config) -> Self {
        Self {
            started: Instant::now(),
            unread: Mutex::new(HashMap::new()),
            listener_ok: Mutex::new(false),
            listener_message: Mutex::new("starting".into()),
            notifications_ok: Mutex::new(false),
            notifications_message: Mutex::new("starting".into()),
            media: Mutex::new(None),
            lyrics: Mutex::new(None),
            lyrics_pending: Mutex::new(false),
            lyrics_sequence: Mutex::new(0),
            weather: Mutex::new(None),
            weather_status: Mutex::new("正在获取天气".into()),
            weather_tx: Mutex::new(None),
            ime: Mutex::new(None),
            config,
            translate_tx: Mutex::new(None),
            mail_tx: Mutex::new(None),
            quota: Mutex::new(Vec::new()),
            quota_tx: Mutex::new(None),
            schedule_tx: Mutex::new(None),
            anniversary_tx: Mutex::new(None),
        }
    }

    pub fn set_translate_sender(&self, sender: std::sync::mpsc::Sender<crate::translate::Job>) {
        if let Ok(mut slot) = self.translate_tx.lock() {
            *slot = Some(sender);
        }
    }

    pub fn set_mail_sender(&self, sender: std::sync::mpsc::Sender<crate::mail::Job>) {
        if let Ok(mut slot) = self.mail_tx.lock() {
            *slot = Some(sender);
        }
    }

    pub fn set_weather_sender(&self, sender: std::sync::mpsc::Sender<crate::weather::Command>) {
        if let Ok(mut slot) = self.weather_tx.lock() {
            *slot = Some(sender);
        }
    }

    pub fn set_quota_sender(&self, sender: std::sync::mpsc::Sender<crate::quota::Command>) {
        if let Ok(mut slot) = self.quota_tx.lock() {
            *slot = Some(sender);
        }
    }

    pub fn set_schedule_sender(
        &self,
        sender: std::sync::mpsc::Sender<crate::schedule::Command>,
    ) {
        if let Ok(mut slot) = self.schedule_tx.lock() {
            *slot = Some(sender);
        }
    }

    pub fn set_anniversary_sender(
        &self,
        sender: std::sync::mpsc::Sender<crate::anniversary::Command>,
    ) {
        if let Ok(mut slot) = self.anniversary_tx.lock() {
            *slot = Some(sender);
        }
    }
}

#[derive(Debug)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
}

impl RpcError {
    pub fn new(code: i64, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}

pub enum Action {
    Respond(Value),
    Shutdown(Value),
    /// 请求已交给后台线程，稍后通过同一 id 单独写回响应。
    Pending,
}

pub fn handle(
    state: &State,
    id: &Value,
    method: &str,
    params: &Value,
) -> Result<Action, RpcError> {
    match method {
        "app.hello" => {
            let client_api = params.get("apiVersion").and_then(Value::as_u64).unwrap_or(0);
            if client_api != API_VERSION as u64 {
                return Err(RpcError::new(
                    ERR_VERSION_MISMATCH,
                    format!("apiVersion mismatch: client {client_api}, service {API_VERSION}"),
                ));
            }
            Ok(Action::Respond(json!({
                "version": env!("CARGO_PKG_VERSION"),
                "apiVersion": API_VERSION,
                "capabilities": CAPABILITIES,
            })))
        }
        "app.ping" => Ok(Action::Respond(json!({
            "pong": true,
            "uptimeMs": state.started.elapsed().as_millis() as u64,
        }))),
        "app.openUrl" => {
            let url = params
                .get("url")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .trim();
            if !(url.starts_with("https://") || url.starts_with("http://")) {
                return Err(RpcError::new(
                    ERR_INVALID_PARAMS,
                    "url must start with http:// or https://",
                ));
            }
            match crate::shell::open_url(url) {
                Ok(()) => Ok(Action::Respond(json!({ "ok": true }))),
                Err(message) => Err(RpcError::new(ERR_INTERNAL, message)),
            }
        }
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
        "media.get" => {
            let media = state
                .media
                .lock()
                .ok()
                .and_then(|slot| slot.clone())
                .unwrap_or_default();
            Ok(Action::Respond(json!({ "media": media })))
        }
        "media.control" => media_control(params),
        "lyrics.get" => {
            let lyrics = state
                .lyrics
                .lock()
                .ok()
                .and_then(|slot| slot.clone());
            let pending = state
                .lyrics_pending
                .lock()
                .map(|value| *value)
                .unwrap_or(false);
            Ok(Action::Respond(json!({
                "lyrics": lyrics,
                "pending": pending,
            })))
        }
        "ime.get" => {
            let cached = state.ime.lock().map(|value| *value).unwrap_or(None);
            #[cfg(windows)]
            let mode = cached.or_else(crate::ime::current_mode);
            #[cfg(not(windows))]
            let mode = cached;
            Ok(Action::Respond(json!({ "mode": mode })))
        }
        "weather.get" => {
            let snapshot = state
                .weather
                .lock()
                .ok()
                .and_then(|slot| slot.clone());
            let status = state
                .weather_status
                .lock()
                .map(|value| value.clone())
                .unwrap_or_default();
            Ok(Action::Respond(json!({
                "snapshot": snapshot,
                "status": status,
            })))
        }
        "weather.search" => {
            let query = params
                .get("query")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .trim();
            if query.is_empty() || query.chars().count() > 80 {
                return Err(RpcError::new(
                    ERR_INVALID_PARAMS,
                    "weather.search requires a query of 1-80 characters",
                ));
            }
            let sender = state
                .weather_tx
                .lock()
                .ok()
                .and_then(|slot| slot.clone());
            let Some(sender) = sender else {
                return Err(RpcError::new(ERR_INTERNAL, "weather worker is not running"));
            };
            sender
                .send(crate::weather::Command::Search {
                    id: id.clone(),
                    query: query.to_string(),
                })
                .map_err(|_| RpcError::new(ERR_INTERNAL, "weather worker stopped"))?;
            Ok(Action::Pending)
        }
        "translate.run" | "translate.models" | "translate.setSecret" => {
            let sender = state
                .translate_tx
                .lock()
                .ok()
                .and_then(|slot| slot.clone());
            let Some(sender) = sender else {
                return Err(RpcError::new(ERR_INTERNAL, "translate worker is not running"));
            };
            sender
                .send(crate::translate::Job {
                    id: id.clone(),
                    method: method.to_string(),
                    params: params.clone(),
                })
                .map_err(|_| RpcError::new(ERR_INTERNAL, "translate worker stopped"))?;
            Ok(Action::Pending)
        }
        "mail.accounts.list"
        | "mail.accounts.add"
        | "mail.accounts.update"
        | "mail.accounts.remove"
        | "mail.oauth.begin"
        | "mail.oauth.cancel"
        | "mail.list"
        | "mail.get"
        | "mail.refresh"
        | "mail.markSeen" => {
            let sender = state
                .mail_tx
                .lock()
                .ok()
                .and_then(|slot| slot.clone());
            let Some(sender) = sender else {
                return Err(RpcError::new(ERR_INTERNAL, "mail worker is not running"));
            };
            sender
                .send(crate::mail::Job {
                    id: id.clone(),
                    method: method.to_string(),
                    params: params.clone(),
                })
                .map_err(|_| RpcError::new(ERR_INTERNAL, "mail worker stopped"))?;
            Ok(Action::Pending)
        }
        "quota.get" => {
            let providers = state
                .quota
                .lock()
                .map(|items| items.clone())
                .unwrap_or_default();
            let updated_at = providers
                .iter()
                .map(|provider| provider.updated_at_ms)
                .max()
                .unwrap_or_else(|| chrono::Utc::now().timestamp_millis());
            Ok(Action::Respond(json!({
                "providers": providers,
                "updatedAtMs": updated_at,
            })))
        }
        "quota.refresh" => {
            let provider = params
                .get("provider")
                .and_then(Value::as_str)
                .filter(|value| matches!(*value, "glm" | "deepseek" | "opencode"))
                .map(str::to_string);
            wake_quota(state, provider);
            Ok(Action::Respond(json!({ "ok": true })))
        }
        "quota.setSecret" => {
            let provider = params
                .get("provider")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let field = params
                .get("field")
                .and_then(Value::as_str)
                .unwrap_or("apiKey");
            let value = params
                .get("value")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let target = match (provider, field) {
                ("glm", "apiKey") => crate::credentials::GLM_KEY,
                ("deepseek", "apiKey") => crate::credentials::DEEPSEEK_KEY,
                ("opencode", "apiKey") => crate::credentials::OPENCODE_KEY,
                ("opencode", "cookie") => crate::credentials::OPENCODE_COOKIE,
                _ => {
                    return Err(RpcError::new(
                        ERR_INVALID_PARAMS,
                        "quota.setSecret requires a known provider and field",
                    ))
                }
            };
            crate::credentials::write(target, value)
                .map_err(|message| RpcError::new(ERR_INTERNAL, message))?;
            wake_quota(state, Some(provider.to_string()));
            Ok(Action::Respond(json!({
                "ok": true,
                "configured": crate::credentials::read(target).is_some(),
            })))
        }
        "schedule.list"
        | "schedule.add"
        | "schedule.update"
        | "schedule.remove"
        | "schedule.clearExpired" => {
            let sender = state
                .schedule_tx
                .lock()
                .ok()
                .and_then(|slot| slot.clone());
            let Some(sender) = sender else {
                return Err(RpcError::new(
                    ERR_INTERNAL,
                    "schedule worker is not running",
                ));
            };
            sender
                .send(crate::schedule::Command {
                    id: id.clone(),
                    method: method.to_string(),
                    params: params.clone(),
                })
                .map_err(|_| RpcError::new(ERR_INTERNAL, "schedule worker stopped"))?;
            Ok(Action::Pending)
        }
        "anniversary.list"
        | "anniversary.add"
        | "anniversary.update"
        | "anniversary.remove" => {
            let sender = state
                .anniversary_tx
                .lock()
                .ok()
                .and_then(|slot| slot.clone());
            let Some(sender) = sender else {
                return Err(RpcError::new(
                    ERR_INTERNAL,
                    "anniversary worker is not running",
                ));
            };
            sender
                .send(crate::anniversary::Command {
                    id: id.clone(),
                    method: method.to_string(),
                    params: params.clone(),
                })
                .map_err(|_| {
                    RpcError::new(ERR_INTERNAL, "anniversary worker stopped")
                })?;
            Ok(Action::Pending)
        }
        "settings.get" => Ok(Action::Respond(json!({
            "settings": settings_snapshot(state),
        }))),
        "settings.set" => {
            let Some(patch) = params.get("settings").and_then(Value::as_object) else {
                return Err(RpcError::new(
                    ERR_INVALID_PARAMS,
                    "settings.set requires a settings object",
                ));
            };
            // 只读派生键和密钥键不允许落进 config.json。
            let mut patch = patch.clone();
            for key in [
                "translateLlmKeyConfigured",
                "translateDeeplKeyConfigured",
                "translateCaiyunKeyConfigured",
                "translateLlmApiKey",
                "translateDeeplApiKey",
                "translateCaiyunToken",
                "quotaGlmKeyConfigured",
                "quotaDeepseekKeyConfigured",
                "quotaOpencodeKeyConfigured",
                "quotaOpencodeCookieConfigured",
            ] {
                patch.remove(key);
            }
            // 客户端每次设置保存都会带上全部键，只有真正变化的额度设置才触发刷新。
            let previous = state.config.snapshot();
            let quota_changed = ["quotaOrder", "quotaRefreshSeconds", "quotaGlmRegion"]
                .iter()
                .any(|key| previous.get(*key) != patch.get(*key));
            let weather_changed = [
                "weatherLocationMode",
                "weatherLocationName",
                "weatherLatitude",
                "weatherLongitude",
            ]
            .iter()
            .any(|key| previous.get(*key) != patch.get(*key));
            match state.config.merge(&patch) {
                Ok(_) => {
                    if quota_changed {
                        wake_quota(state, None);
                    }
                    if weather_changed {
                        wake_weather(state);
                    }
                    Ok(Action::Respond(json!({
                        "ok": true,
                        "settings": settings_snapshot(state),
                    })))
                }
                Err(message) => Err(RpcError::new(
                    ERR_INTERNAL,
                    format!("settings save failed: {message}"),
                )),
            }
        }
        "app.shutdown" => Ok(Action::Shutdown(json!({ "ok": true }))),
        other => Err(RpcError::new(
            ERR_METHOD_NOT_FOUND,
            format!("method not found: {other}"),
        )),
    }
}

fn media_control(params: &Value) -> Result<Action, RpcError> {
    use crate::media::Transport;
    let action = params
        .get("action")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let command = match action {
        "toggle" | "play_pause" => Transport::Toggle,
        "next" => Transport::Next,
        "previous" | "prev" => Transport::Previous,
        "seek" => {
            let position = params
                .get("position")
                .and_then(Value::as_f64)
                .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "seek requires position"))?;
            Transport::Seek(position)
        }
        other => {
            return Err(RpcError::new(
                ERR_INVALID_PARAMS,
                format!("unknown media action: {other}"),
            ))
        }
    };
    let source = params.get("source").and_then(Value::as_str);
    match crate::media::control(command, source) {
        Ok(()) => Ok(Action::Respond(json!({ "ok": true }))),
        Err(message) => Ok(Action::Respond(json!({ "ok": false, "message": message }))),
    }
}

/// 设置快照 + 凭据状态。凭据键是只读派生值，不写入 config.json。
fn settings_snapshot(state: &State) -> Map<String, Value> {
    let mut settings = state.config.snapshot();
    settings.insert(
        "translateLlmKeyConfigured".into(),
        json!(crate::credentials::read(crate::credentials::LLM).is_some()),
    );
    settings.insert(
        "translateDeeplKeyConfigured".into(),
        json!(crate::credentials::read(crate::credentials::DEEPL).is_some()),
    );
    settings.insert(
        "translateCaiyunKeyConfigured".into(),
        json!(crate::credentials::read(crate::credentials::CAIYUN).is_some()),
    );
    settings.insert(
        "quotaGlmKeyConfigured".into(),
        json!(crate::credentials::read(crate::credentials::GLM_KEY).is_some()),
    );
    settings.insert(
        "quotaDeepseekKeyConfigured".into(),
        json!(crate::credentials::read(crate::credentials::DEEPSEEK_KEY).is_some()),
    );
    settings.insert(
        "quotaOpencodeKeyConfigured".into(),
        json!(crate::credentials::read(crate::credentials::OPENCODE_KEY).is_some()),
    );
    settings.insert(
        "quotaOpencodeCookieConfigured".into(),
        json!(crate::credentials::read(crate::credentials::OPENCODE_COOKIE).is_some()),
    );
    settings
}

fn wake_weather(state: &State) {
    if let Ok(slot) = state.weather_tx.lock() {
        if let Some(sender) = slot.as_ref() {
            let _ = sender.send(crate::weather::Command::Refresh);
        }
    }
}

fn wake_quota(state: &State, provider: Option<String>) {
    if let Ok(slot) = state.quota_tx.lock() {
        if let Some(sender) = slot.as_ref() {
            let _ = sender.send(crate::quota::Command::Refresh(provider));
        }
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
    fn settings_round_trip_merges_partial_updates() {
        let state = State::default();
        let set = handle(
            &state,
            &Value::Null,
            "settings.set",
            &json!({ "settings": { "themeId": "midnight", "windowX": 120.5 } }),
        )
        .unwrap();
        let Action::Respond(result) = set else {
            panic!("expected response");
        };
        assert_eq!(result["ok"], true);
        assert_eq!(result["settings"]["themeId"], "midnight");

        let Action::Respond(result) = handle(
            &state,
            &Value::Null,
            "settings.set",
            &json!({ "settings": { "showWeather": false } }),
        )
        .unwrap()
        else {
            panic!("expected response");
        };
        assert_eq!(result["settings"]["themeId"], "midnight");
        assert_eq!(result["settings"]["showWeather"], false);

        let Action::Respond(result) =
            handle(&state, &Value::Null, "settings.get", &json!({})).unwrap()
        else {
            panic!("expected response");
        };
        assert_eq!(result["settings"]["windowX"], 120.5);
    }

    #[test]
    fn settings_set_drops_derived_translate_keys() {
        let state = State::default();
        let _ = handle(
            &state,
            &Value::Null,
            "settings.set",
            &json!({ "settings": {
                "themeId": "midnight",
                "translateLlmKeyConfigured": true,
                "translateDeeplApiKey": "secret",
            } }),
        )
        .unwrap();
        let snapshot = state.config.snapshot();
        assert_eq!(snapshot["themeId"], "midnight");
        assert!(!snapshot.contains_key("translateLlmKeyConfigured"));
        assert!(!snapshot.contains_key("translateDeeplApiKey"));
    }

    #[test]
    fn weather_location_change_wakes_weather_worker() {
        let state = State::default();
        let (tx, rx) = std::sync::mpsc::channel();
        state.set_weather_sender(tx);
        let _ = handle(
            &state,
            &Value::Null,
            "settings.set",
            &json!({ "settings": {
                "weatherLocationMode": "manual",
                "weatherLatitude": 23.11667,
                "weatherLongitude": 113.25,
            } }),
        )
        .unwrap();
        assert!(matches!(
            rx.try_recv(),
            Ok(crate::weather::Command::Refresh)
        ));
    }

    #[test]
    fn weather_search_requires_query() {
        let state = State::default();
        let error = handle(&state, &Value::Null, "weather.search", &json!({}))
            .err()
            .expect("expected error");
        assert_eq!(error.code, ERR_INVALID_PARAMS);
    }

    #[test]
    fn settings_set_requires_object_params() {
        let state = State::default();
        let error = match handle(&state, &Value::Null, "settings.set", &json!({})) {
            Ok(_) => panic!("expected error"),
            Err(error) => error,
        };
        assert_eq!(error.code, ERR_INVALID_PARAMS);
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
