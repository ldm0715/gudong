//! IMAP over TLS 连接。
//!
//! 只接受连接即加密的 TLS，不做 STARTTLS 和明文降级。163 / 126 要求
//! LOGIN 之前先发 RFC 2971 的 `ID`，所以这两个预设需要手工读问候语。

use native_tls::{Protocol, TlsConnector, TlsStream};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::time::Duration;

use super::store::{Account, AuthType, Provider};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const IO_TIMEOUT: Duration = Duration::from_secs(20);

pub type Stream = TlsStream<TcpStream>;
pub type MailSession = imap::Session<Prefixed<Stream>>;

/// 把已经读掉的问候语原样交回给 imap。
pub struct Prefixed<S> {
    head: Vec<u8>,
    position: usize,
    inner: S,
}

impl<S> Prefixed<S> {
    fn new(head: Vec<u8>, inner: S) -> Self {
        Self {
            head,
            position: 0,
            inner,
        }
    }
}

impl<S: Read> Read for Prefixed<S> {
    fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
        if self.position < self.head.len() {
            let count = (self.head.len() - self.position).min(buffer.len());
            buffer[..count].copy_from_slice(&self.head[self.position..self.position + count]);
            self.position += count;
            Ok(count)
        } else {
            self.inner.read(buffer)
        }
    }
}

impl<S: Write> Write for Prefixed<S> {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        self.inner.write(buffer)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.inner.flush()
    }
}

#[derive(Debug)]
pub enum ConnectError {
    /// 用户名、授权码或令牌被服务器拒绝，需要用户重新授权。
    Auth(String),
    Failed(String),
}

impl ConnectError {
    pub fn message(&self) -> &str {
        match self {
            Self::Auth(message) | Self::Failed(message) => message,
        }
    }

    pub fn is_auth(&self) -> bool {
        matches!(self, Self::Auth(_))
    }
}

pub fn connect(account: &Account, secret: &str) -> Result<MailSession, ConnectError> {
    let (host, port, username) = account.endpoint().map_err(ConnectError::Failed)?;
    let stream = tls_stream(&host, port)?;

    let mut id_rejection = None;
    let mut client = if account.provider.needs_id() {
        let outcome = send_id(stream)?;
        id_rejection = outcome.rejected;
        imap::Client::new(Prefixed::new(outcome.greeting, outcome.stream))
    } else {
        imap::Client::new(Prefixed::new(Vec::new(), stream))
    };

    client
        .read_greeting()
        .map_err(|error| ConnectError::Failed(format!("读取服务器问候失败：{error}")))?;

    match account.auth_type {
        AuthType::Password => client
            .login(username, secret)
            .map_err(|(error, _)| auth_error(error, password_hint(account.provider), id_rejection)),
        AuthType::Oauth2 => {
            let authenticator = OAuth2 {
                user: username,
                token: secret.to_string(),
            };
            client
                .authenticate("XOAUTH2", &authenticator)
                .map_err(|(error, _)| {
                    auth_error(error, "OAuth 令牌被拒绝，请重新登录", id_rejection)
                })
        }
    }
}

fn password_hint(provider: Provider) -> &'static str {
    match provider {
        Provider::Gmail => {
            "Gmail 登录被拒绝：请确认已开启两步验证并使用 16 位应用专用密码，不能使用 Google 登录密码"
        }
        Provider::ICloud => {
            "iCloud 登录被拒绝：请使用 iCloud 邮箱地址和 App 专用密码，而不是 Apple 账户密码"
        }
        Provider::Qq => "QQ 邮箱登录被拒绝：请确认已开启 IMAP 并使用授权码",
        Provider::Mail163 | Provider::Mail126 => {
            "网易邮箱登录被拒绝：请确认已开启 IMAP 并使用客户端授权密码"
        }
        Provider::Exmail => {
            "登录被拒绝：请确认 IMAP 已开启，并使用登录密码或客户端专用密码"
        }
        _ => "登录被拒绝，请检查账号和密码",
    }
}

fn auth_error(
    error: imap::Error,
    base: &str,
    id_rejection: Option<String>,
) -> ConnectError {
    if rejected(&error) {
        let message = match id_rejection {
            Some(reason) => format!("{base}；服务器也拒绝了 ID 命令：{reason}"),
            None => base.to_string(),
        };
        ConnectError::Auth(message)
    } else {
        ConnectError::Failed(format!("{base}：{error}"))
    }
}

struct OAuth2 {
    user: String,
    token: String,
}

impl imap::Authenticator for OAuth2 {
    type Response = String;

    fn process(&self, _: &[u8]) -> Self::Response {
        format!("user={}\x01auth=Bearer {}\x01\x01", self.user, self.token)
    }
}

fn tls_stream(host: &str, port: u16) -> Result<Stream, ConnectError> {
    let address = format!("{host}:{port}");
    let addresses: Vec<SocketAddr> = address
        .to_socket_addrs()
        .map_err(|error| ConnectError::Failed(format!("无法解析 IMAP 服务器：{error}")))?
        .collect();
    let tcp = addresses
        .iter()
        .find_map(|address| TcpStream::connect_timeout(address, CONNECT_TIMEOUT).ok())
        .ok_or_else(|| ConnectError::Failed(format!("无法连接 {host}")))?;
    let _ = tcp.set_read_timeout(Some(IO_TIMEOUT));
    let _ = tcp.set_write_timeout(Some(IO_TIMEOUT));

    let connector = TlsConnector::builder()
        .min_protocol_version(Some(Protocol::Tlsv12))
        .build()
        .map_err(|error| ConnectError::Failed(format!("TLS 初始化失败：{error}")))?;
    connector
        .connect(host, tcp)
        .map_err(|error| ConnectError::Failed(format!("TLS 握手失败：{error}")))
}

struct IdOutcome {
    greeting: Vec<u8>,
    stream: Stream,
    rejected: Option<String>,
}

/// 163 / 126：读到问候语后先发 `ID`。
///
/// 服务器拒绝 ID 时不立刻断开，而是把原因带上继续登录：部分服务器只是
/// 不认这个扩展，LOGIN 仍然可用；如果登录也因此失败，上层能同时展示两段原因。
fn send_id(mut stream: Stream) -> Result<IdOutcome, ConnectError> {
    let mut greeting = Vec::new();
    loop {
        let line = read_line(&mut stream)?;
        let text = String::from_utf8_lossy(&line).to_ascii_uppercase();
        greeting.extend_from_slice(&line);
        if text.starts_with("* BYE") {
            return Err(ConnectError::Failed("服务器拒绝连接".into()));
        }
        if text.starts_with("* OK") || text.starts_with("* PREAUTH") {
            break;
        }
        if greeting.len() > 8192 {
            return Err(ConnectError::Failed("服务器问候异常".into()));
        }
    }

    let command = format!(
        "a0001 ID (\"name\" \"gudong\" \"version\" \"{}\" \"vendor\" \"gudong\" \"support-email\" \"noreply@gudong.app\")\r\n",
        env!("CARGO_PKG_VERSION")
    );
    stream
        .write_all(command.as_bytes())
        .and_then(|_| stream.flush())
        .map_err(|error| ConnectError::Failed(format!("发送 ID 失败：{error}")))?;

    loop {
        let line = read_line(&mut stream)?;
        let text = String::from_utf8_lossy(&line);
        let upper = text.to_ascii_uppercase();
        if upper.starts_with("* BYE") {
            return Err(ConnectError::Failed("服务器在 ID 阶段关闭了连接".into()));
        }
        let rest = text
            .strip_prefix("a0001 ")
            .or_else(|| text.strip_prefix("A0001 "));
        let Some(rest) = rest else {
            continue;
        };
        if rest.to_ascii_uppercase().starts_with("OK") {
            return Ok(IdOutcome {
                greeting,
                stream,
                rejected: None,
            });
        }
        let reason: String = rest.trim().chars().take(160).collect();
        return Ok(IdOutcome {
            greeting,
            stream,
            rejected: Some(reason),
        });
    }
}

fn read_line(stream: &mut Stream) -> Result<Vec<u8>, ConnectError> {
    let mut line = Vec::new();
    let mut byte = [0u8; 1];
    loop {
        match stream.read(&mut byte) {
            Ok(0) => return Err(ConnectError::Failed("服务器关闭了连接".into())),
            Ok(_) => {
                line.push(byte[0]);
                if line.ends_with(b"\r\n") {
                    return Ok(line);
                }
                if line.len() > 8192 {
                    return Err(ConnectError::Failed("服务器响应过长".into()));
                }
            }
            Err(error) => {
                return Err(ConnectError::Failed(format!("读取服务器响应失败：{error}")))
            }
        }
    }
}

/// 服务器明确拒绝命令时连接仍然同步；其他错误说明响应没读完，必须重连。
pub fn rejected(error: &imap::Error) -> bool {
    matches!(error, imap::Error::No(_) | imap::Error::Bad(_))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn prefixed_stream_replays_greeting_before_inner_data() {
        let mut stream = Prefixed::new(b"* OK ready\r\n".to_vec(), Cursor::new(b"body".to_vec()));
        let mut output = Vec::new();
        stream.read_to_end(&mut output).unwrap();
        assert_eq!(output, b"* OK ready\r\nbody");
    }

    #[test]
    fn server_rejection_is_distinguished_from_broken_connection() {
        assert!(rejected(&imap::Error::No("no".into())));
        assert!(rejected(&imap::Error::Bad("bad".into())));
        assert!(!rejected(&imap::Error::ConnectionLost));
    }
}
