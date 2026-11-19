import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ipc/sidecar_supervisor.dart';
import '../log.dart';
import 'app_settings.dart';

/// 用户设置。sidecar 落盘到 `%APPDATA%\guduo\config.json`，Flutter 只持有副本。
class SettingsController extends ChangeNotifier {
  SettingsController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
  }

  final SidecarSupervisor supervisor;
  AppSettings _settings = const AppSettings();
  bool _loaded = false;
  bool _loading = false;
  int _saveSequence = 0;
  Future<void> _saveChain = Future<void>.value();

  AppSettings get settings => _settings;

  /// 只有真正取回设置后才为真。窗口位置恢复依赖它，不能提前置位。
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final result = await supervisor.call('settings.get');
      final raw = result['settings'];
      if (raw is Map<String, dynamic>) {
        _settings = AppSettings.fromJson(raw);
      }
    } catch (error) {
      AppLog.write('[settings] load failed: $error');
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// 先本地生效再写盘，连续点击时界面不会等待 RPC。
  /// 写入串行执行，且只有最后一次响应能覆盖本地状态。
  Future<void> save(AppSettings next) {
    _settings = next;
    notifyListeners();
    final sequence = ++_saveSequence;
    final task = _saveChain.then((_) => _write(next, sequence));
    _saveChain = task.catchError((_) {});
    return task;
  }

  Future<void> _write(AppSettings next, int sequence) async {
    try {
      final result = await supervisor.call('settings.set', {
        'settings': next.toJson(),
      });
      if (sequence != _saveSequence) return;
      final raw = result['settings'];
      if (raw is Map<String, dynamic>) {
        _settings = AppSettings.fromJson(raw);
        notifyListeners();
      }
    } catch (error) {
      AppLog.write('[settings] save failed: $error');
    }
  }

  void _onSupervisorChanged() {
    if (!supervisor.ready) {
      _loaded = false;
      _loading = false;
      return;
    }
    if (_loaded || _loading) return;
    _loading = true;
    unawaited(load());
  }

  @override
  void dispose() {
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
