import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../island/client_glyph.dart';
import 'messages_controller.dart';

class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key, required this.controller});

  final MessagesController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final items = controller.unread;
    if (items.isEmpty) return const _EmptyMessages();
    return Column(
      children: [
        Row(
          children: [
            Text(
              '未读 ${controller.unreadCount}',
              style: IslandTypography.caption.tint(colors.muted),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
              onTap: controller.markAllSeen,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: IslandMetrics.space6,
                  vertical: IslandMetrics.space3,
                ),
                child: Text(
                  '全部已读',
                  style: IslandTypography.caption.tint(colors.accent),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: IslandMetrics.space2),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: colors.divider),
            itemBuilder: (context, index) {
              final item = items[index];
              return Tooltip(
                message: '打开${item.sourceName}',
                waitDuration: IslandMotion.tooltipDelay,
                child: InkWell(
                  onTap: () => controller.openMessage(item),
                  borderRadius: BorderRadius.circular(
                    IslandMetrics.radiusControl,
                  ),
                  child: SizedBox(
                    height: 54,
                    child: Row(
                      children: [
                        ClientGlyph(source: item.source, size: 20),
                        const SizedBox(width: IslandMetrics.space10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: IslandTypography.bodyStrong.tint(
                                  colors.text,
                                ),
                              ),
                              const SizedBox(height: IslandMetrics.space2),
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: IslandTypography.micro.tint(
                                  colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: IslandMetrics.space8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(
                            horizontal: IslandMetrics.space6,
                            vertical: IslandMetrics.space2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.chip,
                            borderRadius: BorderRadius.circular(
                              IslandMetrics.radiusPill,
                            ),
                          ),
                          child: Text(
                            '${item.count}',
                            textAlign: TextAlign.center,
                            style: IslandTypography.captionStrong.tint(
                              colors.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: IslandMetrics.space4),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: IslandMetrics.icon2XL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space8),
          Text('暂无新消息', style: IslandTypography.subhead.tint(colors.text)),
          const SizedBox(height: IslandMetrics.space4),
          Text(
            '微信 / QQ 有新消息时会出现在这里',
            style: IslandTypography.caption.tint(colors.muted),
          ),
        ],
      ),
    );
  }
}
