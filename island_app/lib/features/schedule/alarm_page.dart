import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ipc/json_rpc_client.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../island/island_controller.dart';
import 'alarm_controller.dart';
import 'alarm_models.dart';
import 'schedule_controls.dart';
import 'time_picker.dart';

/// 日程第三页：每日闹钟。
///
/// 每张卡片可直接开关，点击卡片编辑时间、名称与生效星期。
class AlarmPage extends StatefulWidget {
  const AlarmPage({
    super.key,
    required this.controller,
    required this.island,
  });

  final AlarmController controller;
  final IslandController island;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final Set<int> _days = {};
  bool _composer = false;
  AlarmItem? _editing;
  String _error = '';
  bool _saving = false;
  ScheduleConfirm? _confirm;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // 下次响铃只在分钟级别变化，页面可见时每分钟刷新一次。
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _title.dispose();
    _time.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _resetComposer() {
    _composer = false;
    _editing = null;
    _error = '';
    _confirm = null;
  }

  void _openComposer([AlarmItem? item]) {
    setState(() {
      _composer = true;
      _editing = item;
      _error = '';
      _confirm = null;
      _title.text = item?.title ?? '';
      _time.text = item?.timeLabel ?? '09:00';
      _days
        ..clear()
        ..addAll(item?.days ?? const [1, 2, 3, 4, 5, 6, 7]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _composer) _titleFocus.requestFocus();
    });
  }

  (int, int)? _parseTime(String text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return (hour, minute);
  }

  Future<void> _pickTime() async {
    final current = _parseTime(_time.text) ?? (9, 0);
    PickedTime? picked;
    widget.island.holdExpanded(true);
    try {
      picked = await showIslandTimePicker(
        context,
        hour: current.$1,
        minute: current.$2,
      );
    } finally {
      widget.island.holdExpanded(false);
    }
    final value = picked;
    if (value == null || !mounted) return;
    setState(
      () => _time.text = formatClockTime(value.hour, value.minute),
    );
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final time = _parseTime(_time.text);
    if (title.isEmpty) {
      setState(() => _error = '请输入名称');
      return;
    }
    if (time == null) {
      setState(() => _error = '时间格式应为 HH:mm');
      return;
    }
    if (_days.isEmpty) {
      setState(() => _error = '至少选择一个生效日');
      return;
    }
    final editing = _editing;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final days = _days.toList()..sort();
      if (editing == null) {
        await widget.controller.add(
          title: title,
          hour: time.$1,
          minute: time.$2,
          days: days,
        );
      } else {
        await widget.controller.update(
          editing.id,
          title: title,
          hour: time.$1,
          minute: time.$2,
          days: days,
        );
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _composer = false;
        _editing = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is RpcException ? error.message : '保存失败，请重试';
      });
    }
  }

  Future<void> _toggle(AlarmItem item, bool enabled) async {
    try {
      await widget.controller.setEnabled(item.id, enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is RpcException ? error.message : '操作失败，请重试';
      });
    }
  }

  void _askDelete(AlarmItem item) {
    setState(() {
      _confirm = ScheduleConfirm(
        title: '删除「${item.title}」？',
        detail: '${item.timeLabel} · ${item.daysLabel} · 删除后无法恢复',
        confirmLabel: '删除',
        danger: true,
        onConfirm: () => _delete(item),
      );
    });
  }

  Future<void> _delete(AlarmItem item) async {
    setState(() {
      _confirm = null;
      _saving = true;
      _error = '';
    });
    try {
      await widget.controller.remove(item.id);
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (_editing?.id == item.id) _resetComposer();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is RpcException ? error.message : '删除失败，请重试';
      });
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_days.contains(day)) {
        _days.remove(day);
      } else {
        _days.add(day);
      }
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final items = widget.controller.items;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(colors, items),
            if (_error.isNotEmpty && !_composer) ...[
              const SizedBox(height: IslandMetrics.space4),
              Text(
                _error,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IslandTypography.micro.tint(colors.warning),
              ),
            ],
            const SizedBox(height: IslandMetrics.space6),
            Expanded(
              child: _composer
                  ? _composerPane(colors)
                  : items.isEmpty
                  ? _empty(colors)
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: IslandMetrics.space4),
                      itemBuilder: (context, index) => _AlarmCard(
                        item: items[index],
                        onEdit: () => _openComposer(items[index]),
                        onToggle: (value) => _toggle(items[index], value),
                        onDelete: () => _askDelete(items[index]),
                      ),
                    ),
            ),
          ],
        ),
        if (_confirm != null)
          Positioned.fill(
            child: ScheduleConfirmOverlay(
              colors: colors,
              confirm: _confirm!,
              onCancel: () => setState(() => _confirm = null),
            ),
          ),
      ],
    );
  }

  Widget _header(IslandColors colors, List<AlarmItem> items) {
    final next = nextAlarmAt(items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('闹钟', style: IslandTypography.bodyStrong.tint(colors.text)),
            const SizedBox(width: IslandMetrics.space4),
            Text(
              '${items.length} 个',
              style: IslandTypography.micro.tint(colors.muted),
            ),
            const Spacer(),
            if (!_composer)
              ScheduleSmallIconButton(
                icon: Icons.add_rounded,
                tooltip: '新建闹钟',
                onTap: _openComposer,
              ),
          ],
        ),
        if (next != null) ...[
          const SizedBox(height: IslandMetrics.space3),
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: IslandMetrics.iconXS,
                color: colors.accent,
              ),
              const SizedBox(width: IslandMetrics.space4),
              Text(
                '下次响铃',
                style: IslandTypography.micro.tint(colors.muted),
              ),
              const SizedBox(width: IslandMetrics.space4),
              Text(
                formatNextAlarm(next),
                style: IslandTypography.microStrong.tint(colors.accent),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _empty(IslandColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.alarm_add_outlined,
            size: IslandMetrics.icon2XL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space6),
          Text('还没有闹钟', style: IslandTypography.subhead.tint(colors.text)),
          const SizedBox(height: IslandMetrics.space3),
          Text('点击右上角 + 添加', style: IslandTypography.micro.tint(colors.muted)),
        ],
      ),
    );
  }

  Widget _composerPane(IslandColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(80)],
          onSubmitted: (_) => _submit(),
          style: IslandTypography.body.copyWith(color: colors.text),
          cursorColor: colors.accent,
          decoration: scheduleInputDecoration(colors, '名称，如：喝水'),
        ),
        const SizedBox(height: IslandMetrics.space6),
        Row(
          children: [
            ScheduleSmallIconButton(
              icon: Icons.schedule_rounded,
              tooltip: '选择时间',
              onTap: _saving ? null : _pickTime,
            ),
            const SizedBox(width: IslandMetrics.space4),
            SizedBox(
              width: 58,
              child: TextField(
                controller: _time,
                enabled: !_saving,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9:]')),
                  LengthLimitingTextInputFormatter(5),
                ],
                style: IslandTypography.clock.copyWith(color: colors.text),
                cursorColor: colors.accent,
                onSubmitted: (_) => _submit(),
                decoration: scheduleInputDecoration(colors, 'HH:mm').copyWith(
                  contentPadding: const EdgeInsets.all(IslandMetrics.space6),
                ),
              ),
            ),
            const SizedBox(width: IslandMetrics.space6),
            Text('每天按此时刻提醒', style: IslandTypography.micro.tint(colors.muted)),
          ],
        ),
        const SizedBox(height: IslandMetrics.space8),
        Row(
          children: [
            Text('生效日', style: IslandTypography.micro.tint(colors.muted)),
            const SizedBox(width: IslandMetrics.space6),
            for (var day = 1; day <= 7; day++) ...[
              if (day > 1) const SizedBox(width: IslandMetrics.space4),
              Expanded(child: _dayPill(colors, day)),
            ],
          ],
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: IslandMetrics.space6),
          Text(
            _error,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: IslandTypography.micro.tint(colors.warning),
          ),
        ],
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SchedulePillButton(
              label: '取消',
              onTap: _saving ? null : () => setState(_resetComposer),
            ),
            const SizedBox(width: IslandMetrics.space6),
            SchedulePillButton(
              label: _saving ? '保存中' : '保存',
              primary: true,
              onTap: _saving ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }

  Widget _dayPill(IslandColors colors, int day) {
    final selected = _days.contains(day);
    return GestureDetector(
      onTap: _saving ? null : () => _toggleDay(day),
      child: Container(
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: 0.18) : colors.surface,
          borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
          border: Border.all(
            color: selected ? colors.accent : colors.stroke,
          ),
        ),
        child: Text(
          alarmWeekdayNames[day - 1],
          style:
              (selected
                      ? IslandTypography.microStrong
                      : IslandTypography.micro)
                  .tint(selected ? colors.accent : colors.muted),
        ),
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final AlarmItem item;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final tone = item.enabled ? colors.accent : colors.muted;
    return Semantics(
      button: true,
      label: '${item.timeLabel} ${item.title} ${item.daysLabel}',
      hint: '点击编辑',
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
        hoverColor: colors.surface,
        highlightColor: colors.chip,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: IslandMetrics.space8,
            vertical: IslandMetrics.space6,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Text(
                item.timeLabel,
                style: IslandTypography.clock.tint(tone),
              ),
              const SizedBox(width: IslandMetrics.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.bodyStrong.tint(
                        item.enabled ? colors.text : colors.muted,
                      ),
                    ),
                    Text(
                      item.daysLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.micro.tint(colors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: IslandMetrics.space6),
              _AlarmToggle(value: item.enabled, onChanged: onToggle),
              ScheduleSmallIconButton(
                icon: Icons.close_rounded,
                tooltip: '删除',
                compact: true,
                onTap: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 自绘开关，避免在岛体里引入 Material 开关的视觉签名。
class _AlarmToggle extends StatefulWidget {
  const _AlarmToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_AlarmToggle> createState() => _AlarmToggleState();
}

class _AlarmToggleState extends State<_AlarmToggle> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Semantics(
      toggled: widget.value,
      label: '启用闹钟',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        onShowFocusHighlight: (value) => setState(() => _focus = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onChanged(!widget.value);
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: () => widget.onChanged(!widget.value),
          child: AnimatedContainer(
            duration: IslandMotion.fast,
            curve: IslandMotion.standard,
            width: 34,
            height: 20,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: widget.value ? colors.accent : colors.chip,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hover || _focus ? colors.stroke : Colors.transparent,
              ),
            ),
            child: AnimatedAlign(
              duration: IslandMotion.fast,
              curve: IslandMotion.standard,
              alignment: widget.value
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: colors.background,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
