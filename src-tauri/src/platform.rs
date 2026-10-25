//! Run blocking capture/clipboard operations on `tauri::async_runtime::spawn_blocking`.
//! Showing a nonactivating window is the exception and requires the main thread.
//! In particular, do not activate the EchoLingo window before `selected_text`.

use serde_json::{json, Value};

pub fn selected_text() -> Result<String, String> {
    run_text("selected-text", None)
}

pub fn capture_ocr() -> Result<String, String> {
    run_text("capture-ocr", None)
}

/// Capture only. The caller chooses whether to submit this PNG to a configured
/// third-party OCR API; the native helper performs no upload or network request.
pub fn capture_image() -> Result<String, String> {
    let result = run("capture-image", None)?;
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

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn show_without_activation(_window: &tauri::WebviewWindow) -> Result<(), String> {
    Err("UNSUPPORTED_PLATFORM: Nonactivating windows support Windows and macOS.".into())
}

pub fn diagnostics() -> Value {
    match run("diagnostics", None) {
        Ok(result) => result.get("diagnostics").cloned().unwrap_or(result),
        Err(error) => {
            json!({ "platform": std::env::consts::OS, "available": false, "error": error })
        }
    }
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

#[cfg(target_os = "windows")]
fn run(mode: &str, input: Option<&str>) -> Result<Value, String> {
    use std::io::{Read, Write};
    use std::process::Stdio;
    use std::time::{Duration, Instant};

    let mut command = native_command(mode)?;
    command
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command
        .spawn()
        .map_err(|error| format!("NATIVE_START: Could not start the system helper: {error}"))?;
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
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(30)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("NATIVE_TIMEOUT: The system helper stopped responding. Retry; if this persists, check system permissions and OCR language installation.".into());
            }
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!(
                    "NATIVE_WAIT: Could not wait for the system helper: {error}"
                ));
            }
        }
    };
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
    parse_response(&output, status.success())
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

#[cfg(target_os = "windows")]
fn native_command(mode: &str) -> Result<std::process::Command, String> {
    use std::os::windows::process::CommandExt;
    use std::sync::OnceLock;
    static SCRIPT: OnceLock<Result<std::path::PathBuf, String>> = OnceLock::new();
    let path = SCRIPT
        .get_or_init(|| {
            let local =
                std::env::var_os("LOCALAPPDATA").ok_or("NATIVE: LOCALAPPDATA is unavailable.")?;
            let folder = std::path::PathBuf::from(local).join("EchoLingo/native");
            ensure_private_directory(&folder)?;
            // Windows PowerShell 5.1 needs a BOM to decode non-ASCII source reliably.
            let mut bytes = vec![0xef, 0xbb, 0xbf];
            bytes.extend_from_slice(include_bytes!("../native/windows.ps1"));
            materialize(&folder, "echolingo-native-helper.ps1", &bytes)
        })
        .as_ref()
        .map_err(Clone::clone)?;
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
        .args(["-Mode", mode]);
    // No command shell, interpolation, user-supplied code, execution-policy change
    // to the machine, or visible console window. Copy text travels through stdin.
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    Ok(command)
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
    fn mac_permission_preflight_uses_this_process_without_requesting_access() {
        let status = super::permission_status().unwrap();
        assert_eq!(status["identity"], "application-process");
        assert_eq!(status["processId"], std::process::id());
        assert!(status["accessibilityGranted"].is_boolean());
        assert!(status["screenCaptureGranted"].is_boolean());
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
