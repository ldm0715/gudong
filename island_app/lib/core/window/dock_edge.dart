/// 岛体停靠的屏幕边缘。顶部为横向，左右两侧为竖向（竖屏）。
enum DockEdge {
  top,
  left,
  right;

  bool get isVertical => this != DockEdge.top;

  String get id => name;

  static DockEdge parse(String? raw) => switch (raw) {
    'left' => DockEdge.left,
    'right' => DockEdge.right,
    _ => DockEdge.top,
  };
}
