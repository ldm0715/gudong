import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'agent_models.dart';

/// 本地 agent 状态。sidecar 只读会话文件并把运行中的会话推过来。
class AgentController extends ChangeNotifier {
  AgentController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  List<AgentSession> _sessions = const [];
  List<AgentStatus> _statuses = const [];
  final List<AgentFinished> _finished = [];
  int _revision = 0;
  bool _loaded = false;

  List<AgentSession> get sessions => _sessions;
  List<AgentStatus> get statuses => _statuses;

  /// 队列或状态变化时递增，IslandController 用它触发横幅切换。
  int get revision => _revision;

  AgentFinished? get bannerItem =>
      _finished.isEmpty ? null : _finished.first;

  /// 收起态按 agent 去重后的运行中 id，保持 sidecar 的返回顺序。
  List<String> get runningAgentIds {
    final seen = <String>{};
    final ids = <String>[];
    for (final session in _sessions) {
      if (seen.add(session.id)) ids.add(session.id);
    }
    return ids;
  }

  bool isWaiting(String id) =>
      _sessions.any((session) => session.id == id && session.waiting);

  AgentStatus? status(String id) {
    for (final item in _statuses) {
      if (item.id == id) return item;
    }
    return null;
  }

  int sessionCount(String id) =>
      _sessions.where((session) => session.id == id).length;

  /// 横幅停留结束后由 IslandController 调用，露出队列里的下一条。
  void dismissBanner() {
    if (_finished.isEmpty) return;
    _finished.removeAt(0);
    _revision++;
    notifyListeners();
  }

  void _onSupervisorChanged() {
    if (!supervisor.ready) {
      _loaded = false;
      _sessions = const [];
      _statuses = const [];
      _finished.clear();
      _revision++;
      notifyListeners();
      return;
    }
    if (_loaded) return;
    _loaded = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await supervisor.call('agents.get');
      _apply(result);
      _revision++;
      notifyListeners();
    } catch (error) {
      AppLog.write('[agent] load failed: $error');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'agent.updated':
        _apply(event);
        _revision++;
        notifyListeners();
      case 'agent.finished':
        final item = AgentFinished.fromJson(event);
        if (item.id.isEmpty || item.sessionId.isEmpty) return;
        if (_finished.any((entry) => entry.key == item.key)) return;
        if (_finished.length >= 8) _finished.removeAt(0);
        _finished.add(item);
        _revision++;
        notifyListeners();
    }
  }

  void _apply(Map<String, dynamic> payload) {
    final sessions = payload['sessions'];
    if (sessions is List) {
      _sessions = [
        for (final item in sessions)
          if (item is Map) AgentSession.fromJson(Map<String, dynamic>.from(item)),
      ];
    } else {
      _sessions = const [];
    }

    final agents = payload['agents'];
    if (agents is List) {
      _statuses = [
        for (final item in agents)
          if (item is Map) AgentStatus.fromJson(Map<String, dynamic>.from(item)),
      ];
    } else {
      _statuses = const [];
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
