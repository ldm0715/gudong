import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/features/schedule/alarm_models.dart';

AlarmItem _alarm(
  String id,
  int hour,
  int minute,
  List<int> days, {
  bool enabled = true,
}) => AlarmItem(
  id: id,
  title: id,
  hour: hour,
  minute: minute,
  days: days,
  enabled: enabled,
  createdAtMs: 0,
);

void main() {
  test('parses an alarm and normalizes days', () {
    final item = AlarmItem.fromJson(const {
      'id': 'al_1',
      'title': '喝水',
      'hour': 9,
      'minute': 5,
      'days': [5, 1, 1, 9],
      'enabled': false,
      'createdAtMs': 1,
    });
    expect(item.timeLabel, '09:05');
    expect(item.days, [1, 5]);
    expect(item.enabled, isFalse);
  });

  test('formats day sets', () {
    expect(formatAlarmDays([1, 2, 3, 4, 5, 6, 7]), '每天');
    expect(formatAlarmDays([1, 2, 3, 4, 5]), '工作日');
    expect(formatAlarmDays([6, 7]), '周末');
    expect(formatAlarmDays([1, 3, 5]), '周一 周三 周五');
    expect(formatAlarmDays([]), '未设置');
  });

  test('finds the next enabled alarm', () {
    // 2026-11-23 是周一。
    final now = DateTime(2026, 11, 23, 9, 0);
    final items = [
      _alarm('a', 10, 0, [1]),
      _alarm('b', 8, 0, [1]),
      _alarm('c', 9, 30, [3]),
      _alarm('d', 9, 15, [1], enabled: false),
    ];
    final next = nextAlarmAt(items, now: now);
    expect(next, DateTime(2026, 11, 23, 10, 0));
    expect(formatNextAlarm(next!, now: now), '今天 10:00');
  });

  test('formats upcoming alarm times', () {
    final now = DateTime(2026, 11, 23, 9, 0);
    expect(
      formatNextAlarm(DateTime(2026, 11, 24, 8, 0), now: now),
      '明天 08:00',
    );
    expect(
      formatNextAlarm(DateTime(2026, 11, 25, 9, 0), now: now),
      '周三 09:00',
    );
    expect(
      formatNextAlarm(DateTime(2026, 12, 1, 9, 0), now: now),
      '12 月 1 日 09:00',
    );
  });

  test('returns null when no alarm is enabled', () {
    final now = DateTime(2026, 11, 23, 9, 0);
    expect(
      nextAlarmAt([_alarm('a', 10, 0, [1], enabled: false)], now: now),
      isNull,
    );
  });
}
