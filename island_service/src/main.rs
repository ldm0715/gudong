//! Guduo island sidecar：stdio JSON-RPC + 微信任务栏监听。
//!
//! 协议：每行一个 JSON。请求带 id，事件不带 id。
//! 日志只写本地文件，stdout 保持纯协议输出。

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod rpc;
#[cfg(windows)]
mod clients;
#[cfg(windows)]
mod foreground;
#[cfg(windows)]
mod notifications;
#[cfg(windows)]
mod wechat;
#[cfg(windows)]
mod wechat_tray;

use serde_json::Value;
use std::io::{BufRead, Write};
use std::sync::{mpsc, Arc};

fn main() {
    let state = Arc::new(rpc::State::default());
    let (tx, rx) = mpsc::channel::<Value>();

    // 事件写线程：监听线程和主线程都不直接写 stdout，避免交错。
    std::thread::Builder::new()
        .name("event-writer".into())
        .spawn(move || {
            for line in rx {
                write_line(&line);
            }
        })
        .expect("failed to start event writer");

    let _ = tx.send(rpc::event(serde_json::json!({
        "type": "service.ready",
        "version": env!("CARGO_PKG_VERSION"),
        "apiVersion": rpc::API_VERSION,
        "capabilities": [
            "wechat.unread",
            "qq.unread",
            "messages.preview",
            "messages.clear",
            "messages.list",
            "messages.open",
        ],
    })));

    #[cfg(windows)]
    {
        foreground::start(state.clone(), tx.clone());
        if let Err(error) = notifications::start(state.clone(), tx.clone()) {
            let _ = tx.send(rpc::emit_status(&state, "notifications", false, &error));
            log(&format!("notification listener failed: {error}"));
        }
        if let Err(error) = wechat::start(state.clone(), tx.clone()) {
            let _ = tx.send(rpc::emit_status(&state, "wechat", false, &error));
            log(&format!("wechat listener failed: {error}"));
        }
    }

    log("service started");
    let stdin = std::io::stdin();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(message) = serde_json::from_str::<Value>(line) else {
            log(&format!("invalid json: {line}"));
            continue;
        };
        let Some(method) = message.get("method").and_then(Value::as_str) else {
            continue;
        };
        let id = message.get("id").cloned().unwrap_or(Value::Null);
        let params = message.get("params").cloned().unwrap_or(Value::Null);
        match rpc::handle(&state, method, &params) {
            Ok(rpc::Action::Respond(result)) => write_line(&rpc::response(&id, result)),
            Ok(rpc::Action::Shutdown(result)) => {
                write_line(&rpc::response(&id, result));
                log("shutdown requested");
                break;
            }
            Err(error) => {
                log(&format!("rpc error: {} {}", error.code, error.message));
                write_line(&rpc::error(&id, error));
            }
        }
    }
    log("stdin closed, service exiting");
}

fn write_line(value: &Value) {
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    let _ = serde_json::to_writer(&mut out, value);
    let _ = out.write_all(b"\n");
    let _ = out.flush();
}

fn log(line: &str) {
    let Some(dir) = log_dir() else { return };
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("island_service.log");
    let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    else {
        return;
    };
    let time = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
    let _ = writeln!(file, "{time} {line}");
}

fn log_dir() -> Option<std::path::PathBuf> {
    let base = std::env::var_os("LOCALAPPDATA")?;
    Some(std::path::PathBuf::from(base).join("guduo").join("logs"))
}
