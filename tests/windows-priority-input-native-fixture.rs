//! Test-only C ABI for the exact production native input pump and pair policy.
//! The capture token is fixture-owned; no application/capture code is executed.
#![allow(dead_code)]
#[path = "../src-tauri/src/mouse_shortcuts.rs"]
mod mouse_shortcuts;
#[path = "../src-tauri/src/windows_mouse_shortcuts.rs"]
mod windows_mouse_shortcuts;

mod windows_capture_input {
    pub static TOKEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    pub fn current_token() -> u64 {
        TOKEN.load(std::sync::atomic::Ordering::SeqCst)
    }
}

use std::sync::{mpsc::Receiver, Mutex};
use windows_mouse_shortcuts::Event;
static EVENTS: Mutex<Option<Receiver<Event>>> = Mutex::new(None);
static LAST: Mutex<Option<Event>> = Mutex::new(None);

#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityStart() -> i32 {
    match windows_mouse_shortcuts::start([1, 2]) {
        Ok(receiver) => match EVENTS.lock() {
            Ok(mut events) => {
                *events = Some(receiver);
                1
            }
            Err(_) => 0,
        },
        Err(_) => 0,
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityConfigure(mask: u32) -> i32 {
    if mask & !15 != 0 {
        return 0;
    }
    i32::from(
        windows_mouse_shortcuts::unregister((!mask & 15) as u8).is_ok()
            && windows_mouse_shortcuts::register(mask as u8).is_ok(),
    )
}

#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityContext(window: isize, management: i32) {
    windows_mouse_shortcuts::set_context(window, management != 0);
}

#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityRecording(lease: u64) -> i32 {
    i32::from(windows_mouse_shortcuts::recording(lease).is_ok())
}

#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityCapture(token: u64) {
    windows_capture_input::TOKEN.store(token, std::sync::atomic::Ordering::SeqCst);
}

/// Caller owns exactly eight writable u64 slots. The final two are metadata
/// handles, never text or clipboard content. Current production queues only an
/// accepted Alt-anchored pair; the fixed historical build intentionally exposes
/// a later hook's generated-decoy retarget as a required red control.
/// 0 means no event; -1 is ABI error.
#[unsafe(no_mangle)]
pub unsafe extern "system" fn EchoLingoPriorityPoll(values: *mut u64, count: u32) -> i32 {
    if values.is_null() || count != 8 {
        return -1;
    }
    let Ok(events) = EVENTS.lock() else {
        return -1;
    };
    let Some(receiver) = events.as_ref() else {
        return -1;
    };
    let Ok(event) = receiver.try_recv() else {
        return 0;
    };
    if event.id == 0 {
        return 0;
    }
    let fields = [
        u64::from(event.id),
        u64::from(windows_mouse_shortcuts::current(event)),
        event.context.generation,
        event.context.capture,
        event.context.recording,
        u64::from(event.context.blocked),
        event.context.foreground as u64,
        event.context.focus as u64,
    ];
    unsafe { std::ptr::copy_nonoverlapping(fields.as_ptr(), values, fields.len()) };
    if let Ok(mut last) = LAST.lock() {
        *last = Some(event);
    }
    1
}

/// The legacy build compiles the exact fixed historical module, which has no
/// recovery entry point. It only runs the old-order negative control matrix.
#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityRecover() -> i32 {
    #[cfg(not(legacy_priority_fixture))]
    {
        i32::from(windows_mouse_shortcuts::request_keyboard_recovery().is_ok())
    }
    #[cfg(legacy_priority_fixture)]
    {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityDiagnostic(index: u32) -> u64 {
    #[cfg(not(legacy_priority_fixture))]
    {
        let names = [
            "recoverySuccesses",
            "recoveryRequests",
            "recoveryAttempts",
            "recoveryPending",
            "recoveryDeferred",
            "recoveryFailures",
            "priorityKeyDownObserved",
            "priorityKeyUpObserved",
            "priorityPairsAccepted",
            "priorityPairsDiscarded",
            "recoveryOwnedPairsBlocked",
            "eventsEnqueued",
            "eventsStaleContext",
        ];
        let Some(name) = names.get(index as usize) else {
            return u64::MAX;
        };
        windows_mouse_shortcuts::diagnostics()
            .into_iter()
            .find_map(|(key, value)| (key == *name).then_some(value))
            .unwrap_or(u64::MAX)
    }
    #[cfg(legacy_priority_fixture)]
    {
        let _ = index;
        u64::MAX
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityLastCurrent() -> i32 {
    LAST.lock().ok().and_then(|last| *last).map_or(-1, |event| {
        i32::from(windows_mouse_shortcuts::current(event))
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn EchoLingoPriorityStop() {
    windows_mouse_shortcuts::stop();
}
