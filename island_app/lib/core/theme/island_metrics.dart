/// 岛体尺寸常量：圆角、间距、图标与命中区。
///
/// 岛体空间受窗口画布 420×300 限制，所有尺寸按此比例取值，不要就地写字面量。
abstract final class IslandMetrics {
  // 圆角

  /// 进度条、指示条等细长元素。
  static const double radiusBar = 2;

  /// 小标签。
  static const double radiusTag = 4;

  /// 紧凑胶囊与内嵌小卡片。
  static const double radiusChip = 6;

  /// 按钮、输入框、tab 的统一圆角。
  static const double radiusControl = 8;

  /// 状态胶囊。
  static const double radiusPill = 10;

  /// 面板与弹层。
  static const double radiusPanel = 12;

  /// 卡片。
  static const double radiusCard = 14;

  /// 封面图。
  static const double radiusCover = 16;

  /// 岛体收起态。
  static const double radiusIslandCollapsed = 18;

  /// 岛体横幅态。
  static const double radiusIslandBanner = 22;

  /// 岛体展开态。
  static const double radiusIslandExpanded = 24;

  /// 完全圆角，按元素高度取半径。
  static double pill(double height) => height / 2;

  // 间距

  static const double space2 = 2;
  static const double space3 = 3;
  static const double space4 = 4;
  static const double space5 = 5;
  static const double space6 = 6;
  static const double space7 = 7;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space14 = 14;
  static const double space16 = 16;

  // 图标

  static const double iconXS = 12;
  static const double iconSM = 14;
  static const double iconMD = 16;
  static const double iconLG = 18;
  static const double iconXL = 22;
  static const double icon2XL = 26;
  static const double icon3XL = 30;

  // 岛体结构

  static const double handleWidth = 36;
  static const double handleHeight = 4;
  static const double waveBarWidth = 2.5;

  /// 叠放图标的相互偏移，后一个压住前一个的多少像素。
  static const double stackOverlap = 6;

  /// 叠放图标之间用背景色描边的宽度，用于区分层次。
  static const double stackRing = 1.5;

  /// 鼠标命中区下限，可点区域小于此值时用内边距补足。
  static const double hitTargetMin = 28;
}
