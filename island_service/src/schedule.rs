//! 日程与闹钟：`%APPDATA%\gudong\schedule.json`。
//!
//! 读写和到点检查都在独立线程里执行，主循环只把请求转发到队列。
//! 到点后推送 `schedule.fired`，并播放一次系统提示音。

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::time::Duration;

use crate::rpc::{self, RpcError, ERR_INTERNAL, ERR_INVALID_PARAMS, ERR_METHOD_NOT_FOUND};

const TITLE_MAX_CHARS: usize = 80;
const MAX_ITEMS: usize = 500;
const MAX_FUTURE_MS: i64 = 10 * 365 * 24 * 60 * 60 * 1000;

/// 已触发的日程保留 7 天，之后自动清理，避免文件无限增长。
const RETENTION_MS: i64 = 7 * 24 * 60 * 60 * 1000;

/// 最长等待时间。系统休眠后墙钟可能跳变，定期重新计算下一次触发。
const MAX_WAIT: Duration = Duration::from_secs(30);

/// 一条日程。`at_ms` 是本地时间对应的 Unix 毫秒时间戳。
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleItem {
    pub id: String,
    pub title: String,
    pub at_ms: i64,
    #[serde(default)]
    pub fired: bool,
    pub created_at_ms: i64,
}

impl ScheduleItem {
    fn new(title: String, at_ms: i64) -> Self {
        Self {
            id: new_id(),
            title,
            at_ms,
            fired: false,
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

/// 启动日程线程。到点检查、文件读写和 RPC 响应都在这个线程里完成。
pub fn start(tx: Sender<Value>, toast_tx: Sender<crate::toast::Toast>) -> Sender<Command> {
    let (command_tx, command_rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("schedule".into())
        .spawn(move || run(tx, toast_tx, command_rx));
    if let Err(error) = spawned {
        crate::log(&format!("schedule: 线程启动失败: {error}"));
    }
    command_tx
}

fn run(tx: Sender<Value>, toast_tx: Sender<crate::toast::Toast>, commands: Receiver<Command>) {
    let mut store = Store::load();
    // 启动前已经到点的日程不再补发提醒，避免重启后突然弹出一串旧闹钟。
    let now = now_ms();
    let mut changed = store.expire_stale(now);
    changed |= store.purge_expired(now);
    if changed {
        if let Err(error) = store.save() {
            crate::log(&format!("schedule: 清理过期日程失败: {error}"));
        }
    }

    loop {
        let now = now_ms();
        if store.purge_expired(now) {
            if let Err(error) = store.save() {
                crate::log(&format!("schedule: 清理过期日程失败: {error}"));
            }
            let _ = tx.send(updated_event(&store));
        }
        let due = store.take_due(now);
        if !due.is_empty() {
            if let Err(error) = store.save() {
                crate::log(&format!("schedule: 保存触发状态失败: {error}"));
            }
            beep();
            for item in due {
                let _ = toast_tx.send(crate::toast::Toast {
                    title: "日程提醒".into(),
                    body: format!("{} {}", time_label(item.at_ms), item.title),
                });
                let _ = tx.send(rpc::event(json!({
                    "type": "schedule.fired",
                    "item": item,
                })));
            }
            let _ = tx.send(updated_event(&store));
        }

        let wait = store
            .next_due(now)
            .map(|at_ms| Duration::from_millis((at_ms - now).max(20) as u64))
            .unwrap_or(MAX_WAIT)
            .min(MAX_WAIT);
        match commands.recv_timeout(wait) {
            Ok(command) => handle(&mut store, command, &tx),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }
    }
}

fn handle(store: &mut Store, command: Command, tx: &Sender<Value>) {
    let result = match command.method.as_str() {
        "schedule.list" => Ok(json!({ "items": store.list() })),
        "schedule.add" => add(store, &command.params).and_then(|item| {
            persist(store, tx)?;
            Ok(json!({ "item": item }))
        }),
        "schedule.update" => update(store, &command.params).and_then(|item| {
            persist(store, tx)?;
            Ok(json!({ "item": item }))
        }),
        "schedule.remove" => remove(store, &command.params).and_then(|_| {
            persist(store, tx)?;
            Ok(json!({ "ok": true }))
        }),
        "schedule.clearExpired" => {
            let removed = store.clear_expired();
            if removed > 0 {
                persist(store, tx).map(|_| json!({ "ok": true, "removed": removed }))
            } else {
                Ok(json!({ "ok": true, "removed": removed }))
            }
        }
        other => Err(RpcError::new(
            ERR_METHOD_NOT_FOUND,
            format!("method not found: {other}"),
        )),
    };
    let response = match result {
        Ok(value) => rpc::response(&command.id, value),
        Err(error) => {
            crate::log(&format!(
                "schedule rpc error: {} {}",
                error.code, error.message
            ));
            rpc::error(&command.id, error)
        }
    };
    let _ = tx.send(response);
}

/// 写盘成功后通知客户端最新列表。列表是唯一数据源，客户端不需要自己合并。
fn persist(store: &Store, tx: &Sender<Value>) -> Result<(), RpcError> {
    store
        .save()
        .map_err(|message| RpcError::new(ERR_INTERNAL, format!("日程保存失败: {message}")))?;
    let _ = tx.send(updated_event(store));
    Ok(())
}

fn updated_event(store: &Store) -> Value {
    rpc::event(json!({
        "type": "schedule.updated",
        "items": store.list(),
    }))
}

fn add(store: &mut Store, params: &Value) -> Result<ScheduleItem, RpcError> {
    if store.items.len() >= MAX_ITEMS {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            format!("日程数量已达上限（{MAX_ITEMS} 条）"),
        ));
    }
    let title = parse_title(params)?;
    let at_ms = parse_at_ms(params)?;
    let item = ScheduleItem::new(title, at_ms);
    store.items.push(item.clone());
    Ok(item)
}

fn update(store: &mut Store, params: &Value) -> Result<ScheduleItem, RpcError> {
    let id = required_id(params)?;
    let index = store
        .items
        .iter()
        .position(|item| item.id == id)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "日程不存在"))?;

    let title = match params.get("title") {
        Some(_) => Some(parse_title(params)?),
        None => None,
    };
    let at_ms = match params.get("atMs") {
        Some(_) => Some(parse_at_ms(params)?),
        None => None,
    };
    if title.is_none() && at_ms.is_none() {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "至少需要修改标题或时间"));
    }

    let item = &mut store.items[index];
    if let Some(title) = title {
        item.title = title;
    }
    if let Some(at_ms) = at_ms {
        item.at_ms = at_ms;
        item.fired = false;
    }
    Ok(item.clone())
}

fn remove(store: &mut Store, params: &Value) -> Result<(), RpcError> {
    let id = required_id(params)?;
    let before = store.items.len();
    store.items.retain(|item| item.id != id);
    if store.items.len() == before {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "日程不存在"));
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
        return Err(RpcError::new(ERR_INVALID_PARAMS, "标题不能为空"));
    }
    if title.chars().count() > TITLE_MAX_CHARS {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            format!("标题不能超过 {TITLE_MAX_CHARS} 个字符"),
        ));
    }
    Ok(title.to_string())
}

/// `atMs` 必须是未来的毫秒时间戳；已经过去的时间不能新建闹钟。
fn parse_at_ms(params: &Value) -> Result<i64, RpcError> {
    let at_ms = params
        .get("atMs")
        .and_then(Value::as_i64)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "atMs 必须是毫秒时间戳"))?;
    let now = now_ms();
    if at_ms <= now {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            "闹钟时间必须晚于当前时间",
        ));
    }
    if at_ms > now + MAX_FUTURE_MS {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "闹钟时间超出允许范围"));
    }
    Ok(at_ms)
}

fn required_id(params: &Value) -> Result<&str, RpcError> {
    params
        .get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "缺少日程 id"))
}

struct Store {
    path: Option<PathBuf>,
    items: Vec<ScheduleItem>,
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
            .and_then(|text| serde_json::from_str::<Vec<ScheduleItem>>(&text).ok())
            .unwrap_or_default()
            .into_iter()
            .filter(|item| {
                !item.id.trim().is_empty() && !item.title.trim().is_empty() && item.at_ms > 0
            })
            .collect();
        Self {
            path: Some(path),
            items,
        }
    }

    fn list(&self) -> Vec<ScheduleItem> {
        let mut items = self.items.clone();
        items.sort_by(|left, right| {
            left.at_ms
                .cmp(&right.at_ms)
                .then_with(|| left.id.cmp(&right.id))
        });
        items
    }

    /// 启动时把已经过期但没触发过的日程标记为已触发，不补发提醒。
    fn expire_stale(&mut self, now: i64) -> bool {
        let mut changed = false;
        for item in &mut self.items {
            if !item.fired && item.at_ms <= now {
                item.fired = true;
                changed = true;
            }
        }
        changed
    }

    /// 删除超过保留期的已触发日程。
    fn purge_expired(&mut self, now: i64) -> bool {
        let cutoff = now - RETENTION_MS;
        let before = self.items.len();
        self.items
            .retain(|item| !(item.fired && item.at_ms < cutoff));
        self.items.len() != before
    }

    /// 手动清理全部已触发日程。
    fn clear_expired(&mut self) -> usize {
        let before = self.items.len();
        self.items.retain(|item| !item.fired);
        before - self.items.len()
    }

    /// 取出所有到点且未触发的日程，并标记为已触发。
    fn take_due(&mut self, now: i64) -> Vec<ScheduleItem> {
        let mut due = Vec::new();
        for item in &mut self.items {
            if !item.fired && item.at_ms <= now {
                item.fired = true;
                due.push(item.clone());
            }
        }
        due.sort_by_key(|item| item.at_ms);
        due
    }

    fn next_due(&self, now: i64) -> Option<i64> {
        self.items
            .iter()
            .filter(|item| !item.fired && item.at_ms > now)
            .map(|item| item.at_ms)
            .min()
    }

    fn save(&self) -> Result<(), String> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        write_atomic(path, &self.items)
    }
}

fn write_atomic(path: &Path, items: &[ScheduleItem]) -> Result<(), String> {
    let Some(dir) = path.parent() else {
        return Err("invalid schedule path".into());
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
    crate::paths::app_data_dir().map(|dir| dir.join("schedule.json"))
}

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

fn time_label(at_ms: i64) -> String {
    use chrono::TimeZone;
    chrono::Local
        .timestamp_millis_opt(at_ms)
        .single()
        .map(|value| value.format("%m-%d %H:%M").to_string())
        .unwrap_or_default()
}

fn new_id() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let sequence = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("s_{:x}_{:x}", now_ms(), sequence)
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

    fn item(id: &str, at_ms: i64) -> ScheduleItem {
        ScheduleItem {
            id: id.into(),
            title: id.into(),
            at_ms,
            fired: false,
            created_at_ms: 0,
        }
    }

    fn store() -> Store {
        Store {
            path: None,
            items: vec![item("a", 1000), item("b", 2000), item("c", 3000)],
        }
    }

    #[test]
    fn due_items_fire_once() {
        let mut store = store();
        let due = store.take_due(2500);
        assert_eq!(due.len(), 2);
        assert_eq!(due[0].id, "a");
        assert_eq!(due[1].id, "b");
        assert!(store.take_due(2500).is_empty());
        assert_eq!(store.next_due(2500), Some(3000));
    }

    #[test]
    fn stale_items_are_marked_without_firing() {
        let mut store = store();
        assert!(store.expire_stale(2500));
        assert!(store.take_due(2500).is_empty());
        assert_eq!(store.next_due(2500), Some(3000));
    }

    #[test]
    fn list_is_sorted_by_time() {
        let mut store = store();
        store.items.reverse();
        let ids: Vec<String> = store.list().into_iter().map(|item| item.id).collect();
        assert_eq!(ids, ["a", "b", "c"]);
    }

    #[test]
    fn purge_removes_only_old_fired_items() {
        let mut store = store();
        store.items[0].fired = true;
        let now = 1000 + RETENTION_MS + 1;
        assert!(store.purge_expired(now));
        assert_eq!(store.items.len(), 2);
        assert!(store.items.iter().all(|item| item.id != "a"));
        assert!(!store.purge_expired(now));
    }

    #[test]
    fn clear_expired_removes_fired_items() {
        let mut store = store();
        store.items[0].fired = true;
        store.items[2].fired = true;
        assert_eq!(store.clear_expired(), 2);
        assert_eq!(store.items.len(), 1);
        assert_eq!(store.items[0].id, "b");
    }

    #[test]
    fn store_round_trips_through_disk() {
        let mut path = std::env::temp_dir();
        path.push(format!("gudong-schedule-test-{}.json", std::process::id()));
        let store = Store {
            path: Some(path.clone()),
            items: vec![item("a", 1000), item("b", 2000)],
        };
        store.save().unwrap();
        let loaded = Store::load_from(path.clone());
        assert_eq!(loaded.items.len(), 2);
        assert_eq!(loaded.items[0].id, "a");
        assert_eq!(loaded.items[1].id, "b");
        let _ = std::fs::remove_file(path);
    }
}
