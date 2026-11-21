import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'shelf_models.dart';

/// 中转站状态。条目由 sidecar 推送，Flutter 只负责接收拖入和发起拖出。
class ShelfController extends ChangeNotifier {
  ShelfController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loaded = false;
  List<ShelfItem> _items = const [];
  bool _dragActive = false;
  String? _notice;
  Timer? _noticeTimer;
  final Map<String, Uint8List> _icons = {};
  int _dropRevision = 0;
  bool _selecting = false;
  final Set<String> _selected = {};
  Set<String> _removing = const {};

  List<ShelfItem> get items => _items;

  /// 是否处于多选模式。
  bool get selecting => _selecting;

  /// 已选中的条目 id。
  Set<String> get selected => _selected;

  /// 已选中的条目，按列表顺序。
  List<ShelfItem> get selectedItems => _items
      .where((item) => _selected.contains(item.id))
      .toList(growable: false);

  bool isSelected(String id) => _selected.contains(id);

  bool isRemoving(String id) => _removing.contains(id);

  void toggleSelecting() {
    _selecting = !_selecting;
    if (!_selecting) _selected.clear();
    notifyListeners();
  }

  void toggleSelected(String id) {
    if (!_selected.remove(id)) _selected.add(id);
    _selecting = true;
    notifyListeners();
  }

  void clearSelection() {
    if (!_selecting && _selected.isEmpty) return;
    _selecting = false;
    _selected.clear();
    notifyListeners();
  }

  /// 系统缩略图 / 图标，已解码成 PNG 字节。
  Uint8List? iconFor(ShelfItem item) => _icons[item.id];

  /// 每次有新条目真正放入时递增，界面据此播放一次放下闪光。
  int get dropRevision => _dropRevision;

  /// 外部文件正悬停在岛体上。
  bool get dragActive => _dragActive;

  String? get notice => _notice;

  void setDragActive(bool value) {
    if (_dragActive == value) return;
    _dragActive = value;
    notifyListeners();
  }

  Future<void> addPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      // 一次拖入多个文件时 sidecar 要逐个读元数据，网络盘可能较慢。
      final result = await supervisor.call('shelf.add', {
        'paths': paths,
      }, const Duration(seconds: 15));
      _applyList(result['items']);
      if (result['added'] is List && (result['added'] as List).isNotEmpty) {
        _dropRevision++;
      }
      _setNotice(_skipNotice(result['skipped']));
      notifyListeners();
    } catch (error) {
      AppLog.write('[shelf] add failed: $error');
      _setNotice('加入中转站失败');
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    try {
      await supervisor.call('shelf.remove', {'id': id});
      _items = _items.where((item) => item.id != id).toList(growable: false);
      _icons.remove(id);
      _selected.remove(id);
      notifyListeners();
    } catch (error) {
      AppLog.write('[shelf] remove failed: $error');
      _setNotice('移除失败');
      notifyListeners();
    }
  }

  Future<int> clear() async {
    try {
      final result = await supervisor.call('shelf.clear');
      final removed = (result['removed'] as num?)?.toInt() ?? 0;
      _items = const [];
      _icons.clear();
      _selected.clear();
      _removing = const {};
      _selecting = false;
      notifyListeners();
      return removed;
    } catch (error) {
      AppLog.write('[shelf] clear failed: $error');
      _setNotice('清空失败');
      notifyListeners();
      return 0;
    }
  }

  /// 批量删除：先让选中的行淡出，再一次性从 sidecar 删除。
  Future<void> removeSelected() async {
    if (_selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    _removing = ids;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 170));
    try {
      await supervisor.call('shelf.removeMany', {'ids': ids.toList()});
      _items = _items
          .where((item) => !ids.contains(item.id))
          .toList(growable: false);
      for (final id in ids) {
        _icons.remove(id);
      }
    } catch (error) {
      AppLog.write('[shelf] removeMany failed: $error');
      _setNotice('批量移除失败');
    } finally {
      _removing = const {};
      _selected.clear();
      _selecting = false;
      notifyListeners();
    }
  }

  Future<void> reveal(ShelfItem item) async {
    if (item.missing) return;
    try {
      await supervisor.call('shelf.reveal', {'id': item.id});
    } catch (error) {
      AppLog.write('[shelf] reveal failed: $error');
      _setNotice('无法定位文件');
      notifyListeners();
    }
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
      final result = await supervisor.call('shelf.list');
      _applyList(result['items']);
      notifyListeners();
    } catch (error) {
      AppLog.write('[shelf] load failed: $error');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'shelf.updated':
        _applyList(event['items']);
        notifyListeners();
      case 'shelf.icon':
        final id = event['id']?.toString();
        final data = event['data']?.toString();
        if (id == null || id.isEmpty || data == null || data.isEmpty) return;
        try {
          final comma = data.indexOf(',');
          _icons[id] = base64Decode(
            comma >= 0 ? data.substring(comma + 1) : data,
          );
          notifyListeners();
        } catch (error) {
          AppLog.write('[shelf] icon decode failed: $error');
        }
    }
  }

  void _applyList(Object? raw) {
    if (raw is! List) return;
    final items = <ShelfItem>[];
    for (final value in raw) {
      if (value is Map<String, dynamic>) {
        final item = ShelfItem.fromJson(value);
        if (item.id.isNotEmpty) items.add(item);
      }
    }
    _items = List.unmodifiable(items);
    final ids = items.map((item) => item.id).toSet();
    _icons.removeWhere((id, _) => !ids.contains(id));
    _selected.removeWhere((id) => !ids.contains(id));
  }

  String? _skipNotice(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    var limit = 0;
    var missing = 0;
    for (final value in raw) {
      if (value is! Map<String, dynamic>) continue;
      switch (value['reason']) {
        case 'limit':
          limit++;
        case 'missing':
          missing++;
      }
    }
    if (limit > 0) return '中转站已满，$limit 个文件未加入';
    if (missing > 0) return '$missing 个路径不存在';
    return '部分路径无效';
  }

  void _setNotice(String? text) {
    _noticeTimer?.cancel();
    _notice = text;
    if (text == null) return;
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      _notice = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
