import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'weather_models.dart';

/// 天气状态。sidecar 每 15 分钟推送 `weather.updated`，连接后先 `weather.get` 取缓存。
class WeatherController extends ChangeNotifier {
  WeatherController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  WeatherSnapshot? _snapshot;
  String _status = '正在获取天气';
  bool _loaded = false;
  bool _refreshing = false;
  Timer? _refreshGuard;

  WeatherSnapshot? get snapshot => _snapshot;
  String get status => _status;

  /// 手动刷新是否进行中；结果到达（`weather.updated`）后复位。
  bool get refreshing => _refreshing;

  Future<void> refresh() async {
    try {
      final result = await supervisor.call('weather.get');
      _apply(result);
      notifyListeners();
    } catch (error) {
      AppLog.write('[weather] refresh failed: $error');
    }
  }

  /// 手动触发一次实况刷新。网络请求在 sidecar 天气线程里执行，
  /// 这里只负责请求与“进行中”状态，结果走 `weather.updated`。
  Future<void> forceRefresh() async {
    if (_refreshing || !supervisor.ready) return;
    _refreshing = true;
    notifyListeners();
    // 网络极差时刷新可能拖到一分钟以上，兜底复位避免按钮一直转圈。
    _refreshGuard?.cancel();
    _refreshGuard = Timer(const Duration(seconds: 60), _finishRefresh);
    try {
      await supervisor.call(
        'weather.refresh',
        const {},
        const Duration(seconds: 5),
      );
    } catch (error) {
      AppLog.write('[weather] manual refresh failed: $error');
      _finishRefresh();
    }
  }

  void _finishRefresh() {
    _refreshGuard?.cancel();
    _refreshGuard = null;
    if (!_refreshing) return;
    _refreshing = false;
    notifyListeners();
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
    if (event['type'] != 'weather.updated') return;
    _apply(event);
    _refreshGuard?.cancel();
    _refreshGuard = null;
    _refreshing = false;
    notifyListeners();
  }

  void _apply(Map<String, dynamic> payload) {
    final raw = payload['snapshot'];
    if (raw is Map<String, dynamic>) {
      _snapshot = WeatherSnapshot.fromJson(raw);
    }
    final status = payload['status']?.toString() ?? '';
    if (status.isNotEmpty) _status = status;
  }

  @override
  void dispose() {
    _refreshGuard?.cancel();
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
