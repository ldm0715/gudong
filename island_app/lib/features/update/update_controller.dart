import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';

/// 更新状态。自动检查发现新版本时递增 revision，外壳据此弹横幅。
class UpdateController extends ChangeNotifier {
  UpdateController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loaded = false;
  bool _available = false;
  String _latestVersion = '';
  int _revision = 0;

  bool get available => _available;
  String get latestVersion => _latestVersion;
  int get revision => _revision;

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
      final result = await supervisor.call('update.status');
      _apply(result['snapshot']);
    } catch (error) {
      AppLog.write('[update] load failed: $error');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] != 'update.available') return;
    _apply(event['snapshot'], notify: true);
  }

  void _apply(Object? raw, {bool notify = false}) {
    if (raw is! Map) return;
    final snapshot = Map<String, dynamic>.from(raw);
    final available = snapshot['updateAvailable'] == true;
    final latest = snapshot['latestVersion']?.toString() ?? '';
    final changed = available != _available || latest != _latestVersion;
    _available = available;
    _latestVersion = latest;
    if (changed && available) _revision++;
    if (changed || notify) notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
