import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import '../island/island_layout.dart';
import 'mail_controller.dart';
import 'mail_models.dart';
import 'mail_provider_badge.dart';

/// 收到新邮件时在收起态出现的临时横幅。
class MailBanner extends StatelessWidget {
  const MailBanner({
    super.key,
    required this.controller,
    required this.item,
  });

  final MailController controller;
  final MailSummary item;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final account = controller.accountFor(item.accountId);
    final accountLabel = account?.displayName ?? '邮箱';
    return SizedBox(
      width: IslandLayout.bannerSize.width,
      height: IslandLayout.bannerSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: IslandMetrics.space16),
        child: Row(
          children: [
            MailProviderBadge(
              provider: account?.provider ?? 'custom',
              email: account?.email,
              size: 40,
              color: colors.accent,
            ),
            const SizedBox(width: IslandMetrics.space12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '新邮件 · $accountLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.micro.tint(colors.muted),
                  ),
                  const SizedBox(height: IslandMetrics.space3),
                  Text(
                    item.from,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.headline.tint(colors.text),
                  ),
                  const SizedBox(height: IslandMetrics.space2),
                  Text(
                    item.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.body.tint(colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: IslandMetrics.space12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.timeLabel,
                  style: IslandTypography.caption.tint(colors.muted),
                ),
                const SizedBox(height: IslandMetrics.space4),
                Icon(
                  Icons.mark_email_unread_outlined,
                  size: IslandMetrics.iconMD,
                  color: colors.muted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
