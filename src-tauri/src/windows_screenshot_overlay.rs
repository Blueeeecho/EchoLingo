//! Windows host for the shared screenshot canvas. The native capture child is
//! already stopped before this parent-owned surface is prepared. Initial display
//! never takes foreground focus; only an explicit editor interaction can request it.
use super::{layout, KeyOwnership, KeyRoute, Layout};
use crate::platform::ScreenshotGeometry;
use std::{
    cell::RefCell,
    ffi::c_void,
    ptr::null_mut,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
use tauri::{Emitter, Manager};
#[path = "windows_capture_ffi.rs"]
mod w;
#[link(name = "user32")]
unsafe extern "system" {
    fn GetForegroundWindow() -> w::H;
    fn GetAncestor(hwnd: w::H, flags: u32) -> w::H;
    fn GetDpiForWindow(hwnd: w::H) -> u32;
    fn GetClientRect(hwnd: w::H, rect: *mut w::Rect) -> i32;
    fn SetTimer(hwnd: w::H, id: usize, ms: u32, callback: *const c_void) -> usize;
    fn KillTimer(hwnd: w::H, id: usize) -> i32;
}
const NOACTIVATE: isize = 0x0800_0000;
const KEY_EVENT: u32 = 0x8000 + 73;
const WAKE: u32 = 0x8000 + 74;
struct Router {
    active: Arc<AtomicBool>,
    thread: u32,
}
static ROUTER: Mutex<Option<Router>> = Mutex::new(None);
struct PreparedHost {
    window: isize,
    original_style: isize,
    frame: [i32; 4],
    dpi: u32,
}
static HOST: Mutex<Option<PreparedHost>> = Mutex::new(None);
fn verify_viewport(native: w::H, frame: [i32; 4], dpi: u32) -> Result<(), String> {
    let mut outer = w::Rect::default();
    let mut client = w::Rect::default();
    if unsafe { w::GetWindowRect(native, &mut outer) } == 0
        || unsafe { GetClientRect(native, &mut client) } == 0
        || [
            outer.left,
            outer.top,
            outer.right - outer.left,
            outer.bottom - outer.top,
        ] != frame
        || client.right - client.left != frame[2]
        || client.bottom - client.top != frame[3]
        || dpi == 0
        || unsafe { GetDpiForWindow(native) } != dpi
    {
        return Err("SCREENSHOT_GEOMETRY: 原地截图窗口位置或 DPI 已变化，请重新截图".into());
    }
    Ok(())
}
struct HookState {
    active: Arc<AtomicBool>,
    window: isize,
    source: isize,
    keys: KeyOwnership,
    thread: u32,
}
thread_local! { static HOOK: RefCell<Option<HookState>> = const { RefCell::new(None) }; }
fn stop_keys() {
    if let Ok(mut slot) = ROUTER.lock() {
        if let Some(router) = slot.take() {
            router.active.store(false, Ordering::SeqCst);
            unsafe {
                w::PostThreadMessageW(router.thread, WAKE, 0, 0);
            }
        }
    }
}
unsafe extern "system" fn key_hook(code: i32, message: usize, data: isize) -> isize {
    if code < 0 || data == 0 {
        return w::CallNextHookEx(null_mut(), code, message, data);
    }
    let key = &*(data as *const w::Keyboard);
    let bit = match key.key {
        13 => 1,
        27 => 2,
        _ => return w::CallNextHookEx(null_mut(), code, message, data),
    };
    let consumed = HOOK.with(|cell| {
        let Ok(mut value) = cell.try_borrow_mut() else {
            return false;
        };
        let Some(state) = value.as_mut() else {
            return false;
        };
        if !matches!(message, 0x100 | 0x101 | 0x104 | 0x105) {
            return false;
        }
        let foreground = GetForegroundWindow() as isize;
        let eligible = foreground != state.window
            && GetAncestor(foreground as w::H, 2) as isize != state.window
            && foreground == state.source
            && ![0x10, 0x11, 0x12, 0x5b, 0x5c]
                .iter()
                .any(|key| w::GetAsyncKeyState(*key) < 0);
        match state.keys.route(
            bit,
            matches!(message, 0x100 | 0x104),
            key.flags & 0x10 != 0,
            state.active.load(Ordering::SeqCst),
            eligible,
        ) {
            KeyRoute::Forward => false,
            KeyRoute::Consume => true,
            KeyRoute::Dispatch => {
                // The hook only posts scalars to its own pump; IPC and allocation
                // happen after returning from the low-level keyboard callback.
                w::PostThreadMessageW(state.thread, KEY_EVENT, key.key as usize, 0);
                true
            }
        }
    });
    if consumed {
        1
    } else {
        w::CallNextHookEx(null_mut(), code, message, data)
    }
}
fn start_keys(window: &tauri::WebviewWindow, id: u64) -> Result<(), String> {
    stop_keys();
    let native = window
        .hwnd()
        .map_err(|_| "SCREENSHOT_WINDOW: 无法访问截图窗口")?
        .0 as isize;
    let source = unsafe { GetForegroundWindow() } as isize;
    let active = Arc::new(AtomicBool::new(true));
    let worker_active = active.clone();
    let app = window.app_handle().clone();
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let thread = unsafe { w::CurrentThreadId() };
        let mut message = w::Message::default();
        unsafe {
            w::PeekMessageW(&mut message, null_mut(), 0, 0, 0);
        }
        let preheld = unsafe {
            u8::from(w::GetAsyncKeyState(13) < 0) | (u8::from(w::GetAsyncKeyState(27) < 0) << 1)
        };
        HOOK.with(|slot| {
            *slot.borrow_mut() = Some(HookState {
                active: worker_active.clone(),
                window: native,
                source,
                keys: KeyOwnership::new(preheld),
                thread,
            })
        });
        let hook = unsafe {
            w::SetWindowsHookExW(13, Some(key_hook), w::GetModuleHandleW(std::ptr::null()), 0)
        };
        if hook.is_null() {
            let _ = tx.send(Err(
                "SCREENSHOT_INPUT: 无法启用截图确认/取消按键".to_string()
            ));
            HOOK.with(|s| *s.borrow_mut() = None);
            return;
        }
        let timer = unsafe { SetTimer(null_mut(), 0, 50, std::ptr::null()) };
        if timer == 0 {
            unsafe {
                w::UnhookWindowsHookEx(hook);
            }
            let _ = tx.send(Err("SCREENSHOT_INPUT: 无法保护截图按键生命周期".to_string()));
            return;
        }
        let _ = tx.send(Ok(thread));
        let mut stopping = None;
        while unsafe { w::GetMessageW(&mut message, null_mut(), 0, 0) } > 0 {
            if message.message == KEY_EVENT && worker_active.load(Ordering::SeqCst) {
                let key = if message.wparam == 13 {
                    "Enter"
                } else {
                    "Escape"
                };
                let _ = app.emit_to(
                    "screenshot-editor",
                    "screenshot-overlay-key",
                    serde_json::json!({"sessionId":id,"key":key}),
                );
            } else {
                unsafe {
                    w::TranslateMessage(&message);
                    w::DispatchMessageW(&message);
                }
            }
            if !worker_active.load(Ordering::SeqCst) {
                let since = stopping.get_or_insert_with(Instant::now);
                let owned = HOOK.with(|slot| {
                    slot.borrow()
                        .as_ref()
                        .is_some_and(|state| state.keys.held())
                });
                // Only already consumed keys survive dismissal; no new key is
                // intercepted. Never release a still-held Enter into the source
                // chat app. Polling only repairs a missing key-up after physical
                // release; process exit also removes the hook automatically.
                let physically_released =
                    unsafe { w::GetAsyncKeyState(13) >= 0 && w::GetAsyncKeyState(27) >= 0 };
                if !owned || (since.elapsed() >= Duration::from_secs(2) && physically_released) {
                    break;
                }
            }
        }
        unsafe {
            KillTimer(null_mut(), timer);
            w::UnhookWindowsHookEx(hook);
        }
        HOOK.with(|slot| *slot.borrow_mut() = None);
    });
    let thread = match rx.recv_timeout(Duration::from_secs(2)) {
        Ok(Ok(thread)) => thread,
        Ok(Err(error)) => {
            active.store(false, Ordering::SeqCst);
            return Err(error);
        }
        Err(_) => {
            active.store(false, Ordering::SeqCst);
            return Err("SCREENSHOT_INPUT: 截图按键准备超时".into());
        }
    };
    *ROUTER
        .lock()
        .map_err(|_| "SCREENSHOT_INPUT: 截图按键状态不可用")? = Some(Router { active, thread });
    Ok(())
}

pub fn prepare(
    window: &tauri::WebviewWindow,
    geometry: &ScreenshotGeometry,
) -> Result<Layout, String> {
    geometry.validate()?;
    stop_keys();
    crate::platform::hide_webview_window(window)?;
    window
        .set_min_size(None::<tauri::LogicalSize<f64>>)
        .map_err(|_| "SCREENSHOT_WINDOW: 无法准备截图尺寸")?;
    window
        .set_decorations(false)
        .map_err(|_| "SCREENSHOT_WINDOW: 无法准备无边框截图层")?;
    window
        .set_resizable(false)
        .map_err(|_| "SCREENSHOT_WINDOW: 无法固定截图层")?;
    let native = window
        .hwnd()
        .map_err(|_| "SCREENSHOT_WINDOW: 无法访问截图窗口")?
        .0;
    let frame = [
        geometry.screen_x.round() as i32,
        geometry.screen_y.round() as i32,
        geometry.screen_width.round() as i32,
        geometry.screen_height.round() as i32,
    ];
    let original_style = unsafe { w::GetWindowLongPtrW(native, -20) };
    *HOST
        .lock()
        .map_err(|_| "SCREENSHOT_WINDOW: 截图窗口状态不可用")? = Some(PreparedHost {
        window: native as isize,
        original_style,
        frame,
        dpi: 0,
    });
    unsafe {
        w::SetWindowLongPtrW(native, -20, original_style | NOACTIVATE | 0x80);
        if w::SetWindowPos(
            native,
            -1isize as w::H,
            frame[0],
            frame[1],
            frame[2],
            frame[3],
            0x10 | 0x20,
        ) == 0
        {
            return Err("SCREENSHOT_WINDOW: 无法定位原地截图层".into());
        }
    }
    let dpi = unsafe { GetDpiForWindow(native) };
    verify_viewport(native, frame, dpi)?;
    if let Some(host) = HOST
        .lock()
        .map_err(|_| "SCREENSHOT_WINDOW: 截图窗口状态不可用")?
        .as_mut()
    {
        host.dpi = dpi;
    }
    layout(geometry, f64::from(dpi) / 96.0)
}
pub fn show(
    window: &tauri::WebviewWindow,
    _geometry: &ScreenshotGeometry,
    id: u64,
) -> Result<(), String> {
    let native = window
        .hwnd()
        .map_err(|_| "SCREENSHOT_WINDOW: 无法访问截图窗口")?
        .0;
    {
        let host = HOST
            .lock()
            .map_err(|_| "SCREENSHOT_WINDOW: 截图窗口状态不可用")?;
        let host = host
            .as_ref()
            .filter(|host| host.window == native as isize)
            .ok_or("SCREENSHOT_WINDOW: 原地截图窗口未准备")?;
        verify_viewport(native, host.frame, host.dpi)?;
    }
    start_keys(window, id)?;
    if let Err(error) = crate::platform::show_without_activation(window) {
        stop_keys();
        return Err(error);
    }
    Ok(())
}
pub fn hide(window: &tauri::WebviewWindow) -> Result<(), String> {
    stop_keys();
    crate::platform::hide_webview_window(window)?;
    let native = window
        .hwnd()
        .map_err(|_| "SCREENSHOT_WINDOW: 无法访问截图窗口")?
        .0;
    let mut saved_host = HOST
        .lock()
        .map_err(|_| "SCREENSHOT_WINDOW: 截图窗口状态不可用")?;
    if let Some(host) = saved_host.as_ref() {
        if host.window == native as isize {
            unsafe {
                w::SetWindowLongPtrW(native, -20, host.original_style);
            }
        }
    }
    // Prepare changed native z-order directly. Restore it directly too, even
    // if the toolkit still caches always_on_top=false. FRAMECHANGED applies
    // restored extended styles without moving, resizing or activating anything.
    if unsafe {
        w::SetWindowPos(
            native,
            -2isize as w::H,
            0,
            0,
            0,
            0,
            0x01 | 0x02 | 0x10 | 0x20,
        )
    } == 0
    {
        return Err("SCREENSHOT_WINDOW: 无法恢复图片窗口层级".into());
    }
    window
        .set_min_size(Some(tauri::LogicalSize::new(720.0, 520.0)))
        .map_err(|_| "SCREENSHOT_WINDOW: 无法恢复编辑器最小尺寸")?;
    // Ordinary local-image opening remains a normal, explicitly requested editor.
    window
        .set_decorations(true)
        .map_err(|_| "SCREENSHOT_WINDOW: 无法恢复图片窗口")?;
    window
        .set_resizable(true)
        .map_err(|_| "SCREENSHOT_WINDOW: 无法恢复图片窗口")?;
    window
        .set_always_on_top(false)
        .map_err(|_| "SCREENSHOT_WINDOW: 无法恢复图片窗口")?;
    *saved_host = None;
    Ok(())
}
pub fn focus_text(window: &tauri::WebviewWindow) -> Result<(), String> {
    let native = window
        .hwnd()
        .map_err(|_| "SCREENSHOT_WINDOW: 无法访问截图窗口")?
        .0;
    unsafe {
        let extended = w::GetWindowLongPtrW(native, -20);
        w::SetWindowLongPtrW(native, -20, extended & !NOACTIVATE);
    }
    // This command is called only after explicit editor interaction, never from
    // screenshot-ready. WebView2 MoveFocus preserves Unicode and IME routing.
    window
        .set_focus()
        .map_err(|_| "SCREENSHOT_INPUT: 无法进入截图文字编辑")?;
    let webview: &tauri::Webview = window.as_ref();
    webview
        .set_focus()
        .map_err(|_| "SCREENSHOT_INPUT: 无法进入截图文字输入")
}
