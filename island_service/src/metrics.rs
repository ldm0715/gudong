//! 系统指标采样：CPU、内存、网络速率、累计流量与 GPU。
//!
//! 采样线程按 1Hz 运行，只向 stdout 推送 `metrics.updated`；主循环缓存最近一帧
//! 供 `metrics.get` 读取。网络流量只统计处于 Up 状态的硬件网卡，避免虚拟网桥
//! 与物理网卡重复计数。累计流量从 sidecar 启动开始计算，不同会话之间不累加。
//! GPU 利用率与专用显存用量取自 PDH 性能计数器，显存总量取自 DXGI。

use serde::Serialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::rpc::{self, State};

const SAMPLE_INTERVAL: Duration = Duration::from_secs(1);

/// 单块显卡的实时指标。`id` 为 `gpu0` / `gpu1`，按 DXGI 枚举顺序排列。
#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GpuSnapshot {
    pub id: String,
    pub name: String,
    pub utilization_percent: f64,
    pub memory_used_bytes: u64,
    pub memory_total_bytes: u64,
    pub memory_percent: f64,
}

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
    pub gpus: Vec<GpuSnapshot>,
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
    let mut cpu = CpuPerformance::new();
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
        let (cpu_mhz, cpu_max_mhz) = if let Some(sampler) = cpu.as_mut() {
            let mhz = sampler.sample();
            let max = sampler.max_mhz();
            mhz.map(|mhz| (mhz, max)).unwrap_or_else(cpu_frequency)
        } else {
            cpu_frequency()
        };
        let gpus = gpu.as_mut().map(GpuSampler::sample).unwrap_or_default();
        let gpu_percent = gpus
            .iter()
            .map(|gpu| gpu.utilization_percent)
            .sum::<f64>()
            .clamp(0.0, 100.0);
        let gpu_memory_used = gpus.iter().map(|gpu| gpu.memory_used_bytes).sum();
        let gpu_memory_total = gpus.iter().map(|gpu| gpu.memory_total_bytes).sum();
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
            gpus,
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

/// 一块可上报的显卡。`key` 与 PDH 实例名里的 LUID 对应。
#[cfg(windows)]
struct GpuAdapter {
    key: String,
    name: String,
    memory_total: u64,
}

/// PDH 采样器：按适配器区分 GPU 引擎利用率与专用显存用量。
#[cfg(windows)]
struct GpuSampler {
    query: isize,
    engine: Option<isize>,
    dedicated: Option<isize>,
    adapters: Vec<GpuAdapter>,
    last_adapter_probe: Instant,
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
        Some(Self {
            query,
            engine,
            dedicated,
            adapters: enumerate_adapters(),
            last_adapter_probe: Instant::now(),
        })
    }

    fn sample(&mut self) -> Vec<GpuSnapshot> {
        use windows::Win32::System::Performance::PdhCollectQueryData;

        // 显卡列表变化不频繁；每 30 秒刷新一次，兼顾 eGPU 热插拔。
        if self.adapters.is_empty() || self.last_adapter_probe.elapsed() >= Duration::from_secs(30)
        {
            self.adapters = enumerate_adapters();
            self.last_adapter_probe = Instant::now();
        }
        if unsafe { PdhCollectQueryData(self.query) } != 0 {
            return self
                .adapters
                .iter()
                .enumerate()
                .map(|(index, adapter)| snapshot_of(index, adapter, 0.0, 0))
                .collect();
        }

        let mut usage: HashMap<String, f64> = HashMap::new();
        if let Some(counter) = self.engine {
            for (name, value) in read_counter_array_named(counter) {
                if let Some(key) = luid_key(&name) {
                    *usage.entry(key).or_insert(0.0) += value;
                }
            }
        }
        let mut memory: HashMap<String, f64> = HashMap::new();
        if let Some(counter) = self.dedicated {
            for (name, value) in read_counter_array_named(counter) {
                if let Some(key) = luid_key(&name) {
                    *memory.entry(key).or_insert(0.0) += value;
                }
            }
        }

        self.adapters
            .iter()
            .enumerate()
            .map(|(index, adapter)| {
                let utilization = usage
                    .get(&adapter.key)
                    .copied()
                    .unwrap_or(0.0)
                    .clamp(0.0, 100.0);
                let used = memory
                    .get(&adapter.key)
                    .copied()
                    .unwrap_or(0.0)
                    .max(0.0) as u64;
                snapshot_of(index, adapter, utilization, used)
            })
            .collect()
    }
}

#[cfg(windows)]
fn snapshot_of(index: usize, adapter: &GpuAdapter, utilization: f64, used: u64) -> GpuSnapshot {
    let percent = if adapter.memory_total > 0 {
        (used as f64 / adapter.memory_total as f64 * 100.0).clamp(0.0, 100.0)
    } else {
        0.0
    };
    GpuSnapshot {
        id: format!("gpu{index}"),
        name: adapter.name.clone(),
        utilization_percent: utilization,
        memory_used_bytes: used,
        memory_total_bytes: adapter.memory_total,
        memory_percent: percent,
    }
}

#[cfg(windows)]
impl Drop for GpuSampler {
    fn drop(&mut self) {
        unsafe { windows::Win32::System::Performance::PdhCloseQuery(self.query) };
    }
}

/// CPU 频率采样：`% Processor Performance` × 基础频率，能反映实时睿频。
#[cfg(windows)]
struct CpuPerformance {
    query: isize,
    counter: isize,
    base_mhz: u32,
    max_mhz: u32,
    observed_max: u32,
}

#[cfg(windows)]
impl CpuPerformance {
    fn new() -> Option<Self> {
        use windows::Win32::System::Performance::{
            PdhCloseQuery, PdhCollectQueryData, PdhOpenQueryW,
        };

        let (current, max) = cpu_frequency();
        let base = cpu_base_mhz().or(if current > 0 { Some(current) } else { None })?;
        let mut query = 0isize;
        if unsafe { PdhOpenQueryW(None, 0, &mut query) } != 0 {
            return None;
        }
        let counter = add_counter(
            query,
            "\\Processor Information(_Total)\\% Processor Performance",
        );
        let Some(counter) = counter else {
            unsafe { PdhCloseQuery(query) };
            return None;
        };
        unsafe { PdhCollectQueryData(query) };
        let max_mhz = max.max(base);
        Some(Self {
            query,
            counter,
            base_mhz: base,
            max_mhz,
            observed_max: max_mhz,
        })
    }

    fn sample(&mut self) -> Option<u32> {
        use windows::Win32::System::Performance::{
            PdhCollectQueryData, PdhGetFormattedCounterValue, PDH_FMT_COUNTERVALUE, PDH_FMT_DOUBLE,
        };

        if unsafe { PdhCollectQueryData(self.query) } != 0 {
            return None;
        }
        let mut value = PDH_FMT_COUNTERVALUE::default();
        let status =
            unsafe { PdhGetFormattedCounterValue(self.counter, PDH_FMT_DOUBLE, None, &mut value) };
        if status != 0 || value.CStatus > 1 {
            return None;
        }
        let percent = unsafe { value.Anonymous.doubleValue };
        if !percent.is_finite() || percent <= 0.0 {
            return None;
        }
        let mhz = (self.base_mhz as f64 * percent / 100.0).round();
        if mhz <= 0.0 {
            return None;
        }
        let mhz = mhz as u32;
        // 睿频会超过标称最大频率，记录运行期见过的峰值。
        self.observed_max = self.observed_max.max(mhz).max(self.max_mhz);
        Some(mhz)
    }

    fn max_mhz(&self) -> u32 {
        self.observed_max
    }
}

#[cfg(windows)]
impl Drop for CpuPerformance {
    fn drop(&mut self) {
        unsafe { windows::Win32::System::Performance::PdhCloseQuery(self.query) };
    }
}

/// 注册表里的标称基础频率，`% Processor Performance` 以它为基准。
#[cfg(windows)]
fn cpu_base_mhz() -> Option<u32> {
    use windows::core::HSTRING;
    use windows::Win32::System::Registry::{
        RegGetValueW, HKEY_LOCAL_MACHINE, RRF_RT_REG_DWORD,
    };

    let subkey = HSTRING::from(r"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
    let value = HSTRING::from("~MHz");
    let mut data = 0u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    let status = unsafe {
        RegGetValueW(
            HKEY_LOCAL_MACHINE,
            &subkey,
            &value,
            RRF_RT_REG_DWORD,
            None,
            Some((&mut data as *mut u32).cast()),
            Some(&mut size),
        )
    };
    if status.is_err() || data == 0 {
        None
    } else {
        Some(data)
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

/// 读取通配符计数器的全部实例名与值。缓冲区不足时 PDH 返回 `PDH_MORE_DATA`，
/// 按返回的字节数分配后再读一次。
#[cfg(windows)]
fn read_counter_array_named(counter: isize) -> Vec<(String, f64)> {
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
        if !value.is_finite() || value < 0.0 {
            continue;
        }
        let name = if item.szName.is_null() {
            String::new()
        } else {
            unsafe { item.szName.to_string() }.unwrap_or_default()
        };
        values.push((name, value));
    }
    values
}

/// 枚举真实显卡。跳过软件适配器和没有专用显存的虚拟显示驱动。
#[cfg(windows)]
fn enumerate_adapters() -> Vec<GpuAdapter> {
    use windows::Win32::Graphics::Dxgi::{
        CreateDXGIFactory1, IDXGIFactory1, DXGI_ADAPTER_FLAG_SOFTWARE,
    };

    let factory: IDXGIFactory1 = match unsafe { CreateDXGIFactory1() } {
        Ok(factory) => factory,
        Err(_) => return Vec::new(),
    };
    let mut adapters = Vec::new();
    let mut seen_devices = Vec::new();
    for index in 0..16 {
        let Ok(adapter) = (unsafe { factory.EnumAdapters1(index) }) else {
            break;
        };
        let desc = match unsafe { adapter.GetDesc1() } {
            Ok(desc) => desc,
            Err(_) => continue,
        };
        let software = desc.Flags & (DXGI_ADAPTER_FLAG_SOFTWARE.0 as u32) != 0;
        if software || desc.DedicatedVideoMemory == 0 {
            continue;
        }
        // 部分驱动会把同一块显卡列出多次，按厂商与设备 ID 去重。
        let device = (desc.VendorId, desc.DeviceId);
        if seen_devices.contains(&device) {
            continue;
        }
        seen_devices.push(device);
        let end = desc
            .Description
            .iter()
            .position(|value| *value == 0)
            .unwrap_or(desc.Description.len());
        let name = String::from_utf16_lossy(&desc.Description[..end])
            .trim()
            .to_string();
        let key = format!(
            "0x{:08x}_0x{:08x}",
            desc.AdapterLuid.HighPart as u32, desc.AdapterLuid.LowPart
        );
        adapters.push(GpuAdapter {
            key,
            name,
            memory_total: desc.DedicatedVideoMemory as u64,
        });
    }
    adapters
}

/// 从 PDH 实例名里取出 LUID 段，如 `luid_0x00000000_0x000128bc_phys_0`。
#[cfg(windows)]
fn luid_key(instance: &str) -> Option<String> {
    let mut parts = instance.split('_');
    while let Some(part) = parts.next() {
        if part == "luid" {
            // PDH 实例名使用大写十六进制，DXGI 的 LUID 统一按小写比较。
            let high = parts.next()?.to_ascii_lowercase();
            let low = parts.next()?.to_ascii_lowercase();
            return Some(format!("{high}_{low}"));
        }
    }
    None
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
            gpus: vec![GpuSnapshot {
                id: "gpu0".into(),
                name: "Test GPU".into(),
                utilization_percent: 42.0,
                memory_used_bytes: 4_000,
                memory_total_bytes: 12_000,
                memory_percent: 33.0,
            }],
            total_upload_bytes: 100,
            total_download_bytes: 200,
            updated_at_ms: 1,
        };
        let value = serde_json::to_value(&snapshot).unwrap();
        assert_eq!(value["uploadBps"], 1.5);
        assert_eq!(value["cpuPercent"], 12.0);
        assert_eq!(value["gpuPercent"], 42.0);
        assert_eq!(value["gpuMemoryUsedBytes"], 4_000);
        assert_eq!(value["gpus"][0]["id"], "gpu0");
        assert_eq!(value["gpus"][0]["utilizationPercent"], 42.0);
        assert_eq!(value["totalDownloadBytes"], 200);
    }
}
