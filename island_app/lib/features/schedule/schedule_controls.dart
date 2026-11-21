import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';

/// 日程相关页面共用的输入框样式。
InputDecoration scheduleInputDecoration(IslandColors colors, String hint) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
    borderSide: BorderSide(color: colors.stroke),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: colors.surface,
    hintText: hint,
    hintStyle: IslandTypography.caption.tint(colors.muted),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: IslandMetrics.space8,
      vertical: IslandMetrics.space7,
    ),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
      borderSide: BorderSide(color: colors.accent),
    ),
  );
}

class SchedulePillButton extends StatelessWidget {
  const SchedulePillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final enabled = onTap != null;
    final background = primary
        ? (danger ? colors.warning : colors.accent)
        : colors.surface;
    final foreground = primary ? colors.background : colors.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: IslandMetrics.space10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
          border: primary ? null : Border.all(color: colors.stroke),
        ),
        child: Text(
          label,
          style: IslandTypography.captionStrong.tint(
            enabled ? foreground : foreground.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class ScheduleSmallIconButton extends StatelessWidget {
  const ScheduleSmallIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      waitDuration: IslandMotion.tooltipDelay,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
          hoverColor: colors.surface,
          highlightColor: colors.chip,
          child: Padding(
            padding: EdgeInsets.all(
              compact ? IslandMetrics.space4 : IslandMetrics.space6,
            ),
            child: Icon(
              icon,
              size: compact ? IslandMetrics.iconXS : IslandMetrics.iconSM,
              color: enabled
                  ? colors.muted
                  : colors.muted.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

class ScheduleConfirm {
  const ScheduleConfirm({
    required this.title,
    required this.detail,
    required this.confirmLabel,
    required this.onConfirm,
    this.danger = false,
  });

  final String title;
  final String detail;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final bool danger;
}

class ScheduleConfirmOverlay extends StatelessWidget {
  const ScheduleConfirmOverlay({
    super.key,
    required this.colors,
    required this.confirm,
    required this.onCancel,
  });

  final IslandColors colors;
  final ScheduleConfirm confirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: ColoredBox(color: colors.background.withValues(alpha: 0.72)),
          ),
        ),
        Center(
          child: Container(
            width: 260,
            padding: const EdgeInsets.all(IslandMetrics.space12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(IslandMetrics.radiusPanel),
              border: Border.all(color: colors.stroke),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  confirm.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: IslandTypography.subhead.tint(colors.text),
                ),
                const SizedBox(height: IslandMetrics.space4),
                Text(
                  confirm.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: IslandTypography.micro.tint(colors.muted),
                ),
                const SizedBox(height: IslandMetrics.space10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SchedulePillButton(label: '取消', onTap: onCancel),
                    const SizedBox(width: IslandMetrics.space6),
                    SchedulePillButton(
                      label: confirm.confirmLabel,
                      primary: true,
                      danger: confirm.danger,
                      onTap: confirm.onConfirm,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
