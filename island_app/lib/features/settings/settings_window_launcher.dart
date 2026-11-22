import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../../core/log.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../agents/agent_bridge.dart';
import '../mail/mail_bridge.dart';
import '../quota/quota_bridge.dart';
import '../translate/translate_bridge.dart';
import '../weather/weather_bridge.dart';
import 'settings_window_args.dart';

/// 主窗口侧：打开 / 复用独立设置窗口，并接收设置窗口的保存请求。
class SettingsWindowLauncher {
  SettingsWindowLauncher(this.settings) {
    unawaited(_register());
  }

  final SettingsController settings;
  static const _channel = WindowMethodChannel(
    'gudong.settings',
    mode: ChannelMode.unidirectional,
  );

  Future<void> _register() async {
    try {
      await _channel.setMethodCallHandler(_onCall);
    } catch (error) {
      AppLog.write('[settings-window] channel register failed: $error');
    }
    try {
      await translateChannel.setMethodCallHandler(_onTranslateCall);
    } catch (error) {
      AppLog.write(
        '[settings-window] translate channel register failed: $error',
      );
    }
    try {
      await mailChannel.setMethodCallHandler(_onMailCall);
    } catch (error) {
      AppLog.write('[settings-window] mail channel register failed: $error');
    }
    try {
      await quotaChannel.setMethodCallHandler(_onQuotaCall);
    } catch (error) {
      AppLog.write('[settings-window] quota channel register failed: $error');
    }
    try {
      await weatherChannel.setMethodCallHandler(_onWeatherCall);
    } catch (error) {
      AppLog.write('[settings-window] weather channel register failed: $error');
    }
    try {
      await agentChannel.setMethodCallHandler(_onAgentCall);
    } catch (error) {
      AppLog.write('[settings-window] agent channel register failed: $error');
    }
  }

  /// 设置窗口的 Agent 状态经主窗口转发给 sidecar。
  Future<dynamic> _onAgentCall(MethodCall call) async {
    try {
      return switch (call.method) {
        'get' => await settings.supervisor.call(
          'agents.get',
          const {},
          const Duration(seconds: 5),
        ),
        _ => throw PlatformException(
          code: 'METHOD_NOT_FOUND',
          message: 'agent method not found: ${call.method}',
        ),
      };
    } catch (error) {
      AppLog.write('[settings-window] agent ${call.method} failed: $error');
      rethrow;
    }
  }

  /// 设置窗口的地点搜索经主窗口转发给 sidecar。
  Future<dynamic> _onWeatherCall(MethodCall call) async {
    final arguments = call.arguments is Map
        ? Map<String, dynamic>.from(call.arguments as Map)
        : <String, dynamic>{};
    try {
      return switch (call.method) {
        'search' => await settings.supervisor.call(
          'weather.search',
          arguments,
          const Duration(seconds: 20),
        ),
        _ => throw PlatformException(
          code: 'METHOD_NOT_FOUND',
          message: 'weather method not found: ${call.method}',
        ),
      };
    } catch (error) {
      AppLog.write('[settings-window] weather ${call.method} failed: $error');
      rethrow;
    }
  }

  /// 设置窗口的额度凭据与刷新操作统一转发给 sidecar。
  Future<dynamic> _onQuotaCall(MethodCall call) async {
    final arguments = call.arguments is Map
        ? Map<String, dynamic>.from(call.arguments as Map)
        : <String, dynamic>{};
    try {
      return switch (call.method) {
        'setSecret' => await settings.supervisor.call(
          'quota.setSecret',
          arguments,
          const Duration(seconds: 10),
        ),
        'refresh' => await settings.supervisor.call(
          'quota.refresh',
          arguments,
          const Duration(seconds: 5),
        ),
        'get' => await settings.supervisor.call(
          'quota.get',
          const {},
          const Duration(seconds: 10),
        ),
        'openUrl' => await settings.supervisor.call(
          'app.openUrl',
          arguments,
          const Duration(seconds: 5),
        ),
        _ => throw PlatformException(
          code: 'METHOD_NOT_FOUND',
          message: 'quota method not found: ${call.method}',
        ),
      };
    } catch (error) {
      AppLog.write('[settings-window] quota ${call.method} failed: $error');
      rethrow;
    }
  }

  /// 设置窗口的邮箱账号操作统一转发给 sidecar。
  Future<dynamic> _onMailCall(MethodCall call) async {
    final arguments = call.arguments is Map
        ? Map<String, dynamic>.from(call.arguments as Map)
        : <String, dynamic>{};
    try {
      return switch (call.method) {
        'accounts.list' => await settings.supervisor.call(
          'mail.accounts.list',
          const {},
          const Duration(seconds: 10),
        ),
        'accounts.add' => await settings.supervisor.call(
          'mail.accounts.add',
          arguments,
          const Duration(seconds: 15),
        ),
        'accounts.update' => await settings.supervisor.call(
          'mail.accounts.update',
          arguments,
          const Duration(seconds: 10),
        ),
        'accounts.remove' => await settings.supervisor.call(
          'mail.accounts.remove',
          arguments,
          const Duration(seconds: 10),
        ),
        'refresh' => await settings.supervisor.call(
          'mail.refresh',
          arguments,
          const Duration(seconds: 10),
        ),
        'openUrl' => await settings.supervisor.call(
          'app.openUrl',
          arguments,
          const Duration(seconds: 5),
        ),
        _ => throw PlatformException(
          code: 'METHOD_NOT_FOUND',
          message: 'mail method not found: ${call.method}',
        ),
      };
    } catch (error) {
      AppLog.write('[settings-window] mail ${call.method} failed: $error');
      rethrow;
    }
  }

  /// 设置窗口没有 sidecar 连接，模型列表、密钥和测试都经主窗口转发。
  Future<dynamic> _onTranslateCall(MethodCall call) async {
    final arguments = call.arguments is Map
        ? Map<String, dynamic>.from(call.arguments as Map)
        : <String, dynamic>{};
    try {
      return switch (call.method) {
        'models' => await settings.supervisor.call(
          'translate.models',
          arguments,
          const Duration(seconds: 30),
        ),
        'run' => await settings.supervisor.call(
          'translate.run',
          arguments,
          const Duration(seconds: 90),
        ),
        'setSecret' => await settings.supervisor.call(
          'translate.setSecret',
          arguments,
          const Duration(seconds: 10),
        ),
        'openUrl' => await settings.supervisor.call(
          'app.openUrl',
          arguments,
          const Duration(seconds: 5),
        ),
        _ => throw PlatformException(
          code: 'METHOD_NOT_FOUND',
          message: 'translate method not found: ${call.method}',
        ),
      };
    } catch (error) {
      AppLog.write('[settings-window] translate ${call.method} failed: $error');
      rethrow;
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
          weatherLocationMode: incoming.weatherLocationMode,
          weatherLocationName: incoming.weatherLocationName,
          weatherLatitude: incoming.weatherLatitude,
          weatherLongitude: incoming.weatherLongitude,
          mediaEnabled: incoming.mediaEnabled,
          showPlayingIndicator: incoming.showPlayingIndicator,
          showImeIndicator: incoming.showImeIndicator,
          showImeBanner: incoming.showImeBanner,
          showScheduleIndicator: incoming.showScheduleIndicator,
          enabledAgents: incoming.enabledAgents,
          showAgentIndicator: incoming.showAgentIndicator,
          showAgentBanner: incoming.showAgentBanner,
          tabOrder: incoming.tabOrder,
          hiddenTabs: incoming.hiddenTabs,
          dashboardMetrics: incoming.dashboardMetrics,
          islandMetrics: incoming.islandMetrics,
          translateProvider: incoming.translateProvider,
          translateBaseUrl: incoming.translateBaseUrl,
          translateModel: incoming.translateModel,
          translateTarget: incoming.translateTarget,
          translateSource: incoming.translateSource,
          translateAutoOrder: incoming.translateAutoOrder,
          translateUserPrompt: incoming.translateUserPrompt,
          translateSystemPrompt: incoming.translateSystemPrompt,
          translateMyMemoryEmail: incoming.translateMyMemoryEmail,
          mailPollSeconds: incoming.mailPollSeconds,
          mailTranslateProvider: incoming.mailTranslateProvider,
          quotaOrder: incoming.quotaOrder,
          hiddenQuotaProviders: incoming.hiddenQuotaProviders,
          shelfMaxItems: incoming.shelfMaxItems,
          shelfViewMode: incoming.shelfViewMode,
          quotaGlmRegion: incoming.quotaGlmRegion,
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
