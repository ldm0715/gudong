//! 翻译：OpenAI 兼容 LLM、DeepL、Azure Translator、MyMemory。
//!
//! 网络请求全部在 sidecar 的独立线程完成，避免阻塞 stdio 主循环。
//! 日志只记录引擎与错误，不记录原文、译文或密钥。
//!
//! 接口以官网文档为准：
//! - OpenAI 兼容：`POST {base}/chat/completions`、`GET {base}/models`
//! - DeepL：`POST {api|api-free}.deepl.com/v2/translate`，`DeepL-Auth-Key`
//! - Azure：`POST api.cognitive.microsofttranslator.com/translate?api-version=3.0`
//! - MyMemory：`GET api.mymemory.translated.net/get?q=&langpair=src|dst`

use serde_json::{json, Map, Value};
use std::io::Read;
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::credentials;
use crate::rpc::{self, RpcError, State, ERR_INTERNAL, ERR_INVALID_PARAMS, ERR_METHOD_NOT_FOUND};

const DEFAULT_LLM_BASE: &str = "https://api.openai.com/v1";
const DEFAULT_TARGET: &str = "zh-CN";
const AUTO_ORDER: &[&str] = &[
    "llm",
    "deepl",
    "caiyun",
    "microsoftFree",
    "mymemory",
];
/// 彩云官方文档提供的测试 Token，不保证可用；未配置个人 Token 时使用。
const CAIYUN_TEST_TOKEN: &str = "3975l6lr5pcbvidl6jl2";
const MAX_TEXT_CHARS: usize = 20_000;
/// MyMemory 的 q 参数上限是 500 字节，留出余量。
const MYMEMORY_CHUNK_BYTES: usize = 450;

const DEFAULT_USER_PROMPT: &str = "Translate to {{to}} (output translation only):\n\n{{text}}";

const DEFAULT_PROMPT: &str = "You are a professional {{to}} native translator who needs to fluently translate text into {{to}}.

## Translation Rules
1. Output only the translated content, without explanations or additional content.
2. Keep the same number of paragraphs and the same format as the original text.
3. If the text contains HTML tags, place the tags correctly in the translation and retain them.
4. If the text contains code blocks, translate comments but leave the code as-is and preserve formatting.
5. Leave content that should not be translated (proper nouns, code, placeholders) unchanged.
6. Output translation directly, without separators or extra text.

{{title_prompt}}{{summary_prompt}}{{terms_prompt}}";

pub struct Job {
    pub id: Value,
    pub method: String,
    pub params: Value,
}

/// 启动翻译线程，返回任务队列。每个请求串行处理，避免同时打出多条大模型请求。
pub fn start(state: Arc<State>, tx: Sender<Value>) -> Sender<Job> {
    let (job_tx, job_rx) = std::sync::mpsc::channel::<Job>();
    let _ = std::thread::Builder::new()
        .name("translate".into())
        .spawn(move || {
            for job in job_rx {
                let result = match job.method.as_str() {
                    "translate.run" => run(&state, &job.params),
                    "translate.models" => models(&state, &job.params),
                    "translate.setSecret" => set_secret(&job.params),
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
        });
    job_tx
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Provider {
    Llm,
    DeepL,
    Caiyun,
    MicrosoftFree,
    MyMemory,
}

impl Provider {
    fn id(self) -> &'static str {
        match self {
            Provider::Llm => "llm",
            Provider::DeepL => "deepl",
            Provider::Caiyun => "caiyun",
            Provider::MicrosoftFree => "microsoftFree",
            Provider::MyMemory => "mymemory",
        }
    }
}

struct Language {
    code: &'static str,
    prompt: &'static str,
    deepl_target: &'static str,
    deepl_source: &'static str,
    azure: &'static str,
}

const LANGUAGES: &[Language] = &[
    Language {
        code: "zh-CN",
        prompt: "简体中文",
        deepl_target: "ZH-HANS",
        deepl_source: "ZH",
        azure: "zh-Hans",
    },
    Language {
        code: "zh-TW",
        prompt: "繁體中文",
        deepl_target: "ZH-HANT",
        deepl_source: "ZH",
        azure: "zh-Hant",
    },
    Language {
        code: "en",
        prompt: "English",
        deepl_target: "EN-US",
        deepl_source: "EN",
        azure: "en",
    },
    Language {
        code: "ja",
        prompt: "日本語",
        deepl_target: "JA",
        deepl_source: "JA",
        azure: "ja",
    },
    Language {
        code: "ko",
        prompt: "한국어",
        deepl_target: "KO",
        deepl_source: "KO",
        azure: "ko",
    },
    Language {
        code: "fr",
        prompt: "Français",
        deepl_target: "FR",
        deepl_source: "FR",
        azure: "fr",
    },
    Language {
        code: "de",
        prompt: "Deutsch",
        deepl_target: "DE",
        deepl_source: "DE",
        azure: "de",
    },
    Language {
        code: "es",
        prompt: "Español",
        deepl_target: "ES",
        deepl_source: "ES",
        azure: "es",
    },
    Language {
        code: "ru",
        prompt: "Русский",
        deepl_target: "RU",
        deepl_source: "RU",
        azure: "ru",
    },
    Language {
        code: "pt",
        prompt: "Português",
        deepl_target: "PT-BR",
        deepl_source: "PT",
        azure: "pt",
    },
    Language {
        code: "it",
        prompt: "Italiano",
        deepl_target: "IT",
        deepl_source: "IT",
        azure: "it",
    },
];

fn language(code: &str) -> Option<&'static Language> {
    LANGUAGES
        .iter()
        .find(|language| language.code.eq_ignore_ascii_case(code))
}

fn prompt_name(code: &str) -> String {
    language(code)
        .map(|language| language.prompt.to_string())
        .unwrap_or_else(|| code.to_string())
}

fn setting<'a>(settings: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    settings
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

fn run(state: &State, params: &Value) -> Result<Value, RpcError> {
    let text = params
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err(RpcError::new(ERR_INVALID_PARAMS, "text is required"));
    }
    if trimmed.chars().count() > MAX_TEXT_CHARS {
        return Err(RpcError::new(
            ERR_INVALID_PARAMS,
            format!("文本过长，单次最多 {MAX_TEXT_CHARS} 字符"),
        ));
    }

    let settings = state.config.snapshot();
    let target = params
        .get("to")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .or_else(|| setting(&settings, "translateTarget"))
        .unwrap_or(DEFAULT_TARGET)
        .to_string();
    let requested = params
        .get("provider")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .or_else(|| setting(&settings, "translateProvider"))
        .unwrap_or("auto");
    let explicit = matches!(
        requested,
        "llm" | "deepl" | "caiyun" | "microsoftFree" | "mymemory"
    );
    let candidates = if explicit {
        vec![provider_from_id(requested).expect("known provider")]
    } else {
        auto_candidates(&settings)
    };

    let mut last_error = String::new();
    let started = Instant::now();
    for provider in candidates {
        if started.elapsed() >= Duration::from_secs(50) {
            return Err(RpcError::new(
                ERR_INTERNAL,
                "翻译超时，请检查网络或更换翻译服务",
            ));
        }
        let result = match provider {
            Provider::Llm => {
                translate_llm(&settings, text, &target).map(|text| (text, None, provider))
            }
            Provider::DeepL => translate_deepl(&settings, trimmed, &target)
                .map(|(text, from)| (text, from, provider)),
            Provider::Caiyun => translate_caiyun(&settings, text, &target)
                .map(|(text, from)| (text, from, provider)),
            Provider::MicrosoftFree => match translate_microsoft_free(&settings, text, &target) {
                Ok((text, from)) => Ok((text, from, provider)),
                Err(message) => {
                    // 实验接口失效时退回 MyMemory，避免自动模式直接不可用。
                    crate::log(&format!(
                        "translate: microsoftFree failed: {message}; falling back to mymemory"
                    ));
                    translate_mymemory(&settings, text, &target)
                        .map(|(text, from)| (text, from, Provider::MyMemory))
                }
            },
            Provider::MyMemory => translate_mymemory(&settings, text, &target)
                .map(|(text, from)| (text, from, provider)),
        };

        match result {
            Ok((translated, from, actual)) => {
                return Ok(json!({
                    "text": translated,
                    "provider": actual.id(),
                    "to": target,
                    "from": from,
                }));
            }
            Err(message) => {
                crate::log(&format!("translate: {} failed: {message}", provider.id()));
                last_error = message;
            }
        }
    }

    Err(RpcError::new(
        ERR_INTERNAL,
        if last_error.is_empty() {
            "没有可用的翻译引擎".to_string()
        } else {
            last_error
        },
    ))
}

fn provider_from_id(id: &str) -> Option<Provider> {
    Some(match id {
        "llm" => Provider::Llm,
        "deepl" => Provider::DeepL,
        "caiyun" => Provider::Caiyun,
        "microsoftFree" => Provider::MicrosoftFree,
        "mymemory" => Provider::MyMemory,
        _ => return None,
    })
}

/// 自动模式按设置顺序列出可用引擎，某个引擎失败后继续尝试下一个。
fn auto_candidates(settings: &Map<String, Value>) -> Vec<Provider> {
    let mut candidates = Vec::new();
    for id in auto_order(settings) {
        let provider = match id.as_str() {
            // Base URL 始终有默认值，配好模型和 Key 就认为大模型可用。
            "llm"
                if setting(settings, "translateModel").is_some()
                    && credentials::read(credentials::LLM).is_some() =>
            {
                Some(Provider::Llm)
            }
            "deepl" if credentials::read(credentials::DEEPL).is_some() => Some(Provider::DeepL),
            "caiyun" => Some(Provider::Caiyun),
            "microsoftFree" => Some(Provider::MicrosoftFree),
            "mymemory" => Some(Provider::MyMemory),
            _ => None,
        };
        if let Some(provider) = provider {
            if !candidates.contains(&provider) {
                candidates.push(provider);
            }
        }
    }
    if candidates.is_empty() {
        candidates.push(Provider::MyMemory);
    }
    candidates
}

/// 用户自定义优先级；未知项忽略，缺项按默认顺序补齐。
fn auto_order(settings: &Map<String, Value>) -> Vec<String> {
    let mut order = Vec::new();
    if let Some(items) = settings.get("translateAutoOrder").and_then(Value::as_array) {
        for item in items {
            let Some(id) = item.as_str() else { continue };
            if AUTO_ORDER.contains(&id) && !order.iter().any(|existing| existing == id) {
                order.push(id.to_string());
            }
        }
    }
    for id in AUTO_ORDER {
        if !order.iter().any(|existing| existing == id) {
            order.push((*id).to_string());
        }
    }
    order
}

fn explicit_source(settings: &Map<String, Value>) -> Option<String> {
    setting(settings, "translateSource")
        .filter(|value| !value.eq_ignore_ascii_case("auto"))
        .map(str::to_string)
}

fn agent(timeout_secs: u64) -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(5))
        .timeout(Duration::from_secs(timeout_secs))
        .build()
}

/// 接受 `https://host/v1`、`https://host/v1/` 或完整的 chat completions / models 地址。
fn normalize_base(base: &str) -> String {
    let trimmed = base.trim().trim_end_matches('/');
    let trimmed = trimmed.strip_suffix("/chat/completions").unwrap_or(trimmed);
    let trimmed = trimmed.strip_suffix("/models").unwrap_or(trimmed);
    trimmed.trim_end_matches('/').to_string()
}

fn translate_llm(
    settings: &Map<String, Value>,
    text: &str,
    target: &str,
) -> Result<String, String> {
    let key = credentials::read(credentials::LLM).ok_or("未配置大模型 API Key")?;
    let base = setting(settings, "translateBaseUrl").unwrap_or(DEFAULT_LLM_BASE);
    let model = setting(settings, "translateModel").ok_or("未配置翻译模型")?;
    let template = setting(settings, "translateSystemPrompt").unwrap_or(DEFAULT_PROMPT);
    let user_template = setting(settings, "translateUserPrompt").unwrap_or(DEFAULT_USER_PROMPT);
    let target_name = prompt_name(target);
    let prompt = build_prompt(template, &target_name);
    let user_message = build_user_prompt(user_template, &target_name, text);
    let body = json!({
        "model": model,
        "temperature": 0.2,
        "stream": false,
        "messages": [
            { "role": "system", "content": prompt },
            { "role": "user", "content": user_message }
        ]
    });
    let url = format!("{}/chat/completions", normalize_base(base));
    let response = agent(25)
        .post(&url)
        .set("Authorization", &format!("Bearer {key}"))
        .set("Content-Type", "application/json")
        .send_string(&body.to_string())
        .map_err(|error| http_error("大模型", error))?;
    let payload = read_json(response, "大模型")?;
    payload["choices"][0]["message"]["content"]
        .as_str()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| clean_llm_output(&value))
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "大模型返回内容为空".to_string())
}

/// 用户提示词支持两种写法：
/// - 含 `{{text}}` 的完整模板：替换 `{{to}}` / `{{text}}` 后直接使用。
/// - 普通文字：作为额外要求拼在 `Translate to {to}.` 之后，再附上原文。
fn build_user_prompt(template: &str, target: &str, text: &str) -> String {
    let template = template.trim();
    if template.contains("{{text}}") {
        return template
            .replace("{{to}}", target)
            .replace("{{text}}", text);
    }
    if template.contains("{{to}}") {
        let mut message = template.replace("{{to}}", target);
        message.push_str("\n\n");
        message.push_str(text);
        return message;
    }
    if template.is_empty() {
        return format!("Translate to {target} (output translation only):\n\n{text}");
    }
    format!("Translate to {target} (output translation only):\n{template}\n\n{text}")
}

/// 去掉模型偶尔加上的“译文：”前缀或 ``` 代码围栏。
fn clean_llm_output(text: &str) -> String {
    let mut value = text.trim().to_string();
    for prefix in [
        "译文：",
        "译文:",
        "翻译：",
        "翻译:",
        "Translation:",
        "Translated text:",
    ] {
        if let Some(rest) = value.strip_prefix(prefix) {
            value = rest.trim().to_string();
        }
    }
    if value.starts_with("```") && value.ends_with("```") && value.len() >= 6 {
        value = value[3..value.len() - 3].trim().to_string();
    }
    value
}

fn models(state: &State, params: &Value) -> Result<Value, RpcError> {
    let settings = state.config.snapshot();
    let base = params
        .get("baseUrl")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .or_else(|| setting(&settings, "translateBaseUrl"))
        .unwrap_or(DEFAULT_LLM_BASE);
    let key = params
        .get("apiKey")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .or_else(|| credentials::read(credentials::LLM))
        .ok_or_else(|| RpcError::new(ERR_INVALID_PARAMS, "请先填写大模型 API Key"))?;
    let url = format!("{}/models", normalize_base(base));
    let response = agent(30)
        .get(&url)
        .set("Authorization", &format!("Bearer {key}"))
        .call()
        .map_err(|error| RpcError::new(ERR_INTERNAL, http_error("模型列表", error)))?;
    let payload = read_json(response, "模型列表").map_err(|message| RpcError::new(ERR_INTERNAL, message))?;
    let mut list: Vec<String> = payload["data"]
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item["id"].as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    list.sort();
    list.dedup();
    if list.is_empty() {
        return Err(RpcError::new(
            ERR_INTERNAL,
            "服务端没有返回模型列表，请检查 base URL",
        ));
    }
    Ok(json!({ "models": list }))
}

fn translate_deepl(
    settings: &Map<String, Value>,
    text: &str,
    target: &str,
) -> Result<(String, Option<String>), String> {
    let key = credentials::read(credentials::DEEPL).ok_or("未配置 DeepL API Key")?;
    let target_code = language(target)
        .map(|language| language.deepl_target.to_string())
        .unwrap_or_else(|| target.to_string());
    let mut body = json!({
        "text": [text],
        "target_lang": target_code,
    });
    if let Some(source) = explicit_source(settings) {
        let source_code = language(&source)
            .map(|language| language.deepl_source.to_string())
            .unwrap_or(source);
        body["source_lang"] = json!(source_code);
    }

    let free = key.ends_with(":fx");
    let first = if free {
        "https://api-free.deepl.com"
    } else {
        "https://api.deepl.com"
    };
    let second = if free {
        "https://api.deepl.com"
    } else {
        "https://api-free.deepl.com"
    };

    let mut last_error = String::new();
    for host in [first, second] {
        let response = agent(20)
            .post(&format!("{host}/v2/translate"))
            .set("Authorization", &format!("DeepL-Auth-Key {key}"))
            .set("Content-Type", "application/json")
            .send_string(&body.to_string());
        match response {
            Ok(response) => {
                let payload = read_json(response, "DeepL")?;
                let translated = payload["translations"][0]["text"]
                    .as_str()
                    .map(str::to_string)
                    .ok_or("DeepL 返回内容为空")?;
                let from = payload["translations"][0]["detected_source_language"]
                    .as_str()
                    .map(|value| value.to_lowercase());
                return Ok((translated, from));
            }
            Err(ureq::Error::Status(403, response)) => {
                // 免费 / 付费密钥用错域名时，DeepL 返回 403 并提示正确域名。
                let body = read_body(response);
                let hinted = body.to_lowercase();
                let wrong_host = (host.contains("api-free") && hinted.contains("api.deepl.com"))
                    || (host.contains("api.deepl.com") && hinted.contains("api-free.deepl.com"));
                if !wrong_host {
                    return Err(format!("DeepL HTTP 403: {}", extract_error(&body)));
                }
                last_error = extract_error(&body);
            }
            Err(error) => return Err(http_error("DeepL", error)),
        }
    }
    Err(format!("DeepL 域名不匹配: {last_error}"))
}

fn translate_caiyun(
    settings: &Map<String, Value>,
    text: &str,
    target: &str,
) -> Result<(String, Option<String>), String> {
    let source = explicit_source(settings).unwrap_or_else(|| detect_source(text).to_string());
    if source.eq_ignore_ascii_case(target) {
        return Ok((text.to_string(), Some(source)));
    }
    let trans_type = caiyun_trans_type(target, &source)?;
    let token = credentials::read(credentials::CAIYUN)
        .unwrap_or_else(|| CAIYUN_TEST_TOKEN.to_string());
    let body = json!({
        "source": [text],
        "trans_type": trans_type,
        "detect": trans_type.starts_with("auto2"),
        "media": "text",
        "request_id": format!("guduo-{}", chrono::Local::now().timestamp_millis()),
    });
    let response = agent(20)
        .post("https://api.interpreter.caiyunai.com/v1/translator")
        .set("Content-Type", "application/json")
        .set("x-authorization", &format!("token {token}"))
        .send_string(&body.to_string())
        .map_err(|error| http_error("彩云小译", error))?;
    let payload = read_json(response, "彩云小译")?;
    let translated = payload["target"][0]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| {
            payload["message"]
                .as_str()
                .map(str::to_string)
                .unwrap_or_else(|| "彩云小译返回内容为空".to_string())
        })?;
    Ok((translated, Some(source)))
}

fn caiyun_trans_type(target: &str, source: &str) -> Result<String, String> {
    let target_key = target.trim().to_ascii_lowercase();
    let source_key = source.trim().to_ascii_lowercase();
    if target_key == "zh-cn" {
        return Ok("auto2zh".to_string());
    }
    if target_key == "zh-tw" {
        let source_code = match source_key.as_str() {
            "zh-cn" | "zh" => "zh",
            "zh-tw" | "zh-hant" => "zh-Hant",
            "en" => "en",
            "ja" => "ja",
            "ko" => "ko",
            "de" => "de",
            "es" => "es",
            "fr" => "fr",
            "it" => "it",
            "pt" => "pt",
            "ru" => "ru",
            _ => return Err(format!("彩云小译无法从 {source} 翻译为繁体中文")),
        };
        return Ok(format!("{source_code}2zh-Hant"));
    }
    let target_code = match target_key.as_str() {
        "en" => "en",
        "ja" => "ja",
        "ko" => "ko",
        _ => return Err(format!("彩云小译不支持目标语言：{target}")),
    };
    let source_code = match source_key.as_str() {
        "zh-cn" | "zh" => "zh",
        "zh-tw" | "zh-hant" => "zh-Hant",
        _ => {
            return Err(format!(
                "彩云小译只支持中文译为{target}，当前源语言：{source}"
            ))
        }
    };
    Ok(format!("{source_code}2{target_code}"))
}

/// Edge 内部免密钥接口。没有官方文档和 SLA，失效时由调用方回退 MyMemory。
fn translate_microsoft_free(
    settings: &Map<String, Value>,
    text: &str,
    target: &str,
) -> Result<(String, Option<String>), String> {
    let target_code = language(target)
        .map(|language| language.azure.to_string())
        .unwrap_or_else(|| target.to_string());
    let source_code = explicit_source(settings)
        .map(|source| {
            language(&source)
                .map(|language| language.azure.to_string())
                .unwrap_or(source)
        })
        .unwrap_or_default();
    let url = format!(
        "https://edge.microsoft.com/translate/translatetext?from={}&to={}&isEnterpriseClient=false",
        urlencoding::encode(&source_code),
        urlencoding::encode(&target_code)
    );
    let response = agent(20)
        .post(&url)
        .set("Content-Type", "application/json")
        .set(
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
             (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0",
        )
        .send_string(&json!([text]).to_string())
        .map_err(|error| http_error("微软免密钥", error))?;
    let payload = read_json(response, "微软免密钥")?;
    let translated = payload[0]["translations"][0]["text"]
        .as_str()
        .map(str::to_string)
        .ok_or("微软免密钥返回内容为空")?;
    let from = payload[0]["detectedLanguage"]["language"]
        .as_str()
        .map(str::to_string);
    Ok((translated, from))
}

fn translate_mymemory(
    settings: &Map<String, Value>,
    text: &str,
    target: &str,
) -> Result<(String, Option<String>), String> {
    let source = explicit_source(settings).unwrap_or_else(|| detect_source(text).to_string());
    if source.eq_ignore_ascii_case(target) {
        return Ok((text.to_string(), Some(source)));
    }
    let email = setting(settings, "translateMyMemoryEmail");
    let mut lines = Vec::new();
    for line in text.split('\n') {
        if line.trim().is_empty() {
            lines.push(String::new());
            continue;
        }
        let mut translated = String::new();
        for chunk in chunk_by_bytes(line, MYMEMORY_CHUNK_BYTES) {
            translated.push_str(&mymemory_chunk(&chunk, &source, target, email)?);
        }
        lines.push(translated);
    }
    Ok((lines.join("\n"), Some(source)))
}

fn mymemory_chunk(
    text: &str,
    source: &str,
    target: &str,
    email: Option<&str>,
) -> Result<String, String> {
    let mut url = format!(
        "https://api.mymemory.translated.net/get?q={}&langpair={}|{}",
        urlencoding::encode(text),
        urlencoding::encode(source),
        urlencoding::encode(target)
    );
    if let Some(email) = email {
        url.push_str("&de=");
        url.push_str(&urlencoding::encode(email));
    }
    let response = agent(15)
        .get(&url)
        .set("Accept", "application/json")
        .call()
        .map_err(|error| http_error("MyMemory", error))?;
    let payload = read_json(response, "MyMemory")?;
    let status = payload["responseStatus"]
        .as_u64()
        .or_else(|| {
            payload["responseStatus"]
                .as_str()
                .and_then(|value| value.parse().ok())
        })
        .unwrap_or(0);
    if status != 200 {
        let detail = payload["responseDetails"]
            .as_str()
            .unwrap_or("MyMemory 请求被拒绝");
        return Err(format!(
            "MyMemory 额度不足或请求被拒绝（匿名 5000 字符/天，填写邮箱可提高到 50000）：{detail}"
        ));
    }
    payload["responseData"]["translatedText"]
        .as_str()
        .map(str::to_string)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "MyMemory 返回内容为空".to_string())
}

fn set_secret(params: &Value) -> Result<Value, RpcError> {
    let provider = params
        .get("provider")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let target = match provider {
        "llm" => credentials::LLM,
        "deepl" => credentials::DEEPL,
        "caiyun" => credentials::CAIYUN,
        _ => {
            return Err(RpcError::new(
                ERR_INVALID_PARAMS,
                format!("unknown provider: {provider}"),
            ))
        }
    };
    let key = params
        .get("key")
        .and_then(Value::as_str)
        .unwrap_or_default();
    credentials::write(target, key)
        .map_err(|error| RpcError::new(ERR_INTERNAL, format!("保存密钥失败: {error}")))?;
    Ok(json!({
        "ok": true,
        "configured": !key.trim().is_empty(),
    }))
}

fn build_prompt(template: &str, target: &str) -> String {
    let mut prompt = template.replace("{{to}}", target);
    // 其余占位符当前没有内容可填，直接移除，避免把 {{...}} 发给模型。
    while let Some(start) = prompt.find("{{") {
        let Some(offset) = prompt[start..].find("}}") else {
            break;
        };
        prompt.replace_range(start..start + offset + 2, "");
    }
    let mut collapsed = String::with_capacity(prompt.len());
    let mut blank = 0;
    for line in prompt.lines() {
        if line.trim().is_empty() {
            blank += 1;
            if blank > 1 {
                continue;
            }
        } else {
            blank = 0;
        }
        collapsed.push_str(line);
        collapsed.push('\n');
    }
    collapsed.trim().to_string()
}

/// MyMemory 不支持自动识别，用字符集做保守推断。
fn detect_source(text: &str) -> &'static str {
    let mut han = 0;
    let mut kana = 0;
    let mut hangul = 0;
    let mut cyrillic = 0;
    let mut latin = 0;
    for ch in text.chars() {
        if ('\u{3040}'..='\u{30FF}').contains(&ch) {
            kana += 1;
        } else if ('\u{AC00}'..='\u{D7AF}').contains(&ch) {
            hangul += 1;
        } else if ('\u{4E00}'..='\u{9FFF}').contains(&ch) {
            han += 1;
        } else if ('\u{0400}'..='\u{04FF}').contains(&ch) {
            cyrillic += 1;
        } else if ch.is_ascii_alphabetic() {
            latin += 1;
        }
    }
    if kana > 0 {
        "ja"
    } else if hangul > 0 {
        "ko"
    } else if han > 0 {
        "zh-CN"
    } else if cyrillic > latin {
        "ru"
    } else {
        "en"
    }
}

/// 先按句子切分，再贪心拼到字节上限；超长句子硬切。保留原有空白。
fn chunk_by_bytes(line: &str, max_bytes: usize) -> Vec<String> {
    let mut sentences = Vec::new();
    let mut current = String::new();
    for ch in line.chars() {
        current.push(ch);
        if matches!(ch, '。' | '！' | '？' | '；' | '.' | '!' | '?' | ';') {
            sentences.push(std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        sentences.push(current);
    }

    let mut chunks = Vec::new();
    let mut current = String::new();
    for sentence in sentences {
        if sentence.len() > max_bytes {
            if !current.is_empty() {
                chunks.push(std::mem::take(&mut current));
            }
            let mut piece = String::new();
            for ch in sentence.chars() {
                if piece.len() + ch.len_utf8() > max_bytes && !piece.is_empty() {
                    chunks.push(std::mem::take(&mut piece));
                }
                piece.push(ch);
            }
            if !piece.is_empty() {
                chunks.push(piece);
            }
            continue;
        }
        if current.len() + sentence.len() > max_bytes && !current.is_empty() {
            chunks.push(std::mem::take(&mut current));
        }
        current.push_str(&sentence);
    }
    if !current.is_empty() {
        chunks.push(current);
    }
    chunks
}

fn read_body(response: ureq::Response) -> String {
    let mut body = String::new();
    let _ = response
        .into_reader()
        .take(4096)
        .read_to_string(&mut body);
    body
}

fn read_json(response: ureq::Response, label: &str) -> Result<Value, String> {
    let mut body = String::new();
    response
        .into_reader()
        .take(2 * 1024 * 1024)
        .read_to_string(&mut body)
        .map_err(|error| format!("{label} 响应读取失败: {error}"))?;
    serde_json::from_str(&body).map_err(|error| format!("{label} 响应不是合法 JSON: {error}"))
}

fn http_error(label: &str, error: ureq::Error) -> String {
    match error {
        ureq::Error::Status(code, response) => {
            let body = read_body(response);
            let detail = extract_error(&body);
            if detail.is_empty() {
                format!("{label} HTTP {code}")
            } else {
                format!("{label} HTTP {code}: {detail}")
            }
        }
        ureq::Error::Transport(error) => format!("{label} 网络错误: {:?}", error.kind()),
    }
}

/// 从各家错误响应里挑一条可读信息，不回显请求正文。
fn extract_error(body: &str) -> String {
    let Ok(value) = serde_json::from_str::<Value>(body) else {
        return body.trim().chars().take(160).collect();
    };
    for pointer in [
        "/error/message",
        "/message",
        "/responseDetails",
        "/error",
    ] {
        if let Some(message) = value.pointer(pointer).and_then(Value::as_str) {
            if !message.trim().is_empty() {
                return message.trim().chars().take(200).collect();
            }
        }
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prompt_replaces_target_and_drops_empty_placeholders() {
        let prompt = build_prompt("Translate into {{to}}.\n\n{{title_prompt}}\n\n{{terms_prompt}}", "Simplified Chinese");
        assert_eq!(prompt, "Translate into Simplified Chinese.");
    }

    #[test]
    fn base_url_accepts_endpoint_or_root() {
        assert_eq!(normalize_base("https://api.openai.com/v1/"), "https://api.openai.com/v1");
        assert_eq!(
            normalize_base("https://api.openai.com/v1/chat/completions"),
            "https://api.openai.com/v1"
        );
        assert_eq!(
            normalize_base("https://api.openai.com/v1/models"),
            "https://api.openai.com/v1"
        );
    }

    #[test]
    fn chunking_respects_byte_limit_and_preserves_text() {
        let line = "你好。World! This is a longer sentence that should split.";
        let chunks = chunk_by_bytes(line, 20);
        assert!(chunks.iter().all(|chunk| chunk.len() <= 20));
        assert_eq!(chunks.concat(), line);
    }

    #[test]
    fn source_detection_covers_common_scripts() {
        assert_eq!(detect_source("hello world"), "en");
        assert_eq!(detect_source("你好"), "zh-CN");
        assert_eq!(detect_source("こんにちは"), "ja");
        assert_eq!(detect_source("안녕하세요"), "ko");
        assert_eq!(detect_source("привет"), "ru");
    }

    #[test]
    fn user_prompt_substitutes_target_and_text() {
        let message = build_user_prompt(
            "Translate to {{to}}:\n\n{{text}}",
            "Simplified Chinese",
            "hello world",
        );
        assert_eq!(message, "Translate to Simplified Chinese:\n\nhello world");
    }

    #[test]
    fn user_prompt_appends_text_when_placeholder_missing() {
        assert_eq!(
            build_user_prompt("Translate to {{to}}:", "Japanese", "hello"),
            "Translate to Japanese:\n\nhello"
        );
    }

    #[test]
    fn user_prompt_accepts_plain_instructions() {
        assert_eq!(
            build_user_prompt("Keep code unchanged", "Japanese", "hello"),
            "Translate to Japanese (output translation only):\nKeep code unchanged\n\nhello"
        );
    }

    #[test]
    fn llm_output_cleans_prefix_and_fence() {
        assert_eq!(clean_llm_output("译文：你好"), "你好");
        assert_eq!(clean_llm_output("```\n你好\n```"), "你好");
    }

    #[test]
    fn auto_order_uses_custom_priority_and_fills_missing() {
        let value = json!({
            "translateAutoOrder": ["mymemory", "llm", "unknown", "llm"]
        });
        let settings = value.as_object().unwrap();
        assert_eq!(
            auto_order(settings),
            vec!["mymemory", "llm", "deepl", "caiyun", "microsoftFree"]
        );
    }

    #[test]
    fn caiyun_trans_type_covers_supported_directions() {
        assert_eq!(caiyun_trans_type("zh-CN", "en").unwrap(), "auto2zh");
        assert_eq!(caiyun_trans_type("zh-TW", "en").unwrap(), "en2zh-Hant");
        assert_eq!(caiyun_trans_type("en", "zh-CN").unwrap(), "zh2en");
        assert!(caiyun_trans_type("en", "ja").is_err());
        assert!(caiyun_trans_type("fr", "en").is_err());
    }

    #[test]
    fn language_mapping_matches_provider_codes() {
        assert_eq!(language("zh-CN").unwrap().deepl_target, "ZH-HANS");
        assert_eq!(language("zh-CN").unwrap().azure, "zh-Hans");
        assert_eq!(language("en").unwrap().deepl_target, "EN-US");
    }
}
