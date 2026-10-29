//! One lightweight WebView, with separate popup and management presentations.
//! Sizing never shows, activates or focuses the window.

use serde::{Deserialize, Serialize};
use std::{
    fs::File,
    io::Read,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};
use tauri::{LogicalSize, Manager, PhysicalPosition, State, WebviewWindow};

const DEFAULT_POPUP_WIDTH: f64 = 680.0;
const MIN_POPUP_WIDTH: f64 = 420.0;
const MAX_INPUT_DIMENSION: f64 = 100_000.0;
const LAYOUT_FILE: &str = "window-layout.json";

pub struct LayoutState {
    management: AtomicBool,
    popup: Arc<Mutex<PopupWidth>>,
    data_dir: Option<PathBuf>,
    constraints: Mutex<Option<Constraints>>,
    #[cfg(target_os = "windows")]
    native_sizing: Mutex<NativeSizing>,
    #[cfg(target_os = "windows")]
    native_observer_installed: AtomicBool,
}
impl Default for LayoutState {
    fn default() -> Self {
        Self {
            management: AtomicBool::new(false),
            popup: Arc::new(Mutex::new(PopupWidth::new(None))),
            data_dir: None,
            constraints: Mutex::new(None),
            #[cfg(target_os = "windows")]
            native_sizing: Mutex::new(NativeSizing::default()),
            #[cfg(target_os = "windows")]
            native_observer_installed: AtomicBool::new(false),
        }
    }
}
impl LayoutState {
    pub fn new(data_dir: PathBuf) -> Self {
        Self {
            popup: Arc::new(Mutex::new(PopupWidth::new(read_saved_width(&data_dir)))),
            data_dir: Some(data_dir),
            ..Self::default()
        }
    }

    pub fn is_popup(&self) -> bool {
        !self.management.load(Ordering::SeqCst)
    }

    // One short-lived debouncer, rather than fsync for every pointer pixel.
    // Only the public width preference is written; no content or credentials.
    fn schedule_save(&self) {
        let Some(directory) = self.data_dir.clone() else {
            return;
        };
        let Ok(mut popup) = self.popup.lock() else {
            return;
        };
        if popup.save_pending {
            return;
        }
        popup.save_pending = true;
        let mut revision = popup.revision;
        let shared = self.popup.clone();
        drop(popup);
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_millis(200));
            let Ok(mut popup) = shared.lock() else {
                return;
            };
            if popup.revision != revision {
                revision = popup.revision;
                continue;
            }
            let _ = write_saved_width(&directory, popup.preferred);
            popup.save_pending = false;
            return;
        });
    }

    /// Optional shutdown flush; also serializes with a pending debounced write.
    pub fn flush(&self) -> Result<(), String> {
        let Some(directory) = &self.data_dir else {
            return Ok(());
        };
        let popup = self.popup.lock().map_err(|_| "窗口布局状态异常")?;
        write_saved_width(directory, popup.preferred)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct Bounds {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

#[derive(Clone, Copy, PartialEq)]
struct Constraints {
    management: bool,
    scale: f64,
    area: Bounds,
}

#[cfg(any(target_os = "windows", test))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct SizingToken {
    revision: u64,
    epoch: u64,
}

#[cfg(any(target_os = "windows", test))]
#[derive(Default)]
struct NativeSizing {
    next_revision: u64,
    current: Option<SizingToken>,
    resized: bool,
    waiters: Vec<tokio::sync::oneshot::Sender<u64>>,
}
#[cfg(any(target_os = "windows", test))]
impl NativeSizing {
    fn begin(&mut self, epoch: u64) -> SizingToken {
        self.next_revision = self.next_revision.wrapping_add(1);
        let token = SizingToken {
            revision: self.next_revision,
            epoch,
        };
        self.current = Some(token);
        self.resized = false;
        token
    }
    fn complete(&mut self, token: SizingToken) -> bool {
        if self.current != Some(token) {
            return false;
        }
        self.current = None;
        self.resized = false;
        self.resolve_waiters();
        true
    }
    fn wait_for_idle(&mut self) -> (u64, Option<tokio::sync::oneshot::Receiver<u64>>) {
        if self.current.is_none() {
            return (self.next_revision, None);
        }
        let (send, receive) = tokio::sync::oneshot::channel();
        self.waiters.push(send);
        (self.next_revision, Some(receive))
    }
    fn destroyed(&mut self) {
        self.current = None;
        self.resized = false;
        self.resolve_waiters();
    }
    fn resolve_waiters(&mut self) {
        for waiter in self.waiters.drain(..) {
            let _ = waiter.send(self.next_revision);
        }
    }
}

#[cfg(any(target_os = "windows", test))]
fn may_remember_native_resize(
    token: SizingToken,
    current: crate::translation_requests::Presentation,
    popup: bool,
    visible: bool,
) -> bool {
    token.epoch == current.epoch && current.presented && popup && visible
}

#[derive(Clone, Copy)]
struct AppliedWidth {
    width: f64,
    scale: f64,
    area: Bounds,
}

struct PopupWidth {
    preferred: f64,
    applied: Option<AppliedWidth>,
    revision: u64,
    save_pending: bool,
}
impl PopupWidth {
    fn new(saved: Option<f64>) -> Self {
        Self {
            preferred: saved
                .filter(|width| valid_preference(*width))
                .unwrap_or(DEFAULT_POPUP_WIDTH),
            applied: None,
            revision: 0,
            save_pending: false,
        }
    }

    fn remember(&mut self, width: f64) -> bool {
        if !valid_preference(width) || (self.preferred - width).abs() <= 1.0 {
            return false;
        }
        self.preferred = width;
        self.revision = self.revision.wrapping_add(1);
        true
    }

    fn observe_user_width(
        &mut self,
        previous_popup: bool,
        actual: f64,
        measured: Option<f64>,
        scale: f64,
        area: Bounds,
    ) -> bool {
        let Some(applied) = self.applied else {
            return false;
        };
        // The first fit honors restored width over the configured startup size.
        // DPI/monitor changes and programmatic width clamps are not user intent.
        if !previous_popup
            || applied.area != area
            || (applied.scale - scale).abs() > 0.001
            || measured.is_none_or(|width| (width - actual).abs() > 2.0)
            || (actual - applied.width).abs() <= 1.0
        {
            return false;
        }
        self.remember(actual)
    }

    fn applied(&mut self, width: f64, scale: f64, area: Bounds) {
        self.applied = Some(AppliedWidth { width, scale, area });
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SavedLayout {
    version: u8,
    popup_width: f64,
}
fn valid_preference(width: f64) -> bool {
    width.is_finite() && (MIN_POPUP_WIDTH..=MAX_INPUT_DIMENSION).contains(&width)
}
fn saved_width(bytes: &[u8]) -> Option<f64> {
    if bytes.len() > 4096 {
        return None;
    }
    let value: SavedLayout = serde_json::from_slice(bytes).ok()?;
    (value.version == 1 && valid_preference(value.popup_width)).then_some(value.popup_width)
}
fn read_saved_width(directory: &Path) -> Option<f64> {
    let mut bytes = Vec::new();
    File::open(directory.join(LAYOUT_FILE))
        .ok()?
        .take(4097)
        .read_to_end(&mut bytes)
        .ok()?;
    saved_width(&bytes)
}
fn write_saved_width(directory: &Path, width: f64) -> Result<(), String> {
    crate::write_json(
        &directory.join(LAYOUT_FILE),
        &SavedLayout {
            version: 1,
            popup_width: width,
        },
    )
}

fn anchor_in_work_area(area: Bounds, x: f64, y: f64, width: f64, height: f64) -> (i32, i32) {
    (
        x.clamp(area.x, area.x + (area.width - width).max(0.0))
            .round() as i32,
        y.clamp(area.y, area.y + (area.height - height).max(0.0))
            .round() as i32,
    )
}
fn available_size(area: Bounds, scale: f64, management: bool) -> (f64, f64) {
    let frame = if management { (16.0, 44.0) } else { (0.0, 0.0) };
    (
        area.width / scale - 16.0 - frame.0,
        area.height / scale - 24.0 - frame.1,
    )
}
fn content_size(management: bool, height: f64, width: f64, available: (f64, f64)) -> (f64, f64) {
    let max_width = available.0.max(1.0);
    let max_height = available.1.max(1.0);
    let min_width = MIN_POPUP_WIDTH.min(max_width);
    let min_height = (if management { 480.0_f64 } else { 160.0_f64 }).min(max_height);
    (
        width.clamp(min_width, max_width),
        height.ceil().clamp(
            min_height,
            (if management {
                max_height
            } else {
                max_height.min(760.0)
            })
            .max(min_height),
        ),
    )
}

fn presentation_size(
    previous_management: bool,
    management: bool,
    measured_height: f64,
    current: (f64, f64),
    popup_width: f64,
    available: (f64, f64),
) -> (f64, f64) {
    let (width, height) = if management {
        // Entering settings needs its own initial geometry, not the previous
        // popup's height. Later fits preserve the user's native resize instead
        // of replacing it with that initial size after every content reflow.
        if previous_management {
            current
        } else {
            (640.0, 720.0)
        }
    } else {
        (popup_width, measured_height)
    };
    content_size(management, height, width, available)
}
fn window_geometry(window: &WebviewWindow) -> Result<(f64, Bounds), String> {
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
    Ok((scale, area))
}

#[cfg(target_os = "windows")]
mod native_resize {
    use super::*;
    use std::ffi::c_void;
    use tauri::Emitter;

    type Handle = *mut c_void;
    type Subclass = unsafe extern "system" fn(Handle, u32, usize, isize, usize, usize) -> isize;
    const ID: usize = 0x4543484f;
    #[link(name = "comctl32")]
    unsafe extern "system" {
        fn SetWindowSubclass(
            window: Handle,
            callback: Option<Subclass>,
            id: usize,
            data: usize,
        ) -> i32;
        fn RemoveWindowSubclass(window: Handle, callback: Option<Subclass>, id: usize) -> i32;
        fn DefSubclassProc(window: Handle, message: u32, word: usize, parameter: isize) -> isize;
    }
    #[link(name = "user32")]
    unsafe extern "system" {
        fn IsWindowVisible(window: Handle) -> i32;
    }

    #[derive(Clone, Serialize)]
    #[serde(rename_all = "camelCase")]
    struct SizingEvent {
        revision: u64,
        presentation_epoch: u64,
        active: bool,
    }

    fn notify(app: &tauri::AppHandle, token: SizingToken, active: bool) {
        let _ = app.emit(
            "popup-native-sizing",
            SizingEvent {
                revision: token.revision,
                presentation_epoch: token.epoch,
                active,
            },
        );
    }

    pub fn install(window: &WebviewWindow, state: &LayoutState) -> Result<(), String> {
        if state.native_observer_installed.load(Ordering::SeqCst) {
            return Ok(());
        }
        let hwnd = window.hwnd().map_err(|_| "无法读取窗口句柄")?.0 as Handle;
        if hwnd.is_null() {
            return Err("无法读取窗口句柄".into());
        }
        // Called from fit's UI-thread transaction. The borrowed HWND belongs
        // only to this app; this never subclasses another application's HWND.
        let data = Box::into_raw(Box::new(window.app_handle().clone()));
        if unsafe { SetWindowSubclass(hwnd, Some(callback), ID, data as usize) } == 0 {
            unsafe {
                drop(Box::from_raw(data));
            }
            return Err("无法观察窗口调整状态".into());
        }
        state
            .native_observer_installed
            .store(true, Ordering::SeqCst);
        Ok(())
    }

    unsafe extern "system" fn callback(
        window: Handle,
        message: u32,
        word: usize,
        parameter: isize,
        _id: usize,
        data: usize,
    ) -> isize {
        if data == 0 {
            return unsafe { DefSubclassProc(window, message, word, parameter) };
        }
        let app = unsafe { &*(data as *const tauri::AppHandle) };
        // Keep a panic from crossing the Win32 ABI. The observer never consumes
        // the native message or performs painting, focus or geometry changes.
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let state = app.state::<LayoutState>();
            if message == 0x0231 {
                // WM_ENTERSIZEMOVE
                if let Ok(presentation) = app
                    .state::<crate::AppState>()
                    .translation_requests
                    .presentation()
                {
                    if let Ok(mut sizing) = state.native_sizing.lock() {
                        let token = sizing.begin(presentation.epoch);
                        drop(sizing);
                        notify(app, token, true);
                    }
                }
            } else if message == 0x0214 {
                // WM_SIZING, unlike title-bar moving.
                if let Ok(mut sizing) = state.native_sizing.lock() {
                    if sizing.current.is_some() {
                        sizing.resized = true;
                    }
                }
            } else if message == 0x0232 {
                // WM_EXITSIZEMOVE
                let token = state
                    .native_sizing
                    .lock()
                    .ok()
                    .and_then(|sizing| sizing.current);
                if let Some(token) = token {
                    // The subclass already runs on its owning window thread.
                    // Completing here cannot lose an extra queued task.
                    finish(app, token);
                }
            }
        }));
        if message == 0x0082 {
            // WM_NCDESTROY owns the final Box release.
            let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let state = app.state::<LayoutState>();
                state
                    .native_observer_installed
                    .store(false, Ordering::SeqCst);
                if let Ok(mut sizing) = state.native_sizing.lock() {
                    sizing.destroyed();
                };
            }));
            unsafe {
                RemoveWindowSubclass(window, Some(callback), ID);
            }
            let result = unsafe { DefSubclassProc(window, message, word, parameter) };
            unsafe {
                drop(Box::from_raw(data as *mut tauri::AppHandle));
            }
            return result;
        }
        unsafe { DefSubclassProc(window, message, word, parameter) }
    }

    fn finish(app: &tauri::AppHandle, token: SizingToken) {
        let state = app.state::<LayoutState>();
        let resized = match state.native_sizing.lock() {
            Ok(sizing) if sizing.current == Some(token) => sizing.resized,
            _ => return,
        };
        let mut changed = false;
        if let Some(window) = app.get_webview_window("main") {
            let visible = window
                .hwnd()
                .ok()
                .is_some_and(|native| unsafe { IsWindowVisible(native.0 as Handle) } != 0);
            if app
                .state::<crate::AppState>()
                .translation_requests
                .presentation()
                .is_ok_and(|current| {
                    may_remember_native_resize(token, current, state.is_popup(), visible)
                })
            {
                if let (Ok((scale, area)), Ok(size)) =
                    (window_geometry(&window), window.inner_size())
                {
                    let width = size.to_logical::<f64>(scale).width;
                    if let Ok(mut popup) = state.popup.lock() {
                        if app
                            .state::<crate::AppState>()
                            .translation_requests
                            .presentation()
                            .is_ok_and(|current| {
                                may_remember_native_resize(
                                    token,
                                    current,
                                    state.is_popup(),
                                    visible,
                                )
                            })
                        {
                            // A move, DPI transition or work-area clamp is not
                            // permission to replace the owner's wider preference.
                            if resized {
                                changed =
                                    popup.observe_user_width(true, width, Some(width), scale, area);
                            }
                            popup.applied(width, scale, area);
                        }
                    }
                }
            }
        }
        if state
            .native_sizing
            .lock()
            .is_ok_and(|mut sizing| sizing.complete(token))
        {
            if changed {
                state.schedule_save();
            }
            notify(app, token, false);
        }
    }
}

pub fn fit(
    window: &WebviewWindow,
    state: &LayoutState,
    management: bool,
    height: f64,
    content_width: Option<f64>,
) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        // Keep the sizing-loop test and all resulting HWND mutations on the
        // same UI thread. A worker-side test could enqueue SetSize just before
        // WM_ENTERSIZEMOVE and apply it in the middle of the user's gesture.
        let _ = state;
        let native = window.clone();
        let app = window.app_handle().clone();
        let (reply, result) = std::sync::mpsc::sync_channel(1);
        window
            .run_on_main_thread(move || {
                let state = app.state::<LayoutState>();
                let value = native_resize::install(&native, &state)
                    .and_then(|_| fit_inner(&native, &state, management, height, content_width));
                let _ = reply.send(value);
            })
            .map_err(|_| "无法安排窗口布局")?;
        return result.recv().map_err(|_| "窗口布局已中断")?;
    }
    #[cfg(not(target_os = "windows"))]
    fit_inner(window, state, management, height, content_width)
}

fn fit_inner(
    window: &WebviewWindow,
    state: &LayoutState,
    management: bool,
    height: f64,
    content_width: Option<f64>,
) -> Result<(), String> {
    if !height.is_finite() || !(0.0..=MAX_INPUT_DIMENSION).contains(&height) {
        return Err("窗口内容高度无效".into());
    }
    if content_width.is_some_and(|width| {
        !width.is_finite() || !(0.0..=MAX_INPUT_DIMENSION).contains(&width) || width == 0.0
    }) {
        return Err("窗口内容宽度无效".into());
    }
    #[cfg(target_os = "windows")]
    if state
        .native_sizing
        .lock()
        .map_err(|_| "窗口布局状态异常")?
        .current
        .is_some()
    {
        // WM_EXITSIZEMOVE queues the final current-epoch width commit and
        // frontend remeasurement. No timer or geometry mutation while active.
        return Ok(());
    }
    let previous = state.management.load(Ordering::SeqCst);
    let (scale, area) = window_geometry(window)?;
    let old_size = window
        .inner_size()
        .map_err(|_| "无法读取窗口大小")?
        .to_logical::<f64>(scale);
    let mut popup = state.popup.lock().map_err(|_| "窗口布局状态异常")?;
    let changed = popup.observe_user_width(!previous, old_size.width, content_width, scale, area);
    let available = available_size(area, scale, management);
    let (width, height) = presentation_size(
        previous,
        management,
        height,
        (old_size.width, old_size.height),
        popup.preferred,
        available,
    );
    let next_constraints = Constraints {
        management,
        scale,
        area,
    };
    let constraints_changed = !cfg!(target_os = "windows")
        || *state.constraints.lock().map_err(|_| "窗口布局状态异常")? != Some(next_constraints);
    if constraints_changed {
        window
            .set_min_size(Some(LogicalSize::new(
                MIN_POPUP_WIDTH.min(available.0.max(1.0)),
                (if management { 480.0_f64 } else { 160.0_f64 }).min(available.1.max(1.0)),
            )))
            .map_err(|_| "无法调整窗口最小大小")?;
        window
            .set_max_size(Some(LogicalSize::new(
                available.0.max(1.0),
                available.1.max(1.0),
            )))
            .map_err(|_| "无法调整窗口最大大小")?;
        if window.is_decorated().map_err(|_| "无法读取窗口外观")? != management {
            window
                .set_decorations(management)
                .map_err(|_| "无法调整窗口外观")?;
        }
        *state.constraints.lock().map_err(|_| "窗口布局状态异常")? = Some(next_constraints);
    }
    if previous != management
        || (old_size.width - width).abs() > 1.0
        || (old_size.height - height).abs() > 1.0
    {
        window
            .set_size(LogicalSize::new(width, height))
            .map_err(|_| "无法调整窗口大小")?;
    }
    let frame = if management { (16.0, 44.0) } else { (0.0, 0.0) };
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
    let repair_popup = !management && (previous != management || constraints_changed);
    if repair_popup {
        // Tao queues macOS style/size mutations. Queue floating level after
        // them too; sizing still must not show, activate or focus the window.
        window
            .set_always_on_top(true)
            .map_err(|_| "无法恢复浮窗置顶")?;
    }
    if !management {
        popup.applied(width, scale, area);
    }
    state.management.store(management, Ordering::SeqCst);
    drop(popup);
    if changed {
        state.schedule_save();
    }
    if repair_popup {
        crate::wake_outside_watcher(window.app_handle());
        // Returning from management may have no separate show_popup command.
        // Restore the same passive floating policy without presenting/focusing.
        let app = window.app_handle().clone();
        let expected = app
            .state::<crate::AppState>()
            .translation_requests
            .presentation()
            .ok();
        let native = window.clone();
        window
            .run_on_main_thread(move || {
                if app.state::<LayoutState>().is_popup()
                    && app
                        .state::<crate::AppState>()
                        .translation_requests
                        .presentation()
                        .ok()
                        == expected
                {
                    if let Err(error) = crate::platform::ensure_popup_behavior(&native) {
                        use tauri::Emitter;
                        let _ = app.emit("action-error", error);
                    }
                }
            })
            .map_err(|_| "无法恢复浮窗状态")?;
    }
    Ok(())
}

#[tauri::command]
pub fn fit_window(
    window: WebviewWindow,
    state: State<LayoutState>,
    presentation: String,
    content_height: f64,
    content_width: Option<f64>,
) -> Result<(), String> {
    if window.label() != "main" {
        return Err("窗口不可用".into());
    }
    let management = match presentation.as_str() {
        "popup" => false,
        "management" => true,
        _ => return Err("未知窗口模式".into()),
    };
    fit(&window, &state, management, content_height, content_width)
}

#[tauri::command]
pub async fn wait_for_window_sizing(
    window: WebviewWindow,
    state: State<'_, LayoutState>,
) -> Result<u64, String> {
    if window.label() != "main" {
        return Err("窗口不可用".into());
    }
    #[cfg(target_os = "windows")]
    {
        // Subscribe under the same lock that closes the native loop: an end
        // between the check and subscription cannot lose the acknowledgement.
        let (revision, completion) = state
            .native_sizing
            .lock()
            .map_err(|_| "窗口布局状态异常")?
            .wait_for_idle();
        return match completion {
            Some(completion) => completion.await.map_err(|_| "窗口调整已中断".into()),
            None => Ok(revision),
        };
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = state;
        Ok(0)
    }
}

#[tauri::command]
pub fn start_window_drag(window: WebviewWindow) -> Result<(), String> {
    window.start_dragging().map_err(|_| "无法拖动窗口".into())
}
#[derive(Clone, Copy, PartialEq)]
enum HorizontalResize {
    West,
    East,
}
fn resize_direction(direction: &str) -> Result<HorizontalResize, String> {
    match direction {
        "west" => Ok(HorizontalResize::West),
        "east" => Ok(HorizontalResize::East),
        _ => Err("窗口调整方向无效".into()),
    }
}
#[tauri::command]
pub fn start_window_resize(
    window: WebviewWindow,
    state: State<LayoutState>,
    direction: String,
    presentation_epoch: u64,
    management: Option<bool>,
) -> Result<(), String> {
    let management = management.unwrap_or(false);
    let presentation = window
        .state::<crate::AppState>()
        .translation_requests
        .presentation()?;
    if window.label() != "main"
        || !resize_presentation_allowed(
            presentation_epoch,
            presentation,
            state.is_popup(),
            window.is_visible().unwrap_or(false),
            management,
        )
    {
        return Err("窗口不可用".into());
    }
    // Tauri exposes this operation on Window, not WebviewWindow. Deserialize
    // only a direction valid for the exact current presentation.
    let direction = native_resize_direction(&direction, management)?;
    let direction =
        serde_json::from_value(serde_json::json!(direction)).map_err(|_| "窗口调整方向无效")?;
    let webview: &tauri::Webview = window.as_ref();
    webview
        .window()
        .start_resize_dragging(direction)
        .map_err(|_| "无法拖动调整窗口大小".into())
}
fn resize_edges(direction: &str) -> Result<(i8, i8), String> {
    match direction {
        "west" => Ok((-1, 0)),
        "east" => Ok((1, 0)),
        "north" => Ok((0, -1)),
        "south" => Ok((0, 1)),
        "north-west" => Ok((-1, -1)),
        "north-east" => Ok((1, -1)),
        "south-west" => Ok((-1, 1)),
        "south-east" => Ok((1, 1)),
        _ => Err("窗口调整方向无效".into()),
    }
}
fn native_resize_direction(direction: &str, management: bool) -> Result<&'static str, String> {
    if !management {
        resize_direction(direction)?;
    }
    match resize_edges(direction)? {
        (-1, 0) => Ok("West"),
        (1, 0) => Ok("East"),
        (0, -1) => Ok("North"),
        (0, 1) => Ok("South"),
        (-1, -1) => Ok("NorthWest"),
        (1, -1) => Ok("NorthEast"),
        (-1, 1) => Ok("SouthWest"),
        (1, 1) => Ok("SouthEast"),
        _ => unreachable!(),
    }
}
fn resize_presentation_allowed(
    epoch: u64,
    presentation: crate::translation_requests::Presentation,
    popup: bool,
    visible: bool,
    management: bool,
) -> bool {
    popup != management && visible && presentation.presented && presentation.epoch == epoch
}
fn resize_allowed(
    epoch: u64,
    presentation: crate::translation_requests::Presentation,
    popup: bool,
    visible: bool,
) -> bool {
    resize_presentation_allowed(epoch, presentation, popup, visible, false)
}

fn resize_position(
    area: Bounds,
    position: (i32, i32),
    old_width: f64,
    width: f64,
    height: f64,
    scale: f64,
    direction: HorizontalResize,
) -> (i32, i32) {
    let x = f64::from(position.0)
        + if direction == HorizontalResize::West {
            (old_width - width) * scale
        } else {
            0.0
        };
    anchor_in_work_area(
        area,
        x,
        f64::from(position.1),
        width * scale,
        height * scale,
    )
}

// Tao does not implement native resize-dragging on macOS. The two local edge
// handles send a coalesced width, rather than receiving general window powers.
#[tauri::command]
pub async fn resize_popup_width(
    window: WebviewWindow,
    width: f64,
    direction: String,
    presentation_epoch: u64,
) -> Result<(), String> {
    if window.label() != "main"
        || !width.is_finite()
        || !(1.0..=MAX_INPUT_DIMENSION).contains(&width)
    {
        return Err("窗口宽度无效".into());
    }
    let direction = resize_direction(&direction)?;
    let app = window.app_handle().clone();
    let (reply, result) = tokio::sync::oneshot::channel();
    app.run_on_main_thread(move || {
        let operation = (|| {
            let app_state = window.state::<crate::AppState>();
            let state = window.state::<LayoutState>();
            let current = app_state.translation_requests.presentation()?;
            if !resize_allowed(
                presentation_epoch,
                current,
                state.is_popup(),
                window.is_visible().unwrap_or(false),
            ) {
                return Err(crate::translation_requests::CANCELLED.into());
            }
            let (scale, area) = window_geometry(&window)?;
            let old_size = window
                .inner_size()
                .map_err(|_| "无法读取窗口大小")?
                .to_logical::<f64>(scale);
            let (next_width, next_height) = content_size(
                false,
                old_size.height,
                width,
                available_size(area, scale, false),
            );
            let position = window.outer_position().map_err(|_| "无法读取窗口位置")?;
            window
                .set_size(LogicalSize::new(next_width, next_height))
                .map_err(|_| "无法调整窗口大小")?;
            let next = resize_position(
                area,
                (position.x, position.y),
                old_size.width,
                next_width,
                next_height,
                scale,
                direction,
            );
            window
                .set_position(PhysicalPosition::new(next.0, next.1))
                .map_err(|_| "无法调整窗口位置")?;
            // Even a drag that was superseded during the native mutation was
            // programmatic. Do not let the next fit misclassify its temporary
            // width as a fresh user resize and persist an abandoned event.
            let mut popup = state.popup.lock().map_err(|_| "窗口布局状态异常")?;
            popup.applied(next_width, scale, area);
            if app_state.translation_requests.presentation()? != current
                || !state.is_popup()
                || !window.is_visible().unwrap_or(false)
            {
                return Err(crate::translation_requests::CANCELLED.into());
            }
            let changed = popup.remember(next_width.max(MIN_POPUP_WIDTH));
            drop(popup);
            if changed {
                state.schedule_save();
            }
            Ok(())
        })();
        let _ = reply.send(operation);
    })
    .map_err(|_| "无法调整窗口大小")?;
    result.await.map_err(|_| "无法调整窗口大小".to_string())?
}

// Management resizing has no persistence side effect. It is separate from
// popup width so a settings corner can never overwrite the saved popup width.
fn management_resize_geometry(
    direction: (i8, i8),
    old: (f64, f64),
    requested: (f64, f64),
    position: (i32, i32),
    frame: (f64, f64),
    area: Bounds,
    scale: f64,
) -> ((f64, f64), (i32, i32)) {
    let size = content_size(
        true,
        if direction.1 == 0 { old.1 } else { requested.1 },
        if direction.0 == 0 { old.0 } else { requested.0 },
        available_size(area, scale, true),
    );
    let x = f64::from(position.0)
        + if direction.0 < 0 {
            (old.0 - size.0) * scale
        } else {
            0.0
        };
    let y = f64::from(position.1)
        + if direction.1 < 0 {
            (old.1 - size.1) * scale
        } else {
            0.0
        };
    let next = anchor_in_work_area(
        area,
        x,
        y,
        (size.0 + frame.0) * scale,
        (size.1 + frame.1) * scale,
    );
    (size, next)
}

#[tauri::command]
pub async fn resize_management_window(
    window: WebviewWindow,
    width: f64,
    height: f64,
    direction: String,
    presentation_epoch: u64,
) -> Result<(), String> {
    if !cfg!(target_os = "macos")
        || window.label() != "main"
        || ![width, height]
            .iter()
            .all(|value| value.is_finite() && (1.0..=MAX_INPUT_DIMENSION).contains(value))
    {
        return Err("窗口大小无效".into());
    }
    let direction = resize_edges(&direction)?;
    let app = window.app_handle().clone();
    let (reply, result) = tokio::sync::oneshot::channel();
    app.run_on_main_thread(move || {
        let operation = (|| {
            let app_state = window.state::<crate::AppState>();
            let state = window.state::<LayoutState>();
            let current = app_state.translation_requests.presentation()?;
            let valid = || -> bool {
                app_state.translation_requests.presentation().ok() == Some(current)
                    && resize_presentation_allowed(
                        presentation_epoch,
                        current,
                        state.is_popup(),
                        window.is_visible().unwrap_or(false),
                        true,
                    )
            };
            if !valid() {
                return Err(crate::translation_requests::CANCELLED.into());
            }
            let (scale, area) = window_geometry(&window)?;
            let old = window
                .inner_size()
                .map_err(|_| "无法读取窗口大小")?
                .to_logical::<f64>(scale);
            let outer = window
                .outer_size()
                .map_err(|_| "无法读取窗口大小")?
                .to_logical::<f64>(scale);
            let position = window.outer_position().map_err(|_| "无法读取窗口位置")?;
            let (size, next) = management_resize_geometry(
                direction,
                (old.width, old.height),
                (width, height),
                (position.x, position.y),
                (
                    (outer.width - old.width).max(0.0),
                    (outer.height - old.height).max(0.0),
                ),
                area,
                scale,
            );
            if !valid() {
                return Err(crate::translation_requests::CANCELLED.into());
            }
            window
                .set_size(LogicalSize::new(size.0, size.1))
                .map_err(|_| "无法调整窗口大小")?;
            if !valid() {
                return Err(crate::translation_requests::CANCELLED.into());
            }
            if (position.x, position.y) != next {
                window
                    .set_position(PhysicalPosition::new(next.0, next.1))
                    .map_err(|_| "无法调整窗口位置")?;
            }
            if !valid() {
                return Err(crate::translation_requests::CANCELLED.into());
            }
            Ok(())
        })();
        let _ = reply.send(operation);
    })
    .map_err(|_| "无法调整窗口大小")?;
    result.await.map_err(|_| "无法调整窗口大小".to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;
    fn area(width: f64) -> Bounds {
        Bounds {
            x: 0.0,
            y: 0.0,
            width,
            height: 1000.0,
        }
    }

    #[test]
    fn popup_default_and_work_area_replace_arbitrary_width_caps() {
        let popup = PopupWidth::new(None);
        assert_eq!(popup.preferred, 680.0);
        assert_eq!(
            content_size(false, 190.0, popup.preferred, (1200.0, 900.0)),
            (680.0, 190.0)
        );
        assert_eq!(
            content_size(false, 18000.0, 1500.0, (1900.0, 900.0)),
            (1500.0, 760.0)
        );
        assert_eq!(
            presentation_size(false, true, 190.0, (680.0, 240.0), 680.0, (1200.0, 900.0)),
            (640.0, 720.0)
        );
        assert_eq!(
            content_size(false, 300.0, 680.0, (380.0, 140.0)),
            (380.0, 140.0)
        );
    }

    #[test]
    fn management_initial_size_is_separate_from_later_native_resizes() {
        assert_eq!(
            presentation_size(false, true, 4000.0, (680.0, 240.0), 850.0, (1200.0, 1000.0)),
            (640.0, 720.0)
        );
        for height in [620.0, 920.0] {
            assert_eq!(
                content_size(true, height, 910.0, (1200.0, 1000.0)),
                (910.0, height)
            );
            assert_eq!(
                presentation_size(true, true, 4000.0, (910.0, height), 850.0, (1200.0, 1000.0)),
                (910.0, height)
            );
        }
        // A monitor/DPI work-area change may clamp the native management size,
        // but content growth must not substitute a popup or default dimension.
        assert_eq!(
            presentation_size(true, true, 4000.0, (1400.0, 1100.0), 850.0, (800.0, 650.0)),
            (800.0, 650.0)
        );
        assert_eq!(
            presentation_size(false, true, 190.0, (680.0, 240.0), 850.0, (380.0, 430.0)),
            (380.0, 430.0)
        );
        // Returning to translation still restores the independent popup width
        // and sizes height from its current source/results.
        assert_eq!(
            presentation_size(true, false, 230.0, (910.0, 920.0), 850.0, (1200.0, 1000.0)),
            (850.0, 230.0)
        );
    }

    #[test]
    fn restore_and_manual_width_survive_management_and_configured_startup_width() {
        let mut popup = PopupWidth::new(None);
        assert!(!popup.observe_user_width(true, 480.0, Some(480.0), 2.0, area(3000.0)));
        popup.applied(680.0, 2.0, area(3000.0));
        assert!(popup.observe_user_width(true, 850.0, Some(850.0), 2.0, area(3000.0)));
        assert_eq!(popup.preferred, 850.0);
        // Management is 640 wide, but never changes the saved popup intent.
        assert!(!popup.observe_user_width(false, 640.0, Some(640.0), 2.0, area(3000.0)));
        assert_eq!(
            content_size(false, 240.0, popup.preferred, (1484.0, 900.0)).0,
            850.0
        );
        let bytes = serde_json::to_vec(&SavedLayout {
            version: 1,
            popup_width: popup.preferred,
        })
        .unwrap();
        let mut restored = PopupWidth::new(saved_width(&bytes));
        assert!(!restored.observe_user_width(true, 680.0, Some(680.0), 2.0, area(3000.0)));
        assert_eq!(restored.preferred, 850.0);
    }

    #[test]
    fn monitor_clamps_and_dpi_changes_never_destroy_a_larger_preference() {
        let mut popup = PopupWidth::new(Some(1400.0));
        let small = area(1600.0);
        let width = content_size(
            false,
            240.0,
            popup.preferred,
            available_size(small, 2.0, false),
        )
        .0;
        assert_eq!(width, 784.0);
        popup.applied(width, 2.0, small);
        assert!(!popup.observe_user_width(true, width, Some(width), 2.0, small));
        assert!(!popup.observe_user_width(true, width * 2.0, Some(width * 2.0), 1.0, small));
        assert!(!popup.observe_user_width(true, 700.0, Some(700.0), 2.0, area(1800.0)));
        assert_eq!(popup.preferred, 1400.0);
        assert_eq!(
            content_size(false, 240.0, popup.preferred, (1900.0, 900.0)).0,
            1400.0
        );
    }

    #[test]
    fn native_sizing_stale_completion_cannot_release_a_newer_gesture() {
        let mut sizing = NativeSizing::default();
        let old = sizing.begin(10);
        sizing.resized = true;
        let current = sizing.begin(11);
        assert!(!sizing.resized); // A new move is not yet a user resize.
        assert!(!sizing.complete(old));
        assert_eq!(sizing.current, Some(current));
        assert!(sizing.complete(current));
        assert_eq!(sizing.current, None);
        assert!(!sizing.complete(current));
    }

    #[test]
    fn native_sizing_completion_ack_is_atomic_and_cleans_up_on_destroy() {
        let mut sizing = NativeSizing::default();
        let (idle, completion) = sizing.wait_for_idle();
        assert_eq!(idle, 0);
        assert!(completion.is_none());
        let first = sizing.begin(10);
        let (_, completion) = sizing.wait_for_idle();
        let mut completion = completion.unwrap();
        assert!(matches!(
            completion.try_recv(),
            Err(tokio::sync::oneshot::error::TryRecvError::Empty)
        ));
        let newer = sizing.begin(11);
        assert!(!sizing.complete(first));
        assert!(matches!(
            completion.try_recv(),
            Err(tokio::sync::oneshot::error::TryRecvError::Empty)
        ));
        assert!(sizing.complete(newer));
        assert_eq!(completion.try_recv().unwrap(), newer.revision);
        let (idle, completion) = sizing.wait_for_idle();
        assert_eq!(idle, newer.revision);
        assert!(completion.is_none());
        let interrupted = sizing.begin(12);
        let (_, completion) = sizing.wait_for_idle();
        let mut completion = completion.unwrap();
        sizing.destroyed();
        assert_eq!(completion.try_recv().unwrap(), interrupted.revision);
        assert!(sizing.current.is_none());
    }

    #[test]
    fn native_resize_width_commit_requires_the_same_visible_popup_epoch() {
        let token = SizingToken {
            revision: 1,
            epoch: 12,
        };
        let shown = crate::translation_requests::Presentation {
            epoch: 12,
            presented: true,
        };
        assert!(may_remember_native_resize(token, shown, true, true));
        assert!(!may_remember_native_resize(token, shown, false, true));
        assert!(!may_remember_native_resize(token, shown, true, false));
        assert!(!may_remember_native_resize(
            token,
            crate::translation_requests::Presentation { epoch: 13, ..shown },
            true,
            true
        ));
        assert!(!may_remember_native_resize(
            token,
            crate::translation_requests::Presentation {
                presented: false,
                ..shown
            },
            true,
            true
        ));
    }

    #[test]
    fn native_completion_commits_actual_width_before_a_late_dom_measurement() {
        let mut popup = PopupWidth::new(None);
        let work = area(3000.0);
        popup.applied(680.0, 2.0, work);
        // The previous implementation rejected a lagging DOM width and then
        // applied preferred=680 over the user's already-expanded native720.
        assert!(!popup.observe_user_width(true, 720.0, Some(700.0), 2.0, work));
        assert_eq!(popup.preferred, 680.0);
        let mut sizing = NativeSizing::default();
        let token = sizing.begin(12);
        assert!(sizing.current.is_some()); // fit must not mutate geometry now.
        assert!(popup.observe_user_width(true, 720.0, Some(720.0), 2.0, work));
        popup.applied(720.0, 2.0, work);
        assert!(sizing.complete(token));
        assert!(!popup.observe_user_width(true, 720.0, Some(700.0), 2.0, work));
        assert_eq!(
            content_size(false, 240.0, popup.preferred, (1484.0, 900.0)).0,
            720.0
        );
    }

    #[test]
    fn saved_layout_is_bounded_versioned_and_has_no_content_fields() {
        for bytes in [
            b"{}".as_slice(),
            b"not JSON",
            b"{\"version\":1,\"popupWidth\":0}",
            b"{\"version\":1,\"popupWidth\":-850}",
            b"{\"version\":1,\"popupWidth\":100001}",
            b"{\"version\":2,\"popupWidth\":850}",
            b"{\"version\":1,\"popupWidth\":850,\"text\":\"unexpected\"}",
        ] {
            assert_eq!(saved_width(bytes), None);
        }
        assert_eq!(saved_width(&vec![b' '; 4097]), None);
        assert_eq!(PopupWidth::new(Some(f64::NAN)).preferred, 680.0);
        assert_eq!(PopupWidth::new(Some(f64::INFINITY)).preferred, 680.0);
        assert_eq!(
            saved_width(b"{\"version\":1,\"popupWidth\":1250.5}"),
            Some(1250.5)
        );
    }

    #[test]
    fn resize_requires_current_visible_popup_and_only_horizontal_directions() {
        let visible = crate::translation_requests::Presentation {
            epoch: 7,
            presented: true,
        };
        assert!(resize_allowed(7, visible, true, true));
        assert!(!resize_allowed(6, visible, true, true));
        assert!(!resize_allowed(7, visible, false, true));
        assert!(!resize_allowed(7, visible, true, false));
        assert!(!resize_allowed(
            7,
            crate::translation_requests::Presentation {
                presented: false,
                ..visible
            },
            true,
            true
        ));
        assert!(resize_direction("west").is_ok());
        assert!(resize_direction("east").is_ok());
        assert!(resize_direction("north").is_err());
    }

    #[test]
    fn management_resize_requires_exact_presentation_and_limits_popup_to_horizontal() {
        let shown = crate::translation_requests::Presentation {
            epoch: 9,
            presented: true,
        };
        assert!(resize_presentation_allowed(9, shown, false, true, true));
        assert!(!resize_presentation_allowed(9, shown, true, true, true));
        assert!(!resize_presentation_allowed(9, shown, false, false, true));
        assert!(!resize_presentation_allowed(8, shown, false, true, true));
        assert!(!resize_presentation_allowed(
            9,
            crate::translation_requests::Presentation {
                presented: false,
                ..shown
            },
            false,
            true,
            true
        ));
        for name in [
            "west",
            "east",
            "north",
            "south",
            "north-west",
            "north-east",
            "south-west",
            "south-east",
        ] {
            assert!(native_resize_direction(name, true).is_ok());
            assert_eq!(
                native_resize_direction(name, false).is_ok(),
                name == "west" || name == "east"
            );
        }
        for name in ["", "North", "move", "south east"] {
            assert!(resize_edges(name).is_err());
        }
    }

    #[test]
    fn management_edges_keep_opposite_anchor_and_do_not_change_the_other_axis() {
        let area = Bounds {
            x: -1920.0,
            y: -200.0,
            width: 3840.0,
            height: 2400.0,
        };
        let old = (640.0, 720.0);
        let position = (-1000, 0);
        let frame = (0.0, 28.0);
        for name in [
            "west",
            "east",
            "north",
            "south",
            "north-west",
            "north-east",
            "south-west",
            "south-east",
        ] {
            let edges = resize_edges(name).unwrap();
            let (size, next) =
                management_resize_geometry(edges, old, (700.0, 760.0), position, frame, area, 2.0);
            assert_eq!(size.0, if edges.0 == 0 { 640.0 } else { 700.0 });
            assert_eq!(size.1, if edges.1 == 0 { 720.0 } else { 760.0 });
            assert_eq!(next.0, if edges.0 < 0 { -1120 } else { -1000 });
            assert_eq!(next.1, if edges.1 < 0 { -80 } else { 0 });
        }
        let small = Bounds {
            x: -800.0,
            y: -100.0,
            width: 800.0,
            height: 650.0,
        };
        let (size, next) = management_resize_geometry(
            (1, 1),
            old,
            (4000.0, 4000.0),
            (-600, 0),
            (16.0, 44.0),
            small,
            1.0,
        );
        assert_eq!(size, (768.0, 582.0));
        assert!(
            f64::from(next.0) >= small.x
                && f64::from(next.0) + size.0 + 16.0 <= small.x + small.width
        );
        assert!(
            f64::from(next.1) >= small.y
                && f64::from(next.1) + size.1 + 44.0 <= small.y + small.height
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

    #[test]
    fn west_resize_preserves_physical_right_anchor_at_retina_scale() {
        let area = Bounds {
            x: -1920.0,
            y: 0.0,
            width: 3840.0,
            height: 2160.0,
        };
        let west = resize_position(
            area,
            (-1000, 200),
            680.0,
            850.0,
            300.0,
            2.0,
            HorizontalResize::West,
        );
        assert_eq!(west, (-1340, 200));
        assert_eq!(f64::from(west.0) + 850.0 * 2.0, -1000.0 + 680.0 * 2.0);
        assert_eq!(
            resize_position(
                area,
                (-1000, 200),
                680.0,
                850.0,
                300.0,
                2.0,
                HorizontalResize::East
            ),
            (-1000, 200)
        );
    }

    #[test]
    fn persistence_round_trip_keeps_only_popup_width() {
        let directory = std::env::temp_dir().join(format!(
            "echolingo-layout-fixture-{}-{}",
            std::process::id(),
            crate::now()
        ));
        std::fs::create_dir(&directory).unwrap();
        let state = LayoutState::new(directory.clone());
        assert!(state.popup.lock().unwrap().remember(850.0));
        state.flush().unwrap();
        let restored = LayoutState::new(directory.clone());
        assert_eq!(restored.popup.lock().unwrap().preferred, 850.0);
        let bytes = std::fs::read(directory.join(LAYOUT_FILE)).unwrap();
        let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(value, serde_json::json!({"version":1,"popupWidth":850.0}));
        std::fs::remove_dir_all(directory).unwrap();
    }
}
