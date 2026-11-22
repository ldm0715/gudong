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

  test('collapsed island grows with metrics but stays inside the canvas', () {
    final base = IslandLayout.collapsedSizeFor(DockEdge.top);
    final one = IslandLayout.collapsedSizeFor(DockEdge.top, metricCount: 1);
    final crowded = IslandLayout.collapsedSizeFor(
      DockEdge.top,
      metricCount: 20,
    );
    expect(one.width, greaterThan(base.width));
    expect(one.height, base.height);
    expect(crowded.width, IslandLayout.maxCollapsedSize.width);
    expect(crowded.width, lessThanOrEqualTo(appWindowSize.width));
  });

  test('vertical collapsed island grows in height only', () {
    final base = IslandLayout.collapsedSizeFor(DockEdge.left);
    final three = IslandLayout.collapsedSizeFor(DockEdge.left, metricCount: 3);
    expect(three.width, base.width);
    expect(three.height, greaterThan(base.height));
    expect(three.height, lessThanOrEqualTo(appWindowSize.height));
  });
}
