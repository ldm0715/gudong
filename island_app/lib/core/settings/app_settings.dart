/// 用户设置。持久化由 sidecar 负责，字段名与 config.json 保持一致。
class AppSettings {
  const AppSettings({
    this.themeId = 'midnight',
    this.showWeather = true,
    this.windowX,
    this.windowY,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeId: json['themeId']?.toString() ?? 'midnight',
      showWeather: json['showWeather'] != false,
      windowX: (json['windowX'] as num?)?.toDouble(),
      windowY: (json['windowY'] as num?)?.toDouble(),
    );
  }

  final String themeId;
  final bool showWeather;
  final double? windowX;
  final double? windowY;

  Map<String, dynamic> toJson() => {
    'themeId': themeId,
    'showWeather': showWeather,
    if (windowX != null) 'windowX': windowX,
    if (windowY != null) 'windowY': windowY,
  };

  AppSettings copyWith({
    String? themeId,
    bool? showWeather,
    double? windowX,
    double? windowY,
  }) {
    return AppSettings(
      themeId: themeId ?? this.themeId,
      showWeather: showWeather ?? this.showWeather,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
    );
  }
}
