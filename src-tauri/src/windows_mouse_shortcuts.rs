//! One native pump for exact Alt+D / Alt+S priority and optional MouseX1/X2.
//! Hooks transfer scalar pairs only. They never read text, call Tauri, wait for
//! IPC, or take application locks. Other key/button combinations pass through.
use crate::mouse_shortcuts::{self as policy, Context, Policy};
use std::{
    cell::RefCell,
    ffi::c_void,
    sync::{
        atomic::{AtomicBool, AtomicIsize, AtomicU32, AtomicU64, AtomicU8, Ordering},
        mpsc::{self, Receiver, SyncSender},
        Mutex, OnceLock,
    },
    thread::JoinHandle,
    time::Duration,
};
type Handle = *mut c_void;
const MASK_MARKER: usize = 0x4543484f;
const CONTROL_MESSAGE: u32 = 0x83d0;
const REFRESH_MESSAGE: u32 = 0x83d1;
const RECOVER_MESSAGE: u32 = 0x83d2;
const RECOVER_CONFIG: u8 = 1;
const RECOVER_FOREGROUND: u8 = 2;
const RECOVER_EXPLICIT: u8 = 4;
enum Control {
    EnsureMouse(SyncSender<Result<(), String>>),
}
#[derive(Clone, Copy, Debug)]
pub struct Event {
    pub id: u32,
    pub context: Context,
}
struct Shared {
    enabled: AtomicU8,
    generation: AtomicU64,
    recording: AtomicU64,
    recording_deadline: AtomicU64,
    priority_ids: [u32; 2],
    management: AtomicBool,
    mouse_reserved: AtomicBool,
    mouse_installed: AtomicBool,
    window: AtomicIsize,
    alive: AtomicBool,
    stopping: AtomicBool,
    thread: AtomicU32,
    events: SyncSender<Event>,
    controls: mpsc::Sender<Control>,
    recovery_pending: AtomicU8,
    recovery_queued: AtomicBool,
    recovery_foreground: AtomicIsize,
    release_hints: AtomicU32,
    health: Health,
}
#[derive(Default)]
struct Health {
    keyboard_installed: AtomicU64,
    foreground_installed: AtomicU64,
    recovery_requests: AtomicU64,
    recovery_attempts: AtomicU64,
    recovery_successes: AtomicU64,
    recovery_failures: AtomicU64,
    recovery_deferred: AtomicU64,
    recovery_last_error: AtomicU64,
    recovery_last_reason: AtomicU64,
    recovery_retire_failures: AtomicU64,
    recovery_owned_pairs_blocked: AtomicU64,
    foreground_events: AtomicU64,
    priority_down: AtomicU64,
    priority_up: AtomicU64,
    priority_pairs_accepted: AtomicU64,
    priority_pairs_discarded: AtomicU64,
    events_enqueued: AtomicU64,
    events_queue_full: AtomicU64,
    events_stale_context: AtomicU64,
}
static SHARED: OnceLock<Shared> = OnceLock::new();
static THREAD: Mutex<Option<JoinHandle<()>>> = Mutex::new(None);
static CONFIG: Mutex<()> = Mutex::new(());
thread_local! { static PAIRS:RefCell<Policy>=RefCell::new(Policy::default()); }
#[repr(C)]
struct Point {
    x: i32,
    y: i32,
}
#[repr(C)]
struct Message {
    window: Handle,
    message: u32,
    word: usize,
    param: isize,
    time: u32,
    point: Point,
    private: u32,
}
#[repr(C)]
struct GuiThreadInfo {
    size: u32,
    flags: u32,
    active: Handle,
    focus: Handle,
    capture: Handle,
    menu: Handle,
    moving: Handle,
    caret: Handle,
    caret_rect: [i32; 4],
}
#[repr(C)]
struct Keyboard {
    key: u32,
    scan: u32,
    flags: u32,
    time: u32,
    extra: usize,
}
#[repr(C)]
struct Mouse {
    point: Point,
    data: u32,
    flags: u32,
    time: u32,
    extra: usize,
}
#[repr(C)]
#[derive(Clone, Copy)]
struct KeyInput {
    key: u16,
    scan: u16,
    flags: u32,
    time: u32,
    extra: usize,
}
#[repr(C)]
#[derive(Clone, Copy)]
struct MouseInput {
    x: i32,
    y: i32,
    data: u32,
    flags: u32,
    time: u32,
    extra: usize,
}
#[repr(C)]
union InputData {
    key: KeyInput,
    mouse: MouseInput,
}
#[repr(C)]
struct Input {
    kind: u32,
    data: InputData,
}
type Hook = unsafe extern "system" fn(i32, usize, isize) -> isize;
type WinEvent = unsafe extern "system" fn(Handle, u32, Handle, i32, i32, u32, u32);
#[link(name = "user32")]
unsafe extern "system" {
    fn SetWindowsHookExW(kind: i32, callback: Option<Hook>, module: Handle, thread: u32) -> Handle;
    fn CallNextHookEx(hook: Handle, code: i32, word: usize, param: isize) -> isize;
    fn UnhookWindowsHookEx(hook: Handle) -> i32;
    fn GetMessageW(message: *mut Message, window: Handle, min: u32, max: u32) -> i32;
    fn PeekMessageW(message: *mut Message, window: Handle, min: u32, max: u32, remove: u32) -> i32;
    fn PostThreadMessageW(thread: u32, message: u32, word: usize, param: isize) -> i32;
    fn GetAsyncKeyState(key: i32) -> i16;
    fn GetForegroundWindow() -> Handle;
    fn GetWindowThreadProcessId(window: Handle, process: *mut u32) -> u32;
    fn GetGUIThreadInfo(thread: u32, info: *mut GuiThreadInfo) -> i32;
    fn SendInput(count: u32, values: *const Input, size: i32) -> u32;
    fn SetWinEventHook(
        minimum: u32,
        maximum: u32,
        module: Handle,
        callback: Option<WinEvent>,
        process: u32,
        thread: u32,
        flags: u32,
    ) -> Handle;
    fn UnhookWinEvent(hook: Handle) -> i32;
}
#[link(name = "kernel32")]
unsafe extern "system" {
    fn GetModuleHandleW(name: *const u16) -> Handle;
    fn GetCurrentThreadId() -> u32;
    fn GetTickCount64() -> u64;
    fn GetLastError() -> u32;
}
fn context(s: &Shared) -> Context {
    let recording = s.recording.load(Ordering::SeqCst);
    let foreground = unsafe { GetForegroundWindow() } as isize;
    let own = foreground == s.window.load(Ordering::SeqCst);
    let mut gui: GuiThreadInfo = unsafe { std::mem::zeroed() };
    gui.size = std::mem::size_of::<GuiThreadInfo>() as u32;
    let thread = if foreground == 0 {
        0
    } else {
        unsafe { GetWindowThreadProcessId(foreground as Handle, std::ptr::null_mut()) }
    };
    let focus = if thread != 0 && unsafe { GetGUIThreadInfo(thread, &mut gui) } != 0 {
        gui.focus as isize
    } else {
        0
    };
    let recording = if own
        && s.management.load(Ordering::SeqCst)
        && unsafe { GetTickCount64() } < s.recording_deadline.load(Ordering::SeqCst)
    {
        recording
    } else {
        0
    };
    Context {
        generation: s.generation.load(Ordering::SeqCst),
        foreground,
        focus,
        capture: crate::windows_capture_input::current_token(),
        recording,
        blocked: own && s.management.load(Ordering::SeqCst) && recording == 0,
    }
}
fn modifiers(alt: bool) -> bool {
    alt && [0x11, 0x10, 0x5b, 0x5c]
        .into_iter()
        .all(|key| unsafe { GetAsyncKeyState(key) } >= 0)
}
fn queue(s: &Shared, id: u32, c: Context) {
    if s.events.try_send(Event { id, context: c }).is_ok() {
        s.health.events_enqueued.fetch_add(1, Ordering::Relaxed);
    } else {
        s.health.events_queue_full.fetch_add(1, Ordering::Relaxed);
    }
}
fn post_recovery(s: &Shared) -> bool {
    if s.recovery_pending.load(Ordering::SeqCst) == 0
        || s.recovery_queued.swap(true, Ordering::SeqCst)
    {
        return true;
    }
    if unsafe { PostThreadMessageW(s.thread.load(Ordering::SeqCst), RECOVER_MESSAGE, 0, 0) } == 0 {
        s.recovery_queued.store(false, Ordering::SeqCst);
        s.health
            .recovery_last_error
            .store(unsafe { GetLastError() } as u64, Ordering::Relaxed);
        return false;
    }
    true
}
fn request_recovery(s: &Shared, reason: u8) -> bool {
    s.health.recovery_requests.fetch_add(1, Ordering::Relaxed);
    s.recovery_pending.fetch_or(reason, Ordering::SeqCst);
    post_recovery(s)
}
unsafe extern "system" fn foreground_event(
    _: Handle,
    event: u32,
    window: Handle,
    _: i32,
    _: i32,
    _: u32,
    _: u32,
) {
    // WINEVENT_SKIPOWNPROCESS excludes our popup and capture overlays. The
    // callback records only scalar metadata and wakes the dedicated pump.
    if event == 3 && !window.is_null() {
        if let Some(s) = SHARED
            .get()
            .filter(|s| s.alive.load(Ordering::SeqCst) && !s.stopping.load(Ordering::SeqCst))
        {
            s.health.foreground_events.fetch_add(1, Ordering::Relaxed);
            s.recovery_foreground
                .store(window as isize, Ordering::SeqCst);
            let _ = request_recovery(s, RECOVER_FOREGROUND);
        }
    }
}
fn physical_recovery_keys() -> u16 {
    [0x44, 0x53, 0xa4, 0xa5, 0xa2, 0xa3, 0xa0, 0xa1, 0x5b, 0x5c]
        .into_iter()
        .fold(0, |held, key| {
            held | if unsafe { GetAsyncKeyState(key as i32) } < 0 {
                policy::recovery_key_bit(key, 0, false)
            } else {
                0
            }
        })
}
fn mask_alt() {
    let key = |flags| Input {
        kind: 1,
        data: InputData {
            key: KeyInput {
                key: 0xe8,
                scan: 0,
                flags,
                time: 0,
                extra: MASK_MARKER,
            },
        },
    };
    let values = [key(0), key(2)];
    if unsafe { SendInput(2, values.as_ptr(), std::mem::size_of::<Input>() as i32) } == 1 {
        let up = [key(2)];
        unsafe { SendInput(1, up.as_ptr(), std::mem::size_of::<Input>() as i32) };
    }
}
unsafe extern "system" fn keyboard(code: i32, word: usize, param: isize) -> isize {
    if code == 0 && param != 0 {
        if let Some(s) = SHARED
            .get()
            .filter(|s| s.alive.load(Ordering::SeqCst) && !s.stopping.load(Ordering::SeqCst))
        {
            let k = unsafe { &*(param as *const Keyboard) };
            // Keep remapped/accessibility input usable; reject only our own mask and
            // lower-integrity injections. Normal SendInput remains testable on Windows.
            if k.extra != MASK_MARKER && k.flags & 2 == 0 {
                let down = matches!(word, 0x100 | 0x104);
                let up = matches!(word, 0x101 | 0x105);
                if down || up {
                    let recovery_key =
                        policy::recovery_key_bit(k.key, k.scan, k.flags & 1 != 0) as u32;
                    if down && recovery_key != 0 {
                        s.release_hints.fetch_and(!recovery_key, Ordering::SeqCst);
                    } else if recovery_key != 0 && s.recovery_pending.load(Ordering::SeqCst) != 0 {
                        s.release_hints.fetch_or(recovery_key, Ordering::SeqCst);
                        let _ = post_recovery(s);
                    }
                    let alt = matches!(k.key, 0x12 | 0xa4 | 0xa5);
                    if alt && up {
                        if PAIRS.with(|p| p.borrow_mut().alt_release()) {
                            mask_alt();
                        }
                    } else if let Some((slot, bit, id)) = match k.key {
                        0x44 => Some((0, policy::PRIORITY_D, s.priority_ids[0])),
                        0x53 => Some((1, policy::PRIORITY_S, s.priority_ids[1])),
                        _ => None,
                    } {
                        let exact = s.enabled.load(Ordering::SeqCst) & bit != 0
                            && modifiers(k.flags & 0x20 != 0);
                        if !exact && !PAIRS.with(|p| p.borrow().owns(slot)) {
                            return unsafe {
                                CallNextHookEx(std::ptr::null_mut(), code, word, param)
                            };
                        }
                        if down {
                            s.health.priority_down.fetch_add(1, Ordering::Relaxed);
                        }
                        if up {
                            s.health.priority_up.fetch_add(1, Ordering::Relaxed);
                        }
                        let mut c = context(s);
                        c.capture = 0;
                        let enabled = exact;
                        let d = PAIRS.with(|p| p.borrow_mut().pair(slot, down, enabled, c));
                        if d.release {
                            s.health
                                .priority_pairs_accepted
                                .fetch_add(1, Ordering::Relaxed);
                            queue(s, id, d.context);
                        } else if up && d.consume {
                            s.health
                                .priority_pairs_discarded
                                .fetch_add(1, Ordering::Relaxed);
                        }
                        if d.consume {
                            return 1;
                        }
                    } else if down && !alt {
                        PAIRS.with(|p| p.borrow_mut().unrelated_key());
                    }
                }
            }
        }
    }
    unsafe { CallNextHookEx(std::ptr::null_mut(), code, word, param) }
}
unsafe extern "system" fn mouse(code: i32, word: usize, param: isize) -> isize {
    if code == 0 {
        if let Some(s) = SHARED.get() {
            let lease = s.recording.load(Ordering::SeqCst);
            if lease != 0
                && unsafe { GetTickCount64() } >= s.recording_deadline.load(Ordering::SeqCst)
                && s.recording
                    .compare_exchange(lease, 0, Ordering::SeqCst, Ordering::SeqCst)
                    .is_ok()
            {
                invalidate();
                refresh(s);
            }
        }
    }
    if code == 0 && param != 0 && matches!(word, 0x20b | 0x20c) {
        if let Some(s) = SHARED
            .get()
            .filter(|s| s.alive.load(Ordering::SeqCst) && !s.stopping.load(Ordering::SeqCst))
        {
            let m = unsafe { &*(param as *const Mouse) };
            if m.extra != MASK_MARKER && m.flags & 2 == 0 {
                if let Some((slot, button)) = match m.data >> 16 {
                    1 => Some((2, policy::Button::X1)),
                    2 => Some((3, policy::Button::X2)),
                    _ => None,
                } {
                    let bound = s.enabled.load(Ordering::SeqCst) & button.bit() != 0
                        || s.recording.load(Ordering::SeqCst) != 0;
                    if !bound && !PAIRS.with(|p| p.borrow().owns(slot)) {
                        return unsafe { CallNextHookEx(std::ptr::null_mut(), code, word, param) };
                    }
                    let c = context(s);
                    let plain = [0x11, 0x12, 0x10, 0x5b, 0x5c]
                        .into_iter()
                        .all(|key| unsafe { GetAsyncKeyState(key) } >= 0);
                    let enabled = plain
                        && c.capture == 0
                        && (s.enabled.load(Ordering::SeqCst) & button.bit() != 0
                            || c.recording != 0);
                    let d = PAIRS.with(|p| p.borrow_mut().pair(slot, word == 0x20b, enabled, c));
                    if d.release {
                        queue(s, button.id(), d.context);
                    }
                    if word == 0x20c {
                        refresh(s);
                    }
                    if d.consume {
                        return 1;
                    }
                }
            }
        }
    }
    unsafe { CallNextHookEx(std::ptr::null_mut(), code, word, param) }
}
fn recover_keyboard(s: &Shared, keyboard: &mut Handle, orphan: &mut Option<Handle>) {
    s.recovery_queued.store(false, Ordering::SeqCst);
    let reason = s.recovery_pending.swap(0, Ordering::SeqCst);
    if reason == 0
        || s.enabled.load(Ordering::SeqCst) & (policy::PRIORITY_D | policy::PRIORITY_S) == 0
    {
        s.release_hints.store(0, Ordering::SeqCst);
        return;
    }
    // Query outside the low-level callback: that callback precedes Windows'
    // async-state update. Its observed ups only bridge that specific delivery
    // gap; a subsequent down clears the corresponding hint.
    let physical = physical_recovery_keys();
    let released = s.release_hints.swap(0, Ordering::SeqCst) as u16;
    let held = physical & !released;
    let (ready, owned) = PAIRS.with(|pairs| {
        let pairs = pairs.borrow();
        (pairs.can_recover_keyboard(held), pairs.keyboard_owned())
    });
    if !ready {
        if owned {
            s.health
                .recovery_owned_pairs_blocked
                .fetch_add(1, Ordering::Relaxed);
        }
        s.recovery_pending.fetch_or(reason, Ordering::SeqCst);
        s.health.recovery_deferred.fetch_add(1, Ordering::Relaxed);
        return;
    }
    if reason == RECOVER_FOREGROUND
        && s.recovery_foreground.load(Ordering::SeqCst) != unsafe { GetForegroundWindow() } as isize
    {
        return;
    }
    s.health
        .recovery_last_reason
        .store(reason as u64, Ordering::Relaxed);
    s.health.recovery_attempts.fetch_add(1, Ordering::Relaxed);
    if orphan.is_some() {
        s.health.recovery_last_error.store(170, Ordering::Relaxed);
        s.health.recovery_failures.fetch_add(1, Ordering::Relaxed);
        return; // A failed rollback is bounded to one handle until shutdown.
    }
    let replacement = unsafe {
        SetWindowsHookExW(
            13,
            Some(self::keyboard),
            GetModuleHandleW(std::ptr::null()),
            0,
        )
    };
    if replacement.is_null() {
        s.health
            .recovery_last_error
            .store(unsafe { GetLastError() } as u64, Ordering::Relaxed);
        s.health.recovery_failures.fetch_add(1, Ordering::Relaxed);
        return; // Keep the old handle; only a new explicit/event request retries.
    }
    if unsafe { UnhookWindowsHookEx(*keyboard) } == 0 {
        let error = unsafe { GetLastError() };
        if !matches!(error, 6 | 1404) {
            s.health
                .recovery_last_error
                .store(error as u64, Ordering::Relaxed);
            s.health.recovery_failures.fetch_add(1, Ordering::Relaxed);
            if unsafe { UnhookWindowsHookEx(replacement) } == 0 {
                *orphan = Some(replacement);
                s.health
                    .recovery_retire_failures
                    .fetch_add(1, Ordering::Relaxed);
            }
            return; // The original hook and pair ownership remain intact.
        }
    } else {
        s.health.recovery_last_error.store(0, Ordering::Relaxed);
    }
    *keyboard = replacement;
    s.health.recovery_successes.fetch_add(1, Ordering::Relaxed);
}
pub fn start(priority_ids: [u32; 2]) -> Result<Receiver<Event>, String> {
    let mut runtime = THREAD.lock().map_err(|_| "输入监听状态异常")?;
    if SHARED.get().is_some() {
        return Err("Windows 输入监听已经初始化".into());
    }
    let (sender, receiver) = mpsc::sync_channel(64);
    let (ready, status) = mpsc::sync_channel(1);
    let (controls, commands) = mpsc::channel();
    SHARED
        .set(Shared {
            enabled: AtomicU8::new(0),
            generation: AtomicU64::new(1),
            recording: AtomicU64::new(0),
            recording_deadline: AtomicU64::new(0),
            priority_ids,
            management: AtomicBool::new(false),
            mouse_reserved: AtomicBool::new(false),
            mouse_installed: AtomicBool::new(false),
            window: AtomicIsize::new(0),
            alive: AtomicBool::new(false),
            stopping: AtomicBool::new(false),
            thread: AtomicU32::new(0),
            events: sender,
            controls,
            recovery_pending: AtomicU8::new(0),
            recovery_queued: AtomicBool::new(false),
            recovery_foreground: AtomicIsize::new(0),
            release_hints: AtomicU32::new(0),
            health: Health::default(),
        })
        .map_err(|_| "输入监听重复初始化")?;
    let handle = std::thread::Builder::new()
        .name("shortcut-input-pump".into())
        .spawn(move || {
            let s = SHARED.get().expect("input initialized");
            let mut msg: Message = unsafe { std::mem::zeroed() };
            unsafe { PeekMessageW(&mut msg, std::ptr::null_mut(), 0, 0, 0) };
            s.thread
                .store(unsafe { GetCurrentThreadId() }, Ordering::SeqCst);
            let mut keyboard = unsafe {
                SetWindowsHookExW(13, Some(keyboard), GetModuleHandleW(std::ptr::null()), 0)
            };
            let mut mouse: Handle = std::ptr::null_mut();
            if keyboard.is_null() {
                let error = std::io::Error::last_os_error();
                let _ = ready.send(Err(format!("Windows 键盘监听安装失败：{error}")));
                s.thread.store(0, Ordering::SeqCst);
                return;
            }
            s.health.keyboard_installed.store(1, Ordering::Relaxed);
            let foreground = unsafe {
                SetWinEventHook(3, 3, std::ptr::null_mut(), Some(foreground_event), 0, 0, 2)
            };
            if foreground.is_null() {
                let error = std::io::Error::last_os_error();
                unsafe { UnhookWindowsHookEx(keyboard) };
                s.health.keyboard_installed.store(0, Ordering::Relaxed);
                s.health
                    .recovery_last_error
                    .store(error.raw_os_error().unwrap_or(0) as u64, Ordering::Relaxed);
                s.thread.store(0, Ordering::SeqCst);
                let _ = ready.send(Err(format!("Windows 前台事件监听安装失败：{error}")));
                return;
            }
            s.health.foreground_installed.store(1, Ordering::Relaxed);
            let mut orphan = None;
            if s.stopping.load(Ordering::SeqCst) {
                unsafe {
                    UnhookWindowsHookEx(mouse);
                    UnhookWindowsHookEx(keyboard);
                    UnhookWinEvent(foreground);
                }
                s.health.keyboard_installed.store(0, Ordering::Relaxed);
                s.health.foreground_installed.store(0, Ordering::Relaxed);
                s.thread.store(0, Ordering::SeqCst);
                let _ = ready.send(Err("输入监听已停止".into()));
                return;
            }
            s.alive.store(true, Ordering::SeqCst);
            let _ = ready.send(Ok(()));
            while unsafe { GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) } > 0 {
                if msg.message == CONTROL_MESSAGE {
                    while let Ok(Control::EnsureMouse(reply)) = commands.try_recv() {
                        if mouse.is_null() {
                            mouse = unsafe {
                                SetWindowsHookExW(
                                    14,
                                    Some(self::mouse),
                                    GetModuleHandleW(std::ptr::null()),
                                    0,
                                )
                            };
                        }
                        s.mouse_installed.store(!mouse.is_null(), Ordering::SeqCst);
                        let result = if mouse.is_null() {
                            Err(format!(
                                "Windows 鼠标侧键监听安装失败：{}",
                                std::io::Error::last_os_error()
                            ))
                        } else {
                            Ok(())
                        };
                        let _ = reply.send(result);
                    }
                } else if msg.message == RECOVER_MESSAGE {
                    recover_keyboard(s, &mut keyboard, &mut orphan);
                } else if msg.message == REFRESH_MESSAGE
                    && !mouse_needed(s)
                    && !PAIRS.with(|pairs| pairs.borrow().mouse_owned())
                    && !mouse.is_null()
                {
                    if unsafe { UnhookWindowsHookEx(mouse) } != 0 {
                        mouse = std::ptr::null_mut();
                        s.mouse_installed.store(false, Ordering::SeqCst);
                    }
                }
            }
            unsafe {
                UnhookWindowsHookEx(mouse);
                UnhookWindowsHookEx(keyboard);
                UnhookWinEvent(foreground);
                if let Some(hook) = orphan {
                    UnhookWindowsHookEx(hook);
                }
            }
            s.health.keyboard_installed.store(0, Ordering::Relaxed);
            s.health.foreground_installed.store(0, Ordering::Relaxed);
            s.mouse_installed.store(false, Ordering::SeqCst);
            s.alive.store(false, Ordering::SeqCst);
            s.thread.store(0, Ordering::SeqCst);
            let _ = s.events.try_send(Event {
                id: 0,
                context: Context::default(),
            });
        })
        .map_err(|e| format!("无法启动输入监听：{e}"))?;
    match status.recv_timeout(Duration::from_secs(3)) {
        Ok(Ok(())) => {
            *runtime = Some(handle);
            Ok(receiver)
        }
        Ok(Err(e)) => {
            let _ = handle.join();
            Err(e)
        }
        Err(_) => {
            SHARED.get().unwrap().stopping.store(true, Ordering::SeqCst);
            let id = SHARED.get().unwrap().thread.load(Ordering::SeqCst);
            if id != 0 {
                unsafe { PostThreadMessageW(id, 0x12, 0, 0) };
            }
            *runtime = Some(handle);
            Err("Windows 输入监听启动未完成".into())
        }
    }
}
fn refresh(s: &Shared) {
    let id = s.thread.load(Ordering::SeqCst);
    if id != 0 {
        unsafe {
            PostThreadMessageW(id, REFRESH_MESSAGE, 0, 0);
        }
    }
}
fn mouse_needed(s: &Shared) -> bool {
    s.mouse_reserved.load(Ordering::SeqCst)
        || s.enabled.load(Ordering::SeqCst) & (policy::MOUSE_X1 | policy::MOUSE_X2) != 0
        || (s.recording.load(Ordering::SeqCst) != 0
            && unsafe { GetTickCount64() } < s.recording_deadline.load(Ordering::SeqCst))
}
struct MouseReservation<'a>(&'a Shared);
impl Drop for MouseReservation<'_> {
    fn drop(&mut self) {
        self.0.mouse_reserved.store(false, Ordering::SeqCst);
        refresh(self.0);
    }
}
fn ensure_mouse(s: &Shared) -> Result<MouseReservation<'_>, String> {
    // Public configuration calls hold CONFIG. Reserve ownership before waking
    // the pump so a queued old refresh cannot remove an acknowledged hook
    // before this caller publishes its binding or recording lease.
    s.mouse_reserved.store(true, Ordering::SeqCst);
    let reservation = MouseReservation(s);
    let (reply, answer) = mpsc::sync_channel(1);
    s.controls
        .send(Control::EnsureMouse(reply))
        .map_err(|_| "鼠标侧键监听线程已结束")?;
    if unsafe { PostThreadMessageW(s.thread.load(Ordering::SeqCst), CONTROL_MESSAGE, 0, 0) } == 0 {
        return Err(format!(
            "无法通知鼠标侧键监听：{}",
            std::io::Error::last_os_error()
        ));
    }
    answer
        .recv_timeout(Duration::from_secs(3))
        .map_err(|_| "鼠标侧键监听未就绪".to_string())??;
    Ok(reservation)
}
pub fn register(bit: u8) -> Result<(), String> {
    let _config = CONFIG.lock().map_err(|_| "输入设置状态异常")?;
    if bit & !(policy::PRIORITY_D | policy::PRIORITY_S | policy::MOUSE_X1 | policy::MOUSE_X2) != 0 {
        return Err("输入绑定无效".into());
    }
    let s = SHARED
        .get()
        .filter(|s| s.alive.load(Ordering::SeqCst) && !s.stopping.load(Ordering::SeqCst))
        .ok_or("Windows 输入监听不可用，请重启应用或选择其他键盘快捷键")?;
    let _reservation = if bit & (policy::MOUSE_X1 | policy::MOUSE_X2) != 0 {
        Some(ensure_mouse(s)?)
    } else {
        None
    };
    let previous = s.enabled.fetch_or(bit, Ordering::SeqCst);
    invalidate();
    if bit & (policy::PRIORITY_D | policy::PRIORITY_S) != 0 && !request_recovery(s, RECOVER_CONFIG)
    {
        s.enabled.store(previous, Ordering::SeqCst);
        invalidate();
        // Match the registration transaction's all-or-rollback contract.
        return Err(format!(
            "键盘监听恢复通知失败：{}",
            s.health.recovery_last_error.load(Ordering::Relaxed)
        ));
    }
    Ok(())
}
pub fn unregister(bit: u8) -> Result<(), String> {
    let _config = CONFIG.lock().map_err(|_| "输入设置状态异常")?;
    let s = SHARED.get().ok_or("Windows 输入监听未初始化")?;
    s.enabled.fetch_and(!bit, Ordering::SeqCst);
    invalidate();
    refresh(s);
    Ok(())
}
pub fn invalidate() {
    if let Some(s) = SHARED.get() {
        s.generation.fetch_add(1, Ordering::SeqCst);
    }
}
pub fn set_context(window: isize, management: bool) {
    if let Some(s) = SHARED.get() {
        let changed = s.window.swap(window, Ordering::SeqCst) != window;
        let changed = s.management.swap(management, Ordering::SeqCst) != management || changed;
        if changed {
            invalidate();
        }
    }
}
pub fn recording(lease: u64) -> Result<(), String> {
    let _config = CONFIG.lock().map_err(|_| "输入设置状态异常")?;
    let deadline = if lease == 0 {
        0
    } else {
        unsafe { GetTickCount64() }.saturating_add(15_000)
    };
    if let Some(s) = SHARED.get() {
        let _reservation = if lease != 0 {
            Some(ensure_mouse(s)?)
        } else {
            None
        };
        s.recording_deadline.store(deadline, Ordering::SeqCst);
        if s.recording.swap(lease, Ordering::SeqCst) != lease {
            invalidate();
        }
        if lease == 0 {
            refresh(s);
        }
        Ok(())
    } else if lease == 0 {
        Ok(())
    } else {
        Err("Windows 输入监听未初始化".into())
    }
}
/// A delayed end for an old editor must not terminate a newer recording.
pub fn end_recording(lease: u64) {
    if let Some(s) = SHARED.get() {
        if s.recording
            .compare_exchange(lease, 0, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok()
        {
            invalidate();
            refresh(s);
        }
    }
}
pub fn current(event: Event) -> bool {
    let current = SHARED.get().is_some_and(|s| {
        !s.stopping.load(Ordering::SeqCst) && s.alive.load(Ordering::SeqCst) && {
            let mut c = context(s);
            if s.priority_ids.contains(&event.id) {
                c.capture = 0;
            }
            c.matches(event.context)
        }
    });
    if !current {
        if let Some(s) = SHARED.get() {
            s.health
                .events_stale_context
                .fetch_add(1, Ordering::Relaxed);
        }
    }
    current
}
/// Request one coalesced, event-driven recovery. Acceptance is not completion;
/// held keys defer it, and diagnostics report the actual attempt and result.
pub fn request_keyboard_recovery() -> Result<(), String> {
    let s = SHARED
        .get()
        .filter(|s| s.alive.load(Ordering::SeqCst) && !s.stopping.load(Ordering::SeqCst))
        .ok_or("Windows 输入监听不可用")?;
    if request_recovery(s, RECOVER_EXPLICIT) {
        Ok(())
    } else {
        Err(format!(
            "键盘监听恢复通知失败：{}",
            s.health.recovery_last_error.load(Ordering::Relaxed)
        ))
    }
}
/// Numeric metadata only. No titles, key log, clipboard or source text.
pub fn diagnostics() -> Vec<(&'static str, u64)> {
    let shared = SHARED.get();
    macro_rules! counter {
        ($name:literal, $field:ident) => {
            (
                $name,
                shared
                    .map(|s| s.health.$field.load(Ordering::Relaxed))
                    .unwrap_or(0),
            )
        };
    }
    vec![
        ("hookRunning", u64::from(running())),
        (
            "recoveryPending",
            shared
                .map(|s| s.recovery_pending.load(Ordering::SeqCst) as u64)
                .unwrap_or(0),
        ),
        counter!("keyboardHookInstalled", keyboard_installed),
        counter!("foregroundHookInstalled", foreground_installed),
        counter!("recoveryRequests", recovery_requests),
        counter!("recoveryAttempts", recovery_attempts),
        counter!("recoverySuccesses", recovery_successes),
        counter!("recoveryFailures", recovery_failures),
        counter!("recoveryDeferred", recovery_deferred),
        counter!("recoveryLastError", recovery_last_error),
        counter!("recoveryLastReason", recovery_last_reason),
        counter!("recoveryRetireFailures", recovery_retire_failures),
        counter!("recoveryOwnedPairsBlocked", recovery_owned_pairs_blocked),
        counter!("foregroundEvents", foreground_events),
        counter!("priorityKeyDownObserved", priority_down),
        counter!("priorityKeyUpObserved", priority_up),
        counter!("priorityPairsAccepted", priority_pairs_accepted),
        counter!("priorityPairsDiscarded", priority_pairs_discarded),
        counter!("eventsEnqueued", events_enqueued),
        counter!("eventsQueueFull", events_queue_full),
        counter!("eventsStaleContext", events_stale_context),
    ]
}
pub fn stop() {
    if let Some(s) = SHARED.get() {
        s.stopping.store(true, Ordering::SeqCst);
        let _ = s.events.try_send(Event {
            id: 0,
            context: Context::default(),
        });
        let id = s.thread.load(Ordering::SeqCst);
        if id != 0 {
            unsafe { PostThreadMessageW(id, 0x12, 0, 0) };
        }
    }
    if let Ok(mut runtime) = THREAD.lock() {
        if let Some(thread) = runtime.take() {
            let _ = thread.join();
        }
    }
}

pub fn active(bit: u8) -> bool {
    SHARED.get().is_some_and(|s| {
        s.alive.load(Ordering::SeqCst)
            && !s.stopping.load(Ordering::SeqCst)
            && s.enabled.load(Ordering::SeqCst) & bit != 0
            && (bit & (policy::MOUSE_X1 | policy::MOUSE_X2) == 0
                || s.mouse_installed.load(Ordering::SeqCst))
    })
}

pub fn running() -> bool {
    SHARED
        .get()
        .is_some_and(|s| s.alive.load(Ordering::SeqCst) && !s.stopping.load(Ordering::SeqCst))
}
