import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import '../weather/weather.dart';

class UnreadItem {
  const UnreadItem({
    required this.id,
    required this.source,
    required this.account,
    required this.window,
    required this.count,
    required this.time,
    this.kind = 'taskbar',
    this.contact,
    this.preview,
  });

  final String id;
  final String source;
  final int account;
  final int window;
  final int count;
  final String time;
  final String kind;
  final String? contact;
  final String? preview;

  String get sourceName => source == 'qq' ? 'QQ' : '微信';

  String get title {
    final name = contact?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return account > 0 ? '$sourceName · 账号 $account' : sourceName;
  }

  String get subtitle {
    final text = preview?.trim() ?? '';
    if (text.isNotEmpty) return text;
    return kind == 'toast' ? '$time · 新消息' : '$time · 第 $count 条提醒';
  }

  factory UnreadItem.fromJson(Map<String, dynamic> json) {
    final source = json['source']?.toString() ?? 'wechat';
    final account = (json['account'] as num?)?.toInt() ?? 0;
    final time = json['time']?.toString() ?? '';
    return UnreadItem(
      id: json['id']?.toString() ?? '$source:$account:$time',
      source: source,
      account: account,
      window: (json['window'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 1,
      time: time,
      kind: json['kind']?.toString() ?? 'taskbar',
      contact: json['contact']?.toString(),
      preview: json['preview']?.toString(),
    );
  }
}

/// 岛体的 UI 状态：展开、未读、连接状态。所有系统能力都来自 sidecar 事件。
class IslandController extends ChangeNotifier {
  IslandController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  final Map<String, UnreadItem> _unread = {};
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _pulseTimer;
  Timer? _bannerTimer;
  bool _showBanner = false;
  bool _disposed = false;

  bool _expanded = false;
  bool _pulse = false;
  bool _wechatOk = false;
  String _wechatStatus = '正在检测微信';
  bool _notificationsOk = false;
  String _notificationsStatus = '正在检测系统通知';
  WeatherSnapshot? _weather;
  String _weatherStatus = '正在获取天气';

  bool get expanded => _expanded;
  bool get pulse => _pulse;
  bool get wechatOk => _wechatOk;
  String get wechatStatus => _wechatStatus;
  bool get notificationsOk => _notificationsOk;
  String get notificationsStatus => _notificationsStatus;
  WeatherSnapshot? get weather => _weather;
  String get weatherStatus => _weatherStatus;
  bool get ready => supervisor.ready;
  String get connectionDetail => supervisor.detail;
  List<UnreadItem> get unread => _unread.values.toList(growable: false);
  bool get hasUnread => _unread.isNotEmpty;
  bool get showBanner => _showBanner && _unread.isNotEmpty;
  UnreadItem? get latestUnread {
    UnreadItem? latest;
    for (final item in _unread.values) {
      if (latest == null || item.time.compareTo(latest.time) >= 0) {
        latest = item;
      }
    }
    return latest;
  }

  int get unreadCount =>
      _unread.values.fold(0, (sum, item) => sum + item.count);
  bool get hasQq => _unread.values.any((item) => item.source == 'qq');
  bool get hasWechat => _unread.values.any((item) => item.source == 'wechat');

  void toggleExpanded() => setExpanded(!_expanded);

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  Future<void> markAllSeen() async {
    if (_unread.isEmpty) return;
    _unread.clear();
    _showBanner = false;
    _bannerTimer?.cancel();
    notifyListeners();
    try {
      await supervisor.call('messages.seen', {});
    } catch (error) {
      debugPrint('[ipc] messages.seen failed: $error');
    }
  }

  Future<bool> openMessage(UnreadItem item) async {
    try {
      final result = await supervisor.call('messages.open', {'id': item.id});
      final ok = result['ok'] == true;
      AppLog.write(
        '[messages] open ${item.id}: ok=$ok message=${result['message'] ?? ''}',
      );
      if (ok) {
        _unread.remove(item.id);
        if (_unread.isEmpty) {
          _showBanner = false;
          _bannerTimer?.cancel();
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (error) {
      AppLog.write('[messages] open ${item.id} failed: $error');
      return false;
    }
  }

  void _onSupervisorChanged() {
    notifyListeners();
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'message.unread':
        final item = UnreadItem.fromJson(event);
        if (item.id.isEmpty) return;
        // 能读到系统通知时，用带预览的条目替换同一来源的任务栏条目。
        if (item.kind == 'toast') {
          _unread.removeWhere(
            (_, existing) =>
                existing.source == item.source && existing.kind == 'taskbar',
          );
        }
        _unread[item.id] = item;
        _showBannerForAWhile();
        _signalPulse();
        notifyListeners();
      case 'message.cleared':
        _onCleared(event);
        if (_unread.isEmpty) {
          _showBanner = false;
          _bannerTimer?.cancel();
        }
        notifyListeners();
      case 'system.status':
        final component = event['component']?.toString();
        if (component == 'wechat') {
          _wechatOk = event['ok'] == true;
          _wechatStatus = _wechatOk
              ? '微信监听中'
              : (event['message']?.toString() ?? '微信监听异常');
          notifyListeners();
        } else if (component == 'notifications') {
          _notificationsOk = event['ok'] == true;
          _notificationsStatus = _notificationsOk
              ? '微信 / QQ 通知监听中'
              : (event['message']?.toString() ?? '系统通知监听异常');
          notifyListeners();
        }
      case 'weather.updated':
        _applyWeather(event);
        notifyListeners();
      case 'sidecar.snapshot':
        _applySnapshot(event);
        notifyListeners();
      default:
        break;
    }
  }

  void _onCleared(Map<String, dynamic> event) {
    final id = event['id']?.toString() ?? '';
    if (id.isNotEmpty) {
      _unread.remove(id);
      return;
    }
    final source = event['source']?.toString() ?? '';
    if (source.isEmpty) return;
    final account = (event['account'] as num?)?.toInt() ?? 0;
    _unread.removeWhere(
      (_, item) =>
          item.source == source &&
          (account == 0 || item.account == account || item.account == 0),
    );
  }

  void _applyWeather(Map<String, dynamic> event) {
    final raw = event['snapshot'];
    if (raw is Map<String, dynamic>) {
      _weather = WeatherSnapshot.fromJson(raw);
    }
    final status = event['status']?.toString() ?? '';
    if (status.isNotEmpty) _weatherStatus = status;
  }

  void _applySnapshot(Map<String, dynamic> event) {
    final items = event['items'];
    if (items is List) {
      _unread.clear();
      for (final raw in items) {
        if (raw is Map<String, dynamic>) {
          final item = UnreadItem.fromJson(raw);
          if (item.id.isNotEmpty) _unread[item.id] = item;
        }
      }
    }
    if (_unread.isNotEmpty) {
      _showBannerForAWhile();
    } else {
      _showBanner = false;
      _bannerTimer?.cancel();
    }
    final listener = event['listener'];
    if (listener is Map<String, dynamic>) {
      _wechatOk = listener['ok'] == true;
      final message = listener['message']?.toString() ?? '';
      _wechatStatus = _wechatOk
          ? '微信监听中'
          : (message.isEmpty ? '微信监听异常' : message);
    }
    final notifications = event['notifications'];
    if (notifications is Map<String, dynamic>) {
      _notificationsOk = notifications['ok'] == true;
      final message = notifications['message']?.toString() ?? '';
      _notificationsStatus = _notificationsOk
          ? '微信 / QQ 通知监听中'
          : (message.isEmpty ? '系统通知监听异常' : message);
    }
    final weather = event['weather'];
    if (weather is Map<String, dynamic>) {
      _applyWeather(weather);
    }
  }

  void _showBannerForAWhile() {
    _showBanner = true;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      _showBanner = false;
      notifyListeners();
    });
  }

  void _signalPulse() {
    _pulseTimer?.cancel();
    _pulse = true;
    _pulseTimer = Timer(const Duration(milliseconds: 1400), () {
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
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
