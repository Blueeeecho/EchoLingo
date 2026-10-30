//! Empty recognition is a normal OCR outcome, not a permission/provider error.
//! Only the three explicit OCR actions may opt into the quiet blank view.
pub fn is_empty_error(action: &str, error: &str) -> bool {
    matches!(action, "capture" | "ocr" | "silentOcr") && error.starts_with("NO_TEXT:")
}
pub fn is_empty(action: &str, result: &Result<String, String>) -> bool {
    if !matches!(action, "capture" | "ocr" | "silentOcr") {
        return false;
    }
    match result {
        Ok(text) => text.trim().is_empty(),
        Err(error) => is_empty_error(action, error),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_ocr_entry_accepts_only_empty_success_or_exact_no_text_code() {
        for action in ["capture", "ocr", "silentOcr"] {
            for result in [
                Ok(String::new()),
                Ok(" \n\t".into()),
                Err("NO_TEXT: No text was recognized".into()),
            ] {
                assert!(is_empty(action, &result));
            }
            assert!(!is_empty(action, &Ok("recognized text".into())));
            for error in [
                "PERMISSION: Screen capture denied",
                "OCR: HTTP 503",
                "NATIVE_START: helper failed",
                "CLIPBOARD_RESTORE_FAILED: original unavailable",
                "CLIPBOARD_RESTORE_SKIPPED: kept new clipboard",
                "CANCELLED: selection dismissed",
                "NO_TEXT_NETWORK: failure",
                "OCR: server said NO_TEXT:",
                "NO_TEXT",
            ] {
                assert!(!is_empty(action, &Err(error.into())), "{action}: {error}");
            }
        }
    }
    #[test]
    fn other_actions_and_provider_failures_cannot_be_silenced_by_no_text() {
        for action in ["selection", "clipboard", "input", "translate", "unknown"] {
            assert!(!is_empty_error(action, "NO_TEXT: provider failed"));
            assert!(!is_empty(action, &Ok(String::new())));
        }
    }
}
