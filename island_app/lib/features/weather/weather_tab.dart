import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import 'weather_controller.dart';
import 'weather_models.dart';
import 'weather_widgets.dart';

/// 天气页：第一页保持原有布局，第二页为 24 小时预报；点击左右边缘切换整页。
class WeatherTab extends StatefulWidget {
  const WeatherTab({super.key, required this.controller});

  final WeatherController controller;

  @override
  State<WeatherTab> createState() => _WeatherTabState();
}

class _WeatherTabState extends State<WeatherTab> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    if (snapshot == null) {
      return _EmptyWeather(status: widget.controller.status);
    }

    final pages = snapshot.hours.isEmpty ? 1 : 2;
    final page = math.min(_page, pages - 1);

    final showArrows = pages > 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showArrows)
          SizedBox(
            width: IslandMetrics.iconSM,
            child: _PageEdgeButton(
              icon: Icons.chevron_left_rounded,
              tooltip: '上一页',
              enabled: page > 0,
              onTap: () => setState(() => _page = page - 1),
            ),
          ),
        Expanded(
          child: page == 0
              ? _CurrentWeatherPage(snapshot: snapshot)
              : _HourlyPage(hours: snapshot.hours),
        ),
        if (showArrows)
          SizedBox(
            width: IslandMetrics.iconSM,
            child: _PageEdgeButton(
              icon: Icons.chevron_right_rounded,
              tooltip: '下一页',
              enabled: page < pages - 1,
              onTap: () => setState(() => _page = page + 1),
            ),
          ),
      ],
    );
  }
}

class _EmptyWeather extends StatelessWidget {
  const _EmptyWeather({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: IslandMetrics.icon2XL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space8),
          Text('天气暂时取不到', style: IslandTypography.subhead.tint(colors.text)),
          const SizedBox(height: IslandMetrics.space4),
          Text(status, style: IslandTypography.caption.tint(colors.muted)),
        ],
      ),
    );
  }
}

/// 左右边缘的翻页热区，覆盖天气内容高度。
class _PageEdgeButton extends StatelessWidget {
  const _PageEdgeButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final color = enabled ? colors.muted : colors.muted.withValues(alpha: 0.25);
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        waitDuration: IslandMotion.tooltipDelay,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Center(
              child: Icon(icon, size: IslandMetrics.iconSM, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// 第一页：保持原有的实时天气、体感指标与 5 天预报。
class _CurrentWeatherPage extends StatelessWidget {
  const _CurrentWeatherPage({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final highLow = snapshot.highC != null && snapshot.lowC != null
        ? '${snapshot.highC!.round()}° / ${snapshot.lowC!.round()}°'
        : null;
    final summary = [
      snapshot.place.isEmpty ? '当地' : snapshot.place,
      ?highLow,
    ].join(' · ');
    final metrics = [
      if (snapshot.feelsLikeC != null) '体感 ${snapshot.feelsLikeC!.round()}°',
      if (snapshot.humidity != null) '湿度 ${snapshot.humidity}%',
      if (snapshot.windKph != null) '风 ${snapshot.windKph!.round()} km/h',
    ];
    final updated = snapshot.updatedAt.millisecondsSinceEpoch > 0
        ? clockText(snapshot.updatedAt)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Column(
                children: [
                  Icon(
                    weatherIcon(snapshot.kind, snapshot.isDay),
                    size: IslandMetrics.icon3XL,
                    color: weatherColor(colors, snapshot.kind),
                  ),
                  const SizedBox(height: IslandMetrics.space5),
                  // 单行定高，长描述按宽度等比缩小，避免撑高整行触发溢出。
                  SizedBox(
                    height: 12,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        snapshot.description,
                        maxLines: 1,
                        style: IslandTypography.micro.tint(colors.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: IslandMetrics.space10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${snapshot.roundedTemp}°',
                        style: IslandTypography.displayLarge.tint(colors.text),
                      ),
                      const Spacer(),
                      if (updated != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: IslandMetrics.space2,
                          ),
                          child: Text(
                            '$updated 更新',
                            style: IslandTypography.micro.tint(colors.muted),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: IslandMetrics.space7),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.caption.tint(colors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: IslandMetrics.space7),
        Divider(height: 1, color: colors.divider),
        if (metrics.isNotEmpty) ...[
          const SizedBox(height: IslandMetrics.space7),
          Row(
            children: [
              for (final metric in metrics)
                Expanded(
                  child: Text(
                    metric,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.micro.tint(colors.text),
                  ),
                ),
            ],
          ),
          const SizedBox(height: IslandMetrics.space7),
          Divider(height: 1, color: colors.divider),
        ],
        const SizedBox(height: IslandMetrics.space7),
        Expanded(
          child: snapshot.days.isEmpty
              ? Center(
                  child: Text(
                    '暂无预报',
                    style: IslandTypography.caption.tint(colors.muted),
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: IslandMetrics.space6,
                      horizontal: IslandMetrics.space2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(
                        IslandMetrics.radiusPill,
                      ),
                    ),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < snapshot.days.length;
                          index++
                        ) ...[
                          if (index > 0)
                            Container(
                              width: 1,
                              height: 40,
                              color: colors.divider,
                            ),
                          Expanded(
                            child: _WeatherDayCell(
                              day: snapshot.days[index],
                              index: index,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 第二页：整页 24 小时温度曲线。
class _HourlyPage extends StatelessWidget {
  const _HourlyPage({required this.hours});

  final List<WeatherHour> hours;

  /// 曲线与上下图标 / 时间行共用 8 个采样点，保证对齐。
  List<WeatherHour> get _stops {
    if (hours.length <= 8) return hours;
    final step = hours.length / 8;
    return List<WeatherHour>.generate(
      8,
      (index) => hours[math.min((index * step).floor(), hours.length - 1)],
      growable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final stops = _stops;
    final minTemp = hours.map((hour) => hour.tempC).reduce(math.min).round();
    final maxTemp = hours.map((hour) => hour.tempC).reduce(math.max).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 12,
          child: Row(
            children: [
              Text(
                '24 小时',
                style: IslandTypography.microStrong.tint(colors.accent),
              ),
              const Spacer(),
              Text(
                '最高 $maxTemp° · 最低 $minTemp°',
                style: IslandTypography.micro.tint(colors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: IslandMetrics.space4),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: IslandMetrics.space6,
              horizontal: IslandMetrics.space10,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(IslandMetrics.radiusPill),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      for (final hour in stops)
                        Expanded(
                          child: Center(
                            child: Icon(
                              weatherIcon(hour.kind, hour.isDay),
                              size: IslandMetrics.iconSM,
                              color: weatherColor(colors, hour.kind),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: IslandMetrics.space2),
                Expanded(
                  child: _HourlyChart(
                    temps: [for (final hour in stops) hour.tempC],
                    colors: colors,
                  ),
                ),
                SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      for (final hour in stops)
                        Expanded(
                          child: Text(
                            hour.time,
                            textAlign: TextAlign.center,
                            style: IslandTypography.micro.tint(colors.muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.temps, required this.colors});

  final List<double> temps;
  final IslandColors colors;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HourlyChartPainter(
          temps: temps,
          lineColor: colors.accent,
          labelStyle: IslandTypography.microStrong.tint(colors.text),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _HourlyChartPainter extends CustomPainter {
  _HourlyChartPainter({
    required this.temps,
    required this.lineColor,
    required this.labelStyle,
  });

  final List<double> temps;
  final Color lineColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (temps.isEmpty || size.isEmpty) return;

    final minTemp = temps.reduce(math.min);
    final maxTemp = temps.reduce(math.max);
    final span = maxTemp - minTemp;
    final low = span < 0.1 ? minTemp - 2 : minTemp;
    final high = span < 0.1 ? maxTemp + 2 : maxTemp;
    final top = IslandMetrics.space16;
    final bottom = size.height - IslandMetrics.space4;
    final xStep = size.width / temps.length;

    Offset pointAt(int index) {
      final x = (index + 0.5) * xStep;
      final ratio = (temps[index] - low) / (high - low);
      return Offset(x, bottom - ratio * (bottom - top));
    }

    final points = [
      for (var index = 0; index < temps.length; index++) pointAt(index),
    ];
    final path = _smoothPath(points);

    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.16),
            lineColor.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dotPaint = Paint()..color = lineColor;
    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(points[index], IslandMetrics.space2, dotPaint);
      final label = TextPainter(
        text: TextSpan(text: '${temps[index].round()}°', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          points[index].dx - label.width / 2,
          points[index].dy - label.height - IslandMetrics.space2,
        ),
      );
    }
  }

  /// Catmull-Rom 转三次贝塞尔，曲线经过每个采样点。
  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final p0 = points[index == 0 ? 0 : index - 1];
      final p1 = points[index];
      final p2 = points[index + 1];
      final p3 =
          points[index + 2 >= points.length ? points.length - 1 : index + 2];
      final cp1 = p1 + (p2 - p0) / 6;
      final cp2 = p2 - (p3 - p1) / 6;
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _HourlyChartPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.labelStyle != labelStyle ||
        !_sameTemps(oldDelegate.temps);
  }

  bool _sameTemps(List<double> other) {
    if (other.length != temps.length) return false;
    for (var index = 0; index < temps.length; index++) {
      if (other[index] != temps[index]) return false;
    }
    return true;
  }
}

class _WeatherDayCell extends StatelessWidget {
  const _WeatherDayCell({required this.day, required this.index});

  final WeatherDay day;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final rain = day.precipProbability;
    final showRain = rain != null && rain >= 20;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(
          height: 12,
          child: Center(
            child: Text(
              dayLabel(index, day.date),
              style: IslandTypography.micro.tint(colors.muted),
            ),
          ),
        ),
        const SizedBox(height: IslandMetrics.space3),
        SizedBox(
          height: 20,
          child: Center(
            child: Icon(
              weatherIcon(day.kind, true),
              size: IslandMetrics.iconLG,
              color: weatherColor(colors, day.kind),
            ),
          ),
        ),
        const SizedBox(height: IslandMetrics.space3),
        SizedBox(
          height: 14,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${day.highC.round()}° / ${day.lowC.round()}°',
                style: IslandTypography.microStrong.tint(colors.text),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 11,
          child: Center(
            child: Text(
              showRain ? '$rain%' : '',
              style: IslandTypography.micro.tint(colors.rain),
            ),
          ),
        ),
      ],
    );
  }
}
