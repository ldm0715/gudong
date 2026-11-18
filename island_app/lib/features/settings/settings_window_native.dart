import 'dart:ffi';

import 'package:ffi/ffi.dart' as ffi_mem;
import 'package:win32/win32.dart';

import '../../core/log.dart';

/// 设置窗口是独立 Flutter 引擎，window_manager 没有注册到该引擎，
/// 标题、尺寸、居中和前台都直接用 Win32 处理。
abstract final class SettingsNativeWindow {
  static const _className = 'FLUTTER_MULTI_WINDOW_WIN32_WINDOW';

  static HWND? find() {
    final className = _className.toPcwstr();
    try {
      final hwnd = FindWindow(className, null).value;
      return hwnd.address == 0 ? null : hwnd;
    } finally {
      ffi_mem.malloc.free(className);
    }
  }

  /// 设置标题和初始尺寸，居中显示在所在显示器，但先不 show。
  static void prepare({
    required String title,
    double width = 880,
    double height = 640,
  }) {
    final hwnd = find();
    if (hwnd == null) {
      AppLog.write('[settings-window] native window not found');
      return;
    }
    final titlePtr = title.toPcwstr();
    try {
      SetWindowText(hwnd, titlePtr);
    } finally {
      ffi_mem.malloc.free(titlePtr);
    }

    final dpi = GetDpiForWindow(hwnd);
    final scale = dpi <= 0 ? 1.0 : dpi / 96.0;
    final w = (width * scale).round();
    final h = (height * scale).round();
    var x = 0;
    var y = 0;
    final monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    final info = ffi_mem.calloc<MONITORINFO>();
    try {
      info.ref.cbSize = sizeOf<MONITORINFO>();
      if (GetMonitorInfo(monitor, info)) {
        final work = info.ref.rcWork;
        x = work.left + ((work.right - work.left) - w) ~/ 2;
        y = work.top + ((work.bottom - work.top) - h) ~/ 2;
      }
    } finally {
      ffi_mem.calloc.free(info);
    }
    SetWindowPos(
      hwnd,
      null,
      x,
      y,
      w,
      h,
      SET_WINDOW_POS_FLAGS(SWP_NOZORDER | SWP_NOACTIVATE),
    );
  }

  static void show() {
    final hwnd = find();
    if (hwnd == null) return;
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);
  }

  static void focus() {
    final hwnd = find();
    if (hwnd == null) return;
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);
  }

  static void close() {
    final hwnd = find();
    if (hwnd == null) return;
    DestroyWindow(hwnd);
  }
}
