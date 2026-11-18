import 'dart:ui';

import '../../core/window/app_window.dart';

/// 岛体各状态的尺寸与命中区域。绘制与点击穿透都以这里为准，避免两处手抄。
abstract final class IslandLayout {
  static const double topInset = 8;

  static const Size collapsedSize = Size(156, 36);
  static const Size bannerSize = Size(360, 80);
  static const Size expandedSize = Size(380, 260);

  /// 在窗口画布内水平居中、距顶部 [topInset] 的矩形（窗口坐标）。
  static Rect centered(Size size) => Rect.fromLTWH(
    (appWindowSize.width - size.width) / 2,
    topInset,
    size.width,
    size.height,
  );
}
