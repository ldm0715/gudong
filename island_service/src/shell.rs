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

/// 开机自启写入 HKCU 的 Run 键，不需要管理员权限，也不会影响其他用户。
#[cfg(windows)]
const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
#[cfg(windows)]
const RUN_VALUE: &str = "Guduo";

/// 启动项指向与 sidecar 同目录的 `island_app.exe`。
#[cfg(windows)]
fn launch_target() -> std::path::PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("island_app.exe")))
        .unwrap_or_else(|| std::path::PathBuf::from("island_app.exe"))
}

/// 读取 Run 键中是否存在本应用的启动项。
#[cfg(windows)]
pub fn launch_at_login_enabled() -> bool {
    use windows::core::HSTRING;
    use windows::Win32::System::Registry::{
        RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_SZ,
    };

    let subkey = HSTRING::from(RUN_KEY);
    let value = HSTRING::from(RUN_VALUE);
    let mut size = 0u32;
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            &subkey,
            &value,
            RRF_RT_REG_SZ,
            None,
            None,
            Some(&mut size),
        )
    };
    if status.is_err() || size == 0 {
        return false;
    }
    let mut buffer = vec![0u16; (size as usize / 2).max(1)];
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            &subkey,
            &value,
            RRF_RT_REG_SZ,
            None,
            Some(buffer.as_mut_ptr().cast()),
            Some(&mut size),
        )
    };
    if status.is_err() {
        return false;
    }
    buffer.iter().any(|unit| *unit != 0)
}

/// 写入或删除启动项；删除不存在的值视为成功。
#[cfg(windows)]
pub fn set_launch_at_login(enabled: bool) -> Result<(), String> {
    use windows::core::HSTRING;
    use windows::Win32::Foundation::ERROR_FILE_NOT_FOUND;
    use windows::Win32::System::Registry::{
        RegCloseKey, RegCreateKeyExW, RegDeleteValueW, RegSetValueExW, HKEY,
        HKEY_CURRENT_USER, KEY_SET_VALUE, REG_OPTION_NON_VOLATILE, REG_SZ,
    };

    let subkey = HSTRING::from(RUN_KEY);
    let mut key = HKEY::default();
    let status = unsafe {
        RegCreateKeyExW(
            HKEY_CURRENT_USER,
            &subkey,
            0,
            None,
            REG_OPTION_NON_VOLATILE,
            KEY_SET_VALUE,
            None,
            &mut key,
            None,
        )
    };
    if status.is_err() {
        return Err(format!("无法打开启动项注册表（{}）", status.0));
    }

    let value = HSTRING::from(RUN_VALUE);
    let result = if enabled {
        let target = launch_target();
        let path = format!("\"{}\"", target.display());
        let data: Vec<u8> = path
            .encode_utf16()
            .chain(std::iter::once(0))
            .flat_map(u16::to_le_bytes)
            .collect();
        let status = unsafe { RegSetValueExW(key, &value, 0, REG_SZ, Some(&data)) };
        if status.is_err() {
            Err(format!("无法写入启动项（{}）", status.0))
        } else {
            Ok(())
        }
    } else {
        let status = unsafe { RegDeleteValueW(key, &value) };
        if status.is_err() && status != ERROR_FILE_NOT_FOUND {
            Err(format!("无法删除启动项（{}）", status.0))
        } else {
            Ok(())
        }
    };
    let _ = unsafe { RegCloseKey(key) };
    result
}

#[cfg(not(windows))]
pub fn launch_at_login_enabled() -> bool {
    false
}

#[cfg(not(windows))]
pub fn set_launch_at_login(_enabled: bool) -> Result<(), String> {
    Err("仅支持 Windows".into())
}
