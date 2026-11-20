/// 邮件摘要，对应协议里的 `MailSummary`。
class MailSummary {
  const MailSummary({
    required this.id,
    required this.accountId,
    required this.from,
    required this.fromAddress,
    required this.subject,
    required this.receivedAt,
    required this.unread,
    required this.snippet,
    required this.hasAttachments,
  });

  factory MailSummary.fromJson(Map<String, dynamic> json) {
    final fromAddress = json['fromAddress']?.toString() ?? '';
    final from = (json['from']?.toString() ?? '').trim();
    final subject = (json['subject']?.toString() ?? '').trim();
    return MailSummary(
      id: json['id']?.toString() ?? '',
      accountId: json['accountId']?.toString() ?? '',
      from: from.isNotEmpty
          ? from
          : (fromAddress.isNotEmpty ? fromAddress : '未知发件人'),
      fromAddress: fromAddress,
      subject: subject.isNotEmpty ? subject : '（无主题）',
      receivedAt: (json['receivedAt'] as num?)?.toInt() ?? 0,
      unread: json['unread'] == true,
      snippet: json['snippet']?.toString() ?? '',
      hasAttachments: json['hasAttachments'] == true,
    );
  }

  final String id;
  final String accountId;
  final String from;
  final String fromAddress;
  final String subject;
  final int receivedAt;
  final bool unread;
  final String snippet;
  final bool hasAttachments;

  MailSummary copyWith({bool? unread}) => MailSummary(
    id: id,
    accountId: accountId,
    from: from,
    fromAddress: fromAddress,
    subject: subject,
    receivedAt: receivedAt,
    unread: unread ?? this.unread,
    snippet: snippet,
    hasAttachments: hasAttachments,
  );

  DateTime? get receivedTime => receivedAt > 0
      ? DateTime.fromMillisecondsSinceEpoch(receivedAt)
      : null;

  /// 当天显示时刻，更早的显示月日。
  String get timeLabel {
    final time = receivedTime;
    if (time == null) return '';
    final now = DateTime.now();
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return '$hh:$mm';
    }
    return '${time.month}-${time.day} $hh:$mm';
  }
}

/// 邮件详情：摘要在前，正文已经过 sidecar 纯文本化和截断。
class MailDetail {
  const MailDetail({
    required this.summary,
    required this.text,
    required this.truncated,
    required this.links,
  });

  factory MailDetail.fromJson(Map<String, dynamic> json) {
    final rawLinks = json['links'];
    final links = <MailLink>[];
    if (rawLinks is List) {
      for (final raw in rawLinks) {
        if (raw is Map<String, dynamic>) {
          final link = MailLink.fromJson(raw);
          if (link.url.isNotEmpty) links.add(link);
        }
      }
    }
    return MailDetail(
      summary: MailSummary.fromJson(json),
      text: json['text']?.toString() ?? '',
      truncated: json['truncated'] == true,
      links: links,
    );
  }

  final MailSummary summary;
  final String text;
  final bool truncated;
  final List<MailLink> links;
}

class MailLink {
  const MailLink({required this.label, required this.url});

  factory MailLink.fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString() ?? '';
    final label = (json['label']?.toString() ?? '').trim();
    return MailLink(label: label.isNotEmpty ? label : url, url: url);
  }

  final String label;
  final String url;
}

/// 邮箱账号，对应协议里的 `MailAccount`。
class MailAccount {
  const MailAccount({
    required this.id,
    required this.provider,
    required this.email,
    required this.label,
    required this.authType,
    required this.enabled,
    required this.webmailUrl,
    required this.state,
    required this.message,
    required this.lastSyncAt,
    required this.reauthRequired,
  });

  factory MailAccount.fromJson(Map<String, dynamic> json) {
    final label = json['label']?.toString().trim() ?? '';
    return MailAccount(
      id: json['id']?.toString() ?? '',
      provider: json['provider']?.toString() ?? 'custom',
      email: json['email']?.toString() ?? '',
      label: label.isEmpty ? null : label,
      authType: json['authType']?.toString() ?? 'password',
      enabled: json['enabled'] != false,
      webmailUrl: json['webmailUrl']?.toString() ?? '',
      state: json['state']?.toString() ?? 'idle',
      message: json['message']?.toString() ?? '',
      lastSyncAt: (json['lastSyncAt'] as num?)?.toInt(),
      reauthRequired: json['reauthRequired'] == true,
    );
  }

  final String id;
  final String provider;
  final String email;
  final String? label;
  final String authType;
  final bool enabled;
  final String webmailUrl;
  final String state;
  final String message;
  final int? lastSyncAt;
  final bool reauthRequired;

  bool get ready => state == 'ready';

  bool get needsAttention =>
      reauthRequired || state == 'auth' || state == 'failed';

  String get providerLabel => switch (provider) {
    'qq' => 'QQ 邮箱',
    '163' => '163 邮箱',
    '126' => '126 邮箱',
    'exmail' => '腾讯企业邮 / 学校邮箱',
    'icloud' => 'iCloud 邮箱',
    'gmail' => 'Gmail',
    'microsoft' => 'Outlook / Microsoft 365',
    _ => '自定义 IMAP',
  };

  String get stateLabel => switch (state) {
    'connecting' => '连接中',
    'ready' => '已连接',
    'auth' => '需要授权',
    'failed' => '连接失败',
    _ => '未连接',
  };

  String get displayName {
    final text = label?.trim() ?? '';
    if (text.isNotEmpty) return text;
    return email;
  }
}
