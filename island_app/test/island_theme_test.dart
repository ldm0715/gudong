import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/core/theme/island_colors.dart';

void main() {
  test('resolves skins by id with midnight as fallback', () {
    expect(IslandColors.byId('daylight').id, 'daylight');
    expect(IslandColors.byId('midnight').id, 'midnight');
    expect(IslandColors.byId('unknown').id, 'midnight');
    expect(IslandColors.byId(null).id, 'midnight');
  });

  test('skins expose distinct brightness and background', () {
    expect(IslandColors.midnight.brightness, Brightness.dark);
    expect(IslandColors.daylight.brightness, Brightness.light);
    expect(
      IslandColors.midnight.background,
      isNot(IslandColors.daylight.background),
    );
  });

  test('lerp keeps the endpoint values', () {
    final start = IslandColors.midnight;
    final end = IslandColors.daylight;
    expect(start.lerp(end, 0).id, 'midnight');
    expect(start.lerp(end, 1).id, 'daylight');
    expect(start.lerp(end, 0).background, start.background);
  });
}
