import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import 'schedule_controls.dart';

/// 日程日期选择浮层。点日期直接返回，取消则关闭。
class ScheduleDatePicker extends StatefulWidget {
  const ScheduleDatePicker({
    super.key,
    required this.initialDate,
    required this.onSelected,
    required this.onCancel,
  });

  final DateTime initialDate;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onCancel;

  @override
  State<ScheduleDatePicker> createState() => _ScheduleDatePickerState();
}

class _ScheduleDatePickerState extends State<ScheduleDatePicker> {
  late DateTime _month = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
  );
  late final DateTime _selected = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
    widget.initialDate.day,
  );

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final today = DateTime.now();
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = DateTime(_month.year, _month.month, 1).weekday - 1;

    final rows = <Widget>[];
    for (var row = 0; row < 6; row++) {
      final cells = <Widget>[];
      for (var column = 0; column < 7; column++) {
        final index = row * 7 + column;
        final dayNumber = index - leading + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          cells.add(const Expanded(child: SizedBox.shrink()));
          continue;
        }
        final day = DateTime(_month.year, _month.month, dayNumber);
        cells.add(
          Expanded(
            child: _DateCell(
              day: day,
              selected: _sameDay(day, _selected),
              today: _sameDay(day, today),
              onTap: () => widget.onSelected(day),
            ),
          ),
        );
      }
      rows.add(SizedBox(height: 17, child: Row(children: cells)));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onCancel,
            child: ColoredBox(color: colors.background.withValues(alpha: 0.72)),
          ),
        ),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              width: 240,
              padding: const EdgeInsets.all(IslandMetrics.space3),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(IslandMetrics.radiusPanel),
                border: Border.all(color: colors.stroke),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ScheduleSmallIconButton(
                        icon: Icons.chevron_left_rounded,
                        tooltip: '上个月',
                        compact: true,
                        onTap: () => _changeMonth(-1),
                      ),
                      Expanded(
                        child: Text(
                          '${_month.year} 年 ${_month.month} 月',
                          textAlign: TextAlign.center,
                          style: IslandTypography.captionStrong.tint(
                            colors.text,
                          ),
                        ),
                      ),
                      ScheduleSmallIconButton(
                        icon: Icons.chevron_right_rounded,
                        tooltip: '下个月',
                        compact: true,
                        onTap: () => _changeMonth(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: IslandMetrics.space2),
                  Row(
                    children: [
                      for (final label in const [
                        '一',
                        '二',
                        '三',
                        '四',
                        '五',
                        '六',
                        '日',
                      ])
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
                  ...rows,
                  const SizedBox(height: IslandMetrics.space2),
                  Row(
                    children: [
                      const Spacer(),
                      SchedulePillButton(
                        label: '今天',
                        onTap: () => widget.onSelected(DateTime.now()),
                      ),
                      const SizedBox(width: IslandMetrics.space6),
                      SchedulePillButton(label: '取消', onTap: widget.onCancel),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final foreground = selected || today ? colors.accent : colors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '${day.year} 年 ${day.month} 月 ${day.day} 日',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
        hoverColor: colors.surface,
        child: Container(
          margin: const EdgeInsets.all(0.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.accent.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
            border: today && !selected
                ? Border.all(color: colors.accent.withValues(alpha: 0.5))
                : null,
          ),
          child: Text(
            '${day.day}',
            style:
                (selected
                        ? IslandTypography.microStrong
                        : IslandTypography.micro)
                    .copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
