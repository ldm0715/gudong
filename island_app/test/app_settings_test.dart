import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/core/settings/app_settings.dart';

void main() {
  test('uses defaults for an empty config', () {
    final settings = AppSettings.fromJson(const {});
    expect(settings.themeId, 'midnight');
    expect(settings.showWeather, isTrue);
    expect(settings.windowX, isNull);
    expect(settings.windowY, isNull);
  });

  test('parses and serializes persisted values', () {
    final settings = AppSettings.fromJson(const {
      'themeId': 'light',
      'showWeather': false,
      'windowX': 120.5,
      'windowY': 8.0,
    });
    expect(settings.themeId, 'light');
    expect(settings.showWeather, isFalse);
    expect(settings.windowX, 120.5);
    expect(settings.windowY, 8.0);
    expect(settings.toJson(), {
      'themeId': 'light',
      'showWeather': false,
      'windowX': 120.5,
      'windowY': 8.0,
    });
  });

  test('copyWith keeps unspecified fields', () {
    const settings = AppSettings(windowX: 10, windowY: 20);
    final next = settings.copyWith(themeId: 'light');
    expect(next.themeId, 'light');
    expect(next.windowX, 10);
    expect(next.windowY, 20);
  });
}
