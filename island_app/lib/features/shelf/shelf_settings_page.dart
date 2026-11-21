import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../settings/settings_panel.dart';

/// 中转站设置：条目上限。引用式存储不占磁盘，只限制列表长度。
class ShelfSettingsPage extends StatelessWidget {
  const ShelfSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  static const List<int> _options = [50, 100, 200, 500];

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('中转站'),
        SettingsCard(
          children: [
            SettingsRow(
              title: '默认视图',
              subtitle: '岛体上的中转站打开时使用的布局',
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'list', label: Text('列表')),
                  ButtonSegment(value: 'grid', label: Text('图标')),
                ],
                selected: {settings.shelfViewMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    onSave(settings.copyWith(shelfViewMode: selection.first)),
              ),
            ),
            const SettingsDivider(),
            SettingsRow(
              title: '条目上限',
              subtitle: '达到上限后新拖入的文件会被拒绝，不自动删除旧条目',
              trailing: SegmentedButton<int>(
                segments: [
                  for (final value in _options)
                    ButtonSegment(value: value, label: Text('$value')),
                ],
                selected: {settings.shelfMaxItems},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    onSave(settings.copyWith(shelfMaxItems: selection.first)),
              ),
            ),
            const SettingsDivider(),
            const SettingsInfoRow(
              title: '存储方式',
              subtitle: '只记录文件路径，不复制内容；原文件移动或删除后条目标记为失效',
              value: '引用原文件',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '把文件拖到岛体上会自动打开中转站；按住条目右侧的拖拽把手可以把文件拖到资源管理器。',
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
