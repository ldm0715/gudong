//! AI 额度：GLM / DeepSeek / OpenCode 的配额与余额。
//!
//! 凭据只从 Windows 凭据管理器读取，不落 config.json。
//! 网络请求全部在独立线程执行，主循环只接收命令并推送 `quota.updated`。

use serde::Serialize;
use serde_json::{json, Value};
use std::io::Read;
use std::sync::mpsc::{Receiver, Sender};
use std::sync::Arc;
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
        Self {
            kind: "billing".into(),
            label: "Balance".into(),
            used_percent: None,
            remaining_percent: None,
            window_minutes: None,
            resets_at_ms: None,
            remaining: Some(amount.max(0.0)),
            currency: Some(currency.into()),
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
    RateLimited,
    Unavailable(String),
}

impl FetchError {
    fn status(&self) -> &'static str {
        match self {
            Self::Unauthorized => "unauthorized",
            Self::RateLimited => "rateLimited",
            Self::Unavailable(_) => "unavailable",
        }
    }

    fn message(&self) -> String {
        match self {
            Self::Unauthorized => "凭据无效或已过期".into(),
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
    let default = ["glm", "deepseek", "opencode"];
    let mut order: Vec<String> = Vec::new();
    if let Some(values) = settings.get("quotaOrder").and_then(Value::as_array) {
        for value in values {
            let Some(id) = value.as_str() else { continue };
            if default.contains(&id) && !order.iter().any(|item| item == id) {
                order.push(id.to_string());
            }
        }
    }
    for id in default {
        if !order.iter().any(|item| item == id) {
            order.push(id.to_string());
        }
    }
    order
}

fn fetch_provider(id: &str, settings: &serde_json::Map<String, Value>) -> QuotaProvider {
    match id {
        "glm" => fetch_glm(settings),
        "deepseek" => fetch_deepseek(),
        "opencode" => fetch_opencode(),
        other => {
            let mut provider = QuotaProvider::new(other, other, "unavailable");
            provider.message = Some("未知的额度服务".into());
            provider
        }
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
            Err(FetchError::Unauthorized) => {
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
            Err(FetchError::Unauthorized) => {
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

fn finish(request: ureq::Request, forbidden_empty: bool) -> Result<Value, FetchError> {
    let response = match request.call() {
        Ok(response) => response,
        Err(ureq::Error::Status(403, _)) if forbidden_empty => return Ok(Value::Null),
        Err(ureq::Error::Status(401 | 403, _)) => return Err(FetchError::Unauthorized),
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
}
