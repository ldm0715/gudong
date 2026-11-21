import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ipc/json_rpc_client.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import 'anniversary_controller.dart';
import 'anniversary_models.dart';
import 'date_picker_overlay.dart';
import 'schedule_controls.dart';

/// 日程第二页：倒计时与纪念日。
///
/// 顶部是标题和新建入口，下面按“未来由近到远、过去由近到远”排列卡片。
class AnniversaryPage extends StatefulWidget {
  const AnniversaryPage({super.key, required this.controller});

  final AnniversaryController controller;

  @override
  State<AnniversaryPage> createState() => _AnniversaryPageState();
}

class _AnniversaryPageState extends State<AnniversaryPage> {
  final TextEditingController _title = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  DateTime _draftDate = DateTime.now();
  Timer? _clock;
  bool _composer = false;
  bool _showDatePicker = false;
  AnniversaryItem? _editing;
  String _error = '';
  bool _saving = false;
  ScheduleConfirm? _confirm;

  @override
  void initState() {
    super.initState();
    // 天数每天变化，页面可见时每分钟刷新一次即可。
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  List<AnniversaryItem> _sortedItems() {
    final now = DateTime.now();
    final items = widget.controller.items.toList();
    items.sort((left, right) {
      final leftDays = left.daysFrom(now);
      final rightDays = right.daysFrom(now);
      final leftPast = leftDays < 0;
      final rightPast = rightDays < 0;
      if (leftPast != rightPast) return leftPast ? 1 : -1;
      if (leftPast) return rightDays.compareTo(leftDays);
      return leftDays.compareTo(rightDays);
    });
    return items;
  }

  void _resetComposer() {
    _composer = false;
    _showDatePicker = false;
    _editing = null;
    _error = '';
    _confirm = null;
  }

  void _openComposer([AnniversaryItem? item]) {
    setState(() {
      _composer = true;
      _showDatePicker = false;
      _editing = item;
      _error = '';
      _confirm = null;
      _title.text = item?.title ?? '';
      _draftDate = item?.localDate ?? DateTime.now();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _composer) _titleFocus.requestFocus();
    });
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请输入名称');
      return;
    }
    final editing = _editing;
    if (editing == null) {
      _save(null);
      return;
    }
    setState(() {
      _showDatePicker = false;
      _confirm = ScheduleConfirm(
        title: '保存修改？',
        detail: '$title · ${formatAnniversaryDate(_draftDate)}',
        confirmLabel: '保存',
        onConfirm: () => _save(editing),
      );
    });
  }

  Future<void> _save(AnniversaryItem? editing) async {
    final title = _title.text.trim();
    final date = formatAnniversaryIsoDate(_draftDate);
    setState(() {
      _saving = true;
      _error = '';
      _confirm = null;
      _showDatePicker = false;
    });
    try {
      if (editing == null) {
        await widget.controller.add(title: title, date: date);
      } else {
        await widget.controller.update(editing.id, title: title, date: date);
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

  void _askDelete(AnniversaryItem item) {
    setState(() {
      _confirm = ScheduleConfirm(
        title: '删除「${item.title}」？',
        detail:
            '${formatAnniversaryDate(item.localDate ?? DateTime.now())} '
            '· 删除后无法恢复',
        confirmLabel: '删除',
        danger: true,
        onConfirm: () => _delete(item),
      );
    });
  }

  Future<void> _delete(AnniversaryItem item) async {
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

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final items = _sortedItems();
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(colors, items.length),
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
                          const SizedBox(height: IslandMetrics.space6),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _AnniversaryCard(
                          item: item,
                          onEdit: () => _openComposer(item),
                          onDelete: () => _askDelete(item),
                        );
                      },
                    ),
            ),
          ],
        ),
        if (_showDatePicker)
          Positioned.fill(
            child: ScheduleDatePicker(
              initialDate: _draftDate,
              onCancel: () => setState(() => _showDatePicker = false),
              onSelected: (date) => setState(() {
                _draftDate = date;
                _showDatePicker = false;
                _error = '';
              }),
            ),
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

  Widget _header(IslandColors colors, int count) {
    return Row(
      children: [
        Text('倒计时 · 纪念日', style: IslandTypography.bodyStrong.tint(colors.text)),
        const SizedBox(width: IslandMetrics.space4),
        Text('$count 条', style: IslandTypography.micro.tint(colors.muted)),
        const Spacer(),
        if (!_composer)
          ScheduleSmallIconButton(
            icon: Icons.add_rounded,
            tooltip: '新建倒计时或纪念日',
            onTap: _openComposer,
          ),
      ],
    );
  }

  Widget _empty(IslandColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.celebration_outlined,
            size: IslandMetrics.icon2XL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space6),
          Text('还没有倒计时或纪念日', style: IslandTypography.subhead.tint(colors.text)),
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
          decoration: scheduleInputDecoration(colors, '名称，如：加入 广大黄埔研究院'),
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
            SizedBox(
              width: 128,
              child: InkWell(
                onTap: _saving
                    ? null
                    : () => setState(() => _showDatePicker = true),
                borderRadius: BorderRadius.circular(
                  IslandMetrics.radiusControl,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IslandMetrics.space8,
                    vertical: IslandMetrics.space7,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(
                      IslandMetrics.radiusControl,
                    ),
                    border: Border.all(color: colors.stroke),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: IslandMetrics.iconXS,
                        color: colors.muted,
                      ),
                      const SizedBox(width: IslandMetrics.space4),
                      Expanded(
                        child: Text(
                          formatAnniversaryIsoDate(_draftDate),
                          textAlign: TextAlign.center,
                          style: IslandTypography.clock.copyWith(
                            color: colors.text,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.expand_more_rounded,
                        size: IslandMetrics.iconXS,
                        color: colors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: IslandMetrics.space6),
            Text('可早于或晚于今天', style: IslandTypography.micro.tint(colors.muted)),
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
          _editing == null ? '保存后按日期排序' : '修改后需要再次确认',
          style: IslandTypography.micro.tint(colors.muted),
        ),
      ],
    );
  }
}

class _AnniversaryCard extends StatelessWidget {
  const _AnniversaryCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final AnniversaryItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final days = item.daysFrom(DateTime.now());
    final past = days < 0;
    final status = days > 0
        ? '还有'
        : past
        ? '已过'
        : '';
    final count = days == 0 ? '今天' : '${days.abs()}';
    final date = item.localDate;
    final tones = [colors.accent, colors.rain, colors.qq, colors.warning];
    final seed = item.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final base = tones[seed % tones.length];

    return Semantics(
      button: true,
      label: '${item.title}，${days == 0 ? '今天' : '${days.abs()} 天'}',
      hint: '点击编辑',
      excludeSemantics: true,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusCard),
        child: Container(
          height: 96,
          padding: const EdgeInsets.all(IslandMetrics.space10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                base.withValues(alpha: 0.55),
                base.withValues(alpha: 0.18),
                colors.surface,
              ],
              stops: const [0, 0.6, 1],
            ),
            borderRadius: BorderRadius.circular(IslandMetrics.radiusCard),
            border: Border.all(color: colors.stroke),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: IslandTypography.bodyStrong.tint(
                                    colors.text,
                                  ),
                                ),
                              ),
                              if (status.isNotEmpty) ...[
                                const SizedBox(width: IslandMetrics.space3),
                                Text(
                                  status,
                                  style: IslandTypography.microStrong.tint(
                                    colors.text.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ScheduleSmallIconButton(
                          icon: Icons.close_rounded,
                          tooltip: '删除',
                          compact: true,
                          onTap: onDelete,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          count,
                          style: IslandTypography.displayLarge.tint(
                            colors.text,
                          ),
                        ),
                        if (days != 0) ...[
                          const SizedBox(width: IslandMetrics.space3),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '天',
                              style: IslandTypography.caption.tint(
                                colors.text.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: IslandMetrics.space2),
                    Text(
                      formatAnniversaryDate(date ?? DateTime.now()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.micro.tint(
                        colors.text.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: IslandMetrics.space8),
              RepaintBoundary(
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: CustomPaint(
                    painter: _ClockDialPainter(
                      color: colors.text.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 参考图右侧的时钟表盘，固定指向 3 点方向。
class _ClockDialPainter extends CustomPainter {
  const _ClockDialPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color,
    );

    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.7);
    for (var index = 0; index < 12; index++) {
      final angle = index * math.pi / 6;
      final direction = Offset(math.sin(angle), -math.cos(angle));
      canvas.drawLine(
        center + direction * (radius - 4),
        center + direction * radius,
        tick,
      );
    }

    final hand = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center + Offset(radius * 0.48, 0), hand);
    canvas.drawLine(center, center - Offset(0, radius * 0.62), hand);
    canvas.drawCircle(center, 1.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ClockDialPainter oldDelegate) =>
      oldDelegate.color != color;
}
