//! In-place screenshot shell. Native capture owns selection; this shell owns only
//! the returned frozen bitmap. It never captures, copies, saves or activates on show.
use crate::platform::ScreenshotGeometry;
use serde::Serialize;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Layout {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub viewport_width: f64,
    pub viewport_height: f64,
    pub toolbar_bounds: Bounds,
}
#[derive(Clone, Debug, Serialize)]
pub struct Bounds {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}
fn layout(geometry: &ScreenshotGeometry, coordinate_scale: f64) -> Result<Layout, String> {
    geometry.validate()?;
    if !coordinate_scale.is_finite() || coordinate_scale <= 0.0 || coordinate_scale > 8.0 {
        return Err("SCREENSHOT_GEOMETRY: 无法验证截图显示缩放".into());
    }
    // A virtual desktop can contain holes. Keep controls on a real selected
    // display, using the largest selection intersection rather than the union.
    let monitor = geometry.screens.iter().max_by(|a, b| {
        let area = |screen: &crate::platform::ScreenshotScreen| {
            let width = ((screen.x + screen.width).min(geometry.x + geometry.width)
                - screen.x.max(geometry.x))
            .max(0.0);
            let height = ((screen.y + screen.height).min(geometry.y + geometry.height)
                - screen.y.max(geometry.y))
            .max(0.0);
            width * height
        };
        area(a).total_cmp(&area(b))
    });
    let toolbar_bounds = monitor.map_or(
        Bounds {
            x: 0.0,
            y: 0.0,
            width: geometry.screen_width / coordinate_scale,
            height: geometry.screen_height / coordinate_scale,
        },
        |screen| Bounds {
            x: (screen.x - geometry.screen_x) / coordinate_scale,
            y: (screen.y - geometry.screen_y) / coordinate_scale,
            width: screen.width / coordinate_scale,
            height: screen.height / coordinate_scale,
        },
    );
    Ok(Layout {
        x: (geometry.x - geometry.screen_x) / coordinate_scale,
        y: (geometry.y - geometry.screen_y) / coordinate_scale,
        width: geometry.width / coordinate_scale,
        height: geometry.height / coordinate_scale,
        viewport_width: geometry.screen_width / coordinate_scale,
        viewport_height: geometry.screen_height / coordinate_scale,
        toolbar_bounds,
    })
}

/// Enter/Escape ownership is per visible overlay session. A key held before
/// a repeated F1 can never confirm the new image; injected releases cannot end
/// ownership of a physical press. Kept pure for both-platform unit coverage.
#[cfg(any(target_os = "windows", test))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyRoute {
    Forward,
    Consume,
    Dispatch,
}
#[cfg(any(target_os = "windows", test))]
pub struct KeyOwnership {
    pressed: u8,
    preheld: u8,
}
#[cfg(any(target_os = "windows", test))]
impl KeyOwnership {
    pub fn new(preheld: u8) -> Self {
        Self {
            pressed: 0,
            preheld,
        }
    }
    pub fn held(&self) -> bool {
        self.pressed != 0
    }
    pub fn route(
        &mut self,
        bit: u8,
        down: bool,
        injected: bool,
        armed: bool,
        eligible: bool,
    ) -> KeyRoute {
        if injected {
            return KeyRoute::Forward;
        }
        if self.preheld & bit != 0 {
            if !down {
                self.preheld &= !bit;
            }
            return KeyRoute::Forward;
        }
        if self.pressed & bit != 0 {
            if !down {
                self.pressed &= !bit;
            }
            return KeyRoute::Consume;
        }
        if !down || !armed || !eligible {
            return KeyRoute::Forward;
        }
        self.pressed |= bit;
        KeyRoute::Dispatch
    }
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn echolingo_prepare_screenshot_overlay(
        window: *mut std::ffi::c_void,
        x: f64,
        y: f64,
        width: f64,
        height: f64,
    ) -> i32;
    fn echolingo_show_screenshot_overlay(
        window: *mut std::ffi::c_void,
        x: f64,
        y: f64,
        width: f64,
        height: f64,
    ) -> i32;
    fn echolingo_hide_screenshot_overlay(window: *mut std::ffi::c_void) -> i32;
}
#[cfg(target_os = "macos")]
pub fn prepare(
    window: &tauri::WebviewWindow,
    geometry: &ScreenshotGeometry,
) -> Result<Layout, String> {
    let result = layout(geometry, 1.0)?;
    let native = window
        .ns_window()
        .map_err(|_| "SCREENSHOT_WINDOW: 无法访问原地截图窗口")?;
    // Caller serializes AppKit work on the main thread. This creates a genuine
    // nonactivating panel; the ordinary Tauri owner remains hidden.
    if unsafe {
        echolingo_prepare_screenshot_overlay(
            native,
            geometry.screen_x,
            geometry.screen_y,
            geometry.screen_width,
            geometry.screen_height,
        )
    } != 0
    {
        return Err("SCREENSHOT_WINDOW: 无法准备原地截图面板；未打开独立编辑窗口".into());
    }
    Ok(result)
}
#[cfg(target_os = "macos")]
pub fn show(
    window: &tauri::WebviewWindow,
    geometry: &ScreenshotGeometry,
    _id: u64,
) -> Result<(), String> {
    let native = window
        .ns_window()
        .map_err(|_| "SCREENSHOT_WINDOW: 无法访问原地截图窗口")?;
    if unsafe {
        echolingo_show_screenshot_overlay(
            native,
            geometry.screen_x,
            geometry.screen_y,
            geometry.screen_width,
            geometry.screen_height,
        )
    } == 0
    {
        Ok(())
    } else {
        Err("SCREENSHOT_WINDOW: 无法显示原地截图面板；未切换当前空间".into())
    }
}
#[cfg(target_os = "macos")]
pub fn hide(window: &tauri::WebviewWindow) -> Result<(), String> {
    let native = window
        .ns_window()
        .map_err(|_| "SCREENSHOT_WINDOW: 无法访问原地截图窗口")?;
    if unsafe { echolingo_hide_screenshot_overlay(native) } != 0 {
        return Err("SCREENSHOT_WINDOW: 无法关闭原地截图面板".into());
    }
    crate::platform::hide_webview_window(window)
}
#[cfg(target_os = "macos")]
pub fn focus_text(_window: &tauri::WebviewWindow) -> Result<(), String> {
    Ok(())
}

#[cfg(target_os = "windows")]
#[path = "windows_screenshot_overlay.rs"]
mod windows;
#[cfg(target_os = "windows")]
pub use windows::{focus_text, hide, prepare, show};

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn prepare(
    _window: &tauri::WebviewWindow,
    _geometry: &ScreenshotGeometry,
) -> Result<Layout, String> {
    Err("SCREENSHOT_PLATFORM: 原地截图仅支持 macOS 和 Windows".into())
}
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn show(
    _window: &tauri::WebviewWindow,
    _geometry: &ScreenshotGeometry,
    _id: u64,
) -> Result<(), String> {
    Err("SCREENSHOT_PLATFORM: 原地截图仅支持 macOS 和 Windows".into())
}
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn hide(window: &tauri::WebviewWindow) -> Result<(), String> {
    crate::platform::hide_webview_window(window)
}
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn focus_text(_window: &tauri::WebviewWindow) -> Result<(), String> {
    Err("SCREENSHOT_PLATFORM: 不支持的平台".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn geometry() -> ScreenshotGeometry {
        ScreenshotGeometry {
            x: -1200.0,
            y: 200.0,
            width: 900.0,
            height: 600.0,
            screen_x: -1920.0,
            screen_y: 0.0,
            screen_width: 3840.0,
            screen_height: 1440.0,
            scale: 1.0,
            screens: vec![],
        }
    }
    #[test]
    fn screenshot_overlay_keys_keep_release_ownership_after_close() {
        let mut keys = KeyOwnership::new(0);
        assert_eq!(keys.route(1, true, false, true, true), KeyRoute::Dispatch);
        assert_eq!(keys.route(1, true, false, false, false), KeyRoute::Consume);
        assert_eq!(keys.route(1, false, true, false, false), KeyRoute::Forward);
        assert!(keys.held());
        assert_eq!(keys.route(1, false, false, false, false), KeyRoute::Consume);
        assert!(!keys.held());
        assert_eq!(keys.route(1, true, false, false, true), KeyRoute::Forward);
    }
    #[test]
    fn screenshot_overlay_preheld_repeat_and_unrelated_foreground_do_not_confirm() {
        let mut next = KeyOwnership::new(1);
        assert_eq!(next.route(1, true, false, true, true), KeyRoute::Forward);
        assert_eq!(next.route(1, false, false, true, true), KeyRoute::Forward);
        assert_eq!(next.route(1, true, false, true, false), KeyRoute::Forward);
        assert_eq!(next.route(1, true, false, true, true), KeyRoute::Dispatch);
    }
    #[test]
    fn screenshot_overlay_negative_mixed_dpi_keeps_physical_pixel_mapping() {
        let result = layout(&geometry(), 1.5).unwrap();
        assert_eq!(
            (result.x, result.y, result.width, result.height),
            (480.0, 200.0 / 1.5, 600.0, 400.0)
        );
        assert_eq!(result.viewport_width, 2560.0);
        // Scaling the viewport does not change screenshot output pixel dimensions.
        assert_eq!(geometry().width, 900.0);
    }
    #[test]
    fn screenshot_overlay_toolbar_uses_real_monitor_not_virtual_desktop_gap() {
        let mut value = geometry();
        value.screens = vec![
            crate::platform::ScreenshotScreen {
                x: -1920.0,
                y: 0.0,
                width: 1920.0,
                height: 1080.0,
            },
            crate::platform::ScreenshotScreen {
                x: 0.0,
                y: 360.0,
                width: 1920.0,
                height: 1080.0,
            },
        ];
        let result = layout(&value, 1.5).unwrap();
        assert_eq!(
            (
                result.toolbar_bounds.x,
                result.toolbar_bounds.y,
                result.toolbar_bounds.width,
                result.toolbar_bounds.height
            ),
            (0.0, 0.0, 1280.0, 720.0)
        );
    }
    #[test]
    fn screenshot_overlay_rejects_nonfinite_outside_and_invalid_scale() {
        assert!(layout(&geometry(), 0.0).is_err());
        let mut value = geometry();
        value.x = f64::NAN;
        assert!(layout(&value, 1.0).is_err());
        value = geometry();
        value.x = -9999.0;
        assert!(layout(&value, 1.0).is_err());
    }
}
