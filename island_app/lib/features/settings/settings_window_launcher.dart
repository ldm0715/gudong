import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../../core/log.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import 'settings_window_args.dart';

/// 主窗口侧：打开 / 复用独立设置窗口，并接收设置窗口的保存请求。
class SettingsWindowLauncher {
  SettingsWindowLauncher(this.settings) {
    unawaited(_register());
  }

  final SettingsController settings;
  static const _channel = WindowMethodChannel(
    'guduo.settings',
    mode: ChannelMode.unidirectional,
  );

  Future<void> _register() async {
    try {
      await _channel.setMethodCallHandler(_onCall);
    } catch (error) {
      AppLog.write('[settings-window] channel register failed: $error');
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method != 'save') return null;
    final raw = call.arguments;
    if (raw is! Map) return {'ok': false};
    try {
      // 设置窗口只负责皮肤与功能开关，窗口位置等状态以主进程为准，
      // 否则会和拖拽保存互相覆盖。
      final incoming = AppSettings.fromJson(Map<String, dynamic>.from(raw));
      await settings.save(
        settings.settings.copyWith(
          themeId: incoming.themeId,
          showWeather: incoming.showWeather,
          mediaEnabled: incoming.mediaEnabled,
          showPlayingIndicator: incoming.showPlayingIndicator,
          tabOrder: incoming.tabOrder,
          hiddenTabs: incoming.hiddenTabs,
        ),
      );
      return {'ok': true};
    } catch (error) {
      AppLog.write('[settings-window] save failed: $error');
      return {'ok': false};
    }
  }

  Future<void> open() async {
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (SettingsWindowArguments.tryParse(window.arguments) == null) {
          continue;
        }
        // 窗口已存在：叫到前面，不重复创建。
        await window.invokeMethod('focus');
        await window.show();
        return;
      }
      await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: SettingsWindowArguments(
            settings: settings.settings,
          ).encode(),
        ),
      );
    } catch (error) {
      AppLog.write('[settings-window] open failed: $error');
    }
  }

  /// 退出应用时关闭设置窗口，避免留下孤儿窗口。
  Future<void> dispose() async {
    try {
      final windows = await WindowController.getAll().timeout(
        const Duration(milliseconds: 800),
      );
      for (final window in windows) {
        if (SettingsWindowArguments.tryParse(window.arguments) == null) {
          continue;
        }
        try {
          await window
              .invokeMethod('close')
              .timeout(const Duration(milliseconds: 500));
        } catch (_) {}
      }
    } catch (error) {
      AppLog.write('[settings-window] close failed: $error');
    }
  }
}
