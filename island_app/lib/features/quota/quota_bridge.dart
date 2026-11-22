import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 设置窗口与主窗口之间的额度代理通道。
/// 设置窗口没有 sidecar 连接，保存凭据与手动刷新都经主窗口转发。
const WindowMethodChannel quotaChannel = WindowMethodChannel(
  'gudong.quota',
  mode: ChannelMode.unidirectional,
);
