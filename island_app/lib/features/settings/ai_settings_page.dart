import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import 'agent_settings_page.dart';
import 'quota_settings_page.dart';

/// AI 设置：额度与 Agent 两个横向 tab。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 260,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.sidebarBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.cardStroke),
          ),
          child: Row(
            children: [
              _tabButton(colors, '额度', 0),
              _tabButton(colors, 'Agent', 1),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_tab == 0)
          QuotaSettingsPage(
            settings: widget.settings,
            onSave: widget.onSave,
          )
        else
          AgentSettingsPage(
            settings: widget.settings,
            onSave: widget.onSave,
          ),
      ],
    );
  }

  Widget _tabButton(IslandColors colors, String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: TextButton(
        onPressed: () => setState(() => _tab = index),
        style: TextButton.styleFrom(
          foregroundColor: selected ? colors.text : colors.muted,
          backgroundColor: selected
              ? colors.cardBackground
              : Colors.transparent,
          minimumSize: const Size(0, 34),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
