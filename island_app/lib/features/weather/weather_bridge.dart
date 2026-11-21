import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 主窗口与设置窗口之间的天气代理通道。
/// 设置窗口没有 sidecar 连接，地点搜索经主窗口转发给 sidecar。
const WindowMethodChannel weatherChannel = WindowMethodChannel(
  'guduo.weather',
  mode: ChannelMode.bidirectional,
);
