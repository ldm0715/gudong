import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 主窗口与设置窗口之间的翻译代理通道。
/// 设置窗口没有 sidecar 连接，getModels / test / setSecret 都经主窗口转发。
const WindowMethodChannel translateChannel = WindowMethodChannel(
  'guduo.translate',
  mode: ChannelMode.bidirectional,
);
