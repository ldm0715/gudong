//! 只读邮件收件箱。
//!
//! 账号清单与凭据分开存放；IMAP 收取、MIME 解析和同步线程都在 sidecar 内完成。
//! 当前阶段不发送、不回复、不删除，也不修改服务器上的已读状态。

mod net;
mod parse;
mod service;
mod store;

pub use service::{start, Job};
