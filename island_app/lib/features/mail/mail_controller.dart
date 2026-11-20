import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/json_rpc_client.dart';
import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'mail_models.dart';

/// 收件箱状态。摘要来自 `mail.list` 与 `mail.received`，正文按需取 `mail.get`。
class MailController extends ChangeNotifier {
  MailController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _refreshTimer;
  bool _loaded = false;
  bool _refreshing = false;
  int _refreshSequence = 0;
  int _revision = 0;
  MailSummary? _bannerItem;

  List<MailAccount> _accounts = const [];
  List<MailSummary> _items = const [];
  String? _accountFilter;
  MailDetail? _detail;
  String? _openingId;
  String _error = '';

  String _translation = '';
  String _translationTarget = '';
  String _translationProvider = '';
  String _translationError = '';
  bool _translating = false;
  bool _showTranslation = false;
  bool _markingRead = false;
  int _translateSequence = 0;

  List<MailAccount> get accounts => _accounts;
  List<MailSummary> get items => _items;

  /// 每收到一封新邮件递增，外壳据此弹横幅。
  int get revision => _revision;
  MailSummary? get bannerItem => _bannerItem;

  /// 当前收件箱筛选的账号；`null` 表示全部账号。
  String? get accountFilter => _accountFilter;

  List<MailSummary> get visibleItems {
    final filter = _accountFilter;
    if (filter == null) return _items;
    if (!_accounts.any((account) => account.id == filter)) return _items;
    return _items
        .where((item) => item.accountId == filter)
        .toList(growable: false);
  }

  int get unreadCount => _items.where((item) => item.unread).length;
  int get visibleUnreadCount =>
      visibleItems.where((item) => item.unread).length;

  MailDetail? get detail => _detail;
  String? get openingId => _openingId;
  String get error => _error;
  bool get refreshing => _refreshing;

  String get translation => _translation;
  String get translationError => _translationError;
  bool get translating => _translating;
  bool get showTranslation => _showTranslation;
  bool get markingRead => _markingRead;

  bool hasTranslationFor(String target, String provider) =>
      _translation.isNotEmpty &&
      _translationTarget == target &&
      _translationProvider == provider;

  MailAccount? accountFor(String accountId) {
    for (final account in _accounts) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  void setAccountFilter(String? accountId) {
    if (_accountFilter == accountId) return;
    _accountFilter = accountId;
    notifyListeners();
  }

  /// 将当前筛选范围（或全部账号）的未读邮件标为已读。
  Future<void> markAllRead() async {
    if (_markingRead || !supervisor.ready) return;
    _markingRead = true;
    _error = '';
    final filter = _accountFilter;
    final targets = filter == null
        ? _accounts.map((account) => account.id).toSet()
        : <String>{filter};
    // 先本地清零，服务器同步在后台进行。
    _setAccountsRead(targets);
    notifyListeners();
    try {
      final params = filter == null
          ? const <String, dynamic>{}
          : <String, dynamic>{'accountId': filter};
      final result = await supervisor.call(
        'mail.markSeen',
        params,
        const Duration(seconds: 60),
      );
      if (result['ok'] != true) {
        final message = result['message']?.toString() ?? '';
        _error = message.isEmpty ? '部分邮箱标记已读失败' : message;
        await refresh();
      }
    } catch (error) {
      _error = _message(error);
      AppLog.write('[mail] markSeen failed: $error');
      await refresh();
    } finally {
      _markingRead = false;
      notifyListeners();
    }
  }

  void _setAccountsRead(Set<String> accountIds) {
    if (accountIds.isEmpty) return;
    _items = List.unmodifiable(
      _items.map(
        (item) => accountIds.contains(item.accountId)
            ? item.copyWith(unread: false)
            : item,
      ),
    );
  }

  Future<void> refresh() async {
    if (!supervisor.ready) return;
    final sequence = ++_refreshSequence;
    _refreshing = true;
    notifyListeners();
    try {
      final result = await supervisor.call(
        'mail.list',
        const {},
        const Duration(seconds: 10),
      );
      if (sequence != _refreshSequence) return;
      _applyAccounts(result['accounts']);
      _applyItems(result['items']);
      _error = '';
    } catch (error) {
      if (sequence != _refreshSequence) return;
      _error = _message(error);
      AppLog.write('[mail] refresh failed: $error');
    } finally {
      if (sequence == _refreshSequence) {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> open(MailSummary item) async {
    if (_openingId != null) return;
    _openingId = item.id;
    _error = '';
    notifyListeners();
    try {
      final result = await supervisor.call(
        'mail.get',
        {'id': item.id},
        const Duration(seconds: 10),
      );
      final raw = result['item'];
      if (raw is! Map<String, dynamic>) {
        throw StateError('邮件正文缺失');
      }
      _detail = MailDetail.fromJson(raw);
      _resetTranslation();
      if (item.unread) {
        // 先本地消除未读，再后台同步到服务器，点击不再等待网络。
        _setItemRead(item.id);
        unawaited(_markRead(item.id));
      }
    } catch (error) {
      _error = _message(error);
      AppLog.write('[mail] open ${item.id} failed: $error');
    } finally {
      _openingId = null;
      notifyListeners();
    }
  }

  void closeDetail() {
    if (_detail == null) return;
    _detail = null;
    _resetTranslation();
    notifyListeners();
  }

  /// 按需翻译当前正文；同一目标语言和服务已有译文时在原文和译文之间切换。
  Future<void> translate({
    required String to,
    String provider = 'auto',
  }) async {
    final detail = _detail;
    if (detail == null || detail.text.trim().isEmpty || _translating) return;
    if (hasTranslationFor(to, provider)) {
      _showTranslation = !_showTranslation;
      notifyListeners();
      return;
    }
    final sequence = ++_translateSequence;
    _translating = true;
    _translation = '';
    _translationTarget = to;
    _translationProvider = provider;
    _translationError = '';
    _showTranslation = false;
    notifyListeners();
    try {
      final result = await supervisor.call(
        'translate.run',
        {'text': detail.text, 'to': to, 'provider': provider},
        const Duration(seconds: 60),
      );
      if (sequence != _translateSequence) return;
      _translation = result['text']?.toString() ?? '';
      _showTranslation = _translation.isNotEmpty;
    } on TimeoutException {
      if (sequence != _translateSequence) return;
      _translationError = '翻译超时，请检查网络或更换翻译服务';
      AppLog.write('[mail] translate timeout');
    } catch (error) {
      if (sequence != _translateSequence) return;
      _translationError = _message(error);
      AppLog.write('[mail] translate failed: $error');
    } finally {
      if (sequence == _translateSequence) {
        _translating = false;
        notifyListeners();
      }
    }
  }

  void toggleTranslation() {
    if (_translation.isEmpty) return;
    _showTranslation = !_showTranslation;
    notifyListeners();
  }

  /// 放弃当前翻译请求；sidecar 侧即使稍后返回，也会因序号变化被丢弃。
  void cancelTranslation() {
    if (!_translating) return;
    _translateSequence++;
    _translating = false;
    _translation = '';
    _translationTarget = '';
    _translationProvider = '';
    _showTranslation = false;
    _translationError = '已取消翻译';
    notifyListeners();
  }

  Future<bool> openWebmail(MailAccount account) async {
    final url = account.webmailUrl.trim();
    if (url.isEmpty) return false;
    return _openUrl(url);
  }

  Future<bool> openLink(String url) => _openUrl(url);

  Future<bool> _openUrl(String url) async {
    try {
      await supervisor.call(
        'app.openUrl',
        {'url': url},
        const Duration(seconds: 5),
      );
      return true;
    } catch (error) {
      _error = _message(error);
      AppLog.write('[mail] open url failed: $error');
      notifyListeners();
      return false;
    }
  }

  void _onSupervisorChanged() {
    if (!supervisor.ready) {
      _loaded = false;
      _refreshing = false;
      return;
    }
    if (_loaded) return;
    _loaded = true;
    unawaited(refresh());
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'mail.received':
        final raw = event['item'];
        if (raw is! Map<String, dynamic>) return;
        final item = MailSummary.fromJson(raw);
        if (item.id.isEmpty) return;
        _upsertItem(item);
        _bannerItem = item;
        _revision++;
        notifyListeners();
      case 'mail.account':
        final raw = event['account'];
        if (raw is! Map<String, dynamic>) return;
        final account = MailAccount.fromJson(raw);
        if (account.id.isEmpty) return;
        _upsertAccount(account);
        notifyListeners();
        // 首次同步完成后正文才进缓存，这里补一次列表。
        if (account.ready) _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(refresh());
    });
  }

  void _applyAccounts(Object? raw) {
    if (raw is! List) return;
    final accounts = <MailAccount>[];
    for (final value in raw) {
      if (value is Map<String, dynamic>) {
        final account = MailAccount.fromJson(value);
        if (account.id.isNotEmpty) accounts.add(account);
      }
    }
    _accounts = List.unmodifiable(accounts);
    if (_accountFilter != null &&
        !accounts.any((account) => account.id == _accountFilter)) {
      _accountFilter = null;
    }
  }

  void _applyItems(Object? raw) {
    if (raw is! List) return;
    final items = <MailSummary>[];
    for (final value in raw) {
      if (value is Map<String, dynamic>) {
        final item = MailSummary.fromJson(value);
        if (item.id.isNotEmpty) items.add(item);
      }
    }
    items.sort((left, right) => right.receivedAt.compareTo(left.receivedAt));
    _items = List.unmodifiable(items);
  }

  void _upsertAccount(MailAccount account) {
    final next = _accounts.toList();
    final index = next.indexWhere((item) => item.id == account.id);
    if (index >= 0) {
      next[index] = account;
    } else {
      next.add(account);
    }
    _accounts = List.unmodifiable(next);
  }

  void _upsertItem(MailSummary item) {
    final next = _items.toList();
    final index = next.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      next[index] = item;
    } else {
      next.add(item);
    }
    next.sort((left, right) => right.receivedAt.compareTo(left.receivedAt));
    _items = List.unmodifiable(next);
  }

  Future<void> _markRead(String id) async {
    try {
      final result = await supervisor.call(
        'mail.markSeen',
        {'id': id},
        const Duration(seconds: 30),
      );
      if (result['ok'] == true) {
        _setItemRead(id);
        return;
      }
      _error = result['message']?.toString() ?? '标记已读失败';
      notifyListeners();
      await refresh();
    } catch (error) {
      _error = _message(error);
      notifyListeners();
      AppLog.write('[mail] mark read $id failed: $error');
      await refresh();
    }
  }

  void _setItemRead(String id) {
    final next = _items.toList();
    final index = next.indexWhere((item) => item.id == id);
    if (index < 0) return;
    next[index] = next[index].copyWith(unread: false);
    _items = List.unmodifiable(next);
    notifyListeners();
  }

  void _resetTranslation() {
    _translateSequence++;
    _translation = '';
    _translationTarget = '';
    _translationProvider = '';
    _translationError = '';
    _translating = false;
    _showTranslation = false;
  }

  String _message(Object error) =>
      error is RpcException ? error.message : '$error';

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
