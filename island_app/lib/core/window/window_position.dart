// Allocator.call 是 dart:ffi 里的扩展，导入后才能用 calloc<T>() 简写。
import 'dart:ffi' show AllocatorAlloc, StructPointer;

import 'package:ffi/ffi.dart' as ffi_mem;
import 'package:window_manager/window_manager.dart';
import 'package:win32/win32.dart';

import '../log.dart';
import '../settings/settings_controller.dart';
import 'island_window.dart';

/// 窗口位置持久化。
///
/// 坐标统一用物理像素：拖拽结束用 GetWindowRect 读，恢复用 SetWindowPos 写，
/// 多屏混合 DPI 下不会因为逻辑坐标换算而偏移。
class WindowPositionKeeper {
  WindowPositionKeeper(this.settings) {
    settings.addListener(_onSettingsChanged);
    _onSettingsChanged();
  }

  final SettingsController settings;
  bool _restored = false;
  bool _disposed = false;

  /// 从顶部拖拽把手调用。`startDragging` 在拖拽结束后才返回，之后保存位置。
  Future<void> startDrag() async {
    try {
      await windowManager.startDragging();
    } catch (error) {
      AppLog.write('[window] drag failed: $error');
      return;
    }
    await saveCurrent();
  }

  Future<void> saveCurrent() async {
    final hwnd = findIslandWindow();
    if (hwnd == null) return;
    final rect = ffi_mem.calloc<RECT>();
    try {
      if (!GetWindowRect(hwnd, rect).value) return;
      await settings.save(
        settings.settings.copyWith(
          windowX: rect.ref.left.toDouble(),
          windowY: rect.ref.top.toDouble(),
        ),
      );
    } finally {
      ffi_mem.calloc.free(rect);
    }
  }

  void _onSettingsChanged() {
    if (_disposed || _restored || !settings.loaded) return;
    _restored = true;
    final x = settings.settings.windowX;
    final y = settings.settings.windowY;
    if (x == null || y == null) return;
    _restore(x.round(), y.round());
  }

  void _restore(int x, int y) {
    final hwnd = findIslandWindow();
    if (hwnd == null) return;
    final point = _clamp(hwnd, x, y);
    final ok = SetWindowPos(
      hwnd,
      null,
      point.$1,
      point.$2,
      0,
      0,
      SET_WINDOW_POS_FLAGS(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE),
    ).value;
    AppLog.write('[window] restore ${point.$1},${point.$2} ok=$ok');
  }

  /// 夹到虚拟桌面范围内，避免拔掉副屏后窗口留在不可见区域。
  (int, int) _clamp(HWND hwnd, int x, int y) {
    final left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    final top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    final width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    final height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    var windowWidth = 420;
    var windowHeight = 300;
    final rect = ffi_mem.calloc<RECT>();
    try {
      if (GetWindowRect(hwnd, rect).value) {
        windowWidth = rect.ref.right - rect.ref.left;
        windowHeight = rect.ref.bottom - rect.ref.top;
      }
    } finally {
      ffi_mem.calloc.free(rect);
    }
    final maxX = left + width - windowWidth;
    final maxY = top + height - windowHeight;
    return (
      x.clamp(left, maxX > left ? maxX : left),
      y.clamp(top, maxY > top ? maxY : top),
    );
  }

  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettingsChanged);
  }
}
