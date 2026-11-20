//! 邮件同步：账号 worker、增量收取与内存缓存。
//!
//! 每个启用的账号一个 worker，持有自己的 IMAP 连接，按 `mailPollSeconds`
//! 轮询新邮件。缓存只在内存里保留每个账号最近 20 封（含正文），不落盘。

use imap::types::Flag;
use imap_proto::types::{BodyContentCommon, BodyStructure, ContentEncoding, SectionPath};
use serde::Serialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use super::{net, parse, store};
use crate::credentials;
use crate::rpc::{self, RpcError, State, ERR_INTERNAL, ERR_INVALID_PARAMS, ERR_METHOD_NOT_FOUND};

const RECENT_LIMIT: usize = 20;
const NEW_PER_CYCLE: usize = 5;
const MAX_PART_BYTES: u32 = 256 * 1024;
const FALLBACK_BYTES: u32 = 512 * 1024;

pub struct Job {
    pub id: Value,
    pub method: String,
    pub params: Value,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MailSummary {
    pub id: String,
    pub account_id: String,
    pub from: String,
    pub from_address: String,
    pub subject: String,
    pub received_at: i64,
    pub unread: bool,
    pub snippet: String,
    pub has_attachments: bool,
}

#[derive(Clone, Serialize)]
pub struct MailDetail {
    #[serde(flatten)]
    pub summary: MailSummary,
    pub text: String,
    pub truncated: bool,
    pub links: Vec<parse::Link>,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountView {
    pub id: String,
    pub provider: store::Provider,
    pub email: String,
    pub label: Option<String>,
    pub auth_type: store::AuthType,
    pub enabled: bool,
    pub custom: Option<store::CustomImap>,
    pub webmail_url: String,
    pub state: String,
    pub message: String,
    pub last_sync_at: Option<i64>,
    pub reauth_required: bool,
}

#[derive(Clone)]
struct CachedMail {
    summary: MailSummary,
    text: String,
    truncated: bool,
    links: Vec<parse::Link>,
}

impl CachedMail {
    fn detail(&self) -> MailDetail {
        MailDetail {
            summary: self.summary.clone(),
            text: self.text.clone(),
            truncated: self.truncated,
            links: self.links.clone(),
        }
    }
}

struct Runtime {
    account: store::Account,
    state: String,
    message: String,
    last_sync_at: Option<i64>,
    reauth_required: bool,
}

struct Shared {
    runtimes: Vec<Runtime>,
    cache: HashMap<String, Vec<CachedMail>>,
}

type SharedRef = Arc<Mutex<Shared>>;

enum WorkerCmd {
    PollNow,
    Stop,
}

enum FetchFailure {
    /// 服务器拒绝了这一封邮件，连接仍可用，跳过继续。
    Skip,
    /// 响应没读完或连接已断，必须退出本次连接。
    Reconnect,
    /// FETCH 响应无法解析；连接可能已失步，重连后改用整封正文兜底。
    Parse,
}

pub fn start(state: Arc<State>, tx: Sender<Value>) -> Sender<Job> {
    let (job_tx, job_rx) = mpsc::channel::<Job>();
    let _ = std::thread::Builder::new()
        .name("mail".into())
        .spawn(move || {
            let mut store = store::Store::load();
            let shared: SharedRef = Arc::new(Mutex::new(Shared::new(store.accounts().to_vec())));
            let mut workers: HashMap<String, Sender<WorkerCmd>> = HashMap::new();
            for account in store.accounts().iter().filter(|account| account.enabled).cloned() {
                let worker = spawn_worker(
                    account.clone(),
                    shared.clone(),
                    tx.clone(),
                    state.clone(),
                );
                workers.insert(account.id, worker);
            }

            while let Ok(job) = job_rx.recv() {
                handle(&job, &mut store, &shared, &mut workers, &tx, &state);
            }

            for worker in workers.values() {
                let _ = worker.send(WorkerCmd::Stop);
            }
        });
    job_tx
}

fn handle(
    job: &Job,
    store: &mut store::Store,
    shared: &SharedRef,
    workers: &mut HashMap<String, Sender<WorkerCmd>>,
    tx: &Sender<Value>,
    state: &Arc<State>,
) {
    let result = match job.method.as_str() {
        "mail.accounts.list" => Ok(json!({
            "accounts": lock(shared).views(),
        })),
        "mail.accounts.add" => add_account(job, store, shared, workers, tx, state),
        "mail.accounts.update" => update_account(job, store, shared, tx),
        "mail.accounts.remove" => remove_account(job, store, shared, workers),
        "mail.list" => list_mail(job, shared),
        "mail.get" => get_mail(job, shared),
        "mail.refresh" => refresh(job, workers),
        "mail.markSeen" => mark_seen(job, store, shared),
        "mail.oauth.begin" => Err(RpcError::new(
            ERR_INTERNAL,
            "微软 OAuth 尚未配置 client_id",
        )),
        "mail.oauth.cancel" => Ok(json!({ "ok": true })),
        other => Err(RpcError::new(
            ERR_METHOD_NOT_FOUND,
            format!("method not found: {other}"),
        )),
    };
    let line = match result {
        Ok(value) => rpc::response(&job.id, value),
        Err(error) => rpc::error(&job.id, error),
    };
    let _ = tx.send(line);
}

fn add_account(
    job: &Job,
    store: &mut store::Store,
    shared: &SharedRef,
    workers: &mut HashMap<String, Sender<WorkerCmd>>,
    tx: &Sender<Value>,
    state: &Arc<State>,
) -> Result<Value, RpcError> {
    let params = &job.params;
    let provider_key = params
        .get("provider")
        .and_then(Value::as_str)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "provider is required"))?;
    let provider = store::Provider::parse(provider_key)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "unknown mail provider"))?;
    if provider.needs_oauth() {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            "微软邮箱请使用 mail.oauth.begin 登录",
        ));
    }
    let email = params
        .get("email")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| valid_email(value))
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "email is invalid"))?
        .to_string();
    if provider == store::Provider::ICloud && !is_apple_mail(&email) {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            "iCloud 只支持 @icloud.com、@me.com 或 @mac.com 邮箱",
        ));
    }
    let password = params
        .get("password")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "password is required"))?
        .to_string();
    let label = params
        .get("label")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string);
    let custom = if provider == store::Provider::Custom {
        let custom = params
            .get("custom")
            .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "custom is required"))?;
        let host = custom
            .get("host")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        let port = custom
            .get("port")
            .and_then(Value::as_u64)
            .unwrap_or(993)
            .try_into()
            .map_err(|_| RpcError::new(ERR_INVALID_PARAMS, "port is invalid"))?;
        let username = custom
            .get("username")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        Some(store::CustomImap {
            host,
            port,
            username,
        })
    } else {
        None
    };

    let mut account = store::Account {
        id: String::new(),
        provider,
        email,
        label,
        auth_type: store::AuthType::Password,
        enabled: true,
        custom,
        webmail_url: None,
    };
    account.endpoint().map_err(|message| {
        RpcError::new(ERR_INVALID_PARAMS, format!("invalid account: {message}"))
    })?;

    let identity = store::identity(&account);
    let existing = store
        .accounts()
        .iter()
        .find(|existing| store::identity(existing) == identity)
        .cloned();
    account.id = existing
        .as_ref()
        .map(|existing| existing.id.clone())
        .unwrap_or_else(|| {
            let taken: Vec<String> = store
                .accounts()
                .iter()
                .map(|account| account.id.clone())
                .collect();
            store::new_id(provider, &account.email, &taken)
        });

    credentials::write(&store::credential_target(&account.id), &password)
        .map_err(|message| RpcError::new(ERR_INTERNAL, format!("保存凭据失败：{message}")))?;
    if let Err(message) = store.upsert(account.clone()) {
        if existing.is_none() {
            let _ = credentials::delete(&store::credential_target(&account.id));
        }
        return Err(RpcError::new(
            ERR_INTERNAL,
            format!("保存账号失败：{message}"),
        ));
    }

    let view = {
        let mut shared = lock(shared);
        shared.upsert_runtime(account.clone());
        shared
            .view_for(&account.id)
            .expect("account exists after upsert")
    };

    if let Some(old) = workers.remove(&account.id) {
        let _ = old.send(WorkerCmd::Stop);
    }
    let worker = spawn_worker(account.clone(), shared.clone(), tx.clone(), state.clone());
    workers.insert(account.id.clone(), worker);

    Ok(json!({ "account": view }))
}

fn update_account(
    job: &Job,
    store: &mut store::Store,
    shared: &SharedRef,
    tx: &Sender<Value>,
) -> Result<Value, RpcError> {
    let id = job
        .params
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "id is required"))?;
    let Some(label_raw) = job.params.get("label").and_then(Value::as_str) else {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "label is required"));
    };
    let label = {
        let trimmed = label_raw.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    };
    let account = store
        .update_label(id, label.clone())
        .map_err(|message| {
            if message == "account not found" {
                RpcError::new(ERR_INVALID_PARAMS, message)
            } else {
                RpcError::new(ERR_INTERNAL, format!("保存邮箱别名失败：{message}"))
            }
        })?;

    let view = {
        let mut shared = lock(shared);
        shared.update_label(&account.id, label)
    };
    if let Some(view) = &view {
        let _ = tx.send(rpc::event(json!({
            "type": "mail.account",
            "account": view,
        })));
    }
    Ok(json!({ "account": view }))
}

fn remove_account(
    job: &Job,
    store: &mut store::Store,
    shared: &SharedRef,
    workers: &mut HashMap<String, Sender<WorkerCmd>>,
) -> Result<Value, RpcError> {
    let id = job
        .params
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "id is required"))?;
    let removed = store.remove(id).map_err(|message| {
        if message == "account not found" {
            RpcError::new(ERR_INVALID_PARAMS, message)
        } else {
            RpcError::new(ERR_INTERNAL, format!("删除账号失败：{message}"))
        }
    })?;
    let _ = credentials::delete(&store::credential_target(&removed.id));
    {
        // 先移除运行时和缓存，再通知 worker 停止；避免在途请求把已删除账号写回来。
        let mut shared = lock(shared);
        shared.runtimes.retain(|runtime| runtime.account.id != removed.id);
        shared.cache.remove(&removed.id);
    }
    if let Some(worker) = workers.remove(&removed.id) {
        let _ = worker.send(WorkerCmd::Stop);
    }
    Ok(json!({ "ok": true }))
}

fn list_mail(job: &Job, shared: &SharedRef) -> Result<Value, RpcError> {
    let account_id = job.params.get("accountId").and_then(Value::as_str);
    let limit = job
        .params
        .get("limit")
        .and_then(Value::as_u64)
        .unwrap_or(RECENT_LIMIT as u64)
        .clamp(1, RECENT_LIMIT as u64) as usize;
    let unread_only = job
        .params
        .get("unreadOnly")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let shared = lock(shared);
    let items = shared.list(account_id, limit, unread_only);
    let accounts = shared.views();
    Ok(json!({ "items": items, "accounts": accounts }))
}

fn get_mail(job: &Job, shared: &SharedRef) -> Result<Value, RpcError> {
    let id = job
        .params
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "id is required"))?;
    lock(shared)
        .get(id)
        .map(|item| json!({ "item": item }))
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "邮件正文尚未缓存"))
}

fn refresh(job: &Job, workers: &HashMap<String, Sender<WorkerCmd>>) -> Result<Value, RpcError> {
    let account_id = job.params.get("accountId").and_then(Value::as_str);
    for (id, worker) in workers {
        if account_id.map_or(true, |wanted| wanted == id) {
            let _ = worker.send(WorkerCmd::PollNow);
        }
    }
    Ok(json!({ "ok": true }))
}

fn is_apple_mail(email: &str) -> bool {
    let lower = email.trim().to_ascii_lowercase();
    ["@icloud.com", "@me.com", "@mac.com"]
        .iter()
        .any(|suffix| lower.ends_with(suffix))
}

fn mark_seen(
    job: &Job,
    store: &store::Store,
    shared: &SharedRef,
) -> Result<Value, RpcError> {
    if let Some(id) = job.params.get("id").and_then(Value::as_str) {
        let Some((account_id, validity, uid)) = parse_mail_id(id) else {
            return Err(RpcError::new(ERR_INVALID_PARAMS, "invalid mail id"));
        };
        let Some(account) = store
            .accounts()
            .iter()
            .find(|account| account.id == account_id)
            .cloned()
        else {
            return Err(RpcError::new(ERR_INVALID_PARAMS, "account not found"));
        };
        let marked = match mark_account_seen(&account, Some(&[uid]), Some(validity)) {
            Ok(count) => count,
            Err(message) => {
                log_error(&account, &format!("mark seen failed: {message}"));
                return Err(RpcError::new(ERR_INTERNAL, message));
            }
        };
        lock(shared).mark_one_read(id);
        return Ok(json!({ "ok": true, "marked": marked, "message": "" }));
    }

    let account_id = job.params.get("accountId").and_then(Value::as_str);
    let accounts: Vec<store::Account> = store
        .accounts()
        .iter()
        .filter(|account| account.enabled && account_id.map_or(true, |id| account.id == id))
        .cloned()
        .collect();
    if accounts.is_empty() {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "account not found"));
    }

    let mut marked = 0usize;
    let mut failures = Vec::new();
    for account in accounts {
        // 不用服务器 UNSEEN SEARCH：部分服务（例如 2925）会错误地返回空集。
        // 以缓存里 UI 正在显示的未读 UID 为准，STORE 本身是幂等的。
        let cached = lock(shared).unread_uids(&account.id);
        let uids = if cached.is_empty() {
            None
        } else {
            Some(cached.as_slice())
        };
        match mark_account_seen(&account, uids, None) {
            Ok(count) => {
                marked += count;
                lock(shared).mark_all_read(&account.id);
            }
            Err(message) => {
                log_error(&account, &format!("mark seen failed: {message}"));
                failures.push(format!("{}: {message}", account.id));
            }
        }
    }

    Ok(json!({
        "ok": failures.is_empty(),
        "marked": marked,
        "message": failures.join("；"),
    }))
}

fn parse_mail_id(id: &str) -> Option<(String, u32, u32)> {
    let mut parts = id.splitn(4, ':');
    if parts.next()? != "mail" {
        return None;
    }
    let account_id = parts.next()?.to_string();
    let validity = parts.next()?.parse().ok()?;
    let uid = parts.next()?.parse().ok()?;
    Some((account_id, validity, uid))
}

/// 标已读使用独立短连接，避免和常驻收信 worker 争用同一条会话。
/// `uids` 为 `None` 时标记该账号所有未读邮件。
fn mark_account_seen(
    account: &store::Account,
    uids: Option<&[u32]>,
    expected_validity: Option<u32>,
) -> Result<usize, String> {
    let target = store::credential_target(&account.id);
    let secret = credentials::read(&target).ok_or_else(|| "没有可用的授权码".to_string())?;
    let mut session =
        net::connect(account, &secret).map_err(|error| error.message().to_string())?;

    let result = (|| -> Result<usize, String> {
        let mailbox = session
            .select("INBOX")
            .map_err(|error| format!("打开收件箱失败：{}", error_kind(&error)))?;
        if let Some(expected) = expected_validity.filter(|value| *value > 0) {
            if mailbox.uid_validity != Some(expected) {
                return Err("邮件列表已变化，请刷新后重试".into());
            }
        }
        let uids: Vec<u32> = match uids {
            Some(uids) => uids.to_vec(),
            None => session
                .uid_search("UNSEEN")
                .map_err(|error| format!("读取未读邮件失败：{}", error_kind(&error)))?
                .into_iter()
                .collect(),
        };
        if uids.is_empty() {
            return Ok(0);
        }
        let mut count = 0usize;
        for chunk in uids.chunks(200) {
            let set = chunk
                .iter()
                .map(u32::to_string)
                .collect::<Vec<_>>()
                .join(",");
            let updated = session
                .uid_store(set, "+FLAGS (\\Seen)")
                .map_err(|error| format!("标记已读失败：{}", error_kind(&error)))?;
            let confirmed = updated
                .iter()
                .filter(|fetch| {
                    fetch
                        .flags()
                        .iter()
                        .any(|flag| matches!(flag, Flag::Seen))
                })
                .count();
            if confirmed == 0 {
                return Err("服务器未确认已读标记".into());
            }
            count += confirmed;
        }
        // 少数服务器（例如 2925）需要一次 NOOP/CLOSE 才把标记落盘。
        let _ = session.noop();
        let _ = session.close();
        Ok(count)
    })();

    let _ = session.logout();
    if let Ok(count) = &result {
        log_line(account, &format!("mark seen: {count}"));
    }
    result
}

fn valid_email(email: &str) -> bool {
    let mut parts = email.split('@');
    let local = parts.next().unwrap_or_default();
    let domain = parts.next().unwrap_or_default();
    parts.next().is_none()
        && !local.is_empty()
        && !domain.is_empty()
        && domain.contains('.')
        && email.len() <= 254
        && !email.chars().any(char::is_whitespace)
}

fn spawn_worker(
    account: store::Account,
    shared: SharedRef,
    tx: Sender<Value>,
    state: Arc<State>,
) -> Sender<WorkerCmd> {
    let (cmd_tx, cmd_rx) = mpsc::channel();
    let name = format!("mail-{}", account.id);
    let _ = std::thread::Builder::new()
        .name(name)
        .spawn(move || worker(account, shared, tx, state, cmd_rx));
    cmd_tx
}

fn worker(
    account: store::Account,
    shared: SharedRef,
    tx: Sender<Value>,
    state: Arc<State>,
    cmd_rx: Receiver<WorkerCmd>,
) {
    let mut last_uid: Option<u32> = None;
    let mut last_validity: Option<u32> = None;
    let mut failures = 0u32;
    // 服务器 BODYSTRUCTURE 无法解析时，后续连接改用整封正文兜底。
    let mut legacy_fetch = false;

    loop {
        set_state(&shared, &account.id, "connecting", "正在连接", false, &tx);

        let target = store::credential_target(&account.id);
        let Some(secret) = credentials::read(&target) else {
            set_state(&shared, &account.id, "auth", "没有可用的授权码", true, &tx);
            if wait(&cmd_rx, backoff(&mut failures)) {
                return;
            }
            continue;
        };

        let mut session = match net::connect(&account, &secret) {
            Ok(session) => session,
            Err(error) => {
                let auth = error.is_auth();
                let state_name = if auth { "auth" } else { "failed" };
                log_line(&account, &format!("state={state_name}"));
                set_state(&shared, &account.id, state_name, error.message(), auth, &tx);
                if wait(&cmd_rx, backoff(&mut failures)) {
                    return;
                }
                continue;
            }
        };

        let mailbox = match session.examine("INBOX") {
            Ok(mailbox) => mailbox,
            Err(error) => {
                let _ = session.logout();
                log_error(&account, &format!("examine failed: {}", error_kind(&error)));
                set_state(&shared, &account.id, "failed", "无法打开收件箱", false, &tx);
                if wait(&cmd_rx, backoff(&mut failures)) {
                    return;
                }
                continue;
            }
        };
        let validity = mailbox.uid_validity.unwrap_or(0);
        if last_validity != Some(validity) {
            last_uid = None;
            last_validity = Some(validity);
        }

        let first_sync = last_uid.is_none();
        let result = if first_sync {
            recent(
                &mut session,
                &account,
                validity,
                mailbox.exists,
                legacy_fetch,
                &shared,
            )
            .map(|max| {
                last_uid = Some(max.unwrap_or(0));
            })
        } else {
            fetch_new(
                &mut session,
                &account,
                validity,
                &mut last_uid,
                legacy_fetch,
                &shared,
                &tx,
            )
        };

        if let Err(failure) = result {
            let _ = session.logout();
            if matches!(failure, FetchFailure::Parse) {
                legacy_fetch = true;
                log_line(&account, "legacy fetch enabled");
            }
            log_error(&account, "initial sync failed");
            set_state(&shared, &account.id, "failed", "读取邮件失败，正在重连", false, &tx);
            if wait(&cmd_rx, backoff(&mut failures)) {
                return;
            }
            continue;
        }

        failures = 0;
        mark_ready(&shared, &account.id, &tx);
        log_line(&account, "ready");

        let mut poll_interval =
            Duration::from_secs(state.config.u64("mailPollSeconds", 180).clamp(60, 900));
        let mut next_poll = Instant::now() + poll_interval;
        // 网易等服务器会在大约 3 分钟无命令时断开；45 秒 NOOP 保活。
        const KEEPALIVE: Duration = Duration::from_secs(45);
        loop {
            poll_interval =
                Duration::from_secs(state.config.u64("mailPollSeconds", 180).clamp(60, 900));
            let now = Instant::now();
            if now >= next_poll {
                match poll_once(
                    &mut session,
                    &account,
                    validity,
                    &mut last_uid,
                    legacy_fetch,
                    &shared,
                    &tx,
                ) {
                    Ok(()) => next_poll = Instant::now() + poll_interval,
                    Err(failure) => {
                        if matches!(failure, FetchFailure::Parse) {
                            legacy_fetch = true;
                            log_line(&account, "legacy fetch enabled");
                        }
                        break;
                    }
                }
                continue;
            }

            let wait = (next_poll - now).min(KEEPALIVE);
            match cmd_rx.recv_timeout(wait) {
                Ok(WorkerCmd::Stop) | Err(RecvTimeoutError::Disconnected) => {
                    let _ = session.logout();
                    return;
                }
                Ok(WorkerCmd::PollNow) => {
                    match poll_once(
                        &mut session,
                        &account,
                        validity,
                        &mut last_uid,
                        legacy_fetch,
                        &shared,
                        &tx,
                    ) {
                        Ok(()) => next_poll = Instant::now() + poll_interval,
                        Err(failure) => {
                            if matches!(failure, FetchFailure::Parse) {
                                legacy_fetch = true;
                                log_line(&account, "legacy fetch enabled");
                            }
                            break;
                        }
                    }
                }
                Err(RecvTimeoutError::Timeout) => {
                    if Instant::now() >= next_poll {
                        match poll_once(
                            &mut session,
                            &account,
                            validity,
                            &mut last_uid,
                            legacy_fetch,
                            &shared,
                            &tx,
                        ) {
                            Ok(()) => next_poll = Instant::now() + poll_interval,
                            Err(failure) => {
                                if matches!(failure, FetchFailure::Parse) {
                                    legacy_fetch = true;
                                    log_line(&account, "legacy fetch enabled");
                                }
                                break;
                            }
                        }
                    } else {
                        match session.noop() {
                            Ok(()) => {}
                            Err(error) if net::rejected(&error) => {}
                            Err(error) => {
                                log_error(
                                    &account,
                                    &format!("noop failed: {}", error_kind(&error)),
                                );
                                break;
                            }
                        }
                    }
                }
            }
        }

        let _ = session.logout();
        log_error(&account, "connection lost");
        set_state(&shared, &account.id, "failed", "邮件连接中断，正在重连", false, &tx);
        if wait(&cmd_rx, backoff(&mut failures)) {
            return;
        }
    }
}

fn poll_once(
    session: &mut net::MailSession,
    account: &store::Account,
    validity: u32,
    last_uid: &mut Option<u32>,
    legacy: bool,
    shared: &SharedRef,
    tx: &Sender<Value>,
) -> Result<(), FetchFailure> {
    fetch_new(session, account, validity, last_uid, legacy, shared, tx)?;
    refresh_flags(session, account, shared)
        .map_err(|_| FetchFailure::Reconnect)?;
    mark_ready(shared, &account.id, tx);
    Ok(())
}

/// 同步缓存邮件的已读标记，避免网页端或其他客户端改状态后本地长期显示未读。
fn refresh_flags(
    session: &mut net::MailSession,
    account: &store::Account,
    shared: &SharedRef,
) -> Result<(), ()> {
    let uids: Vec<u32> = {
        let shared = lock(shared);
        shared
            .cache
            .get(&account.id)
            .map(|cached| {
                cached
                    .iter()
                    .filter_map(|mail| parse_mail_id(&mail.summary.id).map(|(_, _, uid)| uid))
                    .collect()
            })
            .unwrap_or_default()
    };
    if uids.is_empty() {
        return Ok(());
    }
    let set = uids
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(",");
    let fetched = session.uid_fetch(set, "(UID FLAGS)").map_err(|error| {
        log_error(
            account,
            &format!("flag refresh failed: {}", error_kind(&error)),
        );
    })?;
    let flags: HashMap<u32, bool> = fetched
        .iter()
        .filter_map(|fetch| {
            let uid = fetch.uid?;
            let seen = fetch
                .flags()
                .iter()
                .any(|flag| matches!(flag, Flag::Seen));
            Some((uid, seen))
        })
        .collect();
    if flags.is_empty() {
        return Ok(());
    }
    let mut shared = lock(shared);
    if let Some(cached) = shared.cache.get_mut(&account.id) {
        for mail in cached {
            if let Some((_, _, uid)) = parse_mail_id(&mail.summary.id) {
                if let Some(seen) = flags.get(&uid) {
                    mail.summary.unread = !*seen;
                }
            }
        }
    }
    Ok(())
}

fn recent(
    session: &mut net::MailSession,
    account: &store::Account,
    validity: u32,
    exists: u32,
    legacy: bool,
    shared: &SharedRef,
) -> Result<Option<u32>, FetchFailure> {
    let found = match session.uid_search("ALL") {
        Ok(found) => found,
        Err(error) if net::rejected(&error) => {
            log_error(
                account,
                &format!("uid search rejected: {}", error_kind(&error)),
            );
            Default::default()
        }
        Err(error) => {
            log_error(account, &format!("search failed: {}", error_kind(&error)));
            return Err(match error {
                imap::Error::Parse(_) => FetchFailure::Parse,
                _ => FetchFailure::Reconnect,
            });
        }
    };
    let mut uids: Vec<u32> = found.into_iter().collect();

    // 少数服务器 UID SEARCH 返回空但邮箱里有邮件；按序号再取一次最近 UID。
    if uids.is_empty() && exists > 0 {
        let start = exists
            .saturating_sub(RECENT_LIMIT as u32 - 1)
            .max(1);
        let fetched = session
            .fetch(format!("{start}:*"), "(UID FLAGS INTERNALDATE)")
            .map_err(|error| {
                log_error(
                    account,
                    &format!("sequence fetch failed: {}", error_kind(&error)),
                );
                match error {
                    imap::Error::Parse(_) => FetchFailure::Parse,
                    _ => FetchFailure::Reconnect,
                }
            })?;
        uids = fetched.iter().filter_map(|fetch| fetch.uid).collect();
    }

    uids.sort_unstable();
    uids.dedup();
    let max = uids.last().copied();
    log_line(
        account,
        &format!(
            "recent: exists={exists} uids={} max={max:?} legacy={legacy}",
            uids.len()
        ),
    );
    let start = uids.len().saturating_sub(RECENT_LIMIT);
    for uid in &uids[start..] {
        match fetch_one(session, account, validity, *uid, legacy) {
            Ok(Some(mail)) => insert(shared, &account.id, mail),
            Ok(None) | Err(FetchFailure::Skip) => {}
            Err(failure) => return Err(failure),
        }
    }
    Ok(max)
}

fn fetch_new(
    session: &mut net::MailSession,
    account: &store::Account,
    validity: u32,
    last_uid: &mut Option<u32>,
    legacy: bool,
    shared: &SharedRef,
    tx: &Sender<Value>,
) -> Result<(), FetchFailure> {
    let last = last_uid.unwrap_or(0);
    let found = session
        .uid_search(format!("UID {}:*", last.saturating_add(1)))
        .map_err(|error| {
            log_error(account, &format!("search failed: {}", error_kind(&error)));
            match error {
                imap::Error::Parse(_) => FetchFailure::Parse,
                _ => FetchFailure::Reconnect,
            }
        })?;
    let mut uids: Vec<u32> = found.into_iter().filter(|uid| *uid > last).collect();
    uids.sort_unstable();
    uids.truncate(NEW_PER_CYCLE);
    for uid in uids {
        match fetch_one(session, account, validity, uid, legacy) {
            Ok(Some(mail)) => {
                let summary = mail.summary.clone();
                insert(shared, &account.id, mail);
                let _ = tx.send(rpc::event(json!({
                    "type": "mail.received",
                    "accountId": account.id,
                    "item": summary,
                })));
                *last_uid = Some(uid);
            }
            Ok(None) | Err(FetchFailure::Skip) => {
                *last_uid = Some(uid);
            }
            Err(failure) => return Err(failure),
        }
    }
    Ok(())
}

fn fetch_one(
    session: &mut net::MailSession,
    account: &store::Account,
    validity: u32,
    uid: u32,
    legacy: bool,
) -> Result<Option<CachedMail>, FetchFailure> {
    // 默认请求 BODYSTRUCTURE；只有服务器响应无法解析时才降级为整封正文。
    let query = if legacy {
        "(UID FLAGS INTERNALDATE BODY.PEEK[HEADER])"
    } else {
        "(UID FLAGS INTERNALDATE BODYSTRUCTURE BODY.PEEK[HEADER])"
    };
    let fetched = session
        .uid_fetch(uid.to_string(), query)
        .map_err(|error| map_fetch_error(account, error))?;
    let Some(fetch) = fetched.iter().find(|fetch| fetch.uid == Some(uid)) else {
        return Ok(None);
    };
    let unread = !fetch.flags().iter().any(|flag| matches!(flag, Flag::Seen));
    let received_at = fetch
        .internal_date()
        .map(|date| date.timestamp_millis())
        .unwrap_or_else(now_ms);
    let Some(header) = fetch.header() else {
        return Ok(None);
    };

    let parsed_headers = parse::headers(header);
    let (plain, html, has_attachments, partial) = if legacy {
        fallback_text(session, account, uid, header)?
    } else {
        match fetch.bodystructure() {
            Some(structure) => match fetch_parts(session, account, uid, structure) {
                Ok(value) => value,
                Err(FetchFailure::Skip) => fallback_text(session, account, uid, header)?,
                Err(failure) => return Err(failure),
            },
            None => fallback_text(session, account, uid, header)?,
        }
    };

    let body = parse::body(&plain, &html);
    let summary = MailSummary {
        id: format!("mail:{}:{}:{}", account.id, validity, uid),
        account_id: account.id.clone(),
        from: if parsed_headers.from.is_empty() {
            account.email.clone()
        } else {
            parsed_headers.from
        },
        from_address: parsed_headers.from_address,
        subject: if parsed_headers.subject.trim().is_empty() {
            "（无主题）".into()
        } else {
            parsed_headers.subject
        },
        received_at,
        unread,
        snippet: parse::snippet(&body.text),
        has_attachments,
    };

    Ok(Some(CachedMail {
        summary,
        text: body.text,
        truncated: body.truncated || partial,
        links: body.links,
    }))
}

fn fetch_parts(
    session: &mut net::MailSession,
    account: &store::Account,
    uid: u32,
    structure: &BodyStructure,
) -> Result<(String, String, bool, bool), FetchFailure> {
    let mut parts = Vec::new();
    let mut has_attachments = false;
    collect_parts(structure, &mut Vec::new(), &mut parts, &mut has_attachments);

    let mut plain = String::new();
    let mut html = String::new();
    let mut partial = false;
    for part in parts.into_iter().take(8) {
        let (data, cut) = fetch_part(session, account, uid, &part)?;
        partial |= cut;
        let text = parse::decode_part(
            &part.subtype,
            part.charset.as_deref(),
            &part.encoding,
            &data,
        );
        if part.subtype.eq_ignore_ascii_case("html") {
            html.push_str(&text);
            html.push('\n');
        } else {
            plain.push_str(&text);
            plain.push('\n');
        }
    }
    Ok((plain, html, has_attachments, partial))
}

fn fetch_part(
    session: &mut net::MailSession,
    account: &store::Account,
    uid: u32,
    part: &TextPart,
) -> Result<(Vec<u8>, bool), FetchFailure> {
    let path = part
        .path
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(".");
    let (query, partial) = if part.octets > MAX_PART_BYTES {
        (
            format!("(UID BODY.PEEK[{path}]<0.{MAX_PART_BYTES}>)"),
            true,
        )
    } else {
        (format!("(UID BODY.PEEK[{path}])"), false)
    };
    let fetched = session
        .uid_fetch(uid.to_string(), query)
        .map_err(|error| map_fetch_error(account, error))?;
    let data = fetched
        .iter()
        .find(|fetch| fetch.uid == Some(uid))
        .and_then(|fetch| fetch.section(&SectionPath::Part(part.path.clone(), None)))
        .map(|value| value.to_vec())
        .unwrap_or_default();
    Ok((data, partial))
}

struct TextPart {
    path: Vec<u32>,
    subtype: String,
    charset: Option<String>,
    encoding: String,
    octets: u32,
}

fn collect_parts(
    body: &BodyStructure,
    path: &mut Vec<u32>,
    out: &mut Vec<TextPart>,
    has_attachments: &mut bool,
) {
    match body {
        BodyStructure::Multipart { bodies, .. } => {
            for (index, child) in bodies.iter().enumerate() {
                path.push(index as u32 + 1);
                collect_parts(child, path, out, has_attachments);
                path.pop();
            }
        }
        BodyStructure::Text { common, other, .. } => {
            let is_text = common.ty.ty.eq_ignore_ascii_case("text");
            let subtype = common.ty.subtype.to_ascii_lowercase();
            let attachment = is_attachment(common);
            if is_text
                && (subtype == "plain" || subtype == "html")
                && !attachment
            {
                let charset = common
                    .ty
                    .params
                    .as_ref()
                    .and_then(|params| {
                        params
                            .iter()
                            .find(|(key, _)| key.eq_ignore_ascii_case("charset"))
                            .map(|(_, value)| value.to_string())
                    });
                out.push(TextPart {
                    path: if path.is_empty() {
                        vec![1]
                    } else {
                        path.clone()
                    },
                    subtype,
                    charset,
                    encoding: encoding_name(&other.transfer_encoding),
                    octets: other.octets,
                });
            } else if attachment || !is_text {
                *has_attachments = true;
            }
        }
        BodyStructure::Basic { common, .. } => {
            if is_attachment(common) || !common.ty.ty.eq_ignore_ascii_case("text") {
                *has_attachments = true;
            }
        }
        BodyStructure::Message { .. } => {
            *has_attachments = true;
        }
    }
}

fn is_attachment(common: &BodyContentCommon) -> bool {
    let disposition_attachment = common
        .disposition
        .as_ref()
        .is_some_and(|disposition| disposition.ty.eq_ignore_ascii_case("attachment"));
    let named = common
        .disposition
        .as_ref()
        .and_then(|disposition| disposition.params.as_ref())
        .is_some_and(|params| {
            params
                .iter()
                .any(|(key, _)| key.eq_ignore_ascii_case("filename"))
        })
        || common.ty.params.as_ref().is_some_and(|params| {
            params
                .iter()
                .any(|(key, _)| key.eq_ignore_ascii_case("name"))
        });
    disposition_attachment || named
}

fn encoding_name(encoding: &ContentEncoding) -> String {
    match encoding {
        ContentEncoding::SevenBit => "7bit".into(),
        ContentEncoding::EightBit => "8bit".into(),
        ContentEncoding::Binary => "binary".into(),
        ContentEncoding::Base64 => "base64".into(),
        ContentEncoding::QuotedPrintable => "quoted-printable".into(),
        ContentEncoding::Other(value) => (*value).to_string(),
    }
}

fn fallback_text(
    session: &mut net::MailSession,
    account: &store::Account,
    uid: u32,
    header: &[u8],
) -> Result<(String, String, bool, bool), FetchFailure> {
    let fetched = session
        .uid_fetch(
            uid.to_string(),
            format!("(UID BODY.PEEK[TEXT]<0.{FALLBACK_BYTES}>)"),
        )
        .map_err(|error| map_fetch_error(account, error))?;
    let data = fetched
        .iter()
        .find(|fetch| fetch.uid == Some(uid))
        .and_then(|fetch| fetch.text())
        .unwrap_or_default();
    let (plain, html, attachments) = parse::fallback(header, data);
    Ok((plain, html, attachments, data.len() as u32 >= FALLBACK_BYTES))
}

fn map_fetch_error(account: &store::Account, error: imap::Error) -> FetchFailure {
    log_error(account, &format!("fetch failed: {}", error_kind(&error)));
    match error {
        imap::Error::No(_) | imap::Error::Bad(_) => FetchFailure::Skip,
        imap::Error::Parse(_) => FetchFailure::Parse,
        _ => FetchFailure::Reconnect,
    }
}

/// 只记录错误类型，不记录服务器响应正文。
fn error_kind(error: &imap::Error) -> &'static str {
    match error {
        imap::Error::Io(_) => "io",
        imap::Error::TlsHandshake(_) => "tls_handshake",
        imap::Error::Tls(_) => "tls",
        imap::Error::Bad(_) => "bad",
        imap::Error::No(_) => "no",
        imap::Error::ConnectionLost => "connection_lost",
        imap::Error::Parse(_) => "parse",
        imap::Error::Validate(_) => "validate",
        _ => "other",
    }
}

fn insert(shared: &SharedRef, account_id: &str, mail: CachedMail) {
    let mut shared = lock(shared);
    // 账号删除后，仍在收尾的 worker 不允许把邮件写回缓存。
    if !shared
        .runtimes
        .iter()
        .any(|runtime| runtime.account.id == account_id)
    {
        return;
    }
    let list = shared.cache.entry(account_id.to_string()).or_default();
    if let Some(existing) = list
        .iter_mut()
        .find(|existing| existing.summary.id == mail.summary.id)
    {
        *existing = mail;
    } else {
        list.insert(0, mail);
    }
    list.sort_by(|left, right| right.summary.received_at.cmp(&left.summary.received_at));
    list.truncate(RECENT_LIMIT);
}

fn set_state(
    shared: &SharedRef,
    account_id: &str,
    state: &str,
    message: &str,
    reauth_required: bool,
    tx: &Sender<Value>,
) {
    let view = {
        let mut shared = lock(shared);
        shared.set_state(account_id, state, message, reauth_required)
    };
    if let Some(view) = view {
        let _ = tx.send(rpc::event(json!({
            "type": "mail.account",
            "account": view,
        })));
    }
}

fn mark_ready(shared: &SharedRef, account_id: &str, tx: &Sender<Value>) {
    let view = {
        let mut shared = lock(shared);
        shared.mark_ready(account_id)
    };
    if let Some(view) = view {
        let _ = tx.send(rpc::event(json!({
            "type": "mail.account",
            "account": view,
        })));
    }
}

fn wait(cmd_rx: &Receiver<WorkerCmd>, duration: Duration) -> bool {
    match cmd_rx.recv_timeout(duration) {
        Ok(WorkerCmd::Stop) | Err(RecvTimeoutError::Disconnected) => true,
        Ok(WorkerCmd::PollNow) | Err(RecvTimeoutError::Timeout) => false,
    }
}

fn backoff(failures: &mut u32) -> Duration {
    let seconds = 30u64.saturating_mul(1u64 << (*failures).min(1));
    *failures = failures.saturating_add(1);
    Duration::from_secs(seconds.min(60))
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or(0)
}

fn log_line(account: &store::Account, message: &str) {
    crate::log(&format!(
        "mail: id={} provider={} {}",
        account.id,
        account.provider.key(),
        message
    ));
}

fn log_error(account: &store::Account, message: &str) {
    log_line(account, &format!("error={message}"));
}

fn lock(shared: &SharedRef) -> MutexGuard<'_, Shared> {
    match shared.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

impl Shared {
    fn new(accounts: Vec<store::Account>) -> Self {
        Self {
            runtimes: accounts.into_iter().map(Runtime::new).collect(),
            cache: HashMap::new(),
        }
    }

    fn views(&self) -> Vec<AccountView> {
        self.runtimes.iter().map(|runtime| runtime.view()).collect()
    }

    fn view_for(&self, account_id: &str) -> Option<AccountView> {
        self.runtimes
            .iter()
            .find(|runtime| runtime.account.id == account_id)
            .map(Runtime::view)
    }

    fn upsert_runtime(&mut self, account: store::Account) {
        if let Some(existing) = self
            .runtimes
            .iter_mut()
            .find(|runtime| runtime.account.id == account.id)
        {
            existing.account = account;
            existing.state = "connecting".into();
            existing.message = "正在连接".into();
            existing.reauth_required = false;
        } else {
            self.runtimes.push(Runtime::new(account));
        }
    }

    fn set_state(
        &mut self,
        account_id: &str,
        state: &str,
        message: &str,
        reauth_required: bool,
    ) -> Option<AccountView> {
        let runtime = self
            .runtimes
            .iter_mut()
            .find(|runtime| runtime.account.id == account_id)?;
        runtime.state = state.to_string();
        runtime.message = message.to_string();
        runtime.reauth_required = reauth_required;
        Some(runtime.view())
    }

    fn mark_ready(&mut self, account_id: &str) -> Option<AccountView> {
        let runtime = self
            .runtimes
            .iter_mut()
            .find(|runtime| runtime.account.id == account_id)?;
        runtime.state = "ready".into();
        runtime.message.clear();
        runtime.reauth_required = false;
        runtime.last_sync_at = Some(now_ms());
        Some(runtime.view())
    }

    fn list(
        &self,
        account_id: Option<&str>,
        limit: usize,
        unread_only: bool,
    ) -> Vec<MailSummary> {
        let mut items = Vec::new();
        for (id, cached) in &self.cache {
            if account_id.is_some_and(|wanted| wanted != id) {
                continue;
            }
            let mut picked = 0usize;
            for mail in cached {
                if unread_only && !mail.summary.unread {
                    continue;
                }
                items.push(mail.summary.clone());
                picked += 1;
                if picked >= limit {
                    break;
                }
            }
        }
        items.sort_by(|left, right| right.received_at.cmp(&left.received_at));
        items
    }

    fn get(&self, id: &str) -> Option<MailDetail> {
        self.cache
            .values()
            .flat_map(|cached| cached.iter())
            .find(|mail| mail.summary.id == id)
            .map(CachedMail::detail)
    }

    fn unread_uids(&self, account_id: &str) -> Vec<u32> {
        self.cache
            .get(account_id)
            .map(|cached| {
                cached
                    .iter()
                    .filter(|mail| mail.summary.unread)
                    .filter_map(|mail| {
                        parse_mail_id(&mail.summary.id).map(|(_, _, uid)| uid)
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    fn mark_all_read(&mut self, account_id: &str) {
        let Some(cached) = self.cache.get_mut(account_id) else {
            return;
        };
        for mail in cached {
            mail.summary.unread = false;
        }
    }

    fn update_label(&mut self, id: &str, label: Option<String>) -> Option<AccountView> {
        let runtime = self
            .runtimes
            .iter_mut()
            .find(|runtime| runtime.account.id == id)?;
        runtime.account.label = label;
        Some(runtime.view())
    }

    fn mark_one_read(&mut self, id: &str) {
        for cached in self.cache.values_mut() {
            if let Some(mail) = cached.iter_mut().find(|mail| mail.summary.id == id) {
                mail.summary.unread = false;
                return;
            }
        }
    }
}

impl Runtime {
    fn new(account: store::Account) -> Self {
        Self {
            account,
            state: "idle".into(),
            message: "未连接".into(),
            last_sync_at: None,
            reauth_required: false,
        }
    }

    fn view(&self) -> AccountView {
        AccountView {
            id: self.account.id.clone(),
            provider: self.account.provider,
            email: self.account.email.clone(),
            label: self.account.label.clone(),
            auth_type: self.account.auth_type,
            enabled: self.account.enabled,
            custom: self.account.custom.clone(),
            webmail_url: self.account.webmail().to_string(),
            state: self.state.clone(),
            message: self.message.clone(),
            last_sync_at: self.last_sync_at,
            reauth_required: self.reauth_required,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn account(id: &str, email: &str) -> store::Account {
        store::Account {
            id: id.into(),
            provider: store::Provider::Qq,
            email: email.into(),
            label: None,
            auth_type: store::AuthType::Password,
            enabled: true,
            custom: None,
            webmail_url: None,
        }
    }

    fn mail(account_id: &str, uid: u32, received_at: i64, unread: bool) -> CachedMail {
        CachedMail {
            summary: MailSummary {
                id: format!("mail:{account_id}:7:{uid}"),
                account_id: account_id.into(),
                from: "sender".into(),
                from_address: "sender@example.com".into(),
                subject: format!("subject {uid}"),
                received_at,
                unread,
                snippet: "snippet".into(),
                has_attachments: false,
            },
            text: "body".into(),
            truncated: false,
            links: Vec::new(),
        }
    }

    #[test]
    fn cache_keeps_twenty_newest_and_replaces_duplicates() {
        let shared = SharedRef::new(Mutex::new(Shared::new(vec![account("m_1", "a@example.com")])));
        for uid in 1..=25 {
            insert(&shared, "m_1", mail("m_1", uid, uid as i64, true));
        }
        {
            let guard = lock(&shared);
            let cache = &guard.cache["m_1"];
            assert_eq!(cache.len(), RECENT_LIMIT);
            assert_eq!(cache[0].summary.id, "mail:m_1:7:25");
            assert!(cache.iter().all(|item| item.summary.id != "mail:m_1:7:1"));
        }

        insert(&shared, "m_1", mail("m_1", 25, 25, false));
        let guard = lock(&shared);
        let cache = &guard.cache["m_1"];
        assert_eq!(cache.iter().filter(|item| item.summary.received_at == 25).count(), 1);
        assert!(!cache[0].summary.unread);
    }

    #[test]
    fn parses_stable_mail_ids() {
        assert_eq!(
            parse_mail_id("mail:m_1:7:42"),
            Some(("m_1".to_string(), 7, 42))
        );
        assert_eq!(parse_mail_id("bad"), None);
        assert_eq!(parse_mail_id("mail:m_1:7"), None);
    }

    #[test]
    fn unread_uids_come_from_the_ui_cache() {
        let mut shared = Shared::new(vec![account("m_1", "a@example.com")]);
        shared.cache.insert(
            "m_1".into(),
            vec![mail("m_1", 1, 1, true), mail("m_1", 2, 2, false)],
        );
        assert_eq!(shared.unread_uids("m_1"), vec![1]);
        assert!(shared.unread_uids("missing").is_empty());
    }

    #[test]
    fn mark_all_read_only_clears_the_target_account() {
        let mut shared = Shared::new(vec![
            account("m_1", "a@example.com"),
            account("m_2", "b@example.com"),
        ]);
        shared.cache.insert("m_1".into(), vec![mail("m_1", 1, 1, true)]);
        shared.cache.insert("m_2".into(), vec![mail("m_2", 2, 2, true)]);
        shared.mark_all_read("m_1");
        assert!(!shared.cache["m_1"][0].summary.unread);
        assert!(shared.cache["m_2"][0].summary.unread);
    }

    #[test]
    fn list_filters_by_account_and_unread() {
        let mut shared = Shared::new(vec![
            account("m_1", "a@example.com"),
            account("m_2", "b@example.com"),
        ]);
        shared.cache.insert(
            "m_1".into(),
            vec![mail("m_1", 2, 2, false), mail("m_1", 1, 1, true)],
        );
        shared.cache.insert("m_2".into(), vec![mail("m_2", 3, 3, true)]);
        assert_eq!(shared.list(None, 20, false).len(), 3);
        assert_eq!(shared.list(Some("m_1"), 20, false).len(), 2);
        assert_eq!(shared.list(None, 20, true).len(), 2);
        assert_eq!(shared.list(Some("m_1"), 1, false).len(), 1);
    }

    #[test]
    fn account_view_never_contains_credentials() {
        let runtime = Runtime::new(account("m_1", "a@example.com"));
        let value = serde_json::to_value(runtime.view()).unwrap();
        assert!(value.get("password").is_none());
        assert!(value.get("token").is_none());
    }

    #[test]
    fn add_requires_oauth_for_microsoft() {
        let state = Arc::new(State::default());
        let (tx, _rx) = mpsc::channel();
        let mut store = store::Store::memory(Vec::new());
        let shared = SharedRef::new(Mutex::new(Shared::new(Vec::new())));
        let mut workers = HashMap::new();
        let job = Job {
            id: json!(1),
            method: "mail.accounts.add".into(),
            params: json!({
                "provider": "microsoft",
                "email": "a@example.com",
                "password": "x"
            }),
        };
        let error = add_account(&job, &mut store, &shared, &mut workers, &tx, &state)
            .expect_err("microsoft must use oauth");
        assert_eq!(error.code, ERR_INVALID_PARAMS);
    }

    #[test]
    fn add_rejects_custom_starttls_port() {
        let state = Arc::new(State::default());
        let (tx, _rx) = mpsc::channel();
        let mut store = store::Store::memory(Vec::new());
        let shared = SharedRef::new(Mutex::new(Shared::new(Vec::new())));
        let mut workers = HashMap::new();
        let job = Job {
            id: json!(1),
            method: "mail.accounts.add".into(),
            params: json!({
                "provider": "custom",
                "email": "a@example.com",
                "password": "x",
                "custom": { "host": "imap.example.com", "port": 143, "username": "a" }
            }),
        };
        let error = add_account(&job, &mut store, &shared, &mut workers, &tx, &state)
            .expect_err("port 143 must be rejected");
        assert_eq!(error.code, ERR_INVALID_PARAMS);
    }

    #[test]
    fn icloud_rejects_non_apple_addresses() {
        let state = Arc::new(State::default());
        let (tx, _rx) = mpsc::channel();
        let mut store = store::Store::memory(Vec::new());
        let shared = SharedRef::new(Mutex::new(Shared::new(Vec::new())));
        let mut workers = HashMap::new();
        let job = Job {
            id: json!(1),
            method: "mail.accounts.add".into(),
            params: json!({
                "provider": "icloud",
                "email": "user@gmail.com",
                "password": "app-password"
            }),
        };
        let error = add_account(&job, &mut store, &shared, &mut workers, &tx, &state)
            .expect_err("icloud must reject non-Apple mail domains");
        assert_eq!(error.code, ERR_INVALID_PARAMS);
    }
}
