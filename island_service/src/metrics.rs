//! 系统指标采样：CPU、内存、网络速率、累计流量与 GPU。
//!
//! 采样线程按 1Hz 运行，只向 stdout 推送 `metrics.updated`；主循环缓存最近一帧
//! 供 `metrics.get` 读取。网络流量只统计处于 Up 状态的硬件网卡，避免虚拟网桥
//! 与物理网卡重复计数。累计流量从 sidecar 启动开始计算，不同会话之间不累加。
//! GPU 利用率与专用显存用量取自 PDH 性能计数器，显存总量取自 DXGI。

use serde::Serialize;
use serde_json::{json, Value};
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::rpc::{self, State};

const SAMPLE_INTERVAL: Duration = Duration::from_secs(1);

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricsSnapshot {
    pub upload_bps: f64,
    pub download_bps: f64,
    pub cpu_percent: f64,
    pub memory_percent: f64,
    pub memory_used_bytes: u64,
    pub memory_total_bytes: u64,
    pub cpu_mhz: u32,
    pub cpu_max_mhz: u32,
    pub gpu_percent: f64,
    pub gpu_memory_percent: f64,
    pub gpu_memory_used_bytes: u64,
    pub gpu_memory_total_bytes: u64,
    pub total_upload_bytes: u64,
    pub total_download_bytes: u64,
    pub updated_at_ms: i64,
}

/// 启动采样线程。非 Windows 平台保留空实现，保证 State 与协议仍能编译。
pub fn start(state: Arc<State>, tx: Sender<Value>) {
    #[cfg(windows)]
    {
        let spawned = std::thread::Builder::new()
            .name("metrics".into())
            .spawn(move || run(state, tx));
        if let Err(error) = spawned {
            crate::log(&format!("metrics: 线程启动失败: {error}"));
        }
    }
    #[cfg(not(windows))]
    {
        let _ = (state, tx);
    }
}

#[cfg(windows)]
fn run(state: Arc<State>, tx: Sender<Value>) {
    // 第一次只建立基线，CPU 与网络速率都需要一个时间窗口才能算出增量。
    let mut baseline = Baseline::capture();
    let mut gpu = GpuSampler::new();
    let mut total_upload = 0u64;
    let mut total_download = 0u64;
    loop {
        std::thread::sleep(SAMPLE_INTERVAL);
        let now = Baseline::capture();
        let elapsed = now.at.duration_since(baseline.at).as_secs_f64().max(0.1);

        let upload_delta = now.net_up.saturating_sub(baseline.net_up);
        let download_delta = now.net_down.saturating_sub(baseline.net_down);
        total_upload = total_upload.saturating_add(upload_delta);
        total_download = total_download.saturating_add(download_delta);
        let (memory_percent, memory_used, memory_total) = memory();
        let (cpu_mhz, cpu_max_mhz) = cpu_frequency();
        let (gpu_percent, gpu_memory_used, gpu_memory_total) = gpu
            .as_mut()
            .map(GpuSampler::sample)
            .unwrap_or((0.0, 0, 0));
        let gpu_memory_percent = if gpu_memory_total > 0 {
            (gpu_memory_used as f64 / gpu_memory_total as f64 * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        };

        let snapshot = MetricsSnapshot {
            upload_bps: upload_delta as f64 / elapsed,
            download_bps: download_delta as f64 / elapsed,
            cpu_percent: cpu_usage(baseline, now),
            memory_percent,
            memory_used_bytes: memory_used,
            memory_total_bytes: memory_total,
            cpu_mhz,
            cpu_max_mhz,
            gpu_percent,
            gpu_memory_percent,
            gpu_memory_used_bytes: gpu_memory_used,
            gpu_memory_total_bytes: gpu_memory_total,
            total_upload_bytes: total_upload,
            total_download_bytes: total_download,
            updated_at_ms: chrono::Utc::now().timestamp_millis(),
        };

        if let Ok(mut slot) = state.metrics.lock() {
            *slot = Some(snapshot.clone());
        }
        let mut value = serde_json::to_value(&snapshot).unwrap_or(Value::Null);
        if let Value::Object(ref mut object) = value {
            object.insert("type".into(), json!("metrics.updated"));
        }
        if tx.send(rpc::event(value)).is_err() {
            return;
        }
        baseline = now;
    }
}

#[cfg(windows)]
#[derive(Clone, Copy)]
struct Baseline {
    at: Instant,
    idle: u64,
    total: u64,
    net_down: u64,
    net_up: u64,
}

#[cfg(windows)]
impl Baseline {
    fn capture() -> Self {
        let (idle, total) = cpu_times();
        let (net_down, net_up) = network_totals();
        Self {
            at: Instant::now(),
            idle,
            total,
            net_down,
            net_up,
        }
    }
}

#[cfg(windows)]
fn cpu_usage(before: Baseline, after: Baseline) -> f64 {
    let idle = after.idle.saturating_sub(before.idle);
    let total = after.total.saturating_sub(before.total);
    if total == 0 {
        return 0.0;
    }
    let busy = total.saturating_sub(idle);
    (busy as f64 / total as f64 * 100.0).clamp(0.0, 100.0)
}

#[cfg(windows)]
fn cpu_times() -> (u64, u64) {
    use windows::Win32::Foundation::FILETIME;
    use windows::Win32::System::Threading::GetSystemTimes;

    let mut idle = FILETIME::default();
    let mut kernel = FILETIME::default();
    let mut user = FILETIME::default();
    let ok = unsafe { GetSystemTimes(Some(&mut idle), Some(&mut kernel), Some(&mut user)) };
    if ok.is_err() {
        return (0, 0);
    }
    (
        filetime(&idle),
        filetime(&kernel).saturating_add(filetime(&user)),
    )
}

#[cfg(windows)]
fn filetime(time: &windows::Win32::Foundation::FILETIME) -> u64 {
    ((time.dwHighDateTime as u64) << 32) | time.dwLowDateTime as u64
}

#[cfg(windows)]
fn memory() -> (f64, u64, u64) {
    use windows::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};

    let mut status = MEMORYSTATUSEX {
        dwLength: std::mem::size_of::<MEMORYSTATUSEX>() as u32,
        ..Default::default()
    };
    if unsafe { GlobalMemoryStatusEx(&mut status) }.is_err() {
        return (0.0, 0, 0);
    }
    let used = status.ullTotalPhys.saturating_sub(status.ullAvailPhys);
    (status.dwMemoryLoad as f64, used, status.ullTotalPhys)
}

#[cfg(windows)]
fn cpu_frequency() -> (u32, u32) {
    use windows::Win32::System::Power::{
        CallNtPowerInformation, ProcessorInformation, PROCESSOR_POWER_INFORMATION,
    };
    use windows::Win32::System::Threading::{GetActiveProcessorCount, ALL_PROCESSOR_GROUPS};

    let count = unsafe { GetActiveProcessorCount(ALL_PROCESSOR_GROUPS) } as usize;
    if count == 0 {
        return (0, 0);
    }
    let mut buffer = vec![PROCESSOR_POWER_INFORMATION::default(); count];
    let bytes = (buffer.len() * std::mem::size_of::<PROCESSOR_POWER_INFORMATION>()) as u32;
    let status = unsafe {
        CallNtPowerInformation(
            ProcessorInformation,
            None,
            0,
            Some(buffer.as_mut_ptr().cast()),
            bytes,
        )
    };
    if status.0 < 0 {
        return (0, 0);
    }
    let mut current = 0u64;
    let mut max = 0u64;
    for info in &buffer {
        current += info.CurrentMhz as u64;
        max += info.MaxMhz as u64;
    }
    ((current / count as u64) as u32, (max / count as u64) as u32)
}

/// 汇总所有 Up 状态硬件网卡的累计收发字节。`HardwareInterface` 位可排除
/// Hyper-V、Wintun 等虚拟网卡，避免同一份流量被计算两次。
#[cfg(windows)]
fn network_totals() -> (u64, u64) {
    use windows::Win32::NetworkManagement::IpHelper::{
        FreeMibTable, GetIfTable2, IF_TYPE_SOFTWARE_LOOPBACK, MIB_IF_TABLE2,
    };
    use windows::Win32::NetworkManagement::Ndis::IfOperStatusUp;

    let mut table: *mut MIB_IF_TABLE2 = std::ptr::null_mut();
    if unsafe { GetIfTable2(&mut table) }.0 != 0 || table.is_null() {
        return (0, 0);
    }
    let rows = unsafe {
        std::slice::from_raw_parts((*table).Table.as_ptr(), (*table).NumEntries as usize)
    };
    let mut received = 0u64;
    let mut sent = 0u64;
    for row in rows {
        let hardware = row.InterfaceAndOperStatusFlags._bitfield & 0x01 != 0;
        if !hardware || row.OperStatus != IfOperStatusUp || row.Type == IF_TYPE_SOFTWARE_LOOPBACK {
            continue;
        }
        received = received.saturating_add(row.InOctets);
        sent = sent.saturating_add(row.OutOctets);
    }
    unsafe { FreeMibTable(table as *const _) };
    (received, sent)
}

/// PDH 采样器：GPU 引擎利用率与专用显存用量。
#[cfg(windows)]
struct GpuSampler {
    query: isize,
    engine: Option<isize>,
    dedicated: Option<isize>,
    memory_total: u64,
    last_total_probe: Option<Instant>,
}

#[cfg(windows)]
impl GpuSampler {
    fn new() -> Option<Self> {
        use windows::Win32::System::Performance::{
            PdhCloseQuery, PdhCollectQueryData, PdhOpenQueryW,
        };

        let mut query = 0isize;
        // 数据源传 NULL 表示实时数据；空字符串会被 PDH 判为非法参数。
        let status = unsafe { PdhOpenQueryW(None, 0, &mut query) };
        if status != 0 {
            crate::log(&format!("metrics: GPU 查询创建失败 ({status:#x})"));
            return None;
        }
        let engine = add_counter(query, "\\GPU Engine(*)\\Utilization Percentage");
        let dedicated = add_counter(query, "\\GPU Adapter Memory(*)\\Dedicated Usage");
        if engine.is_none() && dedicated.is_none() {
            unsafe { PdhCloseQuery(query) };
            return None;
        }
        // 建立 PDH 基线，下一次采集才有百分比与增量。
        unsafe { PdhCollectQueryData(query) };
        let mut sampler = Self {
            query,
            engine,
            dedicated,
            memory_total: 0,
            last_total_probe: None,
        };
        sampler.memory_total = gpu_memory_total();
        sampler.last_total_probe = Some(Instant::now());
        Some(sampler)
    }

    /// 返回 `(利用率, 专用显存已用, 专用显存总量)`。
    fn sample(&mut self) -> (f64, u64, u64) {
        use windows::Win32::System::Performance::PdhCollectQueryData;

        if unsafe { PdhCollectQueryData(self.query) } != 0 {
            return (0.0, 0, self.memory_total);
        }
        // 多个引擎、多个进程实例的利用率相加后可能超过 100，按整体占用截断。
        let gpu_percent = self
            .engine
            .map(|counter| {
                read_counter_array(counter)
                    .into_iter()
                    .sum::<f64>()
                    .clamp(0.0, 100.0)
            })
            .unwrap_or(0.0);
        let used = self
            .dedicated
            .map(|counter| {
                read_counter_array(counter)
                    .into_iter()
                    .sum::<f64>()
                    .max(0.0) as u64
            })
            .unwrap_or(0);
        // 显存总量在启动时探测一次；取不到时每 30 秒重试，兼容 eGPU 热插拔。
        if self.memory_total == 0
            && self
                .last_total_probe
                .map_or(true, |at| at.elapsed() >= Duration::from_secs(30))
        {
            self.memory_total = gpu_memory_total();
            self.last_total_probe = Some(Instant::now());
        }
        (gpu_percent, used, self.memory_total)
    }
}

#[cfg(windows)]
impl Drop for GpuSampler {
    fn drop(&mut self) {
        unsafe { windows::Win32::System::Performance::PdhCloseQuery(self.query) };
    }
}

#[cfg(windows)]
fn add_counter(query: isize, path: &str) -> Option<isize> {
    use windows::Win32::System::Performance::PdhAddEnglishCounterW;

    let path = windows::core::HSTRING::from(path);
    let mut counter = 0isize;
    let status = unsafe { PdhAddEnglishCounterW(query, &path, 0, &mut counter) };
    (status == 0).then_some(counter)
}

/// 读取通配符计数器的全部实例值。缓冲区不足时 PDH 返回 `PDH_MORE_DATA`，
/// 按返回的字节数分配后再读一次。
#[cfg(windows)]
fn read_counter_array(counter: isize) -> Vec<f64> {
    use windows::Win32::System::Performance::{
        PdhGetFormattedCounterArrayW, PDH_FMT_COUNTERVALUE_ITEM_W, PDH_FMT_DOUBLE, PDH_MORE_DATA,
    };

    let mut size = 0u32;
    let mut count = 0u32;
    let status = unsafe {
        PdhGetFormattedCounterArrayW(counter, PDH_FMT_DOUBLE, &mut size, &mut count, None)
    };
    if status != PDH_MORE_DATA || size == 0 {
        return Vec::new();
    }
    let item_size = std::mem::size_of::<PDH_FMT_COUNTERVALUE_ITEM_W>();
    let capacity = (size as usize + item_size - 1) / item_size;
    let mut buffer = vec![PDH_FMT_COUNTERVALUE_ITEM_W::default(); capacity];
    let status = unsafe {
        PdhGetFormattedCounterArrayW(
            counter,
            PDH_FMT_DOUBLE,
            &mut size,
            &mut count,
            Some(buffer.as_mut_ptr()),
        )
    };
    if status != 0 {
        return Vec::new();
    }
    let count = (count as usize).min(buffer.len());
    let mut values = Vec::with_capacity(count);
    for item in buffer.iter().take(count) {
        // PDH_CSTATUS_VALID_DATA = 0，PDH_CSTATUS_NEW_DATA = 1。
        if item.FmtValue.CStatus > 1 {
            continue;
        }
        let value = unsafe { item.FmtValue.Anonymous.doubleValue };
        if value.is_finite() && value >= 0.0 {
            values.push(value);
        }
    }
    values
}

/// 汇总所有 DXGI 适配器的专用显存容量；软件适配器容量为 0，不影响结果。
#[cfg(windows)]
fn gpu_memory_total() -> u64 {
    use windows::Win32::Graphics::Dxgi::{CreateDXGIFactory1, IDXGIFactory1};

    let factory: IDXGIFactory1 = match unsafe { CreateDXGIFactory1() } {
        Ok(factory) => factory,
        Err(_) => return 0,
    };
    let mut total = 0u64;
    for index in 0..16 {
        let Ok(adapter) = (unsafe { factory.EnumAdapters1(index) }) else {
            break;
        };
        if let Ok(desc) = unsafe { adapter.GetDesc1() } {
            total = total.saturating_add(desc.DedicatedVideoMemory as u64);
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_serializes_with_camel_case_keys() {
        let snapshot = MetricsSnapshot {
            upload_bps: 1.5,
            download_bps: 2.5,
            cpu_percent: 12.0,
            memory_percent: 48.0,
            memory_used_bytes: 8_000,
            memory_total_bytes: 16_000,
            cpu_mhz: 3200,
            cpu_max_mhz: 4800,
            gpu_percent: 42.0,
            gpu_memory_percent: 33.0,
            gpu_memory_used_bytes: 4_000,
            gpu_memory_total_bytes: 12_000,
            total_upload_bytes: 100,
            total_download_bytes: 200,
            updated_at_ms: 1,
        };
        let value = serde_json::to_value(&snapshot).unwrap();
        assert_eq!(value["uploadBps"], 1.5);
        assert_eq!(value["cpuPercent"], 12.0);
        assert_eq!(value["gpuPercent"], 42.0);
        assert_eq!(value["gpuMemoryUsedBytes"], 4_000);
        assert_eq!(value["totalDownloadBytes"], 200);
    }
}
