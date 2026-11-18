import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../weather/weather.dart';
import 'island_controller.dart';

const _bg = Color(0xF0111319);
const _stroke = Color(0x24FFFFFF);
const _accent = Color(0xFF2ED573);
const _text = Color(0xFFF2F4F8);
const _muted = Color(0xFF8B93A7);

/// 收起态宽高。加入天气后需要同步调整点击穿透的命中矩形。
const double _collapsedWidth = 156;
const double _collapsedHeight = 36;

enum _Tab { messages, weather, media, diagnostics }

class IslandView extends StatefulWidget {
  const IslandView({super.key, required this.controller});

  final IslandController controller;

  @override
  State<IslandView> createState() => _IslandViewState();
}

class _IslandViewState extends State<IslandView> {
  _Tab _tab = _Tab.messages;
  Timer? _clock;

  IslandController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scheduleClock();
  }

  void _scheduleClock() {
    final now = DateTime.now();
    _clock = Timer(
      Duration(milliseconds: (60 - now.second) * 1000 - now.millisecond),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleClock();
      },
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final expanded = controller.expanded;
                    final showBanner = controller.showBanner;
                    final width = expanded
                        ? 380.0
                        : (showBanner ? 360.0 : _collapsedWidth);
                    final height = expanded
                        ? 260.0
                        : (showBanner ? 80.0 : _collapsedHeight);
                    final radius = expanded ? 24.0 : (showBanner ? 22.0 : 18.0);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: width,
                      height: height,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          color: controller.pulse && !expanded
                              ? _accent.withValues(alpha: 0.75)
                              : _stroke,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: expanded ? 24 : 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: 0,
                        maxWidth: 380,
                        minHeight: 0,
                        maxHeight: 260,
                        child: expanded
                            ? _ExpandedBody(
                                controller: controller,
                                tab: _tab,
                                onTab: (tab) => setState(() => _tab = tab),
                              )
                            : showBanner
                            ? _NotificationBanner(controller: controller)
                            : _CollapsedBody(controller: controller),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedBody extends StatelessWidget {
  const _CollapsedBody({required this.controller});

  final IslandController controller;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final snapshot = controller.weather;
    return SizedBox(
      width: _collapsedWidth,
      height: _collapsedHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            time,
            style: const TextStyle(
              color: _text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              decoration: TextDecoration.none,
            ),
          ),
          if (snapshot != null) ...[
            const SizedBox(width: 7),
            _WeatherChip(snapshot: snapshot),
          ],
          if (controller.hasWechat) ...[
            const SizedBox(width: 8),
            _ClientGlyph(source: 'wechat', size: 18),
          ],
          if (controller.hasQq) ...[
            const SizedBox(width: 4),
            _ClientGlyph(source: 'qq', size: 18),
          ],
        ],
      ),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  const _WeatherChip({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _weatherIcon(snapshot.kind, snapshot.isDay),
          size: 15,
          color: _weatherColor(snapshot.kind),
        ),
        const SizedBox(width: 3),
        Text(
          '${snapshot.roundedTemp}°',
          style: const TextStyle(
            color: _text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

IconData _weatherIcon(WeatherKind kind, bool isDay) {
  switch (kind) {
    case WeatherKind.clear:
      return isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_outlined;
    case WeatherKind.partly:
      return Icons.wb_cloudy_outlined;
    case WeatherKind.cloudy:
      return Icons.cloud_outlined;
    case WeatherKind.fog:
      return Icons.foggy;
    case WeatherKind.drizzle:
      return Icons.grain;
    case WeatherKind.rain:
      return Icons.water_drop_outlined;
    case WeatherKind.snow:
      return Icons.ac_unit_outlined;
    case WeatherKind.thunder:
      return Icons.thunderstorm_outlined;
  }
}

Color _weatherColor(WeatherKind kind) {
  switch (kind) {
    case WeatherKind.clear:
      return const Color(0xFFFFC857);
    case WeatherKind.partly:
      return const Color(0xFFE6D27A);
    case WeatherKind.cloudy:
    case WeatherKind.fog:
      return _muted;
    case WeatherKind.drizzle:
      return const Color(0xFF7EC8F0);
    case WeatherKind.rain:
      return const Color(0xFF64B5F6);
    case WeatherKind.snow:
      return const Color(0xFFB3E5FC);
    case WeatherKind.thunder:
      return const Color(0xFFFFD54F);
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({required this.controller});

  final IslandController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.latestUnread;
    if (item == null) return const SizedBox.shrink();
    return SizedBox(
      width: 360,
      height: 80,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _ClientGlyph(source: item.source, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _relativeTime(item.time),
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(Icons.expand_more_rounded, size: 16, color: _muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeTime(String time) {
  final parts = time.split(':');
  if (parts.length < 2) return time;
  final now = DateTime.now();
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == now.hour && minute == now.minute) return '刚刚';
  return '${parts[0]}:${parts[1]}';
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.controller,
    required this.tab,
    required this.onTab,
  });

  final IslandController controller;
  final _Tab tab;
  final ValueChanged<_Tab> onTab;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 380,
      height: 260,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 2),
            child: Row(
              children: [
                if (controller.unread.isNotEmpty) ...[
                  _ClientGlyph(
                    source: controller.hasQq && !controller.hasWechat
                        ? 'qq'
                        : 'wechat',
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                ],
                const Text(
                  'Guduo Island',
                  style: TextStyle(
                    color: _text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                _StatusPill(ok: controller.ready),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _TabButton(
                  label: '消息',
                  selected: tab == _Tab.messages,
                  onTap: () => onTab(_Tab.messages),
                ),
                _TabButton(
                  label: '天气',
                  selected: tab == _Tab.weather,
                  onTap: () => onTab(_Tab.weather),
                ),
                _TabButton(
                  label: '媒体',
                  selected: tab == _Tab.media,
                  onTap: () => onTab(_Tab.media),
                ),
                _TabButton(
                  label: '诊断',
                  selected: tab == _Tab.diagnostics,
                  onTap: () => onTab(_Tab.diagnostics),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: switch (tab) {
                _Tab.messages => _MessagesTab(controller: controller),
                _Tab.weather => _WeatherTab(controller: controller),
                _Tab.media => const _MediaTab(),
                _Tab.diagnostics => _DiagnosticsTab(controller: controller),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesTab extends StatelessWidget {
  const _MessagesTab({required this.controller});

  final IslandController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.unread;
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 26, color: _muted),
            SizedBox(height: 8),
            Text(
              '暂无新消息',
              style: TextStyle(
                color: _text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '微信 / QQ 有新消息时会出现在这里',
              style: TextStyle(
                color: _muted,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Text(
              '未读 ${controller.unreadCount}',
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: controller.markAllSeen,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(
                  '全部已读',
                  style: TextStyle(
                    color: _accent,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: Color(0x14FFFFFF)),
            itemBuilder: (context, index) {
              final item = items[index];
              return Tooltip(
                message: '打开${item.sourceName}',
                waitDuration: const Duration(milliseconds: 600),
                child: InkWell(
                  onTap: () => controller.openMessage(item),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 54,
                    child: Row(
                      children: [
                        _ClientGlyph(source: item.source, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 10,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x22FFFFFF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.count}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _text,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeatherTab extends StatelessWidget {
  const _WeatherTab({required this.controller});

  final IslandController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.weather;
    if (snapshot == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 26, color: _muted),
            const SizedBox(height: 8),
            const Text(
              '天气暂时取不到',
              style: TextStyle(
                color: _text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              controller.weatherStatus,
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
    }

    final highLow = snapshot.highC != null && snapshot.lowC != null
        ? '${snapshot.highC!.round()}° / ${snapshot.lowC!.round()}°'
        : null;
    final summary = [
      snapshot.place.isEmpty ? '当地' : snapshot.place,
      ?highLow,
    ].join(' · ');
    final metrics = [
      if (snapshot.feelsLikeC != null) '体感 ${snapshot.feelsLikeC!.round()}°',
      if (snapshot.humidity != null) '湿度 ${snapshot.humidity}%',
      if (snapshot.windKph != null) '风 ${snapshot.windKph!.round()} km/h',
    ];
    final updated = snapshot.updatedAt.millisecondsSinceEpoch > 0
        ? _clockText(snapshot.updatedAt)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Column(
                children: [
                  Icon(
                    _weatherIcon(snapshot.kind, snapshot.isDay),
                    size: 30,
                    color: _weatherColor(snapshot.kind),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    snapshot.description,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${snapshot.roundedTemp}°',
                        style: const TextStyle(
                          color: _text,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const Spacer(),
                      if (updated != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '$updated 更新',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 9,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        const Divider(height: 1, color: Color(0x14FFFFFF)),
        if (metrics.isNotEmpty) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              for (final metric in metrics)
                Expanded(
                  child: Text(
                    metric,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 10,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
        ],
        const SizedBox(height: 7),
        Expanded(
          child: snapshot.days.isEmpty
              ? const Center(
                  child: Text(
                    '暂无预报',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x0AFFFFFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < snapshot.days.length;
                          index++
                        ) ...[
                          if (index > 0)
                            Container(
                              width: 1,
                              height: 40,
                              color: const Color(0x14FFFFFF),
                            ),
                          Expanded(
                            child: _WeatherDayCell(
                              day: snapshot.days[index],
                              index: index,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _WeatherDayCell extends StatelessWidget {
  const _WeatherDayCell({required this.day, required this.index});

  final WeatherDay day;
  final int index;

  @override
  Widget build(BuildContext context) {
    final rain = day.precipProbability;
    final showRain = rain != null && rain >= 20;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(
          height: 12,
          child: Center(
            child: Text(
              _dayLabel(index, day.date),
              style: const TextStyle(
                color: _muted,
                fontSize: 10,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 20,
          child: Center(
            child: Icon(
              _weatherIcon(day.kind, true),
              size: 18,
              color: _weatherColor(day.kind),
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 14,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${day.highC.round()}° / ${day.lowC.round()}°',
                style: const TextStyle(
                  color: _text,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 11,
          child: Center(
            child: Text(
              showRain ? '$rain%' : '',
              style: const TextStyle(
                color: Color(0xFF64B5F6),
                fontSize: 9,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _dayLabel(int index, String date) {
  if (index == 0) return '今天';
  if (index == 1) return '明天';
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return names[parsed.weekday - 1];
}

String _clockText(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

class _MediaTab extends StatelessWidget {
  const _MediaTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note_rounded, size: 28, color: _muted),
          const SizedBox(height: 8),
          const Text(
            'SMTC 媒体未接入',
            style: TextStyle(
              color: _text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Phase 2 接入媒体信息、进度与歌词',
            style: TextStyle(
              color: _muted,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 220,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsTab extends StatelessWidget {
  const _DiagnosticsTab({required this.controller});

  final IslandController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _DiagRow(label: 'sidecar', value: controller.connectionDetail),
        _DiagRow(label: '微信监听', value: controller.wechatStatus),
        _DiagRow(label: '系统通知', value: controller.notificationsStatus),
        _DiagRow(label: '天气', value: controller.weatherStatus),
        const _DiagRow(label: '快捷键', value: 'Ctrl + Alt + Space 展开 / 收起'),
        const _DiagRow(label: '点击穿透', value: '岛体外点击直达下层窗口'),
        const SizedBox(height: 8),
        TextField(
          style: const TextStyle(color: _text, fontSize: 12),
          cursorColor: _accent,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0x14FFFFFF),
            hintText: '输入法测试：用微软拼音或搜狗输入中文',
            hintStyle: const TextStyle(color: _muted, fontSize: 11),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _text,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0x1F2ED573) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _accent : _muted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? _accent : const Color(0xFFFFB020);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            ok ? '已连接' : '重连中',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientGlyph extends StatelessWidget {
  const _ClientGlyph({required this.source, required this.size});

  final String source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final qq = source == 'qq';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: qq ? const Color(0xFF12B7F5) : const Color(0xFF07C160),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: FaIcon(
        qq ? FontAwesomeIcons.qq : FontAwesomeIcons.weixin,
        size: size * 0.62,
        color: Colors.white,
      ),
    );
  }
}
