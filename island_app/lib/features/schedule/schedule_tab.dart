import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ipc/json_rpc_client.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import '../../core/widgets/page_edge_button.dart';
import '../island/island_controller.dart';
import 'alarm_controller.dart';
import 'alarm_page.dart';
import 'anniversary_controller.dart';
import 'anniversary_page.dart';
import 'schedule_controller.dart';
import 'schedule_controls.dart';
import 'schedule_models.dart';
import 'time_picker.dart';

/// 展开态日程页：左侧当天事宜，右侧月历。
///
/// 月历用圆点颜色标出有日程的日期，点击日期切换左侧列表。
/// 新建直接保存，编辑与删除都需要二次确认。
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({
    super.key,
    required this.controller,
    required this.anniversary,
    required this.alarm,
    required this.island,
  });

  final ScheduleController controller;
  final AnniversaryController anniversary;
  final AlarmController alarm;
  final IslandController island;

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  // 日程在中间，左侧是闹钟，右侧是倒计时与纪念日。
  int _page = 1;
  late DateTime _month;
  late DateTime _selected;
  final TextEditingController _title = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  bool _composer = false;
  bool _timeEdited = false;
  ScheduleItem? _editing;
  String _error = '';
  bool _saving = false;
  ScheduleConfirm? _confirm;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = scheduleDay(now);
  }

  @override
  void dispose() {
    _title.dispose();
    _time.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    setState(() {
      _month = next;
      // 编辑状态下只翻月，日期由用户点选后再更新。
      if (_composer) return;
      _selected = DateTime(next.year, next.month, 1);
      _resetComposer();
    });
  }

  void _selectDay(DateTime day) {
    final today = scheduleDay(DateTime.now());
    if (_composer && day.isBefore(today)) {
      setState(() => _error = '日期不能早于今天');
      return;
    }
    setState(() {
      _selected = scheduleDay(day);
      if (_composer) {
        _error = '';
      } else {
        _resetComposer();
      }
    });
  }

  void _resetComposer() {
    _composer = false;
    _editing = null;
    _error = '';
    _confirm = null;
  }

  void _openComposer([ScheduleItem? item]) {
    final now = DateTime.now();
    final today = scheduleDay(now);
    // 默认时间取当前时间的下一分钟，避免打开表单后马上过期。
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    setState(() {
      // 浏览历史日期时新建，默认回到今天，避免默认时间已经过去。
      if (item == null && _selected.isBefore(today)) {
        _selected = today;
        _month = DateTime(today.year, today.month);
      }
      // 23:59 之后创建时，下一分钟已经跨到明天。
      if (item == null &&
          _sameDay(_selected, today) &&
          !_sameDay(nextMinute, today)) {
        _selected = scheduleDay(nextMinute);
        _month = DateTime(_selected.year, _selected.month);
      }
      _composer = true;
      _editing = item;
      _error = '';
      _confirm = null;
      _timeEdited = false;
      _title.text = item?.title ?? '';
      _time.text = item == null
          ? formatScheduleTime(nextMinute)
          : formatScheduleTime(item.at);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _composer) _titleFocus.requestFocus();
    });
  }

  DateTime? _parseTime(String text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return DateTime(
      _selected.year,
      _selected.month,
      _selected.day,
      hour,
      minute,
    );
  }

  Future<void> _pickTime() async {
    final current = _parseTime(_time.text);
    PickedTime? picked;
    widget.island.holdExpanded(true);
    try {
      picked = await showIslandTimePicker(
        context,
        hour: current?.hour ?? 9,
        minute: current?.minute ?? 0,
      );
    } finally {
      widget.island.holdExpanded(false);
    }
    final value = picked;
    if (value == null || !mounted) return;
    setState(() {
      _time.text = formatClockTime(value.hour, value.minute);
      _timeEdited = true;
    });
  }

  void _submit() {
    final title = _title.text.trim();
    final at = _parseTime(_time.text);
    if (title.isEmpty) {
      setState(() => _error = '请输入标题');
      return;
    }
    if (at == null) {
      setState(() => _error = '时间格式应为 HH:mm');
      return;
    }
    final now = DateTime.now();
    final editing = _editing;
    // 没有改过时间的今天日程，按保存时的下一分钟触发。
    final useNextMinute =
        editing == null &&
        !_timeEdited &&
        _sameDay(_selected, scheduleDay(now));
    // 修改已经过期的日程时，只改标题不重新校验时间。
    final keepPastTime =
        editing != null &&
        editing.atMs <= now.millisecondsSinceEpoch &&
        at.millisecondsSinceEpoch == editing.atMs;
    if (!useNextMinute && !keepPastTime) {
      if (scheduleDay(at).isBefore(scheduleDay(now))) {
        setState(() => _error = '日期不能早于今天');
        return;
      }
      if (at.millisecondsSinceEpoch <= now.millisecondsSinceEpoch) {
        setState(() => _error = '时间必须晚于当前时间');
        return;
      }
    }
    if (editing == null) {
      // 表单停留超过一分钟时，默认时间已经过期，顺延到保存时的下一分钟。
      final overrideAt = useNextMinute && !at.isAfter(now)
          ? DateTime(now.year, now.month, now.day, now.hour, now.minute + 1)
          : null;
      _save(null, overrideAt: overrideAt);
      return;
    }
    setState(() {
      _confirm = ScheduleConfirm(
        title: '保存修改？',
        detail: '$title · ${formatScheduleDate(at)} ${formatScheduleTime(at)}',
        confirmLabel: '保存',
        onConfirm: () => _save(editing, keepPastTime: keepPastTime),
      );
    });
  }

  Future<void> _save(
    ScheduleItem? editing, {
    bool keepPastTime = false,
    DateTime? overrideAt,
  }) async {
    final title = _title.text.trim();
    final at = overrideAt ?? _parseTime(_time.text);
    if (at == null) return;
    setState(() {
      _saving = true;
      _error = '';
      _confirm = null;
    });
    try {
      if (editing == null) {
        await widget.controller.add(title: title, at: at);
      } else {
        await widget.controller.update(
          editing.id,
          title: title,
          at: keepPastTime ? null : at,
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

  void _askDelete(ScheduleItem item) {
    setState(() {
      _confirm = ScheduleConfirm(
        title: '删除「${item.title}」？',
        detail:
            '${formatScheduleDate(item.at)} '
            '${formatScheduleTime(item.at)} · 删除后无法恢复',
        confirmLabel: '删除',
        danger: true,
        onConfirm: () => _delete(item),
      );
    });
  }

  void _askClearExpired(int count) {
    setState(() {
      _confirm = ScheduleConfirm(
        title: '清理已过期日程？',
        detail: '将删除 $count 条已经提醒过的日程，删除后无法恢复',
        confirmLabel: '清理',
        danger: true,
        onConfirm: _clearExpired,
      );
    });
  }

  Future<void> _clearExpired() async {
    setState(() {
      _confirm = null;
      _saving = true;
      _error = '';
    });
    try {
      await widget.controller.clearExpired();
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is RpcException ? error.message : '清理失败，请重试';
      });
    }
  }

  Future<void> _delete(ScheduleItem item) async {
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

  String _pageLabel(int page) {
    if (page <= 0) return '闹钟';
    if (page == 1) return '日程';
    return '倒计时与纪念日';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: IslandMetrics.iconSM,
          child: PageEdgeButton(
            icon: Icons.chevron_left_rounded,
            tooltip: _pageLabel(_page - 1),
            enabled: _page > 0,
            onTap: () => setState(() => _page -= 1),
          ),
        ),
        Expanded(
          child: switch (_page) {
            0 => AlarmPage(
              controller: widget.alarm,
              island: widget.island,
            ),
            1 => _schedulePage(context),
            _ => AnniversaryPage(controller: widget.anniversary),
          },
        ),
        SizedBox(
          width: IslandMetrics.iconSM,
          child: PageEdgeButton(
            icon: Icons.chevron_right_rounded,
            tooltip: _pageLabel(_page + 1),
            enabled: _page < 2,
            onTap: () => setState(() => _page += 1),
          ),
        ),
      ],
    );
  }

  Widget _schedulePage(BuildContext context) {
    final colors = context.islandColors;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // 已触发或时间已过的日程视为失效，不再出现在日历和当天列表里。
    final items = widget.controller
        .itemsOn(_selected)
        .where((item) => !item.fired && item.atMs > nowMs)
        .toList(growable: false);
    final counts = <String, int>{};
    for (final item in widget.controller.items) {
      if (item.fired || item.atMs <= nowMs) continue;
      final key = scheduleDayKey(item.at);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _agenda(colors, items)),
            const SizedBox(width: IslandMetrics.space8),
            SizedBox(width: 162, child: _calendar(colors, counts)),
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

  Widget _agenda(IslandColors colors, List<ScheduleItem> items) {
    final expired = widget.controller.items.where((item) => item.fired).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${_selected.month} 月 ${_selected.day} 日',
              style: IslandTypography.bodyStrong.tint(colors.text),
            ),
            const SizedBox(width: IslandMetrics.space4),
            Text(
              scheduleWeekday(_selected),
              style: IslandTypography.micro.tint(colors.muted),
            ),
            const Spacer(),
            if (!_composer) ...[
              if (expired > 0) ...[
                ScheduleSmallIconButton(
                  icon: Icons.auto_delete_outlined,
                  tooltip: '清理已过期',
                  onTap: () => _askClearExpired(expired),
                ),
                const SizedBox(width: IslandMetrics.space2),
              ],
              ScheduleSmallIconButton(
                icon: Icons.add_rounded,
                tooltip: '新建日程',
                onTap: _openComposer,
              ),
            ],
          ],
        ),
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
              ? _emptyAgenda(colors)
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: IslandMetrics.space4),
                  itemBuilder: (context, index) =>
                      _agendaItem(colors, items[index]),
                ),
        ),
      ],
    );
  }

  Widget _agendaItem(IslandColors colors, ScheduleItem item) {
    final past = item.isPast;
    final tone = item.fired
        ? colors.muted
        : past
        ? colors.warning
        : colors.accent;
    return Semantics(
      button: true,
      label: '${formatScheduleTime(item.at)} ${item.title}',
      hint: '点击编辑',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _openComposer(item),
        borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: IslandMetrics.space6,
            vertical: IslandMetrics.space4,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 2,
                height: IslandMetrics.space16,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(IslandMetrics.radiusBar),
                ),
              ),
              const SizedBox(width: IslandMetrics.space6),
              Text(
                formatScheduleTime(item.at),
                style: IslandTypography.clock.copyWith(color: tone),
              ),
              const SizedBox(width: IslandMetrics.space6),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IslandTypography.body.copyWith(
                    color: past ? colors.muted : colors.text,
                  ),
                ),
              ),
              ScheduleSmallIconButton(
                icon: Icons.close_rounded,
                tooltip: '删除',
                compact: true,
                onTap: () => _askDelete(item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyAgenda(IslandColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available_outlined,
            size: IslandMetrics.icon2XL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space6),
          Text('当天没有日程', style: IslandTypography.subhead.tint(colors.text)),
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
          textInputAction: TextInputAction.next,
          inputFormatters: [LengthLimitingTextInputFormatter(80)],
          style: IslandTypography.body.copyWith(color: colors.text),
          cursorColor: colors.accent,
          decoration: scheduleInputDecoration(colors, '事项标题'),
        ),
        const SizedBox(height: IslandMetrics.space6),
        Row(
          children: [
            Icon(
              Icons.event_rounded,
              size: IslandMetrics.iconSM,
              color: colors.muted,
            ),
            const SizedBox(width: IslandMetrics.space4),
            Expanded(
              child: Text(
                '${formatScheduleIsoDate(_selected)} '
                '${scheduleWeekday(_selected)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IslandTypography.caption.tint(colors.text),
              ),
            ),
            Text('右侧日历选日期', style: IslandTypography.micro.tint(colors.muted)),
          ],
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
                onChanged: (_) => _timeEdited = true,
                onSubmitted: (_) => _submit(),
                decoration: scheduleInputDecoration(colors, 'HH:mm').copyWith(
                  contentPadding: const EdgeInsets.all(IslandMetrics.space6),
                ),
              ),
            ),
            const Spacer(),
            SchedulePillButton(
              label: '取消',
              onTap: _saving ? null : () => setState(_resetComposer),
            ),
            const SizedBox(width: IslandMetrics.space4),
            SchedulePillButton(
              label: _saving ? '保存中' : '保存',
              primary: true,
              onTap: _saving ? null : _submit,
            ),
          ],
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: IslandMetrics.space4),
          Text(
            _error,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: IslandTypography.micro.tint(colors.warning),
          ),
        ],
        const Spacer(),
        Text(
          _editing == null ? '保存后按时间排序' : '修改后需要再次确认',
          style: IslandTypography.micro.tint(colors.muted),
        ),
      ],
    );
  }

  Widget _calendar(IslandColors colors, Map<String, int> counts) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = DateTime(_month.year, _month.month, 1).weekday - 1;
    final today = scheduleDay(DateTime.now());
    final cells = <Widget>[];
    for (var index = 0; index < 42; index++) {
      final dayNumber = index - leading + 1;
      if (dayNumber < 1 || dayNumber > daysInMonth) {
        cells.add(const Expanded(child: SizedBox.shrink()));
        continue;
      }
      final day = DateTime(_month.year, _month.month, dayNumber);
      cells.add(
        Expanded(
          child: _DayCell(
            day: dayNumber,
            count: counts[scheduleDayKey(day)] ?? 0,
            selected: _sameDay(day, _selected),
            today: _sameDay(day, today),
            disabled: _composer && day.isBefore(today),
            onTap: () => _selectDay(day),
          ),
        ),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            ScheduleSmallIconButton(
              icon: Icons.chevron_left_rounded,
              tooltip: '上个月',
              onTap: () => _changeMonth(-1),
            ),
            Expanded(
              child: Text(
                '${_month.year} 年 ${_month.month} 月',
                textAlign: TextAlign.center,
                style: IslandTypography.captionStrong.tint(colors.text),
              ),
            ),
            ScheduleSmallIconButton(
              icon: Icons.chevron_right_rounded,
              tooltip: '下个月',
              onTap: () => _changeMonth(1),
            ),
          ],
        ),
        const SizedBox(height: IslandMetrics.space4),
        Row(
          children: [
            for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: IslandTypography.micro.tint(colors.muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: IslandMetrics.space2),
        for (var row = 0; row < 6; row++)
          Expanded(child: Row(children: cells.sublist(row * 7, row * 7 + 7))),
      ],
    );
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.selected,
    required this.today,
    required this.onTap,
    this.disabled = false,
  });

  final int day;
  final int count;
  final bool selected;
  final bool today;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final highlighted = count > 0;
    final dimmed = colors.muted.withValues(alpha: 0.35);
    final foreground = disabled
        ? dimmed
        : selected || today || highlighted
        ? colors.accent
        : colors.text;
    final dotColor = disabled ? dimmed : colors.accent;
    final dots = count > 3 ? 3 : count;
    return Semantics(
      button: !disabled,
      selected: selected,
      label: disabled
          ? '$day 日，日期已过'
          : count > 0
          ? '$day 日，$count 条日程'
          : '$day 日',
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
        hoverColor: colors.surface,
        highlightColor: colors.chip,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? colors.accent.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
            border: today && !selected
                ? Border.all(color: colors.accent.withValues(alpha: 0.55))
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style:
                    (selected
                            ? IslandTypography.microStrong
                            : IslandTypography.micro)
                        .copyWith(color: foreground),
              ),
              const SizedBox(height: 1),
              SizedBox(
                height: 3,
                child: dots == 0
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var index = 0; index < dots; index++)
                            Container(
                              width: 3,
                              height: 3,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 0.5,
                              ),
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
