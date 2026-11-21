import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import '../island/island_layout.dart';
import 'schedule_models.dart';

/// 日程到点时在收起态出现的临时横幅。
class ScheduleBanner extends StatelessWidget {
  const ScheduleBanner({super.key, required this.item});

  final ScheduleItem item;

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
                Icons.alarm_rounded,
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
                    '日程提醒',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.micro.tint(colors.muted),
                  ),
                  const SizedBox(height: IslandMetrics.space3),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.headline.tint(colors.text),
                  ),
                  const SizedBox(height: IslandMetrics.space2),
                  Text(
                    '${formatScheduleDate(item.at)} '
                    '${formatScheduleTime(item.at)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.body.tint(colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: IslandMetrics.space12),
            Text(
              formatScheduleTime(item.at),
              style: IslandTypography.clock.tint(colors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
