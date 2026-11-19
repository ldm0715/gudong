import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/theme/island_motion.dart';
import '../messages/messages_controller.dart';

/// 岛体外壳状态：展开、闪烁、横幅。业务数据由各 feature controller 持有。
class IslandController extends ChangeNotifier {
  IslandController({required this.supervisor, required this.messages}) {
    supervisor.addListener(_onChanged);
    messages.addListener(_onMessagesChanged);
    _lastRevision = messages.revision;
  }

  final SidecarSupervisor supervisor;
  final MessagesController messages;

  bool _expanded = false;
  bool _pulse = false;
  bool _banner = false;
  bool _handleVisible = false;
  int _lastRevision = 0;
  Timer? _pulseTimer;
  Timer? _bannerTimer;
  Timer? _handleTimer;
  bool _disposed = false;

  bool get expanded => _expanded;
  bool get pulse => _pulse;
  bool get handleVisible => _handleVisible;
  bool get showBanner => _banner && messages.hasUnread;
  bool get ready => supervisor.ready;
  String get connectionDetail => supervisor.detail;

  String get statusLabel {
    if (supervisor.phase == SidecarPhase.incompatible) return '需升级';
    return supervisor.ready ? '已连接' : '重连中';
  }

  void toggleExpanded() => setExpanded(!_expanded);

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  /// 光标进入 / 离开岛体。进入时展开，停留后显示顶部拖拽把手。
  void setPointerInside(bool inside) {
    setExpanded(inside);
    _handleTimer?.cancel();
    if (!inside) {
      if (_handleVisible) {
        _handleVisible = false;
        notifyListeners();
      }
      return;
    }
    _handleTimer = Timer(IslandMotion.handleDelay, () {
      if (_disposed || _handleVisible) return;
      _handleVisible = true;
      notifyListeners();
    });
  }

  void _onChanged() => notifyListeners();

  void _onMessagesChanged() {
    if (messages.revision != _lastRevision) {
      _lastRevision = messages.revision;
      if (messages.hasUnread) {
        _showBannerForAWhile();
        _signalPulse();
      }
    }
    notifyListeners();
  }

  void _showBannerForAWhile() {
    _banner = true;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(IslandMotion.bannerHold, () {
      if (_disposed) return;
      _banner = false;
      notifyListeners();
    });
  }

  void _signalPulse() {
    _pulseTimer?.cancel();
    _pulse = true;
    _pulseTimer = Timer(IslandMotion.pulse, () {
      if (_disposed) return;
      _pulse = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pulseTimer?.cancel();
    _bannerTimer?.cancel();
    _handleTimer?.cancel();
    supervisor.removeListener(_onChanged);
    messages.removeListener(_onMessagesChanged);
    super.dispose();
  }
}
