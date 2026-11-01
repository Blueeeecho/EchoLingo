//! Ephemeral, local-only reference windows. No files, clipboard, OCR or network.
use serde::{Deserialize, Serialize};
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
#[derive(Clone, Copy, Debug)]
struct Rect {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}
impl Rect {
    fn intersection(self, other: Self) -> f64 {
        ((self.x + self.width).min(other.x + other.width) - self.x.max(other.x)).max(0.0)
            * ((self.y + self.height).min(other.y + other.height) - self.y.max(other.y)).max(0.0)
    }
}
fn capture_monitor(capture: Rect, monitors: &[Rect]) -> Option<usize> {
    monitors
        .iter()
        .enumerate()
        .map(|(index, area)| (index, area.intersection(capture)))
        .filter(|(_, area)| *area > 0.0)
        .max_by(|a, b| a.1.total_cmp(&b.1))
        .map(|(index, _)| index)
}
// All arguments are in one coordinate system: macOS points, Windows physical
// pixels. `units` is coordinate units per logical UI point on the chosen monitor.
fn placement(
    area: Rect,
    capture: Option<Rect>,
    image: (u32, u32),
    units: f64,
    pixel_scale: f64,
    decoration: (f64, f64),
) -> Result<Rect, String> {
    if ![
        area.x,
        area.y,
        area.width,
        area.height,
        units,
        pixel_scale,
        decoration.0,
        decoration.1,
    ]
    .iter()
    .all(|n| n.is_finite())
        || units <= 0.0
        || pixel_scale <= 0.0
        || area.width <= decoration.0
        || area.height <= decoration.1
        || image.0 == 0
        || image.1 == 0
        || decoration.0 < 0.0
        || decoration.1 < 0.0
    {
        return Err("SCREENSHOT_PIN: 无法确定贴图的可用屏幕范围".into());
    }
    let margin = (8.0 * units)
        .min((area.width - decoration.0) / 8.0)
        .min((area.height - decoration.1) / 8.0);
    let max_width = area.width - decoration.0 - margin * 2.0;
    let max_height = area.height - decoration.1 - margin * 2.0;
    if max_width < 140.0 * units || max_height < 80.0 * units {
        return Err("SCREENSHOT_PIN: 当前屏幕可用范围过小，无法完整显示贴图操作按钮".into());
    }
    if capture.is_some_and(|r| ![r.x, r.y, r.width, r.height].iter().all(|n| n.is_finite())) {
        return Err("SCREENSHOT_PIN: 截图位置无效".into());
    }
    let original = (
        f64::from(image.0) / pixel_scale * units,
        f64::from(image.1) / pixel_scale * units,
    );
    let fit = (720.0 * units).min(max_width) / original.0;
    let fit = fit
        .min((520.0 * units).min(max_height) / original.1)
        .min(1.0);
    let width = (original.0 * fit)
        .max((240.0 * units).min(max_width))
        .min(max_width);
    let height = (original.1 * fit)
        .max((160.0 * units).min(max_height))
        .min(max_height);
    let outer_width = width + decoration.0;
    let outer_height = height + decoration.1;
    let (x, y) = capture.map_or(
        (
            area.x + (area.width - outer_width) / 2.0,
            area.y + (area.height - outer_height) / 2.0,
        ),
        |capture| (capture.x, capture.y),
    );
    let min_x = area.x + margin;
    let min_y = area.y + margin;
    // Exact fits can invert the floating upper/lower bounds by one ULP.
    let max_x = (area.x + area.width - outer_width - margin).max(min_x);
    let max_y = (area.y + area.height - outer_height - margin).max(min_y);
    Ok(Rect {
        x: x.clamp(min_x, max_x),
        y: y.clamp(min_y, max_y),
        width,
        height,
    })
}
fn monitor_rect(monitor: &tauri::Monitor, work_area: bool) -> Rect {
    let (position, size) = if work_area {
        let work = monitor.work_area();
        (work.position, work.size)
    } else {
        (*monitor.position(), *monitor.size())
    };
    // The capture bridge uses top-left global points on macOS, and physical
    // pixels on Windows. Normalize each monitor with its OWN scale, not the
    // current editor's scale (which may still describe its hidden Tauri owner).
    let divisor = if cfg!(target_os = "macos") {
        monitor.scale_factor()
    } else {
        1.0
    };
    Rect {
        x: f64::from(position.x) / divisor,
        y: f64::from(position.y) / divisor,
        width: f64::from(size.width) / divisor,
        height: f64::from(size.height) / divisor,
    }
}
fn position_reference(
    editor: &tauri::WebviewWindow,
    window: &tauri::WebviewWindow,
    geometry: Option<super::platform::ScreenshotGeometry>,
    image: (u32, u32),
) -> Result<(), String> {
    let capture = geometry.as_ref().map(|g| Rect {
        x: g.x,
        y: g.y,
        width: g.width,
        height: g.height,
    });
    let monitors = editor
        .available_monitors()
        .map_err(|_| "SCREENSHOT_PIN: 无法读取截图显示器")?;
    let bounds: Vec<_> = monitors.iter().map(|m| monitor_rect(m, false)).collect();
    let selected = capture.and_then(|capture| capture_monitor(capture, &bounds));
    let monitor = selected
        .and_then(|index| monitors.get(index).cloned())
        .or_else(|| editor.current_monitor().ok().flatten())
        .ok_or("SCREENSHOT_PIN: 截图所在显示器不可用，请重试")?;
    let target_scale = monitor.scale_factor();
    let window_scale = window
        .scale_factor()
        .map_err(|_| "SCREENSHOT_PIN: 无法读取贴图缩放")?;
    if !target_scale.is_finite()
        || target_scale <= 0.0
        || !window_scale.is_finite()
        || window_scale <= 0.0
    {
        return Err("SCREENSHOT_PIN: 显示器缩放无效".into());
    }
    let units = if cfg!(target_os = "macos") {
        1.0
    } else {
        target_scale
    };
    let outer = window
        .outer_size()
        .map_err(|_| "SCREENSHOT_PIN: 无法读取窗口边框")?;
    let inner = window
        .inner_size()
        .map_err(|_| "SCREENSHOT_PIN: 无法读取图片区域")?;
    let decoration = (
        f64::from(outer.width.saturating_sub(inner.width)) / window_scale * units,
        f64::from(outer.height.saturating_sub(inner.height)) / window_scale * units,
    );
    let pixel_scale = if cfg!(target_os = "macos") {
        geometry.as_ref().map_or(target_scale, |g| g.scale)
    } else {
        target_scale
    };
    let frame = placement(
        monitor_rect(&monitor, true),
        capture,
        image,
        units,
        pixel_scale,
        decoration,
    )?;
    window
        .set_min_size(Some(tauri::LogicalSize::new(
            (frame.width / units).min(200.0),
            (frame.height / units).min(120.0),
        )))
        .map_err(|_| "SCREENSHOT_PIN: 无法设置贴图最小尺寸")?;
    #[cfg(target_os = "macos")]
    {
        window
            .set_position(tauri::LogicalPosition::new(frame.x, frame.y))
            .and_then(|_| window.set_size(tauri::LogicalSize::new(frame.width, frame.height)))
            .map_err(|_| "SCREENSHOT_PIN: 无法定位贴图")?;
    }
    #[cfg(not(target_os = "macos"))]
    {
        window
            .set_position(tauri::PhysicalPosition::new(
                frame.x.round() as i32,
                frame.y.round() as i32,
            ))
            .and_then(|_| {
                window.set_size(tauri::PhysicalSize::new(
                    frame.width.floor() as u32,
                    frame.height.floor() as u32,
                ))
            })
            .map_err(|_| "SCREENSHOT_PIN: 无法定位贴图")?;
    }
    Ok(())
}
pub fn destroyed(app: &tauri::AppHandle, label: &str) {
    if let Ok(mut entries) = app
        .state::<super::AppState>()
        .screenshot_pins
        .entries
        .lock()
    {
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
    revision: Option<u64>,
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
    state
        .screenshots
        .check_image_revision(session_id, revision.unwrap_or(0))?;
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
        let geometry = handle
            .state::<super::AppState>()
            .screenshots
            .pin_source_geometry(session_id)?;
        let editor = handle
            .get_webview_window("screenshot-editor")
            .ok_or(CLOSED)?;
        // Do not hold registry/image locks while constructing a WebView.
        // Keep it hidden until the actual source monitor/usable frame is applied.
        let window = tauri::WebviewWindowBuilder::new(
            &handle,
            &name,
            tauri::WebviewUrl::App("pinned-screenshot.html".into()),
        )
        .title("贴图 · EchoLingo")
        .inner_size(240.0, 160.0)
        .visible(false)
        .focused(false)
        .decorations(false)
        .resizable(true)
        .always_on_top(true)
        .visible_on_all_workspaces(true)
        .accept_first_mouse(true)
        .build()
        .map_err(|_| "SCREENSHOT_PIN: 无法创建贴图窗口".to_owned())?;
        position_reference(&editor, &window, geometry, (width, height))
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
        // Native passive show leaves Tao's VISIBLE cache false on Windows.
        // Its style setter would consequently hide this visible reference.
        #[cfg(target_os = "windows")]
        {
            super::platform::set_topmost_without_activation(&window, pinned)
        }
        #[cfg(not(target_os = "windows"))]
        {
            window
                .set_always_on_top(pinned)
                .map_err(|_| "SCREENSHOT_PIN: 无法调整置顶状态".into())
        }
    })
    .await?
}
#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PinResizeDirection {
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
    NorthWest,
}
impl PinResizeDirection {
    fn native_name(self) -> &'static str {
        match self {
            Self::North => "North",
            Self::NorthEast => "NorthEast",
            Self::East => "East",
            Self::SouthEast => "SouthEast",
            Self::South => "South",
            Self::SouthWest => "SouthWest",
            Self::West => "West",
            Self::NorthWest => "NorthWest",
        }
    }
}
fn ready_pin(app: &tauri::AppHandle, window: &tauri::WebviewWindow) -> Result<(), String> {
    if !is_pin(window.label())
        || !super::locked(&app.state::<super::AppState>().screenshot_pins.entries)?
            .get(window.label())
            .is_some_and(|entry| entry.delivered && entry.ready.is_none() && entry.image.is_none())
    {
        return Err(CLOSED.into());
    }
    Ok(())
}
#[tauri::command]
pub async fn start_pinned_screenshot_drag(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
) -> Result<(), String> {
    let handle = app.clone();
    super::screenshot::dialog(&app, move || {
        ready_pin(&handle, &window)?;
        window
            .start_dragging()
            .map_err(|_| "SCREENSHOT_PIN: 无法拖动贴图窗口".to_owned())
    })
    .await?
}
#[tauri::command]
pub async fn resize_pinned_screenshot(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    direction: PinResizeDirection,
) -> Result<(), String> {
    let handle = app.clone();
    super::screenshot::dialog(&app, move || {
        ready_pin(&handle, &window)?;
        let direction = serde_json::from_value(serde_json::json!(direction.native_name()))
            .map_err(|_| "SCREENSHOT_PIN: 贴图调整方向无效".to_owned())?;
        let webview: &tauri::Webview = window.as_ref();
        webview
            .window()
            .start_resize_dragging(direction)
            .map_err(|_| "SCREENSHOT_PIN: 无法调整贴图窗口大小".to_owned())
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

#[cfg(all(target_os = "macos", debug_assertions))]
pub(crate) fn native_smoke_counts(app: &tauri::AppHandle) -> Result<(usize, usize), String> {
    let state = app.state::<super::AppState>();
    let entries = super::locked(&state.screenshot_pins.entries)?;
    Ok((
        entries.len(),
        entries
            .values()
            .filter_map(|e| e.image.as_ref())
            .map(|i| i.png_base64.len())
            .sum(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn borderless_pin_has_no_reserved_toolbar_height() {
        let area = Rect {
            x: 0.0,
            y: 0.0,
            width: 1920.0,
            height: 1080.0,
        };
        let frame = placement(area, None, (640, 480), 1.0, 1.0, (0.0, 0.0)).unwrap();
        assert_eq!((frame.width, frame.height), (640.0, 480.0));
    }
    #[test]
    fn resize_wire_accepts_only_eight_lowercase_directions() {
        for (wire, native) in [
            ("north", "North"),
            ("northeast", "NorthEast"),
            ("east", "East"),
            ("southeast", "SouthEast"),
            ("south", "South"),
            ("southwest", "SouthWest"),
            ("west", "West"),
            ("northwest", "NorthWest"),
        ] {
            let direction: PinResizeDirection =
                serde_json::from_value(serde_json::json!(wire)).unwrap();
            assert_eq!(direction.native_name(), native);
        }
        for invalid in ["North", "north-east", "", "all"] {
            assert!(
                serde_json::from_value::<PinResizeDirection>(serde_json::json!(invalid)).is_err()
            );
        }
    }
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
    fn assert_inside(frame: Rect, area: Rect, decoration: (f64, f64)) {
        assert!(frame.x >= area.x && frame.y >= area.y);
        assert!(frame.x + frame.width + decoration.0 <= area.x + area.width + 0.001);
        assert!(frame.y + frame.height + decoration.1 <= area.y + area.height + 0.001);
    }
    #[test]
    fn pin_chooses_largest_capture_intersection_not_primary_display() {
        let monitors = [
            Rect {
                x: 0.0,
                y: 0.0,
                width: 2560.0,
                height: 1440.0,
            },
            Rect {
                x: -1920.0,
                y: -200.0,
                width: 1920.0,
                height: 1080.0,
            },
        ];
        let capture = Rect {
            x: -500.0,
            y: 100.0,
            width: 600.0,
            height: 500.0,
        };
        assert_eq!(capture_monitor(capture, &monitors), Some(1));
        assert_eq!(
            capture_monitor(
                Rect {
                    x: 8000.0,
                    ..capture
                },
                &monitors
            ),
            None,
        );
    }
    #[test]
    fn pin_clamps_capture_anchor_and_decorations_to_negative_work_area() {
        let area = Rect {
            x: -1920.0,
            y: -176.0,
            width: 1920.0,
            height: 1016.0,
        };
        let capture = Rect {
            x: -90.0,
            y: 800.0,
            width: 300.0,
            height: 200.0,
        };
        let decoration = (16.0, 39.0);
        let frame = placement(area, Some(capture), (1600, 1000), 1.0, 1.0, decoration).unwrap();
        assert_inside(frame, area, decoration);
        assert!(frame.x < -90.0 && frame.y < 800.0);
    }
    #[test]
    fn pin_mixed_dpi_windows_uses_target_scale_not_source_window_scale() {
        let area = Rect {
            x: -3840.0,
            y: 0.0,
            width: 3840.0,
            height: 2080.0,
        };
        let decoration = (32.0, 78.0);
        let frame = placement(area, None, (1600, 1000), 2.0, 2.0, decoration).unwrap();
        assert_inside(frame, area, decoration);
        assert!(frame.width <= 1440.0);
        assert!(
            (frame.x - (area.x + (area.width - frame.width - decoration.0) / 2.0)).abs() < 0.001
        );
        // Mac capture coordinates remain logical points even for a Retina bitmap.
        let mac_area = Rect {
            x: -1920.0,
            y: 24.0,
            width: 1920.0,
            height: 1016.0,
        };
        let mac = placement(mac_area, None, (1600, 1000), 1.0, 2.0, (0.0, 28.0)).unwrap();
        assert_inside(mac, mac_area, (0.0, 28.0));
        assert!(mac.width <= 720.0);
    }
    #[test]
    fn pin_small_work_area_reduces_minimum_instead_of_covering_other_monitors() {
        let area = Rect {
            x: 50.0,
            y: -300.0,
            width: 180.0,
            height: 140.0,
        };
        let decoration = (8.0, 28.0);
        let frame = placement(area, None, (8000, 4000), 1.0, 1.0, decoration).unwrap();
        assert_inside(frame, area, decoration);
        assert!(frame.width < 200.0 && frame.height < 120.0);
        assert!(placement(
            Rect {
                height: 20.0,
                ..area
            },
            None,
            (80, 40),
            1.0,
            1.0,
            decoration,
        )
        .is_err());
    }
    #[test]
    fn pin_exact_fit_rounding_never_inverts_clamp_bounds() {
        let area = Rect {
            x: -920.0,
            y: 9676.0,
            width: 827.0,
            height: 1959.0,
        };
        let decoration = (32.0, 78.0);
        let frame = placement(area, None, (6089, 4215), 2.0, 2.0, decoration).unwrap();
        assert_inside(frame, area, decoration);
    }
    #[test]
    fn pin_rejects_work_area_that_cannot_show_controls() {
        let area = Rect {
            x: 0.0,
            y: 0.0,
            width: 80.0,
            height: 80.0,
        };
        assert!(placement(area, None, (800, 400), 1.0, 1.0, (8.0, 28.0)).is_err());
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
