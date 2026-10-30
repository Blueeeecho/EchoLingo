//! Opt-in, bounded metadata for generated acceptance fixtures. No text or keys.
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Stage {
    Ready,
    Arrival,
    Handler,
    TranslateStart,
    Ticket,
    Dispatch,
    Complete,
    Error,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Record {
    pub stage: Stage,
    pub sequence: u64,
    pub timestamp: u64,
    pub epoch: u64,
    pub generation: u64,
    pub request_epoch: Option<u64>,
    pub request_generation: Option<u64>,
    pub composing: bool,
    pub shift: bool,
    pub alt: bool,
    pub ctrl: bool,
    pub meta: bool,
    pub repeat: bool,
    pub translating: bool,
    pub source_nonempty: bool,
    pub source_focused: bool,
    pub settings_ready: bool,
}
pub fn enabled() -> bool {
    std::env::var("ECHOLINGO_INPUT_DIAGNOSTICS").as_deref() == Ok("1")
}
pub fn append(records: &mut Vec<Record>, record: Record) {
    if records.len() == 32 {
        records.remove(0);
    }
    records.push(record);
}
#[cfg(test)]
mod tests {
    use super::*;
    fn record() -> serde_json::Value {
        serde_json::json!({"stage":"arrival","sequence":1,"timestamp":1,"epoch":1,"generation":1,"composing":false,"shift":false,"alt":false,"ctrl":false,"meta":false,"repeat":false,"translating":false,"sourceNonempty":true,"sourceFocused":true,"settingsReady":true})
    }
    #[test]
    fn rejects_content_and_unknown_stages() {
        let mut value = record();
        value["text"] = serde_json::json!("private");
        assert!(serde_json::from_value::<Record>(value).is_err());
        let mut value = record();
        value["stage"] = serde_json::json!("arbitrary");
        assert!(serde_json::from_value::<Record>(value).is_err());
    }
    #[test]
    fn keeps_only_bounded_metadata() {
        let mut records = Vec::new();
        for sequence in 0..50 {
            let mut r: Record = serde_json::from_value(record()).unwrap();
            r.sequence = sequence;
            append(&mut records, r);
        }
        assert_eq!(records.len(), 32);
        assert_eq!(records[0].sequence, 18);
    }
}
