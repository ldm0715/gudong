import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/log.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import '../weather/weather_controller.dart';
import 'diagnostics_controller.dart';

class DiagnosticsTab extends StatelessWidget {
  const DiagnosticsTab({
    super.key,
    required this.connectionDetail,
    required this.diagnostics,
    required this.weather,
  });

  final String connectionDetail;
  final DiagnosticsController diagnostics;
  final WeatherController weather;

  void _openLogDir() {
    final dir = AppLog.logDir;
    if (dir == null) return;
    try {
      unawaited(Process.start('explorer.exe', [dir]));
    } catch (error) {
      AppLog.write('[diagnostics] open log dir failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _DiagRow(label: '客户端', value: appVersion),
        _DiagRow(label: 'sidecar', value: connectionDetail),
        _DiagRow(label: '微信监听', value: diagnostics.wechatStatus),
        _DiagRow(label: '系统通知', value: diagnostics.notificationsStatus),
        _DiagRow(label: '天气', value: weather.status),
        _DiagRow(label: '日志', value: AppLog.logDir ?? '不可用'),
        const _DiagRow(label: '快捷键', value: 'Ctrl + Alt + Space 展开 / 收起'),
        const _DiagRow(label: '点击穿透', value: '岛体外点击直达下层窗口'),
        Padding(
          padding: const EdgeInsets.only(top: IslandMetrics.space2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
              onTap: _openLogDir,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: IslandMetrics.space6,
                  vertical: IslandMetrics.space3,
                ),
                child: Text(
                  '打开日志目录',
                  style: IslandTypography.caption.tint(colors.accent),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: IslandMetrics.space8),
        TextField(
          style: IslandTypography.body.tint(colors.text),
          cursorColor: colors.accent,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: colors.divider,
            hintText: '输入法测试：用微软拼音或搜狗输入中文',
            hintStyle: IslandTypography.caption.tint(colors.muted),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: IslandMetrics.space10,
              vertical: IslandMetrics.space10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(IslandMetrics.radiusPill),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IslandMetrics.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: IslandTypography.caption.tint(colors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: IslandTypography.caption.tint(colors.text),
            ),
          ),
        ],
      ),
    );
  }
}
