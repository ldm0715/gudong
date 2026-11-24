import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../agents/agent_controller.dart';
import '../agents/agent_glyph.dart';
import '../dashboard/metrics_controller.dart';
import '../dashboard/metrics_island_chips.dart';
import '../ime/ime_controller.dart';
import '../ime/ime_indicator.dart';
import '../mail/mail_controller.dart';
import '../mail/mail_provider_badge.dart';
import '../media/media_controller.dart';
import '../messages/messages_controller.dart';
import '../schedule/schedule_controller.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_models.dart';
import '../weather/weather_widgets.dart';
import 'client_glyph.dart';

/// 收起态：时间 + 天气 + 微信 / QQ 未读标识，播放中显示音波。
///
/// [vertical] 为真时按左右停靠的窄栏竖向排列，内容保持正向不旋转。
class CollapsedBar extends StatefulWidget {
  const CollapsedBar({
    super.key,
    required this.messages,
    required this.mail,
    required this.weather,
    required this.media,
    required this.schedule,
    required this.ime,
    required this.metrics,
    required this.agents,
    required this.showAgents,
    required this.showWeather,
    required this.showPlayingIndicator,
    required this.showImeIndicator,
    required this.showScheduleIndicator,
    required this.showUpdate,
    required this.islandMetrics,
    required this.size,
    this.vertical = false,
  });

  final MessagesController messages;
  final MailController mail;
  final WeatherController weather;
  final MediaController media;
  final ScheduleController schedule;
  final ImeController ime;
  final MetricsController metrics;
  final AgentController agents;
  final bool showAgents;
  final bool showWeather;
  final bool showPlayingIndicator;
  final bool showImeIndicator;
  final bool showScheduleIndicator;

  /// 有新版本可用时显示更新图标。
  final bool showUpdate;

  /// 收起态显示的指标 id，来自设置。
  final List<String> islandMetrics;

  /// 由外壳按实际内容算出的收起态尺寸。
  final Size size;
  final bool vertical;

  @override
  State<CollapsedBar> createState() => _CollapsedBarState();
}

class _CollapsedBarState extends State<CollapsedBar> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _scheduleClock();
  }

  void _scheduleClock() {
    final now = DateTime.now();
    _clock = Timer(
      Duration(milliseconds: (60 - now.second) * 1000 - now.millisecond),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleClock();
      },
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final snapshot = widget.showWeather ? widget.weather.snapshot : null;
    final showWave =
        widget.showPlayingIndicator &&
        widget.media.available &&
        widget.media.playing;
    final showIme = widget.showImeIndicator && widget.ime.mode != null;
    final hasScheduleToday =
        widget.showScheduleIndicator && widget.schedule.hasPendingOn(now);
    final unreadMail = widget.mail.items.where((item) => item.unread);
    final latestUnread = unreadMail.isEmpty ? null : unreadMail.first;
    final latestAccount = latestUnread == null
        ? null
        : widget.mail.accountFor(latestUnread.accountId);
    final mailProvider = latestAccount?.provider;
    final mailEmail = latestAccount?.email;
    final mailColor = colors.accent;
    final runningAgents = widget.showAgents
        ? widget.agents.runningAgentIds
        : const <String>[];
    final agentIcons = runningAgents.take(2).toList(growable: false);
    final extraAgents = runningAgents.length - agentIcons.length;
    final size = widget.size;
    if (widget.vertical) {
      return _buildVertical(
        colors,
        time,
        snapshot,
        showWave,
        showIme,
        hasScheduleToday,
        size,
        mailProvider,
        mailEmail,
        mailColor,
      );
    }
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Row(
        children: [
          const SizedBox(width: IslandMetrics.space10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(time, style: IslandTypography.clock.tint(colors.text)),
                  if (hasScheduleToday) ...[
                    const SizedBox(width: IslandMetrics.space6),
                    const _ScheduleGlyph(),
                  ],
                  if (widget.showUpdate) ...[
                    const SizedBox(width: IslandMetrics.space6),
                    const _UpdateGlyph(),
                  ],
                  if (snapshot != null) ...[
                    const SizedBox(width: IslandMetrics.space7),
                    WeatherChip(snapshot: snapshot),
                  ],
                  if (widget.islandMetrics.isNotEmpty) ...[
                    const SizedBox(width: IslandMetrics.space6),
                    MetricsIslandChips(
                      controller: widget.metrics,
                      metricIds: widget.islandMetrics,
                    ),
                  ],
                  if (agentIcons.isNotEmpty) ...[
                    const SizedBox(width: IslandMetrics.space6),
                    for (var index = 0; index < agentIcons.length; index++) ...[
                      if (index > 0)
                        const SizedBox(width: IslandMetrics.space3),
                      AgentGlyph(id: agentIcons[index], size: 18),
                    ],
                    if (extraAgents > 0) ...[
                      const SizedBox(width: IslandMetrics.space2),
                      Text(
                        '+$extraAgents',
                        style: IslandTypography.micro.tint(colors.muted),
                      ),
                    ],
                  ],
                  if (showIme) ...[
                    const SizedBox(width: IslandMetrics.space6),
                    ImeIndicator(chinese: widget.ime.chinese),
                  ],
                  if (widget.messages.hasWechat) ...[
                    const SizedBox(width: IslandMetrics.space8),
                    const ClientGlyph(source: 'wechat', size: 18),
                  ],
                  if (widget.messages.hasQq) ...[
                    const SizedBox(width: IslandMetrics.space4),
                    const ClientGlyph(source: 'qq', size: 18),
                  ],
                  if (mailProvider != null) ...[
                    const SizedBox(width: IslandMetrics.space6),
                    MailProviderBadge(
                      provider: mailProvider,
                      email: mailEmail,
                      size: IslandMetrics.iconLG,
                      color: mailColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (showWave) ...[
            const SizedBox(width: IslandMetrics.space6),
            const _WaveBars(),
          ],
          const SizedBox(width: IslandMetrics.space10),
        ],
      ),
    );
  }

  /// 竖屏窄栏：时间、天气、客户端标识和音波从上到下排列，文字保持正向。
  Widget _buildVertical(
    IslandColors colors,
    String time,
    WeatherSnapshot? snapshot,
    bool showWave,
    bool showIme,
    bool hasScheduleToday,
    Size size,
    String? mailProvider,
    String? mailEmail,
    Color mailColor,
  ) {
    // 窄栏放不下 "HH:MM"，拆成小时在上、分钟在下。
    final parts = time.split(':');
    final clock = parts.length == 2 ? '${parts[0]}\n${parts[1]}' : time;
    // 竖排时所有图标统一用同一尺寸，避免天气、指标、客户端图标大小不一。
    const iconSize = IslandMetrics.iconLG;
    final runningAgents = widget.showAgents
        ? widget.agents.runningAgentIds
        : const <String>[];
    final agentIcons = runningAgents.take(2).toList(growable: false);
    final extraAgents = runningAgents.length - agentIcons.length;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        children: [
          const SizedBox(height: IslandMetrics.space10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    clock,
                    textAlign: TextAlign.center,
                    style: IslandTypography.clockCompact.tint(colors.text),
                  ),
                  if (hasScheduleToday) ...[
                    const SizedBox(height: IslandMetrics.space6),
                    const _ScheduleGlyph(size: iconSize),
                  ],
                  if (widget.showUpdate) ...[
                    const SizedBox(height: IslandMetrics.space6),
                    const _UpdateGlyph(size: iconSize),
                  ],
                  if (snapshot != null) ...[
                    const SizedBox(height: IslandMetrics.space6),
                    Icon(
                      weatherIcon(snapshot.kind, snapshot.isDay),
                      size: iconSize,
                      color: weatherColor(colors, snapshot.kind),
                    ),
                    const SizedBox(height: IslandMetrics.space2),
                    Text(
                      '${snapshot.roundedTemp}°',
                      style: IslandTypography.microStrong.tint(colors.text),
                    ),
                  ],
                  if (widget.islandMetrics.isNotEmpty) ...[
                    const SizedBox(height: IslandMetrics.space4),
                    MetricsIslandChips(
                      controller: widget.metrics,
                      metricIds: widget.islandMetrics,
                      vertical: true,
                      iconSize: iconSize,
                    ),
                  ],
                  if (agentIcons.isNotEmpty) ...[
                    const SizedBox(height: IslandMetrics.space4),
                    for (var index = 0; index < agentIcons.length; index++) ...[
                      if (index > 0)
                        const SizedBox(height: IslandMetrics.space3),
                      AgentGlyph(id: agentIcons[index], size: iconSize),
                    ],
                    if (extraAgents > 0) ...[
                      const SizedBox(height: IslandMetrics.space2),
                      Text(
                        '+$extraAgents',
                        style: IslandTypography.micro.tint(colors.muted),
                      ),
                    ],
                  ],
                  if (showIme) ...[
                    const SizedBox(height: IslandMetrics.space6),
                    ImeIndicator(chinese: widget.ime.chinese),
                  ],
                  if (widget.messages.hasWechat) ...[
                    const SizedBox(height: IslandMetrics.space6),
                    const ClientGlyph(source: 'wechat', size: iconSize),
                  ],
                  if (widget.messages.hasQq) ...[
                    const SizedBox(height: IslandMetrics.space4),
                    const ClientGlyph(source: 'qq', size: iconSize),
                  ],
                  if (mailProvider != null) ...[
                    const SizedBox(height: IslandMetrics.space4),
                    MailProviderBadge(
                      provider: mailProvider,
                      email: mailEmail,
                      size: iconSize,
                      color: mailColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 与横向版本贴右边一致：音波固定在窄栏最下方。
          if (showWave) ...[
            const SizedBox(height: IslandMetrics.space4),
            const _WaveBars(),
          ],
          const SizedBox(height: IslandMetrics.space10),
        ],
      ),
    );
  }
}

/// 当天有日程时在收起态显示的闹钟标识。
class _ScheduleGlyph extends StatelessWidget {
  const _ScheduleGlyph({this.size = IslandMetrics.iconSM});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Tooltip(
      message: '今日有日程',
      waitDuration: IslandMotion.tooltipDelay,
      child: Semantics(
        label: '今日有日程',
        child: Icon(Icons.alarm_rounded, size: size, color: colors.accent),
      ),
    );
  }
}

/// 有新版本时在收起态显示的更新标识。
class _UpdateGlyph extends StatelessWidget {
  const _UpdateGlyph({this.size = IslandMetrics.iconSM});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Tooltip(
      message: '有新版本可用',
      waitDuration: IslandMotion.tooltipDelay,
      child: Semantics(
        label: '有新版本可用',
        child: Icon(
          Icons.new_releases_rounded,
          size: size,
          color: colors.accent,
        ),
      ),
    );
  }
}

/// 四根随正弦起伏的音波，只在播放中挂载，停止后自动释放动画。
class _WaveBars extends StatefulWidget {
  const _WaveBars();

  @override
  State<_WaveBars> createState() => _WaveBarsState();
}

class _WaveBarsState extends State<_WaveBars>
    with SingleTickerProviderStateMixin {
  /// 中间最高、向两端递减的高度包络。
  static const _envelope = [0.35, 0.65, 1.0, 0.65, 0.35];

  /// 同一频率、按位置递延相位，形成连续行波；相邻条不会独立乱跳。
  static const _phaseStep = 1.05;
  static const _minHeight = 3.5;
  static const _maxHeight = 16.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: IslandMotion.wave,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return RepaintBoundary(
      child: SizedBox(
        width: 20,
        height: _maxHeight,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final time = _controller.value * 2 * math.pi;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var index = 0; index < _envelope.length; index++)
                  Container(
                    width: IslandMetrics.waveBarWidth,
                    height: _barHeight(time, index),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(
                        IslandMetrics.waveBarWidth / 2,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 主波沿条序传播，副波反向缓慢叠加，增加变化但不破坏相邻连续性。
  double _barHeight(double time, int index) {
    final offset = index * _phaseStep;
    final primary = math.sin(time + offset);
    final secondary = math.sin(time * 0.45 - index * 0.65 + 1.7);
    final pulse = (0.62 + 0.28 * primary + 0.1 * secondary).clamp(0.2, 1.0);
    return _minHeight + (_maxHeight - _minHeight) * _envelope[index] * pulse;
  }
}
