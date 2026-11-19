import 'package:flutter/painting.dart';

/// 岛体字阶。字号、字重、字距只在这里定义，颜色由调用处从 `IslandColors` 套用。
abstract final class IslandTypography {
  /// 宽字距，用于时间等需要稳定节奏的文本。
  static const double trackingWide = 0.4;

  /// 紧字距，用于大号数字。
  static const double trackingTight = -0.2;

  /// 等宽数字，用于时间、进度与百分比。
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  /// 10px 辅助文字，如天气说明、消息摘要。
  static const TextStyle micro = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    decoration: TextDecoration.none,
  );

  /// 10px 强调辅助文字，如状态点旁文字。
  static const TextStyle microStrong = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.none,
  );

  /// 11px 说明文字。
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    decoration: TextDecoration.none,
  );

  /// 11px 强调说明，用于角标与选中态。
  static const TextStyle captionStrong = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  /// 12px 正文。
  static const TextStyle body = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    decoration: TextDecoration.none,
  );

  /// 12px 强调正文。
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.none,
  );

  /// 13px 关键信息，如空态标题。
  static const TextStyle subhead = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.none,
  );

  /// 14px 标题，如岛体名称。
  static const TextStyle title = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  /// 15px 大标题，如横幅标题。
  static const TextStyle headline = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  /// 22px 展示数字。
  static const TextStyle display = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: trackingTight,
    decoration: TextDecoration.none,
  );

  /// 26px 主展示，如天气大温度。
  static const TextStyle displayLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1,
    letterSpacing: trackingTight,
    decoration: TextDecoration.none,
  );

  /// 收起态横向时间，等宽数字与宽字距。
  static const TextStyle clock = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: trackingWide,
    fontFeatures: tabularFigures,
    decoration: TextDecoration.none,
  );

  /// 窄栏竖排时钟，等宽数字并收紧行高。
  static const TextStyle clockCompact = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.05,
    letterSpacing: trackingWide,
    fontFeatures: tabularFigures,
    decoration: TextDecoration.none,
  );
}

/// 给字阶套用颜色，避免在调用处重复书写样式字段。
extension IslandTextStyleTint on TextStyle {
  TextStyle tint(Color color) => copyWith(color: color);
}
