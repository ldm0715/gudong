//! Windows 凭据管理器：翻译服务的 API Key 只保存在这里，不写 config.json。
//!
//! 凭据按目标名区分，值以 UTF-16LE 存入 CredentialBlob。

pub const LLM: &str = "guduo/translate/llm";
pub const DEEPL: &str = "guduo/translate/deepl";
pub const CAIYUN: &str = "guduo/translate/caiyun";

pub const GLM_KEY: &str = "guduo/quota/glm";
pub const DEEPSEEK_KEY: &str = "guduo/quota/deepseek";
pub const OPENCODE_KEY: &str = "guduo/quota/opencode";
pub const OPENCODE_COOKIE: &str = "guduo/quota/opencode-cookie";

const USER_NAME: &str = "guduo";

#[cfg(windows)]
pub fn read(target: &str) -> Option<String> {
    use windows::core::PCWSTR;
    use windows::Win32::Security::Credentials::{
        CredFree, CredReadW, CREDENTIALW, CRED_TYPE_GENERIC,
    };

    let target_w: Vec<u16> = target.encode_utf16().chain(std::iter::once(0)).collect();
    let mut pointer: *mut CREDENTIALW = std::ptr::null_mut();
    unsafe {
        CredReadW(PCWSTR(target_w.as_ptr()), CRED_TYPE_GENERIC, 0, &mut pointer).ok()?;
        let credential = &*pointer;
        let size = credential.CredentialBlobSize as usize;
        let blob = std::slice::from_raw_parts(credential.CredentialBlob, size);
        let mut units = Vec::with_capacity(size / 2);
        for chunk in blob.chunks_exact(2) {
            units.push(u16::from_le_bytes([chunk[0], chunk[1]]));
        }
        CredFree(pointer as *const core::ffi::c_void);
        String::from_utf16(&units)
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    }
}

#[cfg(windows)]
pub fn write(target: &str, secret: &str) -> Result<(), String> {
    use windows::core::PWSTR;
    use windows::Win32::Security::Credentials::{
        CredWriteW, CREDENTIALW, CRED_PERSIST_LOCAL_MACHINE, CRED_TYPE_GENERIC,
    };

    let secret = secret.trim();
    if secret.is_empty() {
        return delete(target);
    }
    let mut target_w: Vec<u16> = target.encode_utf16().chain(std::iter::once(0)).collect();
    let mut user_w: Vec<u16> = USER_NAME
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let mut blob: Vec<u8> = secret
        .encode_utf16()
        .flat_map(|unit| unit.to_le_bytes())
        .collect();
    let credential = CREDENTIALW {
        Type: CRED_TYPE_GENERIC,
        TargetName: PWSTR(target_w.as_mut_ptr()),
        CredentialBlobSize: blob.len() as u32,
        CredentialBlob: blob.as_mut_ptr(),
        Persist: CRED_PERSIST_LOCAL_MACHINE,
        UserName: PWSTR(user_w.as_mut_ptr()),
        ..Default::default()
    };
    unsafe { CredWriteW(&credential, 0) }.map_err(|error| error.message())
}

#[cfg(windows)]
pub fn delete(target: &str) -> Result<(), String> {
    use windows::core::PCWSTR;
    use windows::Win32::Security::Credentials::{CredDeleteW, CRED_TYPE_GENERIC};

    // 不存在的凭据直接当作删除成功，避免首次清空时报错。
    if read(target).is_none() {
        return Ok(());
    }
    let target_w: Vec<u16> = target.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe { CredDeleteW(PCWSTR(target_w.as_ptr()), CRED_TYPE_GENERIC, 0) }
        .map_err(|error| error.message())
}

#[cfg(not(windows))]
pub fn read(_target: &str) -> Option<String> {
    None
}

#[cfg(not(windows))]
pub fn write(_target: &str, _secret: &str) -> Result<(), String> {
    Err("凭据管理器仅支持 Windows".into())
}

#[cfg(not(windows))]
pub fn delete(_target: &str) -> Result<(), String> {
    Ok(())
}
