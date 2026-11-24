//! 应用更新：检查 GitHub Releases、下载安装包、校验 SHA-256 并启动安装。
//!
//! 自动检查在独立线程按 6 小时间隔运行；下载也在这个线程内完成，客户端通过
//! `update.status` 轮询进度。安装包下载到 `%LOCALAPPDATA%\gudong\updates`。

use serde::Serialize;
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::rpc::{self, State};

const REPO_API: &str = "https://api.github.com/repos/ldm0715/gudong/releases/latest";
const USER_AGENT: &str = "gudong-updater";
const INITIAL_DELAY: Duration = Duration::from_secs(10);
const MAX_WAIT: Duration = Duration::from_secs(30);

/// 更新状态快照。客户端通过 `update.status` 读取，下载中每秒更新一次进度。
#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSnapshot {
    /// `idle` / `checking` / `downloading` / `ready` / `installing` / `error`。
    pub state: String,
    pub current_version: String,
    /// 当前是否为安装版；便携版不提供自动下载。
    pub installed: bool,
    pub latest_version: String,
    pub update_available: bool,
    pub release_url: String,
    pub notes: String,
    pub asset_name: String,
    pub asset_size: u64,
    pub received_bytes: u64,
    pub message: String,
    pub file_path: String,
}

pub struct Command {
    pub id: Value,
    pub method: String,
}

#[derive(Clone)]
struct ReleaseInfo {
    version: String,
    notes: String,
    release_url: String,
    asset_name: String,
    asset_url: String,
    asset_size: u64,
    sha256: Option<String>,
}

pub fn start(state: Arc<State>, tx: Sender<Value>) -> Sender<Command> {
    let (command_tx, command_rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("update".into())
        .spawn(move || run(state, tx, command_rx));
    if let Err(error) = spawned {
        crate::log(&format!("update: 线程启动失败: {error}"));
    }
    command_tx
}

fn run(state: Arc<State>, tx: Sender<Value>, commands: Receiver<Command>) {
    use chrono::Timelike;

    let mut worker = Worker::new(state, tx);
    let startup = Instant::now() + INITIAL_DELAY;
    let mut checked_date: Option<chrono::NaiveDate> = None;
    loop {
        if worker.state.config.bool("autoCheckUpdates", true) {
            let now = chrono::Local::now();
            let today = now.date_naive();
            // 启动后检查一次；之后每天中午检查一次。
            let startup_due = Instant::now() >= startup;
            let noon_due = now.hour() >= 12;
            if checked_date != Some(today) && (startup_due || noon_due) {
                let today_text = today.format("%Y-%m-%d").to_string();
                let snoozed = worker
                    .state
                    .config
                    .snapshot()
                    .get("updateSnoozeDate")
                    .and_then(|value| value.as_str())
                    .is_some_and(|value| value == today_text);
                if !snoozed {
                    worker.auto_check();
                }
                checked_date = Some(today);
            }
        }
        match commands.recv_timeout(MAX_WAIT) {
            Ok(command) => worker.handle(command),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }
    }
}

struct Worker {
    state: Arc<State>,
    tx: Sender<Value>,
    agent: ureq::Agent,
    download_agent: ureq::Agent,
    release: Option<ReleaseInfo>,
    snapshot: UpdateSnapshot,
}

impl Worker {
    fn new(state: Arc<State>, tx: Sender<Value>) -> Self {
        let snapshot = UpdateSnapshot {
            state: "idle".into(),
            current_version: env!("CARGO_PKG_VERSION").into(),
            installed: is_installed(),
            ..Default::default()
        };
        set_snapshot(&state, &snapshot);
        Self {
            state,
            tx,
            agent: ureq::AgentBuilder::new()
                .timeout_connect(Duration::from_secs(5))
                .timeout(Duration::from_secs(20))
                .build(),
            download_agent: ureq::AgentBuilder::new()
                .timeout_connect(Duration::from_secs(5))
                .timeout(Duration::from_secs(300))
                .build(),
            release: None,
            snapshot,
        }
    }

    fn handle(&mut self, command: Command) {
        match command.method.as_str() {
            "update.check" => {
                self.check();
                let response = rpc::response(&command.id, json!({ "snapshot": self.snapshot }));
                let _ = self.tx.send(response);
            }
            "update.download" => {
                if !self.snapshot.installed {
                    let response = rpc::response(
                        &command.id,
                        json!({ "ok": false, "message": "便携版请前往发布页下载新版本" }),
                    );
                    let _ = self.tx.send(response);
                    return;
                }
                // 下载可能持续几十秒，先确认请求，客户端通过状态轮询进度。
                let response = rpc::response(&command.id, json!({ "ok": true }));
                let _ = self.tx.send(response);
                self.download();
            }
            "update.install" => {
                let result = self.install();
                let response = rpc::response(&command.id, result);
                let _ = self.tx.send(response);
            }
            other => {
                let _ = self.tx.send(rpc::error(
                    &command.id,
                    rpc::RpcError::new(
                        rpc::ERR_METHOD_NOT_FOUND,
                        format!("method not found: {other}"),
                    ),
                ));
            }
        }
    }

    fn auto_check(&mut self) {
        if self.check() {
            let _ = self.tx.send(rpc::event(json!({
                "type": "update.available",
                "snapshot": self.snapshot,
            })));
        }
    }

    /// 检查最新版本，返回是否有更新。
    fn check(&mut self) -> bool {
        self.snapshot.state = "checking".into();
        self.snapshot.message = "正在检查更新".into();
        self.publish();

        let value = match self.fetch_latest() {
            Ok(value) => value,
            Err(message) => {
                self.snapshot.state = "error".into();
                self.snapshot.message = message;
                self.publish();
                return false;
            }
        };
        let Some(release) = parse_release(&value) else {
            self.snapshot.state = "error".into();
            self.snapshot.message = "更新信息解析失败".into();
            self.publish();
            return false;
        };

        let current = env!("CARGO_PKG_VERSION");
        let available = is_newer(&release.version, current);
        self.snapshot.latest_version = release.version.clone();
        self.snapshot.update_available = available;
        self.snapshot.release_url = release.release_url.clone();
        self.snapshot.notes = release.notes.clone();
        self.snapshot.asset_name = release.asset_name.clone();
        self.snapshot.asset_size = release.asset_size;
        self.snapshot.received_bytes = 0;
        self.snapshot.file_path.clear();
        self.snapshot.state = "idle".into();
        self.snapshot.message = if available {
            format!("发现新版本 {}", release.version)
        } else {
            "已是最新版本".into()
        };
        self.release = Some(release);
        self.publish();
        available
    }

    fn fetch_latest(&self) -> Result<Value, String> {
        let response = self
            .agent
            .get(REPO_API)
            .set("User-Agent", USER_AGENT)
            .set("Accept", "application/vnd.github+json")
            .call()
            .map_err(|error| format!("检查更新失败：{error}"))?;
        let text = response
            .into_string()
            .map_err(|error| format!("更新信息读取失败：{error}"))?;
        serde_json::from_str(&text).map_err(|error| format!("更新信息解析失败：{error}"))
    }

    fn download(&mut self) {
        if self.snapshot.state == "downloading" || self.snapshot.state == "installing" {
            return;
        }
        if self.release.is_none() {
            self.check();
        }
        let Some(release) = self.release.clone() else {
            self.snapshot.state = "error".into();
            self.snapshot.message = "请先检查更新".into();
            self.publish();
            return;
        };
        if !self.snapshot.update_available {
            self.snapshot.message = "已是最新版本".into();
            self.publish();
            return;
        }
        let Some(path) = download_path(&release.asset_name) else {
            self.snapshot.state = "error".into();
            self.snapshot.message = "无法确定下载目录".into();
            self.publish();
            return;
        };

        self.snapshot.state = "downloading".into();
        self.snapshot.message = format!("正在下载 {}", release.version);
        self.snapshot.received_bytes = 0;
        self.snapshot.file_path.clear();
        self.publish();

        match self.download_file(&release, &path) {
            Ok(()) => {
                self.snapshot.state = "ready".into();
                self.snapshot.message = "下载完成，可以安装".into();
                self.snapshot.file_path = path.to_string_lossy().to_string();
                self.publish();
                let _ = self.tx.send(rpc::event(json!({
                    "type": "update.ready",
                    "snapshot": self.snapshot,
                })));
            }
            Err(message) => {
                self.snapshot.state = "error".into();
                self.snapshot.message = message;
                self.publish();
            }
        }
    }

    fn download_file(&mut self, release: &ReleaseInfo, path: &Path) -> Result<(), String> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|error| error.to_string())?;
        }
        let response = self
            .download_agent
            .get(&release.asset_url)
            .set("User-Agent", USER_AGENT)
            .call()
            .map_err(|error| format!("下载失败：{error}"))?;
        let total = response
            .header("Content-Length")
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(release.asset_size);
        self.snapshot.asset_size = total;

        let tmp = path.with_extension("part");
        let mut received = 0u64;
        {
            let mut file = std::fs::File::create(&tmp).map_err(|error| error.to_string())?;
            let mut reader = response.into_reader();
            let mut buffer = vec![0u8; 64 * 1024];
            let mut last_report = Instant::now();
            loop {
                let read = reader.read(&mut buffer).map_err(|error| error.to_string())?;
                if read == 0 {
                    break;
                }
                file.write_all(&buffer[..read])
                    .map_err(|error| error.to_string())?;
                received = received.saturating_add(read as u64);
                if last_report.elapsed() >= Duration::from_millis(500) {
                    self.snapshot.received_bytes = received;
                    self.publish();
                    last_report = Instant::now();
                }
            }
            let _ = file.flush();
        }
        self.snapshot.received_bytes = received;
        self.publish();

        if let Some(expected) = &release.sha256 {
            let actual = sha256_file(&tmp)?;
            if !actual.eq_ignore_ascii_case(expected) {
                let _ = std::fs::remove_file(&tmp);
                return Err("安装包校验失败，请重试".into());
            }
        }
        std::fs::rename(&tmp, path).map_err(|error| {
            let _ = std::fs::remove_file(&tmp);
            error.to_string()
        })?;
        Ok(())
    }

    fn install(&mut self) -> Value {
        if !self.snapshot.installed {
            return json!({ "ok": false, "message": "便携版请前往发布页下载新版本" });
        }
        if self.snapshot.state != "ready" || self.snapshot.file_path.is_empty() {
            return json!({ "ok": false, "message": "请先下载更新" });
        }
        let path = PathBuf::from(&self.snapshot.file_path);
        if !path.exists() {
            return json!({ "ok": false, "message": "安装包不存在，请重新下载" });
        }
        self.snapshot.state = "installing".into();
        self.snapshot.message = "正在启动安装程序".into();
        self.publish();
        match std::process::Command::new(&path).spawn() {
            Ok(_) => json!({ "ok": true }),
            Err(error) => {
                self.snapshot.state = "ready".into();
                self.snapshot.message = format!("无法启动安装程序：{error}");
                self.publish();
                json!({ "ok": false, "message": self.snapshot.message })
            }
        }
    }

    fn publish(&self) {
        set_snapshot(&self.state, &self.snapshot);
    }
}

fn set_snapshot(state: &State, snapshot: &UpdateSnapshot) {
    if let Ok(mut slot) = state.update.lock() {
        *slot = snapshot.clone();
    }
}

fn parse_release(value: &Value) -> Option<ReleaseInfo> {
    let tag = value["tag_name"].as_str()?;
    let version = tag.trim().trim_start_matches('v').to_string();
    let notes = value["body"].as_str().unwrap_or_default().to_string();
    let release_url = value["html_url"].as_str().unwrap_or_default().to_string();
    let assets = value["assets"].as_array()?;
    let asset = assets
        .iter()
        .find(|asset| {
            asset["name"]
                .as_str()
                .is_some_and(|name| name.ends_with("-setup.exe"))
        })
        .or_else(|| {
            assets.iter().find(|asset| {
                asset["name"]
                    .as_str()
                    .is_some_and(|name| name.ends_with(".zip"))
            })
        })?;
    let asset_name = asset["name"].as_str()?.to_string();
    let asset_url = asset["browser_download_url"].as_str()?.to_string();
    let asset_size = asset["size"].as_u64().unwrap_or(0);
    let sha256 = checksum_in_notes(&notes, &asset_name);
    // 校验表只留给 sidecar 解析，界面不需要显示 SHA-256 明细。
    let notes = notes
        .split("### 校验")
        .next()
        .unwrap_or(&notes)
        .trim_end()
        .to_string();
    Some(ReleaseInfo {
        version,
        notes,
        release_url,
        asset_name,
        asset_url,
        asset_size,
        sha256,
    })
}

/// 从发布说明的校验表里取出安装包的 SHA-256。
fn checksum_in_notes(notes: &str, asset_name: &str) -> Option<String> {
    let needle = format!("`{asset_name}`");
    for line in notes.lines() {
        if !line.contains(&needle) {
            continue;
        }
        for part in line.split('`') {
            let value = part.trim();
            if value.len() == 64 && value.chars().all(|c| c.is_ascii_hexdigit()) {
                return Some(value.to_ascii_lowercase());
            }
        }
    }
    None
}

/// 当前程序是否由 NSIS 安装版启动。便携版只引导到发布页。
fn is_installed() -> bool {
    #[cfg(windows)]
    {
        use windows::core::HSTRING;
        use windows::Win32::System::Registry::{
            RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_SZ,
        };

        let subkey = HSTRING::from(r"Software\Gudong");
        let value = HSTRING::from("InstallDir");
        let mut size = 0u32;
        let status = unsafe {
            RegGetValueW(
                HKEY_CURRENT_USER,
                &subkey,
                &value,
                RRF_RT_REG_SZ,
                None,
                None,
                Some(&mut size),
            )
        };
        if status.is_err() || size == 0 {
            return false;
        }
        let mut buffer = vec![0u16; (size as usize / 2).max(1)];
        let status = unsafe {
            RegGetValueW(
                HKEY_CURRENT_USER,
                &subkey,
                &value,
                RRF_RT_REG_SZ,
                None,
                Some(buffer.as_mut_ptr().cast()),
                Some(&mut size),
            )
        };
        if status.is_err() {
            return false;
        }
        let end = buffer
            .iter()
            .position(|unit| *unit == 0)
            .unwrap_or(buffer.len());
        let install_dir = String::from_utf16_lossy(&buffer[..end]);
        let install_dir = PathBuf::from(install_dir.trim());
        let Some(exe_dir) = std::env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(|dir| dir.to_path_buf()))
        else {
            return false;
        };
        paths_equal(&install_dir, &exe_dir)
    }
    #[cfg(not(windows))]
    {
        false
    }
}

fn paths_equal(left: &Path, right: &Path) -> bool {
    match (left.canonicalize(), right.canonicalize()) {
        (Ok(left), Ok(right)) => left == right,
        _ => left
            .to_string_lossy()
            .eq_ignore_ascii_case(&right.to_string_lossy()),
    }
}

fn download_path(asset_name: &str) -> Option<PathBuf> {
    let name = Path::new(asset_name)
        .file_name()?
        .to_string_lossy()
        .to_string();
    crate::paths::local_data_dir().map(|dir| dir.join("updates").join(name))
}

fn sha256_file(path: &Path) -> Result<String, String> {
    use sha2::{Digest, Sha256};

    let mut file = std::fs::File::open(path).map_err(|error| error.to_string())?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer).map_err(|error| error.to_string())?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn is_newer(latest: &str, current: &str) -> bool {
    match (parse_version(latest), parse_version(current)) {
        (Some(latest), Some(current)) => latest > current,
        _ => latest != current,
    }
}

fn parse_version(text: &str) -> Option<(u64, u64, u64)> {
    let core = text.trim().trim_start_matches('v');
    let core = core.split(['-', '+']).next()?;
    let mut parts = core.split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next().unwrap_or("0").parse().ok()?;
    let patch = parts.next().unwrap_or("0").parse().ok()?;
    Some((major, minor, patch))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_comparison_handles_v_prefix() {
        assert!(is_newer("0.2.0", "0.1.9"));
        assert!(is_newer("v0.2.0", "0.1.9"));
        assert!(!is_newer("0.1.0", "0.1.0"));
        assert!(!is_newer("v0.1.0", "0.2.0"));
    }

    #[test]
    fn checksum_is_read_from_release_notes() {
        let hash = "a".repeat(64);
        let notes = format!(
            "### 校验\n\n| 文件 | SHA-256 |\n| --- | --- |\n| `gudong-0.2.0-setup.exe` | `{hash}` |"
        );
        assert_eq!(
            checksum_in_notes(&notes, "gudong-0.2.0-setup.exe"),
            Some(hash)
        );
        assert!(checksum_in_notes(&notes, "missing.exe").is_none());
    }

    #[test]
    fn download_path_drops_directories() {
        let path = download_path("..\\evil\\gudong-setup.exe").unwrap();
        assert_eq!(path.file_name().unwrap(), "gudong-setup.exe");
    }
}
