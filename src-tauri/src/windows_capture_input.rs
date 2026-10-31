//! Session-scoped legacy mouse ownership on the existing native hook thread.
//! No foreground changes, content capture, locks or remote HWND queries in the
//! synchronous hook path. The C# picker receives scalar, generation-bound input.

use std::sync::atomic::{AtomicBool, AtomicIsize, AtomicU32, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

#[path = "windows_capture_protocol.rs"]
mod protocol;
pub use protocol::*;
const ARMED: u32 = 1;
const LEFT: u32 = 2;
const RIGHT: u32 = 4;
const MIDDLE: u32 = 8;
const X1: u32 = 16;
const X2: u32 = 32;
const BUTTONS: u32 = LEFT | RIGHT | MIDDLE | X1 | X2;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Decision {
    flags: u32,
    consume: bool,
    message: u32,
}
fn arm(flags: u32, physical: u32, closing: bool) -> Option<u32> {
    (!closing && physical == 0 && flags & BUTTONS == 0).then_some(ARMED)
}
fn button(kind: u32, data: u32) -> Option<(u32, bool)> {
    match kind {
        0x0201 => Some((LEFT, true)),
        0x0202 => Some((LEFT, false)),
        0x0204 => Some((RIGHT, true)),
        0x0205 => Some((RIGHT, false)),
        0x0207 => Some((MIDDLE, true)),
        0x0208 => Some((MIDDLE, false)),
        0x020b | 0x020c => match data >> 16 {
            1 => Some((X1, kind == 0x020b)),
            2 => Some((X2, kind == 0x020b)),
            _ => None,
        },
        _ => None,
    }
}
fn decide(flags: u32, closing: bool, kind: u32, data: u32) -> Decision {
    let mut result = Decision {
        flags,
        ..Decision::default()
    };
    let accepting = flags & ARMED != 0 && !closing;
    if let Some((bit, down)) = button(kind, data) {
        if down {
            if flags & bit != 0 {
                result.consume = true;
            } else if accepting {
                result.flags |= bit;
                result.consume = true;
                result.message = match bit {
                    LEFT => LEFT_DOWN,
                    RIGHT => RIGHT_DOWN,
                    _ => 0,
                };
            }
        } else if flags & bit != 0 {
            result.flags &= !bit;
            result.consume = true;
            result.message = match bit {
                LEFT => LEFT_UP,
                RIGHT => RIGHT_UP,
                _ => 0,
            };
        }
    } else if accepting {
        if kind == 0x0200 {
            result.message = MOVE;
        } else if kind == 0x020a || kind == 0x020e {
            result.consume = true;
        }
    }
    result
}
pub fn pack_point(x: i32, y: i32) -> isize {
    ((u64::from(x as u32) << 32) | u64::from(y as u32)) as isize
}

fn capture_drag_extent(origin: isize, x: i32, y: i32) -> (u32, u32) {
    let origin = origin as u64;
    let extent = |value: i32, start: i32| {
        (i64::from(value) - i64::from(start))
            .unsigned_abs()
            .min(i32::MAX as u64) as u32
    };
    (extent(x, (origin >> 32) as i32), extent(y, origin as u32 as i32))
}

struct Shared {
    thread: AtomicU32,
    token: AtomicU64,
    child: AtomicU32,
    target: AtomicIsize,
    refreshed: AtomicU32,
    closing: AtomicBool,
    end_requested: AtomicBool,
    flags: AtomicU32,
    physical_left: AtomicBool,
    physical_right: AtomicBool,
    physical_aux: AtomicU32,
    move_pending: AtomicBool,
    drag_origin: AtomicIsize,
    drag_max_x: AtomicU32,
    drag_max_y: AtomicU32,
    failed: AtomicBool,
    writer: Mutex<()>,
    available: AtomicIsize,
}
impl Default for Shared {
    fn default() -> Self {
        Self {
            thread: AtomicU32::new(0),
            token: AtomicU64::new(0),
            child: AtomicU32::new(0),
            target: AtomicIsize::new(0),
            refreshed: AtomicU32::new(0),
            closing: AtomicBool::new(true),
            end_requested: AtomicBool::new(false),
            flags: AtomicU32::new(0),
            physical_left: AtomicBool::new(false),
            physical_right: AtomicBool::new(false),
            physical_aux: AtomicU32::new(0),
            move_pending: AtomicBool::new(false),
            drag_origin: AtomicIsize::new(0),
            drag_max_x: AtomicU32::new(0),
            drag_max_y: AtomicU32::new(0),
            failed: AtomicBool::new(false),
            writer: Mutex::new(()),
            available: AtomicIsize::new(0),
        }
    }
}
static SHARED: OnceLock<Shared> = OnceLock::new();
pub fn initialize() {
    let s = shared();
    #[cfg(windows)]
    if s.available.load(Ordering::SeqCst) == 0 {
        let event = unsafe { native::CreateEventW(std::ptr::null(), 1, 1, std::ptr::null()) };
        if !event.is_null()
            && s.available
                .compare_exchange(0, event as isize, Ordering::SeqCst, Ordering::SeqCst)
                .is_err()
        {
            unsafe {
                native::CloseHandle(event);
            }
        }
    }
    #[cfg(not(windows))]
    let _ = s;
}
// Waiting does not revoke a generation: its owned releases must still drain.
// Fail visibly instead of leaving all subsequent shortcuts silently queued.
fn await_availability(
    mut cancelled: impl FnMut() -> bool,
    mut idle: impl FnMut() -> bool,
    mut elapsed: impl FnMut() -> Duration,
    mut wait: impl FnMut() -> Result<(), String>,
) -> Result<(), String> {
    loop {
        if cancelled() {
            return Err("CANCELLED: Native task was superseded.".into());
        }
        if idle() {
            return Ok(());
        }
        if elapsed() >= Duration::from_secs(2) {
            return Err("CAPTURE_INPUT_HOST: Previous capture input is still ending. Release all mouse buttons and Escape, then retry; if it persists, restart EchoLingo.".into());
        }
        wait()?;
    }
}
#[cfg(windows)]
pub fn wait_available(cancelled: impl Fn() -> bool) -> Result<(), String> {
    let s = shared();
    let started = Instant::now();
    await_availability(
        cancelled,
        || s.token.load(Ordering::SeqCst) == 0,
        || started.elapsed(),
        || {
            let event = s.available.load(Ordering::SeqCst);
            if event == 0 || s.thread.load(Ordering::SeqCst) == 0 {
                return Err("CAPTURE_INPUT_HOST: The native input listener is unavailable.".into());
            }
            let result = unsafe { native::WaitForSingleObject(event as _, 30) };
            if result == 0 && s.token.load(Ordering::SeqCst) != 0 {
                std::thread::yield_now();
            }
            if result != 0 && result != 258 {
                return Err(
                    "CAPTURE_INPUT_HOST: Windows could not await the previous input release."
                        .into(),
                );
            }
            Ok(())
        },
    )
}
/// Bounded state only: never expose the random session token or target HWND.
pub fn diagnostic_state() -> [u64; 4] {
    let s = shared();
    [
        u64::from(s.token.load(Ordering::SeqCst) != 0),
        u64::from(s.flags.load(Ordering::SeqCst) & BUTTONS),
        u64::from(s.closing.load(Ordering::SeqCst)),
        u64::from(s.end_requested.load(Ordering::SeqCst)),
    ]
}
pub fn replacement_is_valid(old_unhooked: bool, error: Option<i32>) -> bool {
    old_unhooked || error == Some(1404)
}
fn endpoint_matches(previous: isize, target: isize, expected: u32, actual: u32) -> bool {
    target != 0 && expected != 0 && expected == actual && (previous == 0 || previous == target)
}
fn shared() -> &'static Shared {
    SHARED.get_or_init(Shared::default)
}

// Only the hook/control thread calls this after all owned pairs are drained.
fn finish_generation(s: &Shared) {
    if s.flags.load(Ordering::SeqCst) & BUTTONS != 0 {
        return;
    }
    s.target.store(0, Ordering::SeqCst);
    s.child.store(0, Ordering::SeqCst);
    s.flags.store(0, Ordering::SeqCst);
    #[cfg(windows)]
    if s.available.load(Ordering::SeqCst) != 0 {
        unsafe {
            native::SetEvent(s.available.load(Ordering::SeqCst) as _);
        }
    }
    // Publish idle last: a new session cannot reset the event before this
    // generation has finished signaling its release condition.
    s.token.store(0, Ordering::SeqCst);
}
#[cfg(windows)]
mod native {
    use std::ffi::c_void;
    #[link(name = "user32")]
    unsafe extern "system" {
        pub fn PostMessageW(
            window: *mut c_void,
            message: u32,
            word: usize,
            parameter: isize,
        ) -> i32;
        pub fn PostThreadMessageW(thread: u32, message: u32, word: usize, parameter: isize) -> i32;
        pub fn GetWindowThreadProcessId(window: *mut c_void, process: *mut u32) -> u32;
        pub fn GetAsyncKeyState(key: i32) -> i16;
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        pub fn CreateEventW(
            attributes: *const c_void,
            manual: i32,
            initial: i32,
            name: *const u16,
        ) -> *mut c_void;
        pub fn SetEvent(event: *mut c_void) -> i32;
        pub fn ResetEvent(event: *mut c_void) -> i32;
        pub fn CloseHandle(handle: *mut c_void) -> i32;
        pub fn WaitForSingleObject(event: *mut c_void, milliseconds: u32) -> u32;
    }
    #[link(name = "bcrypt")]
    unsafe extern "system" {
        pub fn BCryptGenRandom(
            algorithm: *mut c_void,
            buffer: *mut u8,
            length: u32,
            flags: u32,
        ) -> i32;
    }
}
#[cfg(windows)]
fn post(target: isize, message: u32, token: u64, parameter: isize) -> bool {
    target != 0
        && unsafe { native::PostMessageW(target as _, message, token as usize, parameter) } != 0
}
#[cfg(windows)]
pub fn publish_host_thread(thread: u32) {
    let s = shared();
    s.physical_left
        .store(unsafe { native::GetAsyncKeyState(1) } < 0, Ordering::SeqCst);
    s.physical_right
        .store(unsafe { native::GetAsyncKeyState(2) } < 0, Ordering::SeqCst);
    let mut aux = 0;
    for (key, flag) in [(4, MIDDLE), (5, X1), (6, X2)] {
        if unsafe { native::GetAsyncKeyState(key) } < 0 {
            aux |= flag;
        }
    }
    s.physical_aux.store(aux, Ordering::SeqCst);
    s.thread.store(thread, Ordering::SeqCst);
}
#[cfg(windows)]
pub fn clear_host_thread() {
    let s = shared();
    s.closing.store(true, Ordering::SeqCst);
    s.thread.store(0, Ordering::SeqCst);
}
pub fn refresh_token(message: u32, word: usize, parameter: isize) -> Option<u64> {
    let token = word as u64;
    (message == REFRESH
        && parameter == 0
        && token != 0
        && shared().token.load(Ordering::SeqCst) == token)
        .then_some(token)
}
pub fn refresh_result(token: u64, success: bool) {
    let s = shared();
    if s.token.load(Ordering::SeqCst) == token {
        s.refreshed
            .store(if success { 1 } else { 2 }, Ordering::SeqCst);
    }
}
#[cfg(windows)]
pub fn control(message: u32, word: usize, parameter: isize) -> bool {
    if !(READY..=END).contains(&message) {
        return false;
    }
    let s = shared();
    let token = parameter as u64;
    let target = word as isize;
    if token == 0 || token != s.token.load(Ordering::SeqCst) {
        return true;
    }
    if message == END {
        s.closing.store(true, Ordering::SeqCst);
        s.target.store(0, Ordering::SeqCst);
        s.end_requested.store(true, Ordering::SeqCst);
        if s.flags.load(Ordering::SeqCst) & BUTTONS == 0 {
            finish_generation(s);
        }
        return true;
    }
    if target == 0 {
        return true;
    }
    if message == READY {
        if s.closing.load(Ordering::SeqCst) {
            return true;
        }
        let mut pid = 0;
        if s.refreshed.load(Ordering::SeqCst) == 1
            && s.child.load(Ordering::SeqCst) != 0
            && unsafe { native::GetWindowThreadProcessId(target as _, &mut pid) } != 0
            && endpoint_matches(
                s.target.load(Ordering::SeqCst),
                target,
                s.child.load(Ordering::SeqCst),
                pid,
            )
        {
            s.target.store(target, Ordering::SeqCst);
            if !post(target, READY_ACK, token, 0) {
                s.failed.store(true, Ordering::SeqCst);
            }
        }
        return true;
    }
    if target != s.target.load(Ordering::SeqCst) {
        return true;
    }
    match message {
        ARM => {
            let left = s.physical_left.load(Ordering::SeqCst)
                || unsafe { native::GetAsyncKeyState(1) } < 0;
            let right = s.physical_right.load(Ordering::SeqCst)
                || unsafe { native::GetAsyncKeyState(2) } < 0;
            let mut physical = if left { LEFT } else { 0 }
                | if right { RIGHT } else { 0 }
                | s.physical_aux.load(Ordering::SeqCst);
            for (key, flag) in [(4, MIDDLE), (5, X1), (6, X2)] {
                if unsafe { native::GetAsyncKeyState(key) } < 0 {
                    physical |= flag;
                }
            }
            if let Some(flags) = arm(
                s.flags.load(Ordering::SeqCst),
                physical,
                s.closing.load(Ordering::SeqCst),
            ) {
                s.flags.store(flags, Ordering::SeqCst);
                if !post(target, ARM_ACK, token, 0) {
                    s.failed.store(true, Ordering::SeqCst);
                    s.closing.store(true, Ordering::SeqCst);
                }
            }
        }
        MOVE_ACK => {
            s.move_pending.store(false, Ordering::SeqCst);
        }
        STOP => {
            s.closing.store(true, Ordering::SeqCst);
            if s.flags.load(Ordering::SeqCst) & BUTTONS == 0 {
                let _ = post(
                    target,
                    STOP_ACK,
                    token,
                    isize::from(s.failed.load(Ordering::SeqCst)),
                );
                // ACK is queued while the mailbox is live; no later callback
                // may post into a destroyed/recycled mailbox after STOP.
                s.target.store(0, Ordering::SeqCst);
            }
        }
        PING => {
            if !post(
                target,
                PING_ACK,
                token,
                isize::from(s.failed.load(Ordering::SeqCst)),
            ) {
                s.failed.store(true, Ordering::SeqCst);
                s.closing.store(true, Ordering::SeqCst);
            }
        }
        _ => {}
    }
    true
}
/// Called only on the existing native hook thread. No locks, HWND queries,
/// allocation, synchronous IPC, painting or content access in this path.
#[cfg(windows)]
pub fn mouse(kind: u32, x: i32, y: i32, mouse_data: u32) -> bool {
    let s = shared();
    match kind {
        0x0201 => s.physical_left.store(true, Ordering::SeqCst),
        0x0202 => s.physical_left.store(false, Ordering::SeqCst),
        0x0204 => s.physical_right.store(true, Ordering::SeqCst),
        0x0205 => s.physical_right.store(false, Ordering::SeqCst),
        _ => {}
    }
    if let Some((bit, down)) = button(kind, mouse_data) {
        if bit & (MIDDLE | X1 | X2) != 0 {
            if down {
                s.physical_aux.fetch_or(bit, Ordering::SeqCst);
            } else {
                s.physical_aux.fetch_and(!bit, Ordering::SeqCst);
            }
        }
    }
    let token = s.token.load(Ordering::SeqCst);
    let target = s.target.load(Ordering::SeqCst);
    if token == 0
        || s.refreshed.load(Ordering::SeqCst) != 1
        || (target == 0 && !s.closing.load(Ordering::SeqCst))
    {
        return false;
    }
    let before = s.flags.load(Ordering::SeqCst);
    let d = decide(
        before,
        s.closing.load(Ordering::SeqCst),
        kind,
        mouse_data,
    );
    s.flags.store(d.flags, Ordering::SeqCst);
    // Keep a scalar maximum independently of throttled MOVE delivery. A fast
    // drag out and back between paints must not become a window click.
    if d.message == LEFT_DOWN {
        s.drag_origin.store(pack_point(x, y), Ordering::SeqCst);
        s.drag_max_x.store(0, Ordering::SeqCst);
        s.drag_max_y.store(0, Ordering::SeqCst);
    } else if before & LEFT != 0 {
        let (dx, dy) = capture_drag_extent(s.drag_origin.load(Ordering::SeqCst), x, y);
        s.drag_max_x.fetch_max(dx, Ordering::SeqCst);
        s.drag_max_y.fetch_max(dy, Ordering::SeqCst);
    }
    if d.message == LEFT_UP && target != 0 && s.target.load(Ordering::SeqCst) == target {
        let excursion = pack_point(s.drag_max_x.load(Ordering::SeqCst) as i32, s.drag_max_y.load(Ordering::SeqCst) as i32);
        if !post(target, DRAG_EXCURSION, token, excursion) {
            s.failed.store(true, Ordering::SeqCst);
            s.closing.store(true, Ordering::SeqCst);
            let _ = post(target, FAILURE, token, 0);
        }
    }
    if target != 0
        && s.target.load(Ordering::SeqCst) == target
        && d.message != 0
        && (d.message != MOVE || !s.move_pending.swap(true, Ordering::SeqCst))
        && !post(target, d.message, token, pack_point(x, y))
    {
        s.failed.store(true, Ordering::SeqCst);
        s.closing.store(true, Ordering::SeqCst);
        let _ = post(target, FAILURE, token, 0);
    }
    if s.closing.load(Ordering::SeqCst) && d.flags & BUTTONS == 0 {
        if target != 0 && s.target.load(Ordering::SeqCst) == target {
            let _ = post(
                target,
                STOP_ACK,
                token,
                isize::from(s.failed.load(Ordering::SeqCst)),
            );
            s.target.store(0, Ordering::SeqCst);
        }
        if s.end_requested.load(Ordering::SeqCst) {
            finish_generation(s);
        }
    }
    d.consume
}

pub struct Session {
    token: u64,
    thread: u32,
    closed: bool,
}
impl Session {
    #[cfg(windows)]
    pub fn begin() -> Result<Self, String> {
        if usize::BITS != 64 {
            return Err(
                "CAPTURE_INPUT_HOST: Native input delegation requires the x64 package.".into(),
            );
        }
        let s = shared();
        let _writer = s
            .writer
            .lock()
            .map_err(|_| "CAPTURE_INPUT_HOST: Session state is unavailable.")?;
        if s.token.load(Ordering::SeqCst) != 0 {
            return Err("CAPTURE_INPUT_HOST: Another input session is still ending.".into());
        }
        let thread = s.thread.load(Ordering::SeqCst);
        if thread == 0 {
            return Err("CAPTURE_INPUT_HOST: The native input listener is unavailable.".into());
        }
        let mut token = 0u64;
        if unsafe {
            native::BCryptGenRandom(std::ptr::null_mut(), (&mut token as *mut u64).cast(), 8, 2)
        } < 0
        {
            return Err(
                "CAPTURE_INPUT_HOST: Windows could not initialize an input session.".into(),
            );
        }
        token &= i64::MAX as u64;
        if token == 0 {
            return Err("CAPTURE_INPUT_HOST: Windows returned an invalid input session.".into());
        }
        let event = s.available.load(Ordering::SeqCst);
        if event == 0 || unsafe { native::ResetEvent(event as _) } == 0 {
            return Err("CAPTURE_INPUT_HOST: Windows could not prepare input availability.".into());
        }
        s.child.store(0, Ordering::SeqCst);
        s.target.store(0, Ordering::SeqCst);
        s.flags.store(0, Ordering::SeqCst);
        s.refreshed.store(0, Ordering::SeqCst);
        s.failed.store(false, Ordering::SeqCst);
        s.move_pending.store(false, Ordering::SeqCst);
        s.closing.store(false, Ordering::SeqCst);
        s.end_requested.store(false, Ordering::SeqCst);
        s.token.store(token, Ordering::SeqCst);
        let mut session = Self {
            token,
            thread,
            closed: false,
        };
        if unsafe { native::PostThreadMessageW(thread, REFRESH, token as usize, 0) } == 0 {
            session.close();
            return Err(
                "CAPTURE_INPUT_HOST: Windows could not prepare the native listener.".into(),
            );
        }
        let deadline = Instant::now() + Duration::from_secs(3);
        while s.refreshed.load(Ordering::SeqCst) == 0 && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(5));
        }
        if s.refreshed.load(Ordering::SeqCst) != 1 {
            session.close();
            return Err("CAPTURE_INPUT_HOST: Windows could not refresh region input ownership; no screenshot was taken.".into());
        }
        Ok(session)
    }
    pub fn thread(&self) -> u32 {
        self.thread
    }
    pub fn token(&self) -> u64 {
        self.token
    }
    pub fn bind_child(&self, pid: u32) {
        let s = shared();
        if s.token.load(Ordering::SeqCst) == self.token {
            s.child.store(pid, Ordering::SeqCst);
        }
    }
    pub fn close(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        let s = shared();
        if s.token.load(Ordering::SeqCst) != self.token {
            return;
        }
        s.closing.store(true, Ordering::SeqCst);
        // Stop delivery immediately, then serialize END with the native hook
        // before a caller kills the helper. Keep already-owned releases even
        // if they arrive after this bounded wait; no new downs are consumed.
        s.target.store(0, Ordering::SeqCst);
        #[cfg(windows)]
        if unsafe { native::PostThreadMessageW(self.thread, END, 0, self.token as isize) } != 0 {
            let until = Instant::now() + Duration::from_millis(500);
            while s.token.load(Ordering::SeqCst) == self.token
                && !s.end_requested.load(Ordering::SeqCst)
                && Instant::now() < until
            {
                std::thread::sleep(Duration::from_millis(5));
            }
        }
        // If the pump is unresponsive, keep this closing generation reserved.
        // A later session must fail visibly rather than overlap its ownership.
    }
}
impl Drop for Session {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn waiting_is_bounded_without_revoking_owned_input() {
        use std::cell::Cell;
        let time = Cell::new(0);
        let s = Shared::default();
        s.token.store(41, Ordering::SeqCst);
        s.flags.store(LEFT, Ordering::SeqCst);
        let result = await_availability(
            || false,
            || s.token.load(Ordering::SeqCst) == 0,
            || Duration::from_millis(time.get()),
            || {
                time.set(time.get() + 30);
                Ok(())
            },
        );
        assert!(result.unwrap_err().starts_with("CAPTURE_INPUT_HOST:"));
        assert_eq!(s.token.load(Ordering::SeqCst), 41);
        assert_eq!(s.flags.load(Ordering::SeqCst), LEFT);
        assert!(time.get() >= 2000 && time.get() < 2030);
        s.flags.store(0, Ordering::SeqCst);
        finish_generation(&s);
        assert!(await_availability(
            || false,
            || s.token.load(Ordering::SeqCst) == 0,
            || Duration::ZERO,
            || panic!("idle must not wait")
        )
        .is_ok());
    }
    #[test]
    fn waiting_cancels_before_idle_and_propagates_listener_failure() {
        assert!(await_availability(
            || true,
            || true,
            || Duration::ZERO,
            || panic!("cancelled must not wait")
        )
        .unwrap_err()
        .starts_with("CANCELLED:"));
        assert_eq!(
            await_availability(
                || false,
                || false,
                || Duration::ZERO,
                || Err("listener failed".into())
            )
            .unwrap_err(),
            "listener failed"
        );
    }
    #[test]
    fn closing_generation_keeps_long_held_owned_release_after_mailbox_detach() {
        let s = Shared::default();
        s.token.store(41, Ordering::SeqCst);
        s.flags.store(ARMED | LEFT | X2, Ordering::SeqCst);
        s.target.store(0, Ordering::SeqCst);
        s.end_requested.store(true, Ordering::SeqCst);
        finish_generation(&s);
        assert_eq!(s.token.load(Ordering::SeqCst), 41);
        let l = decide(s.flags.load(Ordering::SeqCst), true, 0x202, 0);
        assert!(l.consume);
        s.flags.store(l.flags, Ordering::SeqCst);
        finish_generation(&s);
        assert_eq!(s.token.load(Ordering::SeqCst), 41);
        let x = decide(l.flags, true, 0x20c, 2 << 16);
        assert!(x.consume);
        s.flags.store(x.flags, Ordering::SeqCst);
        finish_generation(&s);
        assert_eq!(s.token.load(Ordering::SeqCst), 0);
        assert!(!decide(0, true, 0x202, 0).consume);
    }
    #[test]
    fn fresh_hook_accepts_a_known_removed_old_hook_but_not_unknown_failures() {
        assert!(replacement_is_valid(true, None));
        assert!(replacement_is_valid(false, Some(1404)));
        assert!(!replacement_is_valid(false, Some(5)));
        assert!(!replacement_is_valid(false, None));
    }
    #[test]
    fn mailbox_can_bind_once_and_repeat_but_never_retarget_or_cross_pid() {
        assert!(endpoint_matches(0, 71, 40, 40));
        assert!(endpoint_matches(71, 71, 40, 40));
        assert!(!endpoint_matches(71, 72, 40, 40));
        assert!(!endpoint_matches(0, 71, 40, 41));
        assert!(!endpoint_matches(0, 0, 40, 40));
        assert!(!endpoint_matches(0, 71, 0, 0));
    }
    #[test]
    fn preheld_source_pairs_pass_until_released_then_arm() {
        for flag in [LEFT, RIGHT, MIDDLE, X1, X2] {
            assert_eq!(arm(0, flag, false), None);
        }
        for (down, up, data, _) in [
            (0x201, 0x202, 0, LEFT),
            (0x204, 0x205, 0, RIGHT),
            (0x207, 0x208, 0, MIDDLE),
            (0x20b, 0x20c, 1 << 16, X1),
            (0x20b, 0x20c, 2 << 16, X2),
        ] {
            assert!(!decide(0, false, down, data).consume);
            assert!(!decide(0, false, up, data).consume);
        }
        assert_eq!(arm(0, 0, false), Some(ARMED));
        assert_eq!(arm(0, 0, true), None);
    }
    #[test]
    fn every_owned_button_drains_its_matching_up_after_stop() {
        for (down, up, data, flag) in [
            (0x201, 0x202, 0, LEFT),
            (0x204, 0x205, 0, RIGHT),
            (0x207, 0x208, 0, MIDDLE),
            (0x20b, 0x20c, 1 << 16, X1),
            (0x20b, 0x20c, 2 << 16, X2),
        ] {
            let d = decide(ARMED, false, down, data);
            assert!(d.consume);
            assert_ne!(d.flags & flag, 0);
            assert_eq!(decide(d.flags, false, down, data).message, 0);
            let u = decide(d.flags, true, up, data);
            assert!(u.consume);
            assert_eq!(u.flags, ARMED);
            assert!(!decide(u.flags, true, down, data).consume);
            assert!(!decide(u.flags, true, up, data).consume);
            assert_eq!(arm(d.flags, 0, false), None);
        }
    }
    #[test]
    fn wheel_is_owned_only_when_armed_and_unknown_x_data_does_not_fake_a_pair() {
        for kind in [0x20a, 0x20e] {
            assert!(decide(ARMED, false, kind, 0).consume);
            assert!(!decide(0, false, kind, 0).consume);
        }
        assert!(!decide(ARMED, false, 0x20b, 3 << 16).consume);
        assert_eq!(decide(ARMED, false, 0x200, 0).message, MOVE);
        assert!(!decide(ARMED, false, 0x200, 0).consume);
        assert_eq!(decide(ARMED, true, 0x200, 0).message, 0);
    }
    #[test]
    fn physical_point_scalar_roundtrip_preserves_all_signed_32bit_coordinates() {
        for (x, y) in [
            (0, 0),
            (-1, -1),
            (-3840, 2160),
            (i32::MIN, i32::MAX),
            (i32::MAX, i32::MIN),
        ] {
            let p = pack_point(x, y) as u64;
            assert_eq!(((p >> 32) as u32) as i32, x);
            assert_eq!((p as u32) as i32, y);
        }
    }
    #[test]
    fn foreign_or_stale_control_never_refreshes_a_session() {
        assert_eq!(refresh_token(REFRESH, 0, 0), None);
        assert_eq!(refresh_token(REFRESH, 41, 0), None);
        assert_eq!(refresh_token(READY, 41, 0), None);
        assert_eq!(refresh_token(REFRESH, 41, 1), None);
    }
}

/// Metadata only; hooks never initialize capture state while checking it.
pub fn current_token() -> u64 {
    SHARED
        .get()
        .map_or(0, |state| state.token.load(Ordering::SeqCst))
}

#[cfg(test)]
mod screenshot_extent_tests {
    use super::{capture_drag_extent, pack_point};
    #[test]
    fn signed_display_coordinates_and_extremes_do_not_wrap() {
        assert_eq!(capture_drag_extent(pack_point(-2000, -400), -1998, -401), (2, 1));
        assert_eq!(capture_drag_extent(pack_point(-2000, -400), 300, 600), (2300, 1000));
        assert_eq!(capture_drag_extent(pack_point(i32::MIN, i32::MAX), i32::MAX, i32::MIN), (i32::MAX as u32, i32::MAX as u32));
    }
}
