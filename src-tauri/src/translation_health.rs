//! One bounded, in-memory translation snapshot. Never stores text, provider
//! names/IDs, endpoints, credentials or upstream error messages.
use serde::Serialize;
use std::{
    sync::{Mutex, OnceLock},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ProviderHealth {
    index: usize,
    kind: &'static str,
    phase: &'static str,
    elapsed_ms: u64,
    error_category: Option<&'static str>,
}
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Snapshot {
    request_id: u64,
    started_at_unix_ms: u64,
    phase: &'static str,
    elapsed_ms: u64,
    error_category: Option<&'static str>,
    providers: Vec<ProviderHealth>,
    resolved_source: Option<&'static str>,
    resolved_target: Option<&'static str>,
}
#[derive(Default)]
struct Health {
    latest: Option<Snapshot>,
}
static HEALTH: OnceLock<Mutex<Health>> = OnceLock::new();
fn health() -> &'static Mutex<Health> {
    HEALTH.get_or_init(Mutex::default)
}
fn kind(value: &str) -> &'static str {
    match value {
        "system" => "system",
        "offline" => "offline",
        "openai" => "openai",
        "baidu" => "baidu",
        "youdao" => "youdao",
        "microsoft" => "microsoft",
        "deepl" => "deepl",
        "libretranslate" => "libretranslate",
        _ => "other",
    }
}
fn language(value: &str) -> &'static str {
    "auto am ar hy bn bg my ca chr hr cs da nl en en-US en-GB fi fr ka de el gu he hi hu is id it ja kn kk km ko lo ms ml mr mn no nb or ps fa pl pt pt-BR pa ro ru sr si sk sl es sv ta te th bo tr uk ur vi zh zh-Hans zh-Hant".split(' ').find(|code| *code == value).unwrap_or("other")
}
fn category(value: &str) -> &'static str {
    for prefix in [
        "SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED",
        "SYSTEM_TRANSLATION_UNSUPPORTED",
        "SYSTEM_TRANSLATION_UNAVAILABLE",
        "SYSTEM_TRANSLATION_LANGUAGE",
        "SYSTEM_TRANSLATION_BUSY",
        "SYSTEM_TRANSLATION_TIMEOUT",
        "SYSTEM_TRANSLATION_CANCELLED",
        "SYSTEM_TRANSLATION_FAILED",
        "NATIVE_PROTOCOL",
        "CANCELLED",
    ] {
        if value
            .strip_prefix(prefix)
            .is_some_and(|rest| rest.starts_with(':'))
        {
            return prefix;
        }
    }
    "other"
}
impl Health {
    fn update(&mut self, id: u64, f: impl FnOnce(&mut Snapshot)) {
        if let Some(s) = self.latest.as_mut().filter(|s| s.request_id == id) {
            f(s);
        }
    }
    fn start(&mut self, id: u64) -> bool {
        if self.latest.as_ref().is_some_and(|s| s.request_id >= id) {
            return false;
        }
        self.latest = Some(Snapshot {
            request_id: id,
            started_at_unix_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            phase: "started",
            elapsed_ms: 0,
            error_category: None,
            providers: Vec::new(),
            resolved_source: None,
            resolved_target: None,
        });
        true
    }
}
pub fn snapshot() -> serde_json::Value {
    health()
        .lock()
        .ok()
        .and_then(|h| serde_json::to_value(&h.latest).ok())
        .unwrap_or(serde_json::Value::Null)
}
pub struct RequestTrace {
    id: u64,
    active: bool,
    started: Instant,
    finished: bool,
}
impl RequestTrace {
    pub fn start(id: u64) -> Self {
        let active = health().lock().map(|mut h| h.start(id)).unwrap_or(false);
        Self {
            id,
            active,
            started: Instant::now(),
            finished: false,
        }
    }
    pub fn languages(&self, source: &str, target: &str) {
        if !self.active {
            return;
        }
        if let Ok(mut h) = health().lock() {
            h.update(self.id, |s| {
                s.phase = "languagesResolved";
                s.resolved_source = Some(language(source));
                s.resolved_target = Some(language(target));
            });
        }
    }
    pub fn finish(&mut self, error: Option<&str>) {
        if !self.active {
            return;
        }
        self.finished = true;
        if let Ok(mut h) = health().lock() {
            h.update(self.id, |s| {
                s.phase = if error.is_some() {
                    "failed"
                } else if s.providers.iter().any(|p| p.error_category.is_some()) {
                    "providerFailed"
                } else {
                    "completed"
                };
                s.elapsed_ms = self.started.elapsed().as_millis() as u64;
                s.error_category = error.map(category);
            });
        }
    }
}
impl Drop for RequestTrace {
    fn drop(&mut self) {
        if self.active && !self.finished {
            if let Ok(mut h) = health().lock() {
                h.update(self.id, |s| {
                    s.phase = "cancelled";
                    s.elapsed_ms = self.started.elapsed().as_millis() as u64;
                    s.error_category = Some("CANCELLED");
                });
            }
        }
    }
}
pub struct ProviderTrace {
    id: u64,
    index: usize,
    started: Instant,
    finished: bool,
}
impl ProviderTrace {
    pub fn start(id: u64, index: usize, provider_kind: &str) -> Self {
        if index < 16 {
            if let Ok(mut h) = health().lock() {
                h.update(id, |s| {
                    s.phase = "providers";
                    if s.providers.len() >= 16 || s.providers.iter().any(|p| p.index == index) {
                        return;
                    }
                    s.providers.push(ProviderHealth {
                        index,
                        kind: kind(provider_kind),
                        phase: "running",
                        elapsed_ms: 0,
                        error_category: None,
                    });
                });
            }
        }
        Self {
            id,
            index,
            started: Instant::now(),
            finished: false,
        }
    }
    pub fn finish(&mut self, error: Option<&str>) {
        self.finished = true;
        self.record(
            if error.is_some() {
                "failed"
            } else {
                "completed"
            },
            error.map(category),
        );
    }
    fn record(&self, phase: &'static str, error: Option<&'static str>) {
        if let Ok(mut h) = health().lock() {
            h.update(self.id, |s| {
                if let Some(p) = s.providers.iter_mut().find(|p| p.index == self.index) {
                    p.phase = phase;
                    p.elapsed_ms = self.started.elapsed().as_millis() as u64;
                    p.error_category = error;
                }
            });
        }
    }
}
impl Drop for ProviderTrace {
    fn drop(&mut self) {
        if !self.finished {
            self.record("cancelled", Some("CANCELLED"));
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn real_trace_lifecycle_is_bounded_redacted_and_stale_safe() {
        let id = health()
            .lock()
            .unwrap()
            .latest
            .as_ref()
            .map_or(1, |s| s.request_id + 1);
        let mut request = RequestTrace::start(id);
        request.languages("ca", "zh-Hans");
        let mut providers: Vec<_> = (0..30)
            .map(|i| ProviderTrace::start(id, i, "private provider key"))
            .collect();
        providers[0].finish(Some("SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: private source"));
        for provider in providers.iter_mut().skip(1) {
            provider.finish(None);
        }
        request.finish(None);
        let value = snapshot();
        assert_eq!(value["phase"], "providerFailed");
        assert_eq!(value["providers"].as_array().unwrap().len(), 16);
        assert_eq!(value["resolvedSource"], "ca");
        assert!(!value.to_string().contains("private"));
        let newer = RequestTrace::start(id + 1);
        request.finish(Some("private old failure"));
        providers[0].finish(None);
        assert_eq!(snapshot()["requestId"], id + 1);
        assert_eq!(snapshot()["phase"], "started");
        drop(newer);
        assert_eq!(snapshot()["phase"], "cancelled");
        let mut duplicate = RequestTrace::start(id + 1);
        duplicate.finish(None);
        assert_eq!(snapshot()["phase"], "cancelled");
    }
    #[test]
    fn older_completion_and_start_cannot_replace_newer_request() {
        let mut h = Health::default();
        h.start(9);
        h.start(8);
        h.update(8, |s| s.phase = "failed");
        assert_eq!(h.latest.unwrap().request_id, 9);
    }
    #[test]
    fn metadata_never_retains_untrusted_error_or_provider_values() {
        let secret = "private source https://secret.example/key";
        assert_eq!(kind(secret), "other");
        assert_eq!(category(secret), "other");
        assert_eq!(
            category(&format!("SYSTEM_TRANSLATION_FAILED: {secret}")),
            "SYSTEM_TRANSLATION_FAILED"
        );
        assert_eq!(category("SYSTEM_TRANSLATION_FAILEDINJECT: foo"), "other");
    }
    #[test]
    fn concurrent_provider_slots_preserve_failure_and_success() {
        let mut h = Health::default();
        h.start(1);
        h.update(1, |s| {
            s.providers.push(ProviderHealth {
                index: 0,
                kind: "system",
                phase: "failed",
                elapsed_ms: 4,
                error_category: Some("SYSTEM_TRANSLATION_FAILED"),
            });
            s.providers.push(ProviderHealth {
                index: 1,
                kind: "openai",
                phase: "completed",
                elapsed_ms: 5,
                error_category: None,
            });
        });
        let s = h.latest.unwrap();
        assert_eq!(s.providers.len(), 2);
        assert!(s.providers[0].error_category.is_some());
        assert!(s.providers[1].error_category.is_none());
    }
}
