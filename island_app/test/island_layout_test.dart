import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/core/window/app_window.dart';
import 'package:island_app/core/window/dock_edge.dart';
import 'package:island_app/features/island/island_layout.dart';

const _clockOnly = CollapsedContent();

void main() {
  test('top dock anchors the island to the top center', () {
    final rect = IslandLayout.rectFor(
      DockEdge.top,
      IslandLayout.collapsedSizeFor(DockEdge.top, _clockOnly),
    );
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

  test('collapsed island starts at the minimum width with only the clock', () {
    final size = IslandLayout.collapsedSizeFor(DockEdge.top, _clockOnly);
    expect(size.width, IslandLayout.minCollapsedWidth);
    expect(size.height, IslandLayout.collapsedThickness);
  });

  test('collapsed island grows with each visible element', () {
    final base = IslandLayout.collapsedSizeFor(DockEdge.top, _clockOnly);
    final weather = IslandLayout.collapsedSizeFor(
      DockEdge.top,
      const CollapsedContent(weather: true),
    );
    final crowded = IslandLayout.collapsedSizeFor(
      DockEdge.top,
      const CollapsedContent(
        weather: true,
        schedule: true,
        metricCount: 2,
        agentCount: 2,
        ime: true,
        wechat: true,
        qq: true,
        mail: true,
        playing: true,
      ),
    );
    expect(weather.width, greaterThan(base.width));
    expect(crowded.width, greaterThan(weather.width));
    expect(crowded.width, lessThanOrEqualTo(appWindowSize.width));
  });

  test('collapsed island caps at the canvas width', () {
    final crowded = IslandLayout.collapsedSizeFor(
      DockEdge.top,
      const CollapsedContent(metricCount: 20),
    );
    expect(crowded.width, IslandLayout.maxCollapsedSize.width);
  });

  test('vertical collapsed island grows in height only', () {
    final base = IslandLayout.collapsedSizeFor(DockEdge.left, _clockOnly);
    final three = IslandLayout.collapsedSizeFor(
      DockEdge.left,
      const CollapsedContent(metricCount: 3),
    );
    expect(three.width, base.width);
    expect(three.height, greaterThan(base.height));
    expect(three.height, lessThanOrEqualTo(appWindowSize.height));
  });
}
