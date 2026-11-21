/// 一条日程。字段与 `protocol/README.md` 的 `ScheduleItem` 保持一致。
class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.title,
    required this.atMs,
    required this.fired,
    required this.createdAtMs,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      atMs: (json['atMs'] as num?)?.toInt() ?? 0,
      fired: json['fired'] == true,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final int atMs;
  final bool fired;
  final int createdAtMs;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(atMs);

  bool get isPast => atMs < DateTime.now().millisecondsSinceEpoch;
}

/// 日历按天分组时使用的本地日期键。
DateTime scheduleDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String scheduleDayKey(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String formatScheduleTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String formatScheduleDate(DateTime value) =>
    '${value.month} 月 ${value.day} 日 ${scheduleWeekday(value)}';

String formatScheduleIsoDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String scheduleWeekday(DateTime value) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][value.weekday - 1];
