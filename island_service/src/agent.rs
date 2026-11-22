//! 本地 AI agent 会话检测。
//!
//! 只读各 agent 已经写好的会话文件，不注入 hook、不修改配置、不联网。
//! 检测结果通过 `agent.updated` 推送运行中的会话，回合结束通过 `agent.finished` 推送横幅数据。

use crate::rpc::{self, State};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const POLL_INTERVAL: Duration = Duration::from_secs(2);
const FILE_WINDOW_MS: u64 = 30 * 60 * 1000;
const SETTLE_MS: u64 = 4_000;
const STALE_RUNNING_MS: u64 = 15 * 60 * 1000;
const MAX_HEAD: u64 = 256 * 1024;
const MAX_TAIL: u64 = 512 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Kind {
    Claude,
    Codex,
    Dsh,
    Pi,
    Omp,
}

impl Kind {
    const ALL: [Kind; 5] = [Kind::Claude, Kind::Codex, Kind::Dsh, Kind::Pi, Kind::Omp];

    fn id(self) -> &'static str {
        match self {
            Kind::Claude => "claude",
            Kind::Codex => "codex",
            Kind::Dsh => "dsh",
            Kind::Pi => "pi",
            Kind::Omp => "omp",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Kind::Claude => "Claude Code",
            Kind::Codex => "Codex",
            Kind::Dsh => "DeepSeek Harness",
            Kind::Pi => "Pi",
            Kind::Omp => "Oh My Pi",
        }
    }

    fn from_id(value: &str) -> Option<Kind> {
        match value {
            "claude" => Some(Kind::Claude),
            "codex" => Some(Kind::Codex),
            "dsh" => Some(Kind::Dsh),
            "pi" => Some(Kind::Pi),
            "omp" => Some(Kind::Omp),
            _ => None,
        }
    }

    /// 各 agent 的会话根目录。存在性就是 `available` 的判断依据。
    fn root(self) -> Option<PathBuf> {
        let home = home_dir()?;
        Some(match self {
            Kind::Claude => env_root("CLAUDE_CONFIG_DIR", home.join(".claude"))
                .join("sessions"),
            Kind::Codex => env_root("CODEX_HOME", home.join(".codex")).join("sessions"),
            Kind::Dsh => env_root("DSH_HOME", home.join(".dsh")).join("sessions"),
            Kind::Pi => home.join(".pi").join("agent").join("sessions"),
            Kind::Omp => home.join(".omp").join("agent").join("sessions"),
        })
    }

}

#[derive(Clone)]
struct Active {
    session_id: String,
    title: String,
    cwd: Option<String>,
    state: &'static str,
    started_at_ms: u64,
    last_active_at_ms: u64,
}

#[derive(Clone)]
struct Ended {
    session_id: String,
    title: String,
    cwd: Option<String>,
    state: &'static str,
    started_at_ms: u64,
    ended_at_ms: u64,
    duration_ms: Option<u64>,
    reply_preview: Option<String>,
}

#[derive(Default)]
struct Poll {
    active: Vec<Active>,
    ended: Vec<Ended>,
}

#[derive(Clone)]
struct Running {
    kind: Kind,
    session_id: String,
    title: String,
    cwd: Option<String>,
    state: String,
    started_at_ms: u64,
}

#[derive(Clone, Default)]
struct Parsed {
    session_id: String,
    title: String,
    cwd: Option<String>,
    running: bool,
    waiting: bool,
    aborted: bool,
    /// pi / omp 的最后一条是最终 assistant 消息，需要等文件安静几秒再判定结束。
    final_turn: bool,
    started_at_ms: u64,
    ended_at_ms: u64,
    duration_ms: Option<u64>,
    last_active_ms: u64,
    reply: Option<String>,
}

struct FileCache {
    size: u64,
    modified_ms: u64,
    parsed_at_ms: u64,
    parsed: Parsed,
}

#[derive(Default)]
struct Watcher {
    running: HashMap<String, Running>,
    cache: HashMap<PathBuf, FileCache>,
    titles: HashMap<String, (u64, u64, String)>,
    last_payload: Option<String>,
}

pub fn start(state: Arc<State>, tx: Sender<Value>) {
    let _ = std::thread::Builder::new()
        .name("agent-watcher".into())
        .spawn(move || run(&state, &tx));
}

fn run(state: &State, tx: &Sender<Value>) {
    let mut watcher = Watcher::default();
    loop {
        let enabled = enabled_kinds(state);
        let (sessions, statuses, finished) = watcher.tick(&enabled);
        watcher.publish(state, tx, sessions, statuses);
        for item in finished {
            let _ = tx.send(rpc::event(item));
        }
        std::thread::sleep(POLL_INTERVAL);
    }
}

fn enabled_kinds(state: &State) -> HashSet<Kind> {
    state
        .config
        .string_list(
            "enabledAgents",
            &["claude", "codex", "dsh", "pi", "omp"],
        )
        .iter()
        .filter_map(|id| Kind::from_id(id))
        .collect()
}

impl Watcher {
    fn tick(&mut self, enabled: &HashSet<Kind>) -> (Vec<Value>, Vec<Value>, Vec<Value>) {
        let now = now_ms();
        let mut sessions = Vec::new();
        let mut statuses = Vec::new();
        let mut finished = Vec::new();

        for kind in Kind::ALL {
            let root = kind.root();
            let available = root.as_ref().is_some_and(|path| path.is_dir());
            if !enabled.contains(&kind) {
                self.running.retain(|_, item| item.kind != kind);
                statuses.push(status_json(kind, false, available, 0, "已关闭", "idle"));
                continue;
            }

            let poll = match &root {
                Some(path) if available => self.poll_kind(kind, path, now),
                _ => Poll::default(),
            };
            let active_keys: HashSet<String> = poll
                .active
                .iter()
                .map(|item| key(kind, &item.session_id))
                .collect();

            for end in poll.ended {
                let id = key(kind, &end.session_id);
                if let Some(previous) = self.running.remove(&id) {
                    finished.push(finished_json(kind, &end, &previous));
                }
            }

            let previous_keys: Vec<String> = self
                .running
                .iter()
                .filter(|(_, item)| item.kind == kind)
                .map(|(id, _)| id.clone())
                .collect();
            for id in previous_keys {
                if active_keys.contains(&id) {
                    continue;
                }
                if let Some(previous) = self.running.remove(&id) {
                    let end = Ended {
                        session_id: previous.session_id.clone(),
                        title: previous.title.clone(),
                        cwd: previous.cwd.clone(),
                        state: "done",
                        started_at_ms: previous.started_at_ms,
                        ended_at_ms: now,
                        duration_ms: now.checked_sub(previous.started_at_ms),
                        reply_preview: None,
                    };
                    finished.push(finished_json(kind, &end, &previous));
                }
            }

            for active in poll.active {
                let id = key(kind, &active.session_id);
                sessions.push(session_json(kind, &active));
                self.running.insert(
                    id,
                    Running {
                        kind,
                        session_id: active.session_id,
                        title: active.title,
                        cwd: active.cwd,
                        state: active.state.to_string(),
                        started_at_ms: active.started_at_ms,
                    },
                );
            }

            let count = self
                .running
                .values()
                .filter(|item| item.kind == kind)
                .count();
            let waiting = self
                .running
                .values()
                .any(|item| item.kind == kind && item.state == "waiting");
            let state = if count == 0 {
                "idle"
            } else if waiting {
                "waiting"
            } else {
                "running"
            };
            let message = if available {
                ""
            } else {
                "未找到会话目录"
            };
            statuses.push(status_json(kind, true, available, count, message, state));
        }

        self.prune(now);
        (sessions, statuses, finished)
    }

    fn poll_kind(&mut self, kind: Kind, root: &Path, now: u64) -> Poll {
        match kind {
            Kind::Claude => self.poll_claude(root, now),
            Kind::Codex => self.poll_codex(root, now),
            Kind::Dsh => self.poll_dsh(root, now),
            Kind::Pi | Kind::Omp => self.poll_pi(root, now, kind),
        }
    }

    fn poll_claude(&mut self, root: &Path, now: u64) -> Poll {
        let mut poll = Poll::default();
        let Ok(entries) = fs::read_dir(root) else {
            return poll;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("json") {
                continue;
            }
            let Ok(text) = fs::read_to_string(&path) else {
                continue;
            };
            let Ok(value) = serde_json::from_str::<Value>(&text) else {
                continue;
            };
            let session_id = value
                .get("sessionId")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            if session_id.is_empty() {
                continue;
            }
            let pid = value.get("pid").and_then(Value::as_u64).unwrap_or(0) as u32;
            let status = value.get("status").and_then(Value::as_str).unwrap_or("");
            let updated = value
                .get("updatedAt")
                .and_then(Value::as_u64)
                .unwrap_or(now);
            let alive = pid > 0 && process_alive(pid);
            let active = alive && matches!(status, "busy" | "active" | "waiting" | "blocked");
            let waiting = matches!(status, "waiting" | "blocked");
            let cwd = value.get("cwd").and_then(Value::as_str).map(str::to_string);
            let name = value
                .get("name")
                .and_then(Value::as_str)
                .map(str::to_string);

            if active {
                let title = self
                    .claude_title(&session_id, cwd.as_deref())
                    .or(name)
                    .or_else(|| cwd.as_deref().and_then(base_name))
                    .unwrap_or_else(|| "Claude Code".to_string());
                poll.active.push(Active {
                    session_id,
                    title,
                    cwd,
                    state: if waiting { "waiting" } else { "running" },
                    started_at_ms: value
                        .get("startedAt")
                        .and_then(Value::as_u64)
                        .unwrap_or(updated),
                    last_active_at_ms: updated,
                });
            } else if self
                .running
                .contains_key(&key(Kind::Claude, &session_id))
            {
                let detail = self.claude_finish(&session_id, cwd.as_deref(), updated);
                poll.ended.push(Ended {
                    session_id,
                    title: detail
                        .title
                        .or(name)
                        .unwrap_or_else(|| "Claude Code".to_string()),
                    cwd,
                    state: "done",
                    started_at_ms: detail.started_at_ms.unwrap_or(updated),
                    ended_at_ms: detail.ended_at_ms.unwrap_or(now),
                    duration_ms: detail.duration_ms,
                    reply_preview: detail.reply,
                });
            }
        }
        poll
    }

    fn poll_pi(&mut self, root: &Path, now: u64, kind: Kind) -> Poll {
        let minimum = now.saturating_sub(FILE_WINDOW_MS);
        let mut paths = Vec::new();
        collect_files(root, 5, &mut paths, minimum, 0);

        let mut poll = Poll::default();
        for path in paths {
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("");
            if name == "changes.jsonl" {
                continue;
            }
            if path.extension().and_then(|value| value.to_str()) != Some("jsonl") {
                continue;
            }
            let Ok(meta) = fs::metadata(&path) else {
                continue;
            };
            let modified = meta
                .modified()
                .ok()
                .map(system_time_ms)
                .unwrap_or(0);
            if modified < minimum {
                continue;
            }
            let parsed = self.parse_file(&path, meta.len(), modified, now, |path| {
                parse_pi_file(path, now, modified)
            });
            let id = key(kind, &parsed.session_id);
            let settled = parsed.final_turn && now.saturating_sub(modified) >= SETTLE_MS;
            let running = parsed.running && !settled;
            if running {
                poll.active.push(Active {
                    session_id: parsed.session_id,
                    title: parsed.title,
                    cwd: parsed.cwd,
                    state: if parsed.waiting { "waiting" } else { "running" },
                    started_at_ms: parsed.started_at_ms,
                    last_active_at_ms: parsed.last_active_ms.max(modified),
                });
            } else if self.running.contains_key(&id) {
                poll.ended.push(Ended {
                    session_id: parsed.session_id,
                    title: parsed.title,
                    cwd: parsed.cwd,
                    state: if parsed.aborted { "aborted" } else { "done" },
                    started_at_ms: parsed.started_at_ms,
                    ended_at_ms: if parsed.ended_at_ms > 0 {
                        parsed.ended_at_ms
                    } else {
                        modified
                    },
                    duration_ms: parsed.duration_ms,
                    reply_preview: parsed.reply,
                });
            }
        }
        poll
    }

    fn poll_codex(&mut self, root: &Path, now: u64) -> Poll {
        let minimum = now.saturating_sub(FILE_WINDOW_MS);
        let directory_minimum = now.saturating_sub(2 * 24 * 60 * 60 * 1000);
        let mut paths = Vec::new();
        collect_files(root, 5, &mut paths, minimum, directory_minimum);

        let mut poll = Poll::default();
        for path in paths {
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("");
            if !name.starts_with("rollout-") {
                continue;
            }
            if !name.ends_with(".jsonl") && !name.ends_with(".jsonl.zst") {
                continue;
            }
            let Ok(meta) = fs::metadata(&path) else {
                continue;
            };
            let modified = meta
                .modified()
                .ok()
                .map(system_time_ms)
                .unwrap_or(0);
            if modified < minimum {
                continue;
            }
            let parsed = self.parse_file(&path, meta.len(), modified, now, |path| {
                parse_codex_file(path, now, modified)
            });
            let id = key(Kind::Codex, &parsed.session_id);
            if parsed.running {
                poll.active.push(Active {
                    session_id: parsed.session_id,
                    title: parsed.title,
                    cwd: parsed.cwd,
                    state: if parsed.waiting { "waiting" } else { "running" },
                    started_at_ms: parsed.started_at_ms,
                    last_active_at_ms: parsed.last_active_ms.max(modified),
                });
            } else if self.running.contains_key(&id) {
                poll.ended.push(Ended {
                    session_id: parsed.session_id,
                    title: parsed.title,
                    cwd: parsed.cwd,
                    state: if parsed.aborted { "aborted" } else { "done" },
                    started_at_ms: parsed.started_at_ms,
                    ended_at_ms: if parsed.ended_at_ms > 0 {
                        parsed.ended_at_ms
                    } else {
                        modified
                    },
                    duration_ms: parsed.duration_ms,
                    reply_preview: parsed.reply,
                });
            }
        }
        poll
    }

    fn poll_dsh(&mut self, root: &Path, now: u64) -> Poll {
        let minimum = now.saturating_sub(FILE_WINDOW_MS);
        let mut paths = Vec::new();
        collect_files(root, 5, &mut paths, minimum, 0);

        let mut poll = Poll::default();
        for path in paths {
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("");
            if !name.ends_with(".jsonl") && !name.ends_with(".jsonl.zst") {
                continue;
            }
            let Ok(meta) = fs::metadata(&path) else {
                continue;
            };
            let modified = meta
                .modified()
                .ok()
                .map(system_time_ms)
                .unwrap_or(0);
            if modified < minimum {
                continue;
            }
            let parsed = self.parse_file(&path, meta.len(), modified, now, |path| {
                parse_dsh_file(path, now, modified)
            });
            let id = key(Kind::Dsh, &parsed.session_id);
            if parsed.running {
                poll.active.push(Active {
                    session_id: parsed.session_id,
                    title: parsed.title,
                    cwd: parsed.cwd,
                    state: if parsed.waiting { "waiting" } else { "running" },
                    started_at_ms: parsed.started_at_ms,
                    last_active_at_ms: parsed.last_active_ms.max(modified),
                });
            } else if self.running.contains_key(&id) {
                poll.ended.push(Ended {
                    session_id: parsed.session_id,
                    title: parsed.title,
                    cwd: parsed.cwd,
                    state: if parsed.aborted { "aborted" } else { "done" },
                    started_at_ms: parsed.started_at_ms,
                    ended_at_ms: if parsed.ended_at_ms > 0 {
                        parsed.ended_at_ms
                    } else {
                        modified
                    },
                    duration_ms: parsed.duration_ms,
                    reply_preview: parsed.reply,
                });
            }
        }
        poll
    }

    fn parse_file<F>(
        &mut self,
        path: &Path,
        size: u64,
        modified: u64,
        now: u64,
        parse: F,
    ) -> Parsed
    where
        F: FnOnce(&Path) -> Parsed,
    {
        if let Some(cached) = self.cache.get(path) {
            if cached.size == size && cached.modified_ms == modified {
                return cached.parsed.clone();
            }
            // 大文件（通常是 codex 的 zstd rollout）在活跃追加时降低解析频率。
            if size > 4 * 1024 * 1024 && now.saturating_sub(cached.parsed_at_ms) < 3_000 {
                return cached.parsed.clone();
            }
        }
        let parsed = parse(path);
        self.cache.insert(
            path.to_path_buf(),
            FileCache {
                size,
                modified_ms: modified,
                parsed_at_ms: now,
                parsed: parsed.clone(),
            },
        );
        parsed
    }

    fn claude_title(&mut self, session_id: &str, cwd: Option<&str>) -> Option<String> {
        let path = claude_transcript(session_id, cwd)?;
        let meta = fs::metadata(&path).ok()?;
        let size = meta.len();
        let modified = meta
            .modified()
            .ok()
            .map(system_time_ms)
            .unwrap_or(0);
        if let Some((cached_size, cached_modified, title)) = self.titles.get(session_id) {
            if *cached_size == size && *cached_modified == modified {
                return Some(title.clone());
            }
        }

        let mut text = read_tail(&path, MAX_HEAD).unwrap_or_default();
        if !text.contains("ai-title") && !text.contains("custom-title") {
            text.push_str(&read_head(&path, MAX_HEAD).unwrap_or_default());
        }
        let title = transcript_title(&text);
        if let Some(title) = &title {
            if self.titles.len() > 300 {
                self.titles.clear();
            }
            self.titles
                .insert(session_id.to_string(), (size, modified, title.clone()));
        }
        title
    }

    fn claude_finish(&mut self, session_id: &str, cwd: Option<&str>, fallback: u64) -> Finish {
        let Some(path) = claude_transcript(session_id, cwd) else {
            return Finish {
                title: None,
                reply: None,
                started_at_ms: None,
                ended_at_ms: Some(fallback),
                duration_ms: None,
            };
        };
        let text = read_tail(&path, MAX_TAIL).unwrap_or_default();
        let mut title = None;
        let mut reply = None;
        let mut ended = None;
        let mut duration = None;
        for line in text.lines() {
            let Ok(value) = serde_json::from_str::<Value>(line) else {
                continue;
            };
            match value.get("type").and_then(Value::as_str).unwrap_or("") {
                "assistant" => {
                    if let Some(message) = value.get("message") {
                        let text = content_text(message.get("content"));
                        if !text.trim().is_empty() {
                            reply = preview(&text);
                        }
                    }
                    if let Some(ts) = iso_ms(value.get("timestamp").and_then(Value::as_str)) {
                        ended = Some(ts);
                    }
                }
                "system"
                    if value.get("subtype").and_then(Value::as_str)
                        == Some("turn_duration") =>
                {
                    duration = value.get("durationMs").and_then(Value::as_u64);
                    if let Some(ts) = iso_ms(value.get("timestamp").and_then(Value::as_str)) {
                        ended = Some(ts);
                    }
                }
                "ai-title" => {
                    if let Some(text) = value.get("aiTitle").and_then(Value::as_str) {
                        title = Some(clean_text(text));
                    }
                }
                "custom-title" => {
                    if let Some(text) = value
                        .get("customTitle")
                        .and_then(Value::as_str)
                        .or_else(|| value.get("title").and_then(Value::as_str))
                    {
                        title = Some(clean_text(text));
                    }
                }
                _ => {}
            }
        }
        let ended = ended.unwrap_or(fallback);
        let started = duration.and_then(|value| ended.checked_sub(value));
        if title.is_none() {
            title = self.claude_title(session_id, cwd);
        }
        Finish {
            title,
            reply,
            started_at_ms: started,
            ended_at_ms: Some(ended),
            duration_ms: duration,
        }
    }

    fn prune(&mut self, now: u64) {
        self.cache
            .retain(|_, item| now.saturating_sub(item.parsed_at_ms) < FILE_WINDOW_MS);
        if self.titles.len() > 500 {
            self.titles.clear();
        }
    }

    fn publish(
        &mut self,
        state: &State,
        tx: &Sender<Value>,
        sessions: Vec<Value>,
        statuses: Vec<Value>,
    ) {
        let payload = json!({ "sessions": sessions, "agents": statuses });
        let text = payload.to_string();
        if self.last_payload.as_deref() == Some(text.as_str()) {
            return;
        }
        self.last_payload = Some(text);
        state.set_agent_snapshot(payload.clone());
        let mut event = payload;
        event["type"] = json!("agent.updated");
        let _ = tx.send(rpc::event(event));
    }
}

struct Finish {
    title: Option<String>,
    reply: Option<String>,
    started_at_ms: Option<u64>,
    ended_at_ms: Option<u64>,
    duration_ms: Option<u64>,
}

fn key(kind: Kind, session_id: &str) -> String {
    format!("{}|{session_id}", kind.id())
}

fn session_json(kind: Kind, item: &Active) -> Value {
    json!({
        "id": kind.id(),
        "label": kind.label(),
        "sessionId": item.session_id,
        "title": item.title,
        "cwd": item.cwd,
        "state": item.state,
        "startedAtMs": item.started_at_ms,
        "lastActiveAtMs": item.last_active_at_ms,
    })
}

fn status_json(
    kind: Kind,
    enabled: bool,
    available: bool,
    count: usize,
    message: &str,
    state: &str,
) -> Value {
    json!({
        "id": kind.id(),
        "label": kind.label(),
        "enabled": enabled,
        "available": available,
        "state": state,
        "sessionCount": count,
        "message": message,
    })
}

fn finished_json(kind: Kind, end: &Ended, previous: &Running) -> Value {
    let title = if end.title.is_empty() {
        previous.title.clone()
    } else {
        end.title.clone()
    };
    let started = if end.started_at_ms > 0 {
        end.started_at_ms
    } else {
        previous.started_at_ms
    };
    let mut value = json!({
        "type": "agent.finished",
        "id": kind.id(),
        "label": kind.label(),
        "sessionId": end.session_id,
        "title": title,
        "state": end.state,
        "startedAtMs": started,
        "endedAtMs": end.ended_at_ms,
    });
    if let Some(cwd) = end.cwd.as_ref().or(previous.cwd.as_ref()) {
        value["cwd"] = json!(cwd);
    }
    if let Some(duration) = end.duration_ms {
        value["durationMs"] = json!(duration);
    }
    if let Some(reply) = end.reply_preview.as_ref() {
        value["replyPreview"] = json!(reply);
    }
    value
}

fn parse_pi_file(path: &Path, now: u64, modified: u64) -> Parsed {
    let head = read_head(path, MAX_HEAD).unwrap_or_default();
    let tail = read_tail(path, MAX_TAIL).unwrap_or_default();

    let mut parsed = Parsed {
        session_id: file_session_id(path),
        last_active_ms: modified,
        ..Parsed::default()
    };
    let mut first_user_text = String::new();
    let mut last_role = "";
    let mut last_has_tool = false;
    let mut last_user_ms = 0;
    let mut last_assistant_ms = 0;
    let mut last_assistant_text = String::new();
    let mut last_timestamp = 0;

    for line in head.lines() {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        match value.get("type").and_then(Value::as_str).unwrap_or("") {
            "session" => {
                if let Some(id) = value.get("id").and_then(Value::as_str) {
                    parsed.session_id = id.to_string();
                }
                if let Some(cwd) = value.get("cwd").and_then(Value::as_str) {
                    parsed.cwd = Some(cwd.to_string());
                }
                if let Some(ts) = iso_ms(value.get("timestamp").and_then(Value::as_str)) {
                    parsed.started_at_ms = ts;
                    parsed.last_active_ms = ts;
                }
            }
            "title" => {
                if let Some(title) = value.get("title").and_then(Value::as_str) {
                    parsed.title = clean_text(title);
                }
            }
            "message" => {
                if let Some(message) = value.get("message") {
                    let role = message.get("role").and_then(Value::as_str).unwrap_or("");
                    let text = content_text(message.get("content"));
                    if role == "user" && first_user_text.is_empty() && good_title(&text) {
                        first_user_text = text;
                    }
                }
            }
            _ => {}
        }
    }

    for line in tail.lines() {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let timestamp = iso_ms(value.get("timestamp").and_then(Value::as_str)).unwrap_or(0);
        if timestamp > 0 {
            last_timestamp = last_timestamp.max(timestamp);
        }
        match value.get("type").and_then(Value::as_str).unwrap_or("") {
            "session" => {
                if let Some(id) = value.get("id").and_then(Value::as_str) {
                    parsed.session_id = id.to_string();
                }
                if let Some(cwd) = value.get("cwd").and_then(Value::as_str) {
                    parsed.cwd = Some(cwd.to_string());
                }
            }
            "title" => {
                if let Some(title) = value.get("title").and_then(Value::as_str) {
                    parsed.title = clean_text(title);
                }
            }
            "message" => {
                let Some(message) = value.get("message") else {
                    continue;
                };
                let role = message.get("role").and_then(Value::as_str).unwrap_or("");
                let text = content_text(message.get("content"));
                match role {
                    "user" => {
                        last_role = "user";
                        last_user_ms = timestamp;
                        if first_user_text.is_empty() && good_title(&text) {
                            first_user_text = text;
                        }
                    }
                    "toolResult" | "tool_result" => {
                        last_role = "toolResult";
                    }
                    "assistant" => {
                        last_role = "assistant";
                        last_assistant_ms = timestamp;
                        last_has_tool = has_tool_call(message);
                        if !text.trim().is_empty() {
                            last_assistant_text = text;
                        }
                    }
                    _ => {}
                }
            }
            _ => {}
        }
    }

    if last_timestamp > 0 {
        parsed.last_active_ms = last_timestamp.max(modified);
    }
    if last_role == "assistant" {
        parsed.running = true;
        parsed.final_turn = !last_has_tool;
        parsed.ended_at_ms = last_assistant_ms.max(last_timestamp);
        parsed.duration_ms = if last_user_ms > 0 && parsed.ended_at_ms > last_user_ms {
            Some(parsed.ended_at_ms - last_user_ms)
        } else {
            None
        };
    } else if matches!(last_role, "user" | "toolResult") {
        parsed.running = true;
    } else {
        parsed.running = now.saturating_sub(modified) < 60_000;
    }

    if parsed.title.is_empty() {
        parsed.title = if !first_user_text.is_empty() {
            truncate_chars(&clean_text(&first_user_text), 40)
        } else {
            parsed
                .cwd
                .as_deref()
                .and_then(base_name)
                .unwrap_or_else(|| "Pi".to_string())
        };
    }
    if parsed.started_at_ms == 0 {
        parsed.started_at_ms = if last_user_ms > 0 {
            last_user_ms
        } else {
            parsed.ended_at_ms
        };
    }
    parsed.reply = preview(&last_assistant_text);
    parsed
}

fn parse_codex_file(path: &Path, now: u64, modified: u64) -> Parsed {
    let Some(text) = read_text(path) else {
        return Parsed::default();
    };
    if text.len() > 64 * 1024 * 1024 {
        return Parsed::default();
    }

    let mut parsed = Parsed {
        session_id: file_session_id(path),
        last_active_ms: modified,
        ..Parsed::default()
    };
    let mut first_user_text = String::new();
    let mut last_assistant_text = String::new();
    let mut last_timestamp = 0;

    for line in text.lines() {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let timestamp = iso_ms(value.get("timestamp").and_then(Value::as_str)).unwrap_or(0);
        if timestamp > 0 {
            last_timestamp = last_timestamp.max(timestamp);
        }
        match value.get("type").and_then(Value::as_str).unwrap_or("") {
            "session_meta" => {
                let payload = value.get("payload").unwrap_or(&Value::Null);
                if let Some(id) = payload
                    .get("session_id")
                    .or_else(|| payload.get("id"))
                    .and_then(Value::as_str)
                {
                    parsed.session_id = id.to_string();
                }
                if let Some(cwd) = payload.get("cwd").and_then(Value::as_str) {
                    parsed.cwd = Some(cwd.to_string());
                }
                if let Some(ts) = iso_ms(payload.get("timestamp").and_then(Value::as_str)) {
                    parsed.started_at_ms = ts;
                }
            }
            "event_msg" => {
                let payload = value.get("payload").unwrap_or(&Value::Null);
                match payload.get("type").and_then(Value::as_str).unwrap_or("") {
                    "task_started" => {
                        parsed.running = true;
                        parsed.waiting = false;
                        parsed.aborted = false;
                        parsed.ended_at_ms = 0;
                        parsed.duration_ms = None;
                        parsed.started_at_ms = payload
                            .get("started_at")
                            .and_then(Value::as_u64)
                            .map(|seconds| seconds.saturating_mul(1000))
                            .unwrap_or(timestamp);
                    }
                    "task_complete" => {
                        parsed.running = false;
                        parsed.ended_at_ms = timestamp;
                        parsed.duration_ms = if timestamp > parsed.started_at_ms {
                            Some(timestamp - parsed.started_at_ms)
                        } else {
                            None
                        };
                    }
                    "turn_aborted" => {
                        parsed.running = false;
                        parsed.aborted = true;
                        parsed.ended_at_ms = timestamp;
                        parsed.duration_ms = if timestamp > parsed.started_at_ms {
                            Some(timestamp - parsed.started_at_ms)
                        } else {
                            None
                        };
                    }
                    "item_completed" => {
                        let item = payload.get("item").unwrap_or(&Value::Null);
                        let kind = item.get("type").and_then(Value::as_str).unwrap_or("");
                        let text = content_text(item.get("content"));
                        if kind == "UserMessage"
                            && first_user_text.is_empty()
                            && good_title(&text)
                        {
                            first_user_text = text;
                        } else if kind == "AgentMessage" && !text.trim().is_empty() {
                            parsed.waiting = false;
                            last_assistant_text = text;
                        }
                    }
                    _ => {}
                }
            }
            "response_item" => {
                let payload = value.get("payload").unwrap_or(&Value::Null);
                match payload.get("type").and_then(Value::as_str).unwrap_or("") {
                    "message" => {
                        let role = payload.get("role").and_then(Value::as_str).unwrap_or("");
                        let text = content_text(payload.get("content"));
                        if role == "user" && first_user_text.is_empty() && good_title(&text) {
                            first_user_text = text;
                        } else if role == "assistant" && !text.trim().is_empty() {
                            parsed.waiting = false;
                            last_assistant_text = text;
                        }
                    }
                    "function_call" => {
                        if payload.get("name").and_then(Value::as_str)
                            == Some("request_user_input")
                            && parsed.running
                        {
                            parsed.waiting = true;
                        }
                    }
                    _ => {}
                }
            }
            _ => {}
        }
    }

    if last_timestamp > 0 {
        parsed.last_active_ms = last_timestamp.max(modified);
    }
    if parsed.started_at_ms == 0 {
        parsed.started_at_ms = last_timestamp;
    }
    if parsed.running && now.saturating_sub(modified) > STALE_RUNNING_MS {
        parsed.running = false;
        parsed.aborted = true;
        parsed.ended_at_ms = last_timestamp;
    }
    if parsed.title.is_empty() {
        parsed.title = if !first_user_text.is_empty() {
            truncate_chars(&clean_text(&first_user_text), 40)
        } else {
            parsed
                .cwd
                .as_deref()
                .and_then(base_name)
                .unwrap_or_else(|| "Codex".to_string())
        };
    }
    if !parsed.running && parsed.ended_at_ms == 0 {
        parsed.ended_at_ms = last_timestamp;
    }
    parsed.reply = preview(&last_assistant_text);
    parsed
}

fn parse_dsh_file(path: &Path, now: u64, modified: u64) -> Parsed {
    let Some(text) = read_text(path) else {
        return Parsed::default();
    };
    if text.len() > 64 * 1024 * 1024 {
        return Parsed::default();
    }

    let mut parsed = Parsed {
        session_id: file_session_id(path),
        last_active_ms: modified,
        ..Parsed::default()
    };
    let mut first_user_text = String::new();
    let mut last_assistant_text = String::new();
    let mut last_timestamp = 0;

    for line in text.lines() {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            // 部分实现会在 JSONL 中混入纯文本事件，按关键字兜底。
            if line.contains("turn/start") || line.contains("turn_start") {
                parsed.running = true;
            }
            if line.contains("turn/end") || line.contains("turn_end") {
                parsed.running = false;
            }
            continue;
        };
        let mut timestamp = iso_ms(value.get("timestamp").and_then(Value::as_str)).unwrap_or(0);
        if timestamp == 0 {
            timestamp = value.get("time").and_then(Value::as_u64).unwrap_or(0);
            if timestamp > 0 && timestamp < 10_000_000_000 {
                timestamp = timestamp.saturating_mul(1000);
            }
        }
        if timestamp > 0 {
            last_timestamp = last_timestamp.max(timestamp);
        }

        let event = value
            .get("event")
            .and_then(Value::as_str)
            .or_else(|| {
                value
                    .get("payload")
                    .and_then(|payload| payload.get("type"))
                    .and_then(Value::as_str)
            })
            .or_else(|| value.get("type").and_then(Value::as_str))
            .unwrap_or("");

        if let Some(cwd) = value.get("cwd").and_then(Value::as_str) {
            parsed.cwd = Some(cwd.to_string());
        }
        if let Some(id) = value
            .get("sessionId")
            .or_else(|| value.get("session_id"))
            .and_then(Value::as_str)
        {
            parsed.session_id = id.to_string();
        }
        if event.contains("session/title") || event == "title" {
            if let Some(title) = value
                .get("title")
                .and_then(Value::as_str)
                .or_else(|| {
                    value
                        .get("payload")
                        .and_then(|payload| payload.get("title"))
                        .and_then(Value::as_str)
                })
            {
                parsed.title = clean_text(title);
            }
        }
        if event.contains("turn/start") || event == "turn_start" {
            parsed.running = true;
            parsed.started_at_ms = timestamp;
            parsed.waiting = false;
        }
        if event.contains("turn/end") || event == "turn_end" {
            parsed.running = false;
            parsed.ended_at_ms = timestamp;
            parsed.duration_ms = if timestamp > parsed.started_at_ms {
                Some(timestamp - parsed.started_at_ms)
            } else {
                None
            };
        }

        let role = value
            .get("role")
            .and_then(Value::as_str)
            .or_else(|| {
                value
                    .get("payload")
                    .and_then(|payload| payload.get("role"))
                    .and_then(Value::as_str)
            });
        let text = value
            .get("text")
            .and_then(Value::as_str)
            .or_else(|| value.get("content").and_then(Value::as_str))
            .or_else(|| {
                value
                    .get("message")
                    .and_then(|message| message.get("content"))
                    .and_then(Value::as_str)
            })
            .unwrap_or("");
        if !text.is_empty() {
            if role == Some("assistant") {
                last_assistant_text = text.to_string();
            }
            if role == Some("user") && first_user_text.is_empty() && good_title(text) {
                first_user_text = text.to_string();
            }
        }
    }

    if parsed.started_at_ms == 0 {
        parsed.started_at_ms = last_timestamp;
    }
    if parsed.running && now.saturating_sub(modified) > STALE_RUNNING_MS {
        parsed.running = false;
        parsed.aborted = true;
        parsed.ended_at_ms = last_timestamp;
    }
    if parsed.title.is_empty() {
        parsed.title = if !first_user_text.is_empty() {
            truncate_chars(&clean_text(&first_user_text), 40)
        } else if !parsed.session_id.is_empty() {
            parsed.session_id.clone()
        } else {
            "DeepSeek Harness".to_string()
        };
    }
    if !parsed.running && parsed.ended_at_ms == 0 {
        parsed.ended_at_ms = last_timestamp;
    }
    parsed.reply = preview(&last_assistant_text);
    parsed
}

fn transcript_title(text: &str) -> Option<String> {
    let mut title = None;
    for line in text.lines() {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        match value.get("type").and_then(Value::as_str).unwrap_or("") {
            "ai-title" => {
                if let Some(text) = value.get("aiTitle").and_then(Value::as_str) {
                    let text = clean_text(text);
                    if !text.is_empty() {
                        title = Some(text);
                    }
                }
            }
            "custom-title" => {
                if let Some(text) = value
                    .get("customTitle")
                    .and_then(Value::as_str)
                    .or_else(|| value.get("title").and_then(Value::as_str))
                {
                    let text = clean_text(text);
                    if !text.is_empty() {
                        title = Some(text);
                    }
                }
            }
            _ => {}
        }
    }
    title
}

fn claude_transcript(session_id: &str, cwd: Option<&str>) -> Option<PathBuf> {
    let home = home_dir()?;
    let base = env_root("CLAUDE_CONFIG_DIR", home.join(".claude"))
        .join("projects");
    if let Some(cwd) = cwd {
        let slug = cwd.replace(':', "-").replace('\\', "-").replace('/', "-");
        let candidate = base.join(slug).join(format!("{session_id}.jsonl"));
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    let entries = fs::read_dir(&base).ok()?;
    for entry in entries.flatten() {
        let candidate = entry.path().join(format!("{session_id}.jsonl"));
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn read_text(path: &Path) -> Option<String> {
    if path.extension().and_then(|value| value.to_str()) == Some("zst") {
        let file = File::open(path).ok()?;
        let decoder = zstd::stream::read::Decoder::new(file).ok()?;
        let mut reader = decoder.take(64 * 1024 * 1024);
        let mut bytes = Vec::new();
        // 活跃会话的 zstd 尾部可能还没有写完；保留已经解出的有效前缀。
        let _ = reader.read_to_end(&mut bytes);
        if bytes.is_empty() {
            return None;
        }
        Some(String::from_utf8_lossy(&bytes).into_owned())
    } else {
        fs::read_to_string(path).ok()
    }
}

fn read_head(path: &Path, max: u64) -> Option<String> {
    let file = File::open(path).ok()?;
    let mut reader = file.take(max);
    let mut bytes = Vec::new();
    reader.read_to_end(&mut bytes).ok()?;
    Some(String::from_utf8_lossy(&bytes).into_owned())
}

fn read_tail(path: &Path, max: u64) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let len = file.metadata().ok()?.len();
    let start = len.saturating_sub(max);
    if start > 0 {
        file.seek(SeekFrom::Start(start)).ok()?;
    }
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes).ok()?;
    let mut text = String::from_utf8_lossy(&bytes).into_owned();
    if start > 0 {
        if let Some(position) = text.find('\n') {
            text.drain(..=position);
        }
    }
    Some(text)
}

fn collect_files(
    root: &Path,
    depth: usize,
    out: &mut Vec<PathBuf>,
    file_min_mtime: u64,
    directory_min_mtime: u64,
) {
    if depth == 0 {
        return;
    }
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = entry.metadata() else {
            continue;
        };
        let modified = meta
            .modified()
            .ok()
            .map(system_time_ms)
            .unwrap_or(0);
        if meta.is_dir() {
            if directory_min_mtime > 0 && modified > 0 && modified < directory_min_mtime {
                continue;
            }
            collect_files(
                &path,
                depth - 1,
                out,
                file_min_mtime,
                directory_min_mtime,
            );
        } else if meta.is_file() && modified >= file_min_mtime {
            out.push(path);
        }
    }
}

fn content_text(value: Option<&Value>) -> String {
    let Some(value) = value else {
        return String::new();
    };
    if let Some(text) = value.as_str() {
        return text.to_string();
    }
    let Some(items) = value.as_array() else {
        return String::new();
    };
    let mut parts = Vec::new();
    for item in items {
        if let Some(text) = item.get("text").and_then(Value::as_str) {
            parts.push(text);
        }
    }
    parts.join(" ")
}

fn has_tool_call(message: &Value) -> bool {
    message
        .get("content")
        .and_then(Value::as_array)
        .is_some_and(|items| {
            items.iter().any(|item| {
                matches!(
                    item.get("type").and_then(Value::as_str),
                    Some("toolCall") | Some("tool_call")
                )
            })
        })
}

fn good_title(text: &str) -> bool {
    let text = text.trim();
    !text.is_empty()
        && !text.starts_with("<environment_context")
        && !text.starts_with("<permissions instructions")
        && !text.starts_with("<user_instructions")
        && !text.starts_with("<system")
        && !(text.starts_with('<') && text.ends_with('>'))
}

fn preview(text: &str) -> Option<String> {
    let text = clean_text(text);
    if text.is_empty() {
        None
    } else {
        Some(truncate_chars(&text, 200))
    }
}

fn clean_text(text: &str) -> String {
    let mut out = String::new();
    let mut space = false;
    for character in text.chars() {
        if character.is_whitespace() {
            space = true;
        } else {
            if space && !out.is_empty() {
                out.push(' ');
            }
            space = false;
            out.push(character);
        }
    }
    out.trim().to_string()
}

fn truncate_chars(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    let mut out: String = text.chars().take(max).collect();
    out.push('…');
    out
}

fn file_session_id(path: &Path) -> String {
    let stem = path.file_name().and_then(|value| value.to_str()).unwrap_or("");
    let stem = stem.strip_suffix(".jsonl.zst").unwrap_or(stem);
    let stem = stem.strip_suffix(".jsonl").unwrap_or(stem);
    stem.rsplit('_').next().unwrap_or(stem).to_string()
}

fn base_name(path: &str) -> Option<String> {
    Path::new(path)
        .file_name()
        .and_then(|value| value.to_str())
        .map(str::to_string)
}

fn iso_ms(value: Option<&str>) -> Option<u64> {
    let value = value?;
    chrono::DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|time| time.timestamp_millis().max(0) as u64)
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("USERPROFILE")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from)
}

fn env_root(key: &str, fallback: PathBuf) -> PathBuf {
    std::env::var_os(key).map(PathBuf::from).unwrap_or(fallback)
}

fn now_ms() -> u64 {
    system_time_ms(SystemTime::now())
}

fn system_time_ms(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(windows)]
fn process_alive(pid: u32) -> bool {
    use windows::Win32::Foundation::{CloseHandle, FALSE};
    use windows::Win32::System::Threading::{
        GetExitCodeProcess, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
    };

    unsafe {
        let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid) else {
            return false;
        };
        let mut code = 0u32;
        let ok = GetExitCodeProcess(handle, &mut code).is_ok();
        let _ = CloseHandle(handle);
        ok && code == 259
    }
}

#[cfg(not(windows))]
fn process_alive(_pid: u32) -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn process_alive_sees_current_process() {
        assert!(process_alive(std::process::id()));
    }

    #[test]
    fn clean_text_collapses_whitespace() {
        assert_eq!(clean_text("  a\n\tb  c "), "a b c");
    }

    #[test]
    fn preview_truncates_long_text() {
        let text = "a".repeat(250);
        let value = preview(&text).unwrap();
        assert_eq!(value.chars().count(), 201);
        assert!(value.ends_with('…'));
    }

    #[test]
    fn file_session_id_handles_pi_and_codex_names() {
        let pi = Path::new(
            "2026-11-17T01-50-18-561Z_01a1e732-a5c0-774a-983e-9d57e1e57175.jsonl",
        );
        assert_eq!(
            file_session_id(pi),
            "01a1e732-a5c0-774a-983e-9d57e1e57175"
        );
        let codex = Path::new(
            "rollout-2026-10-17T21-42-21-01a14a19-66d3-7f73-9a85-8fde2e68cc09.jsonl.zst",
        );
        assert_eq!(
            file_session_id(codex),
            "rollout-2026-10-17T21-42-21-01a14a19-66d3-7f73-9a85-8fde2e68cc09"
        );
    }

    #[test]
    fn title_filter_skips_environment_context() {
        assert!(!good_title("<environment_context>\n<cwd>x</cwd>\n</environment_context>"));
        assert!(good_title("把设置页的 AI 额度改成 AI"));
    }

    #[test]
    fn parse_pi_finds_title_and_final_reply() {
        let path = temp_path("gudong-pi-test");
        let text = [
            r#"{"type":"session","version":3,"id":"01a1e732-a5c0-774a-983e-9d57e1e57175","timestamp":"2026-11-17T01:50:18.561Z","cwd":"F:\\My_Project\\guduo"}"#,
            r#"{"type":"title","title":"修复邮件视图返回与复制问题","source":"auto"}"#,
            r#"{"type":"message","timestamp":"2026-11-17T01:51:00.000Z","message":{"role":"user","content":[{"type":"text","text":"修一下返回手势"}]}}"#,
            r#"{"type":"message","timestamp":"2026-11-17T01:52:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"已补上返回手势，并修复复制为空的问题。"}]}}"#,
        ]
        .join("\n");
        fs::write(&path, text).unwrap();
        let parsed = parse_pi_file(
            &path,
            1_800_000_000_000,
            file_ms(&path),
        );
        let _ = fs::remove_file(&path);
        assert_eq!(parsed.session_id, "01a1e732-a5c0-774a-983e-9d57e1e57175");
        assert_eq!(parsed.title, "修复邮件视图返回与复制问题");
        assert!(parsed.final_turn);
        assert!(parsed.reply.unwrap().contains("返回手势"));
    }

    #[test]
    fn parse_codex_marks_completed_turn() {
        let path = temp_path("gudong-codex-test.jsonl");
        let text = [
            r#"{"timestamp":"2026-11-22T05:00:00.000Z","type":"session_meta","payload":{"session_id":"s1","cwd":"F:\\My_Project\\guduo"}}"#,
            r#"{"timestamp":"2026-11-22T05:00:01.000Z","type":"event_msg","payload":{"type":"task_started","started_at":1795323601}}"#,
            r#"{"timestamp":"2026-11-22T05:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"加一个 agent 检测"}]}}"#,
            r#"{"timestamp":"2026-11-22T05:00:03.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"已加上 agent 检测模块。"}]}}"#,
            r#"{"timestamp":"2026-11-22T05:00:04.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#,
        ]
        .join("\n");
        fs::write(&path, text).unwrap();
        let parsed = parse_codex_file(&path, 1_800_000_000_000, file_ms(&path));
        let _ = fs::remove_file(&path);
        assert_eq!(parsed.session_id, "s1");
        assert_eq!(parsed.title, "加一个 agent 检测");
        assert!(!parsed.running);
        assert!(parsed.reply.unwrap().contains("agent 检测模块"));
        assert!(parsed.duration_ms.unwrap() > 0);
    }

    fn temp_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("{name}-{}.tmp", std::process::id()))
    }

    fn file_ms(path: &Path) -> u64 {
        fs::metadata(path)
            .and_then(|meta| meta.modified())
            .ok()
            .map(system_time_ms)
            .unwrap_or(0)
    }
}
