import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import 'agent_models.dart';

/// agent 品牌图标；资源缺失时退回首字母色块。
class AgentGlyph extends StatelessWidget {
  const AgentGlyph({super.key, required this.id, this.size = 18});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final info = AgentCatalog.byId(id);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.chip,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        (info?.label.isNotEmpty ?? false) ? info!.label.substring(0, 1) : '?',
        style: TextStyle(
          color: colors.text,
          fontSize: size * 0.55,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
    if (info == null) return fallback;
    final cache = (size * 3).round();
    return Image.asset(
      info.asset,
      width: size,
      height: size,
      cacheWidth: cache,
      cacheHeight: cache,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
