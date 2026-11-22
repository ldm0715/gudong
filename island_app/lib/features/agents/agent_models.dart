// 本地 agent 的静态信息与 sidecar 推送的数据模型。

class AgentInfo {
  const AgentInfo({
    required this.id,
    required this.label,
    required this.detection,
    required this.asset,
  });

  final String id;
  final String label;
  final String detection;
  final String asset;
}

abstract final class AgentCatalog {
  static const List<AgentInfo> all = [
    AgentInfo(
      id: 'claude',
      label: 'Claude Code',
      detection: '会话注册表 + transcript',
      asset: 'assets/icons/agent-claude.png',
    ),
    AgentInfo(
      id: 'codex',
      label: 'Codex',
      detection: 'rollout 会话文件',
      asset: 'assets/icons/agent-codex.png',
    ),
    AgentInfo(
      id: 'dsh',
      label: 'DeepSeek Harness',
      detection: 'DSH_HOME 会话文件',
      asset: 'assets/icons/agent-deepseek.png',
    ),
    AgentInfo(
      id: 'pi',
      label: 'Pi',
      detection: '~/.pi 会话文件',
      asset: 'assets/icons/agent-pi.png',
    ),
    AgentInfo(
      id: 'omp',
      label: 'Oh My Pi',
      detection: '~/.omp 会话文件',
      asset: 'assets/icons/agent-omp.png',
    ),
  ];

  static AgentInfo? byId(String id) {
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<String> get ids =>
      all.map((item) => item.id).toList(growable: false);
}

class AgentSession {
  const AgentSession({
    required this.id,
    required this.label,
    required this.sessionId,
    required this.title,
    required this.state,
    required this.startedAtMs,
    required this.lastActiveAtMs,
    this.cwd,
  });

  final String id;
  final String label;
  final String sessionId;
  final String title;
  final String state;
  final int startedAtMs;
  final int lastActiveAtMs;
  final String? cwd;

  bool get waiting => state == 'waiting';

  factory AgentSession.fromJson(Map<String, dynamic> json) {
    return AgentSession(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      state: json['state']?.toString() ?? 'running',
      startedAtMs: _int(json['startedAtMs']),
      lastActiveAtMs: _int(json['lastActiveAtMs']),
      cwd: json['cwd']?.toString(),
    );
  }
}

class AgentStatus {
  const AgentStatus({
    required this.id,
    required this.label,
    required this.enabled,
    required this.available,
    required this.state,
    required this.sessionCount,
    required this.message,
  });

  final String id;
  final String label;
  final bool enabled;
  final bool available;
  final String state;
  final int sessionCount;
  final String message;

  factory AgentStatus.fromJson(Map<String, dynamic> json) {
    return AgentStatus(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      enabled: json['enabled'] == true,
      available: json['available'] == true,
      state: json['state']?.toString() ?? 'idle',
      sessionCount: _int(json['sessionCount']),
      message: json['message']?.toString() ?? '',
    );
  }
}

class AgentFinished {
  const AgentFinished({
    required this.id,
    required this.label,
    required this.sessionId,
    required this.title,
    required this.state,
    required this.endedAtMs,
    this.startedAtMs,
    this.durationMs,
    this.replyPreview,
    this.cwd,
  });

  final String id;
  final String label;
  final String sessionId;
  final String title;
  final String state;
  final int endedAtMs;
  final int? startedAtMs;
  final int? durationMs;
  final String? replyPreview;
  final String? cwd;

  bool get aborted => state == 'aborted';

  /// 同一回合去重：同一会话的同一结束时间只展示一次。
  String get key => '$id|$sessionId|$endedAtMs';

  factory AgentFinished.fromJson(Map<String, dynamic> json) {
    return AgentFinished(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      state: json['state']?.toString() ?? 'done',
      endedAtMs: _int(json['endedAtMs']),
      startedAtMs: _optionalInt(json['startedAtMs']),
      durationMs: _optionalInt(json['durationMs']),
      replyPreview: json['replyPreview']?.toString(),
      cwd: json['cwd']?.toString(),
    );
  }
}

String formatAgentClock(int milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatAgentDuration(int milliseconds) {
  final seconds = (milliseconds / 1000).round();
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (rest == 0) return '$minutes 分';
  return '$minutes 分 $rest 秒';
}

int _int(Object? value) => value is num ? value.toInt() : 0;

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;
