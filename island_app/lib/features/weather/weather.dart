/// 天气现象的粗分类，决定显示哪个图标。
enum WeatherKind { clear, partly, cloudy, fog, drizzle, rain, snow, thunder }

WeatherKind weatherKindFromString(String? value) {
  switch (value) {
    case 'clear':
      return WeatherKind.clear;
    case 'partly':
      return WeatherKind.partly;
    case 'cloudy':
      return WeatherKind.cloudy;
    case 'fog':
      return WeatherKind.fog;
    case 'drizzle':
      return WeatherKind.drizzle;
    case 'rain':
      return WeatherKind.rain;
    case 'snow':
      return WeatherKind.snow;
    case 'thunder':
      return WeatherKind.thunder;
    default:
      return WeatherKind.cloudy;
  }
}

class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.kind,
    required this.description,
    required this.highC,
    required this.lowC,
    this.precipProbability,
  });

  factory WeatherDay.fromJson(Map<String, dynamic> json) {
    return WeatherDay(
      date: json['date']?.toString() ?? '',
      kind: weatherKindFromString(json['kind']?.toString()),
      description: json['description']?.toString() ?? '',
      highC: (json['high_c'] as num?)?.toDouble() ?? 0,
      lowC: (json['low_c'] as num?)?.toDouble() ?? 0,
      precipProbability: (json['precip_probability'] as num?)?.toInt(),
    );
  }

  final String date;
  final WeatherKind kind;
  final String description;
  final double highC;
  final double lowC;
  final int? precipProbability;
}

/// sidecar 推送的当前实况与短期预报。抓取与解析都在 Rust 侧完成。
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.place,
    required this.tempC,
    required this.kind,
    required this.description,
    required this.isDay,
    required this.updatedAt,
    required this.days,
    this.feelsLikeC,
    this.humidity,
    this.windKph,
    this.highC,
    this.lowC,
  });

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    return WeatherSnapshot(
      place: json['place']?.toString() ?? '',
      tempC: (json['temp_c'] as num?)?.toDouble() ?? 0,
      kind: weatherKindFromString(json['kind']?.toString()),
      description: json['description']?.toString() ?? '',
      isDay: json['is_day'] == true,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updated_at_ms'] as num?)?.toInt() ?? 0,
      ),
      feelsLikeC: (json['feels_like_c'] as num?)?.toDouble(),
      humidity: (json['humidity'] as num?)?.toInt(),
      windKph: (json['wind_kph'] as num?)?.toDouble(),
      highC: (json['high_c'] as num?)?.toDouble(),
      lowC: (json['low_c'] as num?)?.toDouble(),
      days:
          (json['days'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(WeatherDay.fromJson)
              .toList(growable: false) ??
          const [],
    );
  }

  final String place;
  final double tempC;
  final WeatherKind kind;
  final String description;
  final bool isDay;
  final DateTime updatedAt;
  final double? feelsLikeC;
  final int? humidity;
  final double? windKph;
  final double? highC;
  final double? lowC;
  final List<WeatherDay> days;

  int get roundedTemp => tempC.round();
}
