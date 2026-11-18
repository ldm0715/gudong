import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/click_through/click_through_controller.dart';
import 'core/ipc/sidecar_supervisor.dart';
import 'core/log.dart';
import 'features/island/island_controller.dart';
import 'features/island/island_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.init();
  AppLog.write('[app] bootstrap start');
  await windowManager.ensureInitialized();

  await _prepareWindow();

  final supervisor = SidecarSupervisor();
  final controller = IslandController(supervisor);
  final clickThrough = ClickThroughController();
  clickThrough.setInteractiveRect(ClickThroughController.collapsedRect);
  controller.addListener(() {
    clickThrough.setInteractiveRect(
      controller.expanded
          ? ClickThroughController.expandedRect
          : controller.showBanner
          ? ClickThroughController.notificationRect
          : ClickThroughController.collapsedRect,
    );
  });
  // 悬停展开 / 收起：命中状态来自 16ms 的光标轮询，不依赖 Flutter 的
  // MouseRegion 事件，穿透状态下也能可靠触发。
  clickThrough.pointerInside.addListener(() {
    controller.setExpanded(clickThrough.pointerInside.value);
  });

  runApp(
    GuduoApp(
      supervisor: supervisor,
      controller: controller,
      clickThrough: clickThrough,
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(supervisor.start());
    unawaited(clickThrough.start());
  });
}

/// 窗口只配置一次。热重启时窗口已存在且可见，再等 readyToShow 会永久挂起，
/// 导致 runApp 永远不执行、界面卡死。
Future<void> _prepareWindow() async {
  if (await windowManager.isVisible()) {
    AppLog.write('[app] window already visible, skip setup');
    return;
  }

  const windowOptions = WindowOptions(
    size: Size(420, 300),
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
      await windowManager.setSize(const Size(420, 300));
      await windowManager.setAlignment(Alignment.topCenter);
      final position = await windowManager.getPosition();
      await windowManager.setPosition(Offset(position.dx, position.dy + 8));
      await windowManager.setPreventClose(true);
      await windowManager.show();
      AppLog.write('[app] window shown');
    } catch (error, stack) {
      AppLog.write('[app] window setup failed: $error\n$stack');
      try {
        await windowManager.show();
      } catch (_) {}
    }
  });
}

class GuduoApp extends StatefulWidget {
  const GuduoApp({
    super.key,
    required this.supervisor,
    required this.controller,
    required this.clickThrough,
  });

  final SidecarSupervisor supervisor;
  final IslandController controller;
  final ClickThroughController clickThrough;

  @override
  State<GuduoApp> createState() => _GuduoAppState();
}

class _GuduoAppState extends State<GuduoApp> with WindowListener, TrayListener {
  HotKey? _hotKey;
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    unawaited(_setupTray());
    unawaited(_setupHotKey());
  }

  Future<void> _setupTray() async {
    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('Guduo Island');
      final menu = Menu(
        items: [
          MenuItem(
            key: 'toggle',
            label: '展开 / 收起',
            onClick: (_) => _toggleFromTray(),
          ),
          MenuItem(
            key: 'show',
            label: '显示岛体',
            onClick: (_) => unawaited(_showWindow()),
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit',
            label: '退出',
            onClick: (_) => unawaited(_quit()),
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (error) {
      AppLog.write('[tray] setup failed: $error');
    }
  }

  Future<void> _setupHotKey() async {
    try {
      final hotKey = HotKey(
        identifier: 'guduo.toggle',
        key: PhysicalKeyboardKey.space,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      );
      await HotKeyManager.instance.register(
        hotKey,
        keyDownHandler: (_) {
          unawaited(_showWindow());
          widget.controller.toggleExpanded();
        },
      );
      _hotKey = hotKey;
    } catch (error) {
      AppLog.write('[hotkey] register failed: $error');
    }
  }

  Future<void> _showWindow({bool expand = false}) async {
    if (!await windowManager.isVisible()) {
      await windowManager.show();
    }
    try {
      await windowManager.focus();
    } catch (error) {
      AppLog.write('[app] focus failed: $error');
    }
    if (expand) widget.controller.setExpanded(true);
  }

  Future<void> _toggleFromTray() async {
    await _showWindow();
    widget.controller.toggleExpanded();
  }

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    AppLog.write('[app] quitting');
    final hotKey = _hotKey;
    if (hotKey != null) {
      try {
        await HotKeyManager.instance.unregister(hotKey);
      } catch (_) {}
    }
    try {
      await trayManager.destroy();
    } catch (_) {}
    await widget.supervisor.close();
    widget.controller.dispose();
    widget.clickThrough.dispose();
    await AppLog.close();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    unawaited(windowManager.hide());
  }

  @override
  void onTrayIconMouseDown() {
    // 左键单击托盘图标：显示窗口并展开，避免第二次点击反而收起。
    unawaited(_showWindow(expand: true));
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Guduo Island',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Microsoft YaHei UI',
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: IslandView(controller: widget.controller),
      ),
    );
  }
}
