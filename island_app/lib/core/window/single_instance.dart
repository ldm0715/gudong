import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi_mem;
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import '../log.dart';
import 'island_window.dart';

/// Windows 命名互斥量单实例。句柄保持到进程退出，由系统释放。
abstract final class SingleInstance {
  static ffi.Pointer<ffi.Void>? _mutex;

  /// 返回 false 表示同一会话里已有实例在运行。
  static bool acquire(String name) {
    if (!Platform.isWindows) return true;
    if (_mutex != null) return true;
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    final createMutex = kernel32
        .lookupFunction<
          ffi.IntPtr Function(
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
            ffi.Pointer<ffi_mem.Utf16>,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi_mem.Utf16>)
        >('CreateMutexW');
    final getLastError = kernel32
        .lookupFunction<ffi.Uint32 Function(), int Function()>('GetLastError');

    final namePtr = name.toPcwstr();
    try {
      final handle = createMutex(ffi.nullptr, 1, namePtr);
      // 必须紧跟 CreateMutexW 读取，中间不能再调其他 Win32 API。
      final error = getLastError();
      if (handle == 0) {
        AppLog.write('[single-instance] CreateMutexW failed: $error');
        return false;
      }
      if (error == ERROR_ALREADY_EXISTS) return false;
      _mutex = ffi.Pointer.fromAddress(handle);
      return true;
    } finally {
      ffi_mem.malloc.free(namePtr);
    }
  }

  /// 已有实例时把岛体窗口叫到前台，返回 true。
  ///
  /// 窗口属于本进程说明是开发热重启，返回 false 让新 main 继续启动。
  static bool focusExisting() {
    if (!Platform.isWindows) return false;
    final pid = ffi_mem.calloc<ffi.Uint32>();
    try {
      final hwnd = findIslandWindow();
      if (hwnd == null) {
        // Debug 下可能是热重启时窗口尚未创建；Release 按已有实例处理。
        return !kDebugMode;
      }
      GetWindowThreadProcessId(hwnd, pid);
      if (pid.value == GetCurrentProcessId()) return false;
      ShowWindow(hwnd, SW_SHOW);
      SetForegroundWindow(hwnd);
      return true;
    } finally {
      ffi_mem.calloc.free(pid);
    }
  }
}
