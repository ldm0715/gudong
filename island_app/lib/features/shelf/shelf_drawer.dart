import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../../core/window/dock_edge.dart';
import 'shelf_controller.dart';
import 'shelf_models.dart';

/// 拖出交给 Flutter 的 Windows runner，在平台线程调用 SHDoDragDrop，
/// 由 shell 使用文件原始图标生成拖拽影子。
const MethodChannel _dragChannel = MethodChannel('guduo/drag');

/// 从岛体停靠边缘滑出的中转站抽屉。
class ShelfDrawer extends StatelessWidget {
  const ShelfDrawer({
    super.key,
    required this.controller,
    required this.settings,
    required this.side,
    required this.onClose,
  });

  final ShelfController controller;
  final SettingsController settings;
  final DockEdge side;
  final VoidCallback onClose;

  bool get _grid => settings.settings.shelfViewMode == 'grid';

  void _toggleView() {
    unawaited(
      settings.save(
        settings.settings.copyWith(shelfViewMode: _grid ? 'list' : 'grid'),
      ),
    );
  }

  VoidCallback _tapAction(ShelfItem item) {
    if (controller.selecting || HardwareKeyboard.instance.isControlPressed) {
      return () => controller.toggleSelected(item.id);
    }
    return () => controller.reveal(item);
  }

  List<String> _dragPaths(ShelfItem item) {
    if (controller.isSelected(item.id) && controller.selected.isNotEmpty) {
      final paths = controller.selectedItems
          .where((value) => !value.missing)
          .map((value) => value.path)
          .toList(growable: false);
      if (paths.isNotEmpty) return paths;
    }
    return [item.path];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return AnimatedBuilder(
      animation: Listenable.merge([controller, settings]),
      builder: (context, _) {
        final items = controller.items;
        final grid = _grid;
        final selecting = controller.selecting;
        final selectedCount = controller.selected.length;
        return Material(
          color: colors.background,
          child: Stack(
            children: [
              Column(
                children: [
                  _Header(
                    colors: colors,
                    count: items.length,
                    selectedCount: selectedCount,
                    selecting: selecting,
                    side: side,
                    grid: grid,
                    onToggleSelecting: controller.toggleSelecting,
                    onRemoveSelected: () =>
                        unawaited(controller.removeSelected()),
                    onToggleView: _toggleView,
                    onClear: items.isEmpty ? null : controller.clear,
                    onClose: onClose,
                  ),
                  if (controller.notice != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        IslandMetrics.space12,
                        0,
                        IslandMetrics.space12,
                        IslandMetrics.space6,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          controller.notice!,
                          style: IslandTypography.micro.tint(colors.accent),
                        ),
                      ),
                    ),
                  Expanded(
                    child: items.isEmpty
                        ? _Empty(
                            colors: colors,
                            dragging: controller.dragActive,
                          )
                        : AnimatedSwitcher(
                            duration: IslandMotion.fast,
                            child: grid
                                ? _GridView(
                                    key: const ValueKey('grid'),
                                    items: items,
                                    controller: controller,
                                    colors: colors,
                                    selecting: selecting,
                                    dragPaths: _dragPaths,
                                    tapAction: _tapAction,
                                  )
                                : _ListView(
                                    key: const ValueKey('list'),
                                    items: items,
                                    controller: controller,
                                    colors: colors,
                                    selecting: selecting,
                                    dragPaths: _dragPaths,
                                    tapAction: _tapAction,
                                  ),
                          ),
                  ),
                ],
              ),
              // 放下时整块面板闪一下，给“落进去了”的反馈。
              if (controller.dropRevision > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(controller.dropRevision),
                      tween: Tween(begin: 0.22, end: 0.0),
                      duration: const Duration(milliseconds: 480),
                      curve: IslandMotion.standard,
                      builder: (context, value, child) => ColoredBox(
                        color: colors.accent.withValues(alpha: value),
                      ),
                    ),
                  ),
                ),
              if (controller.dragActive)
                const Positioned.fill(child: IgnorePointer(child: _DropHint())),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.count,
    required this.selectedCount,
    required this.selecting,
    required this.side,
    required this.grid,
    required this.onToggleSelecting,
    required this.onRemoveSelected,
    required this.onToggleView,
    required this.onClear,
    required this.onClose,
  });

  final IslandColors colors;
  final int count;
  final int selectedCount;
  final bool selecting;
  final DockEdge side;
  final bool grid;
  final VoidCallback onToggleSelecting;
  final VoidCallback onRemoveSelected;
  final VoidCallback onToggleView;
  final Future<int> Function()? onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IslandMetrics.space12,
          vertical: IslandMetrics.space6,
        ),
        child: Row(
          children: [
            Icon(
              Icons.inbox_rounded,
              size: IslandMetrics.iconSM,
              color: colors.accent,
            ),
            const SizedBox(width: IslandMetrics.space6),
            Text('中转站', style: IslandTypography.bodyStrong.tint(colors.text)),
            const SizedBox(width: IslandMetrics.space6),
            Text(
              selecting ? '已选 $selectedCount' : '$count',
              style: IslandTypography.micro.tint(
                selecting && selectedCount > 0 ? colors.accent : colors.muted,
              ),
            ),
            const Spacer(),
            if (selecting) ...[
              _IconButton(
                icon: Icons.delete_outline_rounded,
                colors: colors,
                tooltip: '删除选中项',
                onTap: onRemoveSelected,
              ),
              _IconButton(
                icon: Icons.deselect_rounded,
                colors: colors,
                tooltip: '取消多选',
                onTap: onToggleSelecting,
              ),
            ] else
              _IconButton(
                icon: Icons.checklist_rounded,
                colors: colors,
                tooltip: '多选',
                onTap: onToggleSelecting,
              ),
            _IconButton(
              icon: grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              colors: colors,
              tooltip: grid ? '切换到列表视图' : '切换到图标视图',
              onTap: onToggleView,
            ),
            if (!selecting && onClear != null)
              _IconButton(
                icon: Icons.delete_sweep_outlined,
                colors: colors,
                tooltip: '清空中转站',
                onTap: () => onClear!(),
              ),
            _IconButton(
              icon: side == DockEdge.top
                  ? Icons.keyboard_arrow_up_rounded
                  : side == DockEdge.left
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              colors: colors,
              tooltip: '收起中转站',
              onTap: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({
    super.key,
    required this.items,
    required this.controller,
    required this.colors,
    required this.selecting,
    required this.dragPaths,
    required this.tapAction,
  });

  final List<ShelfItem> items;
  final ShelfController controller;
  final IslandColors colors;
  final bool selecting;
  final List<String> Function(ShelfItem item) dragPaths;
  final VoidCallback Function(ShelfItem item) tapAction;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        IslandMetrics.space8,
        0,
        IslandMetrics.space8,
        IslandMetrics.space8,
      ),
      itemExtent: 46,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ShelfListTile(
          key: ValueKey(item.id),
          item: item,
          colors: colors,
          icon: controller.iconFor(item),
          selecting: selecting,
          selected: controller.isSelected(item.id),
          removing: controller.isRemoving(item.id),
          dragPaths: dragPaths(item),
          onTap: tapAction(item),
          onRemove: () => controller.remove(item.id),
        );
      },
    );
  }
}

class _GridView extends StatelessWidget {
  const _GridView({
    super.key,
    required this.items,
    required this.controller,
    required this.colors,
    required this.selecting,
    required this.dragPaths,
    required this.tapAction,
  });

  final List<ShelfItem> items;
  final ShelfController controller;
  final IslandColors colors;
  final bool selecting;
  final List<String> Function(ShelfItem item) dragPaths;
  final VoidCallback Function(ShelfItem item) tapAction;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        IslandMetrics.space8,
        IslandMetrics.space2,
        IslandMetrics.space8,
        IslandMetrics.space8,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: IslandMetrics.space6,
        mainAxisSpacing: IslandMetrics.space6,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ShelfGridTile(
          key: ValueKey(item.id),
          item: item,
          colors: colors,
          icon: controller.iconFor(item),
          selecting: selecting,
          selected: controller.isSelected(item.id),
          removing: controller.isRemoving(item.id),
          dragPaths: dragPaths(item),
          onTap: tapAction(item),
          onRemove: () => controller.remove(item.id),
        );
      },
    );
  }
}

/// 列表行：缩略图 + 名称 + 大小。
class _ShelfListTile extends StatelessWidget {
  const _ShelfListTile({
    super.key,
    required this.item,
    required this.colors,
    required this.icon,
    required this.selecting,
    required this.selected,
    required this.removing,
    required this.dragPaths,
    required this.onTap,
    required this.onRemove,
  });

  final ShelfItem item;
  final IslandColors colors;
  final Uint8List? icon;
  final bool selecting;
  final bool selected;
  final bool removing;
  final List<String> dragPaths;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final muted = item.missing;
    final content = _ShelfDragSurface(
      item: item,
      selected: selected,
      dragPaths: dragPaths,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IslandMetrics.space4,
          vertical: IslandMetrics.space3,
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
                onTap: muted && !selecting ? null : onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IslandMetrics.space4,
                    vertical: IslandMetrics.space2,
                  ),
                  child: Row(
                    children: [
                      _withSelectionBadge(
                        _ShelfLeading(
                          item: item,
                          colors: colors,
                          icon: icon,
                          size: 28,
                        ),
                        selected,
                        colors,
                      ),
                      const SizedBox(width: IslandMetrics.space8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: IslandTypography.body.tint(
                                muted ? colors.muted : colors.text,
                              ),
                            ),
                            Text(
                              item.missing ? '文件已失效' : item.sizeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: IslandTypography.micro.tint(colors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!selecting)
              _IconButton(
                icon: Icons.close_rounded,
                colors: colors,
                size: IslandMetrics.iconXS,
                tooltip: '从中转站移除',
                onTap: onRemove,
              ),
          ],
        ),
      ),
    );
    return _removalAnimation(content, removing);
  }
}

/// 图标网格单元：大图标 + 名称。
class _ShelfGridTile extends StatelessWidget {
  const _ShelfGridTile({
    super.key,
    required this.item,
    required this.colors,
    required this.icon,
    required this.selecting,
    required this.selected,
    required this.removing,
    required this.dragPaths,
    required this.onTap,
    required this.onRemove,
  });

  final ShelfItem item;
  final IslandColors colors;
  final Uint8List? icon;
  final bool selecting;
  final bool selected;
  final bool removing;
  final List<String> dragPaths;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final muted = item.missing;
    final content = _ShelfDragSurface(
      item: item,
      selected: selected,
      dragPaths: dragPaths,
      borderRadius: IslandMetrics.radiusControl,
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
              onTap: muted && !selecting ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  IslandMetrics.space4,
                  IslandMetrics.space6,
                  IslandMetrics.space4,
                  IslandMetrics.space4,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _withSelectionBadge(
                      _ShelfLeading(
                        item: item,
                        colors: colors,
                        icon: icon,
                        size: 40,
                      ),
                      selected,
                      colors,
                    ),
                    const SizedBox(height: IslandMetrics.space4),
                    Text(
                      item.name,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.micro.tint(
                        muted ? colors.muted : colors.text,
                      ),
                    ),
                    Text(
                      item.missing ? '已失效' : item.sizeLabel,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.micro.tint(colors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!selecting)
            Positioned(
              top: 0,
              right: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(IslandMetrics.radiusTag),
                onTap: onRemove,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Icon(
                    Icons.close_rounded,
                    size: 11,
                    color: colors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return _removalAnimation(content, removing);
  }
}

Widget _removalAnimation(Widget child, bool removing) {
  return AnimatedOpacity(
    opacity: removing ? 0 : 1,
    duration: const Duration(milliseconds: 160),
    child: AnimatedScale(
      scale: removing ? 0.9 : 1,
      duration: const Duration(milliseconds: 160),
      child: child,
    ),
  );
}

Widget _withSelectionBadge(Widget child, bool selected, IslandColors colors) {
  if (!selected) return child;
  return Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      Positioned(
        right: -4,
        bottom: -4,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded, size: 10, color: colors.background),
        ),
      ),
    ],
  );
}

/// 共用的按压 / 多选拖出手势与浮起动画。
class _ShelfDragSurface extends StatefulWidget {
  const _ShelfDragSurface({
    required this.item,
    required this.child,
    required this.selected,
    required this.dragPaths,
    this.borderRadius = IslandMetrics.radiusChip,
  });

  final ShelfItem item;
  final Widget child;
  final bool selected;
  final List<String> dragPaths;
  final double borderRadius;

  @override
  State<_ShelfDragSurface> createState() => _ShelfDragSurfaceState();
}

class _ShelfDragSurfaceState extends State<_ShelfDragSurface> {
  static const double _dragThreshold = 6;

  int? _pointer;
  Offset? _start;
  bool _pressed = false;
  bool _dragging = false;
  bool _hovered = false;

  void _onPointerDown(PointerDownEvent event) {
    if (widget.item.missing) return;
    _pointer = event.pointer;
    _start = event.position;
    _pressed = true;
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragging || _pointer != event.pointer) return;
    final start = _start;
    if (start == null) return;
    if ((event.position - start).distance < _dragThreshold) return;
    _dragging = true;
    setState(() {});
    unawaited(_startNativeDrag());
  }

  void _onPointerEnd(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _start = null;
    if (!_dragging && _pressed) {
      setState(() => _pressed = false);
    }
  }

  Future<void> _startNativeDrag() async {
    final paths = widget.dragPaths.isEmpty
        ? [widget.item.path]
        : widget.dragPaths;
    try {
      final ok = await _dragChannel.invokeMethod<bool>('startDrag', {
        'paths': paths,
      });
      if (ok == false) {
        AppLog.write('[shelf] native drag rejected: $paths');
      }
    } catch (error) {
      AppLog.write('[shelf] native drag failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _dragging = false;
          _pressed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final muted = widget.item.missing;
    final lifted = _pressed || _dragging;
    final scale = _dragging
        ? 1.045
        : (_pressed ? 1.03 : (_hovered ? 1.01 : 1.0));

    final content = AnimatedOpacity(
      opacity: _dragging ? 0.72 : 1.0,
      duration: IslandMotion.fast,
      child: AnimatedScale(
        scale: scale,
        duration: IslandMotion.fast,
        curve: IslandMotion.standard,
        child: AnimatedContainer(
          duration: IslandMotion.fast,
          curve: IslandMotion.standard,
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.accent.withValues(alpha: 0.14)
                : lifted
                ? colors.chip
                : (_hovered ? colors.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: widget.selected
                ? Border.all(color: colors.accent.withValues(alpha: 0.55))
                : null,
            boxShadow: lifted
                ? [
                    BoxShadow(
                      color: colors.background.withValues(alpha: 0.5),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );

    final entered = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: IslandMotion.standard,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(18 * (1 - t), 0),
          child: child,
        ),
      ),
      child: content,
    );

    return MouseRegion(
      cursor: muted ? SystemMouseCursors.basic : SystemMouseCursors.grab,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: entered,
      ),
    );
  }
}

/// 优先显示系统缩略图 / 原始文件图标，加载完成前退回分类图标。
class _ShelfLeading extends StatelessWidget {
  const _ShelfLeading({
    required this.item,
    required this.colors,
    required this.size,
    this.icon,
  });

  final ShelfItem item;
  final IslandColors colors;
  final double size;
  final Uint8List? icon;

  @override
  Widget build(BuildContext context) {
    final bytes = icon;
    if (!item.missing && bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(IslandMetrics.radiusTag),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          cacheWidth: 96,
          cacheHeight: 96,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    if (item.kind == 'image' && !item.missing) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(IslandMetrics.radiusTag),
        child: Image.file(
          File(item.path),
          width: size,
          height: size,
          cacheWidth: 96,
          cacheHeight: 96,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => Icon(
            shelfIconFor(item.kind),
            size: size * 0.6,
            color: colors.accent,
          ),
        ),
      );
    }
    return Icon(
      shelfIconFor(item.kind),
      size: size * 0.6,
      color: item.missing ? colors.muted : colors.accent,
    );
  }
}

/// 拖入时盖在抽屉上的提示层。
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.07),
        border: Border.all(
          color: colors.accent.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: IslandMetrics.space10),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: IslandMetrics.space12,
              vertical: IslandMetrics.space5,
            ),
            decoration: BoxDecoration(
              color: colors.background.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
              border: Border.all(color: colors.accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              '松手放进中转站',
              style: IslandTypography.bodyStrong.tint(colors.accent),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.colors,
    required this.onTap,
    this.size = IslandMetrics.iconMD,
    this.tooltip,
  });

  final IconData icon;
  final IslandColors colors;
  final VoidCallback onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
      onTap: onTap,
      child: SizedBox(
        width: IslandMetrics.hitTargetMin,
        height: IslandMetrics.hitTargetMin,
        child: Icon(icon, size: size, color: colors.muted),
      ),
    );
    final message = tooltip;
    return message == null ? button : Tooltip(message: message, child: button);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.colors, required this.dragging});

  final IslandColors colors;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dragging ? Icons.download_rounded : Icons.inbox_outlined,
            size: IslandMetrics.icon3XL,
            color: dragging ? colors.accent : colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space8),
          Text(
            dragging ? '松手放入中转站' : '把文件拖到这里',
            style: IslandTypography.subhead.tint(colors.text),
          ),
          const SizedBox(height: IslandMetrics.space4),
          Text(
            '只记录路径，不复制文件内容',
            style: IslandTypography.caption.tint(colors.muted),
          ),
        ],
      ),
    );
  }
}
