//! A cancelled native request can take a short time to unwind. Wait for that
//! cleanup instead of reporting a spurious immediate busy failure. This never
//! retries translation or releases a permit owned by a blocking native worker.
use std::{sync::Arc, time::Duration};
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
pub async fn acquire(
    serial: Arc<Semaphore>,
    limit: Duration,
) -> Result<OwnedSemaphorePermit, String> {
    tokio::time::timeout(limit, serial.acquire_owned())
        .await
        .map_err(|_| "SYSTEM_TRANSLATION_BUSY: 上一次系统翻译仍在结束，请稍后重试。".to_owned())?
        .map_err(|_| "SYSTEM_TRANSLATION_BUSY: 系统翻译暂时无法开始，请稍后重试。".to_owned())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn next_request_waits_for_previous_native_cleanup() {
        let serial = Arc::new(Semaphore::new(1));
        let previous = serial.clone().acquire_owned().await.unwrap();
        let next = tokio::spawn(acquire(serial.clone(), Duration::from_secs(2)));
        tokio::task::yield_now().await;
        assert!(!next.is_finished());
        drop(previous);
        let permit = next.await.unwrap().unwrap();
        assert_eq!(serial.available_permits(), 0);
        drop(permit);
        assert_eq!(serial.available_permits(), 1);
    }
    #[tokio::test]
    async fn cleanup_timeout_does_not_release_running_worker() {
        let serial = Arc::new(Semaphore::new(1));
        let previous = serial.clone().acquire_owned().await.unwrap();
        assert!(acquire(serial.clone(), Duration::from_millis(1))
            .await
            .unwrap_err()
            .starts_with("SYSTEM_TRANSLATION_BUSY:"));
        assert_eq!(serial.available_permits(), 0);
        drop(previous);
        assert_eq!(serial.available_permits(), 1);
    }
    #[tokio::test]
    async fn cancelled_waiter_never_starts_or_leaks_capacity() {
        let serial = Arc::new(Semaphore::new(1));
        let previous = serial.clone().acquire_owned().await.unwrap();
        let waiting = tokio::spawn(acquire(serial.clone(), Duration::from_secs(2)));
        tokio::task::yield_now().await;
        waiting.abort();
        assert!(waiting.await.unwrap_err().is_cancelled());
        drop(previous);
        assert!(serial.try_acquire().is_ok());
    }
}
