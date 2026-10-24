//! Blocking native operations. Run these on `tauri::async_runtime::spawn_blocking`.
//! In particular, do not activate the EchoLingo window before `selected_text`.

use serde_json::{json, Value};

pub fn selected_text() -> Result<String, String> {
    run_text("selected-text", None)
}

pub fn capture_ocr() -> Result<String, String> {
    run_text("capture-ocr", None)
}

pub fn clipboard_text() -> Result<String, String> {
    run_text("clipboard", None)
}

pub fn copy_text(text: &str) -> Result<(), String> {
    if text.len() > 2 * 1024 * 1024 {
        return Err("CLIPBOARD: Text exceeds the 2 MiB clipboard safety limit.".into());
    }
    run_text("copy", Some(text)).map(|_| ())
}

pub fn diagnostics() -> Value {
    match run("diagnostics", None) {
        Ok(result) => result.get("diagnostics").cloned().unwrap_or(result),
        Err(error) => json!({ "platform": std::env::consts::OS, "available": false, "error": error }),
    }
}

fn run_text(mode: &str, input: Option<&str>) -> Result<String, String> {
    let result = run(mode, input)?;
    result.get("text").and_then(Value::as_str).map(str::to_owned)
        .ok_or_else(|| "NATIVE_PROTOCOL: Native helper returned no text field.".into())
}

fn parse_response(bytes: &[u8], successful: bool) -> Result<Value, String> {
    let value: Value = serde_json::from_slice(bytes)
        .map_err(|_| "NATIVE_PROTOCOL: Native helper returned invalid JSON. Check the platform prerequisites in docs/native-testing.md.".to_string())?;
    if value.get("ok").and_then(Value::as_bool) == Some(true) && successful {
        return Ok(value);
    }
    Err(value.get("error").and_then(Value::as_str)
        .unwrap_or("NATIVE: The native operation failed.").to_owned())
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
fn run(mode: &str, input: Option<&str>) -> Result<Value, String> {
    use std::io::{Read, Write};
    use std::process::Stdio;
    use std::time::{Duration, Instant};

    let mut command = native_command(mode)?;
    command.stdin(if input.is_some() { Stdio::piped() } else { Stdio::null() })
        .stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = command.spawn().map_err(|error| format!("NATIVE_START: Could not start the system helper: {error}"))?;
    // Drain both pipes concurrently so a long OCR result cannot deadlock wait().
    let stdout = child.stdout.take().ok_or("NATIVE: Missing output pipe.")?;
    let stderr = child.stderr.take().ok_or("NATIVE: Missing error pipe.")?;
    let read_pipe = |pipe: Box<dyn Read + Send>| std::thread::spawn(move || {
        let mut bytes = Vec::new();
        pipe.take(4 * 1024 * 1024).read_to_end(&mut bytes).map(|_| bytes)
    });
    let output_thread = read_pipe(Box::new(stdout));
    let error_thread = read_pipe(Box::new(stderr));
    let input_thread = if let Some(text) = input {
        let mut stdin = child.stdin.take().ok_or("NATIVE: Missing input pipe.")?;
        let bytes = text.as_bytes().to_vec();
        Some(std::thread::spawn(move || stdin.write_all(&bytes)))
    } else { None };
    // Helpers cancel their own picker after 120 seconds and OCR after 30 seconds.
    // The longer outer limit gives them time to dispose images and temporary files.
    let limit = if mode == "capture-ocr" { 180 } else { 60 };
    let deadline = Instant::now() + Duration::from_secs(limit);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(30)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("NATIVE_TIMEOUT: The system helper stopped responding. Retry; if this persists, check system permissions and OCR language installation.".into());
            }
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("NATIVE_WAIT: Could not wait for the system helper: {error}"));
            }
        }
    };
    let output = output_thread.join().map_err(|_| "NATIVE: Output reader failed.".to_string())?
        .map_err(|error| format!("NATIVE: Could not read helper output: {error}"))?;
    let errors = error_thread.join().map_err(|_| "NATIVE: Error reader failed.".to_string())?
        .map_err(|error| format!("NATIVE: Could not read helper errors: {error}"))?;
    if let Some(thread) = input_thread {
        let written = thread.join().map_err(|_| "NATIVE_INPUT: Input writer failed.".to_string())?;
        if status.success() {
            written.map_err(|error| format!("NATIVE_INPUT: Could not send clipboard text: {error}"))?;
        }
    }
    if output.is_empty() && !status.success() {
        // PowerShell startup errors can precede our JSON protocol. Do not include
        // script contents or source text in application logs.
        let detail = String::from_utf8_lossy(&errors);
        let detail: String = detail.chars().take(600).collect();
        return Err(format!("NATIVE_START: System helper exited with {status}. {detail}"));
    }
    parse_response(&output, status.success())
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn run(_mode: &str, _input: Option<&str>) -> Result<Value, String> {
    Err("UNSUPPORTED_PLATFORM: Native selection and OCR currently support Windows and macOS.".into())
}

#[cfg(target_os = "macos")]
fn native_command(mode: &str) -> Result<std::process::Command, String> {
    use std::sync::OnceLock;
    static HELPER: OnceLock<Result<std::path::PathBuf, String>> = OnceLock::new();
    let path = HELPER.get_or_init(|| {
        let home = std::env::var_os("HOME").ok_or("NATIVE: HOME is unavailable.")?;
        let folder = std::path::PathBuf::from(home).join("Library/Caches/com.echolingo.app");
        ensure_private_directory(&folder)?;
        let folder = folder.join("native");
        ensure_private_directory(&folder)?;
        materialize(&folder, "echolingo-native-helper",
            include_bytes!(concat!(env!("OUT_DIR"), "/echolingo-native-helper")), true)
    }).as_ref().map_err(Clone::clone)?;
    let mut command = std::process::Command::new(path);
    command.arg(format!("--{mode}"));
    Ok(command)
}

#[cfg(target_os = "windows")]
fn native_command(mode: &str) -> Result<std::process::Command, String> {
    use std::os::windows::process::CommandExt;
    use std::sync::OnceLock;
    static SCRIPT: OnceLock<Result<std::path::PathBuf, String>> = OnceLock::new();
    let path = SCRIPT.get_or_init(|| {
        let local = std::env::var_os("LOCALAPPDATA").ok_or("NATIVE: LOCALAPPDATA is unavailable.")?;
        let folder = std::path::PathBuf::from(local).join("EchoLingo/native");
        ensure_private_directory(&folder)?;
        // Windows PowerShell 5.1 needs a BOM to decode non-ASCII source reliably.
        let mut bytes = vec![0xef, 0xbb, 0xbf];
        bytes.extend_from_slice(include_bytes!("../native/windows.ps1"));
        materialize(&folder, "echolingo-native-helper.ps1", &bytes, false)
    }).as_ref().map_err(Clone::clone)?;
    let system_root = std::env::var_os("SystemRoot").ok_or("NATIVE: SystemRoot is unavailable.")?;
    let powershell = std::path::PathBuf::from(system_root)
        .join("System32/WindowsPowerShell/v1.0/powershell.exe");
    let mut command = std::process::Command::new(powershell);
    command.args(["-NoLogo", "-NoProfile", "-NonInteractive", "-STA", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(path).args(["-Mode", mode]);
    // No command shell, interpolation, user-supplied code, execution-policy change
    // to the machine, or visible console window. Copy text travels through stdin.
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    Ok(command)
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
fn ensure_private_directory(path: &std::path::Path) -> Result<(), String> {
    std::fs::create_dir_all(path).map_err(|error| format!("NATIVE_CACHE: Cannot create helper directory: {error}"))?;
    let metadata = std::fs::symlink_metadata(path).map_err(|error| format!("NATIVE_CACHE: {error}"))?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err("NATIVE_CACHE: The helper cache must be a real directory, not a symlink.".into());
    }
    #[cfg(target_os = "macos")]
    {
        use std::os::unix::fs::{MetadataExt, PermissionsExt};
        unsafe extern "C" { fn geteuid() -> u32; }
        if metadata.uid() != unsafe { geteuid() } {
            return Err("NATIVE_CACHE: The helper cache is not owned by the current user.".into());
        }
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))
            .map_err(|error| format!("NATIVE_CACHE: Cannot secure helper cache: {error}"))?;
    }
    Ok(())
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
fn materialize(folder: &std::path::Path, name: &str, bytes: &[u8], executable: bool) -> Result<std::path::PathBuf, String> {
    use std::io::Write;
    let destination = folder.join(name);
    if let Ok(metadata) = std::fs::symlink_metadata(&destination) {
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err("NATIVE_CACHE: The helper path is not a regular file.".into());
        }
        if std::fs::read(&destination).ok().as_deref() == Some(bytes) {
            #[cfg(target_os = "macos")]
            {
                use std::os::unix::fs::PermissionsExt;
                if executable {
                    std::fs::set_permissions(&destination, std::fs::Permissions::from_mode(0o700))
                        .map_err(|error| format!("NATIVE_CACHE: Cannot secure helper: {error}"))?;
                }
            }
            return Ok(destination);
        }
    }
    let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| "NATIVE_CACHE: System clock is unavailable.".to_string())?.as_nanos();
    let temporary = folder.join(format!(".{name}-{}-{nonce}", std::process::id()));
    let result = (|| -> std::io::Result<()> {
        let mut options = std::fs::OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(target_os = "macos")]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(if executable { 0o700 } else { 0o600 });
        }
        #[cfg(target_os = "windows")]
        let _ = executable;
        let mut file = options.open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        #[cfg(target_os = "windows")]
        if destination.exists() {
            // Windows rename does not replace an existing destination. This
            // directory inherits the current user's LocalAppData ACL.
            std::fs::remove_file(&destination)?;
        }
        std::fs::rename(&temporary, &destination)?;
        Ok(())
    })();
    if let Err(error) = result {
        let _ = std::fs::remove_file(&temporary);
        return Err(format!("NATIVE_CACHE: Cannot extract helper: {error}"));
    }
    Ok(destination)
}

#[cfg(test)]
mod tests {
    use super::parse_response;

    #[test]
    fn native_json_preserves_unicode_and_cancellation() {
        let value = parse_response("{\"ok\":true,\"text\":\"回声译\\nEchoLingo\"}".as_bytes(), true).unwrap();
        assert_eq!(value["text"], "回声译\nEchoLingo");
        assert_eq!(parse_response(br#"{"ok":false,"error":"CANCELLED: Escape"}"#, false).unwrap_err(), "CANCELLED: Escape");
        assert!(parse_response(br#"{"ok":true,"text":"partial"}"#, false).is_err());
        assert!(parse_response(b"not JSON", true).unwrap_err().starts_with("NATIVE_PROTOCOL:"));
    }
}
