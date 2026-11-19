import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';

/// 输入法状态。检测由 sidecar 完成，这里只维护展示用的模式与横幅计时。
class ImeController extends ChangeNotifier {
  ImeController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  /// 横幅保留时长，和消息横幅保持同一节奏。
  static const Duration visibleDuration = Duration(seconds: 2);

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _hideTimer;
  String? _mode;
  bool _visible = false;
  bool _loaded = false;
  bool _disposed = false;

  /// 当前输入法模式：`zh` / `en`，还没取到时为 null。
  String? get mode => _mode;
  bool get chinese => _mode == 'zh';
  bool get visible => _visible;

  /// 连接后主动取一次当前模式，让常驻标识立即显示。
  Future<void> refresh() async {
    try {
      final result = await supervisor.call('ime.get');
      _setMode(result['mode']?.toString());
    } catch (error) {
      AppLog.write('[ime] refresh failed: $error');
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
    if (event['type'] != 'ime.changed') return;
    _setMode(event['mode']?.toString());
    // 换窗口触发的模式同步不弹横幅，只更新常驻标识。
    if (event['banner'] == false) return;
    _visible = true;
    notifyListeners();
    _hideTimer?.cancel();
    _hideTimer = Timer(visibleDuration, () {
      if (_disposed) return;
      _visible = false;
      notifyListeners();
    });
  }

  void _setMode(String? mode) {
    if (mode != 'zh' && mode != 'en') return;
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hideTimer?.cancel();
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
