//! Run blocking capture/clipboard operations on `tauri::async_runtime::spawn_blocking`.
//! Showing a nonactivating window is the exception and requires the main thread.
//! In particular, do not activate the EchoLingo window before `selected_text`.

use serde_json::{json, Value};

#[cfg(any(target_os = "windows", test))]
#[path = "capture_exclusion.rs"]
mod capture_exclusion;
#[cfg(target_os = "windows")]
pub use capture_exclusion::CaptureWindowExclusion;

const NATIVE_CANCELLED: &str = "CANCELLED: Native task was superseded.";
type NativeCancel = std::sync::Arc<std::sync::atomic::AtomicBool>;
fn cancelled(cancel: Option<&NativeCancel>) -> bool {
    cancel.is_some_and(|c| c.load(std::sync::atomic::Ordering::SeqCst))
}

pub fn selected_text_cancelable(cancel: NativeCancel) -> Result<String, String> {
    cancellable_text("selected-text", cancel)
}
pub fn capture_ocr_cancelable(cancel: NativeCancel) -> Result<String, String> {
    cancellable_text("capture-ocr", cancel)
}
pub fn capture_image_cancelable(cancel: NativeCancel) -> Result<String, String> {
    image_response(run_cancelable("capture-image", cancel)?)
}
fn cancellable_text(mode: &str, cancel: NativeCancel) -> Result<String, String> {
    run_cancelable(mode, cancel)?
        .get("text")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| "NATIVE_PROTOCOL: Native helper returned no text field.".into())
}
fn run_cancelable(mode: &str, cancel: NativeCancel) -> Result<Value, String> {
    if cancelled(Some(&cancel)) {
        return Err(NATIVE_CANCELLED.into());
    }
    #[cfg(target_os = "windows")]
    {
        run_windows(mode, None, Some(cancel))
    }
    #[cfg(not(target_os = "windows"))]
    {
        let result = run(mode, None);
        if cancelled(Some(&cancel)) {
            Err(NATIVE_CANCELLED.into())
        } else {
            result
        }
    }
}

#[derive(Clone, Copy)]
pub struct NativeSourceSnapshot {
    #[cfg(target_os = "windows")]
    window: isize,
    #[cfg(target_os = "windows")]
    process: u32,
    #[cfg(target_os = "windows")]
    thread: u32,
    #[cfg(target_os = "windows")]
    focus: isize,
}
impl NativeSourceSnapshot {
    pub fn is_current(&self) -> bool {
        native_source_is_current(self)
    }
}
pub fn native_source_snapshot() -> Result<NativeSourceSnapshot, String> {
    #[cfg(target_os = "windows")]
    {
        native_process::source_snapshot()
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(NativeSourceSnapshot {})
    }
}
pub fn native_source_is_current(expected: &NativeSourceSnapshot) -> bool {
    #[cfg(target_os = "windows")]
    {
        native_process::source_snapshot().is_ok_and(|now| {
            now.window == expected.window
                && now.process == expected.process
                && now.thread == expected.thread
                && now.focus == expected.focus
        })
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = expected;
        true
    }
}

pub fn selected_text() -> Result<String, String> {
    run_text("selected-text", None)
}

pub fn capture_ocr() -> Result<String, String> {
    run_text("capture-ocr", None)
}

/// Capture only. The caller chooses whether to submit this PNG to a configured
/// third-party OCR API; the native helper performs no upload or network request.
pub fn capture_image() -> Result<String, String> {
    image_response(run("capture-image", None)?)
}
fn image_response(result: Value) -> Result<String, String> {
    result
        .get("imageBase64")
        .and_then(Value::as_str)
        .filter(|image| !image.is_empty() && image.len() <= (8usize * 1024 * 1024).div_ceil(3) * 4)
        .map(str::to_owned)
        .ok_or_else(|| {
            "NATIVE_PROTOCOL: Native helper returned an empty or oversized PNG imageBase64 field."
                .into()
        })
}

pub fn clipboard_text() -> Result<String, String> {
    run_text("clipboard", None)
}

pub async fn detect_language(text: &str) -> Result<String, String> {
    if text.trim().is_empty() || text.chars().count() > 20_000 {
        return Err("语言检测的文本无效".into());
    }
    #[cfg(target_os = "macos")]
    {
        let text = text.to_owned();
        tauri::async_runtime::spawn_blocking(move || run_text("detect-language", Some(&text)))
            .await
            .map_err(|_| "本机语言检测未能完成".to_string())?
    }
    #[cfg(not(target_os = "macos"))]
    {
        crate::language_detection::fallback_language(text).ok_or_else(|| "无法确认原文语言".into())
    }
}

pub fn copy_text(text: &str) -> Result<(), String> {
    if text.len() > 2 * 1024 * 1024 {
        return Err("CLIPBOARD: Text exceeds the 2 MiB clipboard safety limit.".into());
    }
    run_text("copy", Some(text)).map(|_| ())
}

/// Query current/recent left/right button activity and pointer position without
/// hooks, event taps, input synthesis, or permission prompts. macOS supplements
/// current state with press counters; Windows uses best-effort recent-press bits.
/// The caller must discard the first sample whenever its window becomes visible.
/// Windows coordinates are
/// physical screen pixels. macOS coordinates are top-left global logical points:
/// multiply BOTH coordinates by this window's `scale_factor()` before comparing
/// against that window's Tauri `outer_position()` and `outer_size()` pixels.
#[cfg(target_os = "windows")]
pub fn pointer_state() -> Result<(bool, f64, f64), String> {
    #[repr(C)]
    struct Point {
        x: i32,
        y: i32,
    }
    #[link(name = "user32")]
    unsafe extern "system" {
        fn GetAsyncKeyState(key: i32) -> i16;
        fn GetCursorPos(point: *mut Point) -> i32;
    }
    let mut point = Point { x: 0, y: 0 };
    // SAFETY: User32 receives a valid writable POINT. Only the left/right mouse
    // button virtual keys are queried, and no input is generated or consumed.
    let down = unsafe {
        if GetCursorPos(&mut point) == 0 {
            return Err(format!(
                "POINTER_UNAVAILABLE: Cannot query the current desktop pointer: {}",
                std::io::Error::last_os_error()
            ));
        }
        // Query both keys on every call. The low "pressed since last query" bit
        // helps catch short clicks, but Windows documents that other processes
        // may consume it, so it cannot replace current-state polling.
        let left = GetAsyncKeyState(0x01) as u16;
        let right = GetAsyncKeyState(0x02) as u16;
        (left | right) & 0x8001 != 0
    };
    Ok((down, f64::from(point.x), f64::from(point.y)))
}

#[cfg(target_os = "macos")]
pub fn pointer_state() -> Result<(bool, f64, f64), String> {
    use std::ffi::c_void;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
    static PREVIOUS_COUNTS: AtomicU64 = AtomicU64::new(0);
    static INITIALIZED: AtomicBool = AtomicBool::new(false);
    #[repr(C)]
    struct Point {
        x: f64,
        y: f64,
    }
    #[link(name = "CoreGraphics", kind = "framework")]
    unsafe extern "C" {
        fn CGEventSourceButtonState(source: i32, button: u32) -> bool;
        fn CGEventSourceCounterForEventType(source: i32, event_type: u32) -> u32;
        fn CGEventCreate(source: *const c_void) -> *const c_void;
        fn CGEventGetLocation(event: *const c_void) -> Point;
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        fn CFRelease(object: *const c_void);
    }
    // SAFETY: A null source creates a read-only snapshot of current event state.
    // The retained event is released exactly once after reading its coordinates.
    // This never installs an event tap, posts an event, or asks for input access.
    let (down, point, counts) = unsafe {
        let event = CGEventCreate(std::ptr::null());
        if event.is_null() {
            return Err("POINTER_UNAVAILABLE: Cannot query the current desktop pointer.".into());
        }
        let point = CGEventGetLocation(event);
        CFRelease(event);
        let down = CGEventSourceButtonState(0, 0) || CGEventSourceButtonState(0, 1);
        let left = CGEventSourceCounterForEventType(0, 1);
        let right = CGEventSourceCounterForEventType(0, 3);
        (down, point, (u64::from(left) << 32) | u64::from(right))
    };
    if !point.x.is_finite() || !point.y.is_finite() {
        return Err("POINTER_UNAVAILABLE: Desktop pointer coordinates are not finite.".into());
    }
    // One visible-window watcher consumes these counters. Counts contain no
    // pointer coordinates or text, and are never logged or persisted. The first
    // process sample establishes a baseline; the caller also discards a sample
    // after each hidden-to-visible transition to ignore activity while hidden.
    let previous = PREVIOUS_COUNTS.swap(counts, Ordering::Relaxed);
    let initialized = INITIALIZED.swap(true, Ordering::Relaxed);
    Ok((
        down || (initialized && counts != previous),
        point.x,
        point.y,
    ))
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn pointer_state() -> Result<(bool, f64, f64), String> {
    Err("UNSUPPORTED_PLATFORM: Pointer state supports Windows and macOS.".into())
}

/// Restore popup stacking/space behavior without showing, ordering, activating,
/// focusing or moving the window. macOS callers must use the app main thread.
#[cfg(target_os = "windows")]
pub fn popup_has_native_foreground(window: &tauri::WebviewWindow) -> bool {
    window.hwnd().ok().is_some_and(|native| {
        !native.0.is_null() && crate::windows_visibility::foreground_is_owned(native.0 as isize)
    })
}

#[cfg(target_os = "windows")]
pub fn popup_foreground_is_external(window: &tauri::WebviewWindow) -> bool {
    window.hwnd().ok().is_some_and(|native| {
        !native.0.is_null() && crate::windows_visibility::foreground_is_external(native.0 as isize)
    })
}

#[cfg(target_os = "macos")]
pub fn ensure_popup_behavior(window: &tauri::WebviewWindow) -> Result<(), String> {
    use std::ffi::c_void;
    unsafe extern "C" {
        fn pthread_main_np() -> i32;
        fn echolingo_ensure_popup_behavior(window: *mut c_void) -> i32;
    }
    // SAFETY: This only checks the current thread, before obtaining AppKit's
    // borrowed NSWindow. The linked Swift ABI checks the thread again.
    if unsafe { pthread_main_np() } == 0 {
        return Err("WINDOW_THREAD: Popup behavior requires the application main thread.".into());
    }
    let native = window
        .ns_window()
        .map_err(|_| "WINDOW_HANDLE: Native macOS window is unavailable.")?;
    if native.is_null() {
        return Err("WINDOW_HANDLE: Native macOS window is unavailable.".into());
    }
    // SAFETY: Tauri owns this valid NSWindow and the main thread was verified.
    match unsafe { echolingo_ensure_popup_behavior(native) } {
        0 => Ok(()),
        -1 => Err("WINDOW_THREAD: Popup behavior requires the application main thread.".into()),
        -2 => Err("WINDOW_HANDLE: Native macOS window is unavailable.".into()),
        _ => Err("WINDOW_BEHAVIOR: Cannot restore floating popup behavior.".into()),
    }
}

#[cfg(target_os = "windows")]
pub fn ensure_popup_behavior(window: &tauri::WebviewWindow) -> Result<(), String> {
    use std::ffi::c_void;
    #[link(name = "user32")]
    unsafe extern "system" {
        fn SetWindowPos(
            window: *mut c_void,
            insert_after: *mut c_void,
            x: i32,
            y: i32,
            width: i32,
            height: i32,
            flags: u32,
        ) -> i32;
    }
    let native = window
        .hwnd()
        .map_err(|_| "WINDOW_HANDLE: Native Windows window is unavailable.")?
        .0;
    if native.is_null() {
        return Err("WINDOW_HANDLE: Native Windows window is unavailable.".into());
    }
    // SAFETY: Tauri owns the HWND. TOPMOST changes stacking only; NOMOVE,
    // NOSIZE and NOACTIVATE preserve geometry and the foreground application.
    // In particular, SHOWWINDOW is absent so hidden windows remain hidden.
    if unsafe {
        SetWindowPos(
            native,
            -1isize as *mut c_void,
            0,
            0,
            0,
            0,
            0x01 | 0x02 | 0x10,
        )
    } == 0
    {
        return Err("WINDOW_BEHAVIOR: Cannot restore floating popup behavior.".into());
    }
    Ok(())
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn ensure_popup_behavior(_window: &tauri::WebviewWindow) -> Result<(), String> {
    Err("UNSUPPORTED_PLATFORM: Popup behavior supports Windows and macOS.".into())
}

/// Show a floating window while keeping the source application active. The
/// caller MUST invoke this on Tauri's main thread. Do not call `window.show()`
/// first: Tao's macOS implementation makes that window key when showing it.
#[cfg(target_os = "macos")]
pub fn show_without_activation(window: &tauri::WebviewWindow) -> Result<(), String> {
    use std::ffi::{c_char, c_void};
    unsafe extern "C" {
        fn pthread_main_np() -> i32;
    }
    #[link(name = "objc")]
    unsafe extern "C" {
        fn sel_registerName(name: *const c_char) -> *const c_void;
        // Typed for NSWindow::orderFrontRegardless, whose signature is void(id, SEL).
        fn objc_msgSend(receiver: *mut c_void, selector: *const c_void);
    }
    // SAFETY: pthread_main_np only reads the current thread identity.
    if unsafe { pthread_main_np() } == 0 {
        return Err(
            "WINDOW_THREAD: Show the floating window on the application main thread.".into(),
        );
    }
    let native = window
        .ns_window()
        .map_err(|error| format!("WINDOW_HANDLE: {error}"))?;
    if native.is_null() {
        return Err("WINDOW_HANDLE: Native macOS window is unavailable.".into());
    }
    // SAFETY: Tauri owns this valid NSWindow. The selector has no arguments or
    // return value, and AppKit is called on the verified main thread. Ordering
    // does not make the window key/main or activate NSApplication.
    unsafe {
        let selector = sel_registerName(c"orderFrontRegardless".as_ptr());
        objc_msgSend(native, selector);
    }
    Ok(())
}

#[cfg(target_os = "windows")]
pub fn show_without_activation(window: &tauri::WebviewWindow) -> Result<(), String> {
    use std::ffi::c_void;
    #[link(name = "user32")]
    unsafe extern "system" {
        fn ShowWindow(window: *mut c_void, command: i32) -> i32;
        fn SetWindowPos(
            window: *mut c_void,
            insert_after: *mut c_void,
            x: i32,
            y: i32,
            width: i32,
            height: i32,
            flags: u32,
        ) -> i32;
    }
    let native = window
        .hwnd()
        .map_err(|error| format!("WINDOW_HANDLE: {error}"))?
        .0;
    if native.is_null() {
        return Err("WINDOW_HANDLE: Native Windows window is unavailable.".into());
    }
    // SAFETY: Tauri owns the HWND. SW_SHOWNOACTIVATE and SWP_NOACTIVATE preserve
    // the foreground application; TOPMOST raises only this window's z-order.
    let positioned = unsafe {
        ShowWindow(native, 4);
        SetWindowPos(
            native,
            -1isize as *mut c_void,
            0,
            0,
            0,
            0,
            0x01 | 0x02 | 0x10 | 0x40,
        )
    };
    if positioned == 0 {
        return Err(format!(
            "WINDOW_SHOW: Cannot show floating window without activation: {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

/// Keep Tao's visibility bookkeeping and the actual native window in sync.
/// A passive Windows show bypasses Tao's VISIBLE flag, so its hide alone can
/// return successfully without changing the HWND. Never show or focus here.
#[cfg(target_os = "windows")]
pub fn hide_window(window: &tauri::Window) -> Result<(), String> {
    use std::ffi::c_void;
    #[link(name = "user32")]
    unsafe extern "system" {
        fn ShowWindow(window: *mut c_void, command: i32) -> i32;
        fn IsWindowVisible(window: *mut c_void) -> i32;
    }
    // Update the runtime's cache first, even if the native window was shown by
    // SW_SHOWNOACTIVATE while Tao still considered it hidden.
    let cached_hide = window.hide().map_err(|_| "无法隐藏窗口".to_owned());
    let native = window
        .hwnd()
        .map_err(|_| "WINDOW_HANDLE: Native Windows window is unavailable.".to_owned())?
        .0;
    if native.is_null() {
        return Err("WINDOW_HANDLE: Native Windows window is unavailable.".into());
    }
    finish_window_hide(
        cached_hide,
        || {
            // SAFETY: Tauri owns the HWND. SW_HIDE only hides it. ShowWindow's
            // return value reports previous visibility, not operation success.
            unsafe {
                ShowWindow(native, 0);
            }
        },
        || unsafe { IsWindowVisible(native) != 0 },
    )
}

#[cfg(not(target_os = "windows"))]
pub fn hide_window(window: &tauri::Window) -> Result<(), String> {
    window.hide().map_err(|_| "无法隐藏窗口".to_owned())
}

/// WebviewWindow exposes its owning Window through AsRef<Webview>. Keep one
/// actual hide implementation for this adapter and CloseRequested's Window.
pub fn hide_webview_window(window: &tauri::WebviewWindow) -> Result<(), String> {
    let webview: &tauri::Webview = window.as_ref();
    hide_window(&webview.window())
}

#[cfg(any(target_os = "windows", test))]
fn finish_window_hide(
    cached_hide: Result<(), String>,
    native_hide: impl FnOnce(),
    native_visible: impl FnOnce() -> bool,
) -> Result<(), String> {
    // A cached no-op or dispatch error must not skip the native hide attempt.
    native_hide();
    if native_visible() {
        return Err("WINDOW_HIDE: 隐藏后窗口仍然可见，请重试。".into());
    }
    cached_hide
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn show_without_activation(_window: &tauri::WebviewWindow) -> Result<(), String> {
    Err("UNSUPPORTED_PLATFORM: Nonactivating windows support Windows and macOS.".into())
}

pub fn diagnostics() -> Value {
    let value = match run("diagnostics", None) {
        Ok(result) => result.get("diagnostics").cloned().unwrap_or(result),
        Err(error) => {
            json!({ "platform": std::env::consts::OS, "available": false, "error": error })
        }
    };
    #[cfg(target_os = "windows")]
    {
        let mut value = value;
        value["captureExclusion"] = capture_exclusion::last_diagnostics();
        value["lastCaptureHealth"] = windows_capture_health()
            .lock()
            .map(|v| v.clone())
            .unwrap_or(Value::Null);
        value["lastSelectionHealth"] = selection_diagnostics().unwrap_or(Value::Null);
        value
    }
    #[cfg(not(target_os = "windows"))]
    value
}

#[cfg(target_os = "windows")]
fn windows_capture_health() -> &'static std::sync::Mutex<Value> {
    static HEALTH: std::sync::OnceLock<std::sync::Mutex<Value>> = std::sync::OnceLock::new();
    HEALTH.get_or_init(|| std::sync::Mutex::new(Value::Null))
}

#[cfg(target_os = "windows")]
fn windows_selection_health() -> &'static std::sync::Mutex<Value> {
    static HEALTH: std::sync::OnceLock<std::sync::Mutex<Value>> = std::sync::OnceLock::new();
    HEALTH.get_or_init(|| std::sync::Mutex::new(Value::Null))
}

#[cfg(any(target_os = "windows", test))]
const SELECTION_HEALTH_MAX: u64 = 10_000_000;

#[cfg(any(target_os = "windows", test))]
fn bounded_selection_health(value: &Value) -> Value {
    const SUFFIXES: &[&str] = &[
        "Stage",
        "Depth",
        "IdentityCompared",
        "IdentityEqual",
        "RootWalkReason",
        "ExceptionKind",
        "Milliseconds",
    ];
    let mut safe = serde_json::Map::new();
    let mut retain = |field: &str| {
        if let Some(number) = value
            .get(field)
            .and_then(Value::as_u64)
            .filter(|number| *number <= SELECTION_HEALTH_MAX)
        {
            safe.insert(field.to_owned(), json!(number));
        }
    };
    retain("selectionQueryCount");
    for index in 1..=16 {
        for suffix in SUFFIXES {
            retain(&format!("selectionQuery{index}{suffix}"));
        }
    }
    Value::Object(safe)
}

#[cfg(any(target_os = "windows", test))]
fn selection_health_from_reply(
    reply: &Value,
    elapsed_milliseconds: u64,
    cancellation_requested: bool,
    cancellation_signalled: bool,
    cancellation_signal_failed: bool,
) -> Value {
    let mut safe = bounded_selection_health(&reply["captureHealth"]);
    // These fields describe our process boundary, never untrusted helper data.
    safe["helperResponseReceived"] = json!(u64::from(reply.is_object()));
    safe["helperElapsedMilliseconds"] = json!(elapsed_milliseconds.min(SELECTION_HEALTH_MAX));
    safe["cancellationRequested"] = json!(u64::from(cancellation_requested));
    safe["cancellationSignalled"] = json!(u64::from(cancellation_signalled));
    safe["cancellationSignalFailed"] = json!(u64::from(cancellation_signal_failed));
    safe
}

#[cfg(any(target_os = "windows", test))]
fn bounded_capture_health(value: &Value) -> Value {
    const FIELDS: &[&str] = &[
        "hookMouseDowns",
        "hookMouseUps",
        "hookMouseMoves",
        "hookEscapeDowns",
        "hookEscapeUps",
        "moveWakesPosted",
        "movePostFailures",
        "uiPhase",
        "inputArmed",
        "leftSwallowed",
        "physicalLeftDown",
        "dragging",
        "knownPointer",
        "desktopMatched",
        "mismatchKind",
        "hookRunningAfterStop",
        "inputBackend",
        "mouseHookInstalled",
        "inputPlaneDowns",
        "inputPlaneUps",
        "inputPlaneMoves",
        "inputPlaneCount",
        "inputPlaneVisibleCount",
        "inputPlaneRemainingAfterCleanup",
        "inputPlaneFallbackUsed",
        "releaseToPngMilliseconds",
        "releaseToCleanupMilliseconds",
        "releaseToReplyMilliseconds",
        "ocrDurationMilliseconds",
        "nativeHostReady",
        "nativeHostArmed",
        "nativeHostDowns",
        "nativeHostUps",
        "nativeHostMoves",
        "nativeHostStopped",
        "nativeHostFailed",
    ];
    let mut safe = serde_json::Map::new();
    for field in FIELDS {
        if let Some(number) = value.get(field).and_then(Value::as_u64) {
            safe.insert((*field).to_owned(), json!(number));
        }
    }
    Value::Object(safe)
}

/// Read the bounded metadata of the last selected-text attempt in this process.
/// This does not capture text, query other applications or request permissions.
#[cfg(target_os = "macos")]
pub fn selection_diagnostics() -> Result<Value, String> {
    run("selection-diagnostics", None)?
        .get("diagnostics")
        .filter(|value| value.is_object())
        .cloned()
        .ok_or_else(|| "NATIVE_PROTOCOL: Missing selection diagnostics.".into())
}

#[cfg(target_os = "windows")]
pub fn selection_diagnostics() -> Result<Value, String> {
    Ok(windows_selection_health()
        .lock()
        .map(|value| value.clone())
        .unwrap_or(Value::Null))
}

/// A read-only preflight. This never requests a permission or opens Settings.
/// On macOS the Swift library executes inside this app, giving TCC one app
/// identity rather than a second executable materialized in the user cache.
pub fn permission_status() -> Result<Value, String> {
    #[cfg(target_os = "macos")]
    {
        return run("permissions", None)?
            .get("permissions")
            .filter(|value| value.is_object())
            .cloned()
            .ok_or_else(|| "NATIVE_PROTOCOL: Missing native permission status.".into());
    }
    #[cfg(not(target_os = "macos"))]
    Ok(json!({
        "platform": std::env::consts::OS,
        "supported": false,
        "identity": "system-native",
        "runningBundledApp": false,
        "bundleIdentifier": "",
        "processId": std::process::id(),
        "accessibilityGranted": cfg!(target_os = "windows"),
        "screenCaptureGranted": cfg!(target_os = "windows")
    }))
}

fn validate_permission_kind(kind: &str) -> Result<(), String> {
    match kind {
        "accessibility" | "screenCapture" => Ok(()),
        _ => Err("PERMISSION_KIND: 不支持的权限类型。".into()),
    }
}

/// Call only for an explicit user action in Settings, never from a hotkey or
/// startup. macOS schedules the actual system permission request on main.
pub fn request_permission(kind: &str) -> Result<Value, String> {
    validate_permission_kind(kind)?;
    #[cfg(target_os = "macos")]
    {
        return run(&format!("request-{kind}"), None)?
            .get("permissions")
            .filter(|value| value.is_object())
            .cloned()
            .ok_or_else(|| "NATIVE_PROTOCOL: Missing native permission status.".into());
    }
    #[cfg(not(target_os = "macos"))]
    Err("PERMISSION_UNSUPPORTED: 此平台不需要 macOS 隐私授权。".into())
}

/// Open only one of two fixed privacy panes. No arbitrary URL is accepted.
pub fn open_permission_settings(kind: &str) -> Result<(), String> {
    validate_permission_kind(kind)?;
    #[cfg(target_os = "macos")]
    {
        return run(&format!("open-settings-{kind}"), None).map(|_| ());
    }
    #[cfg(not(target_os = "macos"))]
    Err("PERMISSION_UNSUPPORTED: 此平台不需要 macOS 隐私授权。".into())
}

fn system_translation_input(
    source: &str,
    target: &str,
    text: Option<&str>,
) -> Result<String, String> {
    let language = |value: &str| {
        !value.is_empty()
            && value.len() <= 40
            && value
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'-')
    };
    if !language(source) || !language(target) || target == "auto" {
        return Err("系统翻译的语言参数无效".into());
    }
    if text.is_some_and(|text| text.trim().is_empty() || text.chars().count() > 20_000) {
        return Err("系统翻译需要 1–20,000 字符的文本".into());
    }
    serde_json::to_string(&json!({"source":source,"target":target,"text":text}))
        .map_err(|_| "无法准备系统翻译参数".into())
}

pub fn system_translation_status(source: &str, target: &str) -> Result<Value, String> {
    let input = system_translation_input(source, target, None)?;
    #[cfg(target_os = "macos")]
    {
        let result = run("system-translation-status", Some(&input))?;
        let mut status = result
            .get("systemTranslation")
            .filter(|v| v.is_object())
            .cloned()
            .ok_or_else(|| "NATIVE_PROTOCOL: 系统翻译状态不可用。".to_string())?;
        status["ready"] = json!(status
            .get("available")
            .and_then(Value::as_bool)
            .unwrap_or(false));
        Ok(status)
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = input;
        Ok(json!({
            "platform":std::env::consts::OS,"supported":false,"ready":false,
            "requiresSetup":false,"status":"unsupported",
            "message":"此系统暂无通用系统翻译接口。Windows 安装包可使用“本机离线翻译”进行中英互译，也可配置自己的 API。"
        }))
    }
}

/// Explicit Settings action only. This may show Apple's language-download UI;
/// translation/hotkeys/status checks never invoke it.
pub fn prepare_system_translation(source: &str, target: &str) -> Result<Value, String> {
    let input = system_translation_input(source, target, None)?;
    #[cfg(target_os = "macos")]
    {
        run("prepare-system-translation", Some(&input))?;
        system_translation_status(source, target)
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = input;
        Err("此平台尚不支持系统文本翻译，请配置翻译 API".into())
    }
}

pub async fn system_translate(text: &str, source: &str, target: &str) -> Result<String, String> {
    let input = system_translation_input(source, target, Some(text))?;
    #[cfg(target_os = "macos")]
    {
        use std::sync::{
            atomic::{AtomicBool, AtomicU64, Ordering},
            Arc, OnceLock,
        };
        static SERIAL: OnceLock<Arc<tokio::sync::Semaphore>> = OnceLock::new();
        static NEXT: AtomicU64 = AtomicU64::new(0);
        // Keep capacity in the blocking worker even if its JoinHandle is dropped.
        let permit = SERIAL
            .get_or_init(|| Arc::new(tokio::sync::Semaphore::new(1)))
            .clone()
            .try_acquire_owned()
            .map_err(|_| "上一次系统翻译正在结束，请稍后重试".to_string())?;
        let operation_id = format!(
            "rust-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        );
        let mut input: Value = serde_json::from_str(&input).map_err(|_| "系统翻译参数无效")?;
        input["operationId"] = json!(operation_id);
        let input = input.to_string();
        let mut cancellation = SystemTranslationCancellation {
            operation_id,
            cancelled: Arc::new(AtomicBool::new(false)),
            finished: false,
        };
        let cancelled = cancellation.cancelled.clone();
        let result = tauri::async_runtime::spawn_blocking(move || {
            let _permit = permit;
            if cancelled.load(Ordering::Acquire) {
                return Err("SYSTEM_TRANSLATION_CANCELLED: 已取消系统翻译。".into());
            }
            run_text("system-translate", Some(&input))
        })
        .await
        .map_err(|_| "系统翻译任务未能完成".to_string())?;
        cancellation.finished = true;
        result.and_then(|result| {
            if result.trim().is_empty() || result.len() > 2 * 1024 * 1024 {
                Err("系统翻译返回的译文为空或超过大小上限".into())
            } else {
                Ok(result)
            }
        })
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = input;
        Err("此平台尚不支持系统文本翻译，请在设置中配置翻译 API".into())
    }
}

#[cfg(target_os = "macos")]
struct SystemTranslationCancellation {
    operation_id: String,
    cancelled: std::sync::Arc<std::sync::atomic::AtomicBool>,
    finished: bool,
}

#[cfg(target_os = "macos")]
impl Drop for SystemTranslationCancellation {
    fn drop(&mut self) {
        if !self.finished {
            self.cancelled
                .store(true, std::sync::atomic::Ordering::Release);
            // Fast C ABI cancellation of this Swift Task only; no source text,
            // AppKit dispatch, prompt, keychain access or waiting.
            let input = json!({"operationId":self.operation_id}).to_string();
            let _ = run("cancel-system-translation", Some(&input));
        }
    }
}

fn run_text(mode: &str, input: Option<&str>) -> Result<String, String> {
    let result = run(mode, input)?;
    result
        .get("text")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| "NATIVE_PROTOCOL: Native helper returned no text field.".into())
}

fn parse_response(bytes: &[u8], successful: bool) -> Result<Value, String> {
    let value: Value = serde_json::from_slice(bytes)
        .map_err(|_| "NATIVE_PROTOCOL: Native helper returned invalid JSON. Check the platform prerequisites in docs/native-testing.md.".to_string())?;
    if value.get("ok").and_then(Value::as_bool) == Some(true) && successful {
        return Ok(value);
    }
    Err(value
        .get("error")
        .and_then(Value::as_str)
        .unwrap_or("NATIVE: The native operation failed.")
        .to_owned())
}

#[cfg(any(target_os = "windows", test))]
fn native_forced_stop_error(mode: &str, reason: &str) -> String {
    if mode == "selected-text" {
        format!("CLIPBOARD_RESTORE_SKIPPED: Selection helper was forcibly stopped before its cleanup could be confirmed. Current clipboard contents were preserved; restoration is uncertain. {reason}")
    } else {
        reason.to_owned()
    }
}

#[cfg(target_os = "windows")]
fn run(mode: &str, input: Option<&str>) -> Result<Value, String> {
    run_windows(mode, input, None)
}
#[cfg(target_os = "windows")]
fn run_windows(
    mode: &str,
    input: Option<&str>,
    cancel: Option<NativeCancel>,
) -> Result<Value, String> {
    use std::io::{Read, Write};
    use std::process::Stdio;
    use std::time::{Duration, Instant};

    let capture = matches!(mode, "capture-ocr" | "capture-image");
    let selection = mode == "selected-text";
    if selection {
        if let Ok(mut health) = windows_selection_health().lock() {
            *health = json!({"helperResponseReceived": 0});
        }
    }
    if capture {
        if let Ok(mut health) = windows_capture_health().lock() {
            *health = json!({"helperResponseReceived": 0});
        }
    }

    if cancelled(cancel.as_ref()) {
        return Err(NATIVE_CANCELLED.into());
    }
    let source = if mode == "selected-text" {
        Some(native_source_snapshot()?)
    } else {
        None
    };
    if capture || mode == "selected-text" {
        crate::windows_capture_input::wait_available(|| cancelled(cancel.as_ref()))?;
    }
    let mut command = native_command(mode)?;
    let mut cancellation = if cancel.is_some() {
        Some(native_process::CancellationEvent::new()?)
    } else {
        None
    };
    if let Some(event) = &cancellation {
        command.args(["-NativeCancellationEvent", event.name()]);
    }
    let mut capture_session = if capture {
        Some(crate::windows_capture_input::Session::begin()?)
    } else {
        None
    };
    if let Some(session) = &capture_session {
        command.args([
            "-CaptureHostThreadId",
            &session.thread().to_string(),
            "-CaptureHostToken",
            &session.token().to_string(),
        ]);
    }
    command
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if cancelled(cancel.as_ref()) {
        return Err(NATIVE_CANCELLED.into());
    }
    if source.is_some_and(|expected| !expected.is_current()) {
        return Err(
            "CANCELLED: The source application changed while the previous native task was ending."
                .into(),
        );
    }
    let helper_started = Instant::now();
    let mut child = command
        .spawn()
        .map_err(|error| format!("NATIVE_START: Could not start the system helper: {error}"))?;
    if let Some(session) = &capture_session {
        session.bind_child(child.id());
    }
    // Drain both pipes concurrently so a long OCR result cannot deadlock wait().
    let stdout = child.stdout.take().ok_or("NATIVE: Missing output pipe.")?;
    let stderr = child.stderr.take().ok_or("NATIVE: Missing error pipe.")?;
    let read_pipe = |pipe: Box<dyn Read + Send>, limit: u64| {
        std::thread::spawn(move || {
            let mut bytes = Vec::new();
            pipe.take(limit).read_to_end(&mut bytes).map(|_| bytes)
        })
    };
    // An 8 MiB PNG expands to about 10.7 MiB of base64 plus the JSON envelope.
    let output_limit = if mode == "capture-image" { 12 } else { 4 } * 1024 * 1024;
    let output_thread = read_pipe(Box::new(stdout), output_limit);
    let error_thread = read_pipe(Box::new(stderr), 4 * 1024 * 1024);
    let input_thread = if let Some(text) = input {
        let mut stdin = child.stdin.take().ok_or("NATIVE: Missing input pipe.")?;
        let bytes = text.as_bytes().to_vec();
        Some(std::thread::spawn(move || stdin.write_all(&bytes)))
    } else {
        None
    };
    // Helpers cancel their own picker after 120 seconds and OCR after 30 seconds.
    // The longer outer limit gives them time to dispose images and temporary files.
    let limit = if matches!(mode, "capture-ocr" | "capture-image") {
        180
    } else {
        60
    };
    let deadline = Instant::now() + Duration::from_secs(limit);
    let mut cancellation_requested = false;
    let mut cancellation_signalled = false;
    let mut cancellation_signal_failed = false;
    let status = loop {
        if !cancellation_requested && cancelled(cancel.as_ref()) {
            cancellation_requested = true;
            if let Some(event) = &mut cancellation {
                cancellation_signalled = event.signal();
                cancellation_signal_failed = !cancellation_signalled;
            }
            if cancellation_signal_failed && capture {
                if let Ok(mut health) = windows_capture_health().lock() {
                    health["cancellationSignalFailed"] = json!(1);
                }
            }
        }
        let wait_result = native_process::wait_child(&child, 30);
        match wait_result.and_then(|_| child.try_wait()) {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => {}
            Ok(None) => {
                if let Some(session) = &mut capture_session {
                    session.close();
                }
                let _ = child.kill();
                let _ = child.wait();
                return Err(native_forced_stop_error(
                    mode,
                    "NATIVE_TIMEOUT: The system helper stopped responding.",
                ));
            }
            Err(error) => {
                if let Some(session) = &mut capture_session {
                    session.close();
                }
                let _ = child.kill();
                let _ = child.wait();
                return Err(native_forced_stop_error(
                    mode,
                    &format!("NATIVE_WAIT: Could not wait for the system helper: {error}"),
                ));
            }
        }
    };
    if let Some(session) = &mut capture_session {
        session.close();
    }
    let output = output_thread
        .join()
        .map_err(|_| "NATIVE: Output reader failed.".to_string())?
        .map_err(|error| format!("NATIVE: Could not read helper output: {error}"))?;
    let errors = error_thread
        .join()
        .map_err(|_| "NATIVE: Error reader failed.".to_string())?
        .map_err(|error| format!("NATIVE: Could not read helper errors: {error}"))?;
    if let Some(thread) = input_thread {
        let written = thread
            .join()
            .map_err(|_| "NATIVE_INPUT: Input writer failed.".to_string())?;
        if status.success() {
            written
                .map_err(|error| format!("NATIVE_INPUT: Could not send clipboard text: {error}"))?;
        }
    }
    if output.is_empty() && !status.success() {
        // PowerShell startup errors can precede our JSON protocol. Do not include
        // script contents or source text in application logs.
        let detail = String::from_utf8_lossy(&errors);
        let detail: String = detail.chars().take(600).collect();
        return Err(format!(
            "NATIVE_START: System helper exited with {status}. {detail}"
        ));
    }
    if capture {
        if let Ok(reply) = serde_json::from_slice::<Value>(&output) {
            let mut safe = bounded_capture_health(&reply["captureHealth"]);
            safe["helperResponseReceived"] = json!(1);
            safe["helperElapsedMilliseconds"] = json!(helper_started
                .elapsed()
                .as_millis()
                .min(u128::from(u64::MAX))
                as u64);
            safe["cancellationRequested"] = json!(u64::from(cancellation_requested));
            safe["cancellationSignalled"] = json!(u64::from(cancellation_signalled));
            safe["cancellationSignalFailed"] = json!(u64::from(cancellation_signal_failed));
            if let Ok(mut health) = windows_capture_health().lock() {
                *health = safe;
            }
        }
    }
    if selection {
        let reply = serde_json::from_slice::<Value>(&output).unwrap_or(Value::Null);
        let safe = selection_health_from_reply(
            &reply,
            helper_started
                .elapsed()
                .as_millis()
                .min(u128::from(SELECTION_HEALTH_MAX)) as u64,
            cancellation_requested,
            cancellation_signalled,
            cancellation_signal_failed,
        );
        if let Ok(mut health) = windows_selection_health().lock() {
            *health = safe;
        }
    }
    let result = parse_response(&output, status.success());
    // Clipboard restoration errors remain visible even when a task was replaced.
    if cancellation_signal_failed
        && result
            .as_ref()
            .err()
            .is_none_or(|error| !error.starts_with("CLIPBOARD_"))
    {
        return Err("NATIVE_CANCEL_SIGNAL: Windows could not signal task cancellation; the previous helper was allowed to clean up safely.".into());
    }
    if cancelled(cancel.as_ref())
        && result
            .as_ref()
            .err()
            .is_none_or(|error| !error.starts_with("CLIPBOARD_"))
    {
        return Err(NATIVE_CANCELLED.into());
    }
    if source.is_some_and(|expected| !expected.is_current())
        && result
            .as_ref()
            .err()
            .is_none_or(|error| !error.starts_with("CLIPBOARD_"))
    {
        return Err("CANCELLED: The source focus changed during selection capture.".into());
    }
    result
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn run(_mode: &str, _input: Option<&str>) -> Result<Value, String> {
    Err(
        "UNSUPPORTED_PLATFORM: Native selection and OCR currently support Windows and macOS."
            .into(),
    )
}

#[cfg(target_os = "macos")]
fn run(mode: &str, input: Option<&str>) -> Result<Value, String> {
    use std::ffi::{c_char, CString};
    use std::sync::Mutex;
    // Serialize operations that can touch the clipboard. Permission preflight
    // remains independent so Settings can inspect state during a region picker.
    static CAPTURE: Mutex<()> = Mutex::new(());
    let _capture = if matches!(
        mode,
        "selected-text" | "clipboard" | "copy" | "capture-ocr" | "capture-image"
    ) {
        Some(
            CAPTURE
                .lock()
                .map_err(|_| "NATIVE: 原生操作状态不可用。".to_string())?,
        )
    } else {
        None
    };
    unsafe extern "C" {
        fn echolingo_native_run(
            mode: *const c_char,
            input: *const u8,
            input_len: usize,
            output_len: *mut usize,
        ) -> *mut u8;
        fn echolingo_native_free(output: *mut u8);
    }
    let mode = CString::new(format!("--{mode}"))
        .map_err(|_| "NATIVE_MODE: Invalid native operation.".to_string())?;
    let input = input.unwrap_or("").as_bytes();
    if input.len() > 2 * 1024 * 1024 {
        return Err("NATIVE_INPUT: 原生输入超过 2 MiB。".into());
    }
    let mut output_len = 0usize;
    // SAFETY: Swift is statically linked into the same executable. The mode is
    // NUL-terminated and the input slice remains alive for the synchronous call.
    // Its output is a byte buffer with an explicit length, released exactly once
    // using the matching Swift allocator after parsing. No Swift object or Rust
    // ownership crosses this C ABI, and this entry never calls exit().
    let output = unsafe {
        echolingo_native_run(mode.as_ptr(), input.as_ptr(), input.len(), &mut output_len)
    };
    if output.is_null() {
        return Err("NATIVE_PROTOCOL: 原生模块未返回结果。".into());
    }
    let result = if output_len == 0 || output_len > 12 * 1024 * 1024 {
        Err("NATIVE_PROTOCOL: 原生返回结果为空或超限。".into())
    } else {
        // SAFETY: The native ABI guarantees an allocated buffer of output_len
        // bytes, and it stays allocated through parse_response.
        parse_response(
            unsafe { std::slice::from_raw_parts(output, output_len) },
            true,
        )
    };
    // SAFETY: This buffer was returned by echolingo_native_run and is freed once.
    unsafe { echolingo_native_free(output) };
    result
}

// Cached paths are an optimization, not proof of the file's current contents.
// Bound every read to the embedded DLL's exact size and never load a changed
// (even otherwise valid) assembly or silently repair it during a shortcut.
#[cfg(any(target_os = "windows", test))]
fn verify_native_assembly(path: &std::path::Path, expected: &[u8]) -> Result<(), String> {
    use std::io::Read;
    let check = (|| -> std::io::Result<bool> {
        let metadata = std::fs::symlink_metadata(path)?;
        if !metadata.is_file()
            || metadata.file_type().is_symlink()
            || metadata.len() != expected.len() as u64
        {
            return Ok(false);
        }
        let file = std::fs::File::open(path)?;
        if file.metadata()?.len() != expected.len() as u64 {
            return Ok(false);
        }
        let mut actual = Vec::with_capacity(expected.len());
        file.take(expected.len() as u64 + 1)
            .read_to_end(&mut actual)?;
        Ok(actual == expected)
    })();
    if check.unwrap_or(false) {
        Ok(())
    } else {
        Err("NATIVE_ASSEMBLY: The packaged Windows native DLL changed or is unavailable. Restart or reinstall EchoLingo.".into())
    }
}

#[cfg(target_os = "windows")]
fn native_command(mode: &str) -> Result<std::process::Command, String> {
    use sha2::{Digest, Sha256};
    use std::os::windows::process::CommandExt;
    use std::sync::OnceLock;
    static HELPER: OnceLock<Result<(std::path::PathBuf, std::path::PathBuf), String>> =
        OnceLock::new();
    let (path, assembly) = HELPER
        .get_or_init(|| {
            let local =
                std::env::var_os("LOCALAPPDATA").ok_or("NATIVE: LOCALAPPDATA is unavailable.")?;
            let folder = std::path::PathBuf::from(local).join("EchoLingo/native");
            ensure_private_directory(&folder)?;
            // Windows PowerShell 5.1 needs a BOM to decode non-ASCII source reliably.
            let mut bytes = vec![0xef, 0xbb, 0xbf];
            bytes.extend_from_slice(include_bytes!("../native/windows.ps1"));
            let script = materialize(&folder, "echolingo-native-helper.ps1", &bytes)?;
            let dll = include_bytes!(concat!(env!("OUT_DIR"), "/echolingo-windows-native.dll"));
            let digest = format!("{:x}", Sha256::digest(dll));
            let assembly = materialize(&folder, &format!("echolingo-native-{digest}.dll"), dll)?;
            Ok((script, assembly))
        })
        .as_ref()
        .map_err(Clone::clone)?;
    verify_native_assembly(
        assembly,
        include_bytes!(concat!(env!("OUT_DIR"), "/echolingo-windows-native.dll")),
    )?;
    let system_root = std::env::var_os("SystemRoot").ok_or("NATIVE: SystemRoot is unavailable.")?;
    let powershell = std::path::PathBuf::from(system_root)
        .join("System32/WindowsPowerShell/v1.0/powershell.exe");
    let mut command = std::process::Command::new(powershell);
    command
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-STA",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg(path)
        .args(["-Mode", mode, "-NativeAssemblyPath"])
        .arg(assembly);
    // No command shell, interpolation, user-supplied code, execution-policy change
    // to the machine, or visible console window. Copy text travels through stdin.
    if mode == "selected-text" {
        command.args(["-ExcludedSourceProcessId", &std::process::id().to_string()]);
    }
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    Ok(command)
}

#[cfg(target_os = "windows")]
mod native_process {
    use super::NativeSourceSnapshot;
    use std::ffi::c_void;
    use std::os::windows::io::AsRawHandle;
    #[repr(C)]
    struct GuiThreadInfo {
        size: u32,
        flags: u32,
        active: *mut c_void,
        focus: *mut c_void,
        capture: *mut c_void,
        menu_owner: *mut c_void,
        move_size: *mut c_void,
        caret: *mut c_void,
        caret_rect: [i32; 4],
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn CreateEventW(
            attributes: *const c_void,
            manual: i32,
            initial: i32,
            name: *const u16,
        ) -> *mut c_void;
        fn SetEvent(event: *mut c_void) -> i32;
        fn CloseHandle(handle: *mut c_void) -> i32;
        fn WaitForSingleObject(handle: *mut c_void, milliseconds: u32) -> u32;
        fn GetLastError() -> u32;
    }
    #[link(name = "user32")]
    unsafe extern "system" {
        fn GetForegroundWindow() -> *mut c_void;
        fn GetWindowThreadProcessId(window: *mut c_void, pid: *mut u32) -> u32;
        fn GetGUIThreadInfo(thread: u32, info: *mut GuiThreadInfo) -> i32;
        fn GetAncestor(window: *mut c_void, flags: u32) -> *mut c_void;
    }
    #[link(name = "bcrypt")]
    unsafe extern "system" {
        fn BCryptGenRandom(algorithm: *mut c_void, buffer: *mut u8, length: u32, flags: u32)
            -> i32;
    }
    pub fn source_snapshot() -> Result<NativeSourceSnapshot, String> {
        let window = unsafe { GetForegroundWindow() };
        let mut process = 0;
        let thread = unsafe { GetWindowThreadProcessId(window, &mut process) };
        if window.is_null() || thread == 0 || process == 0 {
            return Err("SELECTION_SOURCE_CHANGED: The source application is unavailable.".into());
        }
        // Record native focus at the shortcut, before helper startup. Root
        // HWND/PID alone cannot distinguish two editors in the same window.
        // This is bounded Win32 metadata, never a UIA query on the UI thread.
        let mut info: GuiThreadInfo = unsafe { std::mem::zeroed() };
        info.size = std::mem::size_of::<GuiThreadInfo>() as u32;
        if unsafe { GetGUIThreadInfo(thread, &mut info) } == 0
            || unsafe { GetForegroundWindow() } != window
            || (!info.focus.is_null()
                && unsafe { GetAncestor(info.focus, 2) } != unsafe { GetAncestor(window, 2) })
        {
            return Err("SELECTION_SOURCE_CHANGED: The source focus is unavailable.".into());
        }
        Ok(NativeSourceSnapshot {
            window: window as isize,
            process,
            thread,
            focus: info.focus as isize,
        })
    }
    pub struct CancellationEvent {
        handle: *mut c_void,
        name: String,
        signalled: bool,
    }
    impl CancellationEvent {
        pub fn new() -> Result<Self, String> {
            let mut bytes = [0u8; 16];
            if unsafe { BCryptGenRandom(std::ptr::null_mut(), bytes.as_mut_ptr(), 16, 2) } < 0 {
                return Err("NATIVE_CANCEL: Windows could not prepare task cancellation.".into());
            }
            let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
            let name = format!("Local\\EchoLingo-cancel-{}-{suffix}", std::process::id());
            let wide: Vec<u16> = name.encode_utf16().chain(Some(0)).collect();
            let handle = unsafe { CreateEventW(std::ptr::null(), 1, 0, wide.as_ptr()) };
            let error = unsafe { GetLastError() };
            if handle.is_null() {
                return Err("NATIVE_CANCEL: Windows could not create task cancellation.".into());
            }
            if error == 183 {
                unsafe {
                    CloseHandle(handle);
                };
                return Err(
                    "NATIVE_CANCEL: Windows returned an existing cancellation session.".into(),
                );
            }
            Ok(Self {
                handle,
                name,
                signalled: false,
            })
        }
        pub fn name(&self) -> &str {
            &self.name
        }
        pub fn signal(&mut self) -> bool {
            if !self.signalled {
                self.signalled = unsafe { SetEvent(self.handle) } != 0;
            }
            self.signalled
        }
    }
    impl Drop for CancellationEvent {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.handle);
            }
        }
    }
    pub fn wait_child(child: &std::process::Child, milliseconds: u32) -> std::io::Result<()> {
        // This worker owns no HWND and waits on actual process completion;
        // completion wakes immediately, with only cancellation polling bounded.
        match unsafe { WaitForSingleObject(child.as_raw_handle(), milliseconds) } {
            0 | 258 => Ok(()),
            _ => Err(std::io::Error::last_os_error()),
        }
    }
}

#[cfg(target_os = "windows")]
fn ensure_private_directory(path: &std::path::Path) -> Result<(), String> {
    std::fs::create_dir_all(path)
        .map_err(|error| format!("NATIVE_CACHE: Cannot create helper directory: {error}"))?;
    let metadata =
        std::fs::symlink_metadata(path).map_err(|error| format!("NATIVE_CACHE: {error}"))?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(
            "NATIVE_CACHE: The helper cache must be a real directory, not a symlink.".into(),
        );
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn materialize(
    folder: &std::path::Path,
    name: &str,
    bytes: &[u8],
) -> Result<std::path::PathBuf, String> {
    use std::io::Write;
    let destination = folder.join(name);
    if let Ok(metadata) = std::fs::symlink_metadata(&destination) {
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err("NATIVE_CACHE: The helper path is not a regular file.".into());
        }
        if std::fs::read(&destination).ok().as_deref() == Some(bytes) {
            return Ok(destination);
        }
    }
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| "NATIVE_CACHE: System clock is unavailable.".to_string())?
        .as_nanos();
    let temporary = folder.join(format!(".{name}-{}-{nonce}", std::process::id()));
    let result = (|| -> std::io::Result<()> {
        let mut options = std::fs::OpenOptions::new();
        options.create_new(true).write(true);
        let mut file = options.open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        #[cfg(target_os = "windows")]
        if destination.exists() {
            // Windows rename does not replace an existing destination. This
            // directory inherits the current user's LocalAppData ACL.
            std::fs::remove_file(&destination)?;
        }
        std::fs::rename(&temporary, &destination)?;
        Ok(())
    })();
    if let Err(error) = result {
        let _ = std::fs::remove_file(&temporary);
        return Err(format!("NATIVE_CACHE: Cannot extract helper: {error}"));
    }
    Ok(destination)
}

#[cfg(test)]
mod tests {
    use serde_json::{json, Value};

    #[test]
    fn forced_selection_stop_never_claims_clipboard_cleanup_or_hides_its_warning() {
        assert!(
            super::native_forced_stop_error("selected-text", "NATIVE_WAIT")
                .starts_with("CLIPBOARD_RESTORE_SKIPPED:")
        );
        assert_eq!(
            super::native_forced_stop_error("capture-ocr", "NATIVE_WAIT"),
            "NATIVE_WAIT"
        );
    }
    #[test]
    fn superseded_requests_return_before_any_native_helper_or_image_is_started() {
        use std::sync::{atomic::AtomicBool, Arc};
        for result in [
            super::selected_text_cancelable(Arc::new(AtomicBool::new(true))),
            super::capture_ocr_cancelable(Arc::new(AtomicBool::new(true))),
            super::capture_image_cancelable(Arc::new(AtomicBool::new(true))),
        ] {
            assert_eq!(result.unwrap_err(), super::NATIVE_CANCELLED);
        }
    }
    #[test]
    fn capture_image_validation_is_shared_by_ordinary_and_cancelable_paths() {
        assert_eq!(
            super::image_response(serde_json::json!({"imageBase64":"fixture-only"})).unwrap(),
            "fixture-only"
        );
        assert!(super::image_response(serde_json::json!({"imageBase64":""})).is_err());
        assert!(super::image_response(serde_json::json!({"text":"not-an-image"})).is_err());
    }
    #[test]
    fn native_assembly_cache_rechecks_mutation_after_initial_success_without_repair() {
        let directory = std::env::temp_dir().join(format!(
            "echolingo-assembly-integrity-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&directory).unwrap();
        let path = directory.join("generated.dll");
        let expected = b"MZ-generated-assembly-identity-A";
        std::fs::write(&path, expected).unwrap();
        assert!(super::verify_native_assembly(&path, expected).is_ok());
        // A same-length replacement, not only corrupt/missing DLL loading,
        // must be rejected after the path has already passed its first check.
        let changed = b"MZ-generated-assembly-identity-B";
        std::fs::write(&path, changed).unwrap();
        let error = super::verify_native_assembly(&path, expected).unwrap_err();
        assert!(error.starts_with("NATIVE_ASSEMBLY:"));
        assert_eq!(std::fs::read(&path).unwrap(), changed);
        std::fs::write(&path, b"MZ-oversized-generated-assembly-identity-B-extra").unwrap();
        assert!(super::verify_native_assembly(&path, expected).is_err());
        std::fs::remove_file(&path).unwrap();
        assert!(super::verify_native_assembly(&path, expected).is_err());
        std::fs::remove_dir(directory).unwrap();
    }

    #[test]
    fn capture_health_keeps_only_bounded_unsigned_metadata_even_on_failure() {
        let safe = super::bounded_capture_health(&serde_json::json!({
            "hookMouseDowns": 0, "hookMouseUps": 7, "hookMouseMoves": 42,
            "knownPointer": 1, "desktopMatched": 1, "mismatchKind": 1,
            "inputBackend": 2, "mouseHookInstalled": 0,
            "inputPlaneDowns": 1, "inputPlaneUps": 1, "inputPlaneMoves": 18,
            "inputPlaneCount": 2, "inputPlaneVisibleCount": 0,
            "inputPlaneRemainingAfterCleanup": 0, "inputPlaneFallbackUsed": 1,
            "uiPhase": "original text", "dragging": -1,
            "source": "never retain", "title": "never retain", "imageBase64": "never retain",
            "trajectory": [1, 2, 3], "credentials": {"value": "never retain"}
        }));
        assert_eq!(
            safe,
            serde_json::json!({"hookMouseDowns":0,"hookMouseUps":7,"hookMouseMoves":42,"knownPointer":1,"desktopMatched":1,"mismatchKind":1,
                "inputBackend":2,"mouseHookInstalled":0,"inputPlaneDowns":1,"inputPlaneUps":1,"inputPlaneMoves":18,
                "inputPlaneCount":2,"inputPlaneVisibleCount":0,"inputPlaneRemainingAfterCleanup":0,"inputPlaneFallbackUsed":1})
        );
        assert_eq!(
            super::bounded_capture_health(&serde_json::json!(null)),
            serde_json::json!({})
        );
    }

    #[test]
    fn selection_health_rejects_content_unknown_fields_and_invalid_numeric_types() {
        let safe = super::bounded_selection_health(&json!({
            "selectionQueryCount": 7,
            "selectionQuery1Stage": 11,
            "selectionQuery1IdentityCompared": 1,
            "selectionQuery1IdentityEqual": 0,
            "selectionQuery1Depth": -1,
            "selectionQuery2Stage": "selected source text",
            "selectionQuery2Depth": [4],
            "selectionQuery2IdentityEqual": true,
            "selectionQuery2RootWalkReason": {"text":"private"},
            "selectionQuery2ExceptionKind": 1.0,
            "selectionQuery3Milliseconds": 10_000_001_u64,
            "selectionQuery16Milliseconds": 10_000_000,
            "selectionQuery0Stage": 1,
            "selectionQuery01Stage": 1,
            "selectionQuery17Stage": 1,
            "selectionQuery1InitialRoleId": 50033,
            "selectionQuery1SelectionLength": 20,
            "helperElapsedMilliseconds": 9,
            "source": "private", "title":"private", "clipboard":"private",
            "pid": 234, "hwnd": 567, "credentials":{"key":"dummy"}
        }));
        assert_eq!(
            safe,
            json!({
                "selectionQueryCount":7,"selectionQuery1Stage":11,
                "selectionQuery1IdentityCompared":1,"selectionQuery1IdentityEqual":0,
                "selectionQuery16Milliseconds":10_000_000
            })
        );
    }

    #[test]
    fn selection_health_bounds_all_query_slots_and_rejects_malformed_health() {
        let mut input = serde_json::Map::new();
        for index in 1..=17 {
            for suffix in [
                "Stage",
                "Depth",
                "IdentityCompared",
                "IdentityEqual",
                "RootWalkReason",
                "ExceptionKind",
                "Milliseconds",
            ] {
                input.insert(format!("selectionQuery{index}{suffix}"), json!(0));
            }
        }
        input.insert("selectionQueryCount".into(), json!(10_000_000));
        let safe = super::bounded_selection_health(&Value::Object(input));
        assert_eq!(safe.as_object().unwrap().len(), 16 * 7 + 1);
        assert_eq!(safe["selectionQueryCount"], 10_000_000);
        assert_eq!(safe["selectionQuery16ExceptionKind"], 0);
        assert!(safe.get("selectionQuery17Stage").is_none());
        for malformed in [
            Value::Null,
            json!([]),
            json!("private"),
            json!(42),
            json!(false),
            json!({}),
        ] {
            assert_eq!(super::bounded_selection_health(&malformed), json!({}));
        }
    }

    #[test]
    fn selection_health_process_metadata_comes_only_from_our_boundary() {
        let reply = json!({
            "ok":false, "error":"private source must not be retained",
            "text":"private", "captureHealth":{
                "selectionQueryCount":1, "selectionQuery1ExceptionKind":5,
                "helperResponseReceived":0, "helperElapsedMilliseconds":1,
                "cancellationRequested":0, "cancellationSignalled":99,
                "cancellationSignalFailed":"private"
            }
        });
        let safe = super::selection_health_from_reply(&reply, u64::MAX, true, false, true);
        assert_eq!(
            safe,
            json!({
                "selectionQueryCount":1,"selectionQuery1ExceptionKind":5,
                "helperResponseReceived":1,"helperElapsedMilliseconds":10_000_000,
                "cancellationRequested":1,"cancellationSignalled":0,"cancellationSignalFailed":1
            })
        );
        let invalid_json = serde_json::from_slice::<Value>(b"{not-json").unwrap_or(Value::Null);
        for malformed in [invalid_json, json!([]), json!("private"), json!(false)] {
            let empty = super::selection_health_from_reply(&malformed, 0, false, false, false);
            assert_eq!(
                empty,
                json!({
                    "helperResponseReceived":0,"helperElapsedMilliseconds":0,
                    "cancellationRequested":0,"cancellationSignalled":0,"cancellationSignalFailed":0
                })
            );
        }
    }

    #[test]
    fn hide_confirms_native_state_when_runtime_hide_was_a_cached_noop() {
        let visible = std::cell::Cell::new(true);
        // Runtime returns Ok with its VISIBLE flag already false, although
        // passive native presentation left the real window on screen.
        let result = super::finish_window_hide(Ok(()), || visible.set(false), || visible.get());
        assert!(result.is_ok());
        assert!(!visible.get());
    }

    #[test]
    fn hide_reports_a_still_visible_native_window_after_successful_dispatch() {
        let attempted = std::cell::Cell::new(false);
        let result = super::finish_window_hide(Ok(()), || attempted.set(true), || true);
        assert!(attempted.get());
        assert!(result.unwrap_err().starts_with("WINDOW_HIDE:"));
    }

    #[test]
    fn runtime_hide_failure_does_not_skip_native_hide_or_hide_its_error() {
        let visible = std::cell::Cell::new(true);
        let result = super::finish_window_hide(
            Err("runtime dispatch failed".into()),
            || visible.set(false),
            || visible.get(),
        );
        assert!(!visible.get());
        assert_eq!(result.unwrap_err(), "runtime dispatch failed");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn mac_popup_behavior_mask_uses_production_abi_without_window_or_permission_operations() {
        unsafe extern "C" {
            fn echolingo_popup_behavior_mask_for_version(current: u64, modern: i32) -> u64;
        }
        let join_all_spaces = 1;
        let move_to_active_space = 1 << 1;
        let primary = 1 << 7;
        let auxiliary = 1 << 8;
        let none = 1 << 9;
        let modern_roles = (1 << 16) | (1 << 17) | (1 << 18);
        let conflicting = move_to_active_space | primary | none | modern_roles;
        let unrelated = (1 << 4) | (1 << 6) | (1 << 12) | (1 << 40);
        for modern in [0, 1] {
            let required = join_all_spaces | auxiliary | if modern != 0 { 1 << 18 } else { 0 };
            for mask in [0, conflicting, required, unrelated, unrelated | conflicting] {
                // SAFETY: This ABI only transforms an integer mask. It does not
                // instantiate NSApplication, touch windows or request permissions.
                let result = unsafe { echolingo_popup_behavior_mask_for_version(mask, modern) };
                assert_eq!(result, (mask & !conflicting) | required);
                assert_eq!(
                    unsafe { echolingo_popup_behavior_mask_for_version(result, modern) },
                    result
                );
            }
        }
    }

    #[test]
    fn system_translation_input_rejects_invalid_languages_and_unbounded_text() {
        for (source, target) in [
            ("", "en"),
            ("en", "auto"),
            ("en;open", "zh-Hans"),
            ("auto", ""),
        ] {
            assert!(super::system_translation_input(source, target, Some("fixture")).is_err());
        }
        assert!(super::system_translation_input("auto", "zh-Hans", Some(" ")).is_err());
        assert!(
            super::system_translation_input("en", "zh-Hans", Some(&"a".repeat(20_001))).is_err()
        );
        let encoded =
            super::system_translation_input("auto", "zh-Hant", Some("段落一。\n\nparagraph two\0"))
                .unwrap();
        let value: serde_json::Value = serde_json::from_str(&encoded).unwrap();
        assert_eq!(value["text"], "段落一。\n\nparagraph two\0");
        assert_eq!(value["target"], "zh-Hant");
    }
    use super::parse_response;

    #[cfg(any(target_os = "macos", target_os = "windows"))]
    #[test]
    fn pointer_query_returns_finite_screen_coordinates_without_synthesizing_input() {
        let (_, x, y) = super::pointer_state().expect("Native pointer query must be available");
        assert!(x.is_finite() && y.is_finite());
    }

    #[test]
    fn native_json_preserves_unicode_and_cancellation() {
        let value = parse_response(
            "{\"ok\":true,\"text\":\"回声译\\nEchoLingo\"}".as_bytes(),
            true,
        )
        .unwrap();
        assert_eq!(value["text"], "回声译\nEchoLingo");
        assert_eq!(
            parse_response(br#"{"ok":false,"error":"CANCELLED: Escape"}"#, false).unwrap_err(),
            "CANCELLED: Escape"
        );
        assert!(parse_response(br#"{"ok":true,"text":"partial"}"#, false).is_err());
        assert!(parse_response(b"not JSON", true)
            .unwrap_err()
            .starts_with("NATIVE_PROTOCOL:"));
    }

    #[test]
    fn permission_actions_reject_arbitrary_destinations_before_native_ui() {
        for kind in [
            "",
            "screen-capture",
            "https://example.com",
            "accessibility\0",
        ] {
            assert!(super::request_permission(kind)
                .unwrap_err()
                .starts_with("PERMISSION_KIND:"));
            assert!(super::open_permission_settings(kind)
                .unwrap_err()
                .starts_with("PERMISSION_KIND:"));
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn mac_capture_selector_fixture_checks_geometry_without_capturing_the_desktop() {
        let result = super::run("capture-selection-self-test", None).unwrap();
        assert_eq!(result["diagnostics"]["captureSelectionFixturePassed"], true);
        assert_eq!(result["diagnostics"]["screenCaptured"], false);
        assert_eq!(result["diagnostics"]["permissionRequested"], false);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn mac_system_translation_policy_and_cancellation_use_the_production_abi_without_models() {
        let result = super::run("system-translation-self-test", None).unwrap();
        let diagnostic = &result["diagnostics"];
        assert_eq!(diagnostic["systemTranslationPolicyFixturePassed"], true);
        assert_eq!(diagnostic["systemTranslationOutputFixturePassed"], true);
        assert_eq!(diagnostic["systemTranslationOutputFixtureCount"], 19);
        assert_eq!(diagnostic["translationEngineCalled"], false);
        assert_eq!(diagnostic["languageDownloadRequested"], false);
        assert!(
            diagnostic["systemTranslationCancellationFixturePassed"] == true
                || diagnostic["systemTranslationCancellationFixtureSkipped"] == true
        );
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn mac_screen_permission_policy_never_caches_authority_or_opens_concurrent_requests() {
        let result = super::run("permission-policy-self-test", None).unwrap();
        let diagnostic = &result["diagnostics"];
        assert_eq!(diagnostic["permissionPolicyFixturePassed"], true);
        assert_eq!(diagnostic["permissionRequested"], false);
        assert_eq!(diagnostic["screenCaptured"], false);
        assert_eq!(diagnostic["passiveStatusUsesPreflightOnly"], true);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn mac_permission_preflight_uses_this_process_without_requesting_access() {
        let status = super::permission_status().unwrap();
        assert_eq!(status["identity"], "application-process");
        assert_eq!(status["processId"], std::process::id());
        assert!(status["accessibilityGranted"].is_boolean());
        assert!(status["screenCaptureGranted"].is_boolean());
        assert_eq!(
            status["screenCapturePreflightGranted"],
            status["screenCaptureGranted"]
        );
        assert!(matches!(
            status["screenCaptureState"].as_str(),
            Some("granted" | "unconfirmed")
        ));
        assert!(status.get("screenCaptureRequestState").is_none());
        assert!(status["runningBundledApp"].is_boolean());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn mac_static_entry_runs_real_ocr_and_preserves_unicode_nul_input() {
        // This uses the exact production C ABI and statically linked Swift;
        // it never reads the clipboard, selection or desktop pixels.
        let result = super::run("self-test", Some("回声译\0EchoLingo 🪞")).unwrap();
        let diagnostic = &result["diagnostics"];
        assert_eq!(diagnostic["ocrFixturePassed"], true);
        assert_eq!(diagnostic["pngBase64RoundtripPassed"], true);
        assert_eq!(diagnostic["paragraphGeometryFixturePassed"], true);
        assert_eq!(diagnostic["bridgeInputPassed"], true);
        assert_eq!(
            diagnostic["diagnostics"]["permissions"]["processId"],
            std::process::id()
        );
    }
}
