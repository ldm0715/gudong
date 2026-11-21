import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'schedule_models.dart';

/// 日程状态。列表由 sidecar 推送，客户端只发增删改请求。
class ScheduleController extends ChangeNotifier {
  ScheduleController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loaded = false;
  List<ScheduleItem> _items = const [];
  ScheduleItem? _bannerItem;
  int _revision = 0;

  /// 按时间升序排列的全部日程。
  List<ScheduleItem> get items => _items;

  /// 每到一条日程触发就递增，外壳据此弹提醒横幅。
  int get revision => _revision;

  ScheduleItem? get bannerItem => _bannerItem;

  List<ScheduleItem> itemsOn(DateTime day) {
    final key = scheduleDayKey(day);
    return _items
        .where((item) => scheduleDayKey(item.at) == key)
        .toList(growable: false);
  }

  /// 当天是否还有未触发且时间未到的日程。
  bool hasPendingOn(DateTime day, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final currentMs = current.millisecondsSinceEpoch;
    return itemsOn(day).any((item) => !item.fired && item.atMs > currentMs);
  }

  Future<ScheduleItem> add({
    required String title,
    required DateTime at,
  }) async {
    final result = await supervisor.call('schedule.add', {
      'title': title,
      'atMs': at.millisecondsSinceEpoch,
    });
    final item = _itemFrom(result);
    _upsert(item);
    notifyListeners();
    return item;
  }

  Future<ScheduleItem> update(
    String id, {
    required String title,
    DateTime? at,
  }) async {
    final params = <String, dynamic>{'id': id, 'title': title};
    if (at != null) params['atMs'] = at.millisecondsSinceEpoch;
    final result = await supervisor.call('schedule.update', params);
    final item = _itemFrom(result);
    _upsert(item);
    notifyListeners();
    return item;
  }

  Future<void> remove(String id) async {
    await supervisor.call('schedule.remove', {'id': id});
    _items = _items.where((item) => item.id != id).toList(growable: false);
    notifyListeners();
  }

  /// 删除所有已经提醒过的日程，返回实际删除数量。
  Future<int> clearExpired() async {
    final result = await supervisor.call('schedule.clearExpired');
    final removed = (result['removed'] as num?)?.toInt() ?? 0;
    if (removed > 0) {
      _items = _items.where((item) => !item.fired).toList(growable: false);
      notifyListeners();
    }
    return removed;
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
      final result = await supervisor.call('schedule.list');
      _applyList(result['items']);
      notifyListeners();
    } catch (error) {
      AppLog.write('[schedule] load failed: $error');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'schedule.updated':
        _applyList(event['items']);
        notifyListeners();
      case 'schedule.fired':
        final raw = event['item'];
        if (raw is! Map<String, dynamic>) return;
        final item = ScheduleItem.fromJson(raw);
        _upsert(item);
        _bannerItem = item;
        _revision++;
        notifyListeners();
    }
  }

  void _applyList(Object? raw) {
    if (raw is! List) return;
    final items = <ScheduleItem>[];
    for (final value in raw) {
      if (value is Map<String, dynamic>) {
        final item = ScheduleItem.fromJson(value);
        if (item.id.isNotEmpty) items.add(item);
      }
    }
    items.sort((left, right) => left.atMs.compareTo(right.atMs));
    _items = items;
  }

  void _upsert(ScheduleItem item) {
    final items = _items.where((value) => value.id != item.id).toList();
    items.add(item);
    items.sort((left, right) => left.atMs.compareTo(right.atMs));
    _items = List.unmodifiable(items);
  }

  ScheduleItem _itemFrom(Map<String, dynamic> result) {
    final raw = result['item'];
    if (raw is Map<String, dynamic>) return ScheduleItem.fromJson(raw);
    throw StateError('schedule response is missing an item');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
