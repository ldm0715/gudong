import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';

/// 收起态常驻的输入法标识：中文高亮“中”，英文显示灰色“en”。
class ImeIndicator extends StatelessWidget {
  const ImeIndicator({super.key, required this.chinese});

  final bool chinese;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Container(
      width: 22,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: chinese ? colors.accent : colors.chip,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
      ),
      child: Text(
        chinese ? '中' : 'en',
        style: IslandTypography.micro.copyWith(
          color: chinese ? colors.background : colors.muted,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
