//! Early installer-only check. Call before constructing Tauri or its plugins.
//! Exit0: available/disabled;2: occupied/reserved;3: unknown. Standard output
//! keeps two core lines for success, at most five conflict lines/480ASCII bytes,
//! and is empty for unknown. Every enabled startup binding is checked.
pub const FLAG: &str = "--check-shortcuts-on-install";

/// `arguments` includes argv0. No flag means no file/process/registry access.
pub fn run_if_requested(arguments: &[String]) -> Option<i32> {
    let request = requested(arguments)?;
    if !request {
        return Some(3);
    }
    #[cfg(target_os = "windows")]
    {
        let outcome = windows::run();
        let (code, output) = outcome.protocol();
        if !output.is_empty() {
            use std::io::Write;
            let mut stdout = std::io::stdout().lock();
            if stdout.write_all(output.as_bytes()).is_err() || stdout.flush().is_err() {
                return Some(3);
            }
        }
        Some(code)
    }
    #[cfg(not(target_os = "windows"))]
    Some(3)
}

fn requested(arguments: &[String]) -> Option<bool> {
    arguments
        .iter()
        .skip(1)
        .any(|arg| arg == FLAG)
        .then(|| arguments.len() == 2 && arguments[1] == FLAG)
}

#[cfg(any(target_os = "windows", test))]
use crate::model::{
    migrate_core_preferences, migrate_shortcut_defaults, validate_settings, Settings,
};
#[cfg(any(target_os = "windows", test))]
use tauri_plugin_global_shortcut::Shortcut;

#[cfg(any(target_os = "windows", test))]
const MAX_SETTINGS_BYTES: usize = 2 * 1024 * 1024;

#[cfg(any(target_os = "windows", test))]
#[derive(Clone)]
struct Binding {
    action: &'static str,
    combo: String,
    shortcut: Option<Shortcut>,
}

#[cfg(any(target_os = "windows", test))]
fn bindings(bytes: Option<&[u8]>) -> Result<Vec<Binding>, ()> {
    let mut settings = match bytes {
        Some(bytes) if bytes.len() <= MAX_SETTINGS_BYTES => {
            let value: serde_json::Value = serde_json::from_slice(bytes).map_err(|_| ())?;
            if !value.is_object() {
                return Err(());
            }
            serde_json::from_value::<Settings>(value).map_err(|_| ())?
        }
        Some(_) => return Err(()),
        None => Settings::default(),
    };
    // Match startup's pre-validation migration before choosing its shortcut
    // set. Startup falls back to defaults for invalid settings; a read-only
    // installer check cannot call the discarded configured keys available or
    // attribute a default conflict to them, so report unknown instead.
    migrate_core_preferences(&mut settings);
    validate_settings(&settings).map_err(|_| ())?;
    migrate_shortcut_defaults(&mut settings);
    let shortcuts = crate::shortcut_bindings::normalized(&settings.shortcuts).map_err(|_| ())?;
    [
        ("selection", shortcuts.selection),
        ("silentOcr", shortcuts.silent_ocr),
        ("capture", shortcuts.capture),
        ("ocr", shortcuts.ocr),
        ("input", shortcuts.input),
    ]
    .into_iter()
    .map(|(action, combo)| {
        let shortcut = if combo.is_empty() || matches!(combo.as_str(), "MouseX1" | "MouseX2") {
            None
        } else {
            Some(combo.parse().map_err(|_| ())?)
        };
        Ok(Binding {
            action,
            combo,
            shortcut,
        })
    })
    .collect()
}

#[cfg(any(target_os = "windows", test))]
enum Outcome {
    Available(Vec<Binding>),
    Conflict(Vec<Binding>),
    Unknown,
}

#[cfg(any(target_os = "windows", test))]
impl Outcome {
    fn protocol(&self) -> (i32, String) {
        let (code, rows) = match self {
            Self::Available(rows) => (0, rows),
            Self::Conflict(rows) => (2, rows),
            Self::Unknown => return (3, String::new()),
        };
        if rows.len() > 5 || (code == 0 && rows.len() != 5) || (code == 2 && rows.is_empty()) {
            return (3, String::new());
        }
        let mut output = String::new();
        let mut seen = std::collections::HashSet::new();
        for row in rows {
            if !matches!(
                row.action,
                "selection" | "silentOcr" | "capture" | "ocr" | "input"
            ) || !seen.insert(row.action)
                || !row.combo.is_ascii()
                || row.combo.len() > 80
                || row.combo.bytes().any(|byte| byte.is_ascii_control())
            {
                return (3, String::new());
            }
            // Success preserves the original installer protocol. Legacy
            // bindings still participated in registration and cleanup above.
            if code == 0 && !matches!(row.action, "selection" | "silentOcr") {
                continue;
            }
            output.push_str(row.action);
            output.push('=');
            output.push_str(&row.combo);
            output.push('\n');
        }
        if output.len() > 480 {
            return (3, String::new());
        }
        (code, output)
    }
}

#[cfg(any(target_os = "windows", test))]
#[derive(Clone, Copy)]
enum RegisterFailure {
    Conflict,
    Unknown,
}

#[cfg(any(target_os = "windows", test))]
trait ProbeRegistry {
    fn register(&mut self, binding: &Shortcut) -> Result<(), RegisterFailure>;
    fn unregister(&mut self, binding: &Shortcut) -> Result<(), ()>;
}

#[cfg(any(target_os = "windows", test))]
fn check(registry: &mut impl ProbeRegistry, rows: Vec<Binding>) -> Outcome {
    let mut registered = Vec::new();
    let mut conflicts = Vec::new();
    let mut unknown = false;
    for row in &rows {
        if let Some(shortcut) = &row.shortcut {
            match registry.register(shortcut) {
                Ok(()) => registered.push(*shortcut),
                Err(RegisterFailure::Conflict) => conflicts.push(row.clone()),
                Err(RegisterFailure::Unknown) => unknown = true,
            }
        }
    }
    // Remove only registrations that this check actually acquired. Even after
    // a cleanup error, attempt every remaining release, then drop the manager.
    for shortcut in registered.iter().rev() {
        if registry.unregister(shortcut).is_err() {
            unknown = true;
        }
    }
    if unknown {
        Outcome::Unknown
    } else if conflicts.is_empty() {
        Outcome::Available(rows)
    } else {
        Outcome::Conflict(conflicts)
    }
}

// Exact runtime-priority keys and optional side buttons use the native hook,
// not RegisterHotKey. A competing registration cannot classify them as occupied.
// The normal startup separately verifies hook installation and reports failure.
#[cfg(any(target_os = "windows", test))]
fn check_windows(registry: &mut impl ProbeRegistry, mut rows: Vec<Binding>) -> Outcome {
    for row in &mut rows {
        if crate::shortcut_bindings::windows_priority(&row.combo) {
            row.shortcut = None;
        }
    }
    check(registry, rows)
}

#[cfg(any(target_os = "windows", test))]
fn windows_reserved(binding: &Shortcut) -> bool {
    // Microsoft reserves F12 for debuggers even when none is currently running.
    // https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-registerhotkey
    binding.key == tauri_plugin_global_shortcut::Code::F12
}

#[cfg(target_os = "windows")]
mod windows {
    use super::*;
    use std::ffi::{c_void, OsString};
    use std::fs::File;
    use std::io::{ErrorKind, Read};
    use std::os::windows::ffi::OsStringExt;
    use std::path::{Path, PathBuf};

    const IDENTIFIER: &str = "io.github.blueeeecho.echolingo";
    type Handle = *mut c_void;
    struct OwnedHandle(Handle);
    impl Drop for OwnedHandle {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
    #[repr(C)]
    struct Guid {
        first: u32,
        second: u16,
        third: u16,
        tail: [u8; 8],
    }
    const ROAMING: Guid = Guid {
        first: 0x3eb685db,
        second: 0x65f9,
        third: 0x4cf6,
        tail: [0xa0, 0x3a, 0xe3, 0xef, 0x65, 0x72, 0x9f, 0x3d],
    };
    #[repr(C)]
    struct ProcessEntry {
        size: u32,
        usage: u32,
        process: u32,
        heap: usize,
        module: u32,
        threads: u32,
        parent: u32,
        priority: i32,
        flags: u32,
        name: [u16; 260],
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn CloseHandle(handle: Handle) -> i32;
        fn GetLastError() -> u32;
        fn CreateToolhelp32Snapshot(flags: u32, process: u32) -> Handle;
        fn Process32FirstW(snapshot: Handle, entry: *mut ProcessEntry) -> i32;
        fn Process32NextW(snapshot: Handle, entry: *mut ProcessEntry) -> i32;
        fn OpenProcess(access: u32, inherit: i32, process: u32) -> Handle;
        fn QueryFullProcessImageNameW(
            process: Handle,
            flags: u32,
            name: *mut u16,
            size: *mut u32,
        ) -> i32;
    }
    #[link(name = "shell32")]
    unsafe extern "system" {
        fn SHGetKnownFolderPath(
            folder: *const Guid,
            flags: u32,
            token: Handle,
            output: *mut *mut u16,
        ) -> i32;
    }
    #[link(name = "ole32")]
    unsafe extern "system" {
        fn CoTaskMemFree(memory: *mut c_void);
    }

    fn roaming_settings() -> Result<PathBuf, ()> {
        let mut raw = std::ptr::null_mut();
        let result = unsafe { SHGetKnownFolderPath(&ROAMING, 0, std::ptr::null_mut(), &mut raw) };
        struct FolderMemory(*mut u16);
        impl Drop for FolderMemory {
            fn drop(&mut self) {
                if !self.0.is_null() {
                    unsafe {
                        CoTaskMemFree(self.0.cast());
                    }
                }
            }
        }
        let owned = FolderMemory(raw);
        if result < 0 || owned.0.is_null() {
            return Err(());
        }
        for length in 0..32768 {
            if unsafe { *owned.0.add(length) } == 0 {
                let path = PathBuf::from(OsString::from_wide(unsafe {
                    std::slice::from_raw_parts(owned.0, length)
                }));
                if !path.is_absolute() {
                    return Err(());
                }
                return Ok(path.join(IDENTIFIER).join("settings.json"));
            }
        }
        Err(())
    }

    fn read_bindings() -> Result<Vec<Binding>, ()> {
        // Tauri app_data_dir on Windows is KnownFolder RoamingAppData/identifier.
        // No fallback to LOCALAPPDATA, overridden environment or another user.
        let path = roaming_settings()?;
        let file = match File::open(path) {
            Ok(file) => file,
            Err(error) if error.kind() == ErrorKind::NotFound => return bindings(None),
            Err(_) => return Err(()),
        };
        let metadata = file.metadata().map_err(|_| ())?;
        if !metadata.is_file() || metadata.len() > MAX_SETTINGS_BYTES as u64 {
            return Err(());
        }
        let mut bytes = Vec::new();
        file.take((MAX_SETTINGS_BYTES + 1) as u64)
            .read_to_end(&mut bytes)
            .map_err(|_| ())?;
        bindings(Some(&bytes))
    }

    fn process_image(process: u32) -> Result<PathBuf, ()> {
        let raw = unsafe { OpenProcess(0x1000, 0, process) }; // QUERY_LIMITED_INFORMATION
        if raw.is_null() {
            return Err(());
        }
        let handle = OwnedHandle(raw);
        let mut buffer = vec![0_u16; 32768];
        let mut length = buffer.len() as u32;
        if unsafe { QueryFullProcessImageNameW(handle.0, 0, buffer.as_mut_ptr(), &mut length) } == 0
            || length == 0
            || length as usize >= buffer.len()
        {
            return Err(());
        }
        let path = PathBuf::from(OsString::from_wide(&buffer[..length as usize]));
        path.canonicalize().map_err(|_| ())
    }

    fn own_instance_running(current: &Path) -> Result<bool, ()> {
        let own_name = current.file_name().ok_or(())?.to_str().ok_or(())?;
        let raw = unsafe { CreateToolhelp32Snapshot(2, 0) };
        if raw == (-1_isize) as Handle || raw.is_null() {
            return Err(());
        }
        let snapshot = OwnedHandle(raw);
        let mut entry: ProcessEntry = unsafe { std::mem::zeroed() };
        entry.size = std::mem::size_of::<ProcessEntry>() as u32;
        if unsafe { Process32FirstW(snapshot.0, &mut entry) } == 0 {
            return Err(());
        }
        // Read image paths only for another process with this executable name.
        // Same-name but inaccessible/different paths are unknown, never blamed
        // as external owners of a shortcut. No path is retained or printed.
        for _ in 0..8192 {
            let length = entry.name.iter().position(|ch| *ch == 0).ok_or(())?;
            let name = String::from_utf16(&entry.name[..length]).map_err(|_| ())?;
            if entry.process != std::process::id() && name.eq_ignore_ascii_case(own_name) {
                let other = process_image(entry.process)?;
                if other
                    .to_str()
                    .ok_or(())?
                    .eq_ignore_ascii_case(current.to_str().ok_or(())?)
                {
                    return Ok(true);
                }
                return Err(());
            }
            if unsafe { Process32NextW(snapshot.0, &mut entry) } == 0 {
                return if unsafe { GetLastError() } == 18 {
                    Ok(false)
                } else {
                    Err(())
                };
            }
        }
        Err(())
    }

    struct NativeRegistry(global_hotkey::GlobalHotKeyManager);
    impl ProbeRegistry for NativeRegistry {
        fn register(&mut self, binding: &Shortcut) -> Result<(), RegisterFailure> {
            if windows_reserved(binding) {
                return Err(RegisterFailure::Conflict);
            }
            self.0.register(*binding).map_err(|error| match error {
                global_hotkey::Error::AlreadyRegistered(_) => RegisterFailure::Conflict,
                _ => RegisterFailure::Unknown,
            })
        }
        fn unregister(&mut self, binding: &Shortcut) -> Result<(), ()> {
            self.0.unregister(*binding).map_err(|_| ())
        }
    }

    pub(super) fn run() -> Outcome {
        let result = (|| {
            let own = std::env::current_exe()
                .map_err(|_| ())?
                .canonicalize()
                .map_err(|_| ())?;
            if own_instance_running(&own)? {
                return Err(());
            }
            let rows = read_bindings()?;
            // The manager owns a temporary hidden native event HWND on this
            // short-lived thread. No Tauri/WebView/event handler is installed;
            // registration tests call synchronous native register/unregister,
            // and do not process or synthesize any keystrokes.
            let mut registry =
                NativeRegistry(global_hotkey::GlobalHotKeyManager::new().map_err(|_| ())?);
            let outcome = check_windows(&mut registry, rows);
            drop(registry);
            if own_instance_running(&own)? {
                return Err(());
            }
            Ok(outcome)
        })();
        result.unwrap_or(Outcome::Unknown)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::{HashSet, VecDeque};

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| (*value).into()).collect()
    }
    fn configured(selection: &str, ocr: &str) -> Vec<u8> {
        let mut settings = Settings::default();
        settings.shortcuts.selection = selection.into();
        settings.shortcuts.silent_ocr = ocr.into();
        settings.shortcuts.capture.clear();
        settings.shortcuts.ocr.clear();
        settings.shortcuts.input.clear();
        serde_json::to_vec(&settings).unwrap()
    }
    struct FakeRegistry {
        active: HashSet<u32>,
        failures: VecDeque<RegisterFailure>,
        removed: Vec<u32>,
        fail_cleanup: bool,
        conflict_id: Option<u32>,
    }
    impl FakeRegistry {
        fn new(failures: Vec<RegisterFailure>, fail_cleanup: bool) -> Self {
            Self {
                active: HashSet::new(),
                failures: failures.into(),
                removed: Vec::new(),
                fail_cleanup,
                conflict_id: None,
            }
        }
    }
    impl ProbeRegistry for FakeRegistry {
        fn register(&mut self, shortcut: &Shortcut) -> Result<(), RegisterFailure> {
            if self.conflict_id == Some(shortcut.id()) {
                return Err(RegisterFailure::Conflict);
            }
            if let Some(failure) = self.failures.pop_front() {
                return Err(failure);
            }
            assert!(self.active.insert(shortcut.id()));
            Ok(())
        }
        fn unregister(&mut self, shortcut: &Shortcut) -> Result<(), ()> {
            self.removed.push(shortcut.id());
            if self.fail_cleanup {
                return Err(());
            }
            assert!(self.active.remove(&shortcut.id()));
            Ok(())
        }
    }

    #[test]
    fn absent_flag_has_no_probe_side_effect_and_extra_arguments_are_unknown() {
        assert_eq!(run_if_requested(&args(&["app", "--settings"])), None);
        assert_eq!(requested(&args(&["app", FLAG])), Some(true));
        assert_eq!(
            run_if_requested(&args(&["app", FLAG, "--settings"])),
            Some(3)
        );
        assert_eq!(run_if_requested(&args(&["app", FLAG, FLAG])), Some(3));
    }
    #[test]
    fn missing_settings_checks_all_defaults_but_success_lists_only_core_bindings() {
        let rows = bindings(None).unwrap();
        assert_eq!(rows.len(), 5);
        assert_eq!(
            Outcome::Available(rows).protocol(),
            (0, "selection=Alt+D\nsilentOcr=Alt+S\n".into())
        );
    }
    #[test]
    fn real_configured_combinations_are_canonical_and_empty_is_disabled() {
        let rows = bindings(Some(&configured("control+keyd", ""))).unwrap();
        assert!(rows[1].shortcut.is_none());
        let mut registry = FakeRegistry::new(vec![], false);
        assert_eq!(
            check(&mut registry, rows).protocol(),
            (0, "selection=Ctrl+D\nsilentOcr=\n".into())
        );
        assert!(registry.active.is_empty());
        assert_eq!(registry.removed.len(), 1);
    }
    #[test]
    fn old_capture_defaults_migrate_before_probe_like_real_app_startup() {
        let mut settings = Settings::default();
        settings.shortcut_defaults_version = 0;
        settings.shortcuts.capture = "Alt+S".into();
        settings.shortcuts.silent_ocr = "Alt+C".into();
        let bytes = serde_json::to_vec(&settings).unwrap();
        assert_eq!(bindings(Some(&bytes)).unwrap()[1].combo, "Alt+S");
    }
    #[test]
    fn damaged_or_oversized_config_is_unknown_without_printing_it() {
        for bytes in [b"".as_slice(), b"not json", b"[]", b"{\"shortcuts\":null}"] {
            assert!(bindings(Some(bytes)).is_err());
        }
        assert!(bindings(Some(&vec![b' '; MAX_SETTINGS_BYTES + 1])).is_err());
        assert!(bindings(Some(&configured("Ctrl+A", "Control+KeyA"))).is_err());
    }
    #[test]
    fn startup_invalid_settings_cannot_report_disabled_keys_as_available() {
        let mut settings: Settings = serde_json::from_slice(&configured("", "")).unwrap();
        assert!(validate_settings(&settings).is_ok());
        assert!(bindings(Some(&serde_json::to_vec(&settings).unwrap()))
            .unwrap()
            .iter()
            .all(|row| row.shortcut.is_none()));
        settings.providers[0].id.clear();
        assert!(validate_settings(&settings).is_err());
        // Startup discards these disabled keys and uses defaults. The probe
        // must stop before native registration rather than return success.
        assert!(bindings(Some(&serde_json::to_vec(&settings).unwrap())).is_err());
    }
    #[test]
    fn valid_legacy_preferences_migrate_before_validation_and_keep_custom_keys() {
        let mut settings: Settings =
            serde_json::from_slice(&configured("control+keyd", "")).unwrap();
        settings.max_history = 200;
        settings.auto_hide_seconds = 15;
        assert!(validate_settings(&settings).is_err());
        let rows = bindings(Some(&serde_json::to_vec(&settings).unwrap())).unwrap();
        let mut registry = FakeRegistry::new(vec![], false);
        assert_eq!(
            check(&mut registry, rows).protocol(),
            (0, "selection=Ctrl+D\nsilentOcr=\n".into())
        );
        assert!(registry.active.is_empty());
        assert_eq!(registry.removed.len(), 1);
    }
    #[test]
    fn only_actual_conflicts_are_reported_and_no_others_registration_is_removed() {
        let mut registry = FakeRegistry::new(vec![RegisterFailure::Conflict], false);
        let (code, output) = check(&mut registry, bindings(None).unwrap()).protocol();
        assert_eq!((code, output), (2, "selection=Alt+D\n".into()));
        assert!(registry.active.is_empty());
        assert_eq!(registry.removed.len(), 1);
    }
    #[test]
    fn ambiguous_native_failure_takes_precedence_over_known_conflict() {
        let mut registry = FakeRegistry::new(
            vec![RegisterFailure::Conflict, RegisterFailure::Unknown],
            false,
        );
        assert_eq!(
            check(&mut registry, bindings(None).unwrap()).protocol(),
            (3, String::new())
        );
        assert_eq!(registry.removed.len(), 0);
    }
    #[test]
    fn cleanup_failure_is_unknown_and_all_remaining_releases_are_attempted() {
        let mut registry = FakeRegistry::new(vec![], true);
        assert_eq!(
            check(&mut registry, bindings(None).unwrap()).protocol(),
            (3, String::new())
        );
        assert_eq!(registry.removed.len(), 2);
    }

    #[test]
    fn opted_in_input_conflict_is_reported_instead_of_false_core_success() {
        let mut settings = Settings::default();
        settings.shortcuts.input = "Alt+A".into();
        let rows = bindings(Some(&serde_json::to_vec(&settings).unwrap())).unwrap();
        let id = rows
            .iter()
            .find(|row| row.action == "input")
            .unwrap()
            .shortcut
            .unwrap()
            .id();
        let mut registry = FakeRegistry::new(vec![], false);
        registry.conflict_id = Some(id);
        assert_eq!(
            check(&mut registry, rows).protocol(),
            (2, "input=Alt+A\n".into())
        );
        assert!(registry.active.is_empty());
        assert_eq!(registry.removed.len(), 2);
        assert!(!registry.removed.contains(&id));
    }

    #[test]
    fn all_five_enabled_bindings_are_checked_and_released_on_success() {
        let mut settings = Settings::default();
        settings.shortcuts.capture = "Ctrl+F1".into();
        settings.shortcuts.input = "Alt+A".into();
        settings.shortcuts.ocr = "Alt+Shift+S".into();
        let rows = bindings(Some(&serde_json::to_vec(&settings).unwrap())).unwrap();
        let mut registry = FakeRegistry::new(vec![], false);
        assert_eq!(
            check(&mut registry, rows).protocol(),
            (0, "selection=Alt+D\nsilentOcr=Alt+S\n".into())
        );
        assert!(registry.active.is_empty());
        assert_eq!(registry.removed.len(), 5);
    }

    #[test]
    fn disabled_bindings_are_not_registered_or_unregistered() {
        let rows = bindings(Some(&configured("", ""))).unwrap();
        let mut registry = FakeRegistry::new(vec![RegisterFailure::Conflict], false);
        assert_eq!(
            check(&mut registry, rows).protocol(),
            (0, "selection=\nsilentOcr=\n".into())
        );
        assert_eq!(registry.failures.len(), 1);
        assert!(registry.removed.is_empty() && registry.active.is_empty());
    }

    #[test]
    fn legacy_f12_reaches_the_same_reserved_policy_as_a_core_binding() {
        let mut settings = Settings::default();
        settings.shortcuts.input = "F12".into();
        let rows = bindings(Some(&serde_json::to_vec(&settings).unwrap())).unwrap();
        let input = rows.iter().find(|row| row.action == "input").unwrap();
        assert_eq!(input.combo, "F12");
        assert!(windows_reserved(&input.shortcut.unwrap()));
        assert_eq!(
            Outcome::Conflict(vec![input.clone()]).protocol(),
            (2, "input=F12\n".into())
        );
    }
    #[test]
    fn protocol_refuses_control_characters_non_ascii_and_excess_rows() {
        let mut rows = bindings(None).unwrap();
        rows[0].combo = "Alt+D\nsecret".into();
        assert_eq!(Outcome::Conflict(rows).protocol(), (3, String::new()));
        let mut rows = bindings(None).unwrap();
        rows[0].combo = "Ctrl+译".into();
        assert_eq!(Outcome::Conflict(rows).protocol(), (3, String::new()));
        let mut rows = bindings(None).unwrap();
        rows.push(rows[0].clone());
        assert_eq!(Outcome::Available(rows).protocol(), (3, String::new()));
    }
    #[test]
    fn debugger_reserved_f12_is_classified_without_registration() {
        assert!(windows_reserved(&"F12".parse().unwrap()));
        assert!(windows_reserved(&"Ctrl+F12".parse().unwrap()));
        assert!(!windows_reserved(&"F11".parse().unwrap()));
    }
}

#[cfg(test)]
mod native_priority_probe_tests {
    use super::*;
    struct Probe(usize);
    impl ProbeRegistry for Probe {
        fn register(&mut self, _: &Shortcut) -> Result<(), RegisterFailure> {
            self.0 += 1;
            Ok(())
        }
        fn unregister(&mut self, _: &Shortcut) -> Result<(), ()> {
            Ok(())
        }
    }
    #[test]
    fn priority_defaults_do_not_get_false_registerhotkey_conflicts() {
        let mut probe = Probe(0);
        let outcome = check_windows(&mut probe, bindings(None).unwrap());
        assert_eq!(outcome.protocol().0, 0);
        assert_eq!(probe.0, 0);
        // Optional opt-in actions still use the native registrar.
        let mut settings = Settings::default();
        settings.shortcuts.input = "Alt+A".into();
        settings.shortcuts.ocr = "Alt+Shift+S".into();
        let rows = bindings(Some(&serde_json::to_vec(&settings).unwrap())).unwrap();
        assert_eq!(check_windows(&mut probe, rows).protocol().0, 0);
        assert_eq!(probe.0, 2);
    }
}
