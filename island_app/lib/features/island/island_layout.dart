import 'dart:math' as math;
import 'dart:ui';

import '../../core/theme/island_metrics.dart';
import '../../core/widgets/glyph_stack.dart';
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
    this.update = false,
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

  /// 有新版本可用，时间右侧显示更新图标。
  final bool update;
}

/// 按宽度预算取舍后的收起态。`content` 只含装得下的元素，`size` 为最终尺寸。
class CollapsedPlan {
  const CollapsedPlan({required this.content, required this.size});

  final CollapsedContent content;
  final Size size;
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

  /// 展开态尺寸取画布扣除边缘留白后的最大值，与收起态上限一致，
  /// 避免内容多时收起条比展开面板还宽。
  static Size get expandedSize => Size(
    appWindowSize.width - edgeInset * 2,
    appWindowSize.height - edgeInset * 2,
  );

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

  /// 收起态最多展示的 agent 图标数，超出部分合并为 `+N`。
  static const int maxCollapsedAgents = 3;

  // 收起态内容预算。每项都包含自己的前导间距，取舍后直接相加。
  static const double _collapsedPadding = 20;
  static const double _clockWidth = 42;
  static const double _clockHeight = 26;

  static const double _weatherTextWidth = 28;
  static const double _weatherTextHeight = 12;
  static const double _metricTextWidth = 36;
  static const double _metricTextHeight = 12;
  static const double _agentBadgeTextWidth = 18;
  static const double _agentBadgeTextHeight = 12;

  // 横向单项宽度。
  static const double _scheduleWidth =
      IslandMetrics.space6 + IslandMetrics.iconSM;
  static const double _updateWidth = IslandMetrics.space6 + IslandMetrics.iconSM;
  static const double _weatherWidth =
      IslandMetrics.space7 +
      IslandMetrics.iconSM +
      IslandMetrics.space3 +
      _weatherTextWidth;
  static const double _metricChipWidth =
      IslandMetrics.iconSM +
      IslandMetrics.space3 +
      _metricTextWidth +
      IslandMetrics.space6;
  static const double _metricGroupGap = IslandMetrics.space6;
  static const double _imeWidth = IslandMetrics.space6 + 22;
  static const double _wechatWidth = IslandMetrics.space8 + IslandMetrics.iconLG;
  static const double _qqWidth = IslandMetrics.space4 + IslandMetrics.iconLG;
  static const double _mailWidth = IslandMetrics.space6 + IslandMetrics.iconLG;
  static const double _waveWidth = IslandMetrics.space6 + 20;
  static const double _agentGap = IslandMetrics.space6;
  static const double _agentBadgeWidth =
      IslandMetrics.space2 + _agentBadgeTextWidth;

  // 竖向单项高度。
  static const double _scheduleHeight =
      IslandMetrics.space6 + IslandMetrics.iconLG;
  static const double _updateHeight = IslandMetrics.space6 + IslandMetrics.iconLG;
  static const double _weatherHeight =
      IslandMetrics.space6 +
      IslandMetrics.iconLG +
      IslandMetrics.space2 +
      _weatherTextHeight;
  static const double _metricChipHeight =
      IslandMetrics.space2 +
      IslandMetrics.iconLG +
      IslandMetrics.space2 +
      _metricTextHeight;
  static const double _metricGroupGapHeight = IslandMetrics.space4;
  static const double _imeHeight = IslandMetrics.space6 + IslandMetrics.iconLG;
  static const double _wechatHeight =
      IslandMetrics.space6 + IslandMetrics.iconLG;
  static const double _qqHeight = IslandMetrics.space4 + IslandMetrics.iconLG;
  static const double _mailHeight = IslandMetrics.space4 + IslandMetrics.iconLG;
  static const double _waveHeight = IslandMetrics.space4 + 20;
  static const double _agentGapHeight = IslandMetrics.space4;
  static const double _agentBadgeHeight =
      IslandMetrics.space2 + _agentBadgeTextHeight;

  /// 只剩时钟时的最小宽 / 高，避免贴边过紧。
  static const double minCollapsedWidth = 96;
  static const double minCollapsedHeight = 96;

  /// 估算值略大于实际内容，保证内容在字宽波动时也不会溢出。
  static const double _sizingSafety = 6;

  static const double _horizontalBase =
      _collapsedPadding + _clockWidth + _sizingSafety;
  static const double _verticalBase =
      _collapsedPadding + _clockHeight + _sizingSafety;

  /// 收起态最大尺寸，与展开态一致，不能超出窗口画布。
  static Size get maxCollapsedSize => expandedSize;

  /// 按预算取舍收起态内容，并算出最终尺寸。
  ///
  /// 优先级从高到低：未读（微信 / QQ / 邮件）、播放、日程、更新、agent、
  /// 指标、天气、输入法。某一项放不下就截断更低优先级的项；
  /// 指标按配置顺序保留前缀，agent 叠放数量不足时先减少可见图标。
  static CollapsedPlan planFor(DockEdge side, CollapsedContent source) {
    final vertical = side.isVertical;
    final budget = vertical ? maxCollapsedSize.height : maxCollapsedSize.width;
    var used = vertical ? _verticalBase : _horizontalBase;

    var wechat = source.wechat;
    var qq = source.qq;
    var mail = source.mail;
    var playing = source.playing;
    var schedule = source.schedule;
    var update = source.update;
    var weather = source.weather;
    var ime = source.ime;
    var metricCount = 0;
    final agentTotal = source.agentCount + source.extraAgents;
    var agentVisible = source.agentCount;

    // 一旦某个优先级的项放不下，就停止接收更低优先级的项，避免出现
    // "低优先级挤掉高优先级" 的错位。
    var open = true;
    bool fits(double extent) => used + extent <= budget;
    void take(double extent) => used += extent;
    bool place(double extent) {
      if (!open) return false;
      if (fits(extent)) {
        take(extent);
        return true;
      }
      open = false;
      return false;
    }

    if (wechat && !place(vertical ? _wechatHeight : _wechatWidth)) wechat = false;
    if (qq && !place(vertical ? _qqHeight : _qqWidth)) qq = false;
    if (mail && !place(vertical ? _mailHeight : _mailWidth)) mail = false;
    if (playing && !place(vertical ? _waveHeight : _waveWidth)) playing = false;
    if (schedule && !place(vertical ? _scheduleHeight : _scheduleWidth)) {
      schedule = false;
    }
    if (update && !place(vertical ? _updateHeight : _updateWidth)) update = false;

    // agent 先用完整的叠放，放不下就减少可见图标，最后整项放弃。
    if (open && agentVisible > 0) {
      while (agentVisible > 0) {
        final extent = _agentExtent(vertical, agentVisible, agentTotal);
        if (fits(extent)) {
          take(extent);
          break;
        }
        agentVisible--;
      }
      if (agentVisible == 0) open = false;
    }

    // 指标保持配置顺序，放不下的从尾部截断。
    if (open) {
      for (var index = 0; index < source.metricCount; index++) {
        final extent = _metricExtent(vertical, index);
        if (!fits(extent)) {
          open = false;
          break;
        }
        take(extent);
        metricCount++;
      }
    }

    if (weather && !place(vertical ? _weatherHeight : _weatherWidth)) {
      weather = false;
    }
    if (ime && !place(vertical ? _imeHeight : _imeWidth)) ime = false;

    final minExtent = vertical ? minCollapsedHeight : minCollapsedWidth;
    final extent = math.min(budget, math.max(minExtent, used));
    final size = vertical
        ? Size(collapsedVerticalThickness, extent)
        : Size(extent, collapsedThickness);
    return CollapsedPlan(
      content: CollapsedContent(
        schedule: schedule,
        weather: weather,
        metricCount: metricCount,
        agentCount: agentVisible,
        extraAgents: agentTotal - agentVisible,
        ime: ime,
        wechat: wechat,
        qq: qq,
        mail: mail,
        playing: playing,
        update: update,
      ),
      size: size,
    );
  }

  static double _metricExtent(bool vertical, int index) {
    if (vertical) {
      return index == 0
          ? _metricGroupGapHeight + _metricChipHeight
          : _metricChipHeight;
    }
    return index == 0
        ? _metricGroupGap + _metricChipWidth
        : _metricChipWidth;
  }

  static double _agentExtent(bool vertical, int visible, int total) {
    final stack = GlyphStack.extent(
      visible,
      size: IslandMetrics.iconLG,
      overlap: IslandMetrics.stackOverlap,
    );
    final badge = total > visible
        ? (vertical ? _agentBadgeHeight : _agentBadgeWidth)
        : 0.0;
    return (vertical ? _agentGapHeight : _agentGap) + stack + badge;
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
