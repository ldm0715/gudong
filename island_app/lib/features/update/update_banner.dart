import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import '../island/island_layout.dart';

/// 自动检查发现新版本时在收起态出现的临时横幅。
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return SizedBox(
      width: IslandLayout.bannerSize.width,
      height: IslandLayout.bannerSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: IslandMetrics.space16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.new_releases_rounded,
                size: IslandMetrics.iconXL,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: IslandMetrics.space12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '发现新版本',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.micro.tint(colors.muted),
                  ),
                  const SizedBox(height: IslandMetrics.space3),
                  Text(
                    version,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.headline.tint(colors.text),
                  ),
                  const SizedBox(height: IslandMetrics.space2),
                  Text(
                    '当前 $appVersion · 在设置 → 关于中更新',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.body.tint(colors.muted),
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
