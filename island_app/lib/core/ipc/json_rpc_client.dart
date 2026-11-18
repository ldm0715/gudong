import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../log.dart';

/// stdio JSON-RPC 2.0 客户端：一行一个 JSON，请求按 id 关联，事件直接转发。
class JsonRpcClient {
  JsonRpcClient(this.process) {
    _subscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: _onError, onDone: _onDone);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => AppLog.write('[sidecar] $line'));
  }

  final Process process;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<Map<String, dynamic>> _events =
      StreamController.broadcast();
  final Completer<void> _done = Completer<void>();
  StreamSubscription<String>? _subscription;
  int _nextId = 1;
  bool _closed = false;

  Stream<Map<String, dynamic>> get events => _events.stream;
  Future<void> get done => _done.future;
  bool get isClosed => _closed;

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) {
    if (_closed) {
      return Future.error(StateError('sidecar is not connected'));
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final line = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    process.stdin.add(utf8.encode('$line\n'));
    process.stdin.flush().catchError((_) {});
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('rpc timeout: $method');
      },
    );
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(line) as Map<String, dynamic>;
    } catch (error) {
      AppLog.write('[ipc] invalid line: $line');
      return;
    }
    final id = message['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null) return;
      final error = message['error'];
      if (error is Map<String, dynamic>) {
        completer.completeError(
          RpcException(
            error['code'] is int ? error['code'] as int : -1,
            error['message']?.toString() ?? 'unknown error',
          ),
        );
      } else {
        final result = message['result'];
        completer.complete(
          result is Map<String, dynamic> ? result : <String, dynamic>{},
        );
      }
      return;
    }
    if (message['method'] == 'event') {
      final params = message['params'];
      if (params is Map<String, dynamic>) {
        _events.add(params);
      }
    }
  }

  void _onError(Object error) {
    AppLog.write('[ipc] stdout error: $error');
  }

  void _onDone() {
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('sidecar exited'));
      }
    }
    _pending.clear();
    if (!_events.isClosed) _events.close();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> dispose() async {
    _closed = true;
    await _subscription?.cancel();
    await _events.close();
    try {
      process.kill();
    } catch (_) {}
  }
}

class RpcException implements Exception {
  RpcException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'RpcException($code): $message';
}
