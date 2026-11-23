import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';

/// 单块显卡的实时指标。
class GpuSnapshot {
  const GpuSnapshot({
    required this.id,
    required this.name,
    required this.utilizationPercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    required this.memoryPercent,
  });

  factory GpuSnapshot.fromJson(Map<String, dynamic> json) {
    return GpuSnapshot(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      utilizationPercent: _double(json['utilizationPercent']),
      memoryUsedBytes: _int(json['memoryUsedBytes']),
      memoryTotalBytes: _int(json['memoryTotalBytes']),
      memoryPercent: _double(json['memoryPercent']),
    );
  }

  final String id;
  final String name;
  final double utilizationPercent;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  final double memoryPercent;
}

/// sidecar 每秒推送一帧的系统指标快照。
class MetricsSnapshot {
  const MetricsSnapshot({
    required this.uploadBps,
    required this.downloadBps,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    required this.cpuMhz,
    required this.cpuMaxMhz,
    required this.gpus,
    required this.totalUploadBytes,
    required this.totalDownloadBytes,
    required this.updatedAtMs,
  });

  factory MetricsSnapshot.fromJson(Map<String, dynamic> json) {
    final gpus = <GpuSnapshot>[];
    final raw = json['gpus'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          gpus.add(GpuSnapshot.fromJson(item));
        }
      }
    }
    return MetricsSnapshot(
      uploadBps: _double(json['uploadBps']),
      downloadBps: _double(json['downloadBps']),
      cpuPercent: _double(json['cpuPercent']),
      memoryPercent: _double(json['memoryPercent']),
      memoryUsedBytes: _int(json['memoryUsedBytes']),
      memoryTotalBytes: _int(json['memoryTotalBytes']),
      cpuMhz: _int(json['cpuMhz']),
      cpuMaxMhz: _int(json['cpuMaxMhz']),
      gpus: gpus,
      totalUploadBytes: _int(json['totalUploadBytes']),
      totalDownloadBytes: _int(json['totalDownloadBytes']),
      updatedAtMs: _int(json['updatedAtMs']),
    );
  }

  final double uploadBps;
  final double downloadBps;
  final double cpuPercent;
  final double memoryPercent;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  final int cpuMhz;
  final int cpuMaxMhz;
  final List<GpuSnapshot> gpus;
  final int totalUploadBytes;
  final int totalDownloadBytes;
  final int updatedAtMs;

  double get totalBps => uploadBps + downloadBps;

  int get totalTrafficBytes => totalUploadBytes + totalDownloadBytes;
}

/// 仪表盘可显示的指标。id 同时用于 `dashboardMetrics` / `islandMetrics`。
class DashboardMetric {
  const DashboardMetric(this.id, this.label, this.hint, this.icon);

  final String id;
  final String label;
  final String hint;
  final IconData icon;

  static const upload = DashboardMetric(
    'upload',
    '上传',
    '实时上传速率',
    Icons.upload_rounded,
  );
  static const download = DashboardMetric(
    'download',
    '下载',
    '实时下载速率',
    Icons.download_rounded,
  );
  static const network = DashboardMetric(
    'network',
    '总网速',
    '上传与下载速率之和',
    Icons.swap_vert_rounded,
  );
  static const cpu = DashboardMetric(
    'cpu',
    'CPU 利用率',
    '系统总 CPU 占用率',
    Icons.speed_rounded,
  );
  static const memory = DashboardMetric(
    'memory',
    '内存利用率',
    '物理内存占用率',
    Icons.developer_board_rounded,
  );
  static const gpu0 = DashboardMetric(
    'gpu0',
    'GPU1 利用率',
    '第一块显卡使用率',
    Icons.hardware_rounded,
  );
  static const gpu0Memory = DashboardMetric(
    'gpu0Memory',
    'GPU1 显存',
    '第一块显卡显存占用',
    Icons.memory_rounded,
  );
  static const gpu1 = DashboardMetric(
    'gpu1',
    'GPU2 利用率',
    '第二块显卡使用率',
    Icons.hardware_rounded,
  );
  static const gpu1Memory = DashboardMetric(
    'gpu1Memory',
    'GPU2 显存',
    '第二块显卡显存占用',
    Icons.memory_rounded,
  );
  static const cpuFrequency = DashboardMetric(
    'cpuFrequency',
    'CPU 频率',
    '当前平均主频',
    Icons.timer_rounded,
  );
  static const totalTraffic = DashboardMetric(
    'totalTraffic',
    '总流量',
    '本次运行累计收发字节',
    Icons.data_usage_rounded,
  );

  /// 设置页与排序使用的固定顺序。
  static const List<DashboardMetric> all = [
    upload,
    download,
    network,
    cpu,
    memory,
    gpu0,
    gpu0Memory,
    gpu1,
    gpu1Memory,
    cpuFrequency,
    totalTraffic,
  ];

  static DashboardMetric? byId(String id) {
    for (final metric in all) {
      if (metric.id == id) return metric;
    }
    return null;
  }

  static final RegExp _gpuPattern = RegExp(r'^gpu(\d+)(Memory)?$');

  /// GPU 指标返回显卡序号，其他指标返回 null。
  int? get gpuIndex {
    final match = _gpuPattern.firstMatch(id);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  bool get isGpuMemory => id.endsWith('Memory');

  GpuSnapshot? _gpu(MetricsSnapshot? snapshot) {
    final index = gpuIndex;
    if (snapshot == null || index == null || index >= snapshot.gpus.length) {
      return null;
    }
    return snapshot.gpus[index];
  }

  /// 仪表盘卡片使用的主数值。
  String value(MetricsSnapshot? snapshot) {
    if (snapshot == null) return '—';
    if (gpuIndex != null) {
      final gpu = _gpu(snapshot);
      if (gpu == null) return '—';
      if (isGpuMemory) {
        return gpu.memoryTotalBytes > 0
            ? formatPercent(gpu.memoryPercent)
            : '—';
      }
      return formatPercent(gpu.utilizationPercent);
    }
    return switch (id) {
      'upload' => formatRate(snapshot.uploadBps),
      'download' => formatRate(snapshot.downloadBps),
      'network' => formatRate(snapshot.totalBps),
      'cpu' => formatPercent(snapshot.cpuPercent),
      'memory' => formatPercent(snapshot.memoryPercent),
      'cpuFrequency' => formatFrequency(snapshot.cpuMhz.toDouble()),
      'totalTraffic' => formatTraffic(snapshot.totalTrafficBytes.toDouble()),
      _ => '—',
    };
  }

  /// 收起态使用的最短形式。
  String compactValue(MetricsSnapshot? snapshot) {
    if (snapshot == null) return '—';
    if (gpuIndex != null) {
      final gpu = _gpu(snapshot);
      if (gpu == null) return '—';
      if (isGpuMemory) {
        return gpu.memoryTotalBytes > 0
            ? formatPercent(gpu.memoryPercent)
            : '—';
      }
      return formatPercent(gpu.utilizationPercent);
    }
    return switch (id) {
      'upload' => formatRate(snapshot.uploadBps, compact: true),
      'download' => formatRate(snapshot.downloadBps, compact: true),
      'network' => formatRate(snapshot.totalBps, compact: true),
      'cpu' => formatPercent(snapshot.cpuPercent),
      'memory' => formatPercent(snapshot.memoryPercent),
      'cpuFrequency' => formatFrequency(
        snapshot.cpuMhz.toDouble(),
        compact: true,
      ),
      'totalTraffic' => formatTraffic(
        snapshot.totalTrafficBytes.toDouble(),
        compact: true,
      ),
      _ => '—',
    };
  }

  /// 卡片与提示里的补充说明。
  String detail(MetricsSnapshot? snapshot) {
    if (snapshot == null) return '正在采样';
    if (gpuIndex != null) {
      final gpu = _gpu(snapshot);
      if (gpu == null) return '未检测到这块显卡';
      if (isGpuMemory) {
        return gpu.memoryTotalBytes > 0
            ? '${formatTraffic(gpu.memoryUsedBytes.toDouble())}'
                  ' / ${formatTraffic(gpu.memoryTotalBytes.toDouble())}'
            : '未检测到显存';
      }
      return '${gpu.name} · 1 秒刷新';
    }
    return switch (id) {
      'upload' || 'download' || 'network' =>
        '↑ ${formatTraffic(snapshot.totalUploadBytes.toDouble())}'
            ' · ↓ ${formatTraffic(snapshot.totalDownloadBytes.toDouble())}',
      'cpu' => '${formatPercent(snapshot.cpuPercent)} · 1 秒刷新',
      'memory' =>
        '${formatTraffic(snapshot.memoryUsedBytes.toDouble())}'
            ' / ${formatTraffic(snapshot.memoryTotalBytes.toDouble())}',
      'cpuFrequency' =>
        snapshot.cpuMaxMhz > 0
            ? '峰值 ${formatFrequency(snapshot.cpuMaxMhz.toDouble())}'
            : hint,
      'totalTraffic' =>
        '↑ ${formatTraffic(snapshot.totalUploadBytes.toDouble())}'
            ' · ↓ ${formatTraffic(snapshot.totalDownloadBytes.toDouble())}',
      _ => hint,
    };
  }

  Color tone(IslandColors colors, MetricsSnapshot? snapshot) {
    if (snapshot == null) return colors.muted;
    if (gpuIndex != null) {
      final gpu = _gpu(snapshot);
      if (gpu == null) return colors.muted;
      final percent = isGpuMemory ? gpu.memoryPercent : gpu.utilizationPercent;
      return percent >= 85 ? colors.warning : colors.accent;
    }
    return switch (id) {
      'cpu' => snapshot.cpuPercent >= 85 ? colors.warning : colors.accent,
      'memory' => snapshot.memoryPercent >= 85 ? colors.warning : colors.accent,
      'download' => colors.qq,
      'upload' || 'network' => colors.accent,
      'cpuFrequency' => colors.text,
      'totalTraffic' => colors.muted,
      _ => colors.muted,
    };
  }
}

String formatRate(double bytesPerSecond, {bool compact = false}) {
  final value = bytesPerSecond.isFinite && bytesPerSecond > 0
      ? bytesPerSecond
      : 0.0;
  final (scaled, unit) = _scaleBytes(value);
  final text = _scaledText(scaled);
  if (!compact) return '$text $unit/s';
  return '$text${unit[0]}';
}

String formatTraffic(double bytes, {bool compact = false}) {
  final value = bytes.isFinite && bytes > 0 ? bytes : 0.0;
  final (scaled, unit) = _scaleBytes(value);
  final text = _scaledText(scaled);
  return compact ? '$text${unit[0]}' : '$text $unit';
}

String formatPercent(double percent) =>
    '${(percent.isFinite ? percent : 0).round()}%';

String formatFrequency(double mhz, {bool compact = false}) {
  if (!mhz.isFinite || mhz <= 0) return '—';
  final ghz = mhz / 1000;
  return compact
      ? '${ghz.toStringAsFixed(1)}G'
      : '${ghz.toStringAsFixed(2)} GHz';
}

/// 返回缩放后的数值与完整单位（B / KB / MB / GB / TB）。
(double, String) _scaleBytes(double value) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var scaled = value;
  var index = 0;
  while (scaled >= 1024 && index < units.length - 1) {
    scaled /= 1024;
    index++;
  }
  return (scaled, units[index]);
}

/// 大于 100 时取整，否则保留一位小数并去掉多余的 `.0`。
String _scaledText(double value) {
  if (value >= 100) return value.round().toString();
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

double _double(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw?.toString() ?? '') ?? 0;
}

int _int(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}
