//! Bounded, in-memory presentation milestones. Never stores source text,
//! selected app identity, clipboard data, errors, credentials or window titles.
use serde::Serialize;
use std::collections::VecDeque;

const MAX_EVENTS: usize = 48;
#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PopupHealth {
    events: VecDeque<Event>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Event {
    presentation_epoch: u64,
    phase: &'static str,
    recorded_at_unix_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    visible: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    resulting_epoch: Option<u64>,
}
impl PopupHealth {
    pub fn record(&mut self, epoch: u64, phase: &'static str, at: u64, visible: Option<bool>) {
        self.record_related(epoch, phase, at, visible, None);
    }
    pub fn record_related(
        &mut self,
        epoch: u64,
        phase: &'static str,
        at: u64,
        visible: Option<bool>,
        resulting_epoch: Option<u64>,
    ) {
        if self.events.len() == MAX_EVENTS {
            self.events.pop_front();
        }
        self.events.push_back(Event {
            presentation_epoch: epoch,
            phase,
            recorded_at_unix_ms: at,
            visible,
            resulting_epoch,
        });
    }
}
pub fn frontend_phase(phase: &str) -> Option<&'static str> {
    match phase {
        "sourceReceived" => Some("sourceReceived"),
        "sourceRetryDiscarded" => Some("sourceRetryDiscarded"),
        "domPrepared" => Some("domPrepared"),
        "presentationComplete" => Some("presentationComplete"),
        "presentationFailed" => Some("presentationFailed"),
        _ => None,
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn telemetry_is_bounded_and_contains_only_fixed_metadata() {
        let mut health = PopupHealth::default();
        for epoch in 0..100 {
            health.record(epoch, "showCompleted", 1000 + epoch, Some(true));
        }
        assert_eq!(health.events.len(), MAX_EVENTS);
        assert_eq!(health.events.front().unwrap().presentation_epoch, 52);
        let value = serde_json::to_value(health).unwrap();
        let event = value["events"][0].as_object().unwrap();
        assert_eq!(event.len(), 4);
        assert_eq!(event["phase"], "showCompleted");
        assert_eq!(event["visible"], true);
    }
    #[test]
    fn completed_show_links_capture_epoch_to_resumed_presentation() {
        let mut health = PopupHealth::default();
        health.record_related(7, "showCompleted", 100, Some(true), Some(8));
        let event = &serde_json::to_value(health).unwrap()["events"][0];
        assert_eq!(event["presentationEpoch"], 7);
        assert_eq!(event["resultingEpoch"], 8);
    }
    #[test]
    fn frontend_cannot_log_arbitrary_text_or_native_success() {
        for phase in [
            "sourceReceived",
            "domPrepared",
            "presentationComplete",
            "presentationFailed",
        ] {
            assert_eq!(frontend_phase(phase), Some(phase));
        }
        for phase in ["", "showCompleted", "secret text", "sourceReceived\nsecret"] {
            assert_eq!(frontend_phase(phase), None);
        }
    }
}

// An IPC success is sent only after the UI-thread closure has completed, not
// after it was merely queued. A dropped closure is an error, never success.
pub async fn await_show<T>(
    result: tokio::sync::oneshot::Receiver<Result<T, String>>,
) -> Result<T, String> {
    result
        .await
        .map_err(|_| "WINDOW_SHOW: 翻译窗口显示已中断".to_owned())?
}

#[cfg(test)]
mod acknowledgment_tests {
    use super::*;
    #[tokio::test]
    async fn queued_show_cannot_acknowledge_before_native_completion() {
        let (reply, result) = tokio::sync::oneshot::channel::<Result<u64, String>>();
        let mut waiting = Box::pin(await_show(result));
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(1), &mut waiting)
                .await
                .is_err()
        );
        reply.send(Ok(7)).unwrap();
        assert_eq!(waiting.await.unwrap(), 7);
    }
    #[tokio::test]
    async fn native_failure_or_dropped_operation_is_not_a_successful_show() {
        let (reply, result) = tokio::sync::oneshot::channel::<Result<(), String>>();
        reply
            .send(Err("WINDOW_SHOW: native failed".into()))
            .unwrap();
        assert_eq!(
            await_show(result).await.unwrap_err(),
            "WINDOW_SHOW: native failed"
        );
        let (reply, result) = tokio::sync::oneshot::channel::<Result<(), String>>();
        drop(reply);
        assert!(await_show(result)
            .await
            .unwrap_err()
            .starts_with("WINDOW_SHOW:"));
    }
}
