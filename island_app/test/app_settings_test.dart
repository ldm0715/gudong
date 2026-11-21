import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/core/settings/app_settings.dart';

void main() {
  test('uses defaults for an empty config', () {
    final settings = AppSettings.fromJson(const {});
    expect(settings.themeId, 'midnight');
    expect(settings.showWeather, isTrue);
    expect(settings.dockSide, 'top');
    expect(settings.dockOffset, isNull);
  });

  test('parses and serializes persisted values', () {
    final settings = AppSettings.fromJson(const {
      'themeId': 'light',
      'showWeather': false,
      'dockSide': 'left',
      'dockOffset': 420.5,
    });
    expect(settings.themeId, 'light');
    expect(settings.showWeather, isFalse);
    expect(settings.dockSide, 'left');
    expect(settings.dockOffset, 420.5);
    expect(settings.toJson(), {
      'themeId': 'light',
      'showWeather': false,
      'weatherLocationMode': 'auto',
      'weatherLocationName': '',
      'mediaEnabled': true,
      'showPlayingIndicator': true,
      'showImeIndicator': true,
      'showImeBanner': true,
      'tabOrder': [
        'messages',
        'mail',
        'translate',
        'weather',
        'media',
        'quota',
        'diagnostics',
      ],
      'hiddenTabs': <String>[],
      'dockSide': 'left',
      'dockOffset': 420.5,
      'translateProvider': 'auto',
      'translateBaseUrl': 'https://api.openai.com/v1',
      'translateModel': '',
      'translateTarget': 'zh-CN',
      'translateSource': 'auto',
      'translateAutoOrder': [
        'llm',
        'deepl',
        'caiyun',
        'microsoftFree',
        'mymemory',
      ],
      'translateUserPrompt': '',
      'translateSystemPrompt': '',
      'translateMyMemoryEmail': '',
      'mailPollSeconds': 180,
      'mailTranslateProvider': 'auto',
      'quotaOrder': ['glm', 'deepseek', 'opencode'],
      'hiddenQuotaProviders': <String>[],
      'quotaGlmRegion': 'global',
    });
  });

  test('parses and serializes a manual weather location', () {
    final settings = AppSettings.fromJson(const {
      'weatherLocationMode': 'manual',
      'weatherLocationName': '广州 · 广东省 · 中国',
      'weatherLatitude': 23.11667,
      'weatherLongitude': 113.25,
    });
    expect(settings.weatherLocationMode, 'manual');
    expect(settings.weatherLocationName, '广州 · 广东省 · 中国');
    expect(settings.weatherLatitude, 23.11667);
    expect(settings.weatherLongitude, 113.25);
    final json = settings.toJson();
    expect(json['weatherLocationMode'], 'manual');
    expect(json['weatherLatitude'], 23.11667);
    expect(json['weatherLongitude'], 113.25);
  });

  test('falls back to auto for unknown weather location modes', () {
    final settings = AppSettings.fromJson(const {'weatherLocationMode': 'ip'});
    expect(settings.weatherLocationMode, 'auto');
  });

  test('falls back to the top edge for unknown dock sides', () {
    final settings = AppSettings.fromJson(const {'dockSide': 'bottom'});
    expect(settings.dockSide, 'top');
  });

  test('copyWith keeps unspecified fields', () {
    const settings = AppSettings(dockSide: 'right', dockOffset: 20);
    final next = settings.copyWith(themeId: 'light');
    expect(next.themeId, 'light');
    expect(next.dockSide, 'right');
    expect(next.dockOffset, 20);
  });

  test('normalizes unknown and missing tab ids', () {
    final settings = AppSettings.fromJson(const {
      'tabOrder': ['media', 'unknown', 'media', 'messages'],
      'hiddenTabs': ['weather', 'nope'],
    });
    expect(settings.tabOrder, [
      'media',
      'messages',
      'mail',
      'translate',
      'weather',
      'quota',
      'diagnostics',
    ]);
    expect(settings.hiddenTabs, ['weather']);
    expect(settings.visibleTabs.map((tab) => tab.id), [
      'media',
      'messages',
      'mail',
      'translate',
      'quota',
      'diagnostics',
    ]);
  });

  test('allows every tab to be hidden', () {
    final settings = AppSettings.fromJson(const {
      'hiddenTabs': [
        'messages',
        'mail',
        'translate',
        'weather',
        'media',
        'quota',
        'diagnostics',
      ],
    });
    expect(settings.visibleTabs, isEmpty);
    expect(settings.hiddenTabs.length, 7);
  });

  test('clamps the mail poll interval to the protocol range', () {
    expect(AppSettings.fromJson(const {'mailPollSeconds': 5}).mailPollSeconds, 60);
    expect(
      AppSettings.fromJson(const {'mailPollSeconds': 5000}).mailPollSeconds,
      900,
    );
    expect(
      AppSettings.fromJson(const {'mailPollSeconds': 120}).mailPollSeconds,
      120,
    );
  });
}
