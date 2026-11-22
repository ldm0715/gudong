import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 设置窗口与主窗口之间的邮箱代理通道。
/// 设置窗口没有 sidecar 连接，账号的增删查都经主窗口转发。
/// 只有“设置窗口 → 主窗口”一个方向，必须和 `gudong.settings` 一样用单向模式；
/// 双向模式要求两端都注册 handler，否则会报 CHANNEL_UNREGISTERED。
const WindowMethodChannel mailChannel = WindowMethodChannel(
  'gudong.mail',
  mode: ChannelMode.unidirectional,
);
