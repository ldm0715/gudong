//! 用户配置：`%APPDATA%\guduo\config.json`。
//!
//! 写入先落临时文件再替换，避免断电或崩溃留下半个文件。
//! 凭据不放在这里，Phase 2 接 Windows Credential Manager。

use serde_json::{Map, Value};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

pub struct Config {
    path: Option<PathBuf>,
    values: Mutex<Map<String, Value>>,
}

impl Config {
    /// 从磁盘读取。文件缺失或损坏时按空配置启动，不阻止 sidecar 运行。
    pub fn load() -> Self {
        let Some(path) = default_path() else {
            crate::log("config: APPDATA 未设置，配置只保存在内存");
            return Self::in_memory();
        };
        let values = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str::<Map<String, Value>>(&text).ok())
            .unwrap_or_default();
        // 首次启动就把文件建出来，方便用户找到和手工检查。
        // 文件已存在但内容损坏时不覆盖，避免吞掉用户数据。
        if !path.exists() {
            if let Err(error) = write_atomic(&path, &values) {
                crate::log(&format!("config: 初始化失败: {error}"));
            }
        }
        Self {
            path: Some(path),
            values: Mutex::new(values),
        }
    }

    pub fn in_memory() -> Self {
        Self {
            path: None,
            values: Mutex::new(Map::new()),
        }
    }

    pub fn snapshot(&self) -> Map<String, Value> {
        match self.values.lock() {
            Ok(values) => values.clone(),
            Err(poisoned) => poisoned.into_inner().clone(),
        }
    }

    /// 读取布尔开关，缺省或类型不符时返回 `default`。后台线程会频繁读取，不做拷贝。
    pub fn bool(&self, key: &str, default: bool) -> bool {
        let values = match self.values.lock() {
            Ok(values) => values,
            Err(poisoned) => poisoned.into_inner(),
        };
        values.get(key).and_then(Value::as_bool).unwrap_or(default)
    }

    /// 读取无符号整数设置，缺省或类型不符时返回 `default`。
    pub fn u64(&self, key: &str, default: u64) -> u64 {
        let values = match self.values.lock() {
            Ok(values) => values,
            Err(poisoned) => poisoned.into_inner(),
        };
        values.get(key).and_then(Value::as_u64).unwrap_or(default)
    }

    /// 读取字符串数组设置，只保留字符串项；缺省时返回 `default`。
    pub fn string_list(&self, key: &str, default: &[&str]) -> Vec<String> {
        let values = match self.values.lock() {
            Ok(values) => values,
            Err(poisoned) => poisoned.into_inner(),
        };
        match values.get(key).and_then(Value::as_array) {
            Some(items) => items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect(),
            None => default.iter().map(|item| item.to_string()).collect(),
        }
    }

    /// 合并部分设置。写盘成功后才更新内存，失败时保持原值。
    pub fn merge(&self, patch: &Map<String, Value>) -> Result<Map<String, Value>, String> {
        let mut next = self.snapshot();
        for (key, value) in patch {
            if key.trim().is_empty() {
                return Err("setting key must not be empty".into());
            }
            next.insert(key.clone(), value.clone());
        }
        if let Some(path) = &self.path {
            write_atomic(path, &next)?;
        }
        match self.values.lock() {
            Ok(mut values) => *values = next.clone(),
            Err(poisoned) => *poisoned.into_inner() = next.clone(),
        }
        Ok(next)
    }
}

fn default_path() -> Option<PathBuf> {
    let base = std::env::var_os("APPDATA")?;
    Some(PathBuf::from(base).join("guduo").join("config.json"))
}

fn write_atomic(path: &Path, values: &Map<String, Value>) -> Result<(), String> {
    let Some(dir) = path.parent() else {
        return Err("invalid config path".into());
    };
    std::fs::create_dir_all(dir).map_err(|error| error.to_string())?;
    let text = serde_json::to_string_pretty(values).map_err(|error| error.to_string())?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, text).map_err(|error| error.to_string())?;
    std::fs::rename(&tmp, path).map_err(|error| {
        let _ = std::fs::remove_file(&tmp);
        error.to_string()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn merge_updates_memory_and_snapshot() {
        let config = Config::in_memory();
        let patch = json!({ "themeId": "midnight", "showWeather": true });
        let merged = config.merge(patch.as_object().unwrap()).unwrap();
        assert_eq!(merged["themeId"], "midnight");
        assert_eq!(config.snapshot()["showWeather"], true);
    }

    #[test]
    fn merge_rejects_empty_key() {
        let config = Config::in_memory();
        let patch = json!({ "  ": 1 });
        assert!(config.merge(patch.as_object().unwrap()).is_err());
        assert!(config.snapshot().is_empty());
    }
}
