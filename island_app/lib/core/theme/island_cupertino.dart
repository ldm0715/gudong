import 'package:flutter/cupertino.dart';

import 'island_colors.dart';
import 'island_typography.dart';

/// 从岛体 token 派生 Cupertino 主题，仅供少量 Cupertino 叶子控件使用。
///
/// 不使用 Cupertino 默认配色、字体族与尺寸；主题随 `themeId` 切换。
CupertinoThemeData islandCupertinoTheme(IslandColors colors) {
  return CupertinoThemeData(
    brightness: colors.brightness,
    primaryColor: colors.accent,
    primaryContrastingColor: colors.background,
    barBackgroundColor: colors.background,
    scaffoldBackgroundColor: colors.background,
    selectionHandleColor: colors.accent,
    textTheme: CupertinoTextThemeData(
      textStyle: IslandTypography.body.tint(colors.text),
      actionTextStyle: IslandTypography.bodyStrong.tint(colors.accent),
      navActionTextStyle: IslandTypography.body.tint(colors.accent),
      navTitleTextStyle: IslandTypography.title.tint(colors.text),
      navLargeTitleTextStyle: IslandTypography.display.tint(colors.text),
      tabLabelTextStyle: IslandTypography.micro.tint(colors.muted),
      pickerTextStyle: IslandTypography.body.tint(colors.text),
      dateTimePickerTextStyle: IslandTypography.body.tint(colors.text),
    ),
  );
}
