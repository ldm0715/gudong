import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'anniversary_models.dart';

/// 倒计时 / 纪念日状态。列表由 sidecar 推送，客户端只发增删改请求。
class AnniversaryController extends ChangeNotifier {
  AnniversaryController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loaded = false;
  List<AnniversaryItem> _items = const [];

  /// 按日期升序排列的全部条目。
  List<AnniversaryItem> get items => _items;

  Future<AnniversaryItem> add({
    required String title,
    required String date,
  }) async {
    final result = await supervisor.call('anniversary.add', {
      'title': title,
      'date': date,
    });
    final item = _itemFrom(result);
    _upsert(item);
    notifyListeners();
    return item;
  }

  Future<AnniversaryItem> update(
    String id, {
    required String title,
    required String date,
  }) async {
    final result = await supervisor.call('anniversary.update', {
      'id': id,
      'title': title,
      'date': date,
    });
    final item = _itemFrom(result);
    _upsert(item);
    notifyListeners();
    return item;
  }

  Future<void> remove(String id) async {
    await supervisor.call('anniversary.remove', {'id': id});
    _items = _items.where((item) => item.id != id).toList(growable: false);
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
      final result = await supervisor.call('anniversary.list');
      _applyList(result['items']);
      notifyListeners();
    } catch (error) {
      AppLog.write('[anniversary] load failed: $error');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] != 'anniversary.updated') return;
    _applyList(event['items']);
    notifyListeners();
  }

  void _applyList(Object? raw) {
    if (raw is! List) return;
    final items = <AnniversaryItem>[];
    for (final value in raw) {
      if (value is Map<String, dynamic>) {
        final item = AnniversaryItem.fromJson(value);
        if (item.id.isNotEmpty) items.add(item);
      }
    }
    items.sort((left, right) => left.date.compareTo(right.date));
    _items = List.unmodifiable(items);
  }

  void _upsert(AnniversaryItem item) {
    final items = _items.where((value) => value.id != item.id).toList();
    items.add(item);
    items.sort((left, right) => left.date.compareTo(right.date));
    _items = List.unmodifiable(items);
  }

  AnniversaryItem _itemFrom(Map<String, dynamic> result) {
    final raw = result['item'];
    if (raw is Map<String, dynamic>) return AnniversaryItem.fromJson(raw);
    throw StateError('anniversary response is missing an item');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
