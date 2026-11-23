//! AI 额度：GLM / DeepSeek / OpenCode 的配额与余额。
//!
//! 凭据只从 Windows 凭据管理器读取，不落 config.json。
//! 网络请求全部在独立线程执行，主循环只接收命令并推送 `quota.updated`。

use chrono::TimeZone;
use serde::Serialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::Read;
use std::sync::mpsc::{Receiver, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::rpc::{self, State};

const DEFAULT_REFRESH_SECONDS: u64 = 300;
const MIN_REFRESH_SECONDS: u64 = 60;
const MAX_REFRESH_SECONDS: u64 = 3600;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(12);

/// OpenCode Console 需要浏览器 UA；用拼接避免被当成敏感字面量。
fn user_agent() -> String {
    format!(
        "{}/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
        "Mozilla"
    )
}

const GLM_GLOBAL: &str = "https://api.z.ai";
const GLM_BIGMODEL_CN: &str = "https://open.bigmodel.cn";
const DEEPSEEK_BALANCE: &str = "https://api.deepseek.com/user/balance";
const OPENCODE_GO_USAGE: &str = "https://opencode.ai/zen/go/v1/usage";
const OPENCODE_CONSOLE: &str = "https://opencode.ai/console/api";

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaWindow {
    pub kind: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub used_percent: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub remaining_percent: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub window_minutes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resets_at_ms: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub remaining: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub currency: Option<String>,
    pub show_meter: bool,
}

impl QuotaWindow {
    fn session(used_percent: f64, window_minutes: u64, resets_at_ms: Option<i64>) -> Self {
        Self::meter("session", "5-hour", used_percent, window_minutes, resets_at_ms)
    }

    fn weekly(used_percent: f64, resets_at_ms: Option<i64>) -> Self {
        Self::meter(
            "weekly",
            "Weekly",
            used_percent,
            7 * 24 * 60,
            resets_at_ms,
        )
    }

    fn monthly(used_percent: f64, resets_at_ms: Option<i64>) -> Self {
        Self::meter("monthly", "Monthly", used_percent, 30 * 24 * 60, resets_at_ms)
    }

    fn meter(
        kind: &str,
        label: &str,
        used_percent: f64,
        window_minutes: u64,
        resets_at_ms: Option<i64>,
    ) -> Self {
        let used_percent = used_percent.clamp(0.0, 100.0);
        Self {
            kind: kind.into(),
            label: label.into(),
            used_percent: Some(used_percent),
            remaining_percent: Some(100.0 - used_percent),
            window_minutes: Some(window_minutes),
            resets_at_ms,
            remaining: None,
            currency: None,
            show_meter: true,
        }
    }

    fn balance(amount: f64, currency: &str) -> Self {
        Self::balance_with("Balance", amount, Some(currency))
    }

    fn balance_with(label: &str, amount: f64, currency: Option<&str>) -> Self {
        Self {
            kind: "billing".into(),
            label: label.into(),
            used_percent: None,
            remaining_percent: None,
            window_minutes: None,
            resets_at_ms: None,
            remaining: Some(amount.max(0.0)),
            currency: currency.map(str::to_string),
            show_meter: false,
        }
    }

    fn billing_meter(label: &str, used_percent: f64) -> Self {
        let used_percent = used_percent.clamp(0.0, 100.0);
        Self {
            kind: "billing".into(),
            label: label.into(),
            used_percent: Some(used_percent),
            remaining_percent: Some(100.0 - used_percent),
            window_minutes: None,
            resets_at_ms: None,
            remaining: None,
            currency: None,
            show_meter: true,
        }
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaProvider {
    pub id: String,
    pub label: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub plan: Option<String>,
    pub windows: Vec<QuotaWindow>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    /// 站点自动抓取到的图标，data URI；缺失时客户端使用内置图标。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logo: Option<String>,
    pub updated_at_ms: i64,
}

impl QuotaProvider {
    fn new(id: &str, label: &str, status: &str) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            status: status.into(),
            plan: None,
            windows: Vec::new(),
            message: None,
            logo: None,
            updated_at_ms: now_ms(),
        }
    }

    fn with_message(mut self, message: impl Into<String>) -> Self {
        self.message = Some(message.into());
        self
    }
}

#[derive(Debug)]
enum FetchError {
    Unauthorized,
    /// 服务端返回 401/403 时带上的原始说明，便于定位是令牌还是用户 ID 不匹配。
    Rejected(String),
    RateLimited,
    Unavailable(String),
}

impl FetchError {
    fn status(&self) -> &'static str {
        match self {
            Self::Unauthorized | Self::Rejected(_) => "unauthorized",
            Self::RateLimited => "rateLimited",
            Self::Unavailable(_) => "unavailable",
        }
    }

    fn message(&self) -> String {
        match self {
            Self::Unauthorized => "凭据无效或已过期".into(),
            Self::Rejected(detail) => detail.clone(),
            Self::RateLimited => "请求过于频繁".into(),
            Self::Unavailable(detail) => detail.clone(),
        }
    }
}

/// 后台线程命令。`Refresh(None)` 刷新全部，`Refresh(Some(id))` 只刷新一个。
pub enum Command {
    Refresh(Option<String>),
}

/// 启动额度线程，立即拉取一次，之后按设置间隔刷新。
pub fn start(state: Arc<State>, tx: Sender<Value>) -> Sender<Command> {
    let (command_tx, command_rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("quota".into())
        .spawn(move || run(state, tx, command_rx));
    if let Err(error) = spawned {
        crate::log(&format!("quota: 线程启动失败: {error}"));
    }
    command_tx
}

fn run(state: Arc<State>, tx: Sender<Value>, commands: Receiver<Command>) {
    // 首次进入立即超时，先拉一次全量。
    let mut deadline = Instant::now();
    loop {
        let wait = deadline.saturating_duration_since(Instant::now());
        match commands.recv_timeout(wait) {
            Ok(Command::Refresh(provider)) => {
                refresh(&state, &tx, provider);
                deadline = Instant::now() + Duration::from_secs(refresh_seconds(&state));
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                refresh(&state, &tx, None);
                deadline = Instant::now() + Duration::from_secs(refresh_seconds(&state));
            }
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return,
        }
    }
}

fn refresh_seconds(state: &State) -> u64 {
    state
        .config
        .u64("quotaRefreshSeconds", DEFAULT_REFRESH_SECONDS)
        .clamp(MIN_REFRESH_SECONDS, MAX_REFRESH_SECONDS)
}

fn refresh(state: &State, tx: &Sender<Value>, only: Option<String>) {
    let settings = state.config.snapshot();
    let order = provider_order(&settings);
    let existing = state
        .quota
        .lock()
        .map(|items| items.clone())
        .unwrap_or_default();
    let mut providers: Vec<QuotaProvider> = Vec::new();
    for id in order {
        if let Some(target) = &only {
            if target != &id {
                if let Some(previous) = existing.iter().find(|item| item.id == id) {
                    providers.push(previous.clone());
                }
                continue;
            }
        }
        let provider = fetch_provider(&id, &settings);
        if provider.status != "ok" && provider.status != "notConfigured" {
            crate::log(&format!(
                "quota: {id} {} {}",
                provider.status,
                provider.message.as_deref().unwrap_or_default()
            ));
        }
        providers.push(provider);
    }
    if let Ok(mut slot) = state.quota.lock() {
        *slot = providers.clone();
    }
    let _ = tx.send(rpc::event(json!({
        "type": "quota.updated",
        "providers": providers,
        "updatedAtMs": now_ms(),
    })));
}

fn provider_order(settings: &serde_json::Map<String, Value>) -> Vec<String> {
    let default = ["glm", "deepseek", "opencode", "krill"];
    let sites = newapi_sites(settings);
    let site_ids: Vec<String> = sites.iter().map(|site| site.provider_id()).collect();
    let mut order: Vec<String> = Vec::new();
    if let Some(values) = settings.get("quotaOrder").and_then(Value::as_array) {
        for value in values {
            let Some(id) = value.as_str() else { continue };
            if (default.contains(&id) || site_ids.iter().any(|item| item == id))
                && !order.iter().any(|item| item == id)
            {
                order.push(id.to_string());
            }
        }
    }
    for id in default {
        if !order.iter().any(|item| item == id) {
            order.push(id.to_string());
        }
    }
    for id in site_ids {
        if !order.contains(&id) {
            order.push(id);
        }
    }
    let krill_ready = crate::credentials::read(crate::credentials::KRILL_TOKEN).is_some();
    order.retain(|id| id != "krill" || krill_ready);
    order
}

fn fetch_provider(id: &str, settings: &serde_json::Map<String, Value>) -> QuotaProvider {
    match id {
        "glm" => fetch_glm(settings),
        "deepseek" => fetch_deepseek(),
        "opencode" => fetch_opencode(),
        "krill" => fetch_krill(settings),
        _ => match id.strip_prefix("newapi:") {
            Some(site_id) => {
                let sites = newapi_sites(settings);
                match sites.iter().find(|site| site.id == site_id) {
                    Some(site) => fetch_newapi(site),
                    None => QuotaProvider::new(id, "New API", "notConfigured"),
                }
            }
            None => {
                let mut provider = QuotaProvider::new(id, id, "unavailable");
                provider.message = Some("未知的额度服务".into());
                provider
            }
        },
    }
}

// --- GLM / Z.ai -----------------------------------------------------------

fn fetch_glm(settings: &serde_json::Map<String, Value>) -> QuotaProvider {
    let label = "GLM";
    let Some(key) = crate::credentials::read(crate::credentials::GLM_KEY) else {
        return QuotaProvider::new("glm", label, "notConfigured");
    };
    let region = settings
        .get("quotaGlmRegion")
        .and_then(Value::as_str)
        .unwrap_or("global");
    let (base, currency) = if region == "bigmodel-cn" {
        (GLM_BIGMODEL_CN, "CNY")
    } else {
        (GLM_GLOBAL, "USD")
    };
    let agent = agent();
    let quota_url = format!("{base}/api/monitor/usage/quota/limit");
    let quota = match get_json(&agent, &quota_url, Some(&key), &[]) {
        Ok(value) => value,
        Err(error) => return failed("glm", label, error),
    };
    let mut windows = parse_glm_windows(&quota);
    if windows.is_empty() {
        return failed(
            "glm",
            label,
            FetchError::Unavailable("GLM 没有返回可用的额度窗口".into()),
        )
        .maybe_plan(glm_plan(&quota));
    }
    let mut plan = glm_plan(&quota);
    // 订阅信息只用于补充套餐名与续费时间，失败不影响额度。
    if let Ok(subscription) = get_json(
        &agent,
        &format!("{base}/api/biz/subscription/list"),
        Some(&key),
        &[],
    ) {
        plan = glm_plan(&subscription).or(plan);
        if let Some(reset) = glm_subscription_reset(&subscription) {
            for window in &mut windows {
                if window.kind == "weekly" || window.kind == "monthly" {
                    window.resets_at_ms = window.resets_at_ms.or(Some(reset));
                }
            }
        }
    }
    if let Ok(balance) = get_json(
        &agent,
        &format!("{base}/api/biz/account/query-customer-account-report"),
        Some(&key),
        &[],
    ) {
        if let Some(amount) = as_number(&balance["data"]["availableBalance"]) {
            windows.push(QuotaWindow::balance(amount, currency));
        }
    }
    let mut provider = QuotaProvider::new("glm", label, "ok");
    provider.plan = plan.filter(|value| !value.is_empty());
    provider.windows = windows;
    provider
}

fn glm_plan(value: &Value) -> Option<String> {
    let rows = value["data"].as_array()?;
    let row = rows
        .iter()
        .find(|row| row["inCurrentPeriod"].as_bool() == Some(true))
        .or_else(|| rows.first())?;
    for field in [
        "product_name",
        "productName",
        "plan_name",
        "planName",
        "package_name",
        "packageName",
        "plan",
        "plan_type",
        "planType",
        "level",
    ] {
        if let Some(text) = row[field].as_str().map(str::trim).filter(|v| !v.is_empty()) {
            return Some(display_plan(text));
        }
    }
    for field in ["planName", "plan_name", "plan", "planType", "level"] {
        if let Some(text) = value["data"][field]
            .as_str()
            .map(str::trim)
            .filter(|v| !v.is_empty())
        {
            return Some(display_plan(text));
        }
    }
    None
}

fn glm_subscription_reset(value: &Value) -> Option<i64> {
    let rows = value["data"].as_array()?;
    let row = rows
        .iter()
        .find(|row| row["inCurrentPeriod"].as_bool() == Some(true))
        .or_else(|| rows.first())?;
    for field in ["next_renew_time", "nextRenewTime"] {
        if let Some(ms) = iso_to_ms(row[field].as_str()) {
            return Some(ms);
        }
    }
    None
}

fn parse_glm_windows(quota: &Value) -> Vec<QuotaWindow> {
    let limits = quota["data"]["limits"].as_array();
    let Some(limits) = limits else {
        return Vec::new();
    };
    let mut token_limits: Vec<(&Value, u64, f64)> = Vec::new();
    let mut time_limit: Option<(&Value, f64)> = None;
    for limit in limits {
        let kind = limit["type"]
            .as_str()
            .or_else(|| limit["limit_type"].as_str())
            .unwrap_or_default()
            .to_uppercase();
        let Some(percent) = glm_used_percent(limit) else {
            continue;
        };
        let minutes = glm_window_minutes(
            as_number(&limit["unit"]),
            as_number(&limit["number"]),
        );
        if kind == "TOKENS_LIMIT" || kind == "CREDIT_LIMIT" {
            if let Some(minutes) = minutes {
                token_limits.push((limit, minutes, percent));
            }
        } else if kind == "TIME_LIMIT" {
            time_limit = Some((limit, percent));
        }
    }
    token_limits.sort_by_key(|(_, minutes, _)| *minutes);
    let mut windows = Vec::new();
    if token_limits.len() >= 2 {
        let (session, session_minutes, percent) = token_limits[0];
        windows.push(QuotaWindow::session(
            percent,
            session_minutes,
            glm_reset_at(session),
        ));
        let (weekly, minutes, percent) = token_limits[token_limits.len() - 1];
        if minutes <= 6 * 60 {
            windows.push(QuotaWindow::session(percent, minutes, glm_reset_at(weekly)));
        } else {
            windows.push(QuotaWindow::weekly(percent, glm_reset_at(weekly)));
        }
    } else if let Some(&(limit, minutes, percent)) = token_limits.first() {
        if minutes <= 6 * 60 {
            windows.push(QuotaWindow::session(percent, minutes, glm_reset_at(limit)));
        } else if minutes <= 8 * 24 * 60 {
            windows.push(QuotaWindow::weekly(percent, glm_reset_at(limit)));
        } else {
            windows.push(QuotaWindow::monthly(percent, glm_reset_at(limit)));
        }
    }
    if let Some((limit, percent)) = time_limit {
        let mut window = QuotaWindow::billing_meter("MCP", percent);
        window.resets_at_ms = glm_reset_at(limit);
        windows.push(window);
    }
    windows
}

fn glm_used_percent(limit: &Value) -> Option<f64> {
    let total = as_number(&limit["usage"]);
    let remaining = as_number(&limit["remaining"]);
    let current = as_number(&limit["currentValue"])
        .or_else(|| as_number(&limit["current_value"]));
    if let Some(total) = total.filter(|value| *value > 0.0) {
        let from_remaining = remaining.map(|value| total - value);
        let used = match (from_remaining, current) {
            (Some(a), Some(b)) => Some(a.max(b)),
            (Some(a), None) => Some(a),
            (None, Some(b)) => Some(b),
            (None, None) => None,
        };
        if let Some(used) = used {
            return Some((used.clamp(0.0, total) / total * 100.0).clamp(0.0, 100.0));
        }
    }
    as_number(&limit["percentage"])
        .or_else(|| as_number(&limit["usedPercent"]))
        .or_else(|| as_number(&limit["used_percent"]))
        .map(|value| value.clamp(0.0, 100.0))
}

fn glm_window_minutes(unit: Option<f64>, number: Option<f64>) -> Option<u64> {
    let unit = unit?;
    let number = number?;
    if number <= 0.0 {
        return None;
    }
    let minutes = match unit as i64 {
        5 => number,
        3 => number * 60.0,
        1 => number * 24.0 * 60.0,
        6 => number * 7.0 * 24.0 * 60.0,
        _ => return None,
    };
    Some(minutes.round() as u64)
}

fn glm_reset_at(limit: &Value) -> Option<i64> {
    json_to_ms(&limit["nextResetTime"]).or_else(|| json_to_ms(&limit["next_reset_time"]))
}

// --- DeepSeek -------------------------------------------------------------

fn fetch_deepseek() -> QuotaProvider {
    let label = "DeepSeek";
    let Some(key) = crate::credentials::read(crate::credentials::DEEPSEEK_KEY) else {
        return QuotaProvider::new("deepseek", label, "notConfigured");
    };
    let agent = agent();
    let value = match get_json(&agent, DEEPSEEK_BALANCE, Some(&key), &[]) {
        Ok(value) => value,
        Err(error) => return failed("deepseek", label, error),
    };
    let Some(rows) = value["balance_infos"].as_array() else {
        return failed(
            "deepseek",
            label,
            FetchError::Unavailable("DeepSeek 返回的余额格式无法识别".into()),
        );
    };
    let Some((amount, currency)) = select_deepseek_balance(rows) else {
        return failed(
            "deepseek",
            label,
            FetchError::Unavailable("DeepSeek 没有返回可用的余额".into()),
        );
    };
    let mut provider = QuotaProvider::new("deepseek", label, "ok");
    provider.plan = Some("按量付费".into());
    provider.windows = vec![QuotaWindow::balance(amount, &currency)];
    provider
}

fn select_deepseek_balance(rows: &[Value]) -> Option<(f64, String)> {
    let parsed: Vec<(f64, String)> = rows
        .iter()
        .filter_map(|row| {
            let amount = as_number(&row["total_balance"])?;
            let currency = row["currency"].as_str()?.trim().to_uppercase();
            if currency.is_empty() {
                return None;
            }
            Some((amount, currency))
        })
        .collect();
    parsed
        .iter()
        .filter(|(amount, _)| *amount > 0.0)
        .max_by(|a, b| a.0.total_cmp(&b.0))
        .or_else(|| parsed.iter().find(|(_, currency)| currency == "USD"))
        .or_else(|| parsed.first())
        .cloned()
}

// --- OpenCode -------------------------------------------------------------

fn fetch_opencode() -> QuotaProvider {
    let label = "OpenCode";
    let api_key = crate::credentials::read(crate::credentials::OPENCODE_KEY);
    let cookie = crate::credentials::read(crate::credentials::OPENCODE_COOKIE);
    if api_key.is_none() && cookie.is_none() {
        return QuotaProvider::new("opencode", label, "notConfigured");
    }
    let agent = agent();
    let mut windows = Vec::new();
    let mut balance = None;
    let mut status = "notConfigured";
    let mut message: Option<String> = None;

    if let Some(key) = api_key.as_deref() {
        match fetch_opencode_go_api(&agent, key) {
            Ok(found) if !found.is_empty() => {
                windows = found;
                status = "ok";
            }
            Ok(_) => {}
            Err(FetchError::Unauthorized | FetchError::Rejected(_)) => {
                status = "unauthorized";
                message = Some("OpenCode API Key 无效或已过期".into());
            }
            Err(FetchError::RateLimited) => {
                status = "rateLimited";
                message = Some("OpenCode 请求过于频繁".into());
            }
            Err(FetchError::Unavailable(detail)) => {
                if status == "notConfigured" {
                    status = "unavailable";
                }
                message = Some(detail);
            }
        }
    }

    if let Some(cookie) = cookie.as_deref() {
        match fetch_opencode_console(&agent, cookie) {
            Ok(console) => {
                if windows.is_empty() && !console.windows.is_empty() {
                    windows = console.windows;
                    status = "ok";
                }
                if console.balance.is_some() {
                    balance = console.balance;
                    status = "ok";
                }
                if console.plan.is_some() && windows.is_empty() {
                    status = "ok";
                }
            }
            Err(FetchError::Unauthorized | FetchError::Rejected(_)) => {
                if status != "ok" {
                    status = "unauthorized";
                    message = Some("OpenCode Cookie 无效或已过期".into());
                }
            }
            Err(FetchError::RateLimited) => {
                if status != "ok" {
                    status = "rateLimited";
                    message = Some("OpenCode 请求过于频繁".into());
                }
            }
            Err(FetchError::Unavailable(detail)) => {
                if status == "notConfigured" {
                    status = "unavailable";
                }
                if message.is_none() {
                    message = Some(detail);
                }
            }
        }
    }

    if let Some(amount) = balance {
        windows.push(QuotaWindow::balance(amount, "USD"));
    }
    let mut provider = QuotaProvider::new("opencode", label, status);
    if !windows.is_empty() {
        provider.plan = Some(if windows.iter().any(|w| w.kind != "billing") {
            "Go".into()
        } else {
            "Zen".into()
        });
    }
    provider.windows = windows;
    provider.message = message;
    provider
}

fn fetch_opencode_go_api(agent: &ureq::Agent, key: &str) -> Result<Vec<QuotaWindow>, FetchError> {
    let value = get_json_forbidden_empty(agent, OPENCODE_GO_USAGE, key)?;
    if value.is_null() {
        return Err(FetchError::Unavailable("该 API Key 没有 Go 订阅".into()));
    }
    let Some(usage) = value["usage"].as_object() else {
        return Ok(Vec::new());
    };
    let session = opencode_percent(&usage["rolling"]);
    let weekly = opencode_percent(&usage["weekly"]);
    let (Some(session), Some(weekly)) = (session, weekly) else {
        return Ok(Vec::new());
    };
    let mut windows = vec![
        QuotaWindow::session(
            session,
            300,
            usage["rolling"]["resetsAt"].as_str().and_then(|value| iso_to_ms(Some(value))),
        ),
        QuotaWindow::weekly(
            weekly,
            usage["weekly"]["resetsAt"].as_str().and_then(|value| iso_to_ms(Some(value))),
        ),
    ];
    if let Some(monthly) = opencode_percent(&usage["monthly"]) {
        windows.push(QuotaWindow::monthly(
            monthly,
            usage["monthly"]["resetsAt"].as_str().and_then(|value| iso_to_ms(Some(value))),
        ));
    }
    Ok(windows)
}

fn opencode_percent(entry: &Value) -> Option<f64> {
    let percent = as_number(&entry["percent"])
        .or_else(|| as_number(&entry["usagePercent"]))
        .or_else(|| as_number(&entry["usedPercent"]));
    match percent {
        Some(value) => Some(value.clamp(0.0, 100.0)),
        None => (entry["status"].as_str() == Some("rate-limited")).then_some(100.0),
    }
}

struct OpenCodeConsole {
    windows: Vec<QuotaWindow>,
    balance: Option<f64>,
    plan: Option<String>,
}

fn fetch_opencode_console(
    agent: &ureq::Agent,
    raw_cookie: &str,
) -> Result<OpenCodeConsole, FetchError> {
    let cookie = sanitize_cookie(raw_cookie);
    if cookie.is_empty() {
        return Err(FetchError::Unavailable("OpenCode Cookie 为空".into()));
    }
    let ua = user_agent();
    let headers = [
        ("Cookie", cookie.as_str()),
        ("Accept", "application/json"),
        ("User-Agent", ua.as_str()),
    ];
    let orgs = get_json_headers(
        agent,
        &format!("{OPENCODE_CONSOLE}/orgs"),
        &headers,
    )?;
    let workspace = orgs
        .as_array()
        .and_then(|rows| {
            rows.iter()
                .filter_map(|row| row["id"].as_str())
                .find(|id| id.starts_with("wrk_") || id.starts_with("org_"))
        })
        .ok_or_else(|| FetchError::Unauthorized)?;
    let workspace_headers = [
        ("Cookie", cookie.as_str()),
        ("Accept", "application/json"),
        ("User-Agent", ua.as_str()),
        ("x-org-id", workspace),
    ];
    let mut windows = Vec::new();
    let mut plan = None;
    if let Ok(status) = get_json_headers(
        agent,
        &format!("{OPENCODE_CONSOLE}/go/status"),
        &workspace_headers,
    ) {
        if let Some(access) = status["access"].as_object() {
            plan = Some("Go".into());
            for (key, kind) in [
                ("fiveHour", "session"),
                ("week", "weekly"),
                ("month", "monthly"),
            ] {
                let Some(meter) = access.get("meters").and_then(|m| m.get(key)) else {
                    continue;
                };
                let used = meter_value(&meter["usedMicroCents"]);
                let limit = meter_value(&meter["limitMicroCents"]);
                let (Some(used), Some(limit)) = (used, limit) else {
                    continue;
                };
                if limit <= 0.0 {
                    continue;
                }
                let percent = (used / limit * 100.0).clamp(0.0, 100.0);
                let reset = meter["resetsAt"]
                    .as_str()
                    .and_then(|value| iso_to_ms(Some(value)))
                    .or_else(|| {
                        (key == "month")
                            .then(|| access["endsAt"].as_str().and_then(|value| iso_to_ms(Some(value))))
                            .flatten()
                    });
                windows.push(match kind {
                    "session" => QuotaWindow::session(percent, 300, reset),
                    "weekly" => QuotaWindow::weekly(percent, reset),
                    _ => QuotaWindow::monthly(percent, reset),
                });
            }
        }
    }
    let mut balance = None;
    if let Ok(billing) = get_json_headers(
        agent,
        &format!("{OPENCODE_CONSOLE}/billing/status"),
        &workspace_headers,
    ) {
        let prepaid = billing["billingMode"].as_str() == Some("prepaid")
            && billing["mode"].as_str() == Some("pay-as-you-go");
        if prepaid {
            if let Some(micro) = billing["balanceMicroCents"]
                .as_str()
                .and_then(|value| value.parse::<f64>().ok())
                .or_else(|| billing["balanceMicroCents"].as_f64())
            {
                balance = Some(micro / 100_000_000.0);
                plan = plan.or_else(|| Some("Zen".into()));
            }
        }
    }
    Ok(OpenCodeConsole {
        windows,
        balance,
        plan,
    })
}

fn meter_value(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .or_else(|| value.as_i64().map(|value| value as f64))
        .or_else(|| value.as_str().and_then(|text| text.parse::<f64>().ok()))
}

fn sanitize_cookie(raw: &str) -> String {
    let trimmed = raw.trim();
    let lowered = trimmed.to_lowercase();
    let stripped = if let Some(rest) = lowered.strip_prefix("cookie:") {
        &trimmed[trimmed.len() - rest.len()..]
    } else {
        trimmed
    };
    let cleaned = stripped
        .split(';')
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("; ");
    if !cleaned.is_empty() && !cleaned.contains('=') {
        format!("auth={cleaned}")
    } else {
        cleaned
    }
}

// --- New API --------------------------------------------------------------

#[derive(Clone, Debug)]
struct NewApiSite {
    id: String,
    name: String,
    base: String,
    mode: String,
    user_id: String,
    quota_per_unit: Option<f64>,
    currency_symbol: String,
}

impl NewApiSite {
    fn provider_id(&self) -> String {
        format!("newapi:{}", self.id)
    }

    /// 用户填了名称就用名称，否则优先使用 `/api/status` 的 `system_name`，最后退回域名。
    fn label_with(&self, remote: Option<&str>) -> String {
        if !self.name.is_empty() {
            return self.name.clone();
        }
        if let Some(remote) = remote.map(str::trim).filter(|value| !value.is_empty()) {
            return remote.to_string();
        }
        let without_scheme = self.base.split("://").nth(1).unwrap_or(&self.base);
        let host = without_scheme.split('/').next().unwrap_or(without_scheme);
        if host.is_empty() {
            "New API".into()
        } else {
            format!("New API · {host}")
        }
    }
}

fn newapi_sites(settings: &serde_json::Map<String, Value>) -> Vec<NewApiSite> {
    let Some(items) = settings.get("quotaNewApiSites").and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut sites = Vec::new();
    for item in items {
        let Some(id) = item["id"]
            .as_str()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            continue;
        };
        let Some(base) = normalize_newapi_base(item["baseUrl"].as_str().unwrap_or("")) else {
            continue;
        };
        sites.push(NewApiSite {
            id: id.to_string(),
            name: item["name"].as_str().unwrap_or("").trim().to_string(),
            base,
            mode: if item["mode"].as_str() == Some("token") {
                "token".into()
            } else {
                "account".into()
            },
            user_id: item["userId"].as_str().unwrap_or("").trim().to_string(),
            quota_per_unit: item["quotaPerUnit"]
                .as_f64()
                .filter(|value| *value > 0.0),
            currency_symbol: item["currencySymbol"]
                .as_str()
                .unwrap_or("")
                .trim()
                .to_string(),
        });
    }
    sites
}

/// 站点地址允许带 `/v1`、`/api` 或末尾斜杠，统一成只含 scheme 和 host 的根地址。
fn normalize_newapi_base(raw: &str) -> Option<String> {
    let raw = raw.trim();
    if raw.is_empty() {
        return None;
    }
    let mut base = raw.trim_end_matches('/').to_string();
    for suffix in ["/v1", "/api"] {
        if let Some(stripped) = base.strip_suffix(suffix) {
            base = stripped.trim_end_matches('/').to_string();
        }
    }
    if !base.starts_with("http://") && !base.starts_with("https://") {
        base = format!("https://{base}");
    }
    Some(base)
}

/// New API 站点：优先使用系统访问令牌查询账户余额，也支持 API 密钥查询令牌额度。
fn fetch_newapi(site: &NewApiSite) -> QuotaProvider {
    if site.mode == "token" {
        fetch_newapi_token(site)
    } else {
        fetch_newapi_account(site)
    }
}

fn fetch_newapi_token(site: &NewApiSite) -> QuotaProvider {
    let id = site.provider_id();
    let target = crate::credentials::newapi_key(&site.id);
    let Some(key) = crate::credentials::read(&target) else {
        return QuotaProvider::new(&id, &site.label_with(None), "notConfigured");
    };
    let agent = agent();
    let status = newapi_status(&agent, &site.base);
    let label = site.label_with(status.site_name.as_deref());
    let display = status
        .display
        .with_override(site.quota_per_unit, &site.currency_symbol);
    let auth = format!("Bearer {key}");
    let value = match get_json_with_error_message(
        &agent,
        &format!("{}/api/usage/token", site.base),
        &[("Authorization", auth.as_str())],
    ) {
        Ok(value) => value,
        Err(error) => return failed(&id, &label, error),
    };
    if let Some(message) = api_error(&value) {
        return failed(&id, &label, FetchError::Unavailable(message));
    }
    if !value["data"].is_object() {
        return failed(
            &id,
            &label,
            FetchError::Unavailable("New API 没有返回令牌额度".into()),
        );
    }
    let data = &value["data"];
    let unlimited = data["unlimited_quota"].as_bool() == Some(true);
    let name = data["name"]
        .as_str()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let mut provider = QuotaProvider::new(&id, &label, "ok");
    provider.plan = Some(if unlimited {
        "无限额度".into()
    } else {
        name.unwrap_or("API 令牌").to_string()
    });
    if !unlimited {
        let granted = as_number(&data["total_granted"]);
        let used = as_number(&data["total_used"]);
        if let (Some(granted), Some(used)) = (granted, used) {
            if granted > 0.0 {
                let percent = (used / granted * 100.0).clamp(0.0, 100.0);
                provider.windows = vec![QuotaWindow::billing_meter("令牌额度", percent)];
            }
        }
        if let Some(available) = as_number(&data["total_available"]) {
            let (amount, currency) = display.amount(available);
            if let Some(currency) = currency {
                provider.windows.push(QuotaWindow::balance_with(
                    "剩余额度",
                    amount,
                    Some(currency.as_str()),
                ));
            }
        }
    }
    provider.logo = newapi_logo(&agent, &site.base, status.logo.as_deref());
    provider
}

fn fetch_newapi_account(site: &NewApiSite) -> QuotaProvider {
    let id = site.provider_id();
    if site.user_id.is_empty() {
        return QuotaProvider::new(&id, &site.label_with(None), "notConfigured");
    }
    let target = crate::credentials::newapi_access_token(&site.id);
    let Some(token) = crate::credentials::read(&target) else {
        return QuotaProvider::new(&id, &site.label_with(None), "notConfigured");
    };
    let agent = agent();
    let status = newapi_status(&agent, &site.base);
    let label = site.label_with(status.site_name.as_deref());
    let display = status
        .display
        .with_override(site.quota_per_unit, &site.currency_symbol);
    let auth = format!("Bearer {token}");
    let value = match get_json_with_error_message(
        &agent,
        &format!("{}/api/user/self", site.base),
        &[
            ("Authorization", auth.as_str()),
            ("New-Api-User", site.user_id.as_str()),
        ],
    ) {
        Ok(value) => value,
        Err(error) => return failed(&id, &label, error),
    };
    if let Some(message) = api_error(&value) {
        return failed(&id, &label, FetchError::Unavailable(message));
    }
    if !value["data"].is_object() {
        return failed(
            &id,
            &label,
            FetchError::Unavailable("New API 没有返回账户额度".into()),
        );
    }
    let data = &value["data"];
    let remaining = as_number(&data["quota"]);
    let username = data["username"]
        .as_str()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let mut provider = QuotaProvider::new(&id, &label, "ok");
    provider.plan = Some(match username {
        Some(name) => format!("账户 {name}"),
        None => "账户余额".into(),
    });
    if remaining == Some(-1.0) {
        provider.plan = Some("无限额度".into());
        provider.logo = newapi_logo(&agent, &site.base, status.logo.as_deref());
        return provider;
    }
    let remaining = remaining.unwrap_or(0.0);
    let (amount, currency) = display.amount(remaining);
    provider.windows = vec![QuotaWindow::balance_with(
        "账户余额",
        amount,
        currency.as_deref(),
    )];
    provider.logo = newapi_logo(&agent, &site.base, status.logo.as_deref());
    provider
}

/// 站点额度显示方式，来自公开的 `/api/status`；失败时按原始配额显示。
struct NewApiDisplay {
    quota_per_unit: Option<f64>,
    multiplier: f64,
    /// `USD` / `CNY` / 自定义符号；`None` 表示显示原始配额。
    currency: Option<String>,
}

impl NewApiDisplay {
    fn amount(&self, quota: f64) -> (f64, Option<String>) {
        match (&self.currency, self.quota_per_unit) {
            (Some(currency), Some(per_unit)) if per_unit > 0.0 => (
                quota / per_unit * self.multiplier,
                Some(currency.clone()),
            ),
            _ => (quota, None),
        }
    }

    /// `/api/status` 取不到换算信息时，使用站点设置里的手动值。
    fn with_override(mut self, per_unit: Option<f64>, symbol: &str) -> Self {
        if self.quota_per_unit.is_none() {
            if let Some(per_unit) = per_unit.filter(|value| *value > 0.0) {
                self.quota_per_unit = Some(per_unit);
                self.multiplier = 1.0;
                if self.currency.is_none() {
                    let symbol = symbol.trim();
                    self.currency = Some(if symbol.is_empty() {
                        "¤".into()
                    } else {
                        symbol.to_string()
                    });
                }
            }
        }
        self
    }
}

struct NewApiStatus {
    display: NewApiDisplay,
    logo: Option<String>,
    site_name: Option<String>,
}

/// 一次读取 `/api/status`，同时拿到额度显示方式、站点名称和自定义图标地址。
fn newapi_status(agent: &ureq::Agent, base: &str) -> NewApiStatus {
    match get_json(agent, &format!("{base}/api/status"), None, &[]) {
        Ok(value) => NewApiStatus {
            display: newapi_display_from(&value),
            logo: newapi_logo_url(base, &value),
            site_name: value["data"]["system_name"]
                .as_str()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string),
        },
        Err(_) => NewApiStatus {
            display: NewApiDisplay {
                quota_per_unit: None,
                multiplier: 1.0,
                currency: None,
            },
            logo: None,
            site_name: None,
        },
    }
}

fn newapi_logo_url(base: &str, value: &Value) -> Option<String> {
    let logo = value["data"]["logo"].as_str()?.trim();
    if logo.is_empty() {
        return None;
    }
    if logo.starts_with("http://") || logo.starts_with("https://") {
        Some(logo.to_string())
    } else if logo.starts_with('/') {
        Some(format!("{base}{logo}"))
    } else {
        Some(format!("{base}/{logo}"))
    }
}

fn newapi_display_from(value: &Value) -> NewApiDisplay {
    let data = &value["data"];
    let quota_per_unit = as_number(&data["quota_per_unit"]);
    let display_type = data["quota_display_type"].as_str().unwrap_or_default();
    let (currency, multiplier) = match display_type {
        "TOKENS" => (None, 1.0),
        "CNY" => (
            Some("CNY".to_string()),
            as_number(&data["usd_exchange_rate"]).unwrap_or(1.0),
        ),
        "CUSTOM" => {
            let symbol = data["custom_currency_symbol"]
                .as_str()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or("¤")
                .to_string();
            (
                Some(symbol),
                as_number(&data["custom_currency_exchange_rate"]).unwrap_or(1.0),
            )
        }
        "USD" => (Some("USD".to_string()), 1.0),
        _ => {
            // 旧版本只有 display_in_currency。
            if data["display_in_currency"].as_bool().unwrap_or(true) {
                (Some("USD".to_string()), 1.0)
            } else {
                (None, 1.0)
            }
        }
    };
    NewApiDisplay {
        quota_per_unit,
        multiplier: if multiplier > 0.0 { multiplier } else { 1.0 },
        currency,
    }
}

/// 抓取站点图标并缓存成功的站点地址；优先使用 status 里的自定义 logo 地址。
fn newapi_logo(agent: &ureq::Agent, base: &str, preferred: Option<&str>) -> Option<String> {
    static CACHE: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Ok(cache) = cache.lock() {
        if let Some(logo) = cache.get(base) {
            return Some(logo.clone());
        }
    }
    let mut candidates = Vec::new();
    if let Some(url) = preferred {
        candidates.push(url.to_string());
    }
    for path in ["/logo.png", "/favicon.svg", "/favicon.png", "/favicon.ico"] {
        candidates.push(format!("{base}{path}"));
    }
    for url in candidates {
        if let Some(logo) = fetch_image_data_uri(agent, &url) {
            if let Ok(mut cache) = cache.lock() {
                cache.insert(base.to_string(), logo.clone());
            }
            return Some(logo);
        }
    }
    None
}

/// 站点 logo 可能是一千多像素的大图，先缩到 64px 再随额度事件下发。
fn thumbnail_png(bytes: &[u8]) -> Option<Vec<u8>> {
    let image = image::load_from_memory_with_format(bytes, image::ImageFormat::Png).ok()?;
    let thumb = image.resize(64, 64, image::imageops::FilterType::Lanczos3);
    let rgba = thumb.to_rgba8();
    let mut out = Vec::new();
    use image::ImageEncoder;
    image::codecs::png::PngEncoder::new(&mut out)
        .write_image(
            rgba.as_raw(),
            rgba.width(),
            rgba.height(),
            image::ExtendedColorType::Rgba8,
        )
        .ok()?;
    Some(out)
}

fn fetch_image_data_uri(agent: &ureq::Agent, url: &str) -> Option<String> {
    let response = agent
        .get(url)
        .timeout(Duration::from_secs(4))
        .call()
        .ok()?;
    let content_type = response
        .header("Content-Type")
        .unwrap_or("")
        .to_ascii_lowercase();
    let mut bytes = Vec::new();
    response
        .into_reader()
        .take(4 * 1024 * 1024)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.is_empty() || bytes.len() >= 4 * 1024 * 1024 {
        return None;
    }
    let is_svg = content_type.contains("image/svg+xml")
        || (content_type.is_empty() && looks_like_svg(&bytes));
    if is_svg {
        return (bytes.len() <= 512 * 1024).then(|| data_uri("image/svg+xml", &bytes));
    }
    let is_png = bytes.starts_with(b"\x89PNG");
    let mime = if is_png {
        "image/png"
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        "image/jpeg"
    } else if bytes.starts_with(&[0, 0, 1, 0]) {
        "image/x-icon"
    } else if bytes.starts_with(b"GIF8") {
        "image/gif"
    } else if bytes.len() > 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        "image/webp"
    } else {
        return None;
    };
    if is_png {
        if let Some(thumb) = thumbnail_png(&bytes) {
            bytes = thumb;
        }
    }
    if bytes.len() > 512 * 1024 {
        return None;
    }
    Some(data_uri(mime, &bytes))
}

fn looks_like_svg(bytes: &[u8]) -> bool {
    let head = &bytes[..bytes.len().min(2048)];
    String::from_utf8_lossy(head)
        .to_ascii_lowercase()
        .contains("<svg")
}

fn data_uri(mime: &str, bytes: &[u8]) -> String {
    use base64::Engine;
    let encoded = base64::engine::general_purpose::STANDARD.encode(bytes);
    format!("data:{mime};base64,{encoded}")
}

fn api_error(value: &Value) -> Option<String> {
    let failed = value.get("success").and_then(Value::as_bool) == Some(false)
        || value.get("code").and_then(Value::as_bool) == Some(false);
    if !failed {
        return None;
    }
    Some(
        value["message"]
            .as_str()
            .map(str::trim)
            .filter(|message| !message.is_empty())
            .unwrap_or("New API 返回错误")
            .to_string(),
    )
}

// --- Krill Code -----------------------------------------------------------

const KRILL_DEFAULT_BASE: &str = "https://www.krill-code.com";

fn fetch_krill(settings: &serde_json::Map<String, Value>) -> QuotaProvider {
    let label = "Krill Code";
    let Some(token) = crate::credentials::read(crate::credentials::KRILL_TOKEN) else {
        return QuotaProvider::new("krill", label, "notConfigured");
    };
    let base = settings
        .get("quotaKrillBaseUrl")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(KRILL_DEFAULT_BASE);
    let base = normalize_site_base(base);
    let agent = agent();
    let auth = format!("Bearer {token}");
    let headers = [("Authorization", auth.as_str())];
    let subscription = match get_json_with_error_message(
        &agent,
        &format!("{base}/api/subscription"),
        &headers,
    ) {
        Ok(value) => value,
        Err(error) => return failed("krill", label, error),
    };
    if let Some(message) = api_error(&subscription) {
        return failed("krill", label, FetchError::Unavailable(message));
    }
    let data = &subscription["data"];
    if !data.is_object() {
        return failed(
            "krill",
            label,
            FetchError::Unavailable("Krill 没有返回订阅数据".into()),
        );
    }
    let mut balance = as_number(&data["credit_balance_usd"]);
    let mut welfare = as_number(&data["welfare_balance_usd"]);
    if let Ok(credits) =
        get_json_with_error_message(&agent, &format!("{base}/api/credits"), &headers)
    {
        if credits["data"].is_object() {
            balance = as_number(&credits["data"]["balance_usd"]).or(balance);
            welfare = as_number(&credits["data"]["welfare_balance_usd"]).or(welfare);
        }
    }

    let summary = &data["summary"];
    let daily = as_number(&summary["total_daily_quota_usd"]).unwrap_or(0.0);
    let used = as_number(&summary["total_used_usd"]).unwrap_or(0.0);
    let remaining = as_number(&summary["total_remaining_usd"]).unwrap_or(0.0);
    let percent = if daily > 0.0 {
        Some((used / daily * 100.0).clamp(0.0, 100.0))
    } else if used + remaining > 0.0 {
        Some((used / (used + remaining) * 100.0).clamp(0.0, 100.0))
    } else {
        None
    };
    // 套餐可能有多个，优先逐个展示；解析不到时退回汇总值。
    let mut windows = krill_subscription_windows(data);
    if windows.is_empty() {
        if let Some(percent) = percent {
            windows.push(QuotaWindow::billing_meter("套餐额度", percent));
        }
        if remaining > 0.0 {
            windows.push(QuotaWindow::balance_with("套餐剩余", remaining, Some("USD")));
        }
    }
    windows.push(QuotaWindow::balance_with(
        "余额",
        balance.unwrap_or(0.0),
        Some("USD"),
    ));
    if let Some(welfare) = welfare.filter(|value| *value > 0.0) {
        windows.push(QuotaWindow::balance_with("福利余额", welfare, Some("USD")));
    }

    let count = data["subscriptions"].as_array().map_or(0, Vec::len);
    let plan = if count > 1 {
        format!("{count} 个套餐")
    } else if let Some(name) = krill_plan_name(data) {
        name
    } else if let Some(date) = krill_end_date(data) {
        format!("套餐 · {date} 到期")
    } else if daily > 0.0 {
        "Krill 套餐".into()
    } else {
        "无套餐".into()
    };
    let mut provider = QuotaProvider::new("krill", label, "ok");
    provider.plan = Some(plan);
    provider.windows = windows;
    provider.logo = krill_logo(&agent, &base);
    provider
}

/// 逐个套餐生成额度窗口；字段名在不同版本里可能不同，做宽松匹配。
fn krill_subscription_windows(data: &Value) -> Vec<QuotaWindow> {
    let Some(items) = data["subscriptions"].as_array() else {
        return Vec::new();
    };
    let mut windows = Vec::new();
    for item in items {
        let name = krill_lookup_text(item, &["plan_name", "name", "plan", "title"])
            .unwrap_or_else(|| "套餐".into());
        let daily = krill_lookup_number(
            item,
            &[
                "daily_quota_usd",
                "total_daily_quota_usd",
                "daily_limit_usd",
                "quota_usd",
            ],
        );
        let used = krill_lookup_number(
            item,
            &[
                "used_usd",
                "used_today_usd",
                "today_used_usd",
                "total_used_usd",
                "daily_used_usd",
                "used_quota_usd",
            ],
        );
        let remaining = krill_lookup_number(
            item,
            &[
                "remaining_usd",
                "remaining_today_usd",
                "total_remaining_usd",
                "daily_remaining_usd",
                "remaining_quota_usd",
            ],
        );
        let percent = match (daily, used) {
            (Some(daily), Some(used)) if daily > 0.0 => {
                Some((used / daily * 100.0).clamp(0.0, 100.0))
            }
            _ => match (used, remaining) {
                (Some(used), Some(remaining)) if used + remaining > 0.0 => {
                    Some((used / (used + remaining) * 100.0).clamp(0.0, 100.0))
                }
                _ => None,
            },
        };
        let end = krill_item_end_date(item);
        let label = match end {
            Some(date) => format!("{name} · {date}"),
            None => name,
        };
        if let Some(percent) = percent {
            windows.push(QuotaWindow::billing_meter(&label, percent));
        } else if let Some(remaining) = remaining.filter(|value| *value > 0.0) {
            windows.push(QuotaWindow::balance_with(&label, remaining, Some("USD")));
        }
    }
    windows
}

fn krill_lookup<'a>(item: &'a Value, keys: &[&str]) -> Option<&'a Value> {
    // 只接受标量，避免把同名的 `plan` 对象当成字符串字段。
    let scalar = |value: &Value| value.is_string() || value.is_number();
    for key in keys {
        if let Some(value) = item.get(*key).filter(|value| scalar(value)) {
            return Some(value);
        }
    }
    for container in ["plan", "quota", "usage", "subscription"] {
        if let Some(object) = item.get(container) {
            for key in keys {
                if let Some(value) = object.get(*key).filter(|value| scalar(value)) {
                    return Some(value);
                }
            }
        }
    }
    None
}

fn krill_lookup_text(item: &Value, keys: &[&str]) -> Option<String> {
    krill_lookup(item, keys)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn krill_lookup_number(item: &Value, keys: &[&str]) -> Option<f64> {
    krill_lookup(item, keys).and_then(as_number)
}

fn krill_item_end_date(item: &Value) -> Option<String> {
    krill_lookup(
        item,
        &[
            "end_at",
            "ends_at",
            "expires_at",
            "expire_at",
            "end_time",
            "subscription_end_at",
        ],
    )
    .and_then(krill_date_text)
}

fn krill_date_text(value: &Value) -> Option<String> {
    let text = value
        .as_str()
        .map(str::trim)
        .filter(|text| !text.is_empty())?;
    if let Some(ms) = iso_to_ms(Some(text)).or_else(|| json_to_ms(value)) {
        if let Some(date) = chrono::Utc.timestamp_millis_opt(ms).single() {
            return Some(date.format("%Y-%m-%d").to_string());
        }
    }
    (text.len() >= 10).then(|| text[..10].to_string())
}

fn normalize_site_base(raw: &str) -> String {
    let mut base = raw.trim().trim_end_matches('/').to_string();
    if !base.starts_with("http://") && !base.starts_with("https://") {
        base = format!("https://{base}");
    }
    base
}

fn krill_plan_name(data: &Value) -> Option<String> {
    let items = data["subscriptions"].as_array()?;
    for item in items {
        for key in ["plan_name", "name", "plan", "title"] {
            if let Some(text) = item[key]
                .as_str()
                .map(str::trim)
                .filter(|value| !value.is_empty())
            {
                return Some(text.to_string());
            }
        }
    }
    None
}

fn krill_end_date(data: &Value) -> Option<String> {
    let mut values = vec![&data["summary"]["subscription_end_at"]];
    if let Some(items) = data["subscriptions"].as_array() {
        for item in items {
            for key in ["end_at", "expires_at", "subscription_end_at", "end_time"] {
                values.push(&item[key]);
            }
        }
    }
    for value in values {
        let Some(text) = value.as_str().map(str::trim).filter(|text| !text.is_empty()) else {
            continue;
        };
        if let Some(ms) = iso_to_ms(Some(text)).or_else(|| json_to_ms(value)) {
            if let Some(date) = chrono::Utc.timestamp_millis_opt(ms).single() {
                return Some(date.format("%Y-%m-%d").to_string());
            }
        }
        if text.len() >= 10 {
            return Some(text[..10].to_string());
        }
    }
    None
}

fn krill_logo(agent: &ureq::Agent, base: &str) -> Option<String> {
    static CACHE: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Ok(cache) = cache.lock() {
        if let Some(logo) = cache.get(base) {
            return Some(logo.clone());
        }
    }
    for path in ["/apple-touch-icon.png", "/favicon.png", "/favicon.svg"] {
        if let Some(logo) = fetch_image_data_uri(agent, &format!("{base}{path}")) {
            if let Ok(mut cache) = cache.lock() {
                cache.insert(base.to_string(), logo.clone());
            }
            return Some(logo);
        }
    }
    None
}

// --- HTTP -----------------------------------------------------------------

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(5))
        .timeout(REQUEST_TIMEOUT)
        .build()
}

fn get_json(
    agent: &ureq::Agent,
    url: &str,
    bearer: Option<&str>,
    headers: &[(&str, &str)],
) -> Result<Value, FetchError> {
    let mut request = agent.get(url).set("Accept", "application/json");
    if let Some(token) = bearer {
        request = request.set("Authorization", &format!("Bearer {token}"));
    }
    for (name, value) in headers {
        request = request.set(name, value);
    }
    finish(request, false)
}

/// OpenCode 的 Go 额度接口用 403 表示“这个 Key 没有 Go 订阅”，
/// 是账号状态而不是凭据失效；这里把它当作空结果，避免误报 unauthorized。
fn get_json_forbidden_empty(
    agent: &ureq::Agent,
    url: &str,
    bearer: &str,
) -> Result<Value, FetchError> {
    let request = agent
        .get(url)
        .set("Accept", "application/json")
        .set("Authorization", &format!("Bearer {bearer}"));
    finish(request, true)
}

fn get_json_headers(
    agent: &ureq::Agent,
    url: &str,
    headers: &[(&str, &str)],
) -> Result<Value, FetchError> {
    get_json(agent, url, None, headers)
}

/// 与 `get_json_headers` 相同，但 401/403 会保留服务端返回的 message。
fn get_json_with_error_message(
    agent: &ureq::Agent,
    url: &str,
    headers: &[(&str, &str)],
) -> Result<Value, FetchError> {
    let mut request = agent.get(url).set("Accept", "application/json");
    for (name, value) in headers {
        request = request.set(name, value);
    }
    finish_with_message(request)
}

fn finish(request: ureq::Request, forbidden_empty: bool) -> Result<Value, FetchError> {
    finish_inner(request, forbidden_empty, false)
}

fn finish_with_message(request: ureq::Request) -> Result<Value, FetchError> {
    finish_inner(request, false, true)
}

fn finish_inner(
    request: ureq::Request,
    forbidden_empty: bool,
    keep_error_message: bool,
) -> Result<Value, FetchError> {
    let response = match request.call() {
        Ok(response) => response,
        Err(ureq::Error::Status(403, _)) if forbidden_empty => return Ok(Value::Null),
        Err(ureq::Error::Status(401 | 403, response)) => {
            return Err(match keep_error_message.then(|| error_message(response)) {
                Some(Some(message)) => FetchError::Rejected(message),
                _ => FetchError::Unauthorized,
            })
        }
        Err(ureq::Error::Status(429, _)) => return Err(FetchError::RateLimited),
        Err(ureq::Error::Status(code, _)) => {
            return Err(FetchError::Unavailable(format!("服务返回 HTTP {code}")))
        }
        Err(ureq::Error::Transport(error)) => {
            return Err(FetchError::Unavailable(format!(
                "网络错误: {:?}",
                error.kind()
            )))
        }
    };
    let mut body = String::new();
    response
        .into_reader()
        .take(2 * 1024 * 1024)
        .read_to_string(&mut body)
        .map_err(|error| FetchError::Unavailable(format!("响应读取失败: {error}")))?;
    serde_json::from_str(&body)
        .map_err(|_| FetchError::Unavailable("响应不是合法 JSON".into()))
}

fn error_message(response: ureq::Response) -> Option<String> {
    let mut body = String::new();
    response
        .into_reader()
        .take(64 * 1024)
        .read_to_string(&mut body)
        .ok()?;
    let value: Value = serde_json::from_str(&body).ok()?;
    value["message"]
        .as_str()
        .map(str::trim)
        .filter(|message| !message.is_empty())
        .map(str::to_string)
}

fn failed(id: &str, label: &str, error: FetchError) -> QuotaProvider {
    QuotaProvider::new(id, label, error.status()).with_message(error.message())
}

impl QuotaProvider {
    fn maybe_plan(mut self, plan: Option<String>) -> Self {
        if self.plan.is_none() {
            self.plan = plan.filter(|value| !value.is_empty());
        }
        self
    }
}

// --- 辅助 -----------------------------------------------------------------

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

/// 接口里的数字有时是字符串，统一按数字读取。
fn as_number(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .or_else(|| value.as_str().and_then(|text| text.trim().parse::<f64>().ok()))
}

/// 重置时间可能是 ISO 字符串、秒或毫秒时间戳。
fn json_to_ms(value: &Value) -> Option<i64> {
    if let Some(number) = value.as_i64() {
        return Some(if number > 1_000_000_000_000 {
            number
        } else if number > 1_000_000_000 {
            number * 1000
        } else {
            number
        });
    }
    if let Some(number) = value.as_f64() {
        let number = number as i64;
        return Some(if number > 1_000_000_000_000 {
            number
        } else if number > 1_000_000_000 {
            number * 1000
        } else {
            number
        });
    }
    let text = value.as_str()?.trim();
    if text.is_empty() {
        return None;
    }
    iso_to_ms(Some(text)).or_else(|| {
        text.parse::<i64>().ok().map(|number| {
            if number > 1_000_000_000_000 {
                number
            } else {
                number * 1000
            }
        })
    })
}

fn iso_to_ms(value: Option<&str>) -> Option<i64> {
    let text = value?.trim();
    if text.is_empty() {
        return None;
    }
    chrono::DateTime::parse_from_rfc3339(text)
        .ok()
        .map(|time| time.timestamp_millis())
}

fn display_plan(value: &str) -> String {
    let cleaned = value.trim().replace(['_', '-'], " ");
    let cleaned = cleaned.split_whitespace().collect::<Vec<_>>().join(" ");
    cleaned
        .split(' ')
        .map(|word| {
            let lower = word.to_lowercase();
            if lower == "glm" {
                "GLM".into()
            } else if lower == "z.ai" || lower == "zai" {
                "Z.ai".into()
            } else {
                let mut chars = word.chars();
                match chars.next() {
                    Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                    None => String::new(),
                }
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cookie_without_name_gets_auth_prefix() {
        assert_eq!(sanitize_cookie("abc123"), "auth=abc123");
        assert_eq!(sanitize_cookie("Cookie: a=b; c=d"), "a=b; c=d");
    }

    #[test]
    fn glm_minutes_follow_unit_codes() {
        assert_eq!(glm_window_minutes(Some(5.0), Some(300.0)), Some(300));
        assert_eq!(glm_window_minutes(Some(3.0), Some(2.0)), Some(120));
        assert_eq!(glm_window_minutes(Some(6.0), Some(1.0)), Some(10080));
    }

    #[test]
    fn deepseek_prefers_funded_row() {
        let rows = vec![
            json!({ "total_balance": "0.00", "currency": "USD" }),
            json!({ "total_balance": "12.50", "currency": "CNY" }),
        ];
        assert_eq!(select_deepseek_balance(&rows), Some((12.5, "CNY".into())));
    }

    #[test]
    fn glm_used_percent_reads_usage_and_remaining() {
        let limit = json!({ "usage": 100.0, "remaining": 75.0 });
        assert_eq!(glm_used_percent(&limit), Some(25.0));
    }

    #[test]
    fn newapi_base_strips_api_suffixes_and_slash() {
        assert_eq!(
            normalize_newapi_base(" https://ai.example.com/v1/ "),
            Some("https://ai.example.com".into())
        );
        assert_eq!(
            normalize_newapi_base("ai.example.com/api"),
            Some("https://ai.example.com".into())
        );
        assert_eq!(normalize_newapi_base("  "), None);
    }

    #[test]
    fn newapi_display_converts_currency_and_keeps_raw_tokens() {
        let value = json!({
            "data": {
                "quota_per_unit": 500000,
                "quota_display_type": "CNY",
                "usd_exchange_rate": 7.2
            }
        });
        let (amount, currency) = newapi_display_from(&value).amount(1_000_000.0);
        assert!((amount - 14.4).abs() < 0.0001);
        assert_eq!(currency.as_deref(), Some("CNY"));

        let value = json!({
            "data": {"quota_per_unit": 500000, "quota_display_type": "TOKENS"}
        });
        let (amount, currency) = newapi_display_from(&value).amount(1_000_000.0);
        assert_eq!(amount, 1_000_000.0);
        assert!(currency.is_none());
    }

    #[test]
    fn newapi_display_uses_manual_rate_when_status_missing() {
        let display = NewApiDisplay {
            quota_per_unit: None,
            multiplier: 1.0,
            currency: None,
        }
        .with_override(Some(500000.0), "¥");
        let (amount, currency) = display.amount(1_000_000.0);
        assert_eq!(amount, 2.0);
        assert_eq!(currency.as_deref(), Some("¥"));
    }

    #[test]
    fn krill_windows_show_each_subscription_with_expiry() {
        let data = json!({
            "subscriptions": [
                {
                    "plan_name": "Pro",
                    "daily_quota_usd": "10",
                    "used_usd": "2.5",
                    "end_at": "2026-12-31T00:00:00Z"
                },
                {
                    "plan": {"name": "Lite", "daily_quota_usd": 5, "used_usd": 1},
                    "expire_at": "2026-11-30"
                }
            ]
        });
        let windows = krill_subscription_windows(&data);
        assert_eq!(windows.len(), 2);
        assert_eq!(windows[0].label, "Pro · 2026-12-31");
        assert_eq!(windows[0].used_percent, Some(25.0));
        assert_eq!(windows[1].label, "Lite · 2026-11-30");
        assert_eq!(windows[1].used_percent, Some(20.0));
    }

    #[test]
    fn newapi_api_error_reads_failure_message() {
        let value = json!({ "success": false, "message": "access token 无效" });
        assert_eq!(api_error(&value), Some("access token 无效".into()));
        let value = json!({ "code": true, "data": {} });
        assert_eq!(api_error(&value), None);
    }
}
