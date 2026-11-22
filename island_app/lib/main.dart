import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_info.dart';
import 'core/click_through/click_through_controller.dart';
import 'core/input/keyboard_event_guard.dart';
import 'core/ipc/sidecar_supervisor.dart';
import 'core/log.dart';
import 'core/logging/crash_handler.dart';
import 'core/settings/settings_controller.dart';
import 'core/window/app_window.dart';
import 'core/window/single_instance.dart';
import 'core/window/window_position.dart';
import 'features/settings/settings_window.dart';
import 'features/settings/settings_window_args.dart';
import 'features/settings/settings_window_launcher.dart';
import 'features/agents/agent_controller.dart';
import 'features/dashboard/metrics_controller.dart';
import 'features/diagnostics/diagnostics_controller.dart';
import 'features/ime/ime_controller.dart';
import 'features/island/island_controller.dart';
import 'features/island/island_layout.dart';
import 'features/mail/mail_controller.dart';
import 'features/media/media_controller.dart';
import 'features/messages/messages_controller.dart';
import 'features/quota/quota_controller.dart';
import 'features/schedule/anniversary_controller.dart';
import 'features/schedule/schedule_controller.dart';
import 'features/shelf/shelf_controller.dart';
import 'features/translate/translate_controller.dart';
import 'features/volume/volume_controller.dart';
import 'features/weather/weather_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 封面已按显示尺寸解码；限制缓存上限，避免长时间播放后图片缓存持续累积。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 << 20;
  unawaited(KeyboardEventGuard.install());

  // 多窗口：带 type=settings 参数的引擎是设置窗口，不跑岛体逻辑。
  final settingsWindow = await _settingsWindowArguments();
  if (settingsWindow != null) {
    await runSettingsWindow(settingsWindow);
    return;
  }

  // 单实例：已有实例就把它叫到前台后退出；热重启时互斥量属于本进程，继续启动。
  // 这一步必须在 AppLog.init 之前，否则两个进程会同时写 app.log 导致内容交错。
  if (!SingleInstance.acquire('Local\\gudong-island-app')) {
    final focused = SingleInstance.focusExisting();
    if (focused) {
      AppLog.writeDetached('[app] another instance is running');
      if (kDebugMode) {
        // 否则 flutter run 只会报 service protocol 连接失败，看不出原因。
        stderr.writeln('[gudong] 已有实例在运行，请先从托盘退出或结束 island_app.exe 再启动');
      }
      exit(0);
    }
  }

  AppLog.init();
  AppLog.write('[app] bootstrap start v$appVersion');
  CrashHandler.install();

  await windowManager.ensureInitialized();

  final supervisor = SidecarSupervisor();
  final messages = MessagesController(supervisor);
  final mail = MailController(supervisor);
  final weather = WeatherController(supervisor);
  final media = MediaController(supervisor);
  final ime = ImeController(supervisor);
  final diagnostics = DiagnosticsController(supervisor);
  final translate = TranslateController(supervisor);
  final quota = QuotaController(supervisor);
  final metrics = MetricsController(supervisor);
  final schedule = ScheduleController(supervisor);
  final anniversary = AnniversaryController(supervisor);
  final volume = VolumeController(supervisor);
  final shelf = ShelfController(supervisor);
  final agents = AgentController(supervisor);
  final settings = SettingsController(supervisor);
  final settingsLauncher = SettingsWindowLauncher(settings);
  final island = IslandController(
    supervisor: supervisor,
    messages: messages,
    mail: mail,
    schedule: schedule,
    volume: volume,
    agents: agents,
  );
  final clickThrough = ClickThroughController(windowSize: appWindowSize);

  // 悬停展开 / 收起：命中状态来自 16ms 的光标轮询，不依赖 Flutter 的
  // MouseRegion 事件，穿透状态下也能可靠触发。
  clickThrough.pointerInside.addListener(() {
    island.setPointerInside(clickThrough.pointerInside.value);
  });

  // sidecar 进程启动有几百毫秒到一秒多，和窗口初始化并行，缩短冷启动。
  unawaited(supervisor.start());
  await prepareAppWindow();
  // 位置恢复放在窗口准备好之后，避免被窗口初始化覆盖。
  final windowPosition = WindowPositionKeeper(settings);

  // 命中区域跟随岛体状态与停靠方向切换。
  void updateInteractiveRect() {
    final side = windowPosition.side;
    final appSettings = settings.settings;
    final showBanner =
        island.showBanner ||
        island.showMailBanner ||
        island.showScheduleBanner ||
        (appSettings.showAgentBanner && island.showAgentBanner) ||
        island.showVolumeBanner ||
        (appSettings.showImeBanner && ime.visible);
    clickThrough.setInteractiveRect(
      IslandLayout.rectFor(
        side,
        island.expanded
            ? IslandLayout.expandedSizeFor(side)
            : showBanner
            ? IslandLayout.bannerSizeFor(side)
            : IslandLayout.collapsedSizeFor(
                side,
                imeIndicator: appSettings.showImeIndicator,
                metricCount: appSettings.islandMetrics.length,
              ),
      ),
    );
  }

  island.addListener(updateInteractiveRect);
  ime.addListener(updateInteractiveRect);
  agents.addListener(updateInteractiveRect);
  settings.addListener(updateInteractiveRect);
  windowPosition.addListener(updateInteractiveRect);
  updateInteractiveRect();

  runApp(
    GudongApp(
      scope: AppScope(
        supervisor: supervisor,
        island: island,
        messages: messages,
        mail: mail,
        weather: weather,
        media: media,
        ime: ime,
        diagnostics: diagnostics,
        translate: translate,
        quota: quota,
        metrics: metrics,
        schedule: schedule,
        anniversary: anniversary,
        volume: volume,
        agents: agents,
        shelf: shelf,
        settings: settings,
        settingsWindow: settingsLauncher,
        windowPosition: windowPosition,
        clickThrough: clickThrough,
      ),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    AppLog.write('[app] first frame');
    unawaited(clickThrough.start());
  });
}

Future<SettingsWindowArguments?> _settingsWindowArguments() async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    return SettingsWindowArguments.tryParse(controller.arguments);
  } catch (_) {
    return null;
  }
}
