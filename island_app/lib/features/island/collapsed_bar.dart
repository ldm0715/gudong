import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../../core/widgets/glyph_stack.dart';
import '../agents/agent_controller.dart';
import '../agents/agent_glyph.dart';
import '../dashboard/metrics_controller.dart';
import '../dashboard/metrics_island_chips.dart';
import '../ime/ime_controller.dart';
import '../ime/ime_indicator.dart';
import '../mail/mail_controller.dart';
import '../mail/mail_provider_badge.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_widgets.dart';
import 'client_glyph.dart';
import 'island_layout.dart';

/// 收起态：时间 + 天气 + 未读标识 + agent 叠放，播放中显示音波。
///
/// [content] 已按宽度预算取舍，组件只渲染其中的元素，不再自行判断显隐。
/// [vertical] 为真时按左右停靠的窄栏竖向排列，内容保持正向不旋转。
class CollapsedBar extends StatefulWidget {
  const CollapsedBar({
    super.key,
    required this.mail,
    required this.weather,
    required this.ime,
    required this.metrics,
    required this.agents,
    required this.content,
    required this.metricIds,
    required this.size,
    this.vertical = false,
  });

  final MailController mail;
  final WeatherController weather;
  final ImeController ime;
  final MetricsController metrics;
  final AgentController agents;

  /// 预算取舍后的可见元素。
  final CollapsedContent content;

  /// 收起态候选指标，按顺序取前 [CollapsedContent.metricCount] 个。
  final List<String> metricIds;

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
    return widget.vertical ? _buildVertical(context) : _buildHorizontal(context);
  }

  Widget _buildHorizontal(BuildContext context) {
    final colors = context.islandColors;
    final content = widget.content;
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final snapshot = content.weather ? widget.weather.snapshot : null;
    final metricIds = widget.metricIds
        .take(content.metricCount)
        .toList(growable: false);
    final mailProvider = _latestMailProvider();
    final agentIds = widget.agents.runningAgentIds
        .take(content.agentCount)
        .toList(growable: false);
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IslandMetrics.space10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(time, style: IslandTypography.clock.tint(colors.text)),
              if (content.schedule) ...[
                const SizedBox(width: IslandMetrics.space6),
                const _ScheduleGlyph(),
              ],
              if (content.update) ...[
                const SizedBox(width: IslandMetrics.space6),
                const _UpdateGlyph(),
              ],
              if (snapshot != null) ...[
                const SizedBox(width: IslandMetrics.space7),
                WeatherChip(snapshot: snapshot),
              ],
              if (metricIds.isNotEmpty) ...[
                const SizedBox(width: IslandMetrics.space6),
                MetricsIslandChips(
                  controller: widget.metrics,
                  metricIds: metricIds,
                ),
              ],
              if (agentIds.isNotEmpty) ...[
                const SizedBox(width: IslandMetrics.space6),
                _AgentStack(
                  ids: agentIds,
                  extra: content.extraAgents,
                  size: IslandMetrics.iconLG,
                ),
              ],
              if (content.ime) ...[
                const SizedBox(width: IslandMetrics.space6),
                ImeIndicator(chinese: widget.ime.chinese),
              ],
              if (content.wechat) ...[
                const SizedBox(width: IslandMetrics.space8),
                const ClientGlyph(source: 'wechat', size: IslandMetrics.iconLG),
              ],
              if (content.qq) ...[
                const SizedBox(width: IslandMetrics.space4),
                const ClientGlyph(source: 'qq', size: IslandMetrics.iconLG),
              ],
              if (mailProvider != null) ...[
                const SizedBox(width: IslandMetrics.space6),
                MailProviderBadge(
                  provider: mailProvider.provider,
                  email: mailProvider.email,
                  size: IslandMetrics.iconLG,
                  color: colors.accent,
                ),
              ],
              if (content.playing) ...[
                const SizedBox(width: IslandMetrics.space6),
                const _WaveBars(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 竖屏窄栏：时间、天气、客户端标识和音波从上到下排列，文字保持正向。
  Widget _buildVertical(BuildContext context) {
    final colors = context.islandColors;
    final content = widget.content;
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    // 窄栏放不下 "HH:MM"，拆成小时在上、分钟在下。
    final parts = time.split(':');
    final clock = parts.length == 2 ? '${parts[0]}\n${parts[1]}' : time;
    // 竖排时所有图标统一用同一尺寸，避免大小不一。
    const iconSize = IslandMetrics.iconLG;
    final snapshot = content.weather ? widget.weather.snapshot : null;
    final metricIds = widget.metricIds
        .take(content.metricCount)
        .toList(growable: false);
    final mailProvider = _latestMailProvider();
    final agentIds = widget.agents.runningAgentIds
        .take(content.agentCount)
        .toList(growable: false);
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: IslandMetrics.space10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                clock,
                textAlign: TextAlign.center,
                style: IslandTypography.clockCompact.tint(colors.text),
              ),
              if (content.schedule) ...[
                const SizedBox(height: IslandMetrics.space6),
                const _ScheduleGlyph(size: iconSize),
              ],
              if (content.update) ...[
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
              if (metricIds.isNotEmpty) ...[
                const SizedBox(height: IslandMetrics.space4),
                MetricsIslandChips(
                  controller: widget.metrics,
                  metricIds: metricIds,
                  vertical: true,
                  iconSize: iconSize,
                ),
              ],
              if (agentIds.isNotEmpty) ...[
                const SizedBox(height: IslandMetrics.space4),
                _AgentStack(
                  ids: agentIds,
                  extra: content.extraAgents,
                  size: iconSize,
                  vertical: true,
                ),
              ],
              if (content.ime) ...[
                const SizedBox(height: IslandMetrics.space6),
                ImeIndicator(chinese: widget.ime.chinese),
              ],
              if (content.wechat) ...[
                const SizedBox(height: IslandMetrics.space6),
                const ClientGlyph(source: 'wechat', size: iconSize),
              ],
              if (content.qq) ...[
                const SizedBox(height: IslandMetrics.space4),
                const ClientGlyph(source: 'qq', size: iconSize),
              ],
              if (mailProvider != null) ...[
                const SizedBox(height: IslandMetrics.space4),
                MailProviderBadge(
                  provider: mailProvider.provider,
                  email: mailProvider.email,
                  size: iconSize,
                  color: colors.accent,
                ),
              ],
              if (content.playing) ...[
                const SizedBox(height: IslandMetrics.space4),
                const _WaveBars(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ({String provider, String email})? _latestMailProvider() {
    for (final item in widget.mail.items) {
      if (!item.unread) continue;
      final account = widget.mail.accountFor(item.accountId);
      if (account == null) continue;
      return (provider: account.provider, email: account.email);
    }
    return null;
  }
}

/// agent 图标叠放：首个完整可见，超出部分显示 `+N`。
class _AgentStack extends StatelessWidget {
  const _AgentStack({
    required this.ids,
    required this.extra,
    required this.size,
    this.vertical = false,
  });

  final List<String> ids;
  final int extra;
  final double size;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final stack = GlyphStack(
      size: size,
      vertical: vertical,
      semanticsLabel: '${ids.length + extra} 个 agent 运行中',
      children: [
        for (final id in ids) AgentGlyph(id: id, size: size),
      ],
    );
    final badge = extra > 0
        ? Text('+$extra', style: IslandTypography.micro.tint(colors.muted))
        : null;
    // 竖排时数量放在叠放下方，与窄栏纵向布局一致。
    final group = vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              stack,
              if (badge != null) ...[
                const SizedBox(height: IslandMetrics.space2),
                badge,
              ],
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              stack,
              if (badge != null) ...[
                const SizedBox(width: IslandMetrics.space2),
                badge,
              ],
            ],
          );
    // 叠放与数量合并成一个语义节点。
    return Semantics(
      label: '${ids.length + extra} 个 agent 运行中',
      excludeSemantics: true,
      child: group,
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
