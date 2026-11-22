import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';

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
    required this.totalUploadBytes,
    required this.totalDownloadBytes,
    required this.updatedAtMs,
  });

  factory MetricsSnapshot.fromJson(Map<String, dynamic> json) {
    return MetricsSnapshot(
      uploadBps: _double(json['uploadBps']),
      downloadBps: _double(json['downloadBps']),
      cpuPercent: _double(json['cpuPercent']),
      memoryPercent: _double(json['memoryPercent']),
      memoryUsedBytes: _int(json['memoryUsedBytes']),
      memoryTotalBytes: _int(json['memoryTotalBytes']),
      cpuMhz: _int(json['cpuMhz']),
      cpuMaxMhz: _int(json['cpuMaxMhz']),
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
  final int totalUploadBytes;
  final int totalDownloadBytes;
  final int updatedAtMs;

  double get totalBps => uploadBps + downloadBps;

  int get totalTrafficBytes => totalUploadBytes + totalDownloadBytes;
}

/// 仪表盘可显示的指标。id 同时用于 `dashboardMetrics` / `islandMetrics`。
enum DashboardMetric {
  upload('upload', '上传', '实时上传速率', Icons.upload_rounded),
  download('download', '下载', '实时下载速率', Icons.download_rounded),
  network('network', '总网速', '上传与下载速率之和', Icons.swap_vert_rounded),
  cpu('cpu', 'CPU 利用率', '系统总 CPU 占用率', Icons.memory_rounded),
  memory('memory', '内存利用率', '物理内存占用率', Icons.developer_board_rounded),
  cpuFrequency('cpuFrequency', 'CPU 频率', '当前平均主频', Icons.speed_rounded),
  totalTraffic('totalTraffic', '总流量', '本次运行累计收发字节', Icons.data_usage_rounded);

  const DashboardMetric(this.id, this.label, this.hint, this.icon);

  final String id;
  final String label;
  final String hint;
  final IconData icon;

  static DashboardMetric? byId(String id) {
    for (final metric in values) {
      if (metric.id == id) return metric;
    }
    return null;
  }

  /// 仪表盘卡片使用的主数值。
  String value(MetricsSnapshot? snapshot) {
    if (snapshot == null) return '—';
    return switch (this) {
      upload => formatRate(snapshot.uploadBps),
      download => formatRate(snapshot.downloadBps),
      network => formatRate(snapshot.totalBps),
      cpu => formatPercent(snapshot.cpuPercent),
      memory => formatPercent(snapshot.memoryPercent),
      cpuFrequency => formatFrequency(snapshot.cpuMhz.toDouble()),
      totalTraffic => formatTraffic(snapshot.totalTrafficBytes.toDouble()),
    };
  }

  /// 收起态使用的最短形式。
  String compactValue(MetricsSnapshot? snapshot) {
    if (snapshot == null) return '—';
    return switch (this) {
      upload => formatRate(snapshot.uploadBps, compact: true),
      download => formatRate(snapshot.downloadBps, compact: true),
      network => formatRate(snapshot.totalBps, compact: true),
      cpu => formatPercent(snapshot.cpuPercent),
      memory => formatPercent(snapshot.memoryPercent),
      cpuFrequency => formatFrequency(
        snapshot.cpuMhz.toDouble(),
        compact: true,
      ),
      totalTraffic => formatTraffic(
        snapshot.totalTrafficBytes.toDouble(),
        compact: true,
      ),
    };
  }

  /// 卡片与提示里的补充说明。
  String detail(MetricsSnapshot? snapshot) {
    if (snapshot == null) return '正在采样';
    return switch (this) {
      upload || download || network =>
        '↑ ${formatTraffic(snapshot.totalUploadBytes.toDouble())}'
            ' · ↓ ${formatTraffic(snapshot.totalDownloadBytes.toDouble())}',
      cpu => '${formatPercent(snapshot.cpuPercent)} · 1 秒刷新',
      memory =>
        '${formatTraffic(snapshot.memoryUsedBytes.toDouble())}'
            ' / ${formatTraffic(snapshot.memoryTotalBytes.toDouble())}',
      cpuFrequency =>
        snapshot.cpuMaxMhz > 0
            ? '最大 ${formatFrequency(snapshot.cpuMaxMhz.toDouble())}'
            : hint,
      totalTraffic =>
        '↑ ${formatTraffic(snapshot.totalUploadBytes.toDouble())}'
            ' · ↓ ${formatTraffic(snapshot.totalDownloadBytes.toDouble())}',
    };
  }

  Color tone(IslandColors colors, MetricsSnapshot? snapshot) {
    if (snapshot == null) return colors.muted;
    return switch (this) {
      cpu => snapshot.cpuPercent >= 85 ? colors.warning : colors.accent,
      memory => snapshot.memoryPercent >= 85 ? colors.warning : colors.accent,
      download => colors.qq,
      upload || network => colors.accent,
      cpuFrequency => colors.text,
      totalTraffic => colors.muted,
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
