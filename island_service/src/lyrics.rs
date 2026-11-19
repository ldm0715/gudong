//! 歌词：按曲目名、歌手与时长在 QQ 音乐匹配，解析 LRC 后回传。
//!
//! 抓取在独立线程执行；切歌后旧请求的结果会被丢弃，避免覆盖新曲目。

use serde::Serialize;
use serde_json::{json, Value};
use std::io::Read;
use std::sync::{mpsc, Arc};
use std::time::Duration;

use crate::rpc;

#[derive(Clone, Serialize)]
pub struct LyricLine {
    /// 起始时间，单位秒。
    pub time: f64,
    pub text: String,
}

#[derive(Clone, Serialize)]
pub struct LyricsSnapshot {
    pub title: String,
    pub artist: String,
    pub source: String,
    pub lines: Vec<LyricLine>,
}

/// 曲目变化时调用。传入 `None` 表示停止播放或切到非音乐内容，清空歌词。
pub fn update_track(
    state: &Arc<rpc::State>,
    tx: &mpsc::Sender<Value>,
    track: Option<(String, String, f64)>,
) {
    let sequence = next_sequence(state);
    if let Ok(mut slot) = state.lyrics.lock() {
        *slot = None;
    }
    if let Ok(mut pending) = state.lyrics_pending.lock() {
        *pending = track.is_some();
    }
    let _ = tx.send(rpc::event(json!({
        "type": "media.lyrics",
        "lyrics": null,
        "pending": track.is_some(),
    })));

    let Some((title, artist, duration)) = track else {
        return;
    };
    let state = state.clone();
    let tx = tx.clone();
    let spawned = std::thread::Builder::new()
        .name("lyrics-fetch".into())
        .spawn(move || {
            let lyrics = fetch(&title, &artist, duration);
            // 切歌后旧请求的结果直接丢弃，也不要把新曲目的 pending 改成 false。
            if next_sequence_for_check(&state) != sequence {
                return;
            }
            if let Ok(mut pending) = state.lyrics_pending.lock() {
                *pending = false;
            }
            if let Some(lyrics) = lyrics {
                if let Ok(mut slot) = state.lyrics.lock() {
                    *slot = Some(lyrics.clone());
                }
                let _ = tx.send(rpc::event(json!({
                    "type": "media.lyrics",
                    "lyrics": lyrics,
                    "pending": false,
                })));
            } else {
                let _ = tx.send(rpc::event(json!({
                    "type": "media.lyrics",
                    "lyrics": null,
                    "pending": false,
                })));
            }
        });
    if let Err(error) = spawned {
        crate::log(&format!("lyrics: 线程启动失败: {error}"));
    }
}

/// 只递增，不重置。用于判断抓取结果是否仍然对应当前曲目。
fn next_sequence(state: &rpc::State) -> u64 {
    match state.lyrics_sequence.lock() {
        Ok(mut value) => {
            *value = value.wrapping_add(1);
            *value
        }
        Err(poisoned) => {
            let mut value = poisoned.into_inner();
            *value = value.wrapping_add(1);
            *value
        }
    }
}

fn next_sequence_for_check(state: &rpc::State) -> u64 {
    state
        .lyrics_sequence
        .lock()
        .map(|value| *value)
        .unwrap_or_default()
}

fn fetch(title: &str, artist: &str, duration: f64) -> Option<LyricsSnapshot> {
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(4))
        .timeout(Duration::from_secs(8))
        .build();
    let query = if artist.trim().is_empty() {
        title.to_string()
    } else {
        format!("{title} {artist}")
    };
    let url = format!(
        "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w={}&format=json&n=10&new_json=1",
        urlencoding::encode(&query)
    );
    let search = get_json(&agent, &url)?;
    let Some(mid) = pick_song(&search, title, artist, duration) else {
        crate::log(&format!("lyrics: 未匹配到 {title} - {artist}"));
        return None;
    };
    let url = format!(
        "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid={mid}&format=json&nobase64=1"
    );
    let payload = get_json(&agent, &url)?;
    let lrc = payload["lyric"].as_str().unwrap_or_default();
    let lines = parse_lrc(lrc);
    if lines.is_empty() {
        crate::log(&format!("lyrics: 无可用歌词 {title} - {artist}"));
        return None;
    }
    crate::log(&format!("lyrics: {title} - {artist} 共 {} 行", lines.len()));
    Some(LyricsSnapshot {
        title: title.into(),
        artist: artist.into(),
        source: "qqmusic".into(),
        lines,
    })
}

fn get_json(agent: &ureq::Agent, url: &str) -> Option<Value> {
    let response = agent
        .get(url)
        .set("Accept", "application/json")
        .set("Referer", "https://y.qq.com/portal/player.html")
        .set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        .call()
        .map_err(|error| {
            let message = match error {
                ureq::Error::Status(code, _) => format!("HTTP {code}"),
                ureq::Error::Transport(error) => format!("{:?}", error.kind()),
            };
            crate::log(&format!("lyrics: {message}"));
            message
        })
        .ok()?;
    serde_json::from_reader(response.into_reader().take(1024 * 1024))
        .map_err(|error| crate::log(&format!("lyrics: 响应无效: {error}")))
        .ok()
}

/// 只接受规范化后歌名完全一致的候选；歌手与时长用于在同名版本中排序。
fn pick_song(search: &Value, title: &str, artist: &str, duration: f64) -> Option<String> {
    let songs = search["data"]["song"]["list"].as_array()?;
    let wanted = normalize(title);
    let wanted_artist = normalize(artist);
    let mut best: Option<(i64, String)> = None;
    for song in songs {
        let name = song["name"]
            .as_str()
            .or_else(|| song["title"].as_str())
            .or_else(|| song["songname"].as_str())?;
        if normalize(name) != wanted {
            continue;
        }
        let Some(mid) = song["mid"].as_str().or_else(|| song["songmid"].as_str()) else {
            continue;
        };
        let mut score = 0;
        let song_artist = song_artist(song);
        if !wanted_artist.is_empty() && normalize(&song_artist).contains(&wanted_artist) {
            score += 3;
        }
        let song_duration = song["interval"].as_f64().unwrap_or(0.0);
        if duration > 5.0 && song_duration > 0.0 {
            let diff = (duration - song_duration).abs();
            if diff <= 3.0 {
                score += 2;
            } else if diff <= 10.0 {
                score += 1;
            }
        }
        if best.as_ref().is_none_or(|(old, _)| score > *old) {
            best = Some((score, mid.to_string()));
        }
    }
    best.map(|(_, mid)| mid)
}

fn song_artist(song: &Value) -> String {
    for key in ["singer", "artists", "ar"] {
        if let Some(items) = song[key].as_array() {
            let names: Vec<&str> = items
                .iter()
                .filter_map(|item| item["name"].as_str())
                .collect();
            if !names.is_empty() {
                return names.join(" / ");
            }
        }
    }
    String::new()
}

fn normalize(text: &str) -> String {
    text.chars()
        .filter(|ch| !ch.is_whitespace())
        .flat_map(char::to_lowercase)
        .collect()
}

fn parse_lrc(text: &str) -> Vec<LyricLine> {
    let mut lines = Vec::new();
    for raw in text.lines() {
        let mut rest = raw.trim_start();
        let mut times = Vec::new();
        while let Some(stripped) = rest.strip_prefix('[') {
            let Some(end) = stripped.find(']') else { break };
            let tag = &stripped[..end];
            let Some(seconds) = parse_timestamp(tag) else {
                break;
            };
            times.push(seconds);
            rest = &stripped[end + 1..];
        }
        let content = rest.trim();
        if times.is_empty() || content.is_empty() || is_credit(content) {
            continue;
        }
        for time in times {
            lines.push(LyricLine {
                time,
                text: content.to_string(),
            });
        }
    }
    lines.sort_by(|left, right| {
        left.time
            .partial_cmp(&right.time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    lines.dedup_by(|a, b| a.time == b.time && a.text == b.text);
    lines
}

fn parse_timestamp(tag: &str) -> Option<f64> {
    let (minutes, seconds) = tag.split_once(':')?;
    let minutes: f64 = minutes.trim().parse().ok()?;
    let seconds: f64 = seconds.trim().parse().ok()?;
    if !(0.0..60.0).contains(&seconds) || minutes < 0.0 {
        return None;
    }
    Some(minutes * 60.0 + seconds)
}

fn is_credit(text: &str) -> bool {
    const CREDITS: &[&str] = &[
        "作词", "作曲", "编曲", "制作", "出品", "监制", "混音", "母带", "吉他", "贝斯", "和声",
        "录音", "统筹", "发行", "词曲", "OP", "SP",
    ];
    if !(text.contains(':') || text.contains('：')) {
        return false;
    }
    CREDITS.iter().any(|credit| text.contains(credit))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_multiple_timestamps_and_sorts() {
        let lines = parse_lrc(
            "[00:12.50]第二句\n[00:03.00]第一句\n[00:03.00][00:30.00]重复句\n[ar:歌手]\n[01:02.5]最后一句",
        );
        assert_eq!(lines.len(), 5);
        assert_eq!(lines[0].text, "第一句");
        assert_eq!(lines[1].text, "重复句");
        assert_eq!(lines[2].text, "第二句");
        assert_eq!(lines[3].text, "重复句");
        assert_eq!(lines[4].text, "最后一句");
        assert!((lines[0].time - 3.0).abs() < 0.001);
    }

    #[test]
    fn drops_credits_and_empty_lines() {
        let lines = parse_lrc(
            "[00:00.00]作词 : 周杰伦\n[00:01.00]作曲：周杰伦\n[00:02.00]正文\n[00:03.00]",
        );
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text, "正文");
    }

    #[test]
    fn picks_exact_title_and_prefers_matching_artist_and_duration() {
        let search = json!({
            "data": { "song": { "list": [
                { "mid": "a", "name": "晴天", "singer": [{ "name": "其他歌手" }], "interval": 269 },
                { "mid": "b", "name": "晴天", "singer": [{ "name": "周杰伦" }], "interval": 120 },
                { "mid": "c", "name": "晴天", "singer": [{ "name": "周杰伦" }], "interval": 269 },
                { "mid": "d", "name": "晴天（翻唱）", "singer": [{ "name": "周杰伦" }], "interval": 269 }
            ]}}
        });
        assert_eq!(
            pick_song(&search, "晴天", "周杰伦", 268.0),
            Some("c".into())
        );
    }

    #[test]
    #[ignore = "需要网络"]
    fn live_fetches_lyrics_for_known_song() {
        for (title, artist, duration) in
            [("晴天", "周杰伦", 269.0), ("不能说的秘密", "周杰伦", 296.0)]
        {
            let lyrics = fetch(title, artist, duration).expect("should find lyrics");
            assert!(lyrics.lines.len() > 5);
            assert_eq!(lyrics.source, "qqmusic");
        }
    }

    #[test]
    fn rejects_mismatched_titles() {
        let search = json!({
            "data": { "song": { "list": [
                { "mid": "a", "name": "雨天", "singer": [{ "name": "周杰伦" }] }
            ]}}
        });
        assert_eq!(pick_song(&search, "晴天", "周杰伦", 269.0), None);
    }
}
