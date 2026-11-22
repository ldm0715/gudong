import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../island/island_layout.dart';
import 'volume_controller.dart';

/// 系统音量变化时的横幅：显示百分比并允许拖动调整。
class VolumeBanner extends StatelessWidget {
  const VolumeBanner({super.key, required this.controller});

  final VolumeController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final volume = controller.volume.clamp(0.0, 1.0);
    final muted = controller.muted || volume <= 0.001;
    final icon = muted
        ? Icons.volume_off_rounded
        : volume < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;
    return SizedBox(
      width: IslandLayout.bannerSize.width,
      height: IslandLayout.bannerSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: IslandMetrics.space16),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: controller.muted ? '取消静音' : '静音',
              child: Tooltip(
                message: controller.muted ? '取消静音' : '静音',
                waitDuration: IslandMotion.tooltipDelay,
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    IslandMetrics.radiusPanel,
                  ),
                  onTap: controller.toggleMute,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(
                        IslandMetrics.radiusPanel,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: IslandMetrics.iconXL,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: IslandMetrics.space12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '音量',
                        style: IslandTypography.subhead.tint(colors.muted),
                      ),
                      const Spacer(),
                      Text(
                        controller.muted ? '静音' : '${(volume * 100).round()}%',
                        style: IslandTypography.subhead.tint(
                          controller.muted ? colors.muted : colors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: IslandMetrics.space8),
                  _VolumeSlider(
                    value: volume,
                    muted: controller.muted,
                    onChanged: controller.setVolume,
                    onPreview: () => unawaited(controller.preview()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.value,
    required this.muted,
    required this.onChanged,
    required this.onPreview,
  });

  final double value;
  final bool muted;
  final ValueChanged<double> onChanged;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    const knob = 10.0;
    return Semantics(
      slider: true,
      label: '音量',
      value: '${(value * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double valueAt(Offset position) =>
              (position.dx / width).clamp(0.0, 1.0);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => onChanged(valueAt(details.localPosition)),
            onTapUp: (_) => onPreview(),
            onHorizontalDragStart: (details) =>
                onChanged(valueAt(details.localPosition)),
            onHorizontalDragUpdate: (details) =>
                onChanged(valueAt(details.localPosition)),
            onHorizontalDragEnd: (_) => onPreview(),
            child: SizedBox(
              width: width,
              height: IslandMetrics.hitTargetMin,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.switchOff,
                      borderRadius: BorderRadius.circular(
                        IslandMetrics.radiusBar,
                      ),
                    ),
                  ),
                  Container(
                    width: width * value,
                    height: 4,
                    decoration: BoxDecoration(
                      color: muted
                          ? colors.muted.withValues(alpha: 0.5)
                          : colors.accent,
                      borderRadius: BorderRadius.circular(
                        IslandMetrics.radiusBar,
                      ),
                    ),
                  ),
                  Positioned(
                    left: (width * value - knob / 2).clamp(0.0, width - knob),
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: BoxDecoration(
                        color: muted ? colors.muted : colors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.background,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
