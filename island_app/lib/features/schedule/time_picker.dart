import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import 'schedule_controls.dart';

/// 时间选择结果。
class PickedTime {
  const PickedTime(this.hour, this.minute);

  final int hour;
  final int minute;
}

String formatClockTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:'
    '${minute.toString().padLeft(2, '0')}';

/// 岛体窗口只有 420×300，Material 自带时间选择器放不下。
/// 这里用两列滑轮做紧凑版本：上下滑动选择，输入框继续支持直接键入。
Future<PickedTime?> showIslandTimePicker(
  BuildContext context, {
  required int hour,
  required int minute,
}) {
  FocusScope.of(context).unfocus();
  return showDialog<PickedTime>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => _TimePickerDialog(
      hour: hour.clamp(0, 23).toInt(),
      minute: minute.clamp(0, 59).toInt(),
    ),
  );
}

/// 滑轮用足够长的虚拟列表模拟无限循环，初始位置放在中段，
/// 这样从 23 继续向前就能直接到 00。
const int _wheelCycles = 1000;
const int _wheelStartCycle = _wheelCycles ~/ 2;

int _wheelInitialItem(int count, int value) =>
    count * _wheelStartCycle + value;

class _TimePickerDialog extends StatefulWidget {
  const _TimePickerDialog({required this.hour, required this.minute});

  final int hour;
  final int minute;

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  static const double _itemExtent = 22;
  static const double _wheelHeight = 110;

  late int _hour = widget.hour;
  late int _minute = widget.minute;
  late final FixedExtentScrollController _hourController =
      FixedExtentScrollController(initialItem: _wheelInitialItem(24, widget.hour));
  late final FixedExtentScrollController _minuteController =
      FixedExtentScrollController(
        initialItem: _wheelInitialItem(60, widget.minute),
      );

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 244,
          padding: const EdgeInsets.all(IslandMetrics.space14),
          decoration: BoxDecoration(
            // surface 只有很低的不透明度，弹窗必须用不透明卡片色，
            // 否则在透明窗口上会透出桌面。
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(IslandMetrics.radiusPanel),
            border: Border.all(color: colors.stroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '选择时间',
                    style: IslandTypography.captionStrong.tint(colors.accent),
                  ),
                  const Spacer(),
                  Text(
                    formatClockTime(_hour, _minute),
                    style: IslandTypography.bodyStrong.copyWith(
                      color: colors.text,
                      fontFeatures: IslandTypography.tabularFigures,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: IslandMetrics.space10),
              SizedBox(
                height: _wheelHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 中央选中带，横跨两列滑轮。
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          height: _itemExtent + IslandMetrics.space2,
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(
                              IslandMetrics.radiusChip,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Wheel(
                          label: '小时',
                          controller: _hourController,
                          count: 24,
                          selected: _hour,
                          onChanged: (value) => setState(() => _hour = value),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: IslandMetrics.space6,
                          ),
                          child: Text(
                            ':',
                            style: IslandTypography.title.tint(colors.muted),
                          ),
                        ),
                        _Wheel(
                          label: '分钟',
                          controller: _minuteController,
                          count: 60,
                          selected: _minute,
                          onChanged: (value) => setState(() => _minute = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: IslandMetrics.space10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SchedulePillButton(
                    label: '取消',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: IslandMetrics.space6),
                  SchedulePillButton(
                    label: '确定',
                    primary: true,
                    onTap: () => Navigator.of(context).pop(
                      PickedTime(_hour, _minute),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.label,
    required this.controller,
    required this.count,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final FixedExtentScrollController controller;
  final int count;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Semantics(
      label: label,
      child: SizedBox(
        width: 64,
        height: _TimePickerDialogState._wheelHeight,
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: _TimePickerDialogState._itemExtent,
          physics: const FixedExtentScrollPhysics(),
          perspective: 0.002,
          diameterRatio: 1.7,
          squeeze: 1.05,
          overAndUnderCenterOpacity: 0.45,
          // 把虚拟下标取模回真实值，相邻项自然衔接，形成循环。
          onSelectedItemChanged: (index) => onChanged(index % count),
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: count * _wheelCycles,
            builder: (context, index) {
              final value = index % count;
              final isSelected = value == selected;
              return Center(
                child: Text(
                  value.toString().padLeft(2, '0'),
                  style:
                      (isSelected
                              ? IslandTypography.bodyStrong
                              : IslandTypography.body)
                          .copyWith(
                            color: isSelected ? colors.accent : colors.muted,
                            fontFeatures: IslandTypography.tabularFigures,
                          ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
