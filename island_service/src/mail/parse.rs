//! 邮件头与正文的纯文本化。
//!
//! 不渲染 HTML，也不加载远程资源：HTML 只转成文本，链接单独提取给界面。
//! 正文优先 text/plain，缺失时才从 HTML 提取；引用历史和签名在入缓存前剥掉。

use mailparse::{MailAddr, MailHeader, ParsedMail};
use regex::Regex;
use serde::Serialize;
use std::collections::HashSet;
use std::sync::OnceLock;

const MAX_BODY_BYTES: usize = 64 * 1024;
const MAX_LINKS: usize = 20;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParsedHeaders {
    pub subject: String,
    pub from: String,
    pub from_address: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Link {
    pub label: String,
    pub url: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Body {
    pub text: String,
    pub truncated: bool,
    pub links: Vec<Link>,
}

pub fn headers(raw: &[u8]) -> ParsedHeaders {
    let Ok((headers, _)) = mailparse::parse_headers(raw) else {
        return ParsedHeaders {
            subject: String::new(),
            from: String::new(),
            from_address: String::new(),
        };
    };
    let subject = value(&headers, "subject");
    let from = value(&headers, "from");
    let (from, from_address) = display_address(&from);
    ParsedHeaders {
        subject,
        from,
        from_address,
    }
}

fn value(headers: &[MailHeader], key: &str) -> String {
    headers
        .iter()
        .find(|header| header.get_key().eq_ignore_ascii_case(key))
        .map(|header| header.get_value().trim().to_string())
        .unwrap_or_default()
}

fn display_address(raw: &str) -> (String, String) {
    if let Ok(list) = mailparse::addrparse(raw) {
        for address in list.iter() {
            match address {
                MailAddr::Single(single) => {
                    let display = single
                        .display_name
                        .as_deref()
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .unwrap_or(&single.addr)
                        .to_string();
                    return (display, single.addr.clone());
                }
                MailAddr::Group(group) => {
                    if let Some(single) = group.addrs.first() {
                        let display = single
                            .display_name
                            .as_deref()
                            .map(str::trim)
                            .filter(|value| !value.is_empty())
                            .unwrap_or(&single.addr)
                            .to_string();
                        return (display, single.addr.clone());
                    }
                }
            }
        }
    }
    let trimmed = raw.trim().trim_matches('"').to_string();
    (trimmed.clone(), trimmed)
}

/// 把一个 text part 的原始字节按 BODYSTRUCTURE 给出的编码和字符集解码。
pub fn decode_part(
    subtype: &str,
    charset: Option<&str>,
    encoding: &str,
    data: &[u8],
) -> String {
    let charset = charset
        .map(str::trim)
        .map(|value| value.trim_matches('"'))
        .filter(|value| !value.is_empty())
        .unwrap_or("utf-8")
        .to_string();
    let header = format!(
        "Content-Type: text/{subtype}; charset={charset}\r\nContent-Transfer-Encoding: {encoding}\r\n\r\n"
    );
    let mut raw = Vec::with_capacity(header.len() + data.len());
    raw.extend_from_slice(header.as_bytes());
    raw.extend_from_slice(data);
    mailparse::parse_mail(&raw)
        .ok()
        .and_then(|mail| mail.get_body().ok())
        .unwrap_or_else(|| String::from_utf8_lossy(data).into_owned())
}

/// BODYSTRUCTURE 不可用时的兜底：按整封邮件解析，调用方限制读取的字节数。
pub fn fallback(header: &[u8], body: &[u8]) -> (String, String, bool) {
    let mut raw = Vec::with_capacity(header.len() + body.len() + 2);
    raw.extend_from_slice(header);
    if !header.ends_with(b"\r\n\r\n") {
        raw.extend_from_slice(b"\r\n");
    }
    raw.extend_from_slice(body);
    let Ok(mail) = mailparse::parse_mail(&raw) else {
        return (
            String::from_utf8_lossy(body).into_owned(),
            String::new(),
            false,
        );
    };
    let mut plain = String::new();
    let mut html = String::new();
    let mut attachments = false;
    collect_mail(&mail, &mut plain, &mut html, &mut attachments);
    (plain, html, attachments)
}

fn collect_mail(
    mail: &ParsedMail,
    plain: &mut String,
    html: &mut String,
    attachments: &mut bool,
) {
    if mail.subparts.is_empty() {
        let mime = mail.ctype.mimetype.to_ascii_lowercase();
        if mime == "text/plain" {
            if let Ok(text) = mail.get_body() {
                plain.push_str(&text);
                plain.push('\n');
            }
        } else if mime == "text/html" {
            if let Ok(text) = mail.get_body() {
                html.push_str(&text);
                html.push('\n');
            }
        } else if mime != "text/calendar" && mime != "application/ics" {
            *attachments = true;
        }
    } else {
        for part in &mail.subparts {
            collect_mail(part, plain, html, attachments);
        }
    }
}

pub fn body(plain: &str, html: &str) -> Body {
    let plain = normalize(plain);
    let text = if plain.is_empty() {
        html_to_text(html)
    } else {
        plain
    };
    let text = strip_quoted(&text);
    let (text, truncated) = truncate(text, MAX_BODY_BYTES);
    let links = links(html, &text);
    Body {
        text,
        truncated,
        links,
    }
}

pub fn snippet(text: &str) -> String {
    let flat = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut out: String = flat.chars().take(120).collect();
    if flat.chars().count() > 120 {
        out.push('…');
    }
    out
}

fn truncate(text: String, max: usize) -> (String, bool) {
    if text.len() <= max {
        return (text, false);
    }
    let mut end = max;
    while end > 0 && !text.is_char_boundary(end) {
        end -= 1;
    }
    (text[..end].to_string(), true)
}

/// 去掉明显的引用回复和签名。判断保守，找不到明确分隔符就保留原文。
fn strip_quoted(text: &str) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let mut cut = lines.len();
    let mut meaningful = 0usize;
    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        meaningful += 1;
        if meaningful < 3 {
            continue;
        }
        let lower = trimmed.to_ascii_lowercase();
        if (lower.starts_with("on ") && lower.ends_with("wrote:"))
            || lower.contains("-----original message-----")
            || lower.contains("-------- 原始邮件 --------")
            || trimmed == "--"
            || trimmed == "-- "
        {
            cut = index;
            break;
        }
        if trimmed.starts_with("发件人:") || lower.starts_with("from:") {
            let followed_by_headers = lines[index + 1..]
                .iter()
                .take(4)
                .map(|line| line.trim().to_ascii_lowercase())
                .any(|line| {
                    line.starts_with("发送时间:")
                        || line.starts_with("sent:")
                        || line.starts_with("date:")
                });
            if followed_by_headers {
                cut = index;
                break;
            }
        }
    }
    let mut kept = lines[..cut].join("\n");
    let mut kept_lines: Vec<&str> = kept.lines().collect();
    while kept_lines
        .last()
        .is_some_and(|line| line.trim_start().starts_with('>'))
    {
        kept_lines.pop();
    }
    kept = kept_lines.join("\n");
    let trimmed = kept.trim_end();
    if trimmed.is_empty() {
        text.to_string()
    } else {
        trimmed.to_string()
    }
}

pub fn html_to_text(html: &str) -> String {
    let mut text = regex_script()
        .replace_all(html, " ")
        .into_owned();
    text = regex_comment().replace_all(&text, " ").into_owned();
    text = regex_br().replace_all(&text, "\n").into_owned();
    text = regex_li().replace_all(&text, "\n• ").into_owned();
    text = regex_block_close().replace_all(&text, "\n").into_owned();
    text = regex_tag().replace_all(&text, "").into_owned();
    normalize(&decode_entities(&text))
}

fn normalize(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut pending_space = false;
    let mut newlines = 0usize;
    for ch in text.chars() {
        match ch {
            '\r' => {}
            '\n' => {
                while out.ends_with(' ') || out.ends_with('\t') {
                    out.pop();
                }
                if newlines < 2 {
                    out.push('\n');
                }
                newlines += 1;
                pending_space = false;
            }
            ' ' | '\t' | '\u{00a0}' => {
                if newlines == 0 && !out.is_empty() && !pending_space {
                    out.push(' ');
                    pending_space = true;
                }
            }
            other => {
                out.push(other);
                pending_space = false;
                newlines = 0;
            }
        }
    }
    out.trim().to_string()
}

fn decode_entities(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(index) = rest.find('&') {
        out.push_str(&rest[..index]);
        let tail = &rest[index..];
        let Some(end) = tail
            .as_bytes()
            .iter()
            .take(12)
            .position(|byte| *byte == b';')
        else {
            out.push('&');
            rest = &tail[1..];
            continue;
        };
        let entity = &tail[1..end];
        let decoded = match entity {
            "nbsp" | "#160" => Some(' '),
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" | "#39" => Some('\''),
            "middot" | "bull" | "#183" | "#8226" => Some('·'),
            "mdash" => Some('—'),
            "ndash" => Some('–'),
            "hellip" => Some('…'),
            "copy" => Some('©'),
            "reg" => Some('®'),
            other => other
                .strip_prefix("#x")
                .or_else(|| other.strip_prefix("#X"))
                .and_then(|hex| u32::from_str_radix(hex, 16).ok())
                .or_else(|| other.strip_prefix('#').and_then(|dec| dec.parse::<u32>().ok()))
                .and_then(char::from_u32),
        };
        match decoded {
            Some(ch) => {
                out.push(ch);
                rest = &tail[end + 1..];
            }
            None => {
                out.push('&');
                rest = &tail[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

fn links(html: &str, text: &str) -> Vec<Link> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for captures in regex_href().captures_iter(html) {
        let raw = captures
            .get(1)
            .or_else(|| captures.get(2))
            .or_else(|| captures.get(3))
            .map(|value| value.as_str())
            .unwrap_or_default();
        push_link(&mut out, &mut seen, &decode_entities(raw));
        if out.len() >= MAX_LINKS {
            return out;
        }
    }
    for hit in regex_url().find_iter(text) {
        push_link(&mut out, &mut seen, hit.as_str());
        if out.len() >= MAX_LINKS {
            return out;
        }
    }
    out
}

fn push_link(out: &mut Vec<Link>, seen: &mut HashSet<String>, raw: &str) {
    let candidate = raw.trim().trim_end_matches([
        '.', ',', ';', ':', '!', '?', '，', '。', '；', '！', '？', '）', '】', '》',
    ]);
    let Ok(url) = url::Url::parse(candidate) else {
        return;
    };
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return;
    }
    let url = url.to_string();
    if seen.insert(url.clone()) {
        out.push(Link {
            label: url.clone(),
            url,
        });
    }
}

fn regex_script() -> &'static Regex {
    static VALUE: OnceLock<Regex> = OnceLock::new();
    VALUE.get_or_init(|| {
        Regex::new(r"(?is)<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>").expect("script")
    })
}

fn regex_comment() -> &'static Regex {
    static VALUE: OnceLock<Regex> = OnceLock::new();
    VALUE.get_or_init(|| Regex::new(r"(?s)<!--.*?-->").expect("comment"))
}

fn regex_br() -> &'static Regex {
    static VALUE: OnceLock<Regex> = OnceLock::new();
    VALUE.get_or_init(|| Regex::new(r"(?i)<br\s*/?>").expect("br"))
}

fn regex_li() -> &'static Regex {
    static VALUE: OnceLock<Regex> = OnceLock::new();
    VALUE.get_or_init(|| Regex::new(r"(?i)<li\b[^>]*>").expect("li"))
}

fn regex_block_close() -> &'static Regex {
    static VALUE: OnceLock<Regex> = OnceLock::new();
    VALUE.get_or_init(|| {
        Regex::new(
            r"(?i)</(?:p|div|li|tr|h[1-6]|table|section|article|blockquote|ul|ol|header|footer)\s*>",
        )
        .expect("block")
    })
}

fn regex_tag() -> &'static Regex {
    static VALUE: OnceLock<Regex> = OnceLock::new();
    VALUE.get_or_init(|| Regex::new(r"(?s)<[^>]+>").expect("tag"))
}

fn regex_href() -> &'static Regex {
    static VALUE: OnceLock<Regex> = OnceLock::new();
    VALUE.get_or_init(|| {
        Regex::new(r#"(?i)href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#).expect("href")
    })
}

fn regex_url() -> &'static Regex {
    static VALUE: OnceLock<Regex> = OnceLock::new();
    VALUE.get_or_init(|| {
        Regex::new(r#"(?i)https?://[^\s<>"'，。；！？、）】》]+"#).expect("url")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn html_becomes_readable_text_without_tags() {
        let html = r#"<html><style>p{color:red}</style><body><h1>标题</h1><p>第一段&nbsp;文字&amp;更多</p><ul><li>一</li><li>二</li></ul><script>alert(1)</script></body></html>"#;
        let text = html_to_text(html);
        assert!(!text.contains('<'));
        assert!(!text.contains("color:red"));
        assert!(!text.contains("alert"));
        assert!(text.contains("标题"));
        assert!(text.contains("第一段 文字&更多"));
        assert!(text.contains("• 一"));
    }

    #[test]
    fn numeric_entities_are_decoded() {
        assert_eq!(decode_entities("&#20320;&#22909;"), "你好");
        assert_eq!(decode_entities("&#x4F60;&#x597D;"), "你好");
    }

    #[test]
    fn reply_history_and_signature_are_removed() {
        let text = "第一段\n第二段\n第三段\n\nOn Mon, Jan 1, 2026 at 10:00 user wrote:\n> 旧内容";
        assert_eq!(strip_quoted(text), "第一段\n第二段\n第三段");
        let text = "正文第一行\n正文第二行\n正文第三行\n-- \n签名";
        assert_eq!(strip_quoted(text), "正文第一行\n正文第二行\n正文第三行");
    }

    #[test]
    fn short_text_is_not_cut_at_from_line() {
        let text = "Hello\nFrom: someone";
        assert_eq!(strip_quoted(text), text);
    }

    #[test]
    fn truncation_respects_utf8_boundaries() {
        let text = "中".repeat(40_000);
        let (cut, truncated) = truncate(text, 64 * 1024);
        assert!(truncated);
        assert!(cut.is_char_boundary(cut.len()));
        assert!(cut.len() <= 64 * 1024);
    }

    #[test]
    fn links_keep_only_http_and_https() {
        let html = r#"<a href="https://example.com/a">A</a><a href="javascript:alert(1)">B</a>"#;
        let text = "访问 https://example.com/b。";
        let links = links(html, text);
        assert_eq!(links.len(), 2);
        assert!(links.iter().all(|link| link.url.starts_with("https://")));
    }

    #[test]
    fn headers_decode_display_name_and_subject() {
        let raw = "From: =?UTF-8?B?5byg5LiJ?= <a@example.com>\r\nSubject: Hello\r\n\r\n";
        let parsed = headers(raw.as_bytes());
        assert_eq!(parsed.subject, "Hello");
        assert_eq!(parsed.from, "张三");
        assert_eq!(parsed.from_address, "a@example.com");
    }

    #[test]
    fn plain_text_wins_over_html_and_gets_cleaned() {
        let result = body("  正文\n\n\n", "<p>HTML</p>");
        assert_eq!(result.text, "正文");
        assert!(!result.truncated);
    }

    #[test]
    fn fallback_reads_multipart_and_flags_attachment() {
        let header = b"From: a@example.com\r\nSubject: hi\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n";
        let body = b"--b\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nhello\r\n--b\r\nContent-Type: application/pdf\r\n\r\nPDF\r\n--b--\r\n";
        let (plain, html, attachments) = fallback(header, body);
        assert_eq!(plain.trim(), "hello");
        assert!(html.is_empty());
        assert!(attachments);
    }
}
