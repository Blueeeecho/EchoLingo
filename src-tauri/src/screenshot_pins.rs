//! Ephemeral, local-only reference windows. No files, clipboard, OCR or network.
use serde::Serialize;
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex,
    },
    time::Duration,
};
use tauri::Manager;

const PREFIX: &str = "screenshot-pin-";
const MAX_WINDOWS: usize = 6;
const MAX_TOTAL_PIXELS: u64 = 48_000_000;
const MAX_TOTAL_ENCODED: usize = 64 * 1024 * 1024;
const CLOSED: &str = "SCREENSHOT_PIN: 贴图窗口已关闭或图片已失效";
type Reply = tokio::sync::oneshot::Sender<Result<(), String>>;
#[derive(Default)]
pub struct Controller {
    next: AtomicU64,
    entries: Mutex<HashMap<String, Entry>>,
}
struct Entry {
    source: u64,
    image: Option<Snapshot>,
    pixels: u64,
    encoded: usize,
    ready: Option<Reply>,
    delivered: bool,
}
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    png_base64: String,
    width: u32,
    height: u32,
}
pub fn is_pin(label: &str) -> bool {
    label
        .strip_prefix(PREFIX)
        .is_some_and(|id| !id.is_empty() && id.bytes().all(|c| c.is_ascii_digit()))
}
fn capacity(entries: &HashMap<String, Entry>, pixels: u64, encoded: usize) -> bool {
    entries.len() < MAX_WINDOWS
        && pixels <= MAX_TOTAL_PIXELS.saturating_sub(entries.values().map(|e| e.pixels).sum())
        && encoded <= MAX_TOTAL_ENCODED.saturating_sub(entries.values().map(|e| e.encoded).sum())
}
pub fn destroyed(app: &tauri::AppHandle, label: &str) {
    if let Ok(mut entries) = app.state::<super::AppState>().screenshot_pins.entries.lock() {
        if let Some(mut entry) = entries.remove(label) {
            if let Some(reply) = entry.ready.take() {
                let _ = reply.send(Err(CLOSED.into()));
            }
        }
    }
}
async fn discard(app: &tauri::AppHandle, label: String) {
    let handle = app.clone();
    let _ = super::screenshot::dialog(app, move || {
        // Retain accounting if native destruction fails: an orphan must never
        // evade the resource budget. Its large pending payload can still go.
        if let Some(window) = handle.get_webview_window(&label) {
            if window.destroy().is_err() {
                if let Ok(mut entries) = handle
                    .state::<super::AppState>()
                    .screenshot_pins
                    .entries
                    .lock()
                {
                    if let Some(entry) = entries.get_mut(&label) {
                        entry.image = None;
                        entry.ready = None;
                    }
                }
                return;
            }
        }
        destroyed(&handle, &label);
    })
    .await;
}
#[tauri::command]
pub async fn pin_screenshot_image(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    session_id: u64,
    png_base64: String,
) -> Result<(), String> {
    if window.label() != "screenshot-editor" {
        return Err(CLOSED.into());
    }
    let state = app.state::<super::AppState>();
    let _operation = state
        .screenshots
        .operations
        .try_acquire()
        .map_err(|_| "SCREENSHOT_BUSY: 请先完成当前图片操作")?;
    state.screenshots.with_pin_source(session_id, || Ok(()))?;
    let snapshot = tauri::async_runtime::spawn_blocking(move || {
        let pixels = super::screenshot::from_base64(&png_base64, true)?;
        Ok::<_, String>(Snapshot {
            width: pixels.width(),
            height: pixels.height(),
            png_base64,
        })
    })
    .await
    .map_err(|_| "SCREENSHOT_PIN: 无法准备贴图")??;
    let width = snapshot.width;
    let height = snapshot.height;
    let label = format!(
        "{PREFIX}{}",
        state.screenshot_pins.next.fetch_add(1, Ordering::Relaxed)
    );
    let (reply, receive) = tokio::sync::oneshot::channel();
    state.screenshots.with_pin_source(session_id, || {
        let mut entries = super::locked(&state.screenshot_pins.entries)?;
        let pixels = u64::from(width) * u64::from(height);
        let encoded = snapshot.png_base64.len();
        if !capacity(&entries, pixels, encoded) {
            return Err("SCREENSHOT_PIN_LIMIT: 贴图已达到数量或内存上限，请先关闭部分贴图".into());
        }
        entries.insert(
            label.clone(),
            Entry {
                source: session_id,
                image: Some(snapshot),
                pixels,
                encoded,
                ready: Some(reply),
                delivered: false,
            },
        );
        Ok(())
    })?;
    let handle = app.clone();
    let name = label.clone();
    let built = super::screenshot::dialog(&app, move || {
        handle
            .state::<super::AppState>()
            .screenshots
            .with_pin_source(session_id, || Ok(()))?;
        // Do not hold registry/image locks while constructing a WebView.
        let scale = (720.0 / f64::from(width))
            .min(520.0 / f64::from(height))
            .min(1.0);
        tauri::WebviewWindowBuilder::new(
            &handle,
            &name,
            tauri::WebviewUrl::App("pinned-screenshot.html".into()),
        )
        .title("贴图 · EchoLingo")
        .inner_size(
            (f64::from(width) * scale).max(240.0),
            (f64::from(height) * scale + 42.0).max(160.0),
        )
        .min_inner_size(200.0, 120.0)
        .center()
        .visible(false)
        .focused(false)
        .decorations(true)
        .resizable(true)
        .always_on_top(true)
        .visible_on_all_workspaces(true)
        .accept_first_mouse(true)
        .build()
        .map(|_| ())
        .map_err(|_| "SCREENSHOT_PIN: 无法创建贴图窗口".to_owned())
    })
    .await;
    let result = match built {
        Ok(Ok(())) => match tokio::time::timeout(Duration::from_secs(15), receive).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(CLOSED.into()),
            Err(_) => Err("SCREENSHOT_PIN: 贴图加载超时，原截图仍保留，请重试".into()),
        },
        Ok(Err(error)) | Err(error) => Err(error),
    };
    if result.is_err() {
        discard(&app, label).await;
    }
    result
}
#[tauri::command]
pub fn get_pinned_screenshot(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
) -> Result<Snapshot, String> {
    let state = app.state::<super::AppState>();
    let mut entries = super::locked(&state.screenshot_pins.entries)?;
    let entry = entries
        .get_mut(window.label())
        .filter(|entry| !entry.delivered)
        .ok_or(CLOSED)?;
    let snapshot = entry.image.as_ref().ok_or(CLOSED)?.clone();
    entry.delivered = true;
    Ok(snapshot)
}
#[tauri::command]
pub async fn pinned_screenshot_ready(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    success: bool,
) -> Result<(), String> {
    let handle = app.clone();
    super::screenshot::dialog(&app, move || {
        let state = handle.state::<super::AppState>();
        let source = {
            let entries = super::locked(&state.screenshot_pins.entries)?;
            entries
                .get(window.label())
                .filter(|entry| entry.delivered && entry.ready.is_some())
                .ok_or(CLOSED)?
                .source
        };
        let result = if !success {
            Err("SCREENSHOT_PIN: 贴图无法解码，原截图仍保留".into())
        } else {
            state.screenshots.with_pin_source(source, || {
                super::platform::ensure_popup_behavior(&window)?;
                super::platform::show_without_activation(&window)
            })
        };
        let mut entries = super::locked(&state.screenshot_pins.entries)?;
        let entry = entries.get_mut(window.label()).ok_or(CLOSED)?;
        entry.image = None; // Frontend owns the immutable decoded bitmap now.
        if let Some(reply) = entry.ready.take() {
            let _ = reply.send(result.clone());
        }
        result
    })
    .await?
}
#[tauri::command]
pub async fn set_screenshot_pinned(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    pinned: bool,
) -> Result<(), String> {
    let handle = app.clone();
    super::screenshot::dialog(&app, move || {
        let state = handle.state::<super::AppState>();
        if !super::locked(&state.screenshot_pins.entries)?
            .get(window.label())
            .is_some_and(|e| e.ready.is_none())
        {
            return Err(CLOSED.into());
        }
        // Reuse popup space policy when re-pinning; no focus/show/activation.
        if pinned {
            super::platform::ensure_popup_behavior(&window)?;
        }
        window
            .set_always_on_top(pinned)
            .map_err(|_| "SCREENSHOT_PIN: 无法调整置顶状态".into())
    })
    .await?
}
#[tauri::command]
pub async fn close_pinned_screenshot(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
) -> Result<(), String> {
    let handle = app.clone();
    super::screenshot::dialog(&app, move || {
        if !super::locked(&handle.state::<super::AppState>().screenshot_pins.entries)?
            .contains_key(window.label())
        {
            return Err(CLOSED.into());
        }
        window
            .destroy()
            .map_err(|_| "SCREENSHOT_PIN: 无法关闭贴图窗口".to_owned())?;
        destroyed(&handle, window.label());
        Ok(())
    })
    .await?
}

#[cfg(test)]
mod tests {
    use super::*;
    fn entry(pixels: u64, encoded: usize) -> Entry {
        Entry {
            source: 1,
            image: None,
            pixels,
            encoded,
            ready: None,
            delivered: true,
        }
    }
    #[test]
    fn pin_capacity_is_bounded_by_count_pixels_and_encoded_memory() {
        let mut entries = HashMap::new();
        assert!(capacity(&entries, MAX_TOTAL_PIXELS, MAX_TOTAL_ENCODED));
        assert!(!capacity(&entries, MAX_TOTAL_PIXELS + 1, 1));
        assert!(!capacity(&entries, 1, MAX_TOTAL_ENCODED + 1));
        entries.insert("one".into(), entry(MAX_TOTAL_PIXELS, 1));
        assert!(!capacity(&entries, 1, 1));
        entries.clear();
        entries.insert("one".into(), entry(1, MAX_TOTAL_ENCODED));
        assert!(!capacity(&entries, 1, 1));
        entries.clear();
        for i in 0..MAX_WINDOWS {
            entries.insert(i.to_string(), entry(1, 1));
        }
        assert!(!capacity(&entries, 1, 1));
        entries.remove("0");
        assert!(capacity(&entries, 1, 1));
    }
    #[test]
    fn only_generated_pin_labels_bypass_translator_close_policy() {
        assert!(is_pin("screenshot-pin-0"));
        for label in [
            "main",
            "screenshot-editor",
            "screenshot-pin-",
            "screenshot-pin-invalid",
        ] {
            assert!(!is_pin(label));
        }
    }
}
