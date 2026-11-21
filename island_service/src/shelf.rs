//! 中转站：引用式文件暂存，只记路径不搬内容。
//!
//! 索引写在 `%APPDATA%\guduo\shelf.json`，读写都在独立线程里执行。
//! 拖入和拖出都由 Flutter 侧原生拖放处理，这里只负责索引与元数据。

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, Sender, SyncSender};
use std::sync::Arc;

use crate::rpc::{self, RpcError, ERR_INTERNAL, ERR_INVALID_PARAMS, ERR_METHOD_NOT_FOUND};
use crate::shelf_icons::IconJob;

const MAX_ITEMS_DEFAULT: u64 = 100;
const MAX_ITEMS_MIN: u64 = 10;
const MAX_ITEMS_MAX: u64 = 500;

/// 单次请求最多接收的路径数，避免一次拖入整个目录树。
const MAX_PATHS_PER_ADD: usize = 64;

/// 一条中转站条目。`missing` 不落盘，每次读取时按磁盘状态重算。
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShelfItem {
    pub id: String,
    pub path: String,
    pub name: String,
    pub kind: String,
    pub size: u64,
    pub modified_ms: i64,
    pub added_at_ms: i64,
    #[serde(default, skip)]
    pub missing: bool,
}

impl ShelfItem {
    fn from_path(path: &str, added_at_ms: i64) -> Self {
        let meta = std::fs::metadata(path).ok();
        let is_dir = meta.as_ref().map(|value| value.is_dir()).unwrap_or(false);
        Self {
            id: new_id(),
            path: path.to_string(),
            name: display_name(path),
            kind: if is_dir {
                "folder".into()
            } else {
                kind_for(path).into()
            },
            size: if is_dir {
                0
            } else {
                meta.as_ref().map(|value| value.len()).unwrap_or(0)
            },
            modified_ms: meta
                .and_then(|value| value.modified().ok())
                .and_then(|value| value.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|value| value.as_millis() as i64)
                .unwrap_or(0),
            added_at_ms,
            missing: false,
        }
    }

    fn refresh(&mut self) {
        self.missing = !Path::new(&self.path).exists();
        if self.missing {
            return;
        }
        if let Ok(meta) = std::fs::metadata(&self.path) {
            if meta.is_dir() {
                self.kind = "folder".into();
                self.size = 0;
            } else {
                self.kind = kind_for(&self.path).into();
                self.size = meta.len();
            }
        }
    }
}

/// 主循环转发的请求。
pub struct Command {
    pub id: Value,
    pub method: String,
    pub params: Value,
}

/// 启动中转站线程。文件读写、数量校验和 RPC 响应都在这个线程里完成。
pub fn start(
    state: Arc<rpc::State>,
    tx: Sender<Value>,
    icon_tx: SyncSender<IconJob>,
) -> Sender<Command> {
    let (command_tx, command_rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("shelf".into())
        .spawn(move || run(state, tx, icon_tx, command_rx));
    if let Err(error) = spawned {
        crate::log(&format!("shelf: 线程启动失败: {error}"));
    }
    command_tx
}

fn run(
    state: Arc<rpc::State>,
    tx: Sender<Value>,
    icon_tx: SyncSender<IconJob>,
    commands: Receiver<Command>,
) {
    let mut store = Store::load();
    store.refresh_all();
    let mut requested = HashSet::new();
    enqueue_icons(store.items.iter(), &mut requested, &icon_tx);
    for command in commands {
        handle(&state, &mut store, &tx, &icon_tx, &mut requested, command);
    }
}

fn handle(
    state: &rpc::State,
    store: &mut Store,
    tx: &Sender<Value>,
    icon_tx: &SyncSender<IconJob>,
    requested: &mut HashSet<String>,
    command: Command,
) {
    let result = match command.method.as_str() {
        "shelf.list" => Ok(json!({ "items": store.list() })),
        "shelf.add" => add(store, &command.params, max_items(state)).and_then(|result| {
            if !result.added.is_empty() {
                enqueue_icons(result.added.iter(), requested, icon_tx);
                persist(store, tx)?;
            }
            Ok(json!({
                "items": store.list(),
                "added": result.added,
                "skipped": result.skipped,
            }))
        }),
        "shelf.remove" => remove(store, &command.params).and_then(|_| {
            persist(store, tx)?;
            Ok(json!({ "ok": true }))
        }),
        "shelf.removeMany" => remove_many(store, &command.params).and_then(|removed| {
            if removed > 0 {
                persist(store, tx)?;
            }
            Ok(json!({ "ok": true, "removed": removed }))
        }),
        "shelf.clear" => {
            let removed = store.items.len();
            store.items.clear();
            persist(store, tx).map(|_| json!({ "ok": true, "removed": removed }))
        }
        "shelf.reveal" => reveal(store, &command.params).map(|_| json!({ "ok": true })),
        other => Err(RpcError::new(
            ERR_METHOD_NOT_FOUND,
            format!("method not found: {other}"),
        )),
    };
    let response = match result {
        Ok(value) => rpc::response(&command.id, value),
        Err(error) => {
            crate::log(&format!(
                "shelf rpc error: {} {}",
                error.code, error.message
            ));
            rpc::error(&command.id, error)
        }
    };
    let _ = tx.send(response);
}

fn enqueue_icons<'a>(
    items: impl Iterator<Item = &'a ShelfItem>,
    requested: &mut HashSet<String>,
    icon_tx: &SyncSender<IconJob>,
) {
    for item in items {
        if item.missing || !requested.insert(item.id.clone()) {
            continue;
        }
        let job = IconJob {
            id: item.id.clone(),
            path: item.path.clone(),
        };
        if icon_tx.try_send(job).is_err() {
            requested.remove(&item.id);
        }
    }
}

fn max_items(state: &rpc::State) -> usize {
    state
        .config
        .u64("shelfMaxItems", MAX_ITEMS_DEFAULT)
        .clamp(MAX_ITEMS_MIN, MAX_ITEMS_MAX) as usize
}

struct AddResult {
    added: Vec<ShelfItem>,
    skipped: Vec<Value>,
}

fn add(store: &mut Store, params: &Value, max_items: usize) -> Result<AddResult, RpcError> {
    let raw = params
        .get("paths")
        .and_then(Value::as_array)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "paths 必须是字符串数组"))?;
    if raw.is_empty() {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "paths 不能为空"));
    }
    if raw.len() > MAX_PATHS_PER_ADD {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            format!("单次最多接收 {MAX_PATHS_PER_ADD} 个路径"),
        ));
    }

    let now = now_ms();
    let mut added = Vec::new();
    let mut skipped = Vec::new();
    for value in raw {
        let Some(path) = value.as_str().map(str::trim).filter(|v| !v.is_empty()) else {
            skipped.push(json!({ "path": value, "reason": "invalid" }));
            continue;
        };
        if !Path::new(path).exists() {
            skipped.push(json!({ "path": path, "reason": "missing" }));
            continue;
        }
        let key = normalize(path);
        if let Some(index) = store
            .items
            .iter()
            .position(|item| normalize(&item.path) == key)
        {
            // 重复拖入只置顶并刷新元数据，不新增条目。
            let mut item = store.items.remove(index);
            item.added_at_ms = now;
            item.refresh();
            store.items.insert(0, item.clone());
            added.push(item);
            continue;
        }
        if store.items.len() >= max_items {
            skipped.push(json!({ "path": path, "reason": "limit" }));
            continue;
        }
        let item = ShelfItem::from_path(path, now);
        store.items.insert(0, item.clone());
        added.push(item);
    }
    Ok(AddResult { added, skipped })
}

fn remove_many(store: &mut Store, params: &Value) -> Result<usize, RpcError> {
    let raw = params
        .get("ids")
        .and_then(Value::as_array)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "ids 必须是字符串数组"))?;
    if raw.is_empty() {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "ids 不能为空"));
    }
    let ids: HashSet<&str> = raw.iter().filter_map(Value::as_str).collect();
    let before = store.items.len();
    store.items.retain(|item| !ids.contains(item.id.as_str()));
    Ok(before - store.items.len())
}

fn remove(store: &mut Store, params: &Value) -> Result<(), RpcError> {
    let id = required_id(params)?;
    let before = store.items.len();
    store.items.retain(|item| item.id != id);
    if store.items.len() == before {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "条目不存在"));
    }
    Ok(())
}

#[cfg(windows)]
fn reveal(store: &Store, params: &Value) -> Result<(), RpcError> {
    let path = item_path(store, params)?;
    if !Path::new(&path).exists() {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "文件已不存在"));
    }
    std::process::Command::new("explorer")
        .arg(format!("/select,\"{path}\""))
        .spawn()
        .map(|_| ())
        .map_err(|error| RpcError::new(ERR_INTERNAL, format!("无法打开资源管理器: {error}")))
}

#[cfg(not(windows))]
fn reveal(_store: &Store, _params: &Value) -> Result<(), RpcError> {
    Err(RpcError::new(ERR_INTERNAL, "仅支持 Windows"))
}

fn item_path(store: &Store, params: &Value) -> Result<String, RpcError> {
    let id = required_id(params)?;
    store
        .items
        .iter()
        .find(|item| item.id == id)
        .map(|item| item.path.clone())
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "条目不存在"))
}

fn required_id(params: &Value) -> Result<&str, RpcError> {
    params
        .get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "缺少条目 id"))
}

/// 写盘成功后通知客户端最新列表。列表是唯一数据源。
fn persist(store: &Store, tx: &Sender<Value>) -> Result<(), RpcError> {
    store
        .save()
        .map_err(|message| RpcError::new(ERR_INTERNAL, format!("中转站保存失败: {message}")))?;
    let _ = tx.send(rpc::event(json!({
        "type": "shelf.updated",
        "items": store.list(),
    })));
    Ok(())
}

struct Store {
    path: Option<PathBuf>,
    items: Vec<ShelfItem>,
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
            .and_then(|text| serde_json::from_str::<Vec<ShelfItem>>(&text).ok())
            .unwrap_or_default()
            .into_iter()
            .filter(|item| !item.id.trim().is_empty() && !item.path.trim().is_empty())
            .collect();
        Self {
            path: Some(path),
            items,
        }
    }

    fn list(&self) -> Vec<ShelfItem> {
        self.items.clone()
    }

    fn refresh_all(&mut self) {
        for item in &mut self.items {
            item.refresh();
        }
    }

    fn save(&self) -> Result<(), String> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        write_atomic(path, &self.items)
    }
}

fn write_atomic(path: &Path, items: &[ShelfItem]) -> Result<(), String> {
    let Some(dir) = path.parent() else {
        return Err("invalid shelf path".into());
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
    let base = std::env::var_os("APPDATA")?;
    Some(PathBuf::from(base).join("guduo").join("shelf.json"))
}

fn display_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| path.to_string())
}

/// 按扩展名给出展示用分类，缩略图与图标都由客户端决定。
fn kind_for(path: &str) -> &'static str {
    let ext = Path::new(path)
        .extension()
        .map(|value| value.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "bmp" | "svg" | "ico" | "heic" => "image",
        "mp4" | "mkv" | "mov" | "avi" | "webm" | "wmv" | "flv" => "video",
        "mp3" | "flac" | "wav" | "aac" | "m4a" | "ogg" | "wma" => "audio",
        "pdf" | "doc" | "docx" | "xls" | "xlsx" | "ppt" | "pptx" | "txt" | "md" | "csv" => {
            "document"
        }
        "zip" | "rar" | "7z" | "tar" | "gz" | "bz2" | "xz" => "archive",
        "exe" | "msi" => "installer",
        _ => "file",
    }
}

fn normalize(path: &str) -> String {
    path.trim().replace('/', "\\").to_lowercase()
}

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

fn new_id() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let sequence = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("f_{:x}_{:x}", now_ms(), sequence)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str, path: &str) -> ShelfItem {
        ShelfItem {
            id: id.into(),
            path: path.into(),
            name: id.into(),
            kind: "file".into(),
            size: 0,
            modified_ms: 0,
            added_at_ms: 0,
            missing: false,
        }
    }

    fn store() -> Store {
        Store {
            path: None,
            items: vec![item("a", "C:\\a.txt"), item("b", "C:\\b.txt")],
        }
    }

    fn existing_file(name: &str) -> String {
        let mut path = std::env::temp_dir();
        path.push(format!("guduo-shelf-{}-{name}", std::process::id()));
        std::fs::write(&path, b"x").unwrap();
        path.to_string_lossy().to_string()
    }

    #[test]
    fn duplicates_are_moved_to_front() {
        let file = existing_file("dup");
        let mut store = store();
        store.items.push(item("c", &file));
        let path = store.items[2].path.clone();
        let result = add(&mut store, &json!({ "paths": [path] }), 10).unwrap();
        assert_eq!(result.added.len(), 1);
        assert_eq!(store.items.len(), 3);
        assert_eq!(store.items[0].id, "c");
        let _ = std::fs::remove_file(file);
    }

    #[test]
    fn limit_skips_extra_paths() {
        let first = existing_file("limit-a");
        let second = existing_file("limit-b");
        let mut store = store();
        let result = add(
            &mut store,
            &json!({ "paths": [first.clone(), second.clone()] }),
            2,
        )
        .unwrap();
        assert_eq!(result.added.len(), 0);
        assert_eq!(result.skipped.len(), 2);
        assert_eq!(store.items.len(), 2);
        let _ = std::fs::remove_file(first);
        let _ = std::fs::remove_file(second);
    }

    #[test]
    fn missing_paths_are_skipped() {
        let mut store = store();
        let result = add(
            &mut store,
            &json!({ "paths": ["C:\\definitely-not-here-xyz"] }),
            10,
        )
        .unwrap();
        assert!(result.added.is_empty());
        assert_eq!(result.skipped.len(), 1);
        assert_eq!(store.items.len(), 2);
    }

    #[test]
    fn refresh_marks_missing() {
        let mut store = store();
        store.refresh_all();
        assert!(store.items.iter().all(|item| item.missing));
    }

    #[test]
    fn store_round_trips_through_disk() {
        let mut path = std::env::temp_dir();
        path.push(format!("guduo-shelf-test-{}.json", std::process::id()));
        let store = Store {
            path: Some(path.clone()),
            items: vec![item("a", "C:\\a.txt")],
        };
        store.save().unwrap();
        let loaded = Store::load_from(path.clone());
        assert_eq!(loaded.items.len(), 1);
        assert_eq!(loaded.items[0].id, "a");
        let _ = std::fs::remove_file(path);
    }
}
