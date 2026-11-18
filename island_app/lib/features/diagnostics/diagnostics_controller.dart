import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';

/// 微信监听与系统通知的组件状态。连接后从 `messages.list` 取一次，
/// 之后由 `system.status` 事件更新。
class DiagnosticsController extends ChangeNotifier {
  DiagnosticsController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loaded = false;
  bool _wechatFromEvent = false;
  bool _notificationsFromEvent = false;

  bool wechatOk = false;
  String wechatStatus = '正在检测微信';
  bool notificationsOk = false;
  String notificationsStatus = '正在检测系统通知';

  Future<void> refresh() async {
    try {
      final result = await supervisor.call('messages.list');
      final listener = result['listener'];
      if (!_wechatFromEvent && listener is Map<String, dynamic>) {
        _apply(
          component: 'wechat',
          ok: listener['ok'] == true,
          message: listener['message']?.toString() ?? '',
          fromEvent: false,
        );
      }
      final notifications = result['notifications'];
      if (!_notificationsFromEvent && notifications is Map<String, dynamic>) {
        _apply(
          component: 'notifications',
          ok: notifications['ok'] == true,
          message: notifications['message']?.toString() ?? '',
          fromEvent: false,
        );
      }
      notifyListeners();
    } catch (error) {
      AppLog.write('[diagnostics] refresh failed: $error');
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
    if (event['type'] != 'system.status') return;
    final component = event['component']?.toString() ?? '';
    if (component != 'wechat' && component != 'notifications') return;
    _apply(
      component: component,
      ok: event['ok'] == true,
      message: event['message']?.toString() ?? '',
      fromEvent: true,
    );
    notifyListeners();
  }

  void _apply({
    required String component,
    required bool ok,
    required String message,
    required bool fromEvent,
  }) {
    if (component == 'wechat') {
      wechatOk = ok;
      wechatStatus = ok ? '微信监听中' : (message.isEmpty ? '微信监听异常' : message);
      _wechatFromEvent = _wechatFromEvent || fromEvent;
      return;
    }
    notificationsOk = ok;
    notificationsStatus = ok
        ? '微信 / QQ 通知监听中'
        : (message.isEmpty ? '系统通知监听异常' : message);
    _notificationsFromEvent = _notificationsFromEvent || fromEvent;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
