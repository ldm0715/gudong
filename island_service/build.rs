//! 给侧车嵌入应用图标和版本信息。
//!
//! Windows 的托盘气泡通知会用 exe 的图标和 `FileDescription` 作为通知的
//! 应用图标与名称；没有资源时会退化成 `island_service.exe` + 系统信息图标。

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const RESOURCE: &str = r#"1 ICON "gudong.ico"

1 VERSIONINFO
FILEVERSION 0,0,0,0
PRODUCTVERSION 0,0,0,0
FILEFLAGSMASK 0x3fL
FILEFLAGS 0x0L
FILEOS 0x40004L
FILETYPE 0x1L
FILESUBTYPE 0x0L
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904b0"
    BEGIN
      VALUE "CompanyName", "gudong"
      VALUE "FileDescription", "gudong"
      VALUE "FileVersion", "0.0.0.0"
      VALUE "InternalName", "island_service"
      VALUE "OriginalFilename", "island_service.exe"
      VALUE "ProductName", "gudong"
      VALUE "ProductVersion", "0.0.0.0"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
"#;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }

    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let icon = manifest.join("../island_app/assets/tray_icon.ico");
    println!("cargo:rerun-if-changed={}", icon.display());
    let out = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));

    if !icon.is_file() {
        println!("cargo:warning=找不到通知图标: {}", icon.display());
        return;
    }
    let Some(rc) = find_rc() else {
        println!("cargo:warning=未找到 rc.exe，侧车通知将使用默认图标");
        return;
    };
    if let Err(error) = fs::copy(&icon, out.join("gudong.ico")) {
        println!("cargo:warning=复制通知图标失败: {error}");
        return;
    }

    let rc_file = out.join("gudong.rc");
    let res_file = out.join("gudong.res");
    if let Err(error) = fs::write(&rc_file, RESOURCE) {
        println!("cargo:warning=写入资源脚本失败: {error}");
        return;
    }

    let status = Command::new(&rc)
        .current_dir(&out)
        .arg("/nologo")
        .arg("/fo")
        .arg(&res_file)
        .arg(&rc_file)
        .status();
    match status {
        Ok(status) if status.success() => {
            println!("cargo:rustc-link-arg={}", res_file.display());
        }
        Ok(status) => println!("cargo:warning=rc.exe 执行失败: {status}"),
        Err(error) => println!("cargo:warning=无法启动 rc.exe: {error}"),
    }
}

/// 优先用 PATH 里的 rc.exe，其次从 Windows SDK 目录里找。
fn find_rc() -> Option<PathBuf> {
    if Command::new("rc.exe").arg("/?").output().is_ok() {
        return Some(PathBuf::from("rc.exe"));
    }

    let arch = match env::var("CARGO_CFG_TARGET_ARCH").as_deref() {
        Ok("aarch64") => "arm64",
        Ok("x86") => "x86",
        _ => "x64",
    };

    let mut roots = Vec::new();
    if let Ok(dir) = env::var("WindowsSdkDir") {
        roots.push(PathBuf::from(dir).join("bin"));
    }
    if let Ok(path) = env::var("PATH") {
        for entry in path.split(';') {
            let mut current = Path::new(entry);
            for _ in 0..4 {
                let parent = current.parent();
                if parent
                    .and_then(|value| value.file_name())
                    .map(|name| name.to_string_lossy().eq_ignore_ascii_case("windows kits"))
                    .unwrap_or(false)
                {
                    roots.push(current.join("bin"));
                    break;
                }
                match parent {
                    Some(value) => current = value,
                    None => break,
                }
            }
        }
    }
    for key in ["ProgramFiles(x86)", "ProgramFiles"] {
        if let Ok(dir) = env::var(key) {
            roots.push(PathBuf::from(dir).join("Windows Kits/10/bin"));
        }
    }

    for root in roots {
        let Ok(entries) = fs::read_dir(&root) else {
            continue;
        };
        let mut versions: Vec<PathBuf> = entries
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| path.is_dir())
            .collect();
        versions.sort();
        for version in versions.iter().rev() {
            let candidate = version.join(arch).join("rc.exe");
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}
