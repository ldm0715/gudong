import 'package:flutter/material.dart';

import '../theme/island_colors.dart';
import '../theme/island_metrics.dart';
import '../theme/island_motion.dart';

/// 页面左右边缘的翻页热区，供天气页和日程页共用。
class PageEdgeButton extends StatelessWidget {
  const PageEdgeButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final color = enabled ? colors.muted : colors.muted.withValues(alpha: 0.25);
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        waitDuration: IslandMotion.tooltipDelay,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Center(
              child: Icon(icon, size: IslandMetrics.iconSM, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
