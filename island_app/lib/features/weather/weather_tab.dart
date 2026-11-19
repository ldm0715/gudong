import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import 'weather_controller.dart';
import 'weather_models.dart';
import 'weather_widgets.dart';

class WeatherTab extends StatelessWidget {
  const WeatherTab({super.key, required this.controller});

  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final snapshot = controller.snapshot;
    if (snapshot == null) return _EmptyWeather(status: controller.status);

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
              width: 52,
              child: Column(
                children: [
                  Icon(
                    weatherIcon(snapshot.kind, snapshot.isDay),
                    size: IslandMetrics.icon3XL,
                    color: weatherColor(colors, snapshot.kind),
                  ),
                  const SizedBox(height: IslandMetrics.space5),
                  Text(
                    snapshot.description,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.micro.tint(colors.muted),
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
