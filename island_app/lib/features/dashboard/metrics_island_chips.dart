import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import 'metrics_controller.dart';
import 'metrics_models.dart';

/// 收起态指标条：图标 + 精简数值，尺寸由设置中的指标数量决定。
class MetricsIslandChips extends StatelessWidget {
  const MetricsIslandChips({
    super.key,
    required this.controller,
    required this.metricIds,
    this.vertical = false,
    this.iconSize = IslandMetrics.iconSM,
  });

  final MetricsController controller;
  final List<String> metricIds;
  final bool vertical;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final metrics = [for (final id in metricIds) ?DashboardMetric.byId(id)];
    if (metrics.isEmpty) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _build(context, metrics),
    );
  }

  Widget _build(BuildContext context, List<DashboardMetric> metrics) {
    final snapshot = controller.snapshot;
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final metric in metrics)
            Padding(
              padding: const EdgeInsets.only(top: IslandMetrics.space2),
              child: _Chip(
                metric: metric,
                snapshot: snapshot,
                iconSize: iconSize,
                vertical: true,
              ),
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final metric in metrics)
          Padding(
            padding: const EdgeInsets.only(right: IslandMetrics.space6),
            child: _Chip(
              metric: metric,
              snapshot: snapshot,
              iconSize: iconSize,
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.metric,
    required this.snapshot,
    required this.iconSize,
    this.vertical = false,
  });

  final DashboardMetric metric;
  final MetricsSnapshot? snapshot;
  final double iconSize;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final icon = Icon(metric.icon, size: iconSize, color: colors.muted);
    final value = Text(
      metric.compactValue(snapshot),
      maxLines: 1,
      style:
          (vertical
                  ? IslandTypography.microStrong
                  : IslandTypography.bodyStrong)
              .tint(metric.tone(colors, snapshot))
              .copyWith(fontFeatures: IslandTypography.tabularFigures),
    );
    return Tooltip(
      message: '${metric.label} ${metric.value(snapshot)}',
      waitDuration: IslandMotion.tooltipDelay,
      child: vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: IslandMetrics.space2),
                value,
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: IslandMetrics.space3),
                value,
              ],
            ),
    );
  }
}
