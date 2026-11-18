import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/log.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';

/// 设置窗口左侧每个栏目的内容。Phase 1 只实现常规、天气、关于。
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(text, style: TextStyle(color: colors.muted, fontSize: 12)),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.cardStroke),
      ),
      child: Column(children: children),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: colors.text, fontSize: 13)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(color: colors.muted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        activeThumbColor: colors.accent,
        activeTrackColor: colors.accent.withValues(alpha: 0.35),
        inactiveThumbColor: colors.muted,
        inactiveTrackColor: colors.switchOff,
        onChanged: onChanged,
      ),
    );
  }
}

class SettingsInfoRow extends StatelessWidget {
  const SettingsInfoRow({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(color: colors.muted, fontSize: 12),
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: context.islandColors.cardStroke);
  }
}

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('外观'),
        SettingsCard(
          children: [
            SettingsRow(
              title: '主题',
              subtitle: '岛体与设置窗口的配色',
              trailing: Wrap(
                spacing: 8,
                children: [
                  for (final theme in IslandColors.values)
                    _ThemeOption(
                      theme: theme,
                      selected: theme.id == settings.themeId,
                      onTap: () => onSave(settings.copyWith(themeId: theme.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('功能'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              title: '显示天气',
              subtitle: '收起态在时间右侧显示当前天气',
              value: settings.showWeather,
              onChanged: (value) =>
                  onSave(settings.copyWith(showWeather: value)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('启动与快捷键'),
        const SettingsCard(
          children: [
            SettingsInfoRow(title: '全局快捷键', value: 'Ctrl + Alt + Space'),
            SettingsDivider(),
            SettingsInfoRow(title: '开机自启', value: 'Phase 3 接入'),
          ],
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final IslandColors theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.navSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colors.accent : colors.cardStroke,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: theme.background,
                shape: BoxShape.circle,
                border: Border.all(color: theme.accent, width: 2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              theme.name,
              style: TextStyle(
                color: selected ? colors.accent : colors.text,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WeatherSettingsPage extends StatelessWidget {
  const WeatherSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('显示'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              title: '显示天气',
              subtitle: '收起态在时间右侧显示当前天气',
              value: settings.showWeather,
              onChanged: (value) =>
                  onSave(settings.copyWith(showWeather: value)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('数据'),
        const SettingsCard(
          children: [
            SettingsInfoRow(title: '刷新间隔', value: '15 分钟'),
            SettingsDivider(),
            SettingsInfoRow(
              title: '定位与抓取',
              subtitle: '由 sidecar 自动按出口 IP 定位',
              value: '自动',
            ),
          ],
        ),
      ],
    );
  }
}

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  void _openLogDir() {
    final dir = AppLog.logDir;
    if (dir == null) return;
    try {
      unawaited(Process.start('explorer.exe', [dir]));
    } catch (error) {
      AppLog.write('[settings] open log dir failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('版本'),
        const SettingsCard(
          children: [SettingsInfoRow(title: '客户端', value: appVersion)],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('诊断'),
        SettingsCard(
          children: [
            SettingsInfoRow(
              title: '日志目录',
              subtitle: 'app.log / crash.log / settings.log',
              value: AppLog.logDir ?? '不可用',
            ),
            const SettingsDivider(),
            SettingsRow(
              title: '打开日志目录',
              trailing: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _openLogDir,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    '打开',
                    style: TextStyle(color: colors.accent, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('配置文件'),
        const SettingsCard(
          children: [
            SettingsInfoRow(title: '路径', value: r'%APPDATA%\guduo\config.json'),
          ],
        ),
      ],
    );
  }
}

class PlaceholderSettingsPage extends StatelessWidget {
  const PlaceholderSettingsPage({super.key, required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Icon(Icons.construction_rounded, size: 26, color: colors.muted),
              const SizedBox(height: 10),
              Text(
                '后续阶段接入',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
