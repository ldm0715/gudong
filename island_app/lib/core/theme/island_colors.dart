import 'package:flutter/material.dart';

/// 岛体配色主题。皮肤由 `settings.themeId` 决定，通过 ThemeExtension 下发给组件。
class IslandColors extends ThemeExtension<IslandColors> {
  const IslandColors({
    required this.id,
    required this.name,
    required this.brightness,
    required this.background,
    required this.stroke,
    required this.divider,
    required this.surface,
    required this.chip,
    required this.handle,
    required this.accent,
    required this.warning,
    required this.text,
    required this.muted,
    required this.wechat,
    required this.qq,
    required this.rain,
    required this.windowBackground,
    required this.sidebarBackground,
    required this.cardBackground,
    required this.cardStroke,
    required this.navSelected,
    required this.switchOff,
  });

  final String id;
  final String name;
  final Brightness brightness;
  final Color background;
  final Color stroke;
  final Color divider;
  final Color surface;
  final Color chip;
  final Color handle;
  final Color accent;
  final Color warning;
  final Color text;
  final Color muted;
  final Color wechat;
  final Color qq;
  final Color rain;

  /// 独立设置窗口使用的不透明色。
  final Color windowBackground;
  final Color sidebarBackground;
  final Color cardBackground;
  final Color cardStroke;
  final Color navSelected;
  final Color switchOff;

  static const midnight = IslandColors(
    id: 'midnight',
    name: '午夜',
    brightness: Brightness.dark,
    background: Color(0xF0111319),
    stroke: Color(0x24FFFFFF),
    divider: Color(0x14FFFFFF),
    surface: Color(0x0AFFFFFF),
    chip: Color(0x22FFFFFF),
    handle: Color(0x59FFFFFF),
    accent: Color(0xFF2ED573),
    warning: Color(0xFFFFB020),
    text: Color(0xFFF2F4F8),
    muted: Color(0xFF8B93A7),
    wechat: Color(0xFF07C160),
    qq: Color(0xFF12B7F5),
    rain: Color(0xFF64B5F6),
    windowBackground: Color(0xFF161A21),
    sidebarBackground: Color(0xFF12151B),
    cardBackground: Color(0xFF1E232C),
    cardStroke: Color(0xFF2A303B),
    navSelected: Color(0xFF223028),
    switchOff: Color(0xFF3A4150),
  );

  static const daylight = IslandColors(
    id: 'daylight',
    name: '日光',
    brightness: Brightness.light,
    background: Color(0xF4F7F9FC),
    stroke: Color(0x1F1B2029),
    divider: Color(0x141B2029),
    surface: Color(0x0D1B2029),
    chip: Color(0x141B2029),
    handle: Color(0x591B2029),
    accent: Color(0xFF1D9A5B),
    warning: Color(0xFFB07200),
    text: Color(0xFF1B2029),
    muted: Color(0xFF6B7486),
    wechat: Color(0xFF07C160),
    qq: Color(0xFF12B7F5),
    rain: Color(0xFF2E7BD6),
    windowBackground: Color(0xFFFFFFFF),
    sidebarBackground: Color(0xFFF4F6F9),
    cardBackground: Color(0xFFFFFFFF),
    cardStroke: Color(0xFFE6E9EF),
    navSelected: Color(0xFFE8EEF8),
    switchOff: Color(0xFFD5DAE2),
  );

  static const values = [midnight, daylight];

  static IslandColors byId(String? id) =>
      id == daylight.id ? daylight : midnight;

  @override
  IslandColors copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    Color? background,
    Color? stroke,
    Color? divider,
    Color? surface,
    Color? chip,
    Color? handle,
    Color? accent,
    Color? warning,
    Color? text,
    Color? muted,
    Color? wechat,
    Color? qq,
    Color? rain,
    Color? windowBackground,
    Color? sidebarBackground,
    Color? cardBackground,
    Color? cardStroke,
    Color? navSelected,
    Color? switchOff,
  }) {
    return IslandColors(
      id: id ?? this.id,
      name: name ?? this.name,
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      stroke: stroke ?? this.stroke,
      divider: divider ?? this.divider,
      surface: surface ?? this.surface,
      chip: chip ?? this.chip,
      handle: handle ?? this.handle,
      accent: accent ?? this.accent,
      warning: warning ?? this.warning,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      wechat: wechat ?? this.wechat,
      qq: qq ?? this.qq,
      rain: rain ?? this.rain,
      windowBackground: windowBackground ?? this.windowBackground,
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      cardStroke: cardStroke ?? this.cardStroke,
      navSelected: navSelected ?? this.navSelected,
      switchOff: switchOff ?? this.switchOff,
    );
  }

  @override
  IslandColors lerp(ThemeExtension<IslandColors>? other, double t) {
    if (other is! IslandColors) return this;
    if (t >= 1) return other;
    if (t <= 0) return this;
    return IslandColors(
      id: t < 0.5 ? id : other.id,
      name: t < 0.5 ? name : other.name,
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      handle: Color.lerp(handle, other.handle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      wechat: Color.lerp(wechat, other.wechat, t)!,
      qq: Color.lerp(qq, other.qq, t)!,
      rain: Color.lerp(rain, other.rain, t)!,
      windowBackground: Color.lerp(
        windowBackground,
        other.windowBackground,
        t,
      )!,
      sidebarBackground: Color.lerp(
        sidebarBackground,
        other.sidebarBackground,
        t,
      )!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      cardStroke: Color.lerp(cardStroke, other.cardStroke, t)!,
      navSelected: Color.lerp(navSelected, other.navSelected, t)!,
      switchOff: Color.lerp(switchOff, other.switchOff, t)!,
    );
  }
}

extension IslandColorsContext on BuildContext {
  IslandColors get islandColors =>
      Theme.of(this).extension<IslandColors>() ?? IslandColors.midnight;
}
