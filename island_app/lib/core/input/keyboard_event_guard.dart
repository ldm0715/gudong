import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// 过滤 Windows 注入按键产生的伪事件。
///
/// Win+V 剪贴板历史、触摸板手势和部分输入法会发送不带扫描码的按键。
/// Flutter Windows 会把这类事件映射成物理键 `windowsPlane + 0`，不同按键
/// 撞到同一个物理键后，HardwareKeyboard 在 debug 下断言失败；异常又会跳过
/// 事件队列清空，之后每次按键都抛错，所有快捷键（含 Ctrl+V）一起失效。
/// 真实键盘的扫描码不会为 0，这类事件直接丢弃即可。
abstract final class KeyboardEventGuard {
  /// 引擎把无扫描码事件落到 windowsPlane 平面的 0 号物理键上。
  static const int _syntheticPhysicalKey = 0x01600000000;

  static Future<void> install() async {
    final binding = ServicesBinding.instance;
    final dispatcher = ui.PlatformDispatcher.instance;
    // 绑定在 syncKeyboardState 完成后才把按键处理器挂到 dispatcher 上。
    try {
      await binding.keyboard.syncKeyboardState();
    } catch (_) {}
    final previous = dispatcher.onKeyData;
    if (previous != null) {
      dispatcher.onKeyData = (data) {
        if (data.physical == _syntheticPhysicalKey) return true;
        return previous(data);
      };
    }
    // ignore: deprecated_member_use
    final manager = binding.keyEventManager;
    SystemChannels.keyEvent.setMessageHandler((message) async {
      if (message is Map && _hasNoScanCode(message['scanCode'])) {
        return <String, dynamic>{'handled': true};
      }
      // ignore: deprecated_member_use
      return manager.handleRawKeyMessage(message);
    });
  }

  /// 扫描码 0 表示不是真实按下的物理键；带扩展位时低字节同样为 0。
  static bool _hasNoScanCode(Object? value) =>
      value is int && (value & 0xff) == 0;
}
