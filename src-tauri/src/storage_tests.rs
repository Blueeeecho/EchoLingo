//! Disposable file/history regressions. No user settings, history or credentials.

use super::*;
use std::sync::atomic::AtomicU64;

struct StorageFixture(PathBuf);

impl StorageFixture {
    fn new() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "echolingo-storage-回声译-{}-{stamp}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&directory).unwrap();
        Self(directory)
    }

    fn file(&self) -> PathBuf {
        self.0.join("history.json")
    }
}

impl Drop for StorageFixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn json_create_and_replace_preserve_unicode_and_remove_temporary_file() {
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let old = serde_json::json!({"text": "原有记录 🪞", "favorite": true});
    let updated = serde_json::json!({
        "text": "回声译\n日本語 café 🪞\0 quotes: \" ' ` $() ; & | \\",
        "results": ["line one\r\nline two", "翻译结果"],
        "favorite": false
    });
    write_json(&path, &old).unwrap();
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&fs::read(&path).unwrap()).unwrap(),
        old
    );
    write_json(&path, &updated).unwrap();
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&fs::read(&path).unwrap()).unwrap(),
        updated
    );
    assert!(!path.with_extension("json.tmp").exists());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}

#[test]
fn json_temporary_file_failure_keeps_original_bytes() {
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let original = b"{\"fixture\":\"original data, never a user record\"}\n";
    fs::write(&path, original).unwrap();
    // A directory at the temporary-file name reliably prevents opening it on
    // both platforms, including elevated test accounts that ignore chmod.
    let blocked = path.with_extension("json.tmp");
    fs::create_dir(&blocked).unwrap();
    assert!(write_json(&path, &serde_json::json!({"fixture": "replacement"})).is_err());
    assert_eq!(fs::read(&path).unwrap(), original);
    assert!(blocked.is_dir());
}

#[test]
fn json_serialization_failure_does_not_touch_original_or_create_temporary_file() {
    struct InvalidFixture;
    impl Serialize for InvalidFixture {
        fn serialize<S: serde::Serializer>(&self, _serializer: S) -> Result<S::Ok, S::Error> {
            Err(serde::ser::Error::custom("fixture serialization failure"))
        }
    }
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let original = b"{\"fixture\":\"keep this original\"}";
    fs::write(&path, original).unwrap();
    assert!(write_json(&path, &InvalidFixture).is_err());
    assert_eq!(fs::read(&path).unwrap(), original);
    assert!(!path.with_extension("json.tmp").exists());
}

#[cfg(target_os = "windows")]
#[test]
fn windows_locked_target_preserves_original_and_can_be_retried() {
    use std::os::windows::fs::OpenOptionsExt;
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let original = b"{\"fixture\":\"locked original\"}";
    fs::write(&path, original).unwrap();
    // Real Win32 sharing semantics prohibit replacement while this handle is
    // open. The Unicode fixture path also exercises MoveFileExW path encoding.
    let locked_target = fs::OpenOptions::new()
        .read(true)
        .share_mode(0)
        .open(&path)
        .unwrap();
    let replacement = serde_json::json!({"fixture": "替换成功 🪞"});
    assert!(write_json(&path, &replacement).is_err());
    drop(locked_target);
    assert_eq!(fs::read(&path).unwrap(), original);
    write_json(&path, &replacement).unwrap();
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&fs::read(&path).unwrap()).unwrap(),
        replacement
    );
    assert!(!path.with_extension("json.tmp").exists());
}

fn entry(id: &str, favorite: bool) -> HistoryEntry {
    HistoryEntry {
        id: id.into(),
        text: String::new(),
        source_language: "auto".into(),
        target_language: "zh-Hans".into(),
        results: vec![],
        created_at: 0,
        favorite,
    }
}

fn ids(history: &[HistoryEntry]) -> Vec<&str> {
    history.iter().map(|item| item.id.as_str()).collect()
}

fn history_bytes(history: &[HistoryEntry]) -> usize {
    serde_json::to_vec(history).unwrap().len()
}

#[test]
fn history_count_limit_is_hard_even_when_every_entry_is_favorite() {
    let mut history: Vec<_> = (0..6)
        .map(|i| entry(&format!("favorite-{i}"), true))
        .collect();
    trim_history(&mut history, 3);
    assert_eq!(ids(&history), ["favorite-0", "favorite-1", "favorite-2"]);
    trim_history(&mut history, 0);
    assert!(history.is_empty());
    trim_history(&mut history, 0);
    assert!(history.is_empty());
}

#[test]
fn history_byte_limit_evicts_oldest_nonfavorite_and_preserves_order() {
    let mut recent = entry("recent", false);
    recent.text = "x".repeat(3 * 1024 * 1024);
    let mut old = entry("old", false);
    old.results.push(TranslationResult {
        provider_id: "fixture".into(),
        provider_name: "fixture".into(),
        text: "y".repeat(3 * 1024 * 1024),
        error: None,
        elapsed_ms: 0,
    });
    let mut favorite = entry("older-favorite", true);
    favorite.text = "中".repeat(1024 * 1024);
    let mut history = vec![recent, old, favorite];
    assert!(history_bytes(&history) > MAX_HISTORY_BYTES);
    trim_history(&mut history, 100);
    assert_eq!(ids(&history), ["recent", "older-favorite"]);
    assert!(history_bytes(&history) <= MAX_HISTORY_BYTES);
}

#[test]
fn history_favorites_cannot_bypass_byte_limit_or_keep_oversized_entries() {
    let mut recent = entry("recent-favorite", true);
    recent.text = "x".repeat(5 * 1024 * 1024);
    let mut old = entry("old-favorite", true);
    old.text = "y".repeat(5 * 1024 * 1024);
    let mut history = vec![recent, old];
    trim_history(&mut history, 100);
    assert_eq!(ids(&history), ["recent-favorite"]);
    assert!(history_bytes(&history) <= MAX_HISTORY_BYTES);

    let mut oversized = entry("oversized-favorite", true);
    oversized.text = "x".repeat(MAX_HISTORY_BYTES + 1);
    let mut history = vec![oversized];
    trim_history(&mut history, 100);
    assert!(history.is_empty());
}

#[test]
fn history_byte_limit_includes_json_array_delimiters() {
    for over_limit in [false, true] {
        let mut history = vec![entry("boundary-favorite", true)];
        let overhead = history_bytes(&history);
        history[0].text = "x".repeat(MAX_HISTORY_BYTES - overhead + usize::from(over_limit));
        assert_eq!(
            history_bytes(&history),
            MAX_HISTORY_BYTES + usize::from(over_limit)
        );
        trim_history(&mut history, 100);
        if over_limit {
            assert!(
                history.is_empty(),
                "a favorite one byte over the budget must be removed"
            );
        } else {
            assert_eq!(ids(&history), ["boundary-favorite"]);
        }
        assert!(history_bytes(&history) <= MAX_HISTORY_BYTES);
    }
}

#[test]
fn oversized_new_result_does_not_erase_other_history() {
    let mut oversized = entry("oversized-new-favorite", true);
    oversized.text = "x".repeat(MAX_HISTORY_BYTES);
    let mut history = vec![
        oversized,
        entry("healthy-recent", false),
        entry("healthy-old-favorite", true),
    ];
    trim_history(&mut history, 100);
    assert_eq!(ids(&history), ["healthy-recent", "healthy-old-favorite"]);
    assert!(history_bytes(&history) <= MAX_HISTORY_BYTES);
}
