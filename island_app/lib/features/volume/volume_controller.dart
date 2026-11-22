import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';

/// 系统音量。sidecar 轮询默认播放设备，变化时推送 `volume.changed`。
class VolumeController extends ChangeNotifier {
  VolumeController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  double _volume = 0;
  bool _muted = false;
  bool _loaded = false;
  int _revision = 0;
  Timer? _sendTimer;
  Timer? _localHold;
  double? _pendingVolume;

  /// 0.0 - 1.0。
  double get volume => _volume;
  bool get muted => _muted;

  /// 每次系统音量或静音变化递增，外壳据此弹出横幅。
  int get revision => _revision;

  Future<void> refresh() async {
    try {
      final result = await supervisor.call('volume.get');
      _apply(result['volume'], result['muted']);
    } catch (error) {
      AppLog.write('[volume] get failed: $error');
    }
  }

  /// 拖动时先更新本地数值，再把请求合并到约 20Hz。
  void setVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    _volume = next;
    // 与系统音量面板一致：调音量即解除静音。
    _muted = false;
    _localHold?.cancel();
    _localHold = Timer(const Duration(milliseconds: 250), () {});
    notifyListeners();
    _pendingVolume = next;
    _sendTimer ??= Timer(const Duration(milliseconds: 50), _flush);
  }

  Future<void> toggleMute() async {
    final next = !_muted;
    _muted = next;
    notifyListeners();
    try {
      await supervisor.call('volume.mute', {
        'muted': next,
      }, const Duration(seconds: 5));
    } catch (error) {
      AppLog.write('[volume] mute failed: $error');
    }
  }

  /// 按当前音量播放一次提示音，让用户听到调节结果。
  Future<void> preview() async {
    // 先把待发送的音量发出去，保证提示音用的是最终音量。
    _sendTimer?.cancel();
    _sendTimer = null;
    await _flush();
    try {
      await supervisor.call(
        'volume.preview',
        const {},
        const Duration(seconds: 5),
      );
    } catch (error) {
      AppLog.write('[volume] preview failed: $error');
    }
  }

  Future<void> _flush() async {
    _sendTimer = null;
    final value = _pendingVolume;
    _pendingVolume = null;
    if (value == null) return;
    try {
      await supervisor.call('volume.set', {
        'volume': value,
      }, const Duration(seconds: 5));
    } catch (error) {
      AppLog.write('[volume] set failed: $error');
    }
  }

  void _apply(Object? volume, Object? muted) {
    // 拖动期间以本地数值为准，避免往返中的旧事件让滑块回跳。
    if (!(_localHold?.isActive ?? false)) {
      final value = (volume as num?)?.toDouble();
      if (value != null) _volume = value.clamp(0.0, 1.0);
      if (muted is bool) _muted = muted;
    }
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
    if (event['type'] != 'volume.changed') return;
    _revision++;
    _apply(event['volume'], event['muted']);
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _localHold?.cancel();
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
