import 'dart:math' as math;
import 'dart:ui';

import '../../core/theme/island_metrics.dart';
import '../../core/window/app_window.dart';
import '../../core/window/dock_edge.dart';

/// 收起态实际渲染的元素。尺寸计算与绘制共用同一份判断，避免两边各写一套。
class CollapsedContent {
  const CollapsedContent({
    this.schedule = false,
    this.weather = false,
    this.metricCount = 0,
    this.agentCount = 0,
    this.extraAgents = 0,
    this.ime = false,
    this.wechat = false,
    this.qq = false,
    this.mail = false,
    this.playing = false,
  });

  /// 当天还有未触发的日程，时间右侧显示闹钟。
  final bool schedule;

  /// 有天气快照，显示图标与温度。
  final bool weather;

  /// 收起态指标数量。
  final int metricCount;

  /// 实际显示的 agent 图标数，超出部分合并为 `+N`。
  final int agentCount;
  final int extraAgents;

  /// 输入法常驻标识。
  final bool ime;

  /// 微信 / QQ 未读标识。
  final bool wechat;
  final bool qq;

  /// 有未读邮件且能匹配到账号，显示服务商图标。
  final bool mail;

  /// 正在播放，右侧显示音波。
  final bool playing;
}

/// 岛体各状态的尺寸与命中区域。绘制与点击穿透都以这里为准，避免两处手抄。
///
/// 顶部停靠为横向布局；左右停靠为竖向布局，展开面板保持竖向尺寸，
/// 内容不旋转，只把 tab 改为竖排。
abstract final class IslandLayout {
  /// 顶部停靠时岛体与屏幕上边缘的间距。
  static const double edgeInset = 8;

  /// 横杠态贴边显示，避免压在最大化窗口的标题栏上。
  static const double miniEdgeInset = 2;

  // 横向（顶部停靠）。
  static const Size bannerSize = Size(360, 80);
  static const Size expandedSize = Size(380, 260);

  /// 收起态厚度：横向为高度，竖向为宽度。
  static const double collapsedThickness = 36;
  static const double collapsedVerticalThickness = 40;

  // 前台窗口最大化时只显示一条横杠。视觉上很细，命中区补到 28px。
  static const Size miniBarVisualSize = Size(48, 6);
  static const Size miniBarVisualVerticalSize = Size(6, 48);
  static const Size miniBarHitSize = Size(56, 16);
  static const Size miniBarHitVerticalSize = Size(16, 56);

  static Size miniBarVisualSizeFor(DockEdge side) =>
      side.isVertical ? miniBarVisualVerticalSize : miniBarVisualSize;

  static Size miniBarHitSizeFor(DockEdge side) =>
      side.isVertical ? miniBarHitVerticalSize : miniBarHitSize;

  // 收起态内容宽度预算，包含左右各 10 的内边距与时间。
  static const double _collapsedPadding = 20;
  static const double _clockWidth = 42;
  static const double _scheduleWidth = 20;
  static const double _weatherWidth = 48;
  static const double _metricWidth = 46;
  static const double _agentWidth = 21;
  static const double _extraAgentWidth = 14;
  static const double _imeWidth = 28;
  static const double _wechatWidth = 26;
  static const double _qqWidth = 22;
  static const double _mailWidth = 24;
  static const double _waveWidth = 26;

  // 收起态内容高度预算，包含上下各 10 的内边距与两行时间。
  static const double _clockHeight = 26;
  static const double _scheduleHeight = 24;
  static const double _weatherHeight = 38;
  static const double _metricHeight = 36;
  static const double _agentHeight = 21;
  static const double _extraAgentHeight = 14;
  static const double _imeHeight = 24;
  static const double _wechatHeight = 24;
  static const double _qqHeight = 22;
  static const double _mailHeight = 22;
  static const double _waveHeight = 20;

  /// 只剩时钟时的最小宽 / 高，避免贴边过紧。
  static const double minCollapsedWidth = 96;
  static const double minCollapsedHeight = 96;

  /// 估算值略大于实际内容，保证内容不会被 FittedBox 缩小。
  static const double _sizingSafety = 4;

  /// 收起态最大尺寸，不能超出窗口画布扣除边缘留白后的范围。
  static Size get maxCollapsedSize => Size(
    appWindowSize.width - edgeInset * 2,
    appWindowSize.height - edgeInset * 2,
  );

  /// 按实际显示的元素算收起态尺寸：横向只变宽，竖向只变高。
  static Size collapsedSizeFor(DockEdge side, CollapsedContent content) {
    final max = maxCollapsedSize;
    if (side.isVertical) {
      final height = math.min(
        max.height,
        math.max(minCollapsedHeight, _verticalHeight(content)),
      );
      return Size(collapsedVerticalThickness, height);
    }
    final width = math.min(
      max.width,
      math.max(minCollapsedWidth, _horizontalWidth(content)),
    );
    return Size(width, collapsedThickness);
  }

  static double _horizontalWidth(CollapsedContent content) {
    var width = _collapsedPadding + _clockWidth;
    if (content.schedule) width += _scheduleWidth;
    if (content.weather) width += _weatherWidth;
    if (content.metricCount > 0) {
      width += IslandMetrics.space6 + content.metricCount * _metricWidth;
    }
    if (content.agentCount > 0) {
      width += IslandMetrics.space6 + content.agentCount * _agentWidth;
      if (content.extraAgents > 0) width += _extraAgentWidth;
    }
    if (content.ime) width += _imeWidth;
    if (content.wechat) width += _wechatWidth;
    if (content.qq) width += _qqWidth;
    if (content.mail) width += _mailWidth;
    if (content.playing) width += _waveWidth;
    return width + _sizingSafety;
  }

  static double _verticalHeight(CollapsedContent content) {
    var height = _collapsedPadding + _clockHeight;
    if (content.schedule) height += _scheduleHeight;
    if (content.weather) height += _weatherHeight;
    if (content.metricCount > 0) {
      height += IslandMetrics.space4 + content.metricCount * _metricHeight;
    }
    if (content.agentCount > 0) {
      height += IslandMetrics.space4 + content.agentCount * _agentHeight;
      if (content.extraAgents > 0) height += _extraAgentHeight;
    }
    if (content.ime) height += _imeHeight;
    if (content.wechat) height += _wechatHeight;
    if (content.qq) height += _qqHeight;
    if (content.mail) height += _mailHeight;
    if (content.playing) height += _waveHeight;
    return height + _sizingSafety;
  }

  static Size expandedSizeFor(DockEdge side) => expandedSize;

  /// 横幅保持横向，临时消息不因停靠方向变得难读。
  static Size bannerSizeFor(DockEdge side) => bannerSize;

  /// 岛体在窗口画布内的矩形。三种停靠都保留同样的边缘间距。
  static Rect rectFor(DockEdge side, Size size, {double inset = edgeInset}) {
    final centeredX = (appWindowSize.width - size.width) / 2;
    final centeredY = (appWindowSize.height - size.height) / 2;
    return switch (side) {
      DockEdge.top => Rect.fromLTWH(centeredX, inset, size.width, size.height),
      DockEdge.left => Rect.fromLTWH(inset, centeredY, size.width, size.height),
      DockEdge.right => Rect.fromLTWH(
        appWindowSize.width - inset - size.width,
        centeredY,
        size.width,
        size.height,
      ),
    };
  }
}
