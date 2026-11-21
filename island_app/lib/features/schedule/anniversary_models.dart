/// 一条倒计时 / 纪念日。字段与 `protocol/README.md` 的 `AnniversaryItem` 一致。
class AnniversaryItem {
  const AnniversaryItem({
    required this.id,
    required this.title,
    required this.date,
    required this.createdAtMs,
  });

  factory AnniversaryItem.fromJson(Map<String, dynamic> json) {
    return AnniversaryItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;

  /// 本地日期，格式 `YYYY-MM-DD`。
  final String date;
  final int createdAtMs;

  DateTime? get localDate => parseAnniversaryDate(date);

  /// 正数为还剩天数，负数为已经过去的天数，今天为 0。
  int daysFrom(DateTime now) {
    final target = localDate;
    if (target == null) return 0;
    return anniversaryDays(target, now);
  }
}

DateTime? parseAnniversaryDate(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

String formatAnniversaryIsoDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String formatAnniversaryDate(DateTime value) =>
    '${value.year} 年 ${value.month} 月 ${value.day} 日';

/// 按 UTC 日历日计算，避免夏令时导致跨天误差。
int anniversaryDays(DateTime date, DateTime now) {
  final target = DateTime.utc(date.year, date.month, date.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  return target.difference(today).inDays;
}
