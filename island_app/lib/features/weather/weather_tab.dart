import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
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
                    size: 30,
                    color: weatherColor(colors, snapshot.kind),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    snapshot.description,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 10,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${snapshot.roundedTemp}°',
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const Spacer(),
                      if (updated != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '$updated 更新',
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 9,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Divider(height: 1, color: colors.divider),
        if (metrics.isNotEmpty) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              for (final metric in metrics)
                Expanded(
                  child: Text(
                    metric,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 10,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Divider(height: 1, color: colors.divider),
        ],
        const SizedBox(height: 7),
        Expanded(
          child: snapshot.days.isEmpty
              ? Center(
                  child: Text(
                    '暂无预报',
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(10),
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
          Icon(Icons.cloud_off_rounded, size: 26, color: colors.muted),
          const SizedBox(height: 8),
          Text(
            '天气暂时取不到',
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: TextStyle(
              color: colors.muted,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
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
              style: TextStyle(
                color: colors.muted,
                fontSize: 10,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 20,
          child: Center(
            child: Icon(
              weatherIcon(day.kind, true),
              size: 18,
              color: weatherColor(colors, day.kind),
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 14,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${day.highC.round()}° / ${day.lowC.round()}°',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 11,
          child: Center(
            child: Text(
              showRain ? '$rain%' : '',
              style: TextStyle(
                color: colors.rain,
                fontSize: 9,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
