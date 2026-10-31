//! Latest user intent wins; physical native side effects finish under one permit.
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex, MutexGuard,
};

const CANCELLED: &str = "CANCELLED: Native task was superseded";

#[derive(Clone)]
pub struct Request {
    id: u64,
    cancelled: Arc<AtomicBool>,
}
impl Request {
    pub fn id(&self) -> u64 {
        self.id
    }
    pub fn cancellation(&self) -> Arc<AtomicBool> {
        self.cancelled.clone()
    }
    pub fn cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }
}

#[derive(Default)]
struct State {
    next_id: u64,
    current: Option<Request>,
}
#[derive(Default)]
pub struct Controller {
    state: Mutex<State>,
    worker: Mutex<()>,
}
pub struct Permit<'a> {
    _guard: MutexGuard<'a, ()>,
}
impl Controller {
    pub fn begin(&self) -> Result<Request, String> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| "NATIVE_TASK: Intent state is unavailable")?;
        if let Some(old) = state.current.take() {
            old.cancelled.store(true, Ordering::SeqCst);
        }
        let id = state
            .next_id
            .checked_add(1)
            .ok_or("NATIVE_TASK: Request identifiers exhausted; restart the app")?;
        state.next_id = id;
        let request = Request {
            id,
            cancelled: Arc::new(AtomicBool::new(false)),
        };
        state.current = Some(request.clone());
        Ok(request)
    }
    pub fn cancel(&self) {
        if let Ok(mut state) = self.state.lock() {
            if let Some(old) = state.current.take() {
                old.cancelled.store(true, Ordering::SeqCst);
            }
        }
    }
    pub fn is_current(&self, request: &Request) -> bool {
        !request.cancelled()
            && self.state.lock().is_ok_and(|state| {
                state.current.as_ref().is_some_and(|current| {
                    current.id == request.id && Arc::ptr_eq(&current.cancelled, &request.cancelled)
                })
            })
    }
    /// Serialize a short publication against new intent. Never await, perform
    /// native I/O, or re-enter this controller from the closure.
    pub fn publish<R>(&self, request: &Request, publication: impl FnOnce() -> R) -> Option<R> {
        let state = self.state.lock().ok()?;
        let current = state.current.as_ref()?;
        if request.cancelled()
            || current.id != request.id
            || !Arc::ptr_eq(&current.cancelled, &request.cancelled)
        {
            return None;
        }
        Some(publication())
    }
    /// Serialize an explicitly committed clipboard effect with native helpers.
    /// Call only on a blocking worker, then revalidate the image/session before
    /// the effect. It never changes intent and never blocks the UI/controller.
    pub fn enter_effect(&self) -> Result<Permit<'_>, String> {
        let guard = self
            .worker
            .lock()
            .map_err(|_| "NATIVE_TASK: Native worker is unavailable")?;
        Ok(Permit { _guard: guard })
    }
    /// Call on a blocking worker. A stale waiter must not start a helper,
    /// read another application's selection or acquire an exclusion guard.
    pub fn enter(&self, request: &Request) -> Result<Permit<'_>, String> {
        if !self.is_current(request) {
            return Err(CANCELLED.into());
        }
        let guard = self
            .worker
            .lock()
            .map_err(|_| "NATIVE_TASK: Native worker is unavailable")?;
        if !self.is_current(request) {
            return Err(CANCELLED.into());
        }
        Ok(Permit { _guard: guard })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{mpsc, Barrier};
    use std::time::Duration;

    #[test]
    fn each_shortcut_cancels_previous_intent_immediately_without_waiting_for_worker() {
        let controller = Controller::default();
        let old = controller.begin().unwrap();
        let token = old.cancellation();
        let _permit = controller.enter(&old).unwrap();
        let new = controller.begin().unwrap();
        assert!(token.load(Ordering::SeqCst));
        assert!(!controller.is_current(&old));
        assert!(controller.is_current(&new));
        assert_eq!(new.id(), old.id() + 1);
        assert!(!new.cancelled());
    }

    #[test]
    fn only_latest_waiter_can_start_after_real_previous_cleanup() {
        let controller = Arc::new(Controller::default());
        let old = controller.begin().unwrap();
        let old_permit = controller.enter(&old).unwrap();
        let middle = controller.begin().unwrap();
        let ready = Arc::new(Barrier::new(2));
        let (sent, received) = mpsc::channel();
        let worker = {
            let controller = controller.clone();
            let ready = ready.clone();
            std::thread::spawn(move || {
                ready.wait();
                sent.send(controller.enter(&middle).is_ok()).unwrap();
            })
        };
        ready.wait();
        assert!(received.recv_timeout(Duration::from_millis(20)).is_err());
        let latest = controller.begin().unwrap();
        drop(old_permit); // Real cleanup, not a timer, releases the worker.
        assert!(!received.recv_timeout(Duration::from_secs(1)).unwrap());
        worker.join().unwrap();
        assert!(controller.enter(&latest).is_ok());
    }

    #[test]
    fn cancelling_a_hidden_or_management_task_invalidates_its_clones_and_waiters() {
        let controller = Controller::default();
        let request = controller.begin().unwrap();
        let clone = request.clone();
        controller.cancel();
        controller.cancel();
        assert!(request.cancelled() && clone.cancelled());
        assert!(!controller.is_current(&clone));
        assert!(controller.enter(&clone).is_err());
        let next = controller.begin().unwrap();
        assert!(controller.is_current(&next));
    }

    #[test]
    fn explicit_clipboard_effect_waits_for_cleanup_without_changing_latest_intent() {
        let controller = Arc::new(Controller::default());
        let old = controller.begin().unwrap();
        let physical = controller.enter(&old).unwrap();
        let (send, receive) = mpsc::channel();
        let worker = {
            let controller = controller.clone();
            std::thread::spawn(move || {
                let _effect = controller.enter_effect().unwrap();
                send.send(()).unwrap();
            })
        };
        assert!(receive.recv_timeout(Duration::from_millis(20)).is_err());
        let latest = controller.begin().unwrap();
        assert!(old.cancelled());
        drop(physical);
        receive.recv_timeout(Duration::from_secs(1)).unwrap();
        worker.join().unwrap();
        assert!(controller.is_current(&latest));
    }
    #[test]
    fn old_completion_cannot_release_another_intent_or_make_old_request_current() {
        let controller = Controller::default();
        let old = controller.begin().unwrap();
        let permit = controller.enter(&old).unwrap();
        let new = controller.begin().unwrap();
        drop(permit);
        assert!(!controller.is_current(&old));
        assert!(controller.is_current(&new));
        assert!(controller.enter(&new).is_ok());
    }

    #[test]
    fn exhausted_identifiers_cancel_previous_work_and_never_wrap() {
        let controller = Controller::default();
        let old = controller.begin().unwrap();
        controller.state.lock().unwrap().next_id = u64::MAX;
        assert!(controller.begin().is_err());
        assert!(old.cancelled());
        assert!(!controller.is_current(&old));
        assert!(controller.begin().is_err());
    }

    #[test]
    fn superseded_work_cannot_publish_even_after_waiting_for_current_publication() {
        let controller = Controller::default();
        let old = controller.begin().unwrap();
        assert_eq!(controller.publish(&old, || 1), Some(1));
        let current = controller.begin().unwrap();
        assert_eq!(
            controller.publish(&old, || panic!("stale publication")),
            None::<()>
        );
        assert_eq!(controller.publish(&current, || 2), Some(2));
        controller.cancel();
        assert_eq!(
            controller.publish(&current, || panic!("cancelled publication")),
            None::<()>
        );
    }
}
