/// 额度快照。字段与 `protocol/README.md` 的 `QuotaProvider` 保持一致。
class QuotaWindow {
  const QuotaWindow({
    required this.kind,
    required this.label,
    this.usedPercent,
    this.remainingPercent,
    this.windowMinutes,
    this.resetsAtMs,
    this.remaining,
    this.currency,
    this.showMeter = true,
  });

  factory QuotaWindow.fromJson(Map<String, dynamic> json) {
    return QuotaWindow(
      kind: json['kind']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      usedPercent: (json['usedPercent'] as num?)?.toDouble(),
      remainingPercent: (json['remainingPercent'] as num?)?.toDouble(),
      windowMinutes: (json['windowMinutes'] as num?)?.toInt(),
      resetsAtMs: (json['resetsAtMs'] as num?)?.toInt(),
      remaining: (json['remaining'] as num?)?.toDouble(),
      currency: json['currency']?.toString(),
      showMeter: json['showMeter'] != false,
    );
  }

  final String kind;
  final String label;
  final double? usedPercent;
  final double? remainingPercent;
  final int? windowMinutes;
  final int? resetsAtMs;
  final double? remaining;
  final String? currency;
  final bool showMeter;

  bool get isSession => kind == 'session';
  bool get isBilling => kind == 'billing';

  DateTime? get resetsAt => resetsAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(resetsAtMs!);

  /// 有百分比才画进度条；余额这类没有分母的窗口只显示数值。
  bool get hasMeter => showMeter && usedPercent != null;

  /// 剩余比例。服务端没给 `remainingPercent` 时用已用比例反推。
  double? get effectiveRemainingPercent =>
      remainingPercent ?? (usedPercent == null ? null : 100 - usedPercent!);

  /// 按剩余额度填充，读起来像电池电量。
  double get remainingValue =>
      ((effectiveRemainingPercent ?? 0) / 100).clamp(0.0, 1.0);
}

class QuotaProvider {
  const QuotaProvider({
    required this.id,
    required this.label,
    required this.status,
    this.plan,
    this.windows = const [],
    this.message,
    this.logo,
    this.updatedAtMs,
  });

  factory QuotaProvider.fromJson(Map<String, dynamic> json) {
    final windows = <QuotaWindow>[];
    final raw = json['windows'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          windows.add(QuotaWindow.fromJson(item));
        }
      }
    }
    return QuotaProvider(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unavailable',
      plan: json['plan']?.toString(),
      windows: windows,
      message: json['message']?.toString(),
      logo: json['logo']?.toString(),
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt(),
    );
  }

  final String id;
  final String label;
  final String status;
  final String? plan;
  final List<QuotaWindow> windows;
  final String? message;
  final String? logo;
  final int? updatedAtMs;

  /// 收起态用的短名，避免挤占时间与天气。
  String get shortLabel => switch (id) {
    'glm' => 'GLM',
    'deepseek' => 'DS',
    'opencode' => 'OC',
    _ when id.startsWith('newapi:') => 'NA',
    _ => label,
  };

  bool get ok => status == 'ok';
  bool get configured => status != 'notConfigured';

  QuotaWindow? get sessionWindow {
    for (final window in windows) {
      if (window.isSession && window.usedPercent != null) return window;
    }
    return null;
  }

  QuotaWindow? get secondaryWindow {
    for (final window in windows) {
      if (window.kind == 'weekly') return window;
    }
    for (final window in windows) {
      if (window.kind == 'monthly') return window;
    }
    for (final window in windows) {
      if (window.isBilling) return window;
    }
    return null;
  }

  QuotaWindow? get balanceWindow {
    for (final window in windows) {
      if (window.isBilling) return window;
    }
    return null;
  }

  String get statusLabel => switch (status) {
    'notConfigured' => '未配置',
    'unauthorized' => '凭据失效',
    'rateLimited' => '请求受限',
    'unavailable' => '暂时不可用',
    _ => '等待更新',
  };
}

String formatBalance(QuotaWindow window) {
  final amount = window.remaining;
  if (amount == null) return '--';
  final symbol = switch (window.currency) {
    'USD' || r'$' => r'$',
    'CNY' || '¥' => '¥',
    null || '' => '',
    final code => code.length <= 2 ? code : '$code ',
  };
  // 没有货币单位时是站点原始配额，按整数显示更易读。
  final digits = (window.currency == null || window.currency!.isEmpty) ? 0 : 2;
  return '$symbol${amount.toStringAsFixed(digits)}';
}

String formatPercent(double? percent) {
  if (percent == null) return '--';
  final rounded = percent.round();
  return '$rounded%';
}

/// 最近刷新时间。一小时内显示相对时间，更久显示日期。
String formatUpdatedAt(int? millis, {DateTime? now}) {
  if (millis == null || millis <= 0) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(millis);
  final current = now ?? DateTime.now();
  final diff = current.difference(at);
  if (diff.isNegative || diff.inSeconds < 60) return '刚刚更新';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  final hour = at.hour.toString().padLeft(2, '0');
  final minute = at.minute.toString().padLeft(2, '0');
  return '${at.month}-${at.day} $hour:$minute';
}

/// 重置倒计时只保留最有用的粒度，避免每帧重排。
String formatReset(DateTime? reset, {DateTime? now}) {
  if (reset == null) return '';
  final diff = reset.difference(now ?? DateTime.now());
  if (diff.isNegative) return '即将重置';
  if (diff.inMinutes < 1) return '<1 分钟';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟';
  if (diff.inDays < 1) {
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分';
  }
  return '${diff.inDays} 天';
}
