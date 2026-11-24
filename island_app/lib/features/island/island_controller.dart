import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/theme/island_motion.dart';
import '../agents/agent_controller.dart';
import '../agents/agent_models.dart';
import '../mail/mail_controller.dart';
import '../mail/mail_models.dart';
import '../messages/messages_controller.dart';
import '../schedule/alarm_controller.dart';
import '../schedule/alarm_models.dart';
import '../schedule/schedule_controller.dart';
import '../schedule/schedule_models.dart';
import '../update/update_controller.dart';
import '../volume/volume_controller.dart';

/// 岛体外壳状态：展开、闪烁、横幅。业务数据由各 feature controller 持有。
class IslandController extends ChangeNotifier {
  IslandController({
    required this.supervisor,
    required this.messages,
    required this.mail,
    required this.schedule,
    required this.alarm,
    required this.update,
    required this.volume,
    required this.agents,
  }) {
    supervisor.addListener(_onChanged);
    _eventSubscription = supervisor.events.listen(_onEvent);
    messages.addListener(_onMessagesChanged);
    mail.addListener(_onMailChanged);
    schedule.addListener(_onScheduleChanged);
    alarm.addListener(_onAlarmChanged);
    update.addListener(_onUpdateChanged);
    volume.addListener(_onVolumeChanged);
    agents.addListener(_onAgentChanged);
    _lastRevision = messages.revision;
    _lastMailRevision = mail.revision;
    _lastScheduleRevision = schedule.revision;
    _lastAlarmRevision = alarm.revision;
    _lastUpdateRevision = update.revision;
    _lastVolumeRevision = volume.revision;
    _lastAgentRevision = agents.revision;
  }

  final SidecarSupervisor supervisor;
  final MessagesController messages;
  final MailController mail;
  final ScheduleController schedule;
  final AlarmController alarm;
  final UpdateController update;
  final VolumeController volume;
  final AgentController agents;

  bool _expanded = false;
  bool _pulse = false;
  bool _banner = false;
  bool _mailBanner = false;
  bool _scheduleBanner = false;
  bool _alarmBanner = false;
  bool _updateBanner = false;
  bool _volumeBanner = false;
  bool _agentBanner = false;
  bool _handleVisible = false;
  bool _pointerInside = false;
  bool _expandHold = false;
  bool _foregroundMaximized = false;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  int _lastRevision = 0;
  int _lastMailRevision = 0;
  int _lastScheduleRevision = 0;
  int _lastAlarmRevision = 0;
  int _lastUpdateRevision = 0;
  int _lastVolumeRevision = 0;
  int _lastAgentRevision = 0;
  String? _agentBannerKey;
  Timer? _pulseTimer;
  Timer? _bannerTimer;
  Timer? _mailBannerTimer;
  Timer? _scheduleBannerTimer;
  Timer? _alarmBannerTimer;
  Timer? _updateBannerTimer;
  Timer? _volumeBannerTimer;
  Timer? _agentBannerTimer;
  Timer? _handleTimer;
  bool _disposed = false;

  bool get expanded => _expanded;
  bool get pulse => _pulse;
  bool get handleVisible => _handleVisible;
  bool get pointerInside => _pointerInside;

  /// 前台窗口最大化且指针不在岛体上时，只显示一条横杠。
  bool mini(bool enabled) => enabled && _foregroundMaximized && !_pointerInside;
  bool get showBanner => _banner && messages.hasUnread;
  bool get showMailBanner => _mailBanner && mail.bannerItem != null;
  MailSummary? get mailBannerItem => mail.bannerItem;
  bool get showScheduleBanner => _scheduleBanner && schedule.bannerItem != null;
  ScheduleItem? get scheduleBannerItem => schedule.bannerItem;
  bool get showAlarmBanner => _alarmBanner && alarm.bannerItem != null;
  AlarmItem? get alarmBannerItem => alarm.bannerItem;
  bool get showUpdateBanner => _updateBanner && update.available;
  String get updateLatestVersion => update.latestVersion;
  bool get showVolumeBanner => _volumeBanner;
  bool get showAgentBanner => _agentBanner && agents.bannerItem != null;
  AgentFinished? get agentBannerItem => agents.bannerItem;
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

  /// 模态浮层打开时保持展开。指针离开窗口后岛体不收起，
  /// 避免浮层悬空在桌面上。
  void holdExpanded(bool value) {
    if (_expandHold == value) return;
    _expandHold = value;
    if (value) {
      setExpanded(true);
    } else if (!_pointerInside) {
      setExpanded(false);
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] != 'foreground.maximized') return;
    final maximized = event['maximized'];
    if (maximized is! bool || maximized == _foregroundMaximized) return;
    _foregroundMaximized = maximized;
    if (!maximized && _pointerInside) setExpanded(true);
    notifyListeners();
  }

  /// 光标进入 / 离开岛体。进入时展开，停留后显示顶部拖拽把手。
  void setPointerInside(bool inside) {
    _pointerInside = inside;
    if (!inside) {
      _handleTimer?.cancel();
      if (_handleVisible) {
        _handleVisible = false;
        notifyListeners();
      }
      if (!_expandHold) setExpanded(false);
      return;
    }
    // 音量横幅需要拖动，悬停期间不展开；等横幅结束后再按指针状态展开。
    if (showVolumeBanner) {
      _handleTimer?.cancel();
      if (_handleVisible) {
        _handleVisible = false;
        notifyListeners();
      }
      return;
    }
    setExpanded(true);
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

  void _onAlarmChanged() {
    if (alarm.revision != _lastAlarmRevision) {
      _lastAlarmRevision = alarm.revision;
      if (alarm.bannerItem != null) {
        _alarmBanner = true;
        _alarmBannerTimer?.cancel();
        _alarmBannerTimer = Timer(IslandMotion.bannerHoldLong, () {
          if (_disposed) return;
          _alarmBanner = false;
          alarm.dismissBanner();
          notifyListeners();
        });
        _signalPulse();
      }
    }
    notifyListeners();
  }

  void _onUpdateChanged() {
    if (update.revision != _lastUpdateRevision) {
      _lastUpdateRevision = update.revision;
      if (update.available) {
        _updateBanner = true;
        _updateBannerTimer?.cancel();
        _updateBannerTimer = Timer(IslandMotion.bannerHoldLong, () {
          if (_disposed) return;
          _updateBanner = false;
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

  void _onAgentChanged() {
    if (agents.revision != _lastAgentRevision) {
      _lastAgentRevision = agents.revision;
      final item = agents.bannerItem;
      if (item != null && item.key != _agentBannerKey) {
        _agentBannerKey = item.key;
        _agentBanner = true;
        _agentBannerTimer?.cancel();
        _agentBannerTimer = Timer(IslandMotion.bannerHoldLong, () {
          if (_disposed) return;
          _agentBanner = false;
          agents.dismissBanner();
          notifyListeners();
        });
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
    _mailBannerTimer?.cancel();
    _scheduleBannerTimer?.cancel();
    _alarmBannerTimer?.cancel();
    _updateBannerTimer?.cancel();
    _volumeBannerTimer?.cancel();
    _agentBannerTimer?.cancel();
    _handleTimer?.cancel();
    _eventSubscription?.cancel();
    supervisor.removeListener(_onChanged);
    messages.removeListener(_onMessagesChanged);
    mail.removeListener(_onMailChanged);
    schedule.removeListener(_onScheduleChanged);
    alarm.removeListener(_onAlarmChanged);
    update.removeListener(_onUpdateChanged);
    volume.removeListener(_onVolumeChanged);
    agents.removeListener(_onAgentChanged);
    super.dispose();
  }
}
