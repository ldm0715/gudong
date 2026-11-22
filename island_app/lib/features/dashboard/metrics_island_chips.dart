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
  });

  final MetricsController controller;
  final List<String> metricIds;
  final bool vertical;

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
              child: _Chip(metric: metric, snapshot: snapshot),
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
            child: _Chip(metric: metric, snapshot: snapshot),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.metric, required this.snapshot});

  final DashboardMetric metric;
  final MetricsSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Tooltip(
      message: '${metric.label} ${metric.value(snapshot)}',
      waitDuration: IslandMotion.tooltipDelay,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(metric.icon, size: IslandMetrics.iconSM, color: colors.muted),
          const SizedBox(width: IslandMetrics.space3),
          Text(
            metric.compactValue(snapshot),
            maxLines: 1,
            style: IslandTypography.bodyStrong
                .tint(metric.tone(colors, snapshot))
                .copyWith(fontFeatures: IslandTypography.tabularFigures),
          ),
        ],
      ),
    );
  }
}
