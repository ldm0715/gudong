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

/// 地点搜索结果，由 sidecar 调用地理编码接口返回。
class WeatherPlace {
  const WeatherPlace({
    required this.name,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.admin,
    this.country,
  });

  factory WeatherPlace.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    return WeatherPlace(
      name: name,
      label: json['label']?.toString() ?? name,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      admin: json['admin']?.toString(),
      country: json['country']?.toString(),
    );
  }

  final String name;
  final String label;
  final double latitude;
  final double longitude;
  final String? admin;
  final String? country;

  /// 副标题，跳过与名称重复的行政区。
  String get detail => [
    if (admin != null && admin != name) admin!,
    if (country != null && country != name) country!,
  ].join(' · ');
}

/// 逐时预报，从当前小时开始。
class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.tempC,
    required this.kind,
    required this.description,
    required this.isDay,
    this.precipProbability,
    this.feelsLikeC,
  });

  factory WeatherHour.fromJson(Map<String, dynamic> json) {
    return WeatherHour(
      time: json['time']?.toString() ?? '',
      tempC: (json['temp_c'] as num?)?.toDouble() ?? 0,
      kind: weatherKindFromString(json['kind']?.toString()),
      description: json['description']?.toString() ?? '',
      isDay: json['is_day'] == true,
      precipProbability: (json['precip_probability'] as num?)?.toInt(),
      feelsLikeC: (json['feels_like_c'] as num?)?.toDouble(),
    );
  }

  final String time;
  final double tempC;
  final WeatherKind kind;
  final String description;
  final bool isDay;
  final int? precipProbability;
  final double? feelsLikeC;

  int get roundedTemp => tempC.round();
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
    required this.hours,
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
      hours:
          (json['hours'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(WeatherHour.fromJson)
              .toList(growable: false) ??
          const [],
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
  final List<WeatherHour> hours;
  final List<WeatherDay> days;

  int get roundedTemp => tempC.round();
}
