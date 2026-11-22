//! 邮件账号清单：`%APPDATA%\gudong\mail.json`。
//!
//! 只存邮箱、类型和连接参数，任何密码、授权码和 refresh token 都不落这里。
//! 凭据统一放在 Windows 凭据管理器，目标名 `gudong/mail/<id>`。

use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Provider {
    #[serde(rename = "qq")]
    Qq,
    #[serde(rename = "163")]
    Mail163,
    #[serde(rename = "126")]
    Mail126,
    #[serde(rename = "exmail")]
    Exmail,
    #[serde(rename = "icloud")]
    ICloud,
    #[serde(rename = "gmail")]
    Gmail,
    #[serde(rename = "microsoft")]
    Microsoft,
    #[serde(rename = "custom")]
    Custom,
}

impl Provider {
    pub fn parse(key: &str) -> Option<Self> {
        Some(match key.trim().to_ascii_lowercase().as_str() {
            "qq" => Self::Qq,
            "163" => Self::Mail163,
            "126" => Self::Mail126,
            "exmail" => Self::Exmail,
            "icloud" => Self::ICloud,
            "gmail" => Self::Gmail,
            "microsoft" => Self::Microsoft,
            "custom" => Self::Custom,
            _ => return None,
        })
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Qq => "qq",
            Self::Mail163 => "163",
            Self::Mail126 => "126",
            Self::Exmail => "exmail",
            Self::ICloud => "icloud",
            Self::Gmail => "gmail",
            Self::Microsoft => "microsoft",
            Self::Custom => "custom",
        }
    }

    pub fn host(self) -> &'static str {
        match self {
            Self::Qq => "imap.qq.com",
            Self::Mail163 => "imap.163.com",
            Self::Mail126 => "imap.126.com",
            Self::Exmail => "imap.exmail.qq.com",
            Self::ICloud => "imap.mail.me.com",
            Self::Gmail => "imap.gmail.com",
            Self::Microsoft => "outlook.office365.com",
            Self::Custom => "",
        }
    }

    pub fn webmail(self) -> &'static str {
        match self {
            Self::Qq => "https://mail.qq.com/",
            Self::Mail163 => "https://mail.163.com/",
            Self::Mail126 => "https://mail.126.com/",
            Self::Exmail => "https://exmail.qq.com/",
            Self::ICloud => "https://www.icloud.com/mail/",
            Self::Gmail => "https://mail.google.com/",
            Self::Microsoft => "https://outlook.live.com/mail/",
            Self::Custom => "",
        }
    }

    /// 163 / 126 在 LOGIN 之前必须发 RFC 2971 的 `ID`，否则会被判 Unsafe Login。
    pub fn needs_id(self) -> bool {
        matches!(self, Self::Mail163 | Self::Mail126)
    }

    pub fn needs_oauth(self) -> bool {
        matches!(self, Self::Microsoft)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum AuthType {
    #[serde(rename = "password")]
    Password,
    #[serde(rename = "oauth2")]
    Oauth2,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CustomImap {
    pub host: String,
    pub port: u16,
    pub username: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Account {
    pub id: String,
    pub provider: Provider,
    pub email: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    pub auth_type: AuthType,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom: Option<CustomImap>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub webmail_url: Option<String>,
}

fn default_enabled() -> bool {
    true
}

impl Account {
    pub fn endpoint(&self) -> Result<(String, u16, String), String> {
        if self.provider == Provider::Custom {
            let custom = self
                .custom
                .as_ref()
                .ok_or_else(|| "请填写自定义 IMAP 连接配置".to_string())?;
            let host = custom.host.trim().to_ascii_lowercase();
            if host.is_empty()
                || host.len() > 253
                || host.contains('/')
                || host.contains(':')
                || host.contains(char::is_whitespace)
            {
                return Err("IMAP 主机必须是域名或 IPv4 地址".into());
            }
            if custom.port == 0 || custom.port == 143 {
                return Err("仅支持 IMAP over TLS，不支持 143 或明文连接".into());
            }
            let username = if custom.username.trim().is_empty() {
                self.email.trim().to_string()
            } else {
                custom.username.trim().to_string()
            };
            Ok((host, custom.port, username))
        } else {
            Ok((self.provider.host().to_string(), 993, self.email.clone()))
        }
    }

    pub fn webmail(&self) -> &str {
        self.webmail_url
            .as_deref()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| self.provider.webmail())
    }
}

/// 同一 provider、邮箱和自定义端点视为同一个账号，重复添加时覆盖凭据。
pub fn identity(account: &Account) -> String {
    let custom = account
        .custom
        .as_ref()
        .map(|value| {
            format!(
                "{}:{}:{}",
                value.host.trim().to_ascii_lowercase(),
                value.port,
                value.username.trim().to_ascii_lowercase()
            )
        })
        .unwrap_or_default();
    format!(
        "{}|{}|{}",
        account.provider.key(),
        account.email.trim().to_ascii_lowercase(),
        custom
    )
}

pub fn new_id(provider: Provider, email: &str, taken: &[String]) -> String {
    for salt in 0u32.. {
        let mut hasher = DefaultHasher::new();
        provider.key().hash(&mut hasher);
        email.trim().to_ascii_lowercase().hash(&mut hasher);
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|value| value.as_nanos())
            .unwrap_or(0);
        now.hash(&mut hasher);
        std::process::id().hash(&mut hasher);
        salt.hash(&mut hasher);
        let id = format!("m_{:016x}", hasher.finish());
        if !taken.iter().any(|value| value == &id) {
            return id;
        }
    }
    unreachable!()
}

pub fn credential_target(id: &str) -> String {
    format!("gudong/mail/{id}")
}

pub struct Store {
    path: Option<PathBuf>,
    accounts: Vec<Account>,
}

impl Store {
    pub fn load() -> Self {
        let Some(path) = default_path() else {
            return Self {
                path: None,
                accounts: Vec::new(),
            };
        };
        let accounts = std::fs::read(&path)
            .ok()
            .and_then(|raw| serde_json::from_slice::<Vec<Account>>(&raw).ok())
            .unwrap_or_default();
        Self {
            path: Some(path),
            accounts,
        }
    }

    #[cfg(test)]
    pub fn memory(accounts: Vec<Account>) -> Self {
        Self {
            path: None,
            accounts,
        }
    }

    pub fn accounts(&self) -> &[Account] {
        &self.accounts
    }

    pub fn upsert(&mut self, account: Account) -> Result<(), String> {
        let previous = self.accounts.clone();
        let key = identity(&account);
        if let Some(existing) = self
            .accounts
            .iter_mut()
            .find(|existing| identity(existing) == key)
        {
            // 修改授权码或标签时保持原 id，避免凭据目标名和邮件 id 变化。
            let id = existing.id.clone();
            let mut next = account;
            next.id = id;
            *existing = next;
        } else {
            self.accounts.push(account);
        }
        if let Err(error) = self.save() {
            self.accounts = previous;
            return Err(error);
        }
        Ok(())
    }

    pub fn update_label(
        &mut self,
        id: &str,
        label: Option<String>,
    ) -> Result<Account, String> {
        let previous = self.accounts.clone();
        let updated = {
            let Some(account) = self.accounts.iter_mut().find(|account| account.id == id)
            else {
                return Err("account not found".into());
            };
            account.label = label;
            account.clone()
        };
        if let Err(error) = self.save() {
            self.accounts = previous;
            return Err(error);
        }
        Ok(updated)
    }

    pub fn remove(&mut self, id: &str) -> Result<Account, String> {
        let index = self
            .accounts
            .iter()
            .position(|account| account.id == id)
            .ok_or_else(|| "account not found".to_string())?;
        let removed = self.accounts.remove(index);
        if let Err(error) = self.save() {
            self.accounts.insert(index, removed);
            return Err(error);
        }
        Ok(removed)
    }

    fn save(&self) -> Result<(), String> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        let raw = serde_json::to_vec_pretty(&self.accounts).map_err(|error| error.to_string())?;
        write_atomic(path, &raw)
    }
}

fn default_path() -> Option<PathBuf> {
    crate::paths::app_data_dir().map(|dir| dir.join("mail.json"))
}

fn write_atomic(path: &Path, raw: &[u8]) -> Result<(), String> {
    let Some(dir) = path.parent() else {
        return Err("invalid mail path".into());
    };
    std::fs::create_dir_all(dir).map_err(|error| error.to_string())?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, raw).map_err(|error| error.to_string())?;
    std::fs::rename(&tmp, path).map_err(|error| {
        let _ = std::fs::remove_file(&tmp);
        error.to_string()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn account(id: &str, email: &str) -> Account {
        Account {
            id: id.into(),
            provider: Provider::Qq,
            email: email.into(),
            label: None,
            auth_type: AuthType::Password,
            enabled: true,
            custom: None,
            webmail_url: None,
        }
    }

    #[test]
    fn same_identity_replaces_instead_of_appending() {
        let mut store = Store::memory(vec![account("m_1", "a@example.com")]);
        store.upsert(account("m_2", "A@example.com")).unwrap();
        assert_eq!(store.accounts().len(), 1);
        assert_eq!(store.accounts()[0].id, "m_1");
    }

    #[test]
    fn custom_endpoint_is_part_of_identity() {
        let mut first = account("m_1", "a@example.com");
        first.provider = Provider::Custom;
        first.custom = Some(CustomImap {
            host: "imap.example.com".into(),
            port: 993,
            username: "a".into(),
        });
        let mut second = first.clone();
        second.id = "m_2".into();
        second.custom.as_mut().unwrap().host = "other.example.com".into();
        let mut store = Store::memory(vec![first]);
        store.upsert(second).unwrap();
        assert_eq!(store.accounts().len(), 2);
    }

    #[test]
    fn mail_json_has_no_credential_fields() {
        let raw = serde_json::to_vec(&account("m_1", "a@example.com")).unwrap();
        let value: serde_json::Value = serde_json::from_slice(&raw).unwrap();
        assert!(value.get("password").is_none());
        assert!(value.get("token").is_none());
    }

    #[test]
    fn custom_endpoint_rejects_starttls_port_and_url() {
        let mut account = account("m_1", "a@example.com");
        account.provider = Provider::Custom;
        account.custom = Some(CustomImap {
            host: "imap.example.com".into(),
            port: 143,
            username: String::new(),
        });
        assert!(account.endpoint().is_err());
        account.custom.as_mut().unwrap().port = 993;
        account.custom.as_mut().unwrap().host = "https://imap.example.com".into();
        assert!(account.endpoint().is_err());
    }

    #[test]
    fn generated_ids_do_not_collide_with_existing() {
        let id = new_id(Provider::Gmail, "a@example.com", &[]);
        assert!(id.starts_with("m_"));
        let other = new_id(Provider::Gmail, "a@example.com", std::slice::from_ref(&id));
        assert_ne!(id, other);
    }
}
