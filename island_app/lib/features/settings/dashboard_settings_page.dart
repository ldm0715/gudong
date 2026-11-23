import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../dashboard/metrics_models.dart';
import 'settings_panel.dart';

/// 仪表盘设置：分别控制展开面板与收起态显示的指标。
class DashboardSettingsPage extends StatelessWidget {
  const DashboardSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  static List<String> _toggle(
    List<String> current,
    DashboardMetric metric,
    bool enabled,
  ) {
    final ids = current.toSet();
    if (enabled) {
      ids.add(metric.id);
    } else {
      ids.remove(metric.id);
    }
    return [
      for (final item in DashboardMetric.all)
        if (ids.contains(item.id)) item.id,
    ];
  }

  /// GPU 指标显示具体显卡型号；其他指标沿用说明文案。
  String _gpuName(DashboardMetric metric) {
    final index = metric.gpuIndex;
    if (index == null || index >= settings.gpuNames.length) return '';
    return settings.gpuNames[index];
  }

  String _dashboardSubtitle(DashboardMetric metric) {
    final name = _gpuName(metric);
    return name.isEmpty ? metric.hint : name;
  }

  String _islandSubtitle(DashboardMetric metric, bool islandFull) {
    final status = settings.islandMetrics.contains(metric.id)
        ? '收起态显示'
        : islandFull
        ? '最多显示 ${AppSettings.maxIslandMetrics} 个'
        : '收起态显示';
    final name = _gpuName(metric);
    return name.isEmpty ? status : '$name · $status';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final islandFull =
        settings.islandMetrics.length >= AppSettings.maxIslandMetrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('仪表盘'),
        SettingsCard(
          children: [
            for (
              var index = 0;
              index < DashboardMetric.all.length;
              index++
            ) ...[
              if (index > 0) const SettingsDivider(),
              SettingsSwitchRow(
                title: DashboardMetric.all[index].label,
                subtitle: _dashboardSubtitle(DashboardMetric.all[index]),
                leading: Icon(
                  DashboardMetric.all[index].icon,
                  size: 18,
                  color: colors.muted,
                ),
                value: settings.dashboardMetrics.contains(
                  DashboardMetric.all[index].id,
                ),
                onChanged: (value) => onSave(
                  settings.copyWith(
                    dashboardMetrics: _toggle(
                      settings.dashboardMetrics,
                      DashboardMetric.all[index],
                      value,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('灵动岛'),
        SettingsCard(
          children: [
            for (
              var index = 0;
              index < DashboardMetric.all.length;
              index++
            ) ...[
              if (index > 0) const SettingsDivider(),
              SettingsSwitchRow(
                title: DashboardMetric.all[index].label,
                subtitle: _islandSubtitle(
                  DashboardMetric.all[index],
                  islandFull,
                ),
                leading: Icon(
                  DashboardMetric.all[index].icon,
                  size: 18,
                  color: colors.muted,
                ),
                value: settings.islandMetrics.contains(
                  DashboardMetric.all[index].id,
                ),
                onChanged:
                    settings.islandMetrics.contains(
                          DashboardMetric.all[index].id,
                        ) ||
                        !islandFull
                    ? (value) => onSave(
                        settings.copyWith(
                          islandMetrics: _toggle(
                            settings.islandMetrics,
                            DashboardMetric.all[index],
                            value,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '指标由 sidecar 每秒采样一次；灵动岛最多显示 '
            '${AppSettings.maxIslandMetrics} 个指标，会按数量自动加宽。',
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
