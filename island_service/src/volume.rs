//! 系统输出音量：轮询默认播放设备，变化时推送事件，并接受拖动设置。
//!
//! 轮询周期 120ms，足够跟上系统音量键和音量面板；只有数值变化时才写事件。
//! 第一次读取只建立缓存，不推送，避免启动时凭空弹一次音量横幅。

use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::sync::Arc;
use std::time::Duration;

use serde::Serialize;
use serde_json::{json, Value};
use windows::Win32::Foundation::BOOL;
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::{
    eConsole, eRender, IMMDeviceEnumerator, MMDeviceEnumerator, PlaySoundW, SND_ASYNC,
    SND_MEMORY, SND_NODEFAULT,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED,
};

use crate::rpc::{self, State};

const POLL_INTERVAL: Duration = Duration::from_millis(120);
const RETRY_INTERVAL: Duration = Duration::from_secs(1);

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct VolumeSnapshot {
    /// 0.0 - 1.0。
    pub volume: f32,
    pub muted: bool,
}

pub enum Command {
    /// 设置主音量；按系统面板习惯同时解除静音。
    SetVolume(f32),
    SetMuted(bool),
    /// 按当前音量播放一次提示音，用于拖动结束后的响度反馈。
    Preview,
}

/// 启动音量线程，返回设置命令队列。
pub fn start(state: Arc<State>, tx: Sender<Value>) -> Sender<Command> {
    let (command_tx, command_rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("volume".into())
        .spawn(move || run(state, tx, command_rx));
    if let Err(error) = spawned {
        crate::log(&format!("volume: 线程启动失败: {error}"));
    }
    command_tx
}

fn run(state: Arc<State>, tx: Sender<Value>, commands: Receiver<Command>) {
    let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED).ok() };
    let beep = beep_wav();
    let mut endpoint: Option<IAudioEndpointVolume> = None;
    let mut last: Option<VolumeSnapshot> = None;

    loop {
        let command = match commands.recv_timeout(POLL_INTERVAL) {
            Ok(command) => Some(command),
            Err(RecvTimeoutError::Timeout) => None,
            Err(RecvTimeoutError::Disconnected) => return,
        };
        if endpoint.is_none() {
            endpoint = open_endpoint();
        }
        let Some(volume) = endpoint.as_ref() else {
            std::thread::sleep(RETRY_INTERVAL);
            continue;
        };
        if let Some(command) = command {
            match command {
                Command::Preview => play_feedback(&beep),
                command => {
                    apply(volume, command);
                }
            }
        }
        match read(volume) {
            Some(snapshot) => {
                if last != Some(snapshot) {
                    if let Ok(mut slot) = state.volume.lock() {
                        *slot = Some(snapshot);
                    }
                    // 首次读取只建缓存，不推送。
                    if last.is_some() {
                        let _ = tx.send(rpc::event(json!({
                            "type": "volume.changed",
                            "volume": snapshot.volume,
                            "muted": snapshot.muted,
                        })));
                    }
                    last = Some(snapshot);
                }
            }
            None => endpoint = None,
        }
    }
}

fn open_endpoint() -> Option<IAudioEndpointVolume> {
    unsafe {
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).ok()?;
        let device = enumerator.GetDefaultAudioEndpoint(eRender, eConsole).ok()?;
        device.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None).ok()
    }
}

fn read(volume: &IAudioEndpointVolume) -> Option<VolumeSnapshot> {
    unsafe {
        let level = volume.GetMasterVolumeLevelScalar().ok()?;
        let muted = volume.GetMute().ok()?.as_bool();
        Some(VolumeSnapshot {
            volume: level.clamp(0.0, 1.0),
            muted,
        })
    }
}

fn apply(volume: &IAudioEndpointVolume, command: Command) {
    unsafe {
        match command {
            Command::SetVolume(level) => {
                let _ = volume
                    .SetMasterVolumeLevelScalar(level.clamp(0.0, 1.0), std::ptr::null());
                let _ = volume.SetMute(BOOL::from(false), std::ptr::null());
            }
            Command::SetMuted(muted) => {
                let _ = volume.SetMute(BOOL::from(muted), std::ptr::null());
            }
            Command::Preview => {}
        }
    }
}

/// 播放一段短提示音，响度跟随系统主音量，用来感知调节结果。
fn play_feedback(wav: &[u8]) {
    unsafe {
        let sound = windows::core::PCWSTR(wav.as_ptr().cast());
        let _ = PlaySoundW(sound, None, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
    }
}

/// 生成 880Hz、90ms 的 PCM 单声道 WAV，两端淡入淡出避免爆音。
fn beep_wav() -> Vec<u8> {
    const SAMPLE_RATE: u32 = 44_100;
    const DURATION_MS: u32 = 90;
    let samples = SAMPLE_RATE * DURATION_MS / 1000;
    let data_len = samples * 2;
    let mut data = Vec::with_capacity(44 + data_len as usize);
    data.extend_from_slice(b"RIFF");
    data.extend_from_slice(&(36 + data_len).to_le_bytes());
    data.extend_from_slice(b"WAVEfmt ");
    data.extend_from_slice(&16u32.to_le_bytes());
    data.extend_from_slice(&1u16.to_le_bytes());
    data.extend_from_slice(&1u16.to_le_bytes());
    data.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
    data.extend_from_slice(&(SAMPLE_RATE * 2).to_le_bytes());
    data.extend_from_slice(&2u16.to_le_bytes());
    data.extend_from_slice(&16u16.to_le_bytes());
    data.extend_from_slice(b"data");
    data.extend_from_slice(&data_len.to_le_bytes());
    for index in 0..samples {
        let seconds = index as f32 / SAMPLE_RATE as f32;
        let progress = index as f32 / samples as f32;
        let fade = (progress * 8.0).min(1.0).min((1.0 - progress) * 8.0);
        let value = (seconds * 880.0 * std::f32::consts::TAU).sin() * fade * 0.25;
        data.extend_from_slice(&((value * i16::MAX as f32) as i16).to_le_bytes());
    }
    data
}
