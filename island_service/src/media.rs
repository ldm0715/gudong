//! SMTC 媒体会话：读取正在播放、推送变化、处理播放控制。
//!
//! 轮询在独立线程内完成，事件只推变化；播放中最多 1Hz 推送进度，
//! 由客户端本地插值。封面只在曲目变化时读取一次，转成 data URI 随事件下发。

use serde::Serialize;
use serde_json::{json, Value};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};

use crate::rpc;

#[derive(Clone, Debug, Default, Serialize)]
pub struct MediaSnapshot {
    pub available: bool,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub source: String,
    /// `music` / `video` / `unknown`
    pub kind: String,
    pub playing: bool,
    pub position: f64,
    pub duration: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artwork: Option<String>,
}

impl MediaSnapshot {
    fn unavailable() -> Self {
        Self {
            kind: "unknown".into(),
            ..Default::default()
        }
    }

    /// 内容键：进度按秒取整，用于判断是否需要推送。封面不参与比较。
    fn content_key(&self) -> String {
        format!(
            "{}|{}|{}|{}|{}|{}|{}|{}|{}",
            self.available,
            self.title,
            self.artist,
            self.album,
            self.source,
            self.kind,
            self.playing,
            self.position.round() as i64,
            self.duration.round() as i64,
        )
    }
}

/// 播放控制命令。`seek` 的参数单位为秒。
pub enum Transport {
    Toggle,
    Next,
    Previous,
    Seek(f64),
}

pub fn start(state: Arc<rpc::State>, tx: mpsc::Sender<Value>) {
    std::thread::Builder::new()
        .name("media-poller".into())
        .spawn(move || poll_loop(state, tx))
        .expect("failed to start media poller");
}

fn poll_loop(state: Arc<rpc::State>, tx: mpsc::Sender<Value>) {
    #[cfg(windows)]
    let _apartment = init_winrt();
    let mut cache = Cache::default();
    let mut last_key = String::new();
    let mut last_artwork_key = String::new();
    let mut last_artwork_sent = false;
    let mut last_track: Option<String> = None;
    let mut last_emit = Instant::now() - Duration::from_secs(10);
    loop {
        let enabled = state.config.bool("mediaEnabled", true);
        let snapshot = if enabled {
            cache.query()
        } else {
            MediaSnapshot::unavailable()
        };
        // 播放器上报的 PlaybackType 并不可靠；只要有标题就尝试匹配，匹配不到会自行放弃。
        let track = if snapshot.available && !snapshot.title.is_empty() {
            Some(format!("{}|{}", snapshot.title, snapshot.artist))
        } else {
            None
        };
        if track != last_track {
            crate::log(&format!(
                "media: {} - {} source={} kind={} duration={:.0}",
                snapshot.title, snapshot.artist, snapshot.source, snapshot.kind, snapshot.duration
            ));
            let lyric_track = track.clone().map(|_| {
                (
                    snapshot.title.clone(),
                    snapshot.artist.clone(),
                    snapshot.duration,
                )
            });
            last_track = track;
            crate::lyrics::update_track(&state, &tx, lyric_track);
        }
        let key = snapshot.content_key();
        let changed = key != last_key;
        let heartbeat = snapshot.available
            && snapshot.playing
            && last_emit.elapsed() >= Duration::from_millis(900);
        if changed || heartbeat {
            last_key = key;
            last_emit = Instant::now();
            if let Ok(mut slot) = state.media.lock() {
                *slot = Some(snapshot.clone());
            }
            // 封面只在曲目变化时随事件下发，避免每秒重复传输几十 KB。
            // 重连后的 `media.get` 仍能拿到完整快照。
            let artwork_key = format!(
                "{}|{}|{}|{}",
                snapshot.source, snapshot.title, snapshot.artist, snapshot.album
            );
            let attach_artwork = snapshot.artwork.is_some()
                && (artwork_key != last_artwork_key || !last_artwork_sent);
            if attach_artwork {
                last_artwork_key = artwork_key;
                last_artwork_sent = true;
            } else if artwork_key != last_artwork_key {
                // 新曲目暂未取到封面，等后续轮询补发。
                last_artwork_key = artwork_key;
                last_artwork_sent = false;
            }
            let mut event_media = snapshot;
            if !attach_artwork {
                event_media.artwork = None;
            }
            let _ = tx.send(rpc::event(json!({
                "type": "media.changed",
                "media": event_media,
            })));
        }
        std::thread::sleep(if enabled {
            Duration::from_millis(1000)
        } else {
            Duration::from_millis(2000)
        });
    }
}

#[cfg(windows)]
#[derive(Default)]
struct Cache {
    manager: Option<windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager>,
    artwork_key: String,
    artwork: Option<String>,
    artwork_attempt: Option<Instant>,
}

#[cfg(windows)]
impl Cache {
    fn query(&mut self) -> MediaSnapshot {
        use windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager as Manager;

        if self.manager.is_none() {
            self.manager = run_async(Manager::RequestAsync(), Duration::from_millis(400));
        }
        let Some(manager) = self.manager.clone() else {
            return MediaSnapshot::unavailable();
        };
        let Ok(sessions) = manager.GetSessions() else {
            self.manager = None;
            return MediaSnapshot::unavailable();
        };
        let current = manager.GetCurrentSession().ok();
        let mut best: Option<(
            MediaSnapshot,
            windows::Media::Control::GlobalSystemMediaTransportControlsSession,
        )> = None;
        for session in sessions {
            let Some(media) = read_session(&session) else {
                continue;
            };
            let rank = media_rank(&media);
            if best
                .as_ref()
                .map_or(true, |(existing, _)| rank < media_rank(existing))
            {
                best = Some((media, session));
            }
        }
        if best.is_none() {
            if let Some(session) = current {
                if let Some(media) = read_session(&session) {
                    best = Some((media, session));
                }
            }
        }
        let Some((mut media, session)) = best else {
            self.artwork_key.clear();
            self.artwork = None;
            self.artwork_attempt = None;
            return MediaSnapshot::unavailable();
        };

        let key = format!(
            "{}|{}|{}|{}",
            media.source, media.title, media.artist, media.album
        );
        if key != self.artwork_key {
            self.artwork_key = key;
            self.artwork = None;
            self.artwork_attempt = None;
        }
        // 播放器可能晚于曲目信息才提供封面，未取到时每 10 秒重试一次。
        let retry = self.artwork.is_none()
            && self
                .artwork_attempt
                .is_none_or(|at| at.elapsed() >= Duration::from_secs(10));
        if retry {
            self.artwork_attempt = Some(Instant::now());
            self.artwork = read_artwork_uri(&session);
        }
        media.artwork = self.artwork.clone();
        media
    }
}

#[cfg(windows)]
fn media_rank(media: &MediaSnapshot) -> u8 {
    match (media.kind == "music", media.playing) {
        (true, true) => 0,
        (true, false) => 1,
        (false, true) => 2,
        _ => 3,
    }
}

#[cfg(windows)]
fn read_session(
    session: &windows::Media::Control::GlobalSystemMediaTransportControlsSession,
) -> Option<MediaSnapshot> {
    use windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status;

    let props = run_async(
        session.TryGetMediaPropertiesAsync(),
        Duration::from_millis(400),
    )?;
    let title = props.Title().unwrap_or_default().to_string();
    if title.trim().is_empty() {
        return None;
    }
    let artist = props.Artist().unwrap_or_default().to_string();
    let album = props.AlbumTitle().unwrap_or_default().to_string();
    let source = session
        .SourceAppUserModelId()
        .unwrap_or_default()
        .to_string();

    let mut kind = "unknown";
    let mut playing = false;
    if let Ok(info) = session.GetPlaybackInfo() {
        if let Ok(status) = info.PlaybackStatus() {
            playing = status == Status::Playing;
        }
        kind = match info
            .PlaybackType()
            .ok()
            .and_then(|value| value.Value().ok())
            .map(|value| value.0)
        {
            Some(1) => "music",
            Some(2) => "video",
            _ => kind,
        };
    }

    let mut position = 0.0;
    let mut duration = 0.0;
    if let Ok(timeline) = session.GetTimelineProperties() {
        if let Ok(current) = timeline.Position() {
            position = current.Duration as f64 / 10_000_000.0;
        }
        if let Ok(end) = timeline.EndTime() {
            duration = end.Duration as f64 / 10_000_000.0;
        }
        // SMTC 只在事件发生时更新位置，播放中按 LastUpdatedTime 外推。
        if playing {
            if let Ok(at) = timeline.LastUpdatedTime() {
                let now =
                    unsafe { windows::Win32::System::SystemInformation::GetSystemTimeAsFileTime() };
                let now = ((now.dwHighDateTime as i64) << 32) | now.dwLowDateTime as i64;
                let lag = (now - at.UniversalTime) as f64 / 10_000_000.0;
                if (0.0..86_400.0).contains(&lag) {
                    position += lag;
                }
            }
        }
    }
    if duration > 0.0 {
        position = position.clamp(0.0, duration);
    }

    Some(MediaSnapshot {
        available: true,
        title,
        artist,
        album,
        source,
        kind: kind.into(),
        playing,
        position,
        duration,
        artwork: None,
    })
}

#[cfg(windows)]
fn read_artwork_uri(
    session: &windows::Media::Control::GlobalSystemMediaTransportControlsSession,
) -> Option<String> {
    use base64::Engine;
    use windows::core::Interface;
    let props = run_async(
        session.TryGetMediaPropertiesAsync(),
        Duration::from_millis(600),
    )?;
    let thumbnail = props.Thumbnail().ok()?;
    let stream = run_async(thumbnail.OpenReadAsync(), Duration::from_millis(600))?;
    let size = stream.Size().ok()?;
    if size == 0 || size > 4 * 1024 * 1024 {
        return None;
    }
    let input = stream.GetInputStreamAt(0).ok()?;
    let reader = windows::Storage::Streams::DataReader::CreateDataReader(&input).ok()?;
    let loaded = run_async::<u32>(
        reader.LoadAsync(size as u32).ok()?.cast(),
        Duration::from_millis(800),
    )?;
    if loaded != size as u32 {
        return None;
    }
    let mut bytes = vec![0u8; loaded as usize];
    reader.ReadBytes(&mut bytes).ok()?;
    let mime = if bytes.starts_with(&[0x89, 0x50, 0x4e, 0x47]) {
        "image/png"
    } else if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        "image/jpeg"
    } else if bytes.starts_with(b"GIF8") {
        "image/gif"
    } else if bytes.starts_with(b"BM") {
        "image/bmp"
    } else {
        "image/png"
    };
    let encoded = base64::engine::general_purpose::STANDARD.encode(&bytes);
    Some(format!("data:{mime};base64,{encoded}"))
}

/// 保持 WinRT 调用所在的 MTA 公寓存活，线程退出时自动释放。
#[cfg(windows)]
struct ComGuard(Option<windows::Win32::System::Com::CO_MTA_USAGE_COOKIE>);

#[cfg(windows)]
impl Drop for ComGuard {
    fn drop(&mut self) {
        if let Some(cookie) = self.0 {
            let _ = unsafe { windows::Win32::System::Com::CoDecrementMTAUsage(cookie) };
        }
    }
}

#[cfg(windows)]
fn init_winrt() -> ComGuard {
    ComGuard(unsafe { windows::Win32::System::Com::CoIncrementMTAUsage().ok() })
}

#[cfg(windows)]
fn run_async<T>(
    operation: windows::core::Result<windows::Foundation::IAsyncOperation<T>>,
    timeout: Duration,
) -> Option<T>
where
    T: windows::core::RuntimeType + 'static,
{
    use windows::Foundation::AsyncStatus;
    let operation = operation.ok()?;
    let start = Instant::now();
    loop {
        match operation.Status() {
            Ok(AsyncStatus::Started) => {
                if start.elapsed() >= timeout {
                    let _ = operation.Cancel();
                    let _ = operation.Close();
                    return None;
                }
                std::thread::sleep(Duration::from_millis(10));
            }
            Ok(_) => break,
            Err(_) => {
                let _ = operation.Close();
                return None;
            }
        }
    }
    let value = operation.GetResults().ok();
    let _ = operation.Close();
    value
}

/// 执行播放控制。`source` 缺省时操作当前会话。
#[cfg(windows)]
pub fn control(command: Transport, source: Option<&str>) -> Result<(), String> {
    use windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager as Manager;

    let _apartment = init_winrt();
    let manager = run_async(Manager::RequestAsync(), Duration::from_millis(600))
        .ok_or_else(|| "系统媒体会话不可用".to_string())?;
    let sessions = manager
        .GetSessions()
        .map_err(|_| "无法读取媒体会话".to_string())?;
    let mut target = None;
    for session in sessions {
        let matches = source.is_none_or(|source| {
            session
                .SourceAppUserModelId()
                .is_ok_and(|id| id.to_string().eq_ignore_ascii_case(source))
        });
        if matches {
            target = Some(session);
            break;
        }
    }
    let session = target
        .or_else(|| manager.GetCurrentSession().ok())
        .ok_or_else(|| "没有可控制的媒体会话".to_string())?;
    let operation = match command {
        Transport::Toggle => session.TryTogglePlayPauseAsync(),
        Transport::Next => session.TrySkipNextAsync(),
        Transport::Previous => session.TrySkipPreviousAsync(),
        Transport::Seek(seconds) => {
            if !seconds.is_finite() || seconds < 0.0 {
                return Err("跳转位置不合法".into());
            }
            session.TryChangePlaybackPositionAsync((seconds * 10_000_000.0) as i64)
        }
    };
    match run_async(operation, Duration::from_millis(800)) {
        Some(true) => Ok(()),
        Some(false) => Err("播放器拒绝了该操作".into()),
        None => Err("播放器响应超时".into()),
    }
}

#[cfg(not(windows))]
pub fn control(_command: Transport, _source: Option<&str>) -> Result<(), String> {
    Err("仅支持 Windows".into())
}

#[cfg(not(windows))]
#[derive(Default)]
struct Cache;

#[cfg(not(windows))]
impl Cache {
    fn query(&mut self) -> MediaSnapshot {
        MediaSnapshot::unavailable()
    }
}

#[cfg(any(not(windows), test))]
#[allow(dead_code)]
fn _keep_transport_used(command: Transport) -> Option<f64> {
    match command {
        Transport::Seek(seconds) => Some(seconds),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[ignore = "需要本机正在播放媒体"]
    fn live_media_state() {
        let mut cache = Cache::default();
        let mut snapshot = cache.query();
        snapshot.artwork = snapshot.artwork.map(|_| "<artwork>".into());
        eprintln!("{snapshot:?}");
        assert!(snapshot.available);
    }

    #[test]
    fn content_key_tracks_playback_and_ignores_artwork() {
        let mut media = MediaSnapshot {
            available: true,
            title: "歌曲".into(),
            artist: "歌手".into(),
            playing: true,
            position: 12.4,
            duration: 180.0,
            artwork: Some("data:image/png;base64,AA==".into()),
            ..Default::default()
        };
        let key = media.content_key();
        media.artwork = None;
        assert_eq!(key, media.content_key());
        media.position = 12.2;
        assert_eq!(key, media.content_key());
        media.position = 13.6;
        assert_ne!(key, media.content_key());
        media.playing = false;
        assert_ne!(key, media.content_key());
    }
}
