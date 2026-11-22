import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/settings/island_tabs.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../../core/window/dock_edge.dart';
import '../../core/window/window_position.dart';
import '../agents/agent_banner.dart';
import '../agents/agent_controller.dart';
import '../dashboard/dashboard_tab.dart';
import '../dashboard/metrics_controller.dart';
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
import '../shelf/shelf_controller.dart';
import '../shelf/shelf_drawer.dart';
import '../translate/translate_controller.dart';
import '../translate/translate_tab.dart';
import '../volume/volume_banner.dart';
import '../volume/volume_controller.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_tab.dart';
import 'collapsed_bar.dart';
import 'collapsed_content.dart';
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
    required this.metrics,
    required this.schedule,
    required this.anniversary,
    required this.volume,
    required this.agents,
    required this.shelf,
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
  final MetricsController metrics;
  final ScheduleController schedule;
  final AnniversaryController anniversary;
  final VolumeController volume;
  final AgentController agents;
  final ShelfController shelf;
  final SettingsController settings;
  final WindowPositionKeeper windowPosition;
  final VoidCallback onOpenSettings;

  @override
  State<IslandShell> createState() => _IslandShellState();
}

class _IslandShellState extends State<IslandShell> {
  IslandTab _tab = IslandTab.messages;
  bool _shelfOpen = false;
  // tab 条的横向滚动位置，收起后再展开时恢复。
  double _tabScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    widget.windowPosition.addListener(_onDockChanged);
    widget.island.addListener(_onIslandChanged);
  }

  @override
  void dispose() {
    widget.windowPosition.removeListener(_onDockChanged);
    widget.island.removeListener(_onIslandChanged);
    super.dispose();
  }

  void _onDockChanged() {
    if (mounted) setState(() {});
  }

  void _onIslandChanged() {
    // 岛体收起时一并收起抽屉，避免下次展开时突然出现。
    if (!widget.island.expanded && _shelfOpen && mounted) {
      widget.shelf.clearSelection();
      setState(() => _shelfOpen = false);
    }
  }

  void _openShelf() {
    if (!mounted) return;
    widget.island.setExpanded(true);
    if (_shelfOpen) return;
    setState(() => _shelfOpen = true);
  }

  void _onDropEnter() {
    widget.shelf.setDragActive(true);
    _openShelf();
  }

  void _onDropDone(DropDoneDetails details) {
    final paths = details.files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    widget.shelf.setDragActive(false);
    unawaited(widget.shelf.addPaths(paths));
    _openShelf();
  }

  @override
  Widget build(BuildContext context) {
    final island = widget.island;
    final side = widget.windowPosition.side;
    return DropTarget(
      onDragEntered: (_) => _onDropEnter(),
      onDragExited: (_) => widget.shelf.setDragActive(false),
      onDragDone: _onDropDone,
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: switch (side) {
            DockEdge.top => Alignment.topCenter,
            DockEdge.left => Alignment.centerLeft,
            DockEdge.right => Alignment.centerRight,
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
                widget.volume,
                widget.agents,
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
                final showAgentBanner =
                    settings.showAgentBanner &&
                    island.showAgentBanner &&
                    !showBanner &&
                    !showMailBanner &&
                    !showScheduleBanner;
                final showVolumeBanner =
                    island.showVolumeBanner &&
                    !showBanner &&
                    !showMailBanner &&
                    !showScheduleBanner &&
                    !showAgentBanner;
                // 消息横幅优先，其次是邮件、日程、agent 结束和音量，最后是输入法切换。
                final showIme =
                    settings.showImeBanner &&
                    widget.ime.visible &&
                    !showBanner &&
                    !showMailBanner &&
                    !showScheduleBanner &&
                    !showAgentBanner &&
                    !showVolumeBanner;
                final activeBanner =
                    showBanner ||
                    showMailBanner ||
                    showScheduleBanner ||
                    showAgentBanner ||
                    showVolumeBanner ||
                    showIme;
                final tabs = settings.visibleTabs;
                final tab = tabs.contains(_tab)
                    ? _tab
                    : (tabs.isEmpty ? null : tabs.first);
                final mini = island.mini(settings.autoCollapseOnMaximized);
                final collapsedContent = collapsedContentOf(
                  settings: widget.settings,
                  messages: widget.messages,
                  mail: widget.mail,
                  weather: widget.weather,
                  media: widget.media,
                  ime: widget.ime,
                  schedule: widget.schedule,
                  agents: widget.agents,
                );
                final size = mini
                    ? IslandLayout.miniBarHitSizeFor(side)
                    : expanded
                    ? IslandLayout.expandedSizeFor(side)
                    : activeBanner
                    ? IslandLayout.bannerSizeFor(side)
                    : IslandLayout.collapsedSizeFor(side, collapsedContent);
                final radius = mini
                    ? IslandMetrics.pill(size.height)
                    : expanded
                    ? IslandMetrics.radiusIslandExpanded
                    : (activeBanner
                          ? IslandMetrics.radiusIslandBanner
                          : IslandMetrics.radiusIslandCollapsed);
                final contentKey = mini
                    ? 'mini'
                    : expanded
                    ? 'expanded'
                    : showBanner
                    ? 'banner-message'
                    : showMailBanner
                    ? 'banner-mail'
                    : showScheduleBanner
                    ? 'banner-schedule'
                    : showAgentBanner
                    ? 'banner-agent'
                    : showVolumeBanner
                    ? 'banner-volume'
                    : showIme
                    ? 'banner-ime'
                    : 'collapsed';
                return AnimatedPadding(
                  duration: IslandMotion.base,
                  curve: IslandMotion.standard,
                  padding: switch (side) {
                    DockEdge.top => EdgeInsets.only(
                      top: mini
                          ? IslandLayout.miniEdgeInset
                          : IslandLayout.edgeInset,
                    ),
                    DockEdge.left => EdgeInsets.only(
                      left: mini
                          ? IslandLayout.miniEdgeInset
                          : IslandLayout.edgeInset,
                    ),
                    DockEdge.right => EdgeInsets.only(
                      right: mini
                          ? IslandLayout.miniEdgeInset
                          : IslandLayout.edgeInset,
                    ),
                  },
                  child: AnimatedContainer(
                    duration: IslandMotion.base,
                    curve: IslandMotion.standard,
                    width: size.width,
                    height: size.height,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: mini
                          ? colors.background.withValues(alpha: 0)
                          : colors.background,
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: mini
                            ? colors.stroke.withValues(alpha: 0)
                            : ((island.pulse ||
                                          (settings.showImeBanner &&
                                              widget.ime.visible)) &&
                                      !expanded
                                  ? colors.accent.withValues(alpha: 0.75)
                                  : colors.stroke),
                      ),
                    ),
                    child: OverflowBox(
                      // 用 tight 约束锁定内容的目标尺寸，避免内容被父约束压小。
                      alignment: Alignment.topCenter,
                      minWidth: size.width,
                      maxWidth: size.width,
                      minHeight: size.height,
                      maxHeight: size.height,
                      child: AnimatedSwitcher(
                        duration: IslandMotion.base,
                        switchInCurve: IslandMotion.standard,
                        switchOutCurve: IslandMotion.standard,
                        // 默认过渡是 FadeTransition，会生成 OpacityLayer；
                        // Windows 上 OpacityLayer + retained rendering 会触发
                        // picture 断言。改用位移过渡，避免 OpacityLayer。
                        transitionBuilder: (child, animation) =>
                            SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                              alignment: switch (side) {
                                DockEdge.top => Alignment.topCenter,
                                DockEdge.left => Alignment.centerLeft,
                                DockEdge.right => Alignment.centerRight,
                              },
                              // 只渲染当前态，不渲染淡出中的旧态，避免旧态
                              // 的大尺寸内容被塞进缩小后的容器里溢出。
                              children: [?currentChild],
                            ),
                        child: KeyedSubtree(
                          key: ValueKey(contentKey),
                          child: mini
                              ? _MiniBar(
                                  side: side,
                                  onTap: () => island.setExpanded(true),
                                )
                              : expanded
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
                                  metrics: widget.metrics,
                                  schedule: widget.schedule,
                                  anniversary: widget.anniversary,
                                  shelf: widget.shelf,
                                  side: side,
                                  shelfOpen: _shelfOpen,
                                  onToggleShelf: () {
                                    if (_shelfOpen) {
                                      widget.shelf.clearSelection();
                                    }
                                    setState(() => _shelfOpen = !_shelfOpen);
                                  },
                                  onCloseShelf: () {
                                    widget.shelf.clearSelection();
                                    setState(() => _shelfOpen = false);
                                  },
                                  settings: widget.settings,
                                  onOpenSettings: widget.onOpenSettings,
                                  handleVisible: island.handleVisible,
                                  onDragStart: () => unawaited(
                                    widget.windowPosition.startDrag(),
                                  ),
                                  tabs: tabs,
                                  tab: tab,
                                  onTab: (tab) => setState(() => _tab = tab),
                                  tabScrollOffset: _tabScrollOffset,
                                  onTabScroll: (offset) =>
                                      _tabScrollOffset = offset,
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
                              : showAgentBanner
                              ? AgentBanner(item: island.agentBannerItem!)
                              : showVolumeBanner
                              ? VolumeBanner(controller: widget.volume)
                              : showIme
                              ? ImeBanner(chinese: widget.ime.chinese)
                              : CollapsedBar(
                                  messages: widget.messages,
                                  mail: widget.mail,
                                  weather: widget.weather,
                                  media: widget.media,
                                  schedule: widget.schedule,
                                  ime: widget.ime,
                                  metrics: widget.metrics,
                                  agents: widget.agents,
                                  showAgents: settings.showAgentIndicator,
                                  showWeather: settings.showWeather,
                                  showPlayingIndicator:
                                      settings.showPlayingIndicator,
                                  showImeIndicator: settings.showImeIndicator,
                                  showScheduleIndicator:
                                      settings.showScheduleIndicator,
                                  islandMetrics: settings.islandMetrics,
                                  size: size,
                                  vertical: side.isVertical,
                                ),
                        ),
                      ),
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
    required this.metrics,
    required this.schedule,
    required this.anniversary,
    required this.shelf,
    required this.side,
    required this.shelfOpen,
    required this.onToggleShelf,
    required this.onCloseShelf,
    required this.settings,
    required this.onOpenSettings,
    required this.handleVisible,
    required this.onDragStart,
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.tabScrollOffset,
    required this.onTabScroll,
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
  final MetricsController metrics;
  final ScheduleController schedule;
  final AnniversaryController anniversary;
  final ShelfController shelf;
  final DockEdge side;
  final bool shelfOpen;
  final VoidCallback onToggleShelf;
  final VoidCallback onCloseShelf;
  final SettingsController settings;
  final VoidCallback onOpenSettings;
  final bool handleVisible;
  final VoidCallback onDragStart;
  final List<IslandTab> tabs;
  final IslandTab? tab;
  final ValueChanged<IslandTab> onTab;
  final double tabScrollOffset;
  final ValueChanged<double> onTabScroll;

  Offset get _shelfHiddenOffset => switch (side) {
    DockEdge.top => const Offset(0, -1),
    DockEdge.left => const Offset(-1, 0),
    DockEdge.right => const Offset(1, 0),
  };

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    Image.asset(
                      'assets/branding/logo.png',
                      width: IslandMetrics.iconLG,
                      height: IslandMetrics.iconLG,
                      cacheWidth: (IslandMetrics.iconLG * 2).round(),
                      cacheHeight: (IslandMetrics.iconLG * 2).round(),
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(width: IslandMetrics.space6),
                    Text(
                      appName,
                      style: IslandTypography.title.tint(colors.text),
                    ),
                    const Spacer(),
                    _StatusPill(ok: island.ready, label: island.statusLabel),
                    const SizedBox(width: IslandMetrics.space2),
                    InkWell(
                      borderRadius: BorderRadius.circular(
                        IslandMetrics.radiusPill,
                      ),
                      onTap: onToggleShelf,
                      child: Padding(
                        padding: const EdgeInsets.all(IslandMetrics.space4),
                        child: Icon(
                          Icons.inbox_outlined,
                          size: IslandMetrics.iconSM,
                          color: shelfOpen ? colors.accent : colors.muted,
                        ),
                      ),
                    ),
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
                  child: _TabStrip(
                    tabs: tabs,
                    active: activeTab,
                    onTab: onTab,
                    initialOffset: tabScrollOffset,
                    onScroll: onTabScroll,
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
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !shelfOpen,
              child: AnimatedSlide(
                offset: shelfOpen ? Offset.zero : _shelfHiddenOffset,
                duration: IslandMotion.base,
                curve: IslandMotion.standard,
                child: ShelfDrawer(
                  controller: shelf,
                  settings: settings,
                  side: side,
                  onClose: onCloseShelf,
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
      IslandTab.dashboard => DashboardTab(
        controller: metrics,
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

/// 前台窗口最大化时的极简横杠，点击后显示收起态。
class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.side, required this.onTap});

  final DockEdge side;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final visual = IslandLayout.miniBarVisualSizeFor(side);
    return Semantics(
      button: true,
      label: '显示岛体',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Container(
              width: visual.width,
              height: visual.height,
              decoration: BoxDecoration(
                color: colors.text.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: colors.background.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

/// 单行横向滚动的 tab 条：鼠标滚轮平移，切 tab 后把选中项滚入视野。
class _TabStrip extends StatefulWidget {
  const _TabStrip({
    required this.tabs,
    required this.active,
    required this.onTab,
    required this.initialOffset,
    required this.onScroll,
  });

  final List<IslandTab> tabs;
  final IslandTab? active;
  final ValueChanged<IslandTab> onTab;
  final double initialOffset;
  final ValueChanged<double> onScroll;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  final ScrollController _controller = ScrollController();
  final Map<IslandTab, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportOffset);
    final offset = widget.initialOffset;
    if (offset > 0) {
      // 等 viewport 完成布局、拿到 maxScrollExtent 后再恢复位置。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final position = _controller.position;
        final target = offset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if (target > 0 && target != position.pixels) {
          _controller.jumpTo(target);
        }
      });
    }
  }

  /// 把当前滚动位置回传给上层保存，收起后再展开时恢复。
  void _reportOffset() {
    if (_controller.hasClients) widget.onScroll(_controller.offset);
  }

  @override
  void didUpdateWidget(covariant _TabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      // 等新选中项完成布局后再把位置滚到视野内。
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_reportOffset);
    _controller.dispose();
    super.dispose();
  }

  /// 把选中项滚入可视区，瞬时定位不做滚动动画。
  void _revealActive() {
    final context = _itemKeys[widget.active]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(context, alignment: 0.5);
  }

  /// 鼠标滚轮只产生纵向增量，横向 ScrollView 不消费，这里映射为横向平移。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    final position = _controller.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == position.pixels) return;
    _controller.jumpTo(target);
  }

  GlobalKey _keyFor(IslandTab tab) =>
      _itemKeys.putIfAbsent(tab, () => GlobalKey());

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: [
            for (final item in widget.tabs)
              _TabButton(
                key: _keyFor(item),
                label: item.label,
                selected: widget.active == item,
                onTap: () => widget.onTab(item),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
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
