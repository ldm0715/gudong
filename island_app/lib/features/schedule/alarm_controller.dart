import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'alarm_models.dart';

/// 每日闹钟状态。列表由 sidecar 推送，客户端只发增删改请求。
class AlarmController extends ChangeNotifier {
  AlarmController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loaded = false;
  List<AlarmItem> _items = const [];
  AlarmItem? _bannerItem;
  int _revision = 0;

  /// 按时间升序排列的全部闹钟。
  List<AlarmItem> get items => _items;

  /// 每触发一次闹钟就递增，外壳据此弹提醒横幅。
  int get revision => _revision;

  AlarmItem? get bannerItem => _bannerItem;

  Future<AlarmItem> add({
    required String title,
    required int hour,
    required int minute,
    required List<int> days,
    bool enabled = true,
  }) async {
    final result = await supervisor.call('alarm.add', {
      'title': title,
      'hour': hour,
      'minute': minute,
      'days': days,
      'enabled': enabled,
    });
    final item = _itemFrom(result);
    _upsert(item);
    notifyListeners();
    return item;
  }

  Future<AlarmItem> update(
    String id, {
    String? title,
    int? hour,
    int? minute,
    List<int>? days,
    bool? enabled,
  }) async {
    final params = <String, dynamic>{'id': id};
    if (title != null) params['title'] = title;
    if (hour != null) params['hour'] = hour;
    if (minute != null) params['minute'] = minute;
    if (days != null) params['days'] = days;
    if (enabled != null) params['enabled'] = enabled;
    final result = await supervisor.call('alarm.update', params);
    final item = _itemFrom(result);
    _upsert(item);
    notifyListeners();
    return item;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await update(id, enabled: enabled);
  }

  Future<void> remove(String id) async {
    await supervisor.call('alarm.remove', {'id': id});
    _items = _items.where((item) => item.id != id).toList(growable: false);
    notifyListeners();
  }

  void dismissBanner() {
    if (_bannerItem == null) return;
    _bannerItem = null;
    notifyListeners();
  }

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
      final result = await supervisor.call('alarm.list');
      _applyList(result['items']);
      notifyListeners();
    } catch (error) {
      AppLog.write('[alarm] load failed: $error');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'alarm.updated':
        _applyList(event['items']);
        notifyListeners();
      case 'alarm.fired':
        final raw = event['item'];
        if (raw is! Map<String, dynamic>) return;
        _bannerItem = AlarmItem.fromJson(raw);
        _revision++;
        notifyListeners();
    }
  }

  void _applyList(Object? raw) {
    if (raw is! List) return;
    final items = <AlarmItem>[];
    for (final value in raw) {
      if (value is Map<String, dynamic>) {
        final item = AlarmItem.fromJson(value);
        if (item.id.isNotEmpty) items.add(item);
      }
    }
    items.sort(_compare);
    _items = List.unmodifiable(items);
  }

  void _upsert(AlarmItem item) {
    final items = _items.where((value) => value.id != item.id).toList();
    items.add(item);
    items.sort(_compare);
    _items = List.unmodifiable(items);
  }

  static int _compare(AlarmItem left, AlarmItem right) {
    final byHour = left.hour.compareTo(right.hour);
    if (byHour != 0) return byHour;
    final byMinute = left.minute.compareTo(right.minute);
    if (byMinute != 0) return byMinute;
    return left.id.compareTo(right.id);
  }

  AlarmItem _itemFrom(Map<String, dynamic> result) {
    final raw = result['item'];
    if (raw is Map<String, dynamic>) return AlarmItem.fromJson(raw);
    throw StateError('alarm response is missing an item');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
