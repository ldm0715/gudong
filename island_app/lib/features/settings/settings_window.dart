import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/input/keyboard_event_guard.dart';
import '../../core/log.dart';
import '../../core/logging/crash_handler.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../shelf/shelf_settings_page.dart';
import '../translate/translate_bridge.dart';
import '../update/update_bridge.dart';
import '../weather/weather_bridge.dart';
import 'ai_settings_page.dart';
import 'dashboard_settings_page.dart';
import 'mail_settings_page.dart';
import 'settings_panel.dart';
import 'settings_window_args.dart';
import 'settings_window_native.dart';
import 'translate_settings_page.dart';

enum SettingsSection {
  general,
  pages,
  dashboard,
  mail,
  translate,
  music,
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
    SettingsSection.dashboard => '仪表盘',
    SettingsSection.mail => '邮箱',
    SettingsSection.translate => '翻译',
    SettingsSection.music => '音乐与歌词',
    SettingsSection.todos => '中转站',
    SettingsSection.notifications => '通知与日程',
    SettingsSection.ai => 'AI',
    SettingsSection.weather => '天气',
    SettingsSection.about => '关于',
  };

  IconData get icon => switch (this) {
    SettingsSection.general => Icons.settings_rounded,
    SettingsSection.pages => Icons.dashboard_rounded,
    SettingsSection.dashboard => Icons.monitor_heart_outlined,
    SettingsSection.mail => Icons.mail_outline_rounded,
    SettingsSection.translate => Icons.translate_rounded,
    SettingsSection.music => Icons.music_note_rounded,
    SettingsSection.todos => Icons.inbox_rounded,
    SettingsSection.notifications => Icons.notifications_rounded,
    SettingsSection.ai => Icons.auto_awesome_rounded,
    SettingsSection.weather => Icons.wb_sunny_rounded,
    SettingsSection.about => Icons.info_rounded,
  };

  Color get tint => switch (this) {
    SettingsSection.general => const Color(0xFF8E9AAF),
    SettingsSection.pages => const Color(0xFF5B8DEF),
    SettingsSection.dashboard => const Color(0xFFE05C7A),
    SettingsSection.mail => const Color(0xFF4F9CF9),
    SettingsSection.translate => const Color(0xFF7C6CF2),
    SettingsSection.music => const Color(0xFFF06292),
    SettingsSection.todos => const Color(0xFF34C77B),
    SettingsSection.notifications => const Color(0xFF5B8DEF),
    SettingsSection.ai => const Color(0xFF2BB5A0),
    SettingsSection.weather => const Color(0xFF4FC3F7),
    SettingsSection.about => const Color(0xFF8E9AAF),
  };
}

/// 设置窗口主题：沿用 M3 组件的交互能力，但去掉波纹、色调表面与胶囊形。
ThemeData settingsTheme(IslandColors colors) {
  final radius = BorderRadius.circular(8);
  final inputBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: colors.cardStroke),
  );
  return ThemeData(
    brightness: colors.brightness,
    scaffoldBackgroundColor: colors.windowBackground,
    canvasColor: colors.cardBackground,
    fontFamily: 'Microsoft YaHei UI',
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: colors.surface,
    colorScheme: ColorScheme(
      brightness: colors.brightness,
      primary: colors.accent,
      onPrimary: colors.background,
      secondary: colors.accent,
      onSecondary: colors.background,
      error: colors.warning,
      onError: colors.background,
      surface: colors.windowBackground,
      onSurface: colors.text,
      onSurfaceVariant: colors.muted,
      outline: colors.cardStroke,
      outlineVariant: colors.divider,
      surfaceContainerLowest: colors.cardBackground,
      surfaceContainerLow: colors.cardBackground,
      surfaceContainer: colors.sidebarBackground,
      surfaceContainerHigh: colors.cardBackground,
      surfaceContainerHighest: colors.sidebarBackground,
    ),
    extensions: [colors],
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.cardBackground,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.cardStroke),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.cardBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.cardStroke,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      selectedColor: colors.accent,
      selectedTileColor: colors.navSelected,
      textColor: colors.text,
      iconColor: colors.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      horizontalTitleGap: 10,
      minLeadingWidth: 26,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent.withValues(alpha: 0.35)
            : colors.switchOff,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        disabledForegroundColor: colors.muted,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.muted,
        minimumSize: const Size(28, 28),
        padding: const EdgeInsets.all(2),
        iconSize: 18,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colors.sidebarBackground,
      hintStyle: TextStyle(color: colors.muted, fontSize: 11),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.accent),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.cardBackground,
      contentTextStyle: TextStyle(color: colors.text, fontSize: 12),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
  );
}

Future<void> runSettingsWindow(SettingsWindowArguments args) async {
  AppLog.init(appLog: 'settings.log', crashLog: 'settings-crash.log');
  CrashHandler.install();
  unawaited(KeyboardEventGuard.install());
  AppLog.write('[settings-window] engine started');
  SettingsNativeWindow.prepare(title: '$appName 设置');
  // 与主窗口组成双向通道，翻译配置页通过它获取模型和保存密钥。
  try {
    await translateChannel.setMethodCallHandler((call) async => null);
  } catch (error) {
    AppLog.write('[settings-window] translate channel register failed: $error');
  }
  try {
    await weatherChannel.setMethodCallHandler((call) async => null);
  } catch (error) {
    AppLog.write('[settings-window] weather channel register failed: $error');
  }
  try {
    await updateChannel.setMethodCallHandler((call) async => null);
  } catch (error) {
    AppLog.write('[settings-window] update channel register failed: $error');
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
    'gudong.settings',
    mode: ChannelMode.unidirectional,
  );

  late AppSettings _settings = widget.initialSettings;
  late IslandColors _colors = IslandColors.byId(_settings.themeId);
  late ThemeData _theme = settingsTheme(_colors);

  Future<void> _save(AppSettings next) async {
    setState(() {
      _settings = next;
      if (next.themeId != _colors.id) {
        _colors = IslandColors.byId(next.themeId);
        _theme = settingsTheme(_colors);
      }
    });
    try {
      await _channel.invokeMethod('save', next.toJson());
    } catch (error) {
      AppLog.write('[settings-window] save failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '$appName 设置',
      theme: _theme,
      home: Scaffold(
        backgroundColor: _colors.windowBackground,
        body: _SettingsBody(
          settings: _settings,
          colors: _colors,
          onSave: _save,
        ),
      ),
    );
  }
}

/// 侧栏与页面内容。栏目状态放在这里，切换时不重建 MaterialApp 与主题。
class _SettingsBody extends StatefulWidget {
  const _SettingsBody({
    required this.settings,
    required this.colors,
    required this.onSave,
  });

  final AppSettings settings;
  final IslandColors colors;
  final ValueChanged<AppSettings> onSave;

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  SettingsSection _section = SettingsSection.general;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Row(
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
    );
  }

  Widget _page() {
    final settings = widget.settings;
    final onSave = widget.onSave;
    return switch (_section) {
      SettingsSection.general => GeneralSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.weather => WeatherSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.pages => PagesSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.dashboard => DashboardSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.mail => MailSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.translate => TranslateSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.music => MusicSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.ai => AiSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.notifications => ScheduleSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.todos => ShelfSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
      SettingsSection.about => AboutSettingsPage(
        settings: settings,
        onSave: onSave,
      ),
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
    // 用 Material 提供底色：ListTile 的选中背景画在最近的 Material 墨迹层，
    // 若外层是不透明 Container，会把选中背景盖住。
    return SizedBox(
      width: 216,
      child: Material(
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: colors.navSelected,
        tileColor: Colors.transparent,
        onTap: onTap,
        leading: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: section.tint,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(section.icon, size: 15, color: Colors.white),
        ),
        title: Text(
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
    );
  }
}
