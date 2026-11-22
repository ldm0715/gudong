//! Guduo island sidecar：stdio JSON-RPC + 微信任务栏监听。
//!
//! 协议：每行一个 JSON。请求带 id，事件不带 id。
//! 日志只写本地文件，stdout 保持纯协议输出。

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod anniversary;
mod config;
mod credentials;
mod lyrics;
mod mail;
mod media;
mod quota;
mod rpc;
mod schedule;
mod shelf;
mod shelf_icons;
mod shell;
mod single_instance;
mod toast;
mod translate;
mod weather;
#[cfg(windows)]
mod clients;
#[cfg(windows)]
mod foreground;
#[cfg(windows)]
mod ime;
#[cfg(windows)]
mod notifications;
#[cfg(windows)]
mod volume;
#[cfg(windows)]
mod wechat;
#[cfg(windows)]
mod wechat_tray;

use serde_json::Value;
use std::io::{BufRead, Write};
use std::sync::{mpsc, Arc};

fn main() {
    std::panic::set_hook(Box::new(|info| {
        let backtrace = std::backtrace::Backtrace::force_capture();
        log(&format!("panic: {info}\nbacktrace: {backtrace}"));
    }));

    if !single_instance::try_acquire() {
        log("another island_service instance is running, exiting");
        return;
    }
    log(&format!(
        "service {} starting (pid {})",
        env!("CARGO_PKG_VERSION"),
        std::process::id()
    ));

    let state = Arc::new(rpc::State::with_config(config::Config::load()));
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
        "capabilities": rpc::CAPABILITIES,
    })));

    let weather_tx = weather::start(state.clone(), tx.clone());
    state.set_weather_sender(weather_tx);
    media::start(state.clone(), tx.clone());
    let quota_tx = quota::start(state.clone(), tx.clone());
    state.set_quota_sender(quota_tx);
    let translate_tx = translate::start(state.clone(), tx.clone());
    state.set_translate_sender(translate_tx);
    let mail_tx = mail::start(state.clone(), tx.clone());
    state.set_mail_sender(mail_tx);
    let toast_tx = toast::start();
    let schedule_tx = schedule::start(tx.clone(), toast_tx);
    state.set_schedule_sender(schedule_tx);
    let anniversary_tx = anniversary::start(tx.clone());
    state.set_anniversary_sender(anniversary_tx);
    let icon_tx = shelf_icons::start(tx.clone());
    let shelf_tx = shelf::start(state.clone(), tx.clone(), icon_tx);
    state.set_shelf_sender(shelf_tx);

    #[cfg(windows)]
    {
        foreground::start(state.clone(), tx.clone());
        ime::start(state.clone(), tx.clone());
        let volume_tx = volume::start(state.clone(), tx.clone());
        state.set_volume_sender(volume_tx);
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
            write_line(&rpc::error(
                &Value::Null,
                rpc::RpcError::new(rpc::ERR_PARSE, "parse error"),
            ));
            continue;
        };
        let id = message.get("id").cloned().unwrap_or(Value::Null);
        let Some(method) = message.get("method").and_then(Value::as_str) else {
            log(&format!("invalid request: {line}"));
            write_line(&rpc::error(
                &id,
                rpc::RpcError::new(rpc::ERR_INVALID_REQUEST, "method is required"),
            ));
            continue;
        };
        let params = message.get("params").cloned().unwrap_or(Value::Null);
        match rpc::handle(&state, &id, method, &params) {
            Ok(rpc::Action::Respond(result)) => write_line(&rpc::response(&id, result)),
            Ok(rpc::Action::Shutdown(result)) => {
                write_line(&rpc::response(&id, result));
                log("shutdown requested");
                break;
            }
            Ok(rpc::Action::Pending) => {}
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

pub fn log(line: &str) {
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
