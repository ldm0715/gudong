import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
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
              style: TextStyle(
                color: colors.muted,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: controller.markAllSeen,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(
                  '全部已读',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
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
                waitDuration: const Duration(milliseconds: 600),
                child: InkWell(
                  onTap: () => controller.openMessage(item),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 54,
                    child: Row(
                      children: [
                        ClientGlyph(source: item.source, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 10,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.chip,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.count}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
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
            size: 26,
            color: colors.muted,
          ),
          const SizedBox(height: 8),
          Text(
            '暂无新消息',
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '微信 / QQ 有新消息时会出现在这里',
            style: TextStyle(
              color: colors.muted,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
