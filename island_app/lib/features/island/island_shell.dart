import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/settings/settings_controller.dart';
import '../../core/theme/island_colors.dart';
import '../../core/window/window_position.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/diagnostics_tab.dart';
import '../media/media_controller.dart';
import '../media/media_tab.dart';
import '../messages/messages_controller.dart';
import '../messages/messages_tab.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_tab.dart';
import 'client_glyph.dart';
import 'collapsed_bar.dart';
import 'island_controller.dart';
import 'island_layout.dart';
import 'notification_banner.dart';

enum IslandTab { messages, weather, media, diagnostics }

/// 岛体外壳：收起 / 横幅 / 展开三态的容器与 tab 切换。
class IslandShell extends StatefulWidget {
  const IslandShell({
    super.key,
    required this.island,
    required this.messages,
    required this.weather,
    required this.media,
    required this.diagnostics,
    required this.settings,
    required this.windowPosition,
    required this.onOpenSettings,
  });

  final IslandController island;
  final MessagesController messages;
  final WeatherController weather;
  final MediaController media;
  final DiagnosticsController diagnostics;
  final SettingsController settings;
  final WindowPositionKeeper windowPosition;
  final VoidCallback onOpenSettings;

  @override
  State<IslandShell> createState() => _IslandShellState();
}

class _IslandShellState extends State<IslandShell> {
  IslandTab _tab = IslandTab.messages;

  @override
  Widget build(BuildContext context) {
    final island = widget.island;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned(
            top: IslandLayout.topInset,
            left: 0,
            right: 0,
            child: Center(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    island,
                    widget.messages,
                    widget.weather,
                    widget.media,
                    widget.diagnostics,
                    widget.settings,
                  ]),
                  builder: (context, _) {
                    final colors = context.islandColors;
                    final expanded = island.expanded;
                    final showBanner = island.showBanner;
                    final size = expanded
                        ? IslandLayout.expandedSize
                        : showBanner
                        ? IslandLayout.bannerSize
                        : IslandLayout.collapsedSize;
                    final radius = expanded ? 24.0 : (showBanner ? 22.0 : 18.0);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: size.width,
                      height: size.height,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          color: island.pulse && !expanded
                              ? colors.accent.withValues(alpha: 0.75)
                              : colors.stroke,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: expanded ? 24 : 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: 0,
                        maxWidth: IslandLayout.expandedSize.width,
                        minHeight: 0,
                        maxHeight: IslandLayout.expandedSize.height,
                        child: expanded
                            ? _ExpandedBody(
                                island: island,
                                messages: widget.messages,
                                weather: widget.weather,
                                media: widget.media,
                                diagnostics: widget.diagnostics,
                                onOpenSettings: widget.onOpenSettings,
                                handleVisible: island.handleVisible,
                                onDragStart: () => unawaited(
                                  widget.windowPosition.startDrag(),
                                ),
                                tab: _tab,
                                onTab: (tab) => setState(() => _tab = tab),
                              )
                            : showBanner
                            ? NotificationBanner(controller: widget.messages)
                            : CollapsedBar(
                                messages: widget.messages,
                                weather: widget.weather,
                                showWeather:
                                    widget.settings.settings.showWeather,
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.island,
    required this.messages,
    required this.weather,
    required this.media,
    required this.diagnostics,
    required this.onOpenSettings,
    required this.handleVisible,
    required this.onDragStart,
    required this.tab,
    required this.onTab,
  });

  final IslandController island;
  final MessagesController messages;
  final WeatherController weather;
  final MediaController media;
  final DiagnosticsController diagnostics;
  final VoidCallback onOpenSettings;
  final bool handleVisible;
  final VoidCallback onDragStart;
  final IslandTab tab;
  final ValueChanged<IslandTab> onTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return SizedBox(
      width: IslandLayout.expandedSize.width,
      height: IslandLayout.expandedSize.height,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 2),
                child: Row(
                  children: [
                    if (messages.unread.isNotEmpty) ...[
                      ClientGlyph(
                        source: messages.hasQq && !messages.hasWechat
                            ? 'qq'
                            : 'wechat',
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'Guduo Island',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    _StatusPill(ok: island.ready, label: island.statusLabel),
                    const SizedBox(width: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onOpenSettings,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.settings_rounded,
                          size: 14,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _TabButton(
                      label: '消息',
                      selected: tab == IslandTab.messages,
                      onTap: () => onTab(IslandTab.messages),
                    ),
                    _TabButton(
                      label: '天气',
                      selected: tab == IslandTab.weather,
                      onTap: () => onTab(IslandTab.weather),
                    ),
                    _TabButton(
                      label: '媒体',
                      selected: tab == IslandTab.media,
                      onTap: () => onTab(IslandTab.media),
                    ),
                    _TabButton(
                      label: '诊断',
                      selected: tab == IslandTab.diagnostics,
                      onTap: () => onTab(IslandTab.diagnostics),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  child: switch (tab) {
                    IslandTab.messages => MessagesTab(controller: messages),
                    IslandTab.weather => WeatherTab(controller: weather),
                    IslandTab.media => MediaTab(controller: media),
                    IslandTab.diagnostics => DiagnosticsTab(
                      connectionDetail: island.connectionDetail,
                      diagnostics: diagnostics,
                      weather: weather,
                    ),
                  },
                ),
              ),
            ],
          ),
          if (handleVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 16,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) => onDragStart(),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.handle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.accent : colors.muted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final color = ok ? colors.accent : colors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
