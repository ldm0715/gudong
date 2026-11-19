//! 天气：按网络出口定位，再拉取实况。
//!
//! 定位优先 ipwho.is，失败退 freeipapi；天气优先 wttr.in，失败退 Open-Meteo。
//! 三个接口都不需要密钥。日志只记录服务名与错误，不记录 IP 或坐标。

use serde::Serialize;
use serde_json::{json, Value};
use std::io::Read;
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::rpc::{self, State};

const REFRESH_INTERVAL: Duration = Duration::from_secs(15 * 60);
const RETRY_INTERVAL: Duration = Duration::from_secs(2 * 60);
const LOCATE_TTL: Duration = Duration::from_secs(3 * 60 * 60);
const FORECAST_DAYS: usize = 5;

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
    pub days: Vec<WeatherDay>,
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

/// 启动天气线程：先拉一次，之后每 15 分钟刷新，失败 2 分钟后重试。
pub fn start(state: Arc<State>, tx: Sender<Value>) {
    let spawned = std::thread::Builder::new()
        .name("weather".into())
        .spawn(move || {
            let agent = agent();
            let mut location: Option<Location> = None;
            let mut located_at: Option<Instant> = None;
            let mut prefer_wttr = true;
            loop {
                let stale = located_at
                    .map(|at| at.elapsed() >= LOCATE_TTL)
                    .unwrap_or(true);
                if stale {
                    if let Some(found) = locate(&agent) {
                        location = Some(found);
                        located_at = Some(Instant::now());
                    }
                }

                let previous = state.weather.lock().ok().and_then(|slot| slot.clone());
                let snapshot = fetch(&agent, location.as_ref(), &mut prefer_wttr);
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

                let delay = if current.is_some() {
                    REFRESH_INTERVAL
                } else {
                    RETRY_INTERVAL
                };
                std::thread::sleep(delay);
            }
        });
    if let Err(error) = spawned {
        crate::log(&format!("weather: 线程启动失败: {error}"));
    }
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
         &daily=weather_code,temperature_2m_max,temperature_2m_min,\
         precipitation_probability_max&timezone=auto&forecast_days=5",
        location.lat, location.lon
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
        days,
    })
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
