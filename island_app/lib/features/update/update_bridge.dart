import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 设置窗口与主窗口之间的更新代理通道。
/// 设置窗口没有 sidecar 连接，检查、下载与安装都经主窗口转发。
const WindowMethodChannel updateChannel = WindowMethodChannel(
  'gudong.update',
  mode: ChannelMode.unidirectional,
);
