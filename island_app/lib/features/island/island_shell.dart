import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/settings/island_tabs.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../../core/window/dock_edge.dart';
import '../../core/window/window_position.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/diagnostics_tab.dart';
import '../ime/ime_banner.dart';
import '../ime/ime_controller.dart';
import '../mail/mail_banner.dart';
import '../mail/mail_controller.dart';
import '../mail/mail_tab.dart';
import '../media/media_controller.dart';
import '../media/media_tab.dart';
import '../messages/messages_controller.dart';
import '../messages/messages_tab.dart';
import '../quota/quota_controller.dart';
import '../quota/quota_tab.dart';
import '../schedule/anniversary_controller.dart';
import '../schedule/schedule_banner.dart';
import '../schedule/schedule_controller.dart';
import '../schedule/schedule_tab.dart';
import '../translate/translate_controller.dart';
import '../translate/translate_tab.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_tab.dart';
import 'client_glyph.dart';
import 'collapsed_bar.dart';
import 'island_controller.dart';
import 'island_layout.dart';
import 'notification_banner.dart';

/// 岛体外壳：收起 / 横幅 / 展开三态的容器与 tab 切换。
class IslandShell extends StatefulWidget {
  const IslandShell({
    super.key,
    required this.island,
    required this.messages,
    required this.mail,
    required this.weather,
    required this.media,
    required this.ime,
    required this.diagnostics,
    required this.translate,
    required this.quota,
    required this.schedule,
    required this.anniversary,
    required this.settings,
    required this.windowPosition,
    required this.onOpenSettings,
  });

  final IslandController island;
  final MessagesController messages;
  final MailController mail;
  final WeatherController weather;
  final MediaController media;
  final ImeController ime;
  final DiagnosticsController diagnostics;
  final TranslateController translate;
  final QuotaController quota;
  final ScheduleController schedule;
  final AnniversaryController anniversary;
  final SettingsController settings;
  final WindowPositionKeeper windowPosition;
  final VoidCallback onOpenSettings;

  @override
  State<IslandShell> createState() => _IslandShellState();
}

class _IslandShellState extends State<IslandShell> {
  IslandTab _tab = IslandTab.messages;

  @override
  void initState() {
    super.initState();
    widget.windowPosition.addListener(_onDockChanged);
  }

  @override
  void dispose() {
    widget.windowPosition.removeListener(_onDockChanged);
    super.dispose();
  }

  void _onDockChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final island = widget.island;
    final side = widget.windowPosition.side;
    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: switch (side) {
          DockEdge.top => Alignment.topCenter,
          DockEdge.left => Alignment.centerLeft,
          DockEdge.right => Alignment.centerRight,
        },
        child: Padding(
          padding: switch (side) {
            DockEdge.top => const EdgeInsets.only(top: IslandLayout.edgeInset),
            DockEdge.left => const EdgeInsets.only(
              left: IslandLayout.edgeInset,
            ),
            DockEdge.right => const EdgeInsets.only(
              right: IslandLayout.edgeInset,
            ),
          },
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                island,
                widget.messages,
                widget.mail,
                widget.weather,
                widget.media,
                widget.ime,
                widget.diagnostics,
                widget.translate,
                widget.quota,
                widget.schedule,
                widget.anniversary,
                widget.settings,
              ]),
              builder: (context, _) {
                final colors = context.islandColors;
                final expanded = island.expanded;
                final showBanner = island.showBanner;
                final showMailBanner = island.showMailBanner && !showBanner;
                final showScheduleBanner =
                    island.showScheduleBanner && !showBanner && !showMailBanner;
                final settings = widget.settings.settings;
                // 消息横幅优先，其次是新邮件和日程提醒，最后是输入法切换。
                final showIme =
                    settings.showImeBanner &&
                    widget.ime.visible &&
                    !showBanner &&
                    !showMailBanner &&
                    !showScheduleBanner;
                final activeBanner =
                    showBanner ||
                    showMailBanner ||
                    showScheduleBanner ||
                    showIme;
                final tabs = settings.visibleTabs;
                final tab = tabs.contains(_tab)
                    ? _tab
                    : (tabs.isEmpty ? null : tabs.first);
                final size = expanded
                    ? IslandLayout.expandedSizeFor(side)
                    : activeBanner
                    ? IslandLayout.bannerSizeFor(side)
                    : IslandLayout.collapsedSizeFor(
                        side,
                        imeIndicator: settings.showImeIndicator,
                      );
                final radius = expanded
                    ? IslandMetrics.radiusIslandExpanded
                    : (activeBanner
                          ? IslandMetrics.radiusIslandBanner
                          : IslandMetrics.radiusIslandCollapsed);
                return AnimatedContainer(
                  duration: IslandMotion.base,
                  curve: IslandMotion.standard,
                  width: size.width,
                  height: size.height,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color:
                          (island.pulse ||
                                  (settings.showImeBanner &&
                                      widget.ime.visible)) &&
                              !expanded
                          ? colors.accent.withValues(alpha: 0.75)
                          : colors.stroke,
                    ),
                  ),
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: 0,
                    maxWidth: size.width,
                    minHeight: 0,
                    maxHeight: size.height,
                    child: expanded
                        ? _ExpandedBody(
                            size: IslandLayout.expandedSizeFor(side),
                            island: island,
                            messages: widget.messages,
                            mail: widget.mail,
                            weather: widget.weather,
                            media: widget.media,
                            diagnostics: widget.diagnostics,
                            translate: widget.translate,
                            quota: widget.quota,
                            schedule: widget.schedule,
                            anniversary: widget.anniversary,
                            settings: widget.settings,
                            onOpenSettings: widget.onOpenSettings,
                            handleVisible: island.handleVisible,
                            onDragStart: () =>
                                unawaited(widget.windowPosition.startDrag()),
                            tabs: tabs,
                            tab: tab,
                            onTab: (tab) => setState(() => _tab = tab),
                          )
                        : showBanner
                        ? NotificationBanner(controller: widget.messages)
                        : showMailBanner
                        ? MailBanner(
                            controller: widget.mail,
                            item: island.mailBannerItem!,
                          )
                        : showScheduleBanner
                        ? ScheduleBanner(item: island.scheduleBannerItem!)
                        : showIme
                        ? ImeBanner(chinese: widget.ime.chinese)
                        : CollapsedBar(
                            messages: widget.messages,
                            mail: widget.mail,
                            weather: widget.weather,
                            media: widget.media,
                            schedule: widget.schedule,
                            ime: widget.ime,
                            showWeather: settings.showWeather,
                            showPlayingIndicator: settings.showPlayingIndicator,
                            showImeIndicator: settings.showImeIndicator,
                            showScheduleIndicator:
                                settings.showScheduleIndicator,
                            vertical: side.isVertical,
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.size,
    required this.island,
    required this.messages,
    required this.mail,
    required this.weather,
    required this.media,
    required this.diagnostics,
    required this.translate,
    required this.quota,
    required this.schedule,
    required this.anniversary,
    required this.settings,
    required this.onOpenSettings,
    required this.handleVisible,
    required this.onDragStart,
    required this.tabs,
    required this.tab,
    required this.onTab,
  });

  final Size size;
  final IslandController island;
  final MessagesController messages;
  final MailController mail;
  final WeatherController weather;
  final MediaController media;
  final DiagnosticsController diagnostics;
  final TranslateController translate;
  final QuotaController quota;
  final ScheduleController schedule;
  final AnniversaryController anniversary;
  final SettingsController settings;
  final VoidCallback onOpenSettings;
  final bool handleVisible;
  final VoidCallback onDragStart;
  final List<IslandTab> tabs;
  final IslandTab? tab;
  final ValueChanged<IslandTab> onTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final activeTab = tab;
    // 天气页自己管理左右翻页栏，用岛体整宽换回更宽的显示区域。
    final horizontalPadding =
        activeTab == IslandTab.weather || activeTab == IslandTab.schedule
        ? 0.0
        : IslandMetrics.space14;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  IslandMetrics.space14,
                  IslandMetrics.space10,
                  IslandMetrics.space8,
                  IslandMetrics.space2,
                ),
                child: Row(
                  children: [
                    if (messages.unread.isNotEmpty) ...[
                      ClientGlyph(
                        source: messages.hasQq && !messages.hasWechat
                            ? 'qq'
                            : 'wechat',
                        size: IslandMetrics.iconXL,
                      ),
                      const SizedBox(width: IslandMetrics.space8),
                    ],
                    Text(
                      'Guduo Island',
                      style: IslandTypography.title.tint(colors.text),
                    ),
                    const Spacer(),
                    _StatusPill(ok: island.ready, label: island.statusLabel),
                    const SizedBox(width: IslandMetrics.space2),
                    InkWell(
                      borderRadius: BorderRadius.circular(
                        IslandMetrics.radiusPill,
                      ),
                      onTap: onOpenSettings,
                      child: Padding(
                        padding: const EdgeInsets.all(IslandMetrics.space4),
                        child: Icon(
                          Icons.settings_rounded,
                          size: IslandMetrics.iconSM,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (tabs.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IslandMetrics.space12,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in tabs)
                          _TabButton(
                            label: item.label,
                            selected: activeTab == item,
                            onTap: () => onTab(item),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: IslandMetrics.space4),
              ],
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    IslandMetrics.space4,
                    horizontalPadding,
                    IslandMetrics.space12,
                  ),
                  child: _content(colors, activeTab),
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
                      padding: const EdgeInsets.only(top: IslandMetrics.space3),
                      child: Container(
                        width: IslandMetrics.handleWidth,
                        height: IslandMetrics.handleHeight,
                        decoration: BoxDecoration(
                          color: colors.handle,
                          borderRadius: BorderRadius.circular(
                            IslandMetrics.radiusBar,
                          ),
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

  Widget _content(IslandColors colors, IslandTab? activeTab) {
    if (activeTab == null) {
      return _NoVisibleTabs(colors: colors, onOpenSettings: onOpenSettings);
    }
    return switch (activeTab) {
      IslandTab.messages => MessagesTab(controller: messages),
      IslandTab.mail => MailTab(
        controller: mail,
        settings: settings,
        onOpenSettings: onOpenSettings,
      ),
      IslandTab.translate => TranslateTab(
        controller: translate,
        settings: settings,
      ),
      IslandTab.weather => WeatherTab(controller: weather),
      IslandTab.media => MediaTab(controller: media),
      IslandTab.quota => QuotaTab(
        controller: quota,
        settings: settings.settings,
      ),
      IslandTab.schedule => ScheduleTab(
        controller: schedule,
        anniversary: anniversary,
      ),
      IslandTab.diagnostics => DiagnosticsTab(
        connectionDetail: island.connectionDetail,
        diagnostics: diagnostics,
        weather: weather,
      ),
    };
  }
}

/// 所有页面都被隐藏时的展开态内容，保留设置入口。
class _NoVisibleTabs extends StatelessWidget {
  const _NoVisibleTabs({required this.colors, required this.onOpenSettings});

  final IslandColors colors;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dashboard_outlined,
            size: IslandMetrics.iconXL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space8),
          Text('未启用页面', style: IslandTypography.subhead.tint(colors.text)),
          const SizedBox(height: IslandMetrics.space4),
          Text(
            '在设置 → 页面管理中开启',
            style: IslandTypography.caption.tint(colors.muted),
          ),
          const SizedBox(height: IslandMetrics.space10),
          InkWell(
            borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
            onTap: onOpenSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: IslandMetrics.space12,
                vertical: IslandMetrics.space5,
              ),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(
                  IslandMetrics.radiusControl,
                ),
              ),
              child: Text(
                '打开设置',
                style: IslandTypography.caption.tint(colors.accent),
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
      borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: IslandMetrics.space6),
        padding: const EdgeInsets.symmetric(
          horizontal: IslandMetrics.space8,
          vertical: IslandMetrics.space5,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
        ),
        child: Text(
          label,
          style: IslandTypography.caption.copyWith(
            color: selected ? colors.accent : colors.muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
      padding: const EdgeInsets.symmetric(
        horizontal: IslandMetrics.space8,
        vertical: IslandMetrics.space3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IslandMetrics.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: IslandMetrics.space6,
            height: IslandMetrics.space6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: IslandMetrics.space5),
          Text(label, style: IslandTypography.microStrong.tint(color)),
        ],
      ),
    );
  }
}
