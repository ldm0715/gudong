import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:ffi/ffi.dart' as ffi_mem;
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import '../log.dart';

/// 逐像素命中：光标不在岛体形状内时给窗口加 WS_EX_TRANSPARENT，点击落到下层窗口。
///
/// 点击穿透必须同时带 WS_EX_LAYERED。只加 WS_EX_TRANSPARENT 时，点击仍会被
/// Flutter 的渲染子窗口接收。WS_EX_LAYERED 只加在宿主窗口上：加到渲染子窗口
/// 会让画面变黑。LAYERED 在启动时设置一次并保留，之后只切换 TRANSPARENT。
///
/// 轮询频率 16ms，只在命中状态变化时修改扩展样式。
class ClickThroughController {
  static const Size windowSize = Size(420, 300);
  static const Rect collapsedRect = Rect.fromLTWH(156, 8, 108, 36);
  static const Rect notificationRect = Rect.fromLTWH(30, 8, 360, 80);
  static const Rect expandedRect = Rect.fromLTWH(20, 8, 380, 260);
  static const int _wsExTransparent = 0x00000020;
  static const int _wsExLayered = 0x00080000;

  /// 光标是否在岛体可交互区域内，用于驱动悬停展开 / 收起。
  final ValueNotifier<bool> pointerInside = ValueNotifier(false);
  final ffi.Pointer<POINT> _cursor = ffi_mem.calloc<POINT>(ffi.sizeOf<POINT>());
  final ffi.Pointer<RECT> _client = ffi_mem.calloc<RECT>(ffi.sizeOf<RECT>());
  final ffi.Pointer<POINT> _origin = ffi_mem.calloc<POINT>(ffi.sizeOf<POINT>());

  HWND? _hwnd;
  Timer? _timer;
  Rect _interactive = collapsedRect;
  bool _transparent = false;
  bool _disposed = false;

  void setInteractiveRect(Rect rect) {
    _interactive = rect;
  }

  Future<void> start() async {
    if (!Platform.isWindows) return;
    try {
      for (var attempt = 0; attempt < 40 && !_disposed; attempt++) {
        final hwnd = _findWindow();
        if (hwnd != null) {
          _hwnd = hwnd;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final hwnd = _hwnd;
      if (hwnd == null) {
        AppLog.write('[click-through] window not found');
        return;
      }
      _ensureLayered(hwnd);
      AppLog.write('[click-through] attached');
      _timer = Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _tick(hwnd),
      );
    } catch (error, stack) {
      AppLog.write('[click-through] start failed: $error\n$stack');
    }
  }

  HWND? _findWindow() {
    final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toPcwstr();
    final windowName = 'guduo_island'.toPcwstr();
    try {
      final hwnd = FindWindow(className, windowName).value;
      return hwnd.address == 0 ? null : hwnd;
    } finally {
      ffi_mem.malloc.free(className);
      ffi_mem.malloc.free(windowName);
    }
  }

  void _tick(HWND hwnd) {
    if (_disposed) return;
    if (!IsWindowVisible(hwnd)) {
      _updatePointerInside(false);
      return;
    }
    if (!GetCursorPos(_cursor).value) return;
    if (!GetClientRect(hwnd, _client).value) return;
    // ClientToScreen 会原地累加坐标，每帧必须从 (0,0) 重新计算。
    _origin.ref.x = 0;
    _origin.ref.y = 0;
    if (!ClientToScreen(hwnd, _origin)) return;
    final width = (_client.ref.right - _client.ref.left).toDouble();
    if (width <= 0) return;
    final scale = width / windowSize.width;
    final local = Offset(
      (_cursor.ref.x - _origin.ref.x) / scale,
      (_cursor.ref.y - _origin.ref.y) / scale,
    );
    final inside = _interactive.contains(local);
    _setTransparent(hwnd, !inside);
    _updatePointerInside(inside);
  }

  void _ensureLayered(HWND hwnd) {
    final current = GetWindowLongPtr(hwnd, GWL_EXSTYLE).value;
    if ((current & _wsExLayered) == 0) {
      SetWindowLongPtr(hwnd, GWL_EXSTYLE, current | _wsExLayered);
    }
    // 分层窗口必须显式设置 alpha，否则 Flutter 子窗口内容不会显示。
    SetLayeredWindowAttributes(hwnd, const COLORREF(0), 255, LWA_ALPHA);
  }

  void _setTransparent(HWND hwnd, bool transparent) {
    if (_transparent == transparent) return;
    final current = GetWindowLongPtr(hwnd, GWL_EXSTYLE).value;
    final next = transparent
        ? current | _wsExTransparent
        : current & ~_wsExTransparent;
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, next);
    _transparent = transparent;
    AppLog.write('[click-through] transparent=$transparent');
  }

  void _updatePointerInside(bool inside) {
    if (pointerInside.value == inside) return;
    pointerInside.value = inside;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    ffi_mem.calloc.free(_cursor);
    ffi_mem.calloc.free(_client);
    ffi_mem.calloc.free(_origin);
    pointerInside.dispose();
  }
}
