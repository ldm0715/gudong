import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../island/island_layout.dart';
import 'ime_chip.dart';

/// 输入法切换时的激活态横幅，尺寸与消息横幅一致。
class ImeBanner extends StatelessWidget {
  const ImeBanner({super.key, required this.chinese});

  final bool chinese;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return SizedBox(
      width: IslandLayout.bannerSize.width,
      height: IslandLayout.bannerSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.keyboard_rounded,
                size: 22,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '输入法已切换',
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
                    chinese ? '中文输入' : 'English 输入',
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
            ImeChip(chinese: chinese),
          ],
        ),
      ),
    );
  }
}
