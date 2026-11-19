import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/core/window/app_window.dart';
import 'package:island_app/core/window/dock_edge.dart';
import 'package:island_app/features/island/island_layout.dart';

void main() {
  test('top dock anchors the island to the top center', () {
    final rect = IslandLayout.rectFor(DockEdge.top, IslandLayout.collapsedSize);
    expect(rect.top, IslandLayout.edgeInset);
    expect(rect.center.dx, appWindowSize.width / 2);
  });

  test('side docks reuse the top panel and keep the edge inset', () {
    final frame = IslandLayout.expandedSizeFor(DockEdge.left);
    expect(frame, IslandLayout.expandedSize);

    final left = IslandLayout.rectFor(DockEdge.left, frame);
    final right = IslandLayout.rectFor(DockEdge.right, frame);
    expect(left.left, IslandLayout.edgeInset);
    expect(right.right, appWindowSize.width - IslandLayout.edgeInset);
    expect(left.center.dy, appWindowSize.height / 2);
    expect(right.center.dy, appWindowSize.height / 2);
  });

  test('portrait panel fits the window canvas', () {
    final frame = IslandLayout.expandedSizeFor(DockEdge.right);
    expect(frame.width, lessThanOrEqualTo(appWindowSize.width));
    expect(frame.height, lessThanOrEqualTo(appWindowSize.height));
  });
}
