//! Conservative path removal for diagnostic text intended to be copied/shared.
use serde_json::Value;
const REDACTED: &str = "[local path hidden]";

pub fn scrub(value: &mut Value) {
    match value {
        Value::Object(fields) => {
            for (key, value) in fields {
                let key = key.to_ascii_lowercase();
                if (key.ends_with("path") || key.ends_with("directory")) && value.is_string() {
                    *value = Value::String(REDACTED.into());
                } else {
                    scrub(value);
                }
            }
        }
        Value::Array(values) => {
            for value in values {
                scrub(value);
            }
        }
        Value::String(text) if contains_path(text) => *text = REDACTED.into(),
        _ => {}
    }
}
fn contains_path(text: &str) -> bool {
    // Native error strings can embed paths, not only dedicated path fields.
    // Prefer losing error detail to copying a username into a public issue.
    text.contains('\\')
        || text.char_indices().any(|(index, ch)| {
            ch == '/'
                && (index == 0
                    || text[..index].chars().next_back().is_some_and(|c| {
                        c.is_whitespace() || matches!(c, ':' | '"' | '\'' | '(' | '=')
                    }))
        })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn removes_nested_mac_windows_and_error_paths() {
        let mut value = serde_json::json!({"dataDirectory":"/fixture-mac/private/Library/EchoLingo", "native":{"bundlePath":"/Applications/EchoLingo.app","error":"read failed: /home/private/file", "other":"Q:\\fixture\\private\\file"}, "warnings":["open '/tmp/private/file' failed"],"counter":2,"granted":true,"version":"0.2.17"});
        scrub(&mut value);
        let encoded = value.to_string();
        assert!(!encoded.contains("private"));
        assert!(!encoded.contains("/Applications"));
        assert_eq!(value["counter"], 2);
        assert_eq!(value["granted"], true);
        assert_eq!(value["version"], "0.2.17");
    }
}
