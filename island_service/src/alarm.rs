//! 每日闹钟：`%APPDATA%\gudong\alarms.json`。
//!
//! 按星期与 HH:mm 匹配，到点推送 `alarm.fired`，并播放一次系统提示音。
//! 检查线程每 20 秒醒来一次，同一分钟内的重复检查会按分钟键去重。

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::time::Duration;

use crate::rpc::{self, RpcError, ERR_INTERNAL, ERR_INVALID_PARAMS, ERR_METHOD_NOT_FOUND};

const TITLE_MAX_CHARS: usize = 80;
const MAX_ITEMS: usize = 100;

/// 轮询间隔。闹钟按分钟匹配，20 秒足够准时，也能及时响应命令。
const CHECK_INTERVAL: Duration = Duration::from_secs(20);

/// 一条每日闹钟。`days` 使用 ISO 星期：1 = 周一，7 = 周日。
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AlarmItem {
    pub id: String,
    pub title: String,
    pub hour: u8,
    pub minute: u8,
    pub days: Vec<u8>,
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
    pub created_at_ms: i64,
}

fn enabled_by_default() -> bool {
    true
}

impl AlarmItem {
    fn new(title: String, hour: u8, minute: u8, days: Vec<u8>, enabled: bool) -> Self {
        Self {
            id: new_id(),
            title,
            hour,
            minute,
            days,
            enabled,
            created_at_ms: now_ms(),
        }
    }
}

/// 主循环转发的请求。
pub struct Command {
    pub id: Value,
    pub method: String,
    pub params: Value,
}

pub fn start(tx: Sender<Value>, toast_tx: Sender<crate::toast::Toast>) -> Sender<Command> {
    let (command_tx, command_rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("alarm".into())
        .spawn(move || run(tx, toast_tx, command_rx));
    if let Err(error) = spawned {
        crate::log(&format!("alarm: 线程启动失败: {error}"));
    }
    command_tx
}

fn run(tx: Sender<Value>, toast_tx: Sender<crate::toast::Toast>, commands: Receiver<Command>) {
    let mut store = Store::load();
    // 同一分钟内只触发一次，避免 20 秒轮询重复提醒。
    let mut fired_keys: HashMap<String, String> = HashMap::new();
    loop {
        fire_due(&store, &mut fired_keys, &tx, &toast_tx);
        match commands.recv_timeout(CHECK_INTERVAL) {
            Ok(command) => handle(&mut store, command, &tx),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }
    }
}

fn fire_due(
    store: &Store,
    fired_keys: &mut HashMap<String, String>,
    tx: &Sender<Value>,
    toast_tx: &Sender<crate::toast::Toast>,
) {
    let due = due_items(store, fired_keys, chrono::Local::now());
    if due.is_empty() {
        return;
    }

    beep();
    for item in due {
        let _ = toast_tx.send(crate::toast::Toast {
            title: "闹钟".into(),
            body: item.title.clone(),
        });
        let _ = tx.send(rpc::event(json!({
            "type": "alarm.fired",
            "item": item,
        })));
    }
}

/// 找出当前分钟应触发的闹钟，并记录去重键。
fn due_items(
    store: &Store,
    fired_keys: &mut HashMap<String, String>,
    now: chrono::DateTime<chrono::Local>,
) -> Vec<AlarmItem> {
    use chrono::{Datelike, Timelike};

    let key = now.format("%Y-%m-%d %H:%M").to_string();
    // 只保留当前分钟的记录，避免映射随运行时间无限增长。
    fired_keys.retain(|_, value| value == &key);

    let weekday = now.weekday().number_from_monday() as u8;
    let hour = now.hour() as u8;
    let minute = now.minute() as u8;
    let due: Vec<AlarmItem> = store
        .items
        .iter()
        .filter(|item| {
            item.enabled
                && item.hour == hour
                && item.minute == minute
                && item.days.contains(&weekday)
                && fired_keys.get(&item.id) != Some(&key)
        })
        .cloned()
        .collect();
    for item in &due {
        fired_keys.insert(item.id.clone(), key.clone());
    }
    due
}

fn handle(store: &mut Store, command: Command, tx: &Sender<Value>) {
    let result = match command.method.as_str() {
        "alarm.list" => Ok(json!({ "items": store.list() })),
        "alarm.add" => add(store, &command.params).and_then(|item| {
            persist(store, tx)?;
            Ok(json!({ "item": item }))
        }),
        "alarm.update" => update(store, &command.params).and_then(|item| {
            persist(store, tx)?;
            Ok(json!({ "item": item }))
        }),
        "alarm.remove" => remove(store, &command.params).and_then(|_| {
            persist(store, tx)?;
            Ok(json!({ "ok": true }))
        }),
        other => Err(RpcError::new(
            ERR_METHOD_NOT_FOUND,
            format!("method not found: {other}"),
        )),
    };
    let response = match result {
        Ok(value) => rpc::response(&command.id, value),
        Err(error) => {
            crate::log(&format!("alarm rpc error: {} {}", error.code, error.message));
            rpc::error(&command.id, error)
        }
    };
    let _ = tx.send(response);
}

fn persist(store: &Store, tx: &Sender<Value>) -> Result<(), RpcError> {
    store
        .save()
        .map_err(|message| RpcError::new(ERR_INTERNAL, format!("闹钟保存失败: {message}")))?;
    let _ = tx.send(rpc::event(json!({
        "type": "alarm.updated",
        "items": store.list(),
    })));
    Ok(())
}

fn add(store: &mut Store, params: &Value) -> Result<AlarmItem, RpcError> {
    if store.items.len() >= MAX_ITEMS {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            format!("闹钟数量已达上限（{MAX_ITEMS} 条）"),
        ));
    }
    let title = parse_title(params)?;
    let hour = parse_hour(params)?;
    let minute = parse_minute(params)?;
    let days = parse_days(params)?;
    let enabled = params
        .get("enabled")
        .and_then(Value::as_bool)
        .unwrap_or(true);
    let item = AlarmItem::new(title, hour, minute, days, enabled);
    store.items.push(item.clone());
    Ok(item)
}

fn update(store: &mut Store, params: &Value) -> Result<AlarmItem, RpcError> {
    let id = required_id(params)?;
    let index = store
        .items
        .iter()
        .position(|item| item.id == id)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "闹钟不存在"))?;

    let item = &mut store.items[index];
    let mut changed = false;
    if params.get("title").is_some() {
        item.title = parse_title(params)?;
        changed = true;
    }
    if params.get("hour").is_some() {
        item.hour = parse_hour(params)?;
        changed = true;
    }
    if params.get("minute").is_some() {
        item.minute = parse_minute(params)?;
        changed = true;
    }
    if params.get("days").is_some() {
        item.days = parse_days(params)?;
        changed = true;
    }
    if let Some(enabled) = params.get("enabled").and_then(Value::as_bool) {
        item.enabled = enabled;
        changed = true;
    }
    if !changed {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "至少需要修改一个字段"));
    }
    Ok(item.clone())
}

fn remove(store: &mut Store, params: &Value) -> Result<(), RpcError> {
    let id = required_id(params)?;
    let before = store.items.len();
    store.items.retain(|item| item.id != id);
    if store.items.len() == before {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "闹钟不存在"));
    }
    Ok(())
}

fn parse_title(params: &Value) -> Result<String, RpcError> {
    let title = params
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim();
    if title.is_empty() {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "名称不能为空"));
    }
    if title.chars().count() > TITLE_MAX_CHARS {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            format!("名称不能超过 {TITLE_MAX_CHARS} 个字符"),
        ));
    }
    Ok(title.to_string())
}

fn parse_hour(params: &Value) -> Result<u8, RpcError> {
    let hour = params
        .get("hour")
        .and_then(Value::as_u64)
        .filter(|value| *value <= 23)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "hour 取值应为 0–23"))?;
    Ok(hour as u8)
}

fn parse_minute(params: &Value) -> Result<u8, RpcError> {
    let minute = params
        .get("minute")
        .and_then(Value::as_u64)
        .filter(|value| *value <= 59)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "minute 取值应为 0–59"))?;
    Ok(minute as u8)
}

/// 至少选择一天；重复项忽略，结果按周一到周日排序。
fn parse_days(params: &Value) -> Result<Vec<u8>, RpcError> {
    let raw = params
        .get("days")
        .and_then(Value::as_array)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "days 必须是非空数组"))?;
    let mut days = Vec::new();
    for value in raw {
        let day = value
            .as_u64()
            .filter(|value| (1..=7).contains(value))
            .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "days 取值应为 1–7"))?;
        let day = day as u8;
        if !days.contains(&day) {
            days.push(day);
        }
    }
    if days.is_empty() {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            "至少需要选择一个生效日",
        ));
    }
    days.sort_unstable();
    Ok(days)
}

fn required_id(params: &Value) -> Result<&str, RpcError> {
    params
        .get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "缺少闹钟 id"))
}

struct Store {
    path: Option<PathBuf>,
    items: Vec<AlarmItem>,
}

impl Store {
    fn load() -> Self {
        let Some(path) = default_path() else {
            return Self {
                path: None,
                items: Vec::new(),
            };
        };
        Self::load_from(path)
    }

    fn load_from(path: PathBuf) -> Self {
        let items = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str::<Vec<AlarmItem>>(&text).ok())
            .unwrap_or_default()
            .into_iter()
            .filter_map(normalize)
            .collect();
        Self {
            path: Some(path),
            items,
        }
    }

    fn list(&self) -> Vec<AlarmItem> {
        let mut items = self.items.clone();
        items.sort_by(|left, right| {
            left.hour
                .cmp(&right.hour)
                .then_with(|| left.minute.cmp(&right.minute))
                .then_with(|| left.id.cmp(&right.id))
        });
        items
    }

    fn save(&self) -> Result<(), String> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        write_atomic(path, &self.items)
    }
}

/// 读取时修复非法条目：去掉无效星期、排序去重；无法修复的条目丢弃。
fn normalize(mut item: AlarmItem) -> Option<AlarmItem> {
    item.title = item.title.trim().to_string();
    if item.id.trim().is_empty() || item.title.is_empty() {
        return None;
    }
    if item.hour > 23 || item.minute > 59 {
        return None;
    }
    let mut days: Vec<u8> = item
        .days
        .into_iter()
        .filter(|day| (1..=7).contains(day))
        .collect();
    days.sort_unstable();
    days.dedup();
    if days.is_empty() {
        return None;
    }
    item.days = days;
    Some(item)
}

fn write_atomic(path: &Path, items: &[AlarmItem]) -> Result<(), String> {
    let Some(dir) = path.parent() else {
        return Err("invalid alarm path".into());
    };
    std::fs::create_dir_all(dir).map_err(|error| error.to_string())?;
    let text = serde_json::to_string_pretty(items).map_err(|error| error.to_string())?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, text).map_err(|error| error.to_string())?;
    std::fs::rename(&tmp, path).map_err(|error| {
        let _ = std::fs::remove_file(&tmp);
        error.to_string()
    })
}

fn default_path() -> Option<PathBuf> {
    crate::paths::app_data_dir().map(|dir| dir.join("alarms.json"))
}

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

fn new_id() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let sequence = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("al_{:x}_{:x}", now_ms(), sequence)
}

#[cfg(windows)]
fn beep() {
    use windows::Win32::System::Diagnostics::Debug::MessageBeep;
    use windows::Win32::UI::WindowsAndMessaging::MB_ICONEXCLAMATION;
    let _ = unsafe { MessageBeep(MB_ICONEXCLAMATION) };
}

#[cfg(not(windows))]
fn beep() {}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str, hour: u8, minute: u8, days: Vec<u8>) -> AlarmItem {
        AlarmItem {
            id: id.into(),
            title: id.into(),
            hour,
            minute,
            days,
            enabled: true,
            created_at_ms: 0,
        }
    }

    #[test]
    fn list_is_sorted_by_time() {
        let store = Store {
            path: None,
            items: vec![
                item("b", 9, 30, vec![1]),
                item("a", 8, 0, vec![1]),
                item("c", 9, 0, vec![2]),
            ],
        };
        let ids: Vec<String> = store.list().into_iter().map(|item| item.id).collect();
        assert_eq!(ids, ["a", "c", "b"]);
    }

    #[test]
    fn days_are_validated_and_sorted() {
        let params = json!({ "days": [5, 1, 1, 3] });
        assert_eq!(parse_days(&params).unwrap(), vec![1, 3, 5]);
        assert_eq!(
            parse_days(&json!({ "days": [] })).unwrap_err().code,
            ERR_INVALID_PARAMS
        );
        assert_eq!(
            parse_days(&json!({ "days": [0] })).unwrap_err().code,
            ERR_INVALID_PARAMS
        );
        assert_eq!(
            parse_days(&json!({ "days": [8] })).unwrap_err().code,
            ERR_INVALID_PARAMS
        );
    }

    #[test]
    fn time_fields_are_range_checked() {
        assert_eq!(parse_hour(&json!({ "hour": 23 })).unwrap(), 23);
        assert_eq!(
            parse_hour(&json!({ "hour": 24 })).unwrap_err().code,
            ERR_INVALID_PARAMS
        );
        assert_eq!(parse_minute(&json!({ "minute": 59 })).unwrap(), 59);
        assert_eq!(
            parse_minute(&json!({ "minute": 60 })).unwrap_err().code,
            ERR_INVALID_PARAMS
        );
    }

    #[test]
    fn due_items_match_time_weekday_and_enabled() {
        use chrono::TimeZone;

        let now = chrono::Local
            .with_ymd_and_hms(2026, 11, 23, 9, 30, 0)
            .unwrap();
        let weekday = {
            use chrono::Datelike;
            now.weekday().number_from_monday() as u8
        };
        let other = if weekday == 1 { 2 } else { 1 };
        let mut store = Store {
            path: None,
            items: vec![
                item("a", 9, 30, vec![weekday]),
                item("b", 9, 30, vec![other]),
                item("c", 9, 31, vec![weekday]),
                item("d", 9, 30, vec![weekday]),
            ],
        };
        store.items[3].enabled = false;

        let mut keys = HashMap::new();
        let due = due_items(&store, &mut keys, now);
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].id, "a");
        // 同一分钟再次检查不会重复触发。
        assert!(due_items(&store, &mut keys, now).is_empty());
    }

    #[test]
    fn update_requires_a_field() {
        let mut store = Store {
            path: None,
            items: vec![item("a", 8, 0, vec![1])],
        };
        let error = update(&mut store, &json!({ "id": "a" })).unwrap_err();
        assert_eq!(error.code, ERR_INVALID_PARAMS);
    }

    #[test]
    fn normalize_drops_invalid_items_and_fixes_days() {
        let fixed = normalize(item("a", 8, 0, vec![7, 1, 1, 9, 0])).unwrap();
        assert_eq!(fixed.days, vec![1, 7]);
        assert!(normalize(item("", 8, 0, vec![1])).is_none());
        assert!(normalize(item("a", 24, 0, vec![1])).is_none());
        assert!(normalize(item("a", 8, 0, vec![])).is_none());
    }

    #[test]
    fn store_round_trips_through_disk() {
        let mut path = std::env::temp_dir();
        path.push(format!("gudong-alarm-test-{}.json", std::process::id()));
        let store = Store {
            path: Some(path.clone()),
            items: vec![item("a", 8, 0, vec![1, 2])],
        };
        store.save().unwrap();
        let loaded = Store::load_from(path.clone());
        assert_eq!(loaded.items.len(), 1);
        assert_eq!(loaded.items[0].days, vec![1, 2]);
        assert!(loaded.items[0].enabled);
        let _ = std::fs::remove_file(path);
    }
}
