import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/log.dart';
import '../../core/theme/island_colors.dart';
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
          padding: const EdgeInsets.only(top: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _openLogDir,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(
                  '打开日志目录',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          style: TextStyle(color: colors.text, fontSize: 12),
          cursorColor: colors.accent,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: colors.divider,
            hintText: '输入法测试：用微软拼音或搜狗输入中文',
            hintStyle: TextStyle(color: colors.muted, fontSize: 11),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colors.text,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
