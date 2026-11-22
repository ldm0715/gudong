import 'dart:math' as math;
import 'dart:ui';

import '../../core/window/app_window.dart';
import '../../core/window/dock_edge.dart';

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
  static const Size collapsedSize = Size(178, 36);
  static const Size bannerSize = Size(360, 80);
  static const Size expandedSize = Size(380, 260);

  // 常驻输入法标识会占用一段宽度，单独放大收起态，避免挤压其他内容。
  static const Size collapsedImeSize = Size(210, 36);

  // 竖向（左右停靠）：收起为窄条；展开面板与顶部完全同尺寸、同布局。
  static const Size collapsedVerticalSize = Size(40, 178);
  static const Size collapsedVerticalImeSize = Size(40, 200);

  // 前台窗口最大化时只显示一条横杠。视觉上很细，命中区补到 28px。
  static const Size miniBarVisualSize = Size(48, 6);
  static const Size miniBarVisualVerticalSize = Size(6, 48);
  static const Size miniBarHitSize = Size(56, 16);
  static const Size miniBarHitVerticalSize = Size(16, 56);

  static Size miniBarVisualSizeFor(DockEdge side) =>
      side.isVertical ? miniBarVisualVerticalSize : miniBarVisualSize;

  static Size miniBarHitSizeFor(DockEdge side) =>
      side.isVertical ? miniBarHitVerticalSize : miniBarHitSize;

  /// 收起态每个指标占用的额外宽 / 高，随设置中的指标数量增长。
  /// 竖排指标为图标在上、数值在下两行，高度按两行加间距计算。
  static const double metricChipWidth = 40;
  static const double metricChipHeight = 34;

  /// 收起态最大尺寸，不能超出窗口画布扣除边缘留白后的范围。
  static Size get maxCollapsedSize => Size(
    appWindowSize.width - edgeInset * 2,
    appWindowSize.height - edgeInset * 2,
  );

  static Size collapsedSizeFor(
    DockEdge side, {
    bool imeIndicator = false,
    int metricCount = 0,
  }) {
    final base = side.isVertical
        ? (imeIndicator ? collapsedVerticalImeSize : collapsedVerticalSize)
        : (imeIndicator ? collapsedImeSize : collapsedSize);
    if (metricCount <= 0) return base;
    final max = maxCollapsedSize;
    if (side.isVertical) {
      final height = math.min(
        max.height,
        base.height + metricCount * metricChipHeight,
      );
      return Size(base.width, height);
    }
    final width = math.min(
      max.width,
      base.width + metricCount * metricChipWidth,
    );
    return Size(width, base.height);
  }

  /// 收起栏自身使用的尺寸，按横向 / 竖向布局取。
  static Size collapsedBarSize({
    required bool vertical,
    required bool imeIndicator,
    int metricCount = 0,
  }) => collapsedSizeFor(
    vertical ? DockEdge.left : DockEdge.top,
    imeIndicator: imeIndicator,
    metricCount: metricCount,
  );

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
