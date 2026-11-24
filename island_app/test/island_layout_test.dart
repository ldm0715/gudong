import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/core/window/app_window.dart';
import 'package:island_app/core/window/dock_edge.dart';
import 'package:island_app/features/island/island_layout.dart';

const _clockOnly = CollapsedContent();

const _allOn = CollapsedContent(
  schedule: true,
  weather: true,
  metricCount: 2,
  agentCount: 3,
  extraAgents: 2,
  ime: true,
  wechat: true,
  qq: true,
  mail: true,
  playing: true,
  update: true,
);

void main() {
  test('top dock anchors the island to the top center', () {
    final rect = IslandLayout.rectFor(
      DockEdge.top,
      IslandLayout.planFor(DockEdge.top, _clockOnly).size,
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
    final size = IslandLayout.planFor(DockEdge.top, _clockOnly).size;
    expect(size.width, IslandLayout.minCollapsedWidth);
    expect(size.height, IslandLayout.collapsedThickness);
  });

  test('collapsed island grows with each visible element', () {
    final base = IslandLayout.planFor(DockEdge.top, _clockOnly).size;
    final weather = IslandLayout.planFor(
      DockEdge.top,
      const CollapsedContent(weather: true),
    ).size;
    final crowded = IslandLayout.planFor(
      DockEdge.top,
      const CollapsedContent(
        weather: true,
        schedule: true,
        metricCount: 2,
        agentCount: 3,
        ime: true,
        wechat: true,
        qq: true,
        mail: true,
        playing: true,
      ),
    ).size;
    expect(weather.width, greaterThan(base.width));
    expect(crowded.width, greaterThan(weather.width));
    expect(crowded.width, lessThanOrEqualTo(appWindowSize.width));
  });

  test('horizontal budget never exceeds the canvas', () {
    final plan = IslandLayout.planFor(
      DockEdge.top,
      const CollapsedContent(metricCount: 20),
    );
    expect(plan.size.width, lessThanOrEqualTo(IslandLayout.maxCollapsedSize.width));
    expect(plan.content.metricCount, lessThan(20));
  });

  test('horizontal worst case keeps unread, metrics and agents', () {
    final plan = IslandLayout.planFor(DockEdge.top, _allOn);
    expect(plan.size.width, lessThanOrEqualTo(IslandLayout.maxCollapsedSize.width));
    expect(plan.content.wechat, isTrue);
    expect(plan.content.qq, isTrue);
    expect(plan.content.mail, isTrue);
    expect(plan.content.playing, isTrue);
    expect(plan.content.metricCount, 2);
    expect(plan.content.agentCount, 3);
    expect(plan.content.extraAgents, 2);
    // 低优先级的天气与输入法先让位。
    expect(plan.content.weather, isFalse);
    expect(plan.content.ime, isFalse);
  });

  test('vertical worst case keeps agents and fits the canvas', () {
    final plan = IslandLayout.planFor(DockEdge.left, _allOn);
    expect(
      plan.size.height,
      lessThanOrEqualTo(IslandLayout.maxCollapsedSize.height),
    );
    expect(plan.content.wechat, isTrue);
    expect(plan.content.qq, isTrue);
    expect(plan.content.mail, isTrue);
    expect(plan.content.agentCount, 3);
    // 竖向空间更紧，指标放不下后截断天气与输入法。
    expect(plan.content.metricCount, 0);
    expect(plan.content.weather, isFalse);
    expect(plan.content.ime, isFalse);
  });

  test('vertical collapsed island grows in height only', () {
    final base = IslandLayout.planFor(DockEdge.left, _clockOnly).size;
    final three = IslandLayout.planFor(
      DockEdge.left,
      const CollapsedContent(metricCount: 3),
    ).size;
    expect(three.width, base.width);
    expect(three.height, greaterThan(base.height));
    expect(three.height, lessThanOrEqualTo(appWindowSize.height));
  });
}
