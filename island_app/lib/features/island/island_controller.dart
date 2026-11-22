import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/theme/island_motion.dart';
import '../mail/mail_controller.dart';
import '../mail/mail_models.dart';
import '../messages/messages_controller.dart';
import '../schedule/schedule_controller.dart';
import '../schedule/schedule_models.dart';
import '../volume/volume_controller.dart';

/// 岛体外壳状态：展开、闪烁、横幅。业务数据由各 feature controller 持有。
class IslandController extends ChangeNotifier {
  IslandController({
    required this.supervisor,
    required this.messages,
    required this.mail,
    required this.schedule,
    required this.volume,
  }) {
    supervisor.addListener(_onChanged);
    messages.addListener(_onMessagesChanged);
    mail.addListener(_onMailChanged);
    schedule.addListener(_onScheduleChanged);
    volume.addListener(_onVolumeChanged);
    _lastRevision = messages.revision;
    _lastMailRevision = mail.revision;
    _lastScheduleRevision = schedule.revision;
    _lastVolumeRevision = volume.revision;
  }

  final SidecarSupervisor supervisor;
  final MessagesController messages;
  final MailController mail;
  final ScheduleController schedule;
  final VolumeController volume;

  bool _expanded = false;
  bool _pulse = false;
  bool _banner = false;
  bool _mailBanner = false;
  bool _scheduleBanner = false;
  bool _volumeBanner = false;
  bool _handleVisible = false;
  bool _pointerInside = false;
  int _lastRevision = 0;
  int _lastMailRevision = 0;
  int _lastScheduleRevision = 0;
  int _lastVolumeRevision = 0;
  Timer? _pulseTimer;
  Timer? _bannerTimer;
  Timer? _mailBannerTimer;
  Timer? _scheduleBannerTimer;
  Timer? _volumeBannerTimer;
  Timer? _handleTimer;
  bool _disposed = false;

  bool get expanded => _expanded;
  bool get pulse => _pulse;
  bool get handleVisible => _handleVisible;
  bool get showBanner => _banner && messages.hasUnread;
  bool get showMailBanner => _mailBanner && mail.bannerItem != null;
  MailSummary? get mailBannerItem => mail.bannerItem;
  bool get showScheduleBanner => _scheduleBanner && schedule.bannerItem != null;
  ScheduleItem? get scheduleBannerItem => schedule.bannerItem;
  bool get showVolumeBanner => _volumeBanner;
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
    _pointerInside = inside;
    // 音量横幅需要拖动，悬停期间不展开；等横幅结束后再按指针状态展开。
    if (inside && showVolumeBanner) {
      _handleTimer?.cancel();
      if (_handleVisible) {
        _handleVisible = false;
        notifyListeners();
      }
      return;
    }
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

  void _onMailChanged() {
    if (mail.revision != _lastMailRevision) {
      _lastMailRevision = mail.revision;
      if (mail.bannerItem != null) {
        _mailBanner = true;
        _mailBannerTimer?.cancel();
        _mailBannerTimer = Timer(IslandMotion.bannerHold, () {
          if (_disposed) return;
          _mailBanner = false;
          notifyListeners();
        });
        _signalPulse();
      }
    }
    notifyListeners();
  }

  void _onScheduleChanged() {
    if (schedule.revision != _lastScheduleRevision) {
      _lastScheduleRevision = schedule.revision;
      if (schedule.bannerItem != null) {
        _scheduleBanner = true;
        _scheduleBannerTimer?.cancel();
        _scheduleBannerTimer = Timer(IslandMotion.bannerHold, () {
          if (_disposed) return;
          _scheduleBanner = false;
          notifyListeners();
        });
        _signalPulse();
      }
    }
    notifyListeners();
  }

  void _onVolumeChanged() {
    if (volume.revision != _lastVolumeRevision) {
      _lastVolumeRevision = volume.revision;
      _volumeBanner = true;
      _volumeBannerTimer?.cancel();
      _volumeBannerTimer = Timer(IslandMotion.bannerHold, () {
        if (_disposed) return;
        _volumeBanner = false;
        if (_pointerInside) setExpanded(true);
        notifyListeners();
      });
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
    _mailBannerTimer?.cancel();
    _scheduleBannerTimer?.cancel();
    _volumeBannerTimer?.cancel();
    _handleTimer?.cancel();
    supervisor.removeListener(_onChanged);
    messages.removeListener(_onMessagesChanged);
    mail.removeListener(_onMailChanged);
    schedule.removeListener(_onScheduleChanged);
    volume.removeListener(_onVolumeChanged);
    super.dispose();
  }
}
