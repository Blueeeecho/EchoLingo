//! Opt-in, memory-only fixed-state trace. No text, coordinates, names or paths.
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, VecDeque};
#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "camelCase")]
pub enum Stage {
    NativeDown,
    OutsideHeader,
    GuardFrame,
    GuardViewport,
    GuardButton,
    HeaderStarted,
    HeaderMoved,
    NativeHandoff,
    FitDeferred,
    FitApplied,
    FitRepositioned,
    GuardEpoch,
    GuardNotPresented,
    GuardNotPopup,
    GuardHidden,
    GuardToken,
    Released,
    Replaced,
    PresentationChanged,
    Hidden,
    Disabled,
    Closed,
    Escape,
    InvalidFrame,
    InvalidOwner,
    DomHeaderDown,
    DomSourceDown,
    DomResultDown,
    DomBlur,
    ResizeWestDown,
    ResizeEastDown,
    ResizeRequest,
    ResizeBlur,
    ResizePointerCancel,
    ResizeCaptureLost,
    ResizeButtonsZero,
}
#[derive(Default)]
pub struct Diagnostics {
    enabled: bool,
    events: VecDeque<Stage>,
    counts: BTreeMap<Stage, u32>,
}
impl Diagnostics {
    pub fn set_enabled(&mut self, enabled: bool) {
        if enabled {
            self.events.clear();
            self.counts.clear();
        }
        self.enabled = enabled;
    }
    pub fn record(&mut self, stage: Stage) {
        if !self.enabled {
            return;
        }
        let count = self.counts.entry(stage).or_default();
        *count = count.saturating_add(1).min(1_000_000);
        if self.events.back() != Some(&stage) {
            if self.events.len() == 64 {
                self.events.pop_front();
            }
            self.events.push_back(stage);
        }
    }
    pub fn snapshot(&self) -> serde_json::Value {
        serde_json::json!({"schemaVersion":1,"enabled":self.enabled,"owner":"appkit-window-server-v1",
            "memoryOnly":true,"containsContent":false,"containsCoordinates":false,
            "events":self.events,"counts":self.counts})
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn off_by_default_and_after_stop() {
        let mut d = Diagnostics::default();
        d.record(Stage::NativeDown);
        assert!(d.events.is_empty());
        d.set_enabled(true);
        d.record(Stage::NativeDown);
        d.set_enabled(false);
        d.record(Stage::HeaderStarted);
        assert_eq!(d.events.len(), 1);
        assert!(!d.snapshot()["enabled"].as_bool().unwrap());
    }
    #[test]
    fn fixed_events_bounded_and_guards_distinct_from_stops() {
        let mut d = Diagnostics::default();
        d.set_enabled(true);
        for _ in 0..100 {
            d.record(Stage::GuardToken);
            d.record(Stage::InvalidOwner);
        }
        assert_eq!(d.events.len(), 64);
        assert_eq!(d.counts[&Stage::GuardToken], 100);
        assert_eq!(d.counts[&Stage::InvalidOwner], 100);
        assert!(!d.counts.contains_key(&Stage::PresentationChanged));
        assert!(serde_json::from_str::<Stage>("\"arbitrary user text\"").is_err());
        d.set_enabled(true);
        assert!(d.events.is_empty());
        assert!(d.counts.is_empty());
    }
}
