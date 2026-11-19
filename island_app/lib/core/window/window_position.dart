// Allocator.call 是 dart:ffi 里的扩展，导入后才能用 calloc<T>() 简写。
import 'dart:ffi' show AllocatorAlloc, StructPointer, sizeOf;

import 'package:ffi/ffi.dart' as ffi_mem;
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:win32/win32.dart';

import '../log.dart';
import '../settings/settings_controller.dart';
import 'dock_edge.dart';
import 'island_window.dart';

/// 物理像素矩形，left/top 包含在内。
typedef _Bounds = ({int left, int top, int right, int bottom});

/// 窗口停靠与位置持久化。
///
/// 岛体只能停在屏幕边缘：拖拽结束后按窗口离哪条边最近吸附到顶部、左侧或右侧。
/// 坐标统一用物理像素：拖拽结束用 GetWindowRect 读，停靠用 SetWindowPos 写，
/// 多屏混合 DPI 下不会因为逻辑坐标换算而偏移。
class WindowPositionKeeper extends ChangeNotifier {
  WindowPositionKeeper(this.settings) {
    settings.addListener(_onSettingsChanged);
    _onSettingsChanged();
  }

  final SettingsController settings;
  DockEdge _side = DockEdge.top;
  bool _restored = false;
  bool _disposed = false;

  /// 当前停靠边缘。左右两侧时界面切换为竖屏布局。
  DockEdge get side => _side;

  /// 从拖拽把手调用。`startDragging` 在拖拽结束后才返回，之后吸附并保存。
  Future<void> startDrag() async {
    try {
      await windowManager.startDragging();
    } catch (error) {
      AppLog.write('[window] drag failed: $error');
      return;
    }
    await _snapToEdge();
  }

  /// 吸附到离窗口中心最近的边缘，沿边位置保持不变。
  Future<void> _snapToEdge() async {
    final hwnd = findIslandWindow();
    if (hwnd == null) return;
    final bounds = _windowBounds(hwnd);
    if (bounds == null) return;
    final work = _workArea(hwnd);
    final side = _nearestSide(bounds, work);
    final offset = side.isVertical
        ? (bounds.top + bounds.bottom) ~/ 2
        : (bounds.left + bounds.right) ~/ 2;
    final changed = side != _side;
    _side = side;
    _moveTo(hwnd, side, offset, work);
    if (changed) notifyListeners();
    // 设置还没加载完成时保存会用默认值覆盖磁盘配置。
    if (!settings.loaded) return;
    await settings.save(
      settings.settings.copyWith(
        dockSide: side.id,
        dockOffset: offset.toDouble(),
      ),
    );
  }

  void _onSettingsChanged() {
    if (_disposed || _restored || !settings.loaded) return;
    final hwnd = findIslandWindow();
    if (hwnd == null) {
      // 窗口还没创建好时不消耗这次恢复机会，等下一次通知。
      AppLog.write('[window] restore skipped: window not found');
      return;
    }
    _restored = true;
    final side = DockEdge.parse(settings.settings.dockSide);
    _side = side;
    final work = _workArea(hwnd);
    final centered = side.isVertical
        ? (work.top + work.bottom) ~/ 2
        : (work.left + work.right) ~/ 2;
    final offset = settings.settings.dockOffset?.round() ?? centered;
    AppLog.write(
      '[window] restore side=${side.id} offset=$offset '
      'saved=${settings.settings.dockOffset}',
    );
    _moveTo(hwnd, side, offset, work);
    notifyListeners();
  }

  /// 把窗口移到指定边缘，`offset` 是岛体中心沿边的物理坐标。
  void _moveTo(HWND hwnd, DockEdge side, int offset, _Bounds work) {
    final bounds = _windowBounds(hwnd);
    if (bounds == null) return;
    final width = bounds.right - bounds.left;
    final height = bounds.bottom - bounds.top;
    final maxX = work.right - width;
    final maxY = work.bottom - height;
    var x = work.left;
    var y = work.top;
    if (side == DockEdge.top) {
      x = _clamp(
        offset - width ~/ 2,
        work.left,
        maxX > work.left ? maxX : work.left,
      );
    } else {
      y = _clamp(
        offset - height ~/ 2,
        work.top,
        maxY > work.top ? maxY : work.top,
      );
      if (side == DockEdge.right) {
        x = maxX > work.left ? maxX : work.left;
      }
    }
    final ok = SetWindowPos(
      hwnd,
      null,
      x,
      y,
      0,
      0,
      SET_WINDOW_POS_FLAGS(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE),
    ).value;
    AppLog.write('[window] dock ${side.id} at $x,$y ok=$ok');
  }

  DockEdge _nearestSide(_Bounds bounds, _Bounds work) {
    final centerX = (bounds.left + bounds.right) ~/ 2;
    final centerY = (bounds.top + bounds.bottom) ~/ 2;
    final top = (centerY - work.top).abs();
    final left = (centerX - work.left).abs();
    final right = (work.right - centerX).abs();
    if (top <= left && top <= right) return DockEdge.top;
    return left <= right ? DockEdge.left : DockEdge.right;
  }

  /// 取窗口所在显示器的工作区；失败时退回整个虚拟桌面。
  _Bounds _workArea(HWND hwnd) {
    final info = ffi_mem.calloc<MONITORINFO>();
    try {
      info.ref.cbSize = sizeOf<MONITORINFO>();
      final monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      if (GetMonitorInfo(monitor, info)) {
        final work = info.ref.rcWork;
        return (
          left: work.left,
          top: work.top,
          right: work.right,
          bottom: work.bottom,
        );
      }
    } finally {
      ffi_mem.calloc.free(info);
    }
    final left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    final top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    return (
      left: left,
      top: top,
      right: left + GetSystemMetrics(SM_CXVIRTUALSCREEN),
      bottom: top + GetSystemMetrics(SM_CYVIRTUALSCREEN),
    );
  }

  _Bounds? _windowBounds(HWND hwnd) {
    final rect = ffi_mem.calloc<RECT>();
    try {
      if (!GetWindowRect(hwnd, rect).value) return null;
      return (
        left: rect.ref.left,
        top: rect.ref.top,
        right: rect.ref.right,
        bottom: rect.ref.bottom,
      );
    } finally {
      ffi_mem.calloc.free(rect);
    }
  }

  static int _clamp(int value, int min, int max) =>
      value < min ? min : (value > max ? max : value);

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
