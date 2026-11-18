import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../log.dart';
import 'json_rpc_client.dart';

enum SidecarPhase {
  starting,
  ready,
  reconnecting,
  unavailable,
  incompatible,
  stopped,
}

/// sidecar 生命周期管理：启动、握手、心跳、崩溃退避重启、退出清理。
class SidecarSupervisor extends ChangeNotifier {
  SidecarSupervisor() {
    _events = StreamController<Map<String, dynamic>>.broadcast();
  }

  static const int apiVersion = 1;
  static const List<Duration> _backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  late final StreamController<Map<String, dynamic>> _events;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  JsonRpcClient? _client;
  Timer? _heartbeat;
  Timer? _restartTimer;
  int _restartAttempt = 0;
  int _heartbeatFailures = 0;
  bool _disposed = false;
  bool _launching = false;

  SidecarPhase _phase = SidecarPhase.starting;
  String _detail = '正在启动 sidecar';
  String? _binaryPath;
  String _version = 'unknown';
  Set<String> _capabilities = const {};

  SidecarPhase get phase => _phase;
  String get detail => _detail;
  String? get binaryPath => _binaryPath;
  String get version => _version;
  Set<String> get capabilities => _capabilities;
  bool get ready => _phase == SidecarPhase.ready;
  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> start() async {
    await _launch();
  }

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) {
    final client = _client;
    if (client == null || client.isClosed) {
      return Future.error(StateError('sidecar is not connected'));
    }
    return client.call(method, params);
  }

  Future<void> _launch() async {
    if (_disposed || _launching) return;
    _launching = true;
    _restartTimer?.cancel();
    _setPhase(SidecarPhase.starting, '正在启动 sidecar');
    try {
      final path = _resolveBinary();
      if (path == null) {
        _setPhase(
          SidecarPhase.unavailable,
          '未找到 island_service.exe，请先运行 island_service 构建，或设置 ISLAND_SERVICE 环境变量',
        );
        _scheduleRestart(const Duration(seconds: 5));
        return;
      }
      _binaryPath = path;
      AppLog.write('[sidecar] launching $path');
      final process = await Process.start(
        path,
        const [],
        workingDirectory: File(path).parent.path,
        mode: ProcessStartMode.normal,
      );
      final client = JsonRpcClient(process);
      _client = client;
      _eventSubscription = client.events.listen(_events.add);
      unawaited(client.done.then((_) => _onExit(client)));

      final hello = await client
          .call('app.hello', {'apiVersion': apiVersion})
          .timeout(const Duration(seconds: 4));
      if (_disposed) return;
      _version = hello['version']?.toString() ?? 'unknown';
      final capabilities = hello['capabilities'];
      _capabilities = capabilities is List
          ? capabilities.map((value) => value.toString()).toSet()
          : const {};
      _heartbeatFailures = 0;
      _restartAttempt = 0;
      AppLog.write('[sidecar] ready v$_version');
      _setPhase(SidecarPhase.ready, 'sidecar $_version 已连接');
      // 只广播连接结果，功能数据由各自的 controller 主动拉取。
      _events.add({
        'type': 'sidecar.connected',
        'version': _version,
        'capabilities': _capabilities.toList(growable: false),
      });
      _startHeartbeat();
    } catch (error) {
      AppLog.write('[sidecar] launch failed: $error');
      await _client?.dispose();
      _client = null;
      // 版本不匹配重试也不会变好，停在不可恢复状态等用户升级。
      if (error is RpcException && error.code == RpcErrorCode.versionMismatch) {
        _setPhase(SidecarPhase.incompatible, 'sidecar 与客户端版本不兼容，请升级');
        return;
      }
      _setPhase(SidecarPhase.reconnecting, 'sidecar 启动失败：$error');
      _scheduleRestart(_backoff[0]);
    } finally {
      _launching = false;
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_disposed) return;
      final client = _client;
      if (client == null) return;
      try {
        await client.call('app.ping').timeout(const Duration(seconds: 3));
        _heartbeatFailures = 0;
      } catch (error) {
        _heartbeatFailures++;
        AppLog.write(
          '[sidecar] heartbeat failed ($_heartbeatFailures): $error',
        );
        if (_heartbeatFailures >= 2) {
          await _restart('心跳超时');
        }
      }
    });
  }

  Future<void> _restart(String reason) async {
    if (_disposed) return;
    _heartbeat?.cancel();
    _heartbeat = null;
    _heartbeatFailures = 0;
    final client = _client;
    _client = null;
    await client?.dispose();
    _setPhase(SidecarPhase.reconnecting, reason);
    _scheduleRestart(_backoff[_backoffIndex]);
    _restartAttempt++;
  }

  void _onExit(JsonRpcClient client) {
    if (_disposed || _client != client) return;
    AppLog.write('[sidecar] exited');
    _client = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _setPhase(SidecarPhase.reconnecting, 'sidecar 已退出，正在重启');
    _scheduleRestart(_backoff[_backoffIndex]);
    _restartAttempt++;
  }

  void _scheduleRestart(Duration delay) {
    if (_disposed) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      if (!_disposed) unawaited(_launch());
    });
  }

  void _setPhase(SidecarPhase phase, String detail) {
    _phase = phase;
    _detail = detail;
    AppLog.write('[sidecar] phase=${phase.name} $detail');
    if (!_disposed) notifyListeners();
  }

  String? _resolveBinary() {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;
    final env = Platform.environment['ISLAND_SERVICE'];
    final candidates = <String>[
      if (env != null && env.isNotEmpty) env,
      '$executableDir\\island_service.exe',
      '$cwd\\..\\island_service\\target\\release\\island_service.exe',
      '$cwd\\..\\island_service\\target\\debug\\island_service.exe',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  int get _backoffIndex =>
      _restartAttempt < _backoff.length ? _restartAttempt : _backoff.length - 1;

  Future<void> _shutdown() async {
    final client = _client;
    if (client != null && !client.isClosed) {
      try {
        await client
            .call('app.shutdown')
            .timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
  }

  /// 异步清理。`dispose` 是 ChangeNotifier 的同步入口，内部走这里。
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _heartbeat?.cancel();
    _restartTimer?.cancel();
    await _shutdown();
    await _eventSubscription?.cancel();
    await _client?.dispose();
    _client = null;
    await _events.close();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
