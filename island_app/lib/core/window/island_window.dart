import 'package:ffi/ffi.dart' as ffi_mem;
import 'package:win32/win32.dart';

/// Flutter runner 主窗口的类名与标题。
const String islandWindowClassName = 'FLUTTER_RUNNER_WIN32_WINDOW';
const String islandWindowTitle = 'gudong_island';

HWND? findIslandWindow() {
  final className = islandWindowClassName.toPcwstr();
  final windowName = islandWindowTitle.toPcwstr();
  try {
    final hwnd = FindWindow(className, windowName).value;
    return hwnd.address == 0 ? null : hwnd;
  } finally {
    ffi_mem.malloc.free(className);
    ffi_mem.malloc.free(windowName);
  }
}
