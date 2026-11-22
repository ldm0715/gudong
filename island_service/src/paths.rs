//! 应用数据目录与旧目录迁移。
//!
//! 早期版本使用 `%APPDATA%\guduo` 和 `%LOCALAPPDATA%\guduo`，现在统一到
//! `...\gudong`。启动时把旧目录里新目录缺少的文件复制过来，旧文件保留，
//! 方便回退到旧版本。

use std::path::{Path, PathBuf};

const CURRENT_DIR: &str = "gudong";
const LEGACY_DIR: &str = "guduo";

/// 用户配置与业务数据目录：`%APPDATA%\gudong`。
pub fn app_data_dir() -> Option<PathBuf> {
    base_dir("APPDATA").map(|base| base.join(CURRENT_DIR))
}

/// 日志与缓存目录：`%LOCALAPPDATA%\gudong`。
pub fn local_data_dir() -> Option<PathBuf> {
    base_dir("LOCALAPPDATA").map(|base| base.join(CURRENT_DIR))
}

fn base_dir(variable: &str) -> Option<PathBuf> {
    std::env::var_os(variable).map(PathBuf::from)
}

fn legacy_dir(variable: &str) -> Option<PathBuf> {
    base_dir(variable).map(|base| base.join(LEGACY_DIR))
}

/// 把旧目录中的文件复制到新目录，返回迁移记录。
///
/// 新目录已有同名文件时，先改名为 `*.legacy*.bak` 再覆盖，旧数据不丢。
pub fn migrate_legacy() -> Vec<String> {
    let mut notes = Vec::new();
    if let (Some(old), Some(new)) = (legacy_dir("APPDATA"), app_data_dir()) {
        let marker = new.join(".migrated-from-guduo");
        if !marker.exists() && std::fs::create_dir_all(&new).is_ok() {
            copy_missing(&old, &new, &mut notes);
            // 只迁移一次，避免之后每次启动都用旧目录覆盖新数据。
            let _ = std::fs::write(&marker, "migrated from guduo\n");
        }
    }
    if let (Some(old), Some(new)) = (legacy_dir("LOCALAPPDATA"), local_data_dir()) {
        let marker = new.join(".migrated-from-guduo");
        if !marker.exists() && std::fs::create_dir_all(&new).is_ok() {
            copy_missing(&old, &new, &mut notes);
            let _ = std::fs::write(&marker, "migrated from guduo\n");
        }
    }
    notes
}

fn copy_missing(old: &Path, new: &Path, notes: &mut Vec<String>) {
    let Ok(entries) = std::fs::read_dir(old) else {
        return;
    };
    for entry in entries.flatten() {
        let from = entry.path();
        let Some(name) = from.file_name() else {
            continue;
        };
        let to = new.join(name);
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            if copy_dir(&from, &to) {
                notes.push(format!("migrated dir {}", to.display()));
            }
            continue;
        }
        if std::fs::create_dir_all(new).is_err() {
            continue;
        }
        if to.exists() {
            let Some(backup) = backup_path(&to) else {
                continue;
            };
            if std::fs::rename(&to, &backup).is_err() {
                continue;
            }
            notes.push(format!("backed up {}", backup.display()));
        }
        if std::fs::copy(&from, &to).is_ok() {
            notes.push(format!("migrated {}", to.display()));
        }
    }
}

fn backup_path(path: &Path) -> Option<PathBuf> {
    let name = path.file_name()?.to_string_lossy();
    for index in 0..100 {
        let candidate = if index == 0 {
            path.with_file_name(format!("{name}.legacy.bak"))
        } else {
            path.with_file_name(format!("{name}.legacy.{index}.bak"))
        };
        if !candidate.exists() {
            return Some(candidate);
        }
    }
    None
}

fn copy_dir(from: &Path, to: &Path) -> bool {
    let Ok(entries) = std::fs::read_dir(from) else {
        return false;
    };
    if std::fs::create_dir_all(to).is_err() {
        return false;
    }
    let mut copied = false;
    for entry in entries.flatten() {
        let source = entry.path();
        let target = to.join(entry.file_name());
        if target.exists() {
            continue;
        }
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            copied |= copy_dir(&source, &target);
        } else {
            copied |= std::fs::copy(&source, &target).is_ok();
        }
    }
    copied
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_root(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!(
            "gudong-paths-{}-{name}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn copies_files_and_backs_up_existing() {
        let root = temp_root("migrate");
        let old = root.join("old");
        let new = root.join("new");
        fs::create_dir_all(&old).unwrap();
        fs::create_dir_all(&new).unwrap();
        fs::write(old.join("config.json"), "current").unwrap();
        fs::write(new.join("config.json"), "legacy").unwrap();
        fs::write(old.join("mail.json"), "mail").unwrap();

        let mut notes = Vec::new();
        copy_missing(&old, &new, &mut notes);

        assert_eq!(
            fs::read_to_string(new.join("config.json")).unwrap(),
            "current"
        );
        assert_eq!(
            fs::read_to_string(new.join("config.json.legacy.bak")).unwrap(),
            "legacy"
        );
        assert_eq!(fs::read_to_string(new.join("mail.json")).unwrap(), "mail");

        let _ = fs::remove_dir_all(&root);
    }
}
