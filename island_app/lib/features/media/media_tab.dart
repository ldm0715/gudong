import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import 'media_controller.dart';

class MediaTab extends StatelessWidget {
  const MediaTab({super.key, required this.controller});

  final MediaController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    if (controller.available) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, size: 28, color: colors.accent),
            const SizedBox(height: 8),
            Text(
              controller.title ?? '未知曲目',
              style: TextStyle(
                color: colors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              controller.artist ?? '',
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_note_rounded, size: 28, color: colors.muted),
          const SizedBox(height: 8),
          Text(
            'SMTC 媒体未接入',
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Phase 2 接入媒体信息、进度与歌词',
            style: TextStyle(
              color: colors.muted,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 220,
            height: 3,
            decoration: BoxDecoration(
              color: colors.chip,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
