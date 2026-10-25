//! Temporary exclusion of our own top-level window from Windows capture APIs.
//!
//! Keep this guard inside the blocking capture operation: dropping an async
//! caller must not restore the affinity while its capture worker is still busy.
//! Tauri's `set_content_protected` only reports dispatch success, so this module
//! checks the Win32 return values and reads the affinity back before capture.
//!
//! https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity
//! https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-getwindowdisplayaffinity
//! https://learn.microsoft.com/windows/win32/devnotes/rtlgetversion

const EXCLUDE_FROM_CAPTURE: u32 = 0x11;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ExclusionError {
    Unavailable,
    RollbackFailed,
    RestoreFailed,
}

#[cfg(target_os = "windows")]
impl ExclusionError {
    fn message(self) -> String {
        match self {
            Self::Unavailable => {
                "当前 Windows 无法排除已固定的翻译窗口，本次截图已取消。请取消固定后重试。"
            }
            Self::RollbackFailed => {
                "本次截图已取消，但未能恢复窗口的屏幕捕获设置。请重启 EchoLingo 后重试。"
            }
            Self::RestoreFailed => "截图已结束，但未能恢复窗口的屏幕捕获设置。请重启 EchoLingo。",
        }
        .into()
    }
}

fn supports_capture_exclusion(version: Option<(u32, u32)>) -> bool {
    version.is_some_and(|(major, build)| major > 10 || (major == 10 && build >= 19_041))
}

/// Small synchronous interface so failure/rollback behavior can be tested
/// without creating a real window or querying the operating system.
trait DisplayAffinity {
    fn version(&self) -> Option<(u32, u32)>;
    fn owns_top_level_window(&self, hwnd: isize) -> bool;
    fn get(&self, hwnd: isize) -> Result<u32, ()>;
    fn set(&self, hwnd: isize, affinity: u32) -> Result<(), ()>;
}

struct AffinityGuard<B: DisplayAffinity> {
    backend: B,
    hwnd: isize,
    original: u32,
    armed: bool,
}

impl<B: DisplayAffinity> AffinityGuard<B> {
    fn acquire(backend: B, hwnd: isize) -> Result<Self, ExclusionError> {
        if hwnd == 0
            || !supports_capture_exclusion(backend.version())
            || !backend.owns_top_level_window(hwnd)
        {
            return Err(ExclusionError::Unavailable);
        }
        // Do not mutate a window unless its exact previous state is known.
        let original = backend.get(hwnd).map_err(|_| ExclusionError::Unavailable)?;
        let mut guard = Self {
            backend,
            hwnd,
            original,
            armed: true,
        };
        let applied = guard.backend.set(hwnd, EXCLUDE_FROM_CAPTURE).is_ok()
            && guard.backend.get(hwnd) == Ok(EXCLUDE_FROM_CAPTURE);
        if !applied {
            // Even a rejected Set is treated as potentially having changed the
            // window. Restore and verify before reporting that capture stopped.
            return match guard.restore_inner() {
                Ok(()) => Err(ExclusionError::Unavailable),
                Err(_) => Err(ExclusionError::RollbackFailed),
            };
        }
        Ok(guard)
    }

    fn restore_inner(&mut self) -> Result<(), ExclusionError> {
        if !self.armed {
            return Ok(());
        }
        if !self.backend.owns_top_level_window(self.hwnd) {
            // A closed HWND can be recycled into another process. Do not
            // change a window that no longer belongs to this process.
            self.armed = false;
            return Err(ExclusionError::RestoreFailed);
        }
        if self.backend.set(self.hwnd, self.original).is_err()
            || self.backend.get(self.hwnd) != Ok(self.original)
        {
            // Leave armed for one final Drop cleanup attempt. No retry loop.
            return Err(ExclusionError::RestoreFailed);
        }
        self.armed = false;
        Ok(())
    }

    fn restore(mut self) -> Result<(), ExclusionError> {
        self.restore_inner()
    }
}

impl<B: DisplayAffinity> Drop for AffinityGuard<B> {
    fn drop(&mut self) {
        let _ = self.restore_inner();
    }
}

#[cfg(target_os = "windows")]
pub struct CaptureWindowExclusion {
    guard: AffinityGuard<win32::WindowsDisplayAffinity>,
}

#[cfg(target_os = "windows")]
impl CaptureWindowExclusion {
    /// Only the current process's top-level HWND is accepted. Windows permits
    /// these synchronous User32 calls from our capture worker; no UI-thread
    /// dispatcher acknowledgment is mistaken for an operating-system result.
    pub fn acquire(window: &tauri::WebviewWindow) -> Result<Self, String> {
        let hwnd = window
            .hwnd()
            .map_err(|_| ExclusionError::Unavailable.message())?
            .0 as isize;
        AffinityGuard::acquire(win32::WindowsDisplayAffinity, hwnd)
            .map(|guard| Self { guard })
            .map_err(ExclusionError::message)
    }

    /// Call as soon as the blocking capture returns, including cancellation or
    /// errors, before waiting for credentials or any remote OCR request.
    pub fn restore(self) -> Result<(), String> {
        self.guard.restore().map_err(ExclusionError::message)
    }
}

#[cfg(target_os = "windows")]
mod win32 {
    use super::DisplayAffinity;
    use std::{ffi::c_void, mem::size_of};

    type Hwnd = *mut c_void;

    // RTL_OSVERSIONINFOW/OSVERSIONINFOW contains only DWORDs and WCHARs.
    #[repr(C)]
    struct OsVersionInfo {
        size: u32,
        major: u32,
        minor: u32,
        build: u32,
        platform: u32,
        service_pack: [u16; 128],
    }

    #[link(name = "user32")]
    unsafe extern "system" {
        fn SetWindowDisplayAffinity(hwnd: Hwnd, affinity: u32) -> i32;
        fn GetWindowDisplayAffinity(hwnd: Hwnd, affinity: *mut u32) -> i32;
        fn GetWindowThreadProcessId(hwnd: Hwnd, process_id: *mut u32) -> u32;
        fn GetAncestor(hwnd: Hwnd, flags: u32) -> Hwnd;
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcessId() -> u32;
    }
    #[link(name = "ntdll")]
    unsafe extern "system" {
        fn RtlGetVersion(version: *mut OsVersionInfo) -> i32;
    }

    pub(super) struct WindowsDisplayAffinity;

    impl DisplayAffinity for WindowsDisplayAffinity {
        fn version(&self) -> Option<(u32, u32)> {
            let mut version = OsVersionInfo {
                size: size_of::<OsVersionInfo>() as u32,
                major: 0,
                minor: 0,
                build: 0,
                platform: 0,
                service_pack: [0; 128],
            };
            // SAFETY: The initialized output buffer matches the Windows ABI;
            // RtlGetVersion avoids manifest-dependent version virtualization.
            (unsafe { RtlGetVersion(&mut version) } >= 0).then_some((version.major, version.build))
        }

        fn owns_top_level_window(&self, hwnd: isize) -> bool {
            let hwnd = hwnd as Hwnd;
            let mut owner = 0;
            // SAFETY: User32 validates HWND values, and owner is writable. The
            // GA_ROOT result must be the same window, not an ancestor HWND.
            unsafe {
                !hwnd.is_null()
                    && GetAncestor(hwnd, 2) == hwnd
                    && GetWindowThreadProcessId(hwnd, &mut owner) != 0
                    && owner == GetCurrentProcessId()
            }
        }

        fn get(&self, hwnd: isize) -> Result<u32, ()> {
            let mut affinity = 0;
            // SAFETY: The affinity output is valid and HWND is checked above.
            if unsafe { GetWindowDisplayAffinity(hwnd as Hwnd, &mut affinity) } == 0 {
                Err(())
            } else {
                Ok(affinity)
            }
        }

        fn set(&self, hwnd: isize, affinity: u32) -> Result<(), ()> {
            // SAFETY: Only our validated top-level HWND is changed, with a
            // documented value or the exact value previously read from Windows.
            if unsafe { SetWindowDisplayAffinity(hwnd as Hwnd, affinity) } == 0 {
                Err(())
            } else {
                Ok(())
            }
        }
    }

    #[cfg(test)]
    #[test]
    fn version_buffer_matches_windows_abi() {
        assert_eq!(size_of::<OsVersionInfo>(), 284);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{cell::RefCell, collections::VecDeque, rc::Rc};

    #[derive(Default)]
    struct State {
        reads: VecDeque<Result<u32, ()>>,
        writes: VecDeque<Result<(), ()>>,
        calls: Vec<u32>,
        owned: bool,
    }

    #[derive(Clone)]
    struct Mock {
        version: Option<(u32, u32)>,
        state: Rc<RefCell<State>>,
    }

    impl Mock {
        fn new(reads: impl IntoIterator<Item = Result<u32, ()>>) -> Self {
            Self {
                version: Some((10, 19_041)),
                state: Rc::new(RefCell::new(State {
                    reads: reads.into_iter().collect(),
                    owned: true,
                    ..State::default()
                })),
            }
        }
    }

    impl DisplayAffinity for Mock {
        fn version(&self) -> Option<(u32, u32)> {
            self.version
        }
        fn owns_top_level_window(&self, _hwnd: isize) -> bool {
            self.state.borrow().owned
        }
        fn get(&self, _hwnd: isize) -> Result<u32, ()> {
            self.state.borrow_mut().reads.pop_front().unwrap_or(Err(()))
        }
        fn set(&self, _hwnd: isize, affinity: u32) -> Result<(), ()> {
            let mut state = self.state.borrow_mut();
            state.calls.push(affinity);
            state.writes.pop_front().unwrap_or(Ok(()))
        }
    }

    #[test]
    fn old_unknown_windows_never_attempt_exclusion() {
        for version in [None, Some((6, 7601)), Some((10, 18_363))] {
            let mut mock = Mock::new([Ok(0)]);
            mock.version = version;
            assert!(matches!(
                AffinityGuard::acquire(mock.clone(), 1),
                Err(ExclusionError::Unavailable)
            ));
            assert!(mock.state.borrow().calls.is_empty());
            assert_eq!(mock.state.borrow().reads.len(), 1);
        }
        assert!(supports_capture_exclusion(Some((10, 19_041))));
        assert!(supports_capture_exclusion(Some((10, 22_000))));
        assert!(supports_capture_exclusion(Some((11, 0))));
    }

    #[test]
    fn unknown_original_or_foreign_window_is_not_mutated() {
        let mock = Mock::new([Err(())]);
        assert!(AffinityGuard::acquire(mock.clone(), 1).is_err());
        assert!(mock.state.borrow().calls.is_empty());
        let foreign = Mock::new([Ok(0)]);
        foreign.state.borrow_mut().owned = false;
        assert!(AffinityGuard::acquire(foreign.clone(), 1).is_err());
        assert!(foreign.state.borrow().calls.is_empty());
        assert_eq!(foreign.state.borrow().reads.len(), 1);
    }

    #[test]
    fn successful_guard_restores_exact_previous_affinity_once() {
        // Existing monitor-only protection must not be reset to WDA_NONE.
        let mock = Mock::new([Ok(1), Ok(EXCLUDE_FROM_CAPTURE), Ok(1)]);
        let guard = AffinityGuard::acquire(mock.clone(), 1).unwrap();
        assert_eq!(mock.state.borrow().calls, [EXCLUDE_FROM_CAPTURE]);
        assert_eq!(guard.restore(), Ok(()));
        assert_eq!(mock.state.borrow().calls, [EXCLUDE_FROM_CAPTURE, 1]);
    }

    #[test]
    fn false_set_or_wrong_readback_rolls_back_before_error() {
        let rejected = Mock::new([Ok(0), Ok(0)]);
        rejected.state.borrow_mut().writes.push_back(Err(()));
        assert!(matches!(
            AffinityGuard::acquire(rejected.clone(), 1),
            Err(ExclusionError::Unavailable)
        ));
        assert_eq!(rejected.state.borrow().calls, [EXCLUDE_FROM_CAPTURE, 0]);

        for readback in [Ok(1), Err(())] {
            let wrong = Mock::new([Ok(0), readback, Ok(0)]);
            assert!(matches!(
                AffinityGuard::acquire(wrong.clone(), 1),
                Err(ExclusionError::Unavailable)
            ));
            assert_eq!(wrong.state.borrow().calls, [EXCLUDE_FROM_CAPTURE, 0]);
        }
    }

    #[test]
    fn rollback_failure_is_reported_and_drop_makes_one_final_attempt() {
        let mock = Mock::new([Ok(0), Ok(1), Err(()), Ok(0)]);
        assert!(matches!(
            AffinityGuard::acquire(mock.clone(), 1),
            Err(ExclusionError::RollbackFailed)
        ));
        assert_eq!(mock.state.borrow().calls, [EXCLUDE_FROM_CAPTURE, 0, 0]);
    }

    #[test]
    fn dropped_capture_restores_and_explicit_failure_stays_visible() {
        let dropped = Mock::new([Ok(0), Ok(EXCLUDE_FROM_CAPTURE), Ok(0)]);
        drop(AffinityGuard::acquire(dropped.clone(), 1).unwrap());
        assert_eq!(dropped.state.borrow().calls, [EXCLUDE_FROM_CAPTURE, 0]);

        let failed = Mock::new([Ok(0), Ok(EXCLUDE_FROM_CAPTURE), Ok(1), Ok(0)]);
        let guard = AffinityGuard::acquire(failed.clone(), 1).unwrap();
        assert_eq!(guard.restore(), Err(ExclusionError::RestoreFailed));
        assert_eq!(failed.state.borrow().calls, [EXCLUDE_FROM_CAPTURE, 0, 0]);
    }

    #[test]
    fn cleanup_never_mutates_a_replaced_or_foreign_window() {
        let mock = Mock::new([Ok(0), Ok(EXCLUDE_FROM_CAPTURE)]);
        let guard = AffinityGuard::acquire(mock.clone(), 1).unwrap();
        mock.state.borrow_mut().owned = false;
        assert_eq!(guard.restore(), Err(ExclusionError::RestoreFailed));
        assert_eq!(mock.state.borrow().calls, [EXCLUDE_FROM_CAPTURE]);
    }
}
