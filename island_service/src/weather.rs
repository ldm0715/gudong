//! 天气：按网络出口定位，再拉取实况。
//!
//! 定位优先 ipwho.is，失败退 freeipapi；天气优先 wttr.in，失败退 Open-Meteo。
//! 三个接口都不需要密钥。日志只记录服务名与错误，不记录 IP 或坐标。

use serde::Serialize;
use serde_json::{json, Value};
use std::io::Read;
use std::sync::mpsc::{Receiver, Sender};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::rpc::{self, RpcError, State};

const REFRESH_INTERVAL: Duration = Duration::from_secs(15 * 60);
const RETRY_INTERVAL: Duration = Duration::from_secs(2 * 60);
const LOCATE_TTL: Duration = Duration::from_secs(3 * 60 * 60);
const FORECAST_DAYS: usize = 5;
/// 逐时预报只取未来 24 小时。
const HOURLY_HOURS: usize = 24;
const HOURLY_FIELDS: &str =
    "temperature_2m,weather_code,is_day,precipitation_probability,apparent_temperature";

#[derive(Clone, Serialize)]
pub struct WeatherSnapshot {
    pub place: String,
    pub temp_c: f64,
    pub kind: String,
    pub description: String,
    pub is_day: bool,
    pub updated_at_ms: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub feels_like_c: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub humidity: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wind_kph: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub high_c: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub low_c: Option<f64>,
    /// 从当前小时开始的 24 小时逐时预报，缺省时为空数组。
    pub hours: Vec<WeatherHour>,
    pub days: Vec<WeatherDay>,
}

#[derive(Clone, Serialize)]
pub struct WeatherHour {
    /// 地点本地时间，`HH:mm`。
    pub time: String,
    pub temp_c: f64,
    pub kind: String,
    pub description: String,
    pub is_day: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub precip_probability: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub feels_like_c: Option<f64>,
}

#[derive(Clone, Serialize)]
pub struct WeatherDay {
    pub date: String,
    pub kind: String,
    pub description: String,
    pub high_c: f64,
    pub low_c: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub precip_probability: Option<u32>,
}

#[derive(Clone)]
struct Location {
    lat: f64,
    lon: f64,
    place: String,
}

/// 地点搜索结果，由 Open-Meteo 地理编码接口返回。
#[derive(Clone, Serialize)]
pub struct PlaceOption {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub admin: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
    pub latitude: f64,
    pub longitude: f64,
    /// 用于直接展示的完整名称，如「广州 · 广东省 · 中国」。
    pub label: String,
}

pub enum Command {
    /// 设置变更或手动触发，立即刷新一次。
    Refresh,
    /// 地点搜索，结果通过事件写线程返回。
    Search { id: Value, query: String },
}

/// 启动天气线程：先拉一次，之后每 15 分钟刷新，失败 2 分钟后重试。
/// 返回的命令队列用于唤醒刷新与地点搜索。
pub fn start(state: Arc<State>, tx: Sender<Value>) -> Sender<Command> {
    let (command_tx, command_rx) = std::sync::mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("weather".into())
        .spawn(move || run(state, tx, command_rx));
    if let Err(error) = spawned {
        crate::log(&format!("weather: 线程启动失败: {error}"));
    }
    command_tx
}

fn run(state: Arc<State>, tx: Sender<Value>, commands: Receiver<Command>) {
    let agent = agent();
    let mut auto_location: Option<Location> = None;
    let mut located_at: Option<Instant> = None;
    let mut prefer_wttr = true;
    let mut was_manual = false;
    let mut next_refresh = Instant::now();

    loop {
        // 先清空排队的命令，避免刷新阻塞搜索响应。
        loop {
            match commands.try_recv() {
                Ok(Command::Refresh) => next_refresh = Instant::now(),
                Ok(Command::Search { id, query }) => respond_search(&agent, &tx, &id, &query),
                Err(std::sync::mpsc::TryRecvError::Empty) => break,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => return,
            }
        }

        let now = Instant::now();
        if now >= next_refresh {
            next_refresh = now
                + refresh(
                    &state,
                    &tx,
                    &agent,
                    &mut auto_location,
                    &mut located_at,
                    &mut prefer_wttr,
                    &mut was_manual,
                );
            continue;
        }

        match commands.recv_timeout(next_refresh.saturating_duration_since(now)) {
            Ok(Command::Refresh) => next_refresh = Instant::now(),
            Ok(Command::Search { id, query }) => respond_search(&agent, &tx, &id, &query),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return,
        }
    }
}

fn refresh(
    state: &State,
    tx: &Sender<Value>,
    agent: &ureq::Agent,
    auto_location: &mut Option<Location>,
    located_at: &mut Option<Instant>,
    prefer_wttr: &mut bool,
    was_manual: &mut bool,
) -> Duration {
    let manual = configured_location(&state.config);
    let is_manual = manual.is_some();
    // 从手动切回自动时丢弃旧的 IP 定位，立即重新定位。
    if *was_manual && !is_manual {
        *located_at = None;
    }
    *was_manual = is_manual;

    if !is_manual {
        let stale = located_at
            .map(|at| at.elapsed() >= LOCATE_TTL)
            .unwrap_or(true);
        if stale {
            if let Some(found) = locate(agent) {
                *auto_location = Some(found);
                *located_at = Some(Instant::now());
            }
        }
    }

    let location = manual.or_else(|| auto_location.clone());
    let previous = state.weather.lock().ok().and_then(|slot| slot.clone());
    let snapshot = fetch(agent, location.as_ref(), prefer_wttr);
    let status = match &snapshot {
        Some(value) if value.place.is_empty() => {
            format!("{} {}°C", value.description, value.temp_c.round() as i64)
        }
        Some(value) => format!(
            "{} {} {}°C",
            value.place,
            value.description,
            value.temp_c.round() as i64
        ),
        None if previous.is_some() => "刷新失败，沿用上次数据".into(),
        None => "天气暂时取不到".into(),
    };

    let current = match snapshot {
        Some(value) => {
            if let Ok(mut slot) = state.weather.lock() {
                *slot = Some(value.clone());
            }
            Some(value)
        }
        None => previous,
    };
    if let Ok(mut slot) = state.weather_status.lock() {
        *slot = status.clone();
    }
    let _ = tx.send(rpc::event(json!({
        "type": "weather.updated",
        "snapshot": current,
        "status": status,
    })));

    if current.is_some() {
        REFRESH_INTERVAL
    } else {
        RETRY_INTERVAL
    }
}

/// 用户在设置里指定了地点时优先使用，否则按出口 IP 自动定位。
fn configured_location(config: &crate::config::Config) -> Option<Location> {
    let values = config.snapshot();
    if values.get("weatherLocationMode").and_then(Value::as_str) != Some("manual") {
        return None;
    }
    let lat = values.get("weatherLatitude").and_then(Value::as_f64)?;
    let lon = values.get("weatherLongitude").and_then(Value::as_f64)?;
    if !valid_coordinates(lat, lon) {
        return None;
    }
    let place = values
        .get("weatherLocationName")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    Some(Location { lat, lon, place })
}

fn respond_search(agent: &ureq::Agent, tx: &Sender<Value>, id: &Value, query: &str) {
    let message = match search(agent, query) {
        Ok(places) => rpc::response(id, json!({ "places": places })),
        Err(message) => {
            crate::log(&format!("weather: 地点搜索失败: {message}"));
            rpc::error(id, RpcError::new(rpc::ERR_INTERNAL, message))
        }
    };
    let _ = tx.send(message);
}

fn search(agent: &ureq::Agent, query: &str) -> Result<Vec<PlaceOption>, String> {
    let url = format!(
        "https://geocoding-api.open-meteo.com/v1/search?name={}&count=8&language=zh&format=json",
        urlencoding::encode(query.trim())
    );
    let value = get_json(agent, &url, "Open-Meteo 地理编码")?;
    Ok(parse_places(&value))
}

fn parse_places(value: &Value) -> Vec<PlaceOption> {
    let Some(results) = value.get("results").and_then(Value::as_array) else {
        return Vec::new();
    };
    results.iter().filter_map(parse_place).collect()
}

fn parse_place(value: &Value) -> Option<PlaceOption> {
    let name = value.get("name").and_then(Value::as_str)?.trim();
    if name.is_empty() {
        return None;
    }
    let lat = value.get("latitude").and_then(Value::as_f64)?;
    let lon = value.get("longitude").and_then(Value::as_f64)?;
    if !valid_coordinates(lat, lon) {
        return None;
    }
    let admin = text_field(value, "admin1").or_else(|| text_field(value, "admin2"));
    let country = text_field(value, "country");
    let mut parts = vec![name.to_string()];
    for extra in [admin.as_deref(), country.as_deref()] {
        if let Some(extra) = extra {
            if !parts.iter().any(|part| part == extra) {
                parts.push(extra.to_string());
            }
        }
    }
    Some(PlaceOption {
        name: name.to_string(),
        admin,
        country,
        latitude: lat,
        longitude: lon,
        label: parts.join(" · "),
    })
}

fn text_field(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_string)
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(4))
        .timeout(Duration::from_secs(8))
        .build()
}

fn fetch(
    agent: &ureq::Agent,
    location: Option<&Location>,
    prefer_wttr: &mut bool,
) -> Option<WeatherSnapshot> {
    if *prefer_wttr {
        if let Some(snapshot) = fetch_wttr(agent, location) {
            return Some(snapshot);
        }
        if let Some(location) = location {
            *prefer_wttr = false;
            if let Some(snapshot) = fetch_open_meteo(agent, location) {
                return Some(snapshot);
            }
        }
        return None;
    }

    if let Some(location) = location {
        if let Some(snapshot) = fetch_open_meteo(agent, location) {
            return Some(snapshot);
        }
    }
    *prefer_wttr = true;
    fetch_wttr(agent, location)
}

fn locate(agent: &ureq::Agent) -> Option<Location> {
    match get_json(agent, "https://ipwho.is/?lang=zh-CN", "ipwho.is") {
        Ok(value) => {
            if let Some(location) = parse_ipwho(&value) {
                return Some(location);
            }
            crate::log("weather: ipwho.is 未返回可用位置");
        }
        Err(error) => crate::log(&format!("weather: {error}")),
    }
    match get_json(agent, "https://free.freeipapi.com/api/v1/json", "freeipapi") {
        Ok(value) => {
            if let Some(location) = parse_freeipapi(&value) {
                return Some(location);
            }
            crate::log("weather: freeipapi 未返回可用位置");
        }
        Err(error) => crate::log(&format!("weather: {error}")),
    }
    None
}

fn fetch_wttr(agent: &ureq::Agent, location: Option<&Location>) -> Option<WeatherSnapshot> {
    let path = location
        .map(|location| format!("{:.4},{:.4}", location.lat, location.lon))
        .unwrap_or_default();
    let url = format!("https://wttr.in/{path}?format=j1&lang=zh-cn");
    match get_json(agent, &url, "wttr.in") {
        Ok(value) => {
            let Some(mut snapshot) =
                parse_wttr(&value, location.map(|location| location.place.as_str()))
            else {
                crate::log("weather: wttr.in 响应缺少实况字段");
                return None;
            };
            // wttr.in 只给 3 天预报，不足 5 天时用 7Timer 补齐。
            if snapshot.days.len() < FORECAST_DAYS {
                if let Some(location) = location {
                    let extra = seven_timer_days(agent, location);
                    merge_days(&mut snapshot.days, extra);
                }
            }
            snapshot.high_c = snapshot.days.first().map(|day| day.high_c);
            snapshot.low_c = snapshot.days.first().map(|day| day.low_c);
            Some(snapshot)
        }
        Err(error) => {
            crate::log(&format!("weather: {error}"));
            None
        }
    }
}

fn seven_timer_days(agent: &ureq::Agent, location: &Location) -> Vec<WeatherDay> {
    let url = format!(
        "https://www.7timer.info/bin/api.pl?lon={:.4}&lat={:.4}&product=civil&output=json",
        location.lon, location.lat
    );
    match get_json(agent, &url, "7Timer") {
        Ok(value) => parse_seven_timer(&value),
        Err(error) => {
            crate::log(&format!("weather: {error}"));
            Vec::new()
        }
    }
}

fn merge_days(days: &mut Vec<WeatherDay>, extra: Vec<WeatherDay>) {
    for day in extra {
        if days.len() >= FORECAST_DAYS {
            break;
        }
        if !days.iter().any(|existing| existing.date == day.date) {
            days.push(day);
        }
    }
    days.sort_by(|left, right| left.date.cmp(&right.date));
    days.truncate(FORECAST_DAYS);
}

fn parse_seven_timer(value: &Value) -> Vec<WeatherDay> {
    parse_seven_timer_at(value, chrono::Local::now().date_naive())
}

fn parse_seven_timer_init(text: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    use chrono::TimeZone;
    if text.len() != 10 {
        return None;
    }
    let year: i32 = text[0..4].parse().ok()?;
    let month: u32 = text[4..6].parse().ok()?;
    let day: u32 = text[6..8].parse().ok()?;
    let hour: u32 = text[8..10].parse().ok()?;
    let naive = chrono::NaiveDate::from_ymd_opt(year, month, day)?.and_hms_opt(hour, 0, 0)?;
    Some(chrono::Utc.from_utc_datetime(&naive))
}

fn parse_seven_timer_at(value: &Value, today: chrono::NaiveDate) -> Vec<WeatherDay> {
    use chrono::Timelike;

    let Some(init) = value["init"].as_str().and_then(parse_seven_timer_init) else {
        return Vec::new();
    };
    let Some(series) = value["dataseries"].as_array() else {
        return Vec::new();
    };

    struct Bucket {
        date: String,
        high: i64,
        low: i64,
        noon_distance: i64,
        kind: &'static str,
        description: String,
    }

    let mut buckets: Vec<Bucket> = Vec::new();
    for entry in series {
        let Some(timepoint) = entry["timepoint"].as_u64() else {
            continue;
        };
        let Some(temp) = entry["temp2m"].as_i64() else {
            continue;
        };
        let Some(at) = init.checked_add_signed(chrono::Duration::hours(timepoint as i64)) else {
            continue;
        };
        let local = at.with_timezone(&chrono::Local);
        let date = local.format("%Y-%m-%d").to_string();
        let weather = entry["weather"].as_str().unwrap_or("");
        let (kind, description) = describe_seven_timer(weather);
        let noon_distance = ((local.hour() as i64 - 12).abs() * 60) + local.minute() as i64;

        if let Some(bucket) = buckets.iter_mut().find(|bucket| bucket.date == date) {
            bucket.high = bucket.high.max(temp);
            bucket.low = bucket.low.min(temp);
            if noon_distance < bucket.noon_distance {
                bucket.noon_distance = noon_distance;
                bucket.kind = kind;
                bucket.description = description.to_string();
            }
        } else {
            buckets.push(Bucket {
                date,
                high: temp,
                low: temp,
                noon_distance,
                kind,
                description: description.to_string(),
            });
        }
    }

    buckets
        .into_iter()
        .filter(|bucket| {
            chrono::NaiveDate::parse_from_str(&bucket.date, "%Y-%m-%d")
                .map(|date| {
                    date >= today && date < today + chrono::Duration::days(FORECAST_DAYS as i64)
                })
                .unwrap_or(false)
        })
        .map(|bucket| WeatherDay {
            date: bucket.date,
            kind: bucket.kind.to_string(),
            description: bucket.description,
            high_c: bucket.high as f64,
            low_c: bucket.low as f64,
            precip_probability: None,
        })
        .collect()
}

fn describe_seven_timer(weather: &str) -> (&'static str, &'static str) {
    let code = weather
        .strip_suffix("day")
        .or_else(|| weather.strip_suffix("night"))
        .unwrap_or(weather);
    match code {
        "clear" => ("clear", "晴"),
        "pcloudy" | "mcloudy" => ("partly", "多云"),
        "cloudy" => ("cloudy", "阴"),
        "humid" | "fog" => ("fog", "雾"),
        "lightrain" => ("rain", "小雨"),
        "oshower" | "ishower" => ("rain", "阵雨"),
        "lightsnow" => ("snow", "小雪"),
        "rainsnow" => ("snow", "雨夹雪"),
        "ts" | "tsrain" => ("thunder", "雷阵雨"),
        _ => ("cloudy", "多云"),
    }
}

fn fetch_open_meteo(agent: &ureq::Agent, location: &Location) -> Option<WeatherSnapshot> {
    let url = format!(
        "https://api.open-meteo.com/v1/forecast?latitude={:.4}&longitude={:.4}\
         &current=temperature_2m,is_day,weather_code,apparent_temperature,\
         relative_humidity_2m,wind_speed_10m\
         &hourly={}\
         &daily=weather_code,temperature_2m_max,temperature_2m_min,\
         precipitation_probability_max&timezone=auto&forecast_days=5",
        location.lat, location.lon, HOURLY_FIELDS
    );
    match get_json(agent, &url, "Open-Meteo") {
        Ok(value) => {
            let snapshot = parse_open_meteo(&value, &location.place);
            if snapshot.is_none() {
                crate::log("weather: Open-Meteo 响应缺少实况字段");
            }
            snapshot
        }
        Err(error) => {
            crate::log(&format!("weather: {error}"));
            None
        }
    }
}

fn get_json(agent: &ureq::Agent, url: &str, service: &str) -> Result<Value, String> {
    let response = agent
        .get(url)
        .set("Accept", "application/json")
        .set("User-Agent", concat!("Guduo/", env!("CARGO_PKG_VERSION")))
        .call()
        .map_err(|error| match error {
            ureq::Error::Status(code, _) => format!("{service} HTTP {code}"),
            ureq::Error::Transport(error) => format!("{service} {:?}", error.kind()),
        })?;
    serde_json::from_reader(response.into_reader().take(1024 * 1024))
        .map_err(|error| format!("{service} 响应无效: {error}"))
}

fn parse_ipwho(value: &Value) -> Option<Location> {
    if value["success"].as_bool() != Some(true) {
        return None;
    }
    let lat = value["latitude"].as_f64()?;
    let lon = value["longitude"].as_f64()?;
    if !valid_coordinates(lat, lon) {
        return None;
    }
    let city = value["city"].as_str().unwrap_or("").trim();
    let region = value["region"].as_str().unwrap_or("").trim();
    Some(Location {
        lat,
        lon,
        place: if city.is_empty() {
            region.to_string()
        } else {
            city.to_string()
        },
    })
}

fn parse_freeipapi(value: &Value) -> Option<Location> {
    let lat = value["latitude"].as_f64()?;
    let lon = value["longitude"].as_f64()?;
    if !valid_coordinates(lat, lon) {
        return None;
    }
    let city = value["cityName"].as_str().unwrap_or("").trim();
    let region = value["regionName"].as_str().unwrap_or("").trim();
    Some(Location {
        lat,
        lon,
        place: if city.is_empty() {
            region.to_string()
        } else {
            city.to_string()
        },
    })
}

fn valid_coordinates(lat: f64, lon: f64) -> bool {
    (-90.0..=90.0).contains(&lat) && (-180.0..=180.0).contains(&lon)
}

fn parse_wttr(value: &Value, place: Option<&str>) -> Option<WeatherSnapshot> {
    let current = &value["current_condition"][0];
    let temp = number(&current["temp_C"])?;
    let code = integer(&current["weatherCode"])? as u16;
    let kind = kind_from_wwo(code);
    let description = wttr_description(current["lang_zh-cn"][0]["value"].as_str(), code, kind);
    let place = place
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| wttr_place(value));
    let days = wttr_days(value);
    Some(WeatherSnapshot {
        place,
        temp_c: temp,
        kind: kind.to_string(),
        description: description.to_string(),
        is_day: wttr_is_day(value),
        updated_at_ms: chrono::Local::now().timestamp_millis(),
        feels_like_c: number(&current["FeelsLikeC"]),
        humidity: integer(&current["humidity"]).map(|value| value.min(100)),
        wind_kph: number(&current["windspeedKmph"]),
        high_c: days.first().map(|day| day.high_c),
        low_c: days.first().map(|day| day.low_c),
        hours: wttr_hours(value),
        days,
    })
}

fn parse_open_meteo(value: &Value, place: &str) -> Option<WeatherSnapshot> {
    let current = &value["current"];
    let temp = current["temperature_2m"].as_f64()?;
    let code = current["weather_code"].as_u64()? as u16;
    let kind = kind_from_wmo(code);
    let days = open_meteo_days(&value["daily"]);
    Some(WeatherSnapshot {
        place: place.trim().to_string(),
        temp_c: temp,
        kind: kind.to_string(),
        description: describe_wmo(code).to_string(),
        is_day: current["is_day"].as_u64().unwrap_or(1) != 0,
        updated_at_ms: chrono::Local::now().timestamp_millis(),
        feels_like_c: current["apparent_temperature"].as_f64(),
        humidity: integer(&current["relative_humidity_2m"]).map(|value| value.min(100)),
        wind_kph: current["wind_speed_10m"].as_f64(),
        high_c: days.first().map(|day| day.high_c),
        low_c: days.first().map(|day| day.low_c),
        hours: open_meteo_hours(value),
        days,
    })
}

/// wttr.in 的逐时数据是 3 小时粒度，从当前时段开始取 8 个点覆盖一天。
fn wttr_hours(value: &Value) -> Vec<WeatherHour> {
    use chrono::Timelike;

    let Some(days) = value["weather"].as_array() else {
        return Vec::new();
    };
    let mut slots: Vec<(usize, u32, &Value)> = Vec::new();
    for (day_index, day) in days.iter().take(2).enumerate() {
        let Some(entries) = day["hourly"].as_array() else {
            continue;
        };
        for entry in entries {
            let Some(hour) = entry["time"].as_str().and_then(parse_wttr_hour) else {
                continue;
            };
            slots.push((day_index, hour, entry));
        }
    }
    if slots.is_empty() {
        return Vec::new();
    }

    let now_hour = chrono::Local::now().hour();
    let first_day_len = slots.iter().take_while(|slot| slot.0 == 0).count();
    let start = slots
        .iter()
        .take(first_day_len)
        .position(|slot| slot.1 >= now_hour)
        .unwrap_or(first_day_len);

    slots
        .into_iter()
        .skip(start)
        .take(8)
        .filter_map(|(_, hour, entry)| {
            let temp = number(&entry["tempC"])?;
            let code = integer(&entry["weatherCode"])? as u16;
            let kind = kind_from_wwo(code);
            Some(WeatherHour {
                time: format!("{hour:02}:00"),
                temp_c: temp,
                kind: kind.to_string(),
                description: wttr_description(
                    entry["lang_zh-cn"][0]["value"].as_str(),
                    code,
                    kind,
                ),
                is_day: (6..18).contains(&hour),
                precip_probability: ["chanceofrain", "chanceofsnow"]
                    .iter()
                    .filter_map(|key| {
                        integer(entry.get(*key)?).map(|value| value.min(100) as u32)
                    })
                    .max(),
                feels_like_c: number(&entry["FeelsLikeC"]),
            })
        })
        .collect()
}

fn parse_wttr_hour(text: &str) -> Option<u32> {
    text.trim().parse::<u32>().ok().map(|value| value / 100)
}

fn open_meteo_hours(value: &Value) -> Vec<WeatherHour> {
    let hourly = &value["hourly"];
    let Some(times) = hourly["time"].as_array() else {
        return Vec::new();
    };
    let start = hourly_start_index(times, value);
    let mut hours = Vec::with_capacity(HOURLY_HOURS);
    for (index, time) in times.iter().enumerate().skip(start) {
        if hours.len() >= HOURLY_HOURS {
            break;
        }
        let Some(time) = time.as_str() else { continue };
        let Some(temp) = hourly["temperature_2m"].get(index).and_then(Value::as_f64) else {
            continue;
        };
        let Some(code) = hourly["weather_code"].get(index).and_then(Value::as_u64) else {
            continue;
        };
        let code = code as u16;
        let kind = kind_from_wmo(code);
        hours.push(WeatherHour {
            time: hour_label(time),
            temp_c: temp,
            kind: kind.to_string(),
            description: describe_wmo(code).to_string(),
            is_day: hourly["is_day"]
                .get(index)
                .and_then(Value::as_u64)
                .unwrap_or(1)
                != 0,
            precip_probability: hourly["precipitation_probability"]
                .get(index)
                .and_then(Value::as_u64)
                .map(|value| value.min(100) as u32),
            feels_like_c: hourly["apparent_temperature"]
                .get(index)
                .and_then(Value::as_f64),
        });
    }
    hours
}

/// 从当前小时开始截取；Open-Meteo 的 `current.time` 使用地点本地时区。
fn hourly_start_index(times: &[Value], value: &Value) -> usize {
    let current = value["current"]["time"].as_str().unwrap_or("");
    let prefix = current.get(..13).unwrap_or("");
    if prefix.is_empty() {
        return 0;
    }
    times
        .iter()
        .position(|time| {
            time.as_str()
                .and_then(|text| text.get(..13))
                .map(|text| text == prefix)
                .unwrap_or(false)
        })
        .unwrap_or(0)
}

/// ISO 时间转 `HH:mm`，用于岛体逐时标签。
fn hour_label(time: &str) -> String {
    time.get(11..16).unwrap_or(time).to_string()
}

fn wttr_days(value: &Value) -> Vec<WeatherDay> {
    let Some(days) = value["weather"].as_array() else {
        return Vec::new();
    };
    days.iter()
        .take(4)
        .filter_map(|day| {
            let date = day["date"].as_str()?.to_string();
            let high = number(&day["maxtempC"])?;
            let low = number(&day["mintempC"])?;
            let hours = day["hourly"].as_array()?;
            let noon = hours
                .iter()
                .find(|hour| hour["time"].as_str() == Some("1200"))
                .or_else(|| hours.first())?;
            let code = integer(&noon["weatherCode"])? as u16;
            let kind = kind_from_wwo(code);
            let description = wttr_description(noon["lang_zh-cn"][0]["value"].as_str(), code, kind);
            Some(WeatherDay {
                date,
                kind: kind.to_string(),
                description,
                high_c: high,
                low_c: low,
                precip_probability: integer(&noon["chanceofrain"]).map(|value| value.min(100)),
            })
        })
        .collect()
}

fn open_meteo_days(daily: &Value) -> Vec<WeatherDay> {
    let Some(dates) = daily["time"].as_array() else {
        return Vec::new();
    };
    let mut days = Vec::new();
    for (index, date) in dates.iter().enumerate() {
        let Some(date) = date.as_str() else {
            continue;
        };
        let Some(code) = daily["weather_code"].get(index).and_then(Value::as_u64) else {
            continue;
        };
        let Some(high) = daily["temperature_2m_max"]
            .get(index)
            .and_then(Value::as_f64)
        else {
            continue;
        };
        let Some(low) = daily["temperature_2m_min"]
            .get(index)
            .and_then(Value::as_f64)
        else {
            continue;
        };
        let code = code as u16;
        let kind = kind_from_wmo(code);
        days.push(WeatherDay {
            date: date.to_string(),
            kind: kind.to_string(),
            description: describe_wmo(code).to_string(),
            high_c: high,
            low_c: low,
            precip_probability: daily["precipitation_probability_max"]
                .get(index)
                .and_then(Value::as_u64)
                .map(|value| value.min(100) as u32),
        });
        if days.len() >= 4 {
            break;
        }
    }
    days
}

fn number(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .or_else(|| value.as_str().and_then(|text| text.parse().ok()))
}

fn integer(value: &Value) -> Option<u32> {
    value
        .as_u64()
        .map(|value| value as u32)
        .or_else(|| value.as_str().and_then(|text| text.parse().ok()))
}

fn wttr_place(value: &Value) -> String {
    let area = &value["nearest_area"][0];
    let name = area["areaName"][0]["value"].as_str().unwrap_or("").trim();
    let region = area["region"][0]["value"].as_str().unwrap_or("").trim();
    if name.is_empty() {
        return String::new();
    }
    if region.is_empty() || region == name {
        name.to_string()
    } else {
        format!("{name} · {region}")
    }
}

fn wttr_is_day(value: &Value) -> bool {
    use chrono::Timelike;
    let astronomy = &value["weather"][0]["astronomy"][0];
    if let (Some(sunrise), Some(sunset)) = (
        astronomy["sunrise"].as_str().and_then(parse_12_hour),
        astronomy["sunset"].as_str().and_then(parse_12_hour),
    ) {
        let now = chrono::Local::now();
        let minutes = now.hour() * 60 + now.minute();
        return minutes >= sunrise && minutes < sunset;
    }
    let hour = chrono::Local::now().hour();
    (6..18).contains(&hour)
}

fn parse_12_hour(text: &str) -> Option<u32> {
    let (clock, period) = text.trim().split_once(' ')?;
    let (hour, minute) = clock.split_once(':')?;
    let mut hour: u32 = hour.parse().ok()?;
    let minute: u32 = minute.parse().ok()?;
    if hour == 12 {
        hour = 0;
    }
    if period.eq_ignore_ascii_case("PM") {
        hour += 12;
    }
    Some(hour * 60 + minute)
}

fn kind_from_wmo(code: u16) -> &'static str {
    match code {
        0 => "clear",
        1 | 2 => "partly",
        3 => "cloudy",
        45 | 48 => "fog",
        51..=57 => "drizzle",
        61..=67 => "rain",
        71..=77 => "snow",
        80..=82 => "rain",
        85 | 86 => "snow",
        95..=99 => "thunder",
        _ => "cloudy",
    }
}

/// wttr.in 使用 World Weather Online 的天气代码。
fn kind_from_wwo(code: u16) -> &'static str {
    match code {
        113 => "clear",
        116 => "partly",
        119 | 122 => "cloudy",
        143 | 149 | 248 | 260 => "fog",
        263 | 266 | 281 | 284 => "drizzle",
        176 | 293 | 296 | 299 | 302 | 305 | 308 | 311 | 314 | 353 | 356 | 359 => "rain",
        179 | 182 | 185 | 227 | 230 | 317 | 320 | 323 | 326 | 329 | 332 | 335 | 338 | 350 | 362
        | 365 | 368 | 371 | 374 | 377 => "snow",
        200 | 386 | 389 | 392 | 395 => "thunder",
        _ => "cloudy",
    }
}

/// wttr.in 的 zh-cn 字段有时直接回传英文，例如 149 的 Smoky haze。
fn has_cjk(text: &str) -> bool {
    text.chars()
        .any(|ch| ('\u{4e00}'..='\u{9fff}').contains(&ch))
}

/// 优先使用 wttr 的中文描述，缺失时按天气代码或 kind 兜底。
fn wttr_description(value: Option<&str>, code: u16, kind: &str) -> String {
    value
        .map(str::trim)
        .filter(|text| !text.is_empty() && has_cjk(text))
        .map(str::to_string)
        .or_else(|| describe_wwo(code).map(str::to_string))
        .unwrap_or_else(|| describe_kind(kind).to_string())
}

/// wttr 未提供中文时的固定文案。
fn describe_wwo(code: u16) -> Option<&'static str> {
    match code {
        143 => Some("薄雾"),
        149 => Some("霾"),
        248 => Some("雾"),
        260 => Some("冻雾"),
        _ => None,
    }
}

fn describe_kind(kind: &str) -> &'static str {
    match kind {
        "clear" => "晴",
        "partly" => "多云",
        "cloudy" => "阴",
        "fog" => "雾",
        "drizzle" => "毛毛雨",
        "rain" => "雨",
        "snow" => "雪",
        "thunder" => "雷阵雨",
        _ => "多云",
    }
}

fn describe_wmo(code: u16) -> &'static str {
    match code {
        0 => "晴",
        1 => "晴间多云",
        2 => "多云",
        3 => "阴",
        45 | 48 => "雾",
        51 | 53 | 55 => "毛毛雨",
        56 | 57 | 66 | 67 => "冻雨",
        61 => "小雨",
        63 => "中雨",
        65 => "大雨",
        71 => "小雪",
        73 => "中雪",
        75 => "大雪",
        77 => "米雪",
        80 => "阵雨",
        81 => "强阵雨",
        82 => "暴雨",
        85 => "阵雪",
        86 => "强阵雪",
        95 => "雷阵雨",
        97 => "强雷阵雨",
        96 | 99 => "雷暴伴冰雹",
        _ => "多云",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_wttr_payload() {
        let snapshot = parse_wttr(
            &json!({
                "current_condition": [{
                    "temp_C": "19",
                    "FeelsLikeC": "17",
                    "humidity": "68",
                    "windspeedKmph": "19",
                    "weatherCode": "122",
                    "lang_zh-cn": [{ "value": "阴" }],
                    "weatherDesc": [{ "value": "Overcast" }],
                }],
                "nearest_area": [{
                    "areaName": [{ "value": "Guangzhou" }],
                    "region": [{ "value": "Guangdong" }],
                }],
                "weather": [
                    {
                        "date": "2026-11-18",
                        "maxtempC": "24",
                        "mintempC": "18",
                        "astronomy": [{
                            "sunrise": "06:42 AM",
                            "sunset": "05:42 PM",
                        }],
                        "hourly": [{
                            "time": "1200",
                            "weatherCode": "116",
                            "chanceofrain": "20",
                            "lang_zh-cn": [{ "value": "多云" }],
                        }],
                    },
                ],
            }),
            Some("广州"),
        )
        .expect("payload should parse");
        assert_eq!(snapshot.place, "广州");
        assert_eq!(snapshot.temp_c, 19.0);
        assert_eq!(snapshot.kind, "cloudy");
        assert_eq!(snapshot.description, "阴");
        assert_eq!(snapshot.feels_like_c, Some(17.0));
        assert_eq!(snapshot.humidity, Some(68));
        assert_eq!(snapshot.wind_kph, Some(19.0));
        assert_eq!(snapshot.high_c, Some(24.0));
        assert_eq!(snapshot.low_c, Some(18.0));
        assert_eq!(snapshot.days.len(), 1);
        assert_eq!(snapshot.days[0].kind, "partly");
        assert_eq!(snapshot.days[0].precip_probability, Some(20));
    }

    #[test]
    fn replaces_untranslated_wttr_description() {
        let snapshot = parse_wttr(
            &json!({
                "current_condition": [{
                    "temp_C": "8",
                    "weatherCode": "149",
                    "lang_zh-cn": [{ "value": "Smoky haze" }],
                    "weatherDesc": [{ "value": "Smoky haze" }],
                }],
                "nearest_area": [{
                    "areaName": [{ "value": "Shanghai" }],
                    "region": [{ "value": "Shanghai" }],
                }],
                "weather": [],
            }),
            Some("上海"),
        )
        .expect("payload should parse");
        assert_eq!(snapshot.kind, "fog");
        assert_eq!(snapshot.description, "霾");
        assert!(snapshot.days.is_empty());
    }

    #[test]
    fn wttr_description_falls_back_to_kind_label() {
        assert_eq!(
            wttr_description(Some("Partly cloudy"), 116, "partly"),
            "多云"
        );
        assert_eq!(wttr_description(Some("阴"), 122, "cloudy"), "阴");
        assert_eq!(wttr_description(None, 999, "rain"), "雨");
    }

    #[test]
    fn parses_open_meteo_payload() {
        let snapshot = parse_open_meteo(
            &json!({
                "current": {
                    "temperature_2m": 20.2,
                    "is_day": 0,
                    "weather_code": 0,
                    "apparent_temperature": 18.6,
                    "relative_humidity_2m": 67,
                    "wind_speed_10m": 17.7,
                },
                "daily": {
                    "time": ["2026-11-18", "2026-11-19"],
                    "weather_code": [53, 3],
                    "temperature_2m_max": [25.4, 21.4],
                    "temperature_2m_min": [17.3, 15.2],
                    "precipitation_probability_max": [30, 10],
                },
            }),
            "广州",
        )
        .expect("payload should parse");
        assert_eq!(snapshot.place, "广州");
        assert_eq!(snapshot.temp_c, 20.2);
        assert_eq!(snapshot.kind, "clear");
        assert_eq!(snapshot.description, "晴");
        assert!(!snapshot.is_day);
        assert_eq!(snapshot.feels_like_c, Some(18.6));
        assert_eq!(snapshot.humidity, Some(67));
        assert_eq!(snapshot.wind_kph, Some(17.7));
        assert_eq!(snapshot.high_c, Some(25.4));
        assert_eq!(snapshot.low_c, Some(17.3));
        assert_eq!(snapshot.days.len(), 2);
        assert_eq!(snapshot.days[0].kind, "drizzle");
        assert_eq!(snapshot.days[0].precip_probability, Some(30));
        assert_eq!(snapshot.days[1].kind, "cloudy");
    }

    #[test]
    fn parses_wttr_hourly_slots() {
        let hourly: Vec<Value> = (0..8)
            .map(|index| {
                json!({
                    "time": (index * 300).to_string(),
                    "tempC": "10",
                    "FeelsLikeC": "9",
                    "weatherCode": "122",
                    "lang_zh-cn": [{ "value": "阴" }],
                    "chanceofrain": "20",
                })
            })
            .collect();
        let hours = wttr_hours(&json!({
            "weather": [
                { "date": "2026-11-20", "hourly": hourly },
                { "date": "2026-11-21", "hourly": hourly.clone() },
            ],
        }));
        assert_eq!(hours.len(), 8);
        assert!(hours.iter().all(|hour| hour.temp_c == 10.0));
        assert!(hours.iter().all(|hour| hour.kind == "cloudy"));
        assert!(hours.iter().all(|hour| hour.description == "阴"));
        assert!(hours.iter().all(|hour| hour.precip_probability == Some(20)));
        assert!(hours.iter().all(|hour| hour.time.ends_with(":00")));
    }

    #[test]
    fn parses_wttr_hour_labels() {
        assert_eq!(parse_wttr_hour("0"), Some(0));
        assert_eq!(parse_wttr_hour("300"), Some(3));
        assert_eq!(parse_wttr_hour("1200"), Some(12));
        assert_eq!(parse_wttr_hour("2100"), Some(21));
        assert_eq!(parse_wttr_hour("bad"), None);
    }

    #[test]
    fn parses_hourly_window_from_current_hour() {
        let value = json!({
            "current": { "time": "2026-11-20T21:15" },
            "hourly": {
                "time": [
                    "2026-11-20T19:00",
                    "2026-11-20T20:00",
                    "2026-11-20T21:00",
                    "2026-11-20T22:00",
                    "2026-11-20T23:00",
                    "2026-11-21T00:00",
                ],
                "temperature_2m": [10.0, 11.0, 12.0, 13.0, 14.0, 15.0],
                "weather_code": [0, 1, 2, 3, 45, 61],
                "is_day": [1, 1, 0, 0, 0, 0],
                "precipitation_probability": [0, 0, 10, 20, 30, 80],
                "apparent_temperature": [9.0, 10.0, 11.0, 12.0, 13.0, 14.0],
            },
        });
        let hours = open_meteo_hours(&value);
        assert_eq!(hours.len(), 4);
        assert_eq!(hours[0].time, "21:00");
        assert_eq!(hours[0].temp_c, 12.0);
        assert_eq!(hours[0].kind, "partly");
        assert!(!hours[0].is_day);
        assert_eq!(hours[0].precip_probability, Some(10));
        assert_eq!(hours[3].time, "00:00");
        assert_eq!(hours[3].kind, "rain");
        assert_eq!(hours[3].precip_probability, Some(80));
    }

    #[test]
    fn parses_seven_timer_days() {
        let days = parse_seven_timer_at(
            &json!({
                "init": "2026111800",
                "dataseries": [
                    { "timepoint": 3, "temp2m": 20, "weather": "cloudyday" },
                    { "timepoint": 6, "temp2m": 25, "weather": "pcloudyday" },
                    { "timepoint": 9, "temp2m": 18, "weather": "lightrainday" },
                    { "timepoint": 27, "temp2m": 22, "weather": "clearday" },
                    { "timepoint": 51, "temp2m": 19, "weather": "cloudynight" },
                ],
            }),
            chrono::NaiveDate::from_ymd_opt(2026, 11, 18).expect("valid date"),
        );
        assert_eq!(days.len(), 3);
        assert_eq!(days[0].date, "2026-11-18");
        assert_eq!(days[0].high_c, 25.0);
        assert_eq!(days[0].low_c, 18.0);
        assert_eq!(days[0].kind, "cloudy");
        assert_eq!(days[1].kind, "clear");
        assert_eq!(days[2].kind, "cloudy");
    }

    #[test]
    fn parses_geocoding_results() {
        let places = parse_places(&json!({
            "results": [
                {
                    "name": "广州",
                    "latitude": 23.11667,
                    "longitude": 113.25,
                    "country": "中国",
                    "admin1": "广东省",
                    "admin2": "广州市",
                },
                {
                    "name": "新加坡",
                    "latitude": 1.28967,
                    "longitude": 103.85007,
                    "country": "新加坡",
                    "admin1": "新加坡",
                },
                {
                    "name": "",
                    "latitude": 0,
                    "longitude": 0,
                },
            ],
        }));
        assert_eq!(places.len(), 2);
        assert_eq!(places[0].name, "广州");
        assert_eq!(places[0].label, "广州 · 广东省 · 中国");
        assert_eq!(places[1].label, "新加坡");
    }

    #[test]
    fn rejects_malformed_payloads() {
        assert!(parse_wttr(&json!({}), None).is_none());
        assert!(parse_wttr(&json!({ "current_condition": [{ "temp_C": "x" }] }), None).is_none());
        assert!(parse_open_meteo(&json!({}), "x").is_none());
        assert!(parse_open_meteo(&json!({ "current": {} }), "x").is_none());
    }

    #[test]
    fn parses_twelve_hour_clock() {
        assert_eq!(parse_12_hour("06:42 AM"), Some(402));
        assert_eq!(parse_12_hour("12:05 AM"), Some(5));
        assert_eq!(parse_12_hour("05:42 PM"), Some(1062));
        assert_eq!(parse_12_hour("bad"), None);
    }
}
