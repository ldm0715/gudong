import 'dart:async';

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
                  : GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: IslandMetrics.space6,
                            crossAxisSpacing: IslandMetrics.space6,
                            mainAxisExtent: 100,
                          ),
                      itemCount: items.length,
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
    final today = days == 0;
    final tone = past ? colors.muted : colors.accent;
    final status = today
        ? ''
        : past
        ? '已过'
        : '还有';
    final date = item.localDate;

    return Semantics(
      button: true,
      label: '${item.title}，${today ? '今天' : '$status ${days.abs()} 天'}',
      hint: '点击编辑',
      excludeSemantics: true,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            IslandMetrics.space8,
            IslandMetrics.space2,
            IslandMetrics.space4,
            IslandMetrics.space6,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.bodyStrong.tint(colors.text),
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
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status.isNotEmpty)
                        Text(
                          status,
                          style: IslandTypography.micro.tint(colors.muted),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            today ? '今天' : '${days.abs()}',
                            style:
                                (today
                                        ? IslandTypography.title
                                        : IslandTypography.displayLarge)
                                    .tint(tone),
                          ),
                          if (!today) ...[
                            const SizedBox(width: IslandMetrics.space2),
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: IslandMetrics.space2,
                              ),
                              child: Text(
                                '天',
                                style: IslandTypography.caption.tint(
                                  colors.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                formatAnniversaryDate(date ?? DateTime.now()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: IslandTypography.micro.tint(colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
