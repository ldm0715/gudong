import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/log.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/island_tabs.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_motion.dart';
import '../weather/weather_bridge.dart';
import '../weather/weather_models.dart';

/// 设置窗口左侧每个栏目的内容。
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: children),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
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
    this.leading,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;

  /// 为 null 时开关不可操作，用于已达数量上限的选项。
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: Switch(value: value, onChanged: onChanged),
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
        const SettingsSectionLabel('窗口'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              title: '窗口最大化时自动收起',
              subtitle: '前台窗口最大化时只保留一条横杠，点击横杠显示岛体',
              value: settings.autoCollapseOnMaximized,
              onChanged: (value) =>
                  onSave(settings.copyWith(autoCollapseOnMaximized: value)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('输入法'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              title: '显示输入法状态',
              subtitle: '收起态显示当前“中 / en”输入模式',
              value: settings.showImeIndicator,
              onChanged: (value) =>
                  onSave(settings.copyWith(showImeIndicator: value)),
            ),
            const SettingsDivider(),
            SettingsSwitchRow(
              title: '切换时显示横幅',
              subtitle: '输入法切换时弹出与消息提醒相同的横幅',
              value: settings.showImeBanner,
              onChanged: (value) =>
                  onSave(settings.copyWith(showImeBanner: value)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('启动与快捷键'),
        SettingsCard(
          children: [
            const SettingsInfoRow(
              title: '全局快捷键',
              value: 'Ctrl + Alt + Space',
            ),
            const SettingsDivider(),
            SettingsSwitchRow(
              title: '开机自启',
              subtitle: '登录 Windows 后自动启动 Guduo',
              value: settings.launchAtLogin,
              onChanged: (value) =>
                  onSave(settings.copyWith(launchAtLogin: value)),
            ),
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
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: colors.navSelected,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: selected ? colors.accent : colors.cardStroke),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      visualDensity: VisualDensity.compact,
      avatar: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: theme.background,
          shape: BoxShape.circle,
          border: Border.all(color: theme.accent, width: 2),
        ),
      ),
      label: Text(
        theme.name,
        style: TextStyle(
          color: selected ? colors.accent : colors.text,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class PagesSettingsPage extends StatelessWidget {
  const PagesSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  void _setVisible(IslandTab tab, bool visible) {
    final hidden = settings.hiddenTabs.toList();
    if (visible) {
      hidden.remove(tab.id);
    } else if (!hidden.contains(tab.id)) {
      hidden.add(tab.id);
    }
    onSave(settings.copyWith(hiddenTabs: hidden));
  }

  void _reorder(int oldIndex, int newIndex) {
    final ids = settings.orderedTabs.map((item) => item.id).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    if (newIndex < 0 || newIndex >= ids.length) return;
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    onSave(settings.copyWith(tabOrder: ids));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final order = settings.orderedTabs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('岛体页面'),
        SettingsCard(
          children: [
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorder: _reorder,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: colors.cardBackground,
                  surfaceTintColor: Colors.transparent,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final tab = order[index];
                return Column(
                  key: ValueKey(tab.id),
                  children: [
                    _PageRow(
                      tab: tab,
                      index: index,
                      visible: !settings.hiddenTabs.contains(tab.id),
                      onVisible: (value) => _setVisible(tab, value),
                    ),
                    if (index < order.length - 1) const SettingsDivider(),
                  ],
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '拖动右侧手柄调整顺序；隐藏的页面不会出现在岛体 tab 栏，'
            '全部隐藏时岛体只保留标题栏，可从齿轮重新打开设置。',
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.tab,
    required this.index,
    required this.visible,
    required this.onVisible,
  });

  final IslandTab tab;
  final int index;
  final bool visible;
  final ValueChanged<bool> onVisible;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return SettingsRow(
      leading: Tooltip(
        message: '拖动排序',
        waitDuration: IslandMotion.tooltipDelay,
        child: ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.drag_handle_rounded,
              size: 18,
              color: colors.muted,
            ),
          ),
        ),
      ),
      title: tab.label,
      subtitle: visible ? '在岛体显示' : '已隐藏',
      trailing: Switch(value: visible, onChanged: onVisible),
    );
  }
}

class ScheduleSettingsPage extends StatelessWidget {
  const ScheduleSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('日程'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              title: '显示今日日程图标',
              subtitle: '当天有日程时，收起态显示闹钟图标',
              value: settings.showScheduleIndicator,
              onChanged: (value) =>
                  onSave(settings.copyWith(showScheduleIndicator: value)),
            ),
            const SettingsDivider(),
            const SettingsInfoRow(
              title: '提醒方式',
              subtitle: '到点后在收起态显示横幅，同时发送 Windows 通知',
              value: '横幅 + 系统通知',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '日程保存在本机，重启后仍然保留；已触发的日程保留 7 天后自动清理。',
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class MusicSettingsPage extends StatelessWidget {
  const MusicSettingsPage({
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
        const SettingsSectionLabel('媒体'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              title: '媒体信息与控制',
              subtitle: '显示系统媒体会话的曲目、进度与封面，并支持播放控制',
              value: settings.mediaEnabled,
              onChanged: (value) =>
                  onSave(settings.copyWith(mediaEnabled: value)),
            ),
            const SettingsDivider(),
            SettingsSwitchRow(
              title: '播放时显示音波',
              subtitle: '收起态最右侧显示动态音波图标',
              value: settings.showPlayingIndicator,
              onChanged: (value) =>
                  onSave(settings.copyWith(showPlayingIndicator: value)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('数据'),
        const SettingsCard(
          children: [
            SettingsInfoRow(title: '刷新频率', subtitle: '播放中', value: '1 秒'),
            SettingsDivider(),
            SettingsInfoRow(title: '封面', value: '随曲目更新'),
            SettingsDivider(),
            SettingsInfoRow(
              title: '歌词',
              subtitle: '按曲目名、歌手与时长自动匹配',
              value: 'QQ 音乐',
            ),
          ],
        ),
      ],
    );
  }
}

class WeatherSettingsPage extends StatefulWidget {
  const WeatherSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  State<WeatherSettingsPage> createState() => _WeatherSettingsPageState();
}

class _WeatherSettingsPageState extends State<WeatherSettingsPage> {
  final TextEditingController _query = TextEditingController();
  List<WeatherPlace> _places = const [];
  bool _searching = false;
  String? _message;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final result = await weatherChannel.invokeMethod<dynamic>('search', {
        'query': query,
      });
      final raw = result is Map ? result['places'] : null;
      final places = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) =>
                      WeatherPlace.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const <WeatherPlace>[];
      if (!mounted) return;
      setState(() {
        _places = places;
        if (places.isEmpty) _message = '没有找到匹配的地点';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '搜索失败：$error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _apply(WeatherPlace place) {
    widget.onSave(
      widget.settings.copyWith(
        weatherLocationMode: 'manual',
        weatherLocationName: place.label,
        weatherLatitude: place.latitude,
        weatherLongitude: place.longitude,
      ),
    );
    _query.clear();
    setState(() {
      _places = const [];
      _message = null;
    });
  }

  void _useAuto() {
    widget.onSave(widget.settings.copyWith(weatherLocationMode: 'auto'));
    setState(() {
      _places = const [];
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final colors = context.islandColors;
    final manual = settings.weatherLocationMode == 'manual';
    final current = manual
        ? (settings.weatherLocationName.isEmpty
              ? '手动位置'
              : settings.weatherLocationName)
        : '自动';
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
                  widget.onSave(settings.copyWith(showWeather: value)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('定位'),
        SettingsCard(
          children: [
            SettingsRow(
              title: '当前定位',
              subtitle: manual ? '使用手动指定的地点' : '按网络出口 IP 自动定位',
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  current,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ),
            ),
            if (manual) ...[
              const SettingsDivider(),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: TextButton(
                    onPressed: _useAuto,
                    child: const Text('恢复自动定位'),
                  ),
                ),
              ),
            ],
            const SettingsDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      style: TextStyle(color: colors.text, fontSize: 12),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => unawaited(_search()),
                      decoration: const InputDecoration(
                        hintText: '输入城市名，如 广州、Tokyo',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _searching ? null : _search,
                    child: Text(_searching ? '搜索中…' : '搜索'),
                  ),
                ],
              ),
            ),
            if (_message != null) ...[
              const SettingsDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  _message!,
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
              ),
            ],
            for (final place in _places) ...[
              const SettingsDivider(),
              ListTile(
                dense: true,
                onTap: () => _apply(place),
                title: Text(
                  place.name,
                  style: TextStyle(color: colors.text, fontSize: 13),
                ),
                subtitle: place.detail.isEmpty
                    ? null
                    : Text(
                        place.detail,
                        style: TextStyle(color: colors.muted, fontSize: 11),
                      ),
                trailing: TextButton(
                  onPressed: () => _apply(place),
                  child: const Text('使用'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('数据'),
        const SettingsCard(
          children: [
            SettingsInfoRow(title: '刷新间隔', value: '15 分钟'),
            SettingsDivider(),
            SettingsInfoRow(
              title: '数据来源',
              subtitle: '地点搜索使用 Open-Meteo 地理编码，天气由 sidecar 抓取',
              value: '内置',
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutHeader extends StatelessWidget {
  const _AboutHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Image.asset(
              'assets/branding/logo.png',
              width: 64,
              height: 64,
              cacheWidth: 128,
              cacheHeight: 128,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appName,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appTagline,
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v$appVersion',
                    style: TextStyle(color: colors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

  void _openRepository() {
    try {
      unawaited(Process.start('explorer.exe', [appRepositoryUrl]));
    } catch (error) {
      AppLog.write('[settings] open repository failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AboutHeader(),
        const SizedBox(height: 18),
        const SettingsSectionLabel('版本'),
        const SettingsCard(
          children: [SettingsInfoRow(title: '客户端', value: appVersion)],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('项目'),
        SettingsCard(
          children: [
            SettingsRow(
              title: '项目仓库',
              subtitle: '源码、问题反馈与版本更新',
              trailing: TextButton(
                onPressed: _openRepository,
                child: const Text('打开'),
              ),
            ),
          ],
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
              trailing: TextButton(
                onPressed: _openLogDir,
                child: const Text('打开'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('配置文件'),
        const SettingsCard(
          children: [
            SettingsInfoRow(
              title: '路径',
              value: r'%APPDATA%\gudong\config.json',
            ),
          ],
        ),
      ],
    );
  }
}
