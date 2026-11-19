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
      'mediaEnabled': true,
      'showPlayingIndicator': true,
      'showImeIndicator': true,
      'showImeBanner': true,
      'tabOrder': [
        'messages',
        'translate',
        'weather',
        'media',
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
    });
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
      'translate',
      'weather',
      'diagnostics',
    ]);
    expect(settings.hiddenTabs, ['weather']);
    expect(settings.visibleTabs.map((tab) => tab.id), [
      'media',
      'messages',
      'translate',
      'diagnostics',
    ]);
  });

  test('allows every tab to be hidden', () {
    final settings = AppSettings.fromJson(const {
      'hiddenTabs': [
        'messages',
        'translate',
        'weather',
        'media',
        'diagnostics',
      ],
    });
    expect(settings.visibleTabs, isEmpty);
    expect(settings.hiddenTabs.length, 5);
  });
}
