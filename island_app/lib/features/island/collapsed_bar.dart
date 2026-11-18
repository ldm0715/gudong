import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../messages/messages_controller.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_widgets.dart';
import 'client_glyph.dart';
import 'island_layout.dart';

/// 收起态：时间 + 天气 + 微信 / QQ 未读标识。
class CollapsedBar extends StatefulWidget {
  const CollapsedBar({
    super.key,
    required this.messages,
    required this.weather,
    required this.showWeather,
  });

  final MessagesController messages;
  final WeatherController weather;
  final bool showWeather;

  @override
  State<CollapsedBar> createState() => _CollapsedBarState();
}

class _CollapsedBarState extends State<CollapsedBar> {
  Timer? _clock;

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
    final colors = context.islandColors;
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final snapshot = widget.showWeather ? widget.weather.snapshot : null;
    return SizedBox(
      width: IslandLayout.collapsedSize.width,
      height: IslandLayout.collapsedSize.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            time,
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              decoration: TextDecoration.none,
            ),
          ),
          if (snapshot != null) ...[
            const SizedBox(width: 7),
            WeatherChip(snapshot: snapshot),
          ],
          if (widget.messages.hasWechat) ...[
            const SizedBox(width: 8),
            const ClientGlyph(source: 'wechat', size: 18),
          ],
          if (widget.messages.hasQq) ...[
            const SizedBox(width: 4),
            const ClientGlyph(source: 'qq', size: 18),
          ],
        ],
      ),
    );
  }
}
