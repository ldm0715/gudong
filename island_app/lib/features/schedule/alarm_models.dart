/// 一条每日闹钟。字段与 `protocol/README.md` 的 `AlarmItem` 一致。
class AlarmItem {
  const AlarmItem({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    required this.days,
    required this.enabled,
    required this.createdAtMs,
  });

  factory AlarmItem.fromJson(Map<String, dynamic> json) {
    final days = <int>[];
    final raw = json['days'];
    if (raw is List) {
      for (final value in raw) {
        final day = value is num
            ? value.toInt()
            : int.tryParse(value.toString());
        if (day != null && day >= 1 && day <= 7 && !days.contains(day)) {
          days.add(day);
        }
      }
    }
    days.sort();
    return AlarmItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      days: days,
      enabled: json['enabled'] != false,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final int hour;
  final int minute;

  /// ISO 星期：1 = 周一，7 = 周日。
  final List<int> days;
  final bool enabled;
  final int createdAtMs;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get daysLabel => formatAlarmDays(days);
}

const List<String> alarmWeekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 把星期集合压缩成可读文案：每天 / 工作日 / 周末 / 周一 周三 周五。
String formatAlarmDays(List<int> days) {
  final sorted = days.where((day) => day >= 1 && day <= 7).toSet().toList()
    ..sort();
  if (sorted.isEmpty) return '未设置';
  if (sorted.length == 7) return '每天';
  if (sorted.length == 5 && sorted.every((day) => day <= 5)) return '工作日';
  if (sorted.length == 2 && sorted[0] == 6 && sorted[1] == 7) return '周末';
  return sorted.map((day) => '周${alarmWeekdayNames[day - 1]}').join(' ');
}

/// 已启用闹钟中最近的一次触发时间；没有启用的闹钟时返回 null。
DateTime? nextAlarmAt(List<AlarmItem> items, {DateTime? now}) {
  final current = now ?? DateTime.now();
  DateTime? next;
  for (final item in items) {
    if (!item.enabled) continue;
    for (final day in item.days) {
      if (day < 1 || day > 7) continue;
      final delta = (day - current.weekday) % 7;
      var candidate = DateTime(
        current.year,
        current.month,
        current.day + delta,
        item.hour,
        item.minute,
      );
      // 今天的时间已经过去时顺延到下周同一天。
      if (!candidate.isAfter(current)) {
        candidate = DateTime(
          current.year,
          current.month,
          current.day + delta + 7,
          item.hour,
          item.minute,
        );
      }
      if (next == null || candidate.isBefore(next)) next = candidate;
    }
  }
  return next;
}

/// 下次响铃时间：今天 / 明天 / 周几 + HH:mm，超过一周显示日期。
String formatNextAlarm(DateTime next, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final target = DateTime(next.year, next.month, next.day);
  final days = target.difference(today).inDays;
  final time =
      '${next.hour.toString().padLeft(2, '0')}:'
      '${next.minute.toString().padLeft(2, '0')}';
  if (days <= 0) return '今天 $time';
  if (days == 1) return '明天 $time';
  if (days < 7) return '周${alarmWeekdayNames[next.weekday - 1]} $time';
  return '${next.month} 月 ${next.day} 日 $time';
}
