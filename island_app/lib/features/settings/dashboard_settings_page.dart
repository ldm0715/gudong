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
      for (final item in DashboardMetric.values)
        if (ids.contains(item.id)) item.id,
    ];
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
              index < DashboardMetric.values.length;
              index++
            ) ...[
              if (index > 0) const SettingsDivider(),
              SettingsSwitchRow(
                title: DashboardMetric.values[index].label,
                subtitle: DashboardMetric.values[index].hint,
                leading: Icon(
                  DashboardMetric.values[index].icon,
                  size: 18,
                  color: colors.muted,
                ),
                value: settings.dashboardMetrics.contains(
                  DashboardMetric.values[index].id,
                ),
                onChanged: (value) => onSave(
                  settings.copyWith(
                    dashboardMetrics: _toggle(
                      settings.dashboardMetrics,
                      DashboardMetric.values[index],
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
              index < DashboardMetric.values.length;
              index++
            ) ...[
              if (index > 0) const SettingsDivider(),
              SettingsSwitchRow(
                title: DashboardMetric.values[index].label,
                subtitle:
                    settings.islandMetrics.contains(
                      DashboardMetric.values[index].id,
                    )
                    ? '收起态显示'
                    : islandFull
                    ? '最多显示 ${AppSettings.maxIslandMetrics} 个'
                    : '收起态显示',
                leading: Icon(
                  DashboardMetric.values[index].icon,
                  size: 18,
                  color: colors.muted,
                ),
                value: settings.islandMetrics.contains(
                  DashboardMetric.values[index].id,
                ),
                onChanged:
                    settings.islandMetrics.contains(
                          DashboardMetric.values[index].id,
                        ) ||
                        !islandFull
                    ? (value) => onSave(
                        settings.copyWith(
                          islandMetrics: _toggle(
                            settings.islandMetrics,
                            DashboardMetric.values[index],
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
