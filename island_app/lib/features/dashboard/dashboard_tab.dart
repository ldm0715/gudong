import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import 'metrics_controller.dart';
import 'metrics_models.dart';

/// 展开态实时仪表盘：按设置在 3 列卡片中显示所选指标。
class DashboardTab extends StatelessWidget {
  const DashboardTab({
    super.key,
    required this.controller,
    required this.settings,
  });

  final MetricsController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final metrics = [
      for (final id in settings.dashboardMetrics) ?DashboardMetric.byId(id),
    ];
    if (metrics.isEmpty) return _EmptyDashboard(colors: colors);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: IslandMetrics.space6,
            crossAxisSpacing: IslandMetrics.space6,
            childAspectRatio: 2.15,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) =>
              _MetricCard(metric: metrics[index], snapshot: snapshot),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.snapshot});

  final DashboardMetric metric;
  final MetricsSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final tone = metric.tone(colors, snapshot);
    final value = metric.value(snapshot);
    return Tooltip(
      message: '${metric.label}\n${metric.detail(snapshot)}',
      waitDuration: IslandMotion.tooltipDelay,
      child: Semantics(
        label: '${metric.label} $value',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: IslandMetrics.space8,
            vertical: IslandMetrics.space6,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    metric.icon,
                    size: IslandMetrics.iconXS,
                    color: colors.muted,
                  ),
                  const SizedBox(width: IslandMetrics.space4),
                  Expanded(
                    child: Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.micro.tint(colors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: IslandMetrics.space4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: IslandTypography.title
                      .tint(tone)
                      .copyWith(fontFeatures: IslandTypography.tabularFigures),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard({required this.colors});

  final IslandColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.speed_outlined,
            size: IslandMetrics.icon2XL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space8),
          Text('未启用指标', style: IslandTypography.subhead.tint(colors.text)),
          const SizedBox(height: IslandMetrics.space4),
          Text(
            '在设置 → 仪表盘中开启',
            style: IslandTypography.caption.tint(colors.muted),
          ),
        ],
      ),
    );
  }
}
