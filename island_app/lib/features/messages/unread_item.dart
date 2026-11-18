/// 一条未读提醒，对应 sidecar 协议里的 `Unread`。
class UnreadItem {
  const UnreadItem({
    required this.id,
    required this.source,
    required this.account,
    required this.window,
    required this.count,
    required this.time,
    this.kind = 'taskbar',
    this.contact,
    this.preview,
  });

  factory UnreadItem.fromJson(Map<String, dynamic> json) {
    final source = json['source']?.toString() ?? 'wechat';
    final account = (json['account'] as num?)?.toInt() ?? 0;
    final time = json['time']?.toString() ?? '';
    return UnreadItem(
      id: json['id']?.toString() ?? '$source:$account:$time',
      source: source,
      account: account,
      window: (json['window'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 1,
      time: time,
      kind: json['kind']?.toString() ?? 'taskbar',
      contact: json['contact']?.toString(),
      preview: json['preview']?.toString(),
    );
  }

  final String id;
  final String source;
  final int account;
  final int window;
  final int count;
  final String time;
  final String kind;
  final String? contact;
  final String? preview;

  String get sourceName => source == 'qq' ? 'QQ' : '微信';

  String get title {
    final name = contact?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return account > 0 ? '$sourceName · 账号 $account' : sourceName;
  }

  String get subtitle {
    final text = preview?.trim() ?? '';
    if (text.isNotEmpty) return text;
    return kind == 'toast' ? '$time · 新消息' : '$time · 第 $count 条提醒';
  }
}
