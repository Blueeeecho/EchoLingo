//! Windows popup dismissal uses observed mouse-down events, not the unreliable
//! GetAsyncKeyState recent-press bit. The hook never consumes input or queries
//! app state; a bounded queue transfers only coordinates and an in-memory token.

use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Mutex,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Token {
    pub epoch: u64,
    revision: u64,
}

#[derive(Clone, Copy, Debug)]
pub struct Click {
    pub token: Token,
    pub x: i32,
    pub y: i32,
}

#[derive(Default)]
pub struct Gate {
    writer: Mutex<()>,
    revision: AtomicU64,
    epoch: AtomicU64,
    armed: AtomicBool,
    focused_revision: AtomicU64,
}

impl Gate {
    pub fn arm(&self, epoch: u64, focused: bool) {
        let Ok(_writer) = self.writer.lock() else {
            return;
        };
        // Height fits call the existing wake helper too. Keep their current
        // token so ordinary streaming/layout updates cannot discard a click.
        if let Some(token) = self.token().filter(|token| token.epoch == epoch) {
            if focused {
                self.focused_revision
                    .store(token.revision, Ordering::SeqCst);
            }
            return;
        }
        self.revision.fetch_add(1, Ordering::SeqCst);
        self.armed.store(false, Ordering::SeqCst);
        self.epoch.store(epoch, Ordering::SeqCst);
        let revision = self.revision.fetch_add(1, Ordering::SeqCst) + 1;
        self.focused_revision
            .store(if focused { revision } else { 0 }, Ordering::SeqCst);
        self.armed.store(true, Ordering::SeqCst);
    }

    pub fn disarm(&self) {
        let Ok(_writer) = self.writer.lock() else {
            return;
        };
        self.revision.fetch_add(1, Ordering::SeqCst);
        self.armed.store(false, Ordering::SeqCst);
        self.focused_revision.store(0, Ordering::SeqCst);
        self.revision.fetch_add(1, Ordering::SeqCst);
    }

    pub fn token(&self) -> Option<Token> {
        let before = self.revision.load(Ordering::SeqCst);
        if before % 2 != 0 || !self.armed.load(Ordering::SeqCst) {
            return None;
        }
        let epoch = self.epoch.load(Ordering::SeqCst);
        (before == self.revision.load(Ordering::SeqCst) && self.armed.load(Ordering::SeqCst))
            .then_some(Token {
                epoch,
                revision: before,
            })
    }

    pub fn is_current(&self, token: Token) -> bool {
        self.token() == Some(token)
    }

    pub fn mark_focused(&self, token: Token) {
        if self.is_current(token) {
            self.focused_revision
                .store(token.revision, Ordering::SeqCst);
        }
    }

    pub fn may_dismiss_blur(&self, token: Token, external_foreground: bool) -> bool {
        external_foreground
            && self.is_current(token)
            && self.focused_revision.load(Ordering::SeqCst) == token.revision
    }
}

pub fn outside_bounds(click: Click, left: i32, top: i32, width: u32, height: u32) -> bool {
    let (x, y, left, top) = (
        i64::from(click.x),
        i64::from(click.y),
        i64::from(left),
        i64::from(top),
    );
    x < left || y < top || x >= left + i64::from(width) || y >= top + i64::from(height)
}

fn observe_down(
    token: Token,
    x: i32,
    y: i32,
    left: i32,
    top: i32,
    width: u32,
    height: u32,
) -> Option<Click> {
    let click = Click { token, x, y };
    (width > 0 && height > 0 && outside_bounds(click, left, top, width, height)).then_some(click)
}

fn external_focus(known: bool, owned: bool, class: Option<&str>) -> bool {
    known
        && !owned
        && class.is_some_and(|class| !matches!(class, "IME" | "MSCTFIME UI" | "CiceroUIWndFrame"))
}

#[cfg(target_os = "windows")]
mod native {
    use super::*;
    use std::{
        ffi::c_void,
        sync::{
            atomic::AtomicIsize,
            mpsc::{self, Receiver, SyncSender},
            OnceLock,
        },
        time::Duration,
    };

    type Handle = *mut c_void;
    #[repr(C)]
    struct Point {
        x: i32,
        y: i32,
    }
    #[repr(C)]
    struct Rect {
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    }
    #[repr(C)]
    struct MouseData {
        point: Point,
        mouse_data: u32,
        flags: u32,
        time: u32,
        extra: usize,
    }
    #[repr(C)]
    struct Message {
        window: Handle,
        message: u32,
        wparam: usize,
        lparam: isize,
        time: u32,
        point: Point,
        private: u32,
    }
    type Hook = unsafe extern "system" fn(i32, usize, isize) -> isize;
    #[link(name = "user32")]
    unsafe extern "system" {
        fn SetWindowsHookExW(
            kind: i32,
            callback: Option<Hook>,
            module: Handle,
            thread: u32,
        ) -> Handle;
        fn CallNextHookEx(hook: Handle, code: i32, wparam: usize, lparam: isize) -> isize;
        fn UnhookWindowsHookEx(hook: Handle) -> i32;
        fn GetMessageW(message: *mut Message, window: Handle, minimum: u32, maximum: u32) -> i32;
        fn TranslateMessage(message: *const Message) -> i32;
        fn DispatchMessageW(message: *const Message) -> isize;
        fn PostThreadMessageW(thread: u32, message: u32, wparam: usize, lparam: isize) -> i32;
        fn GetForegroundWindow() -> Handle;
        fn WindowFromPoint(point: Point) -> Handle;
        fn GetAncestor(window: Handle, kind: u32) -> Handle;
        fn GetWindowThreadProcessId(window: Handle, process: *mut u32) -> u32;
        fn GetClassNameW(window: Handle, name: *mut u16, maximum: i32) -> i32;
        fn GetWindowRect(window: Handle, rectangle: *mut Rect) -> i32;
        fn SetThreadDpiAwarenessContext(context: Handle) -> Handle;
        fn GetThreadDpiAwarenessContext() -> Handle;
        fn GetAwarenessFromDpiAwarenessContext(context: Handle) -> i32;
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetModuleHandleW(name: *const u16) -> Handle;
        fn GetCurrentThreadId() -> u32;
    }

    struct Shared {
        gate: Gate,
        clicks: SyncSender<Click>,
        thread: AtomicU64,
        window: AtomicIsize,
    }
    static SHARED: OnceLock<Shared> = OnceLock::new();

    // No app-state locks, waiting, painting, logging or user-content access.
    unsafe extern "system" fn mouse(code: i32, wparam: usize, lparam: isize) -> isize {
        if code == 0 && matches!(wparam, 0x0201 | 0x0204) && lparam != 0 {
            if let Some(shared) = SHARED.get() {
                if let Some(token) = shared.gate.token() {
                    let data = unsafe { &*(lparam as *const MouseData) };
                    // Classify against the HWND bounds at the down event,
                    // before an inside toolbar/edge gesture can move it. This
                    // is an own-window User32 metadata query, never Tauri.
                    let mut bounds = Rect {
                        left: 0,
                        top: 0,
                        right: 0,
                        bottom: 0,
                    };
                    let window = shared.window.load(Ordering::SeqCst) as Handle;
                    if !window.is_null() && unsafe { GetWindowRect(window, &mut bounds) } != 0 {
                        let width = u32::try_from(i64::from(bounds.right) - i64::from(bounds.left));
                        let height =
                            u32::try_from(i64::from(bounds.bottom) - i64::from(bounds.top));
                        if let (Ok(width), Ok(height)) = (width, height) {
                            if let Some(click) = observe_down(
                                token,
                                data.point.x,
                                data.point.y,
                                bounds.left,
                                bounds.top,
                                width,
                                height,
                            ) {
                                // An owned native dialog/menu or IME can sit
                                // outside the main rect. Classify its HWND at
                                // down too, before it closes or moves away.
                                let target = unsafe {
                                    WindowFromPoint(Point {
                                        x: data.point.x,
                                        y: data.point.y,
                                    })
                                };
                                if external_window(window as isize, target) {
                                    let _ = shared.clicks.try_send(click);
                                }
                            }
                        }
                    }
                }
            }
        }
        unsafe { CallNextHookEx(std::ptr::null_mut(), code, wparam, lparam) }
    }

    pub fn start() -> Result<Receiver<Click>, String> {
        let (sender, receiver) = mpsc::sync_channel(256);
        SHARED
            .set(Shared {
                gate: Gate::default(),
                clicks: sender,
                thread: AtomicU64::new(0),
                window: AtomicIsize::new(0),
            })
            .map_err(|_| "Windows popup observation already started".to_owned())?;
        let (ready, status) = mpsc::sync_channel(1);
        std::thread::Builder::new()
            .name("popup-mouse-pump".into())
            .spawn(move || {
                // MSLLHOOKSTRUCT points and GetWindowRect must share physical
                // coordinates, including negative/mixed-DPI monitor layouts.
                let mut previous_dpi = unsafe { SetThreadDpiAwarenessContext(-4isize as Handle) };
                // Windows 10 1607 supports per-monitor V1; V2 starts at1703.
                // Both provide the physical coordinates required by this pump.
                if previous_dpi.is_null() {
                    previous_dpi = unsafe { SetThreadDpiAwarenessContext(-3isize as Handle) };
                }
                let physical = unsafe {
                    GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext()) == 2
                };
                if previous_dpi.is_null() || !physical {
                    let _ = ready.send(Err(
                        "Windows popup observation requires per-monitor physical coordinates"
                            .to_owned(),
                    ));
                    return;
                }
                // SAFETY: The static callback remains alive until the dedicated
                // thread removes its hook; GetMessage pumps its required messages.
                let hook = unsafe {
                    SetWindowsHookExW(14, Some(mouse), GetModuleHandleW(std::ptr::null()), 0)
                };
                if hook.is_null() {
                    let _ = ready.send(Err(format!(
                        "Windows outside-click observation failed: {}",
                        std::io::Error::last_os_error()
                    )));
                    unsafe {
                        SetThreadDpiAwarenessContext(previous_dpi);
                    }
                    return;
                }
                let shared = SHARED.get().expect("observer initialized");
                shared
                    .thread
                    .store(u64::from(unsafe { GetCurrentThreadId() }), Ordering::SeqCst);
                let _ = ready.send(Ok(()));
                let mut message: Message = unsafe { std::mem::zeroed() };
                while unsafe { GetMessageW(&mut message, std::ptr::null_mut(), 0, 0) } > 0 {
                    unsafe {
                        TranslateMessage(&message);
                        DispatchMessageW(&message);
                    }
                }
                shared.gate.disarm();
                unsafe {
                    UnhookWindowsHookEx(hook);
                    SetThreadDpiAwarenessContext(previous_dpi);
                }
            })
            .map_err(|_| "Cannot start Windows popup observation".to_owned())?;
        status
            .recv_timeout(Duration::from_secs(3))
            .map_err(|_| "Windows popup observation did not initialize".to_owned())??;
        Ok(receiver)
    }

    pub fn arm(epoch: u64, focused: bool, window: isize) {
        if let Some(shared) = SHARED.get() {
            shared.window.store(window, Ordering::SeqCst);
            shared.gate.arm(epoch, focused);
        }
    }
    pub fn disarm() {
        if let Some(shared) = SHARED.get() {
            shared.gate.disarm();
        }
    }
    pub fn token() -> Option<Token> {
        SHARED.get()?.gate.token()
    }
    pub fn current(token: Token) -> bool {
        SHARED
            .get()
            .is_some_and(|shared| shared.gate.is_current(token))
    }
    pub fn mark_focused(token: Token) {
        if let Some(shared) = SHARED.get() {
            shared.gate.mark_focused(token);
        }
    }
    pub fn may_dismiss_blur(token: Token, external: bool) -> bool {
        SHARED
            .get()
            .is_some_and(|shared| shared.gate.may_dismiss_blur(token, external))
    }
    pub fn stop() {
        disarm();
        if let Some(shared) = SHARED.get() {
            unsafe {
                PostThreadMessageW(shared.thread.load(Ordering::SeqCst) as u32, 0x0012, 0, 0);
            }
        }
    }

    fn window_is_owned(main_window: isize, target: Handle) -> bool {
        if target.is_null() {
            return false;
        }
        let root = unsafe { GetAncestor(target, 3) }; // GA_ROOTOWNER
        let mut process = 0;
        unsafe {
            GetWindowThreadProcessId(target, &mut process);
        }
        target as isize == main_window
            || root as isize == main_window
            || process == std::process::id()
    }

    fn external_window(main_window: isize, target: Handle) -> bool {
        // Treat unknown focus conservatively. Owned windows and standard IME
        // UI are part of editing, not a request to dismiss the translation.
        if target.is_null() || window_is_owned(main_window, target) {
            return false;
        }
        let mut name = [0u16; 128];
        let length = unsafe { GetClassNameW(target, name.as_mut_ptr(), name.len() as i32) };
        if length <= 0 {
            return false;
        }
        let class = String::from_utf16_lossy(&name[..length as usize]);
        external_focus(true, false, Some(class.as_str()))
    }

    pub fn foreground_is_external(main_window: isize) -> bool {
        external_window(main_window, unsafe { GetForegroundWindow() })
    }

    pub fn foreground_is_owned(main_window: isize) -> bool {
        window_is_owned(main_window, unsafe { GetForegroundWindow() })
    }
}

#[cfg(target_os = "windows")]
pub use native::*;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_click_and_first_click_have_no_sampling_or_initial_discard() {
        let gate = Gate::default();
        gate.arm(12, false);
        let token = gate.token().unwrap();
        // A down then up entirely between old 20ms polling samples still has
        // its own down record. No current-button-state field is required.
        let click = Click { token, x: 5, y: 5 };
        assert!(gate.is_current(click.token));
        assert!(outside_bounds(click, 100, 100, 680, 300));
    }

    #[test]
    fn old_click_and_blur_cannot_dismiss_new_epoch_or_same_epoch_rearm() {
        let gate = Gate::default();
        gate.arm(12, true);
        let old = gate.token().unwrap();
        gate.disarm();
        assert!(!gate.is_current(old));
        gate.arm(13, true);
        assert!(!gate.is_current(old));
        assert!(!gate.may_dismiss_blur(old, true));
        let before_pin_or_management = gate.token().unwrap();
        gate.disarm();
        gate.arm(13, true);
        assert!(!gate.is_current(before_pin_or_management));
    }

    #[test]
    fn repeated_content_fits_preserve_current_click_and_focus_tokens() {
        let gate = Gate::default();
        gate.arm(12, false);
        let token = gate.token().unwrap();
        gate.arm(12, false);
        assert!(gate.is_current(token));
        gate.arm(12, true);
        assert!(gate.is_current(token));
        assert!(gate.may_dismiss_blur(token, true));
    }

    #[test]
    fn passive_popup_ignores_initial_blur_and_own_or_ime_focus() {
        let gate = Gate::default();
        gate.arm(12, false);
        let token = gate.token().unwrap();
        assert!(!gate.may_dismiss_blur(token, true));
        gate.mark_focused(token);
        assert!(!gate.may_dismiss_blur(token, false));
        assert!(gate.may_dismiss_blur(token, true));
        gate.arm(13, false);
        gate.mark_focused(token); // A stale focus notification cannot arm it.
        assert!(!gate.may_dismiss_blur(gate.token().unwrap(), true));
    }

    #[test]
    fn physical_rectangles_handle_negative_displays_boundaries_and_large_sizes() {
        let gate = Gate::default();
        gate.arm(1, false);
        let click = |x, y| Click {
            token: gate.token().unwrap(),
            x,
            y,
        };
        assert!(!outside_bounds(click(-1800, -200), -1800, -200, 1020, 450));
        assert!(!outside_bounds(click(-781, 249), -1800, -200, 1020, 450));
        assert!(outside_bounds(click(-780, 250), -1800, -200, 1020, 450));
        assert!(!outside_bounds(
            click(i32::MAX, 0),
            i32::MAX - 1,
            0,
            u32::MAX,
            1
        ));
    }

    #[test]
    fn inside_down_cannot_become_outside_after_drag_or_resize() {
        let gate = Gate::default();
        gate.arm(3, true);
        let token = gate.token().unwrap();
        // It was inside the toolbar at down; even if asynchronous handling is
        // delayed until the window moves, no dismissal event was queued.
        assert!(observe_down(token, 150, 110, 100, 100, 680, 300).is_none());
        let old_inside = Click {
            token,
            x: 150,
            y: 110,
        };
        assert!(outside_bounds(old_inside, 400, 300, 680, 300));
        assert!(observe_down(token, 779, 399, 100, 100, 680, 300).is_none());
        // An outside observation overtaken by movement under the pointer is
        // also rejected by the processing-time bounds check.
        let outside = observe_down(token, 800, 400, 100, 100, 680, 300).unwrap();
        assert!(!outside_bounds(outside, 700, 300, 680, 300));
    }

    #[test]
    fn focus_classification_preserves_owned_dialog_ime_and_unknown_targets() {
        assert!(!external_focus(false, false, Some("Chrome_WidgetWin_1")));
        assert!(!external_focus(true, true, Some("#32770")));
        assert!(!external_focus(true, false, None));
        for class in ["IME", "MSCTFIME UI", "CiceroUIWndFrame"] {
            assert!(!external_focus(true, false, Some(class)));
        }
        assert!(external_focus(true, false, Some("Chrome_WidgetWin_1")));
        assert!(external_focus(true, false, Some("#32770")));
    }
}
