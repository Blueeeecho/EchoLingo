//! One lightweight WebView, with separate popup and management presentations.
//! Sizing never shows, activates or focuses the window.

use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{LogicalSize, Manager, PhysicalPosition, State, WebviewWindow};

#[derive(Default)]
pub struct LayoutState {
    management: AtomicBool,
}
impl LayoutState {
    pub fn is_popup(&self) -> bool {
        !self.management.load(Ordering::SeqCst)
    }
}

#[derive(Clone, Copy, Debug)]
struct Bounds {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

fn anchor_in_work_area(area: Bounds, x: f64, y: f64, width: f64, height: f64) -> (i32, i32) {
    (
        x.clamp(area.x, area.x + (area.width - width).max(0.0))
            .round() as i32,
        y.clamp(area.y, area.y + (area.height - height).max(0.0))
            .round() as i32,
    )
}

fn content_size(management: bool, height: f64, width: f64, available: (f64, f64)) -> (f64, f64) {
    let max_width = available.0.max(1.0);
    let max_height = available.1.max(1.0);
    let min_width = 420.0_f64.min(max_width);
    let min_height = (if management { 480.0_f64 } else { 160.0_f64 }).min(max_height);
    (
        width.clamp(
            min_width,
            max_width.min(if management { 1000.0 } else { 900.0 }),
        ),
        (if management { 720.0 } else { height.ceil() })
            .clamp(min_height, max_height.min(760.0).max(min_height)),
    )
}

pub fn fit(
    window: &WebviewWindow,
    state: &LayoutState,
    management: bool,
    height: f64,
) -> Result<(), String> {
    if !height.is_finite() || !(0.0..=100_000.0).contains(&height) {
        return Err("窗口内容高度无效".into());
    }
    let previous = state.management.load(Ordering::SeqCst);
    let scale = window.scale_factor().map_err(|_| "无法读取窗口比例")?;
    if !scale.is_finite() || scale <= 0.0 {
        return Err("窗口比例无效".into());
    }
    let monitor = window
        .current_monitor()
        .ok()
        .flatten()
        .or_else(|| window.primary_monitor().ok().flatten());
    let area = monitor
        .map(|monitor| {
            let work = monitor.work_area();
            Bounds {
                x: f64::from(work.position.x),
                y: f64::from(work.position.y),
                width: f64::from(work.size.width),
                height: f64::from(work.size.height),
            }
        })
        .unwrap_or(Bounds {
            x: 0.0,
            y: 0.0,
            width: 1280.0 * scale,
            height: 800.0 * scale,
        });
    let old_size = window
        .inner_size()
        .map_err(|_| "无法读取窗口大小")?
        .to_logical::<f64>(scale);
    let desired_width = if previous != management {
        if management {
            640.0
        } else {
            480.0
        }
    } else {
        old_size.width
    };
    // Reserve margins and a conventional management title bar. The popup is
    // undecorated; it has no second OS title bar above its tiny toolbar.
    let frame = if management { (16.0, 44.0) } else { (0.0, 0.0) };
    let available = (
        area.width / scale - 16.0 - frame.0,
        area.height / scale - 24.0 - frame.1,
    );
    let (width, height) = content_size(management, height, desired_width, available);
    window
        .set_min_size(Some(LogicalSize::new(
            420.0_f64.min(available.0.max(1.0)),
            (if management { 480.0_f64 } else { 160.0_f64 }).min(available.1.max(1.0)),
        )))
        .map_err(|_| "无法调整窗口最小大小")?;
    if window.is_decorated().map_err(|_| "无法读取窗口外观")? != management {
        window
            .set_decorations(management)
            .map_err(|_| "无法调整窗口外观")?;
    }
    if (old_size.width - width).abs() > 1.0 || (old_size.height - height).abs() > 1.0 {
        window
            .set_size(LogicalSize::new(width, height))
            .map_err(|_| "无法调整窗口大小")?;
    }
    if let Ok(position) = window.outer_position() {
        let next = anchor_in_work_area(
            area,
            f64::from(position.x),
            f64::from(position.y),
            (width + frame.0) * scale,
            (height + frame.1) * scale,
        );
        if (position.x, position.y) != next {
            window
                .set_position(PhysicalPosition::new(next.0, next.1))
                .map_err(|_| "无法调整窗口位置")?;
        }
    }
    state.management.store(management, Ordering::SeqCst);
    if !management {
        crate::wake_outside_watcher(window.app_handle());
    }
    Ok(())
}

#[tauri::command]
pub fn fit_window(
    window: WebviewWindow,
    state: State<LayoutState>,
    presentation: String,
    content_height: f64,
) -> Result<(), String> {
    if window.label() != "main" {
        return Err("窗口不可用".into());
    }
    let management = match presentation.as_str() {
        "popup" => false,
        "management" => true,
        _ => return Err("未知窗口模式".into()),
    };
    fit(&window, &state, management, content_height)
}

#[tauri::command]
pub fn start_window_drag(window: WebviewWindow) -> Result<(), String> {
    window.start_dragging().map_err(|_| "无法拖动窗口".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn popup_grows_with_text_and_management_has_its_own_size() {
        assert_eq!(
            content_size(false, 190.0, 480.0, (1200.0, 900.0)),
            (480.0, 190.0)
        );
        assert_eq!(
            content_size(false, 18_000.0, 480.0, (1200.0, 900.0)),
            (480.0, 760.0)
        );
        assert_eq!(
            content_size(true, 190.0, 640.0, (1200.0, 900.0)),
            (640.0, 720.0)
        );
        assert_eq!(
            content_size(false, 300.0, 480.0, (380.0, 140.0)),
            (380.0, 140.0)
        );
    }
    #[test]
    fn resize_stays_on_negative_origin_monitor_without_moving_a_valid_anchor() {
        let area = Bounds {
            x: -1920.0,
            y: -200.0,
            width: 1920.0,
            height: 1080.0,
        };
        assert_eq!(
            anchor_in_work_area(area, -1700.0, 0.0, 960.0, 640.0),
            (-1700, 0)
        );
        assert_eq!(
            anchor_in_work_area(area, -100.0, 700.0, 960.0, 640.0),
            (-960, 240)
        );
        assert_eq!(
            anchor_in_work_area(area, -2200.0, -400.0, 960.0, 640.0),
            (-1920, -200)
        );
    }
}
