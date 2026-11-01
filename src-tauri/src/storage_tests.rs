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
fn json_failed_replacement_keeps_destination_and_cleans_temporary_file() {
    let fixture = StorageFixture::new();
    let path = fixture.file();
    fs::create_dir(&path).unwrap();
    let original = path.join("original");
    fs::write(&original, b"preserved").unwrap();
    assert!(write_json(&path, &serde_json::json!({"fixture": "replacement"})).is_err());
    assert_eq!(fs::read(&original).unwrap(), b"preserved");
    assert_eq!(fs::read_dir(&fixture.0).unwrap().count(), 1);
}

#[cfg(unix)]
#[test]
fn json_write_never_follows_a_legacy_temporary_symlink() {
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let victim = fixture.0.join("unrelated.txt");
    fs::write(&victim, b"must not truncate").unwrap();
    std::os::unix::fs::symlink(&victim, path.with_extension("json.tmp")).unwrap();
    write_json(&path, &serde_json::json!({"saved": true})).unwrap();
    assert_eq!(fs::read(&victim).unwrap(), b"must not truncate");
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&fs::read(path).unwrap()).unwrap(),
        serde_json::json!({"saved": true})
    );
}

#[test]
fn json_concurrent_replacements_are_complete_and_do_not_share_temporary_files() {
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
    std::thread::scope(|scope| {
        for writer in 0..8 {
            let path = &path;
            let barrier = barrier.clone();
            scope.spawn(move || {
                barrier.wait();
                for _ in 0..8 {
                    write_json(
                        path,
                        &serde_json::json!({"writer": writer, "text": "x".repeat(65536)}),
                    )
                    .unwrap();
                    let value: serde_json::Value =
                        serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
                    assert_eq!(value["text"].as_str().unwrap().len(), 65536);
                }
            });
        }
    });
    assert_eq!(fs::read_dir(&fixture.0).unwrap().count(), 1);
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

// Readers using the normal Rust sharing mode must not prevent replacement,
// and an already-open reader must retain the complete previous snapshot.
#[cfg(target_os = "windows")]
#[test]
fn windows_shared_reader_retains_old_snapshot_during_atomic_replace() {
    use std::io::Read;
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let original = serde_json::json!({"text": "old snapshot"});
    let replacement = serde_json::json!({"text": "new snapshot"});
    write_json(&path, &original).unwrap();
    let mut reader = fs::File::open(&path).unwrap();
    write_json(&path, &replacement).unwrap();
    let mut old_bytes = Vec::new();
    reader.read_to_end(&mut old_bytes).unwrap();
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&old_bytes).unwrap(),
        original
    );
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&fs::read(&path).unwrap()).unwrap(),
        replacement
    );
    assert_eq!(fs::read_dir(&fixture.0).unwrap().count(), 1);
}

// Keep publication handles alive deliberately: create_new is not an exclusive
// sharing mode. Readers must work before the writer's handle has been closed,
// including after a subsequent publication replaces that still-open file.
#[cfg(target_os = "windows")]
#[test]
fn windows_published_json_is_readable_while_publication_handles_remain_open() {
    use std::io::{Read, Write};
    use std::os::windows::fs::OpenOptionsExt;
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let mut handles = Vec::new();
    let mut first_reader = None;
    for generation in 0..2 {
        let temporary = fixture.0.join(format!("publication-{generation}.tmp"));
        // Match write_json's actual handle access and default sharing mode.
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .access_mode(0x40000000 | 0x00010000)
            .open(&temporary)
            .unwrap();
        let expected = serde_json::json!({"generation": generation});
        file.write_all(&serde_json::to_vec(&expected).unwrap())
            .unwrap();
        file.sync_all().unwrap();
        crate::windows_atomic_file::replace(&file, &path).unwrap();
        handles.push(file);
        let actual: serde_json::Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(actual, expected);
        if generation == 0 {
            first_reader = Some(fs::File::open(&path).unwrap());
        }
    }
    let mut old_bytes = Vec::new();
    first_reader
        .as_mut()
        .unwrap()
        .read_to_end(&mut old_bytes)
        .unwrap();
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&old_bytes).unwrap(),
        serde_json::json!({"generation": 0})
    );
    drop(first_reader);
    drop(handles);
    assert_eq!(fs::read_dir(&fixture.0).unwrap().count(), 1);
}

// Keep the original fs::read concurrency regression unchanged. This companion
// separates the original failing Open/Read operation without retrying it or
// reading paths/data into diagnostics. NTSTATUS is sampled before another OS
// operation; it is supplementary thread state, not a replacement for io::Error.
#[cfg(target_os = "windows")]
#[test]
fn windows_concurrent_json_open_and_read_report_original_failure_stage() {
    use std::io::Read;
    #[link(name = "ntdll")]
    unsafe extern "system" {
        fn RtlGetLastNtStatus() -> i32;
    }
    let fixture = StorageFixture::new();
    let path = fixture.file();
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
    std::thread::scope(|scope| {
        for writer in 0..8 {
            let path = &path;
            let barrier = barrier.clone();
            scope.spawn(move || {
                barrier.wait();
                for iteration in 0..8 {
                    write_json(
                        path,
                        &serde_json::json!({"writer": writer, "text": "x".repeat(65536)}),
                    )
                    .unwrap();
                    let mut reader = match fs::File::open(path) {
                        Ok(reader) => reader,
                        Err(error) => {
                            // SAFETY: no arguments; reads this thread's native
                            // last-status slot without accessing fixture data.
                            let status = unsafe { RtlGetLastNtStatus() } as u32;
                            panic!(
                                "json read stage=open writer={writer} iteration={iteration} win32={:?} ntstatus=0x{status:08X}",
                                error.raw_os_error()
                            );
                        }
                    };
                    let mut bytes = Vec::new();
                    if let Err(error) = reader.read_to_end(&mut bytes) {
                        // SAFETY: same thread-local observation as above.
                        let status = unsafe { RtlGetLastNtStatus() } as u32;
                        panic!(
                            "json read stage=read writer={writer} iteration={iteration} win32={:?} ntstatus=0x{status:08X}",
                            error.raw_os_error()
                        );
                    }
                    let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
                    assert_eq!(value["text"].as_str().unwrap().len(), 65536);
                }
            });
        }
    });
    assert_eq!(fs::read_dir(&fixture.0).unwrap().count(), 1);
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
        preserved: false,
        provider_id: "fixture".into(),
        provider_name: "fixture".into(),
        text: "y".repeat(3 * 1024 * 1024),
        error: None,
        elapsed_ms: 0,
        resolved_languages: None,
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
