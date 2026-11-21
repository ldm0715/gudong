import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/features/quota/quota_models.dart';

void main() {
  test('parses a quota provider and picks the 5-hour window', () {
    final provider = QuotaProvider.fromJson(const {
      'id': 'glm',
      'label': 'GLM',
      'status': 'ok',
      'plan': 'GLM Coding Pro',
      'windows': [
        {
          'kind': 'session',
          'label': '5-hour',
          'usedPercent': 32.4,
          'windowMinutes': 300,
          'resetsAtMs': 1795000000000,
          'showMeter': true,
        },
        {
          'kind': 'weekly',
          'label': 'Weekly',
          'usedPercent': 18.0,
          'windowMinutes': 10080,
          'showMeter': true,
        },
      ],
    });
    expect(provider.ok, isTrue);
    expect(provider.shortLabel, 'GLM');
    expect(provider.sessionWindow?.usedPercent, 32.4);
    expect(
      provider.sessionWindow?.effectiveRemainingPercent,
      closeTo(67.6, 0.001),
    );
    expect(provider.secondaryWindow?.kind, 'weekly');
    expect(formatPercent(32.4), '32%');
  });

  test('formats balance windows with the window currency', () {
    final window = QuotaWindow.fromJson(const {
      'kind': 'billing',
      'label': 'Balance',
      'remaining': 12.5,
      'currency': 'CNY',
      'showMeter': false,
    });
    expect(window.hasMeter, isFalse);
    expect(formatBalance(window), '¥12.50');
  });

  test('renders a compact reset countdown', () {
    final now = DateTime(2026, 11, 20, 12);
    expect(
      formatReset(now.add(const Duration(hours: 3, minutes: 20)), now: now),
      '3 小时 20 分',
    );
    expect(
      formatReset(now.subtract(const Duration(minutes: 1)), now: now),
      '即将重置',
    );
  });
}
