import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'metrics_models.dart';

/// 系统指标。sidecar 以 1Hz 推送 `metrics.updated`，连接后先 `metrics.get` 取缓存。
class MetricsController extends ChangeNotifier {
  MetricsController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  MetricsSnapshot? _snapshot;
  bool _loaded = false;

  /// 最近一帧；首次采样完成前为 `null`。
  MetricsSnapshot? get snapshot => _snapshot;

  void _onSupervisorChanged() {
    if (!supervisor.ready) {
      _loaded = false;
      return;
    }
    if (_loaded) return;
    _loaded = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await supervisor.call('metrics.get');
      _apply(result['snapshot']);
      notifyListeners();
    } catch (error) {
      AppLog.write('[metrics] load failed: $error');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] != 'metrics.updated') return;
    _apply(event);
    notifyListeners();
  }

  void _apply(Object? raw) {
    if (raw is! Map) return;
    final snapshot = MetricsSnapshot.fromJson(Map<String, dynamic>.from(raw));
    if (snapshot.updatedAtMs <= 0) return;
    _snapshot = snapshot;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
