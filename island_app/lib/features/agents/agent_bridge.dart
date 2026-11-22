import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 设置窗口读取 agent 实时状态时，经主窗口转发给 sidecar。
const WindowMethodChannel agentChannel = WindowMethodChannel(
  'guduo.agent',
  mode: ChannelMode.unidirectional,
);
