import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'unread_item.dart';

/// 未读提醒状态。数据只来自 sidecar 的 `message.*` 事件与 `messages.list` 快照。
class MessagesController extends ChangeNotifier {
  MessagesController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  final Map<String, UnreadItem> _unread = {};
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loaded = false;
  int _revision = 0;

  /// 每收到一条新提醒递增，外壳据此触发横幅与边框闪烁。
  int get revision => _revision;
  List<UnreadItem> get unread => _unread.values.toList(growable: false);
  bool get hasUnread => _unread.isNotEmpty;
  bool get hasWechat => _unread.values.any((item) => item.source == 'wechat');
  bool get hasQq => _unread.values.any((item) => item.source == 'qq');
  int get unreadCount =>
      _unread.values.fold(0, (sum, item) => sum + item.count);

  UnreadItem? get latestUnread {
    UnreadItem? latest;
    for (final item in _unread.values) {
      if (latest == null || item.time.compareTo(latest.time) >= 0) {
        latest = item;
      }
    }
    return latest;
  }

  Future<void> refresh() async {
    try {
      final result = await supervisor.call('messages.list');
      final items = result['items'];
      if (items is! List) return;
      _unread.clear();
      for (final raw in items) {
        if (raw is Map<String, dynamic>) {
          final item = UnreadItem.fromJson(raw);
          if (item.id.isNotEmpty) _unread[item.id] = item;
        }
      }
      notifyListeners();
    } catch (error) {
      AppLog.write('[messages] refresh failed: $error');
    }
  }

  Future<void> markAllSeen() async {
    if (_unread.isEmpty) return;
    _unread.clear();
    notifyListeners();
    try {
      await supervisor.call('messages.seen', {});
    } catch (error) {
      AppLog.write('[messages] markAllSeen failed: $error');
    }
  }

  Future<bool> openMessage(UnreadItem item) async {
    try {
      final result = await supervisor.call('messages.open', {'id': item.id});
      final ok = result['ok'] == true;
      AppLog.write(
        '[messages] open ${item.id}: ok=$ok message=${result['message'] ?? ''}',
      );
      if (!ok) return false;
      _unread.remove(item.id);
      notifyListeners();
      return true;
    } catch (error) {
      AppLog.write('[messages] open ${item.id} failed: $error');
      return false;
    }
  }

  void _onSupervisorChanged() {
    if (!supervisor.ready) {
      _loaded = false;
      return;
    }
    if (_loaded) return;
    _loaded = true;
    unawaited(refresh());
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'message.unread':
        final item = UnreadItem.fromJson(event);
        if (item.id.isEmpty) return;
        // 能读到系统通知时，用带预览的条目替换同一来源的任务栏条目。
        if (item.kind == 'toast') {
          _unread.removeWhere(
            (_, existing) =>
                existing.source == item.source && existing.kind == 'taskbar',
          );
        }
        _unread[item.id] = item;
        _revision++;
        notifyListeners();
      case 'message.cleared':
        if (_clearFromEvent(event)) notifyListeners();
    }
  }

  bool _clearFromEvent(Map<String, dynamic> event) {
    final before = _unread.length;
    final id = event['id']?.toString() ?? '';
    if (id.isNotEmpty) {
      _unread.remove(id);
      return _unread.length != before;
    }
    final source = event['source']?.toString() ?? '';
    if (source.isEmpty) return false;
    final account = (event['account'] as num?)?.toInt() ?? 0;
    _unread.removeWhere(
      (_, item) =>
          item.source == source &&
          (account == 0 || item.account == account || item.account == 0),
    );
    return _unread.length != before;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
