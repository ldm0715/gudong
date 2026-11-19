import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../../core/log.dart';
import '../../core/logging/crash_handler.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../translate/translate_bridge.dart';
import 'settings_panel.dart';
import 'settings_window_args.dart';
import 'settings_window_native.dart';
import 'translate_settings_page.dart';

enum SettingsSection {
  general,
  pages,
  translate,
  music,
  focus,
  todos,
  notifications,
  ai,
  weather,
  about,
}

extension SettingsSectionMeta on SettingsSection {
  String get label => switch (this) {
    SettingsSection.general => '常规',
    SettingsSection.pages => '页面管理',
    SettingsSection.translate => '翻译',
    SettingsSection.music => '音乐与歌词',
    SettingsSection.focus => '专注与饮水',
    SettingsSection.todos => '待办与置物',
    SettingsSection.notifications => '通知、邮箱与日程',
    SettingsSection.ai => 'AI 额度',
    SettingsSection.weather => '天气',
    SettingsSection.about => '关于',
  };

  IconData get icon => switch (this) {
    SettingsSection.general => Icons.settings_rounded,
    SettingsSection.pages => Icons.dashboard_rounded,
    SettingsSection.translate => Icons.translate_rounded,
    SettingsSection.music => Icons.music_note_rounded,
    SettingsSection.focus => Icons.local_fire_department_rounded,
    SettingsSection.todos => Icons.checklist_rounded,
    SettingsSection.notifications => Icons.notifications_rounded,
    SettingsSection.ai => Icons.auto_awesome_rounded,
    SettingsSection.weather => Icons.wb_sunny_rounded,
    SettingsSection.about => Icons.info_rounded,
  };

  Color get tint => switch (this) {
    SettingsSection.general => const Color(0xFF8E9AAF),
    SettingsSection.pages => const Color(0xFF5B8DEF),
    SettingsSection.translate => const Color(0xFF7C6CF2),
    SettingsSection.music => const Color(0xFFF06292),
    SettingsSection.focus => const Color(0xFFF59E0B),
    SettingsSection.todos => const Color(0xFF34C77B),
    SettingsSection.notifications => const Color(0xFF5B8DEF),
    SettingsSection.ai => const Color(0xFF2BB5A0),
    SettingsSection.weather => const Color(0xFF4FC3F7),
    SettingsSection.about => const Color(0xFF8E9AAF),
  };

  String get placeholder => switch (this) {
    SettingsSection.focus => '专注计时与喝水提醒会放在这里。',
    SettingsSection.todos => '待办、置物架和快捷入口会放在这里。',
    SettingsSection.notifications => '通知聚合、邮箱与日程会放在这里。',
    SettingsSection.ai => 'AI 服务的额度与用量会放在这里。',
    _ => '该页面将在后续阶段接入。',
  };
}

Future<void> runSettingsWindow(SettingsWindowArguments args) async {
  AppLog.init(appLog: 'settings.log', crashLog: 'settings-crash.log');
  CrashHandler.install();
  AppLog.write('[settings-window] engine started');
  SettingsNativeWindow.prepare(title: 'Guduo 设置');
  // 与主窗口组成双向通道，翻译配置页通过它获取模型和保存密钥。
  try {
    await translateChannel.setMethodCallHandler((call) async => null);
  } catch (error) {
    AppLog.write('[settings-window] translate channel register failed: $error');
  }

  // 主窗口通过 WindowController 发送 focus / close。
  try {
    final controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler((call) async {
      if (call.method == 'focus') {
        SettingsNativeWindow.focus();
      } else if (call.method == 'close') {
        SettingsNativeWindow.close();
      }
      return null;
    });
  } catch (error) {
    AppLog.write('[settings-window] method handler failed: $error');
  }

  runApp(SettingsWindowApp(initialSettings: args.settings));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SettingsNativeWindow.show();
  });
}

class SettingsWindowApp extends StatefulWidget {
  const SettingsWindowApp({super.key, required this.initialSettings});

  final AppSettings initialSettings;

  @override
  State<SettingsWindowApp> createState() => _SettingsWindowAppState();
}

class _SettingsWindowAppState extends State<SettingsWindowApp> {
  static const _channel = WindowMethodChannel(
    'guduo.settings',
    mode: ChannelMode.unidirectional,
  );

  late AppSettings _settings = widget.initialSettings;
  SettingsSection _section = SettingsSection.general;

  Future<void> _save(AppSettings next) async {
    setState(() => _settings = next);
    try {
      await _channel.invokeMethod('save', next.toJson());
    } catch (error) {
      AppLog.write('[settings-window] save failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IslandColors.byId(_settings.themeId);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Guduo 设置',
      theme: ThemeData(
        brightness: colors.brightness,
        scaffoldBackgroundColor: colors.windowBackground,
        fontFamily: 'Microsoft YaHei UI',
        useMaterial3: true,
        extensions: [colors],
      ),
      home: Scaffold(
        backgroundColor: colors.windowBackground,
        body: Row(
          children: [
            _SettingsSidebar(
              selected: _section,
              onSelect: (section) => setState(() => _section = section),
            ),
            Container(width: 1, color: colors.cardStroke),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
                    child: Text(
                      _section.label,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                      child: _page(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page() {
    return switch (_section) {
      SettingsSection.general => GeneralSettingsPage(
        settings: _settings,
        onSave: _save,
      ),
      SettingsSection.weather => WeatherSettingsPage(
        settings: _settings,
        onSave: _save,
      ),
      SettingsSection.pages => PagesSettingsPage(
        settings: _settings,
        onSave: _save,
      ),
      SettingsSection.translate => TranslateSettingsPage(
        settings: _settings,
        onSave: _save,
      ),
      SettingsSection.music => MusicSettingsPage(
        settings: _settings,
        onSave: _save,
      ),
      SettingsSection.about => const AboutSettingsPage(),
      _ => PlaceholderSettingsPage(description: _section.placeholder),
    };
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({required this.selected, required this.onSelect});

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final sections = SettingsSection.values
        .where((section) => section != SettingsSection.about)
        .toList(growable: false);
    return Container(
      width: 216,
      color: colors.sidebarBackground,
      child: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final section in sections)
                  _NavItem(
                    section: section,
                    selected: section == selected,
                    onTap: () => onSelect(section),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
            child: _NavItem(
              section: SettingsSection.about,
              selected: selected == SettingsSection.about,
              onTap: () => onSelect(SettingsSection.about),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.navSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: section.tint,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(section.icon, size: 15, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                section.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
