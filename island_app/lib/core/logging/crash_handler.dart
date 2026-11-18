import 'package:flutter/foundation.dart';

import '../log.dart';

/// 捕获 Flutter 框架与 isolate 的未处理异常，写入 crash.log。
abstract final class CrashHandler {
  static void install() {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      AppLog.crash(
        '[flutter] ${details.exceptionAsString()}\n'
        '${details.stack ?? StackTrace.empty}',
      );
      if (previousOnError != null) {
        previousOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLog.crash('[isolate] $error\n$stack');
      return true;
    };
  }
}
