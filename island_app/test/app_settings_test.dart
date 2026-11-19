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
      'mediaEnabled': true,
      'showPlayingIndicator': true,
      'tabOrder': ['messages', 'weather', 'media', 'diagnostics'],
      'hiddenTabs': <String>[],
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

  test('normalizes unknown and missing tab ids', () {
    final settings = AppSettings.fromJson(const {
      'tabOrder': ['media', 'unknown', 'media', 'messages'],
      'hiddenTabs': ['weather', 'nope'],
    });
    expect(settings.tabOrder, [
      'media',
      'messages',
      'weather',
      'diagnostics',
    ]);
    expect(settings.hiddenTabs, ['weather']);
    expect(settings.visibleTabs.map((tab) => tab.id), [
      'media',
      'messages',
      'diagnostics',
    ]);
  });

  test('allows every tab to be hidden', () {
    final settings = AppSettings.fromJson(const {
      'hiddenTabs': ['messages', 'weather', 'media', 'diagnostics'],
    });
    expect(settings.visibleTabs, isEmpty);
    expect(settings.hiddenTabs.length, 4);
  });
}
