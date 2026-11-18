import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/click_through/click_through_controller.dart';
import 'core/ipc/sidecar_supervisor.dart';
import 'core/log.dart';
import 'core/settings/settings_controller.dart';
import 'core/theme/island_colors.dart';
import 'core/window/window_position.dart';
import 'features/diagnostics/diagnostics_controller.dart';
import 'features/island/island_controller.dart';
import 'features/island/island_shell.dart';
import 'features/media/media_controller.dart';
import 'features/messages/messages_controller.dart';
import 'features/settings/settings_window_launcher.dart';
import 'features/weather/weather_controller.dart';

/// 应用级依赖集合，由 main 组装，退出时统一释放。
class AppScope {
  AppScope({
    required this.supervisor,
    required this.island,
    required this.messages,
    required this.weather,
    required this.media,
    required this.diagnostics,
    required this.settings,
    required this.settingsWindow,
    required this.windowPosition,
    required this.clickThrough,
  });

  final SidecarSupervisor supervisor;
  final IslandController island;
  final MessagesController messages;
  final WeatherController weather;
  final MediaController media;
  final DiagnosticsController diagnostics;
  final SettingsController settings;
  final SettingsWindowLauncher settingsWindow;
  final WindowPositionKeeper windowPosition;
  final ClickThroughController clickThrough;

  Future<void> dispose() async {
    await settingsWindow.dispose();
    windowPosition.dispose();
    island.dispose();
    messages.dispose();
    weather.dispose();
    media.dispose();
    diagnostics.dispose();
    settings.dispose();
    await supervisor.close();
    clickThrough.dispose();
    await AppLog.close();
  }
}

class GuduoApp extends StatefulWidget {
  const GuduoApp({super.key, required this.scope});

  final AppScope scope;

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
          MenuItem(
            key: 'settings',
            label: '设置',
            onClick: (_) => unawaited(widget.scope.settingsWindow.open()),
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
          widget.scope.island.toggleExpanded();
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
    if (expand) widget.scope.island.setExpanded(true);
  }

  Future<void> _toggleFromTray() async {
    await _showWindow();
    widget.scope.island.toggleExpanded();
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
    await widget.scope.dispose();
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
    return AnimatedBuilder(
      animation: widget.scope.settings,
      builder: (context, _) {
        final colors = IslandColors.byId(
          widget.scope.settings.settings.themeId,
        );
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Guduo Island',
          theme: ThemeData(
            brightness: colors.brightness,
            scaffoldBackgroundColor: Colors.transparent,
            fontFamily: 'Microsoft YaHei UI',
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            extensions: [colors],
          ),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: IslandShell(
              island: widget.scope.island,
              messages: widget.scope.messages,
              weather: widget.scope.weather,
              media: widget.scope.media,
              diagnostics: widget.scope.diagnostics,
              settings: widget.scope.settings,
              windowPosition: widget.scope.windowPosition,
              onOpenSettings: () =>
                  unawaited(widget.scope.settingsWindow.open()),
            ),
          ),
        );
      },
    );
  }
}
