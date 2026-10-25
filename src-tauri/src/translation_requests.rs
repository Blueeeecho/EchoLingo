use futures_util::future::{AbortHandle, AbortRegistration, Abortable};
use serde::Serialize;
use std::{future::Future, sync::Mutex};

pub const CANCELLED: &str = "CANCELLED: 翻译已取消";

#[derive(Default)]
pub struct TranslationRequests(Mutex<Requests>);

#[derive(Default)]
struct Requests {
    next_id: u64,
    presentation: Presentation,
    active: Option<Request>,
}
#[derive(Clone, Copy, Default, Debug, PartialEq, Eq, Serialize)]
pub struct Presentation {
    pub epoch: u64,
    pub presented: bool,
}
struct Request {
    id: u64,
    abort: AbortHandle,
    registration: Option<AbortRegistration>,
}

impl TranslationRequests {
    pub fn is_current(&self, id: u64) -> Result<bool, String> {
        let requests = self.0.lock().map_err(|_| "翻译状态异常")?;
        Ok(requests.presentation.presented
            && requests
                .active
                .as_ref()
                .is_some_and(|active| active.id == id && !active.abort.is_aborted()))
    }
    pub fn presentation(&self) -> Result<Presentation, String> {
        Ok(self.0.lock().map_err(|_| "翻译状态异常")?.presentation)
    }

    // A native hide must invalidate even a begin IPC that has not been handled
    // yet. Request IDs alone cannot cover that interval. Reopening advances the
    // epoch again, so a delayed old hide event cannot cancel the new popup.
    pub fn suspend(&self) -> Result<Presentation, String> {
        self.invalidate_presentation(Some(false))
    }

    pub fn invalidate(&self) -> Result<Presentation, String> {
        self.invalidate_presentation(None)
    }

    fn invalidate_presentation(&self, presented: Option<bool>) -> Result<Presentation, String> {
        let mut requests = self.0.lock().map_err(|_| "翻译状态异常")?;
        requests.presentation.epoch = requests
            .presentation
            .epoch
            .checked_add(1)
            .ok_or("请重新启动应用")?;
        if let Some(presented) = presented {
            requests.presentation.presented = presented;
        }
        if let Some(active) = requests.active.take() {
            active.abort.abort();
        }
        Ok(requests.presentation)
    }

    pub fn resume(&self, expected_epoch: Option<u64>) -> Result<Presentation, String> {
        let mut requests = self.0.lock().map_err(|_| "翻译状态异常")?;
        if expected_epoch.is_some_and(|epoch| epoch != requests.presentation.epoch) {
            return Err(CANCELLED.into());
        }
        if !requests.presentation.presented {
            requests.presentation.epoch = requests
                .presentation
                .epoch
                .checked_add(1)
                .ok_or("请重新启动应用")?;
            requests.presentation.presented = true;
        }
        Ok(requests.presentation)
    }

    // Allocate on the backend before starting HTTP. Cancellation that arrives
    // before translate's IPC is therefore effective, without unbounded tombstones.
    pub fn begin(&self, presentation_epoch: u64) -> Result<u64, String> {
        let mut requests = self.0.lock().map_err(|_| "翻译状态异常")?;
        if !requests.presentation.presented || requests.presentation.epoch != presentation_epoch {
            return Err(CANCELLED.into());
        }
        let id = requests.next_id.checked_add(1).ok_or("请重新启动应用")?;
        requests.next_id = id;
        if let Some(previous) = requests.active.take() {
            previous.abort.abort();
        }
        let (abort, registration) = AbortHandle::new_pair();
        requests.active = Some(Request {
            id,
            abort,
            registration: Some(registration),
        });
        Ok(id)
    }

    pub fn cancel(&self, id: Option<u64>) -> Result<Option<u64>, String> {
        let mut requests = self.0.lock().map_err(|_| "翻译状态异常")?;
        if requests
            .active
            .as_ref()
            .is_some_and(|active| id.is_none_or(|id| active.id == id))
        {
            let active = requests.active.take().unwrap();
            active.abort.abort();
            return Ok(Some(active.id));
        }
        Ok(None)
    }

    pub async fn execute<T>(&self, id: u64, future: impl Future<Output = T>) -> Result<T, String> {
        let registration = {
            let mut requests = self.0.lock().map_err(|_| "翻译状态异常")?;
            requests
                .active
                .as_mut()
                .filter(|active| active.id == id)
                .and_then(|active| active.registration.take())
                .ok_or(CANCELLED)?
        };
        Abortable::new(future, registration)
            .await
            .map_err(|_| CANCELLED.into())
    }

    // Progress and cancellation share the same ordering boundary. A cancelled
    // or superseded request must never publish another chunk into a new popup.
    pub fn publish(&self, id: u64, emit: impl FnOnce(Presentation)) -> Result<bool, String> {
        let requests = self.0.lock().map_err(|_| "翻译状态异常")?;
        if !requests.presentation.presented
            || !requests
                .active
                .as_ref()
                .is_some_and(|active| active.id == id && !active.abort.is_aborted())
        {
            return Ok(false);
        }
        emit(requests.presentation);
        Ok(true)
    }

    // Keep cancellation and history commit in one ordering boundary. No await
    // occurs while locked; a superseded/cancelled request cannot commit afterward.
    pub fn finish<T>(
        &self,
        id: u64,
        commit: impl FnOnce() -> Result<T, String>,
    ) -> Result<T, String> {
        let mut requests = self.0.lock().map_err(|_| "翻译状态异常")?;
        if !requests
            .active
            .as_ref()
            .is_some_and(|active| active.id == id && !active.abort.is_aborted())
        {
            return Err(CANCELLED.into());
        }
        let result = commit();
        requests.active = None;
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };
    use std::time::Duration;

    #[test]
    fn progress_only_publishes_for_the_current_visible_request() {
        let requests = TranslationRequests::default();
        let epoch = requests.resume(None).unwrap().epoch;
        let old = requests.begin(epoch).unwrap();
        assert!(requests.is_current(old).unwrap());
        assert!(requests
            .publish(old, |p| assert_eq!(p.epoch, epoch))
            .unwrap());
        let current = requests.begin(epoch).unwrap();
        assert!(!requests.is_current(old).unwrap());
        assert!(!requests
            .publish(old, |_| panic!("superseded progress"))
            .unwrap());
        assert!(requests.publish(current, |_| {}).unwrap());
        requests.cancel(Some(current)).unwrap();
        assert!(!requests.is_current(current).unwrap());
        assert!(!requests
            .publish(current, |_| panic!("cancelled progress"))
            .unwrap());
        let last = requests.begin(epoch).unwrap();
        requests.suspend().unwrap();
        assert!(!requests
            .publish(last, |_| panic!("hidden progress"))
            .unwrap());
    }

    #[tokio::test]
    async fn cancellation_before_ipc_start_and_stale_cancellation_are_safe() {
        let requests = TranslationRequests::default();
        let epoch = requests.resume(None).unwrap().epoch;
        let old = requests.begin(epoch).unwrap();
        requests.cancel(Some(old)).unwrap();
        assert_eq!(
            requests.execute(old, async { 1 }).await.unwrap_err(),
            CANCELLED
        );
        let current = requests.begin(epoch).unwrap();
        assert_eq!(requests.cancel(Some(old)).unwrap(), None);
        assert_eq!(requests.execute(current, async { 2 }).await.unwrap(), 2);
        assert_eq!(requests.finish(current, || Ok(3)).unwrap(), 3);
        assert!(requests.finish(old, || Ok(4)).is_err());
    }

    #[tokio::test]
    async fn superseded_or_cancelled_results_never_reach_history_commit() {
        let requests = TranslationRequests::default();
        let epoch = requests.resume(None).unwrap().epoch;
        let old = requests.begin(epoch).unwrap();
        requests.execute(old, async {}).await.unwrap();
        let current = requests.begin(epoch).unwrap();
        let committed = AtomicBool::new(false);
        assert!(requests
            .finish(old, || {
                committed.store(true, Ordering::SeqCst);
                Ok(())
            })
            .is_err());
        requests.cancel(None).unwrap();
        assert!(requests
            .finish(current, || {
                committed.store(true, Ordering::SeqCst);
                Ok(())
            })
            .is_err());
        assert!(!committed.load(Ordering::SeqCst));
    }

    #[tokio::test]
    async fn native_hide_blocks_unallocated_tickets_and_reopen_rejects_stale_work() {
        let requests = TranslationRequests::default();
        assert_eq!(requests.begin(0).unwrap_err(), CANCELLED);
        let original = requests.resume(None).unwrap();
        let hidden = requests.suspend().unwrap();
        assert!(!hidden.presented);
        assert!(hidden.epoch > original.epoch);
        // The old begin IPC can arrive after hide, or even after a new show.
        assert_eq!(requests.begin(original.epoch).unwrap_err(), CANCELLED);
        assert_eq!(requests.begin(hidden.epoch).unwrap_err(), CANCELLED);
        assert_eq!(
            requests.resume(Some(original.epoch)).unwrap_err(),
            CANCELLED
        );
        let reopened = requests.resume(Some(hidden.epoch)).unwrap();
        assert!(reopened.presented);
        assert!(reopened.epoch > hidden.epoch);
        assert_eq!(requests.begin(original.epoch).unwrap_err(), CANCELLED);
        let current = requests.begin(reopened.epoch).unwrap();
        assert_eq!(requests.resume(Some(hidden.epoch)).unwrap_err(), CANCELLED);
        // Reopening an already visible input window preserves its valid ticket.
        assert_eq!(requests.resume(None).unwrap(), reopened);
        assert_eq!(requests.execute(current, async { 7 }).await.unwrap(), 7);
        assert_eq!(requests.finish(current, || Ok(8)).unwrap(), 8);
    }

    #[tokio::test]
    async fn history_clear_invalidates_pending_begins_without_suspending_visible_input() {
        let requests = TranslationRequests::default();
        let original = requests.resume(None).unwrap();
        let old = requests.begin(original.epoch).unwrap();
        let cleared = requests.invalidate().unwrap();
        assert!(cleared.presented);
        assert_eq!(requests.begin(original.epoch).unwrap_err(), CANCELLED);
        assert_eq!(
            requests.execute(old, async { 1 }).await.unwrap_err(),
            CANCELLED
        );
        assert!(requests.finish(old, || Ok(())).is_err());
        let current = requests.begin(cleared.epoch).unwrap();
        assert_eq!(requests.execute(current, async { 2 }).await.unwrap(), 2);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn cancelling_drops_a_real_pending_http_response() {
        use std::io::{Read, Write};
        use std::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let (received, started) = tokio::sync::oneshot::channel();
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(Duration::from_secs(4)))
                .unwrap();
            let mut bytes = [0; 8192];
            assert!(socket.read(&mut bytes).unwrap() > 0);
            socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100000\r\n\r\n").unwrap();
            received.send(()).unwrap();
            // The client must close the unfinished response, rather than wait
            // for its normal 45-second timeout. Drain any unread request bytes.
            loop {
                match socket.read(&mut bytes) {
                    Ok(0) => return true,
                    Ok(_) => continue,
                    Err(error) if error.kind() == std::io::ErrorKind::ConnectionReset => {
                        return true
                    }
                    Err(_) => return false,
                }
            }
        });
        let requests = Arc::new(TranslationRequests::default());
        let epoch = requests.resume(None).unwrap().epoch;
        let id = requests.begin(epoch).unwrap();
        let task_requests = requests.clone();
        let task = tokio::spawn(async move {
            let mut provider = crate::model::Settings::default()
                .providers
                .into_iter()
                .find(|p| p.kind == "openai")
                .unwrap();
            provider.base_url = format!("http://{address}/v1");
            let client = reqwest::Client::new();
            task_requests
                .execute(
                    id,
                    crate::translation::translate_one(
                        &client,
                        &provider,
                        Ok("fixture-only".into()),
                        "Hello",
                        "en",
                        "zh-Hans",
                    ),
                )
                .await
        });
        tokio::time::timeout(Duration::from_secs(4), started)
            .await
            .unwrap()
            .unwrap();
        requests.cancel(Some(id)).unwrap();
        let result = tokio::time::timeout(Duration::from_secs(2), task)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(result.unwrap_err(), CANCELLED);
        assert!(
            server.join().unwrap(),
            "cancelled HTTP body remained connected"
        );
    }
}
