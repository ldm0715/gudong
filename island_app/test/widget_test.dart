import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/features/island/island_controller.dart';

void main() {
  test('parses a message.unread event', () {
    final item = UnreadItem.fromJson({
      'type': 'message.unread',
      'source': 'wechat',
      'account': 4321,
      'window': 9876,
      'count': 3,
      'time': '12:34:56',
    });
    expect(item.source, 'wechat');
    expect(item.account, 4321);
    expect(item.window, 9876);
    expect(item.count, 3);
    expect(item.time, '12:34:56');
  });

  test('falls back to safe defaults', () {
    final item = UnreadItem.fromJson({'account': 1});
    expect(item.source, 'wechat');
    expect(item.count, 1);
    expect(item.time, '');
  });
}
