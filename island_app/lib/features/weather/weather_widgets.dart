import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import 'weather_models.dart';

/// 收起态的时间右侧天气：图标 + 温度。
class WeatherChip extends StatelessWidget {
  const WeatherChip({super.key, required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          weatherIcon(snapshot.kind, snapshot.isDay),
          size: 15,
          color: weatherColor(colors, snapshot.kind),
        ),
        const SizedBox(width: 3),
        Text(
          '${snapshot.roundedTemp}°',
          style: TextStyle(
            color: colors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

IconData weatherIcon(WeatherKind kind, bool isDay) {
  switch (kind) {
    case WeatherKind.clear:
      return isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_outlined;
    case WeatherKind.partly:
      return Icons.wb_cloudy_outlined;
    case WeatherKind.cloudy:
      return Icons.cloud_outlined;
    case WeatherKind.fog:
      return Icons.foggy;
    case WeatherKind.drizzle:
      return Icons.grain;
    case WeatherKind.rain:
      return Icons.water_drop_outlined;
    case WeatherKind.snow:
      return Icons.ac_unit_outlined;
    case WeatherKind.thunder:
      return Icons.thunderstorm_outlined;
  }
}

Color weatherColor(IslandColors colors, WeatherKind kind) {
  switch (kind) {
    case WeatherKind.clear:
      return const Color(0xFFFFC857);
    case WeatherKind.partly:
      return const Color(0xFFE6D27A);
    case WeatherKind.cloudy:
    case WeatherKind.fog:
      return colors.muted;
    case WeatherKind.drizzle:
      return const Color(0xFF7EC8F0);
    case WeatherKind.rain:
      return colors.rain;
    case WeatherKind.snow:
      return const Color(0xFFB3E5FC);
    case WeatherKind.thunder:
      return const Color(0xFFFFD54F);
  }
}

String dayLabel(int index, String date) {
  if (index == 0) return '今天';
  if (index == 1) return '明天';
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return names[parsed.weekday - 1];
}

String clockText(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';
