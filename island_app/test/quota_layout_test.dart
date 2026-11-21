import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/features/quota/quota_models.dart';
import 'package:island_app/features/quota/quota_tab.dart';

QuotaProvider _provider({String id = 'glm'}) => QuotaProvider.fromJson({
  'id': id,
  'label': id == 'deepseek' ? 'DeepSeek' : 'GLM',
  'status': 'ok',
  'plan': 'GLM Coding Pro',
  'windows': [
    {
      'kind': 'session',
      'label': '5-hour',
      'usedPercent': 32.4,
      'remainingPercent': 67.6,
      'windowMinutes': 300,
      'resetsAtMs': 1795000000000,
      'showMeter': true,
    },
    {
      'kind': 'weekly',
      'label': 'Weekly',
      'usedPercent': 18.0,
      'remainingPercent': 82.0,
      'windowMinutes': 10080,
      'showMeter': true,
    },
    {
      'kind': 'billing',
      'label': 'Balance',
      'remaining': 12.5,
      'currency': 'CNY',
      'showMeter': false,
    },
  ],
});

void main() {
  testWidgets('quota cards render every window inside a scrollable list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 352,
          height: 182,
          child: ListView(
            children: [
              for (var index = 0; index < 3; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: QuotaProviderCard(provider: _provider()),
                ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('5小时'), findsWidgets);
    expect(find.text('本周'), findsWidgets);
    expect(find.text('余额'), findsWidgets);
  });

  testWidgets('linear quota meter fills its full height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            child: LinearQuotaMeter(
              value: 0.5,
              color: Color(0xFF2ED573),
              thickness: 6,
            ),
          ),
        ),
      ),
    );
    final boxes = find
        .descendant(
          of: find.byType(LinearQuotaMeter),
          matching: find.byType(ColoredBox),
        )
        .evaluate()
        .toList();
    expect(boxes.length, 2);
    for (final box in boxes) {
      expect((box.renderObject as RenderBox).size.height, 6);
    }
  });

  testWidgets('a single quota card sizes to its content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: QuotaProviderCard(provider: _provider(id: 'deepseek')),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
