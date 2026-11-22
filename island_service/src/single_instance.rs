//! Windows 命名互斥量：同一登录会话只允许一个 sidecar。

#[cfg(windows)]
pub fn try_acquire() -> bool {
    use windows::core::w;
    use windows::Win32::Foundation::{CloseHandle, GetLastError, BOOL, ERROR_ALREADY_EXISTS};
    use windows::Win32::System::Threading::CreateMutexW;

    unsafe {
        let Ok(handle) = CreateMutexW(None, BOOL(1), w!("Local\\gudong-island-service")) else {
            return false;
        };
        if GetLastError() == ERROR_ALREADY_EXISTS {
            let _ = CloseHandle(handle);
            return false;
        }
        // 句柄保持打开，进程退出时由系统释放。
        true
    }
}

#[cfg(not(windows))]
pub fn try_acquire() -> bool {
    true
}
