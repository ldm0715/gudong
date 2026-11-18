import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 简单文件日志：控制台 + `%LOCALAPPDATA%\guduo\logs\`。
///
/// `app.log` 记录运行日志，`crash.log` 只记未捕获异常，避免被高频日志淹没。
/// 单文件超过 1MB 时轮换为 `*.old.log`。
class AppLog {
  static const int _maxBytes = 1024 * 1024;
  static IOSink? _sink;
  static IOSink? _crashSink;
  static bool _initialized = false;

  static String? get logDir {
    final base = Platform.environment['LOCALAPPDATA'];
    return base == null ? null : '$base\\guduo\\logs';
  }

  static void init({
    String appLog = 'app.log',
    String crashLog = 'crash.log',
  }) {
    if (_initialized) return;
    _initialized = true;
    _sink = _open(appLog);
    _crashSink = _open(crashLog);
  }

  static IOSink? _open(String name) {
    final dir = logDir;
    if (dir == null) return null;
    try {
      Directory(dir).createSync(recursive: true);
      final file = File('$dir\\$name');
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        final rotated = File('$dir\\${name.replaceFirst('.log', '.old.log')}');
        if (rotated.existsSync()) rotated.deleteSync();
        file.renameSync(rotated.path);
      }
      return file.openWrite(mode: FileMode.append);
    } catch (_) {
      return null;
    }
  }

  static void write(String line) {
    debugPrint(line);
    _sink?.writeln('${DateTime.now().toIso8601String()} $line');
  }

  /// 极早期日志（单实例退出等）。不依赖 [init]，也避免和主实例抢 `app.log`。
  static void writeDetached(String line) {
    final dir = logDir;
    if (dir == null) return;
    try {
      Directory(dir).createSync(recursive: true);
      File('$dir\\instance.log').writeAsStringSync(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  /// 未捕获异常入口。写完立即 flush，尽量保住崩溃前的最后一条。
  static void crash(String line) {
    debugPrint(line);
    final sink = _crashSink;
    if (sink == null) return;
    sink.writeln('${DateTime.now().toIso8601String()} $line');
    unawaited(sink.flush());
  }

  static Future<void> close() async {
    await _sink?.flush();
    await _crashSink?.flush();
    await _sink?.close();
    await _crashSink?.close();
    _sink = null;
    _crashSink = null;
  }
}
