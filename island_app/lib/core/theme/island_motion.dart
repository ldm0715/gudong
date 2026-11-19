import 'package:flutter/animation.dart';

/// 岛体动画时长与曲线。视觉动效只从这里取时长，控制器业务计时不受此约束。
abstract final class IslandMotion {
  /// 悬停与按下反馈。
  static const Duration hover = Duration(milliseconds: 100);

  /// 小控件状态切换。
  static const Duration fast = Duration(milliseconds: 160);

  /// 岛体尺寸与圆角切换。
  static const Duration base = Duration(milliseconds: 220);

  /// 进度与数值过渡。
  static const Duration progress = Duration(milliseconds: 340);

  /// 提示气泡出现前的等待。
  static const Duration tooltipDelay = Duration(milliseconds: 600);

  /// 拖拽把手出现前的停留。
  static const Duration handleDelay = Duration(milliseconds: 700);

  /// 音波一个完整周期。
  static const Duration wave = Duration(milliseconds: 900);

  /// 高亮脉冲持续时间。
  static const Duration pulse = Duration(milliseconds: 1400);

  /// 消息横幅停留时间。
  static const Duration bannerHold = Duration(seconds: 2);

  /// 复制完成等一次性反馈的保持时间。
  static const Duration feedbackHold = Duration(seconds: 1);

  /// 默认缓动曲线。
  static const Curve standard = Curves.easeOutCubic;
}
