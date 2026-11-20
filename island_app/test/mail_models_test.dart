import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/features/mail/mail_models.dart';

void main() {
  test('parses a mail summary and falls back for missing fields', () {
    final item = MailSummary.fromJson({
      'id': 'mail:m_1:7:42',
      'accountId': 'm_1',
      'fromAddress': 'sender@example.com',
      'subject': '',
      'receivedAt': 1794997775244,
      'unread': true,
      'snippet': '正文片段',
      'hasAttachments': true,
    });
    expect(item.id, 'mail:m_1:7:42');
    expect(item.accountId, 'm_1');
    expect(item.from, 'sender@example.com');
    expect(item.subject, '（无主题）');
    expect(item.unread, isTrue);
    expect(item.hasAttachments, isTrue);
    expect(item.timeLabel, isNotEmpty);
  });

  test('parses detail body and keeps only valid links', () {
    final detail = MailDetail.fromJson({
      'id': 'mail:m_1:7:42',
      'accountId': 'm_1',
      'from': '张三',
      'fromAddress': 'a@example.com',
      'subject': '项目进度',
      'receivedAt': 1794997775244,
      'unread': false,
      'snippet': '本周',
      'hasAttachments': false,
      'text': '本周的进度是……',
      'truncated': true,
      'links': [
        {'label': '详情', 'url': 'https://example.com/detail'},
        {'label': '空链接', 'url': ''},
      ],
    });
    expect(detail.summary.subject, '项目进度');
    expect(detail.text, '本周的进度是……');
    expect(detail.truncated, isTrue);
    expect(detail.links.length, 1);
    expect(detail.links.first.label, '详情');
  });

  test('maps account state and provider labels', () {
    final account = MailAccount.fromJson({
      'id': 'm_1',
      'provider': 'qq',
      'email': 'a@qq.com',
      'label': '工作',
      'authType': 'password',
      'enabled': true,
      'webmailUrl': 'https://mail.qq.com/',
      'state': 'auth',
      'message': '登录被拒绝',
      'reauthRequired': true,
    });
    expect(account.providerLabel, 'QQ 邮箱');
    expect(account.displayName, '工作');
    expect(account.stateLabel, '需要授权');
    expect(account.needsAttention, isTrue);
    expect(account.ready, isFalse);
  });
}
