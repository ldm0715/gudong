//! 中转站条目的系统缩略图 / 原始图标。
//!
//! 在独立 STA 线程里用 `IShellItemImageFactory` 取 96 px 预览，文件夹与无法生成
//! 缩略图的文件会得到 shell 提供的原始图标。结果编码成 PNG 后通过 `shelf.icon`
//! 事件推给客户端，PNG 编码失败或文件不存在时静默跳过。

use std::ffi::c_void;
use std::path::Path;
use std::sync::mpsc::{Receiver, Sender, SyncSender};

use base64::Engine;
use serde_json::{json, Value};

use crate::rpc;

pub struct IconJob {
    pub id: String,
    pub path: String,
}

/// 启动缩略图线程，返回任务队列。队列满时调用方应放弃本次请求。
pub fn start(tx: Sender<Value>) -> SyncSender<IconJob> {
    let (job_tx, job_rx) = std::sync::mpsc::sync_channel(128);
    let spawned = std::thread::Builder::new()
        .name("shelf-icons".into())
        .spawn(move || run(tx, job_rx));
    if let Err(error) = spawned {
        crate::log(&format!("shelf-icons: 线程启动失败: {error}"));
    }
    job_tx
}

fn run(tx: Sender<Value>, jobs: Receiver<IconJob>) {
    #[cfg(windows)]
    unsafe {
        let _ = windows::Win32::System::Com::CoInitializeEx(
            None,
            windows::Win32::System::Com::COINIT_APARTMENTTHREADED,
        );
    }
    while let Ok(job) = jobs.recv() {
        let Some(png) = load_png(&job.path) else {
            continue;
        };
        let data = base64::engine::general_purpose::STANDARD.encode(png);
        let _ = tx.send(rpc::event(json!({
            "type": "shelf.icon",
            "id": job.id,
            "data": format!("data:image/png;base64,{data}"),
        })));
    }
    #[cfg(windows)]
    unsafe {
        windows::Win32::System::Com::CoUninitialize();
    }
}

fn load_png(path: &str) -> Option<Vec<u8>> {
    let path = Path::new(path);
    if !path.exists() {
        return None;
    }
    let is_dir = std::fs::metadata(path)
        .map(|metadata| metadata.is_dir())
        .unwrap_or(false);
    let (width, height, pixels) = shell_preview(path, is_dir)?;
    let image = image::RgbaImage::from_raw(width as u32, height as u32, pixels)?;
    let mut out = Vec::new();
    {
        use image::ImageEncoder;
        image::codecs::png::PngEncoder::new(&mut out)
            .write_image(
                image.as_raw(),
                width as u32,
                height as u32,
                image::ExtendedColorType::Rgba8,
            )
            .ok()?;
    }
    Some(out)
}

/// 文件夹只取图标；文件优先取内容缩略图，没有缩略图时 shell 会退化成原始图标。
#[cfg(windows)]
fn shell_preview(path: &Path, is_dir: bool) -> Option<(usize, usize, Vec<u8>)> {
    use std::os::windows::ffi::OsStrExt;

    use windows::core::PCWSTR;
    use windows::Win32::Foundation::{HWND, SIZE};
    use windows::Win32::Graphics::Gdi::{
        DeleteObject, GetDC, GetDIBits, GetObjectW, ReleaseDC, BITMAP, BITMAPINFO,
        BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS, HGDIOBJ,
    };
    use windows::Win32::UI::Shell::{
        IShellItemImageFactory, SHCreateItemFromParsingName, SIIGBF_BIGGERSIZEOK,
        SIIGBF_ICONONLY, SIIGBF_RESIZETOFIT,
    };

    const PREVIEW_PX: i32 = 96;

    let mut wide: Vec<u16> = path.as_os_str().encode_wide().collect();
    wide.push(0);
    let flags = if is_dir {
        SIIGBF_ICONONLY
    } else {
        SIIGBF_RESIZETOFIT | SIIGBF_BIGGERSIZEOK
    };

    unsafe {
        let factory: IShellItemImageFactory =
            SHCreateItemFromParsingName(PCWSTR(wide.as_ptr()), None).ok()?;
        let bitmap = factory
            .GetImage(
                SIZE {
                    cx: PREVIEW_PX,
                    cy: PREVIEW_PX,
                },
                flags,
            )
            .ok()?;

        let mut info = BITMAP::default();
        let got = GetObjectW(
            HGDIOBJ(bitmap.0),
            std::mem::size_of::<BITMAP>() as i32,
            Some(&mut info as *mut BITMAP as *mut c_void),
        );
        let (width, height) = (info.bmWidth, info.bmHeight.abs());
        if got == 0 || width <= 0 || height <= 0 || width > 1024 || height > 1024 {
            let _ = DeleteObject(HGDIOBJ(bitmap.0));
            return None;
        }

        let mut header = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: width,
                biHeight: -height,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB.0,
                ..Default::default()
            },
            ..Default::default()
        };
        let mut pixels = vec![0u8; (width * height * 4) as usize];
        let dc = GetDC(HWND::default());
        let lines = GetDIBits(
            dc,
            bitmap,
            0,
            height as u32,
            Some(pixels.as_mut_ptr() as *mut c_void),
            &mut header,
            DIB_RGB_COLORS,
        );
        let _ = ReleaseDC(HWND::default(), dc);
        let _ = DeleteObject(HGDIOBJ(bitmap.0));
        if lines == 0 {
            return None;
        }

        // BGRA（预乘）转 RGBA；JPEG 缩略图 alpha 全 0，视为不透明。
        let opaque = pixels.chunks_exact(4).all(|pixel| pixel[3] == 0);
        for pixel in pixels.chunks_exact_mut(4) {
            pixel.swap(0, 2);
            if opaque {
                pixel[3] = 255;
            }
        }
        Some((width as usize, height as usize, pixels))
    }
}

#[cfg(not(windows))]
fn shell_preview(_path: &Path, _is_dir: bool) -> Option<(usize, usize, Vec<u8>)> {
    None
}

#[cfg(all(test, windows))]
mod tests {
    use super::*;

    #[test]
    fn generates_png_for_a_temp_file() {
        unsafe {
            let _ = windows::Win32::System::Com::CoInitializeEx(
                None,
                windows::Win32::System::Com::COINIT_APARTMENTTHREADED,
            );
        }
        let path = std::env::temp_dir().join(format!(
            "gudong-icon-probe-{}.txt",
            std::process::id()
        ));
        std::fs::write(&path, b"x").unwrap();
        let png = load_png(path.to_string_lossy().as_ref());
        let _ = std::fs::remove_file(&path);
        let png = png.expect("shell icon png");
        assert!(png.starts_with(b"\x89PNG"));
    }
}
