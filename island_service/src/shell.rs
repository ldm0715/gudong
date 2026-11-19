//! 系统外壳动作。打开外链属于系统控制，放在 sidecar，Flutter 只发请求。

#[cfg(windows)]
pub fn open_url(url: &str) -> Result<(), String> {
    use windows::core::{HSTRING, PCWSTR};
    use windows::Win32::Foundation::HWND;
    use windows::Win32::UI::Shell::ShellExecuteW;
    use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

    let operation = HSTRING::from("open");
    let file = HSTRING::from(url);
    let result = unsafe {
        ShellExecuteW(
            HWND::default(),
            &operation,
            &file,
            PCWSTR::null(),
            PCWSTR::null(),
            SW_SHOWNORMAL,
        )
    };
    // ShellExecuteW 返回值 <= 32 表示失败。
    let code = result.0 as isize;
    if code <= 32 {
        return Err(format!("无法打开链接（ShellExecute 返回 {code}）"));
    }
    Ok(())
}

#[cfg(not(windows))]
pub fn open_url(_url: &str) -> Result<(), String> {
    Err("仅支持 Windows".into())
}
