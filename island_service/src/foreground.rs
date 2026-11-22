//! 每秒检查一次前台窗口：切到微信 / QQ 主窗口就清除该来源的提醒；
//! 同时推送前台窗口的最大化状态，供客户端决定是否收起成横杠。

use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::Duration;

use serde_json::{json, Value};

use crate::{clients, rpc};

pub fn start(state: Arc<rpc::State>, tx: Sender<Value>) {
    let _ = std::thread::Builder::new()
        .name("foreground-watcher".into())
        .spawn(move || {
            let mut last: Option<(&'static str, u32)> = None;
            let mut last_maximized: Option<bool> = None;
            loop {
                std::thread::sleep(Duration::from_millis(800));
                let current = clients::foreground_client();
                if current != last {
                    last = current;
                    if let Some((source, _)) = current {
                        let (event, removed) =
                            rpc::emit_cleared(&state, None, Some(source), None);
                        if removed > 0 {
                            let _ = tx.send(event);
                        }
                    }
                }
                if let Some(maximized) = clients::foreground_maximized() {
                    if last_maximized != Some(maximized) {
                        last_maximized = Some(maximized);
                        let _ = tx.send(rpc::event(json!({
                            "type": "foreground.maximized",
                            "maximized": maximized,
                        })));
                    }
                }
            }
        });
}
