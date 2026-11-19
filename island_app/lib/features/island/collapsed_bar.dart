import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../ime/ime_controller.dart';
import '../ime/ime_indicator.dart';
import '../media/media_controller.dart';
import '../messages/messages_controller.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_models.dart';
import '../weather/weather_widgets.dart';
import 'client_glyph.dart';
import 'island_layout.dart';

/// 收起态：时间 + 天气 + 微信 / QQ 未读标识，播放中显示音波。
///
/// [vertical] 为真时按左右停靠的窄栏竖向排列，内容保持正向不旋转。
class CollapsedBar extends StatefulWidget {
  const CollapsedBar({
    super.key,
    required this.messages,
    required this.weather,
    required this.media,
    required this.ime,
    required this.showWeather,
    required this.showPlayingIndicator,
    required this.showImeIndicator,
    this.vertical = false,
  });

  final MessagesController messages;
  final WeatherController weather;
  final MediaController media;
  final ImeController ime;
  final bool showWeather;
  final bool showPlayingIndicator;
  final bool showImeIndicator;
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
    final size = IslandLayout.collapsedBarSize(
      vertical: widget.vertical,
      imeIndicator: widget.showImeIndicator,
    );
    if (widget.vertical) {
      return _buildVertical(colors, time, snapshot, showWave, showIme, size);
    }
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Row(
        children: [
          const SizedBox(width: IslandMetrics.space10),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(time, style: IslandTypography.clock.tint(colors.text)),
                if (snapshot != null) ...[
                  const SizedBox(width: IslandMetrics.space7),
                  WeatherChip(snapshot: snapshot),
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
              ],
            ),
          ),
          if (showWave) const _WaveBars(),
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
    Size size,
  ) {
    // 窄栏放不下 "HH:MM"，拆成小时在上、分钟在下。
    final parts = time.split(':');
    final clock = parts.length == 2 ? '${parts[0]}\n${parts[1]}' : time;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        children: [
          const SizedBox(height: IslandMetrics.space10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  clock,
                  textAlign: TextAlign.center,
                  style: IslandTypography.clockCompact.tint(colors.text),
                ),
                if (snapshot != null) ...[
                  const SizedBox(height: IslandMetrics.space6),
                  Icon(
                    weatherIcon(snapshot.kind, snapshot.isDay),
                    size: IslandMetrics.iconSM,
                    color: weatherColor(colors, snapshot.kind),
                  ),
                  const SizedBox(height: IslandMetrics.space2),
                  Text(
                    '${snapshot.roundedTemp}°',
                    style: IslandTypography.microStrong.tint(colors.text),
                  ),
                ],
                if (showIme) ...[
                  const SizedBox(height: IslandMetrics.space6),
                  ImeIndicator(chinese: widget.ime.chinese),
                ],
                if (widget.messages.hasWechat) ...[
                  const SizedBox(height: IslandMetrics.space6),
                  const ClientGlyph(source: 'wechat', size: 18),
                ],
                if (widget.messages.hasQq) ...[
                  const SizedBox(height: IslandMetrics.space4),
                  const ClientGlyph(source: 'qq', size: 18),
                ],
              ],
            ),
          ),
          // 与横向版本贴右边一致：音波固定在窄栏最下方。
          if (showWave) const _WaveBars(),
          const SizedBox(height: IslandMetrics.space10),
        ],
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
