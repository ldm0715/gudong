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

  WeatherSnapshot? get snapshot => _snapshot;
  String get status => _status;

  Future<void> refresh() async {
    try {
      final result = await supervisor.call('weather.get');
      _apply(result);
      notifyListeners();
    } catch (error) {
      AppLog.write('[weather] refresh failed: $error');
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
    if (event['type'] != 'weather.updated') return;
    _apply(event);
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
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
