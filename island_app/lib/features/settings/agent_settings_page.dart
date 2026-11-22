import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../agents/agent_bridge.dart';
import '../agents/agent_glyph.dart';
import '../agents/agent_models.dart';
import 'settings_panel.dart';

/// Agent 设置：显示开关与逐 agent 的检测接入。
class AgentSettingsPage extends StatefulWidget {
  const AgentSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  State<AgentSettingsPage> createState() => _AgentSettingsPageState();
}

class _AgentSettingsPageState extends State<AgentSettingsPage> {
  Timer? _timer;
  Map<String, AgentStatus> _statuses = const {};
  bool _loading = true;
  bool _refreshing = false;
  bool _disconnected = false;

  IslandColors get _colors => context.islandColors;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final raw = await agentChannel.invokeMethod<dynamic>('get');
      if (!mounted) return;
      final map = raw is Map ? Map<String, dynamic>.from(raw) : const {};
      final list = map['agents'];
      final statuses = <String, AgentStatus>{};
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final status = AgentStatus.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (status.id.isNotEmpty) statuses[status.id] = status;
          }
        }
      }
      setState(() {
        _statuses = statuses;
        _loading = false;
        _disconnected = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statuses = const {};
        _loading = false;
        _disconnected = true;
      });
    } finally {
      _refreshing = false;
    }
  }

  void _setEnabled(AgentInfo info, bool enabled) {
    final next = List<String>.of(widget.settings.enabledAgents);
    if (enabled) {
      if (!next.contains(info.id)) next.add(info.id);
    } else {
      next.remove(info.id);
    }
    widget.onSave(widget.settings.copyWith(enabledAgents: next));
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) unawaited(_refresh());
    });
  }

  String _statusText(AgentStatus? status) {
    if (_disconnected) return '未连接';
    if (status == null) return _loading ? '读取中…' : '空闲';
    if (!status.enabled) return '已关闭';
    if (!status.available) {
      return status.message.isEmpty ? '未检测到' : status.message;
    }
    return switch (status.state) {
      'running' => '运行中 · ${status.sessionCount} 个会话',
      'waiting' => '等待输入 · ${status.sessionCount} 个会话',
      _ => '空闲',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('显示'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              title: '运行中显示图标',
              subtitle: '收起态最多显示 2 个 agent 图标，超出显示 +N',
              value: widget.settings.showAgentIndicator,
              onChanged: (value) => widget.onSave(
                widget.settings.copyWith(showAgentIndicator: value),
              ),
            ),
            const SettingsDivider(),
            SettingsSwitchRow(
              title: '结束时显示横幅',
              subtitle: '显示会话标题、结束时间与一行回复摘要',
              value: widget.settings.showAgentBanner,
              onChanged: (value) => widget.onSave(
                widget.settings.copyWith(showAgentBanner: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('接入检测'),
        SettingsCard(
          children: [
            for (var index = 0; index < AgentCatalog.all.length; index++) ...[
              _agentRow(AgentCatalog.all[index]),
              if (index < AgentCatalog.all.length - 1)
                const SettingsDivider(),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '只读取本地会话文件，不修改任何 agent 配置，也不会上传标题或回复内容。',
            style: TextStyle(color: _colors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _agentRow(AgentInfo info) {
    final enabled = widget.settings.enabledAgents.contains(info.id);
    final status = _statuses[info.id];
    return SettingsRow(
      leading: AgentGlyph(id: info.id, size: 22),
      title: info.label,
      subtitle: '${info.detection} · ${_statusText(status)}',
      trailing: Switch(
        value: enabled,
        onChanged: (value) => _setEnabled(info, value),
      ),
    );
  }
}
