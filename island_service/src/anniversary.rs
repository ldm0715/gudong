//! 倒计时与纪念日：`%APPDATA%\gudong\anniversaries.json`。
//!
//! 只存标题和日期，天数由客户端按本地日期计算。读写与 RPC 响应都在独立线程执行。

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, Sender};

use crate::rpc::{self, RpcError, ERR_INTERNAL, ERR_INVALID_PARAMS, ERR_METHOD_NOT_FOUND};

const TITLE_MAX_CHARS: usize = 80;
const MAX_ITEMS: usize = 200;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AnniversaryItem {
    pub id: String,
    pub title: String,
    /// 本地日期，格式 `YYYY-MM-DD`。
    pub date: String,
    pub created_at_ms: i64,
}

impl AnniversaryItem {
    fn new(title: String, date: String) -> Self {
        Self {
            id: new_id(),
            title,
            date,
            created_at_ms: now_ms(),
        }
    }
}

pub struct Command {
    pub id: Value,
    pub method: String,
    pub params: Value,
}

pub fn start(tx: Sender<Value>) -> Sender<Command> {
    let (command_tx, command_rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("anniversary".into())
        .spawn(move || run(tx, command_rx));
    if let Err(error) = spawned {
        crate::log(&format!("anniversary: 线程启动失败: {error}"));
    }
    command_tx
}

fn run(tx: Sender<Value>, commands: Receiver<Command>) {
    let mut store = Store::load();
    while let Ok(command) = commands.recv() {
        handle(&mut store, command, &tx);
    }
}

fn handle(store: &mut Store, command: Command, tx: &Sender<Value>) {
    let result = match command.method.as_str() {
        "anniversary.list" => Ok(json!({ "items": store.list() })),
        "anniversary.add" => add(store, &command.params).and_then(|item| {
            persist(store, tx)?;
            Ok(json!({ "item": item }))
        }),
        "anniversary.update" => update(store, &command.params).and_then(|item| {
            persist(store, tx)?;
            Ok(json!({ "item": item }))
        }),
        "anniversary.remove" => remove(store, &command.params).and_then(|_| {
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
            crate::log(&format!(
                "anniversary rpc error: {} {}",
                error.code, error.message
            ));
            rpc::error(&command.id, error)
        }
    };
    let _ = tx.send(response);
}

fn persist(store: &Store, tx: &Sender<Value>) -> Result<(), RpcError> {
    store
        .save()
        .map_err(|message| RpcError::new(ERR_INTERNAL, format!("倒计时保存失败: {message}")))?;
    let _ = tx.send(rpc::event(json!({
        "type": "anniversary.updated",
        "items": store.list(),
    })));
    Ok(())
}

fn add(store: &mut Store, params: &Value) -> Result<AnniversaryItem, RpcError> {
    if store.items.len() >= MAX_ITEMS {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            format!("倒计时数量已达上限（{MAX_ITEMS} 条）"),
        ));
    }
    let title = parse_title(params)?;
    let date = parse_date(params)?;
    let item = AnniversaryItem::new(title, date);
    store.items.push(item.clone());
    Ok(item)
}

fn update(store: &mut Store, params: &Value) -> Result<AnniversaryItem, RpcError> {
    let id = required_id(params)?;
    let index = store
        .items
        .iter()
        .position(|item| item.id == id)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "倒计时不存在"))?;

    let title = match params.get("title") {
        Some(_) => Some(parse_title(params)?),
        None => None,
    };
    let date = match params.get("date") {
        Some(_) => Some(parse_date(params)?),
        None => None,
    };
    if title.is_none() && date.is_none() {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "至少需要修改标题或日期"));
    }

    let item = &mut store.items[index];
    if let Some(title) = title {
        item.title = title;
    }
    if let Some(date) = date {
        item.date = date;
    }
    Ok(item.clone())
}

fn remove(store: &mut Store, params: &Value) -> Result<(), RpcError> {
    let id = required_id(params)?;
    let before = store.items.len();
    store.items.retain(|item| item.id != id);
    if store.items.len() == before {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "倒计时不存在"));
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

fn parse_date(params: &Value) -> Result<String, RpcError> {
    let text = params
        .get("date")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim();
    let parsed = NaiveDate::parse_from_str(text, "%Y-%m-%d")
        .map_err(|_| RpcError::new(ERR_INVALID_PARAMS, "日期格式应为 YYYY-MM-DD"))?;
    let canonical = parsed.format("%Y-%m-%d").to_string();
    if canonical != text {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "日期格式应为 YYYY-MM-DD"));
    }
    Ok(canonical)
}

fn required_id(params: &Value) -> Result<&str, RpcError> {
    params
        .get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "缺少倒计时 id"))
}

struct Store {
    path: Option<PathBuf>,
    items: Vec<AnniversaryItem>,
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
            .and_then(|text| serde_json::from_str::<Vec<AnniversaryItem>>(&text).ok())
            .unwrap_or_default()
            .into_iter()
            .filter(|item| {
                !item.id.trim().is_empty()
                    && !item.title.trim().is_empty()
                    && valid_date(&item.date)
            })
            .collect();
        Self {
            path: Some(path),
            items,
        }
    }

    fn list(&self) -> Vec<AnniversaryItem> {
        let mut items = self.items.clone();
        items.sort_by(|left, right| {
            left.date
                .cmp(&right.date)
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

fn valid_date(text: &str) -> bool {
    NaiveDate::parse_from_str(text, "%Y-%m-%d")
        .map(|date| date.format("%Y-%m-%d").to_string() == text)
        .unwrap_or(false)
}

fn write_atomic(path: &Path, items: &[AnniversaryItem]) -> Result<(), String> {
    let Some(dir) = path.parent() else {
        return Err("invalid anniversary path".into());
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
    crate::paths::app_data_dir().map(|dir| dir.join("anniversaries.json"))
}

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

fn new_id() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let sequence = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("a_{:x}_{:x}", now_ms(), sequence)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str, date: &str) -> AnniversaryItem {
        AnniversaryItem {
            id: id.into(),
            title: id.into(),
            date: date.into(),
            created_at_ms: 0,
        }
    }

    fn store() -> Store {
        Store {
            path: None,
            items: vec![
                item("b", "2026-10-01"),
                item("a", "2025-09-04"),
                item("c", "2027-01-01"),
            ],
        }
    }

    #[test]
    fn list_is_sorted_by_date() {
        let store = store();
        let ids: Vec<String> = store.list().into_iter().map(|item| item.id).collect();
        assert_eq!(ids, ["a", "b", "c"]);
    }

    #[test]
    fn date_must_be_canonical() {
        let params = json!({ "date": "2025-9-4" });
        assert_eq!(parse_date(&params).unwrap_err().code, ERR_INVALID_PARAMS);
        let params = json!({ "date": "2025-02-30" });
        assert_eq!(parse_date(&params).unwrap_err().code, ERR_INVALID_PARAMS);
        let params = json!({ "date": "2025-09-04" });
        assert_eq!(parse_date(&params).unwrap(), "2025-09-04");
    }

    #[test]
    fn update_requires_a_field() {
        let mut store = store();
        let error = update(&mut store, &json!({ "id": "a" })).unwrap_err();
        assert_eq!(error.code, ERR_INVALID_PARAMS);
    }

    #[test]
    fn store_round_trips_through_disk() {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "gudong-anniversary-test-{}.json",
            std::process::id()
        ));
        let store = Store {
            path: Some(path.clone()),
            items: vec![item("a", "2025-09-04")],
        };
        store.save().unwrap();
        let loaded = Store::load_from(path.clone());
        assert_eq!(loaded.items.len(), 1);
        assert_eq!(loaded.items[0].title, "a");
        let _ = std::fs::remove_file(path);
    }
}
