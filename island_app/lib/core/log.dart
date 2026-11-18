import 'dart:io';

import 'package:flutter/foundation.dart';

/// 简单文件日志：同时输出到 debug console，写入 %LOCALAPPDATA%\guduo\logs\app.log。
class AppLog {
  static IOSink? _sink;
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    try {
      final base = Platform.environment['LOCALAPPDATA'];
      if (base == null) return;
      final dir = Directory('$base\\guduo\\logs');
      dir.createSync(recursive: true);
      final file = File('${dir.path}\\app.log');
      // 单文件超过 1MB 时轮换，避免长期挂机把磁盘写满。
      if (file.existsSync() && file.lengthSync() > 1024 * 1024) {
        final rotated = File('${dir.path}\\app.old.log');
        if (rotated.existsSync()) rotated.deleteSync();
        file.renameSync(rotated.path);
      }
      _sink = file.openWrite(mode: FileMode.append);
    } catch (_) {
      _sink = null;
    }
  }

  static void write(String line) {
    debugPrint(line);
    final sink = _sink;
    if (sink == null) return;
    final now = DateTime.now().toIso8601String();
    sink.writeln('$now $line');
  }

  static Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
