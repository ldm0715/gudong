import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';

/// 官方品牌图标；资源缺失时退回文字标记。
class QuotaProviderIcon extends StatelessWidget {
  const QuotaProviderIcon({
    super.key,
    required this.id,
    required this.fallback,
    required this.color,
    required this.size,
  });

  final String id;
  final String fallback;
  final Color color;
  final double size;

  static const Map<String, String> _assets = {
    'glm': 'assets/icons/zai.svg',
    'deepseek': 'assets/icons/deepseek.svg',
    'opencode': 'assets/icons/opencode.svg',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final asset = _assets[id];
    if (asset == null) return _fallback(colors);
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  Widget _fallback(IslandColors colors) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.chip,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusTag),
      ),
      child: Text(
        fallback,
        maxLines: 1,
        style: IslandTypography.microStrong.tint(color),
      ),
    );
  }
}
