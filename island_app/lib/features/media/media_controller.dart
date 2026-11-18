import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';

/// 媒体状态占位。Phase 2 接入 SMTC 后由 `media.changed` 事件刷新。
class MediaController extends ChangeNotifier {
  MediaController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loaded = false;

  String? title;
  String? artist;
  bool playing = false;
  bool available = false;

  Future<void> refresh() async {
    try {
      final result = await supervisor.call('media.get');
      _apply(result);
      notifyListeners();
    } catch (error) {
      AppLog.write('[media] refresh failed: $error');
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
    if (event['type'] != 'media.changed') return;
    _apply(event);
    notifyListeners();
  }

  void _apply(Map<String, dynamic> payload) {
    available = payload['available'] == true;
    playing = payload['playing'] == true;
    title = payload['title']?.toString();
    artist = payload['artist']?.toString();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
