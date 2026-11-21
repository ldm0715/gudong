import 'package:flutter/material.dart';

import '../theme/island_colors.dart';
import '../theme/island_metrics.dart';
import '../theme/island_typography.dart';

/// 文本选择右键菜单。
///
/// Flutter 桌面端默认菜单固定 222px 宽，短标签会留下大片空白；这里按内容
/// 自适应宽度并套用岛体主题。用于 [SelectionArea] 或 [SelectableText] 的
/// `contextMenuBuilder`。
class IslandSelectionToolbar extends StatelessWidget {
  const IslandSelectionToolbar({
    super.key,
    required this.anchors,
    required this.items,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> items;

  static const double _screenPadding = 8;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = context.islandColors;
    final paddingAbove = MediaQuery.paddingOf(context).top + _screenPadding;
    final localAdjustment = Offset(_screenPadding, paddingAbove);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _screenPadding,
        paddingAbove,
        _screenPadding,
        _screenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: DesktopTextSelectionToolbarLayoutDelegate(
          anchor: anchors.primaryAnchor - localAdjustment,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(IslandMetrics.radiusPanel),
            border: Border.all(color: colors.stroke),
          ),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  _ToolbarEntry(
                    label: _labelFor(item.type),
                    onTap: item.onPressed,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _labelFor(ContextMenuButtonType type) => switch (type) {
    ContextMenuButtonType.copy => '复制',
    ContextMenuButtonType.selectAll => '全选',
    ContextMenuButtonType.cut => '剪切',
    ContextMenuButtonType.paste => '粘贴',
    ContextMenuButtonType.delete => '删除',
    ContextMenuButtonType.share => '分享',
    ContextMenuButtonType.lookUp => '查询',
    ContextMenuButtonType.searchWeb => '网页搜索',
    ContextMenuButtonType.liveTextInput => '听写',
    ContextMenuButtonType.custom => '操作',
  };
}

class _ToolbarEntry extends StatefulWidget {
  const _ToolbarEntry({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_ToolbarEntry> createState() => _ToolbarEntryState();
}

class _ToolbarEntryState extends State<_ToolbarEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            color: _hovered
                ? colors.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(
              horizontal: IslandMetrics.space12,
              vertical: IslandMetrics.space6,
            ),
            child: Text(
              widget.label,
              style: IslandTypography.caption.tint(
                _hovered ? colors.accent : colors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
