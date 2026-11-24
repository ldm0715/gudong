import 'package:flutter/material.dart';

import '../theme/island_colors.dart';
import '../theme/island_metrics.dart';

/// 叠放的一组方形图标：第一个位于最左（竖向为最上）并完整可见，
/// 后续图标依次向右（向下）偏移并被压住，用背景色描边区分层次。
///
/// 只适合可重复、同类的图标（如多个 agent），不要用于品牌标识或数值。
class GlyphStack extends StatelessWidget {
  const GlyphStack({
    super.key,
    required this.children,
    required this.semanticsLabel,
    this.size = IslandMetrics.iconLG,
    this.overlap = IslandMetrics.stackOverlap,
    this.vertical = false,
  });

  final List<Widget> children;
  final String semanticsLabel;
  final double size;
  final double overlap;
  final bool vertical;

  /// 叠放 [count] 个图标占用的总边长。
  static double extent(
    int count, {
    double size = IslandMetrics.iconLG,
    double overlap = IslandMetrics.stackOverlap,
  }) {
    if (count <= 0) return 0;
    return size + (count - 1) * (size - overlap);
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final colors = context.islandColors;
    final step = size - overlap;
    final length = size + (children.length - 1) * step;
    final radius = size * 0.28;
    final ring = IslandMetrics.stackRing;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: vertical ? size : length,
        height: vertical ? length : size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 逆序绘制：第一个图标最后画，保持完整可见。
            for (var index = children.length - 1; index >= 0; index--)
              Positioned(
                left: vertical ? 0 : index * step,
                top: vertical ? index * step : 0,
                width: size,
                height: size,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  // 前景描边画在图标之上，压住被遮挡图标的一圈边缘。
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: colors.background, width: ring),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: children[index],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
