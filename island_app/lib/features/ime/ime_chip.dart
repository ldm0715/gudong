import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';

/// 输入法横幅里的中英文切换标识：两个分段同时显示，当前模式高亮。
class ImeChip extends StatelessWidget {
  const ImeChip({super.key, required this.chinese});

  final bool chinese;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(label: '中', active: chinese),
          _Segment(label: 'en', active: !chinese),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 40,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? colors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? colors.background : colors.muted,
          fontSize: label == 'en' ? 13 : 15,
          fontWeight: FontWeight.w700,
          height: 1,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
