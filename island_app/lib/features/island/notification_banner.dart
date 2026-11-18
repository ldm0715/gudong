import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../messages/messages_controller.dart';
import 'client_glyph.dart';
import 'island_layout.dart';

/// 收起态出现的临时消息横幅，2 秒后回到收起态。
class NotificationBanner extends StatelessWidget {
  const NotificationBanner({super.key, required this.controller});

  final MessagesController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final item = controller.latestUnread;
    if (item == null) return const SizedBox.shrink();
    return SizedBox(
      width: IslandLayout.bannerSize.width,
      height: IslandLayout.bannerSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            ClientGlyph(source: item.source, size: 40),
            const SizedBox(width: 12),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _relativeTime(item.time),
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 16,
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

String _relativeTime(String time) {
  final parts = time.split(':');
  if (parts.length < 2) return time;
  final now = DateTime.now();
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == now.hour && minute == now.minute) return '刚刚';
  return '${parts[0]}:${parts[1]}';
}
