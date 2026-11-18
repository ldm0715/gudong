import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../log.dart';

/// 主窗口画布尺寸。岛体布局在这个画布内居中摆放。
const Size appWindowSize = Size(420, 300);

/// 窗口只配置一次。热重启时窗口已存在且可见，再等 readyToShow 会永久挂起，
/// 导致 runApp 永远不执行、界面卡死。
Future<void> prepareAppWindow() async {
  if (await windowManager.isVisible()) {
    AppLog.write('[window] already visible, skip setup');
    return;
  }

  const windowOptions = WindowOptions(
    size: appWindowSize,
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
    title: 'guduo_island',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  // 配置必须在首帧之前完成，否则会闪出 1280x720 的默认窗口。
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    try {
      await windowManager.setAsFrameless();
      await windowManager.setResizable(false);
      // Windows 版 window_manager 没有实现 setMovable，无边框窗口本身不可拖动。
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setTitle('guduo_island');
      await windowManager.setSize(appWindowSize);
      await windowManager.setAlignment(Alignment.topCenter);
      final position = await windowManager.getPosition();
      await windowManager.setPosition(Offset(position.dx, position.dy + 8));
      await windowManager.setPreventClose(true);
      await windowManager.show();
      AppLog.write('[window] shown');
    } catch (error, stack) {
      AppLog.write('[window] setup failed: $error\n$stack');
      try {
        await windowManager.show();
      } catch (_) {}
    }
  });
}
