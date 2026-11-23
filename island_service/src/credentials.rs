//! Windows 凭据管理器：翻译服务的 API Key 只保存在这里，不写 config.json。
//!
//! 凭据按目标名区分，值以 UTF-16LE 存入 CredentialBlob。

pub const LLM: &str = "gudong/translate/llm";
pub const DEEPL: &str = "gudong/translate/deepl";
pub const CAIYUN: &str = "gudong/translate/caiyun";

pub const GLM_KEY: &str = "gudong/quota/glm";
pub const DEEPSEEK_KEY: &str = "gudong/quota/deepseek";
pub const OPENCODE_KEY: &str = "gudong/quota/opencode";
pub const OPENCODE_COOKIE: &str = "gudong/quota/opencode-cookie";
pub const KRILL_TOKEN: &str = "gudong/quota/krill";

/// New API 站点按站点 id 分开保存，避免多站点互相覆盖。
pub fn newapi_key(site_id: &str) -> String {
    format!("gudong/quota/newapi/{site_id}")
}

pub fn newapi_access_token(site_id: &str) -> String {
    format!("gudong/quota/newapi/{site_id}/access")
}

const USER_NAME: &str = "gudong";

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

/// 把旧目标名的凭据复制到新目标名。只复制，不删除旧凭据。
#[cfg(windows)]
pub fn migrate_legacy() -> Vec<String> {
    let mut notes = Vec::new();
    for target in [
        LLM,
        DEEPL,
        CAIYUN,
        GLM_KEY,
        DEEPSEEK_KEY,
        OPENCODE_KEY,
        OPENCODE_COOKIE,
        KRILL_TOKEN,
    ] {
        let old = target.replacen("gudong/", "guduo/", 1);
        if migrate_target(&old, target) {
            notes.push(format!("migrated credential {target}"));
        }
    }
    for id in mail_account_ids() {
        let target = format!("gudong/mail/{id}");
        let old = format!("guduo/mail/{id}");
        if migrate_target(&old, &target) {
            notes.push(format!("migrated credential {target}"));
        }
    }
    notes
}

#[cfg(windows)]
fn migrate_target(old: &str, new: &str) -> bool {
    if read(new).is_some() {
        return false;
    }
    match read(old) {
        Some(secret) => write(new, &secret).is_ok(),
        None => false,
    }
}

#[cfg(windows)]
fn mail_account_ids() -> Vec<String> {
    let Some(path) = crate::paths::app_data_dir().map(|dir| dir.join("mail.json")) else {
        return Vec::new();
    };
    let Ok(raw) = std::fs::read(path) else {
        return Vec::new();
    };
    let Ok(items) = serde_json::from_slice::<Vec<serde_json::Value>>(&raw) else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| item.get("id").and_then(|id| id.as_str()).map(str::to_string))
        .collect()
}

#[cfg(not(windows))]
pub fn migrate_legacy() -> Vec<String> {
    Vec::new()
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
