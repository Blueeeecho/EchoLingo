#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod bilingual_input;
mod credential_cache;
mod frontend_input_diagnostics;
mod language_detection;
#[cfg(target_os = "macos")]
mod macos_startup;
mod model;
mod mouse_shortcuts;
mod native_tasks;
mod ocr;
mod ocr_native;
mod ocr_outcome;
mod offline_translation;
mod platform;
mod popup_health;
mod service_links;
mod shortcut_bindings;
mod shortcut_control;
mod shortcut_probe;
mod source_delivery;
#[cfg(test)]
mod storage_tests;
#[cfg(any(target_os = "macos", test))]
mod system_translation_gate;
mod translation;
mod translation_health;
mod translation_requests;
mod translation_selection;
mod update_notice;
mod window_layout;
#[cfg(target_os = "windows")]
mod windows_capture_input;
#[cfg(target_os = "windows")]
mod windows_mouse_shortcuts;
#[cfg(windows)]
mod windows_ocr;
#[cfg(any(target_os = "windows", test))]
mod windows_visibility;

use model::*;
use serde::{Deserialize, Serialize};
use shortcut_bindings::Binding;
use std::{
    fs,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tauri::{Emitter, Manager, State};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

struct AppState {
    settings: Mutex<Settings>,
    credentials: credential_cache::CredentialCache<String>,
    credential_reads: Mutex<()>,
    history: Mutex<Vec<HistoryEntry>>,
    pinned: AtomicBool,
    native_tasks: native_tasks::Controller,
    shortcut_gate: Mutex<shortcut_control::ShortcutGate>,
    shortcut_routes: shortcut_control::ShortcutRoutes,
    shortcut_updating: AtomicBool,
    shortcut_maintenance: shortcut_control::ShortcutMaintenance,
    registered_shortcuts: Mutex<Vec<Binding>>,
    shortcut_failures: Mutex<std::collections::BTreeMap<String, String>>,
    translation_busy: tokio::sync::Semaphore,
    translation_requests: translation_requests::TranslationRequests,
    data_dir: PathBuf,
    client: reqwest::Client,
    update_notice: update_notice::Controller,
    offline: offline_translation::OfflineTranslation,
    startup_warnings: Mutex<Vec<String>>,
    outside_thread: Mutex<Option<std::thread::Thread>>,
    pending_settings: Mutex<Option<u64>>,
    source_deliveries: Mutex<source_delivery::SourceDeliveries<serde_json::Value>>,
    pending_shortcut_settings: AtomicBool,
    popup_health: Mutex<popup_health::PopupHealth>,
}

#[cfg(target_os = "macos")]
#[derive(Default)]
struct ApplicationPolicyDiagnostics(Mutex<std::collections::BTreeMap<String, serde_json::Value>>);

// This bounded support record contains this process's native role only, never
// window contents, other apps, permissions, clipboard, settings or credentials.
// It diagnoses a failed launch policy without toggling it at runtime.
fn verify_application_policy(app: &tauri::AppHandle, phase: &'static str) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        let metadata = macos_startup::application_policy_metadata()?;
        let accessory = metadata.ns_application_policy == 1;
        let diagnostics = app.state::<ApplicationPolicyDiagnostics>();
        let mut observations = locked(&diagnostics.0)?;
        observations.insert(
            phase.to_owned(),
            serde_json::json!({ "recordedAtUnixMs": now(), "metadata": metadata }),
        );
        let _ = write_json(
            &app.state::<AppState>()
                .data_dir
                .join("window-policy-diagnostics.json"),
            &*observations,
        );
        if !accessory {
            return Err("WINDOW_POLICY: macOS 菜单栏应用模式未生效，请重新打开 EchoLingo。".into());
        }
    }
    #[cfg(not(target_os = "macos"))]
    let _ = (app, phase);
    Ok(())
}

#[cfg(target_os = "macos")]
async fn verify_capture_application_policy(app: &tauri::AppHandle) -> Result<(), String> {
    let (send, receive) = tokio::sync::oneshot::channel();
    let handle = app.clone();
    app.run_on_main_thread(move || {
        let _ = send.send(verify_application_policy(&handle, "beforeCapture"));
    })
    .map_err(|_| "WINDOW_THREAD: Cannot verify capture startup policy.".to_string())?;
    receive
        .await
        .map_err(|_| "WINDOW_THREAD: Capture startup policy check was interrupted.".to_string())?
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct OpenSettingsEvent {
    presentation_epoch: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    section: Option<&'static str>,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct TranslationProgress {
    request_id: u64,
    presentation_epoch: u64,
    sequence: u64,
    done: bool,
    result: TranslationResult,
}

fn publish_translation_progress(
    app: &tauri::AppHandle,
    state: &AppState,
    request_id: u64,
    sequence: u64,
    done: bool,
    result: TranslationResult,
) {
    let _ = state
        .translation_requests
        .publish(request_id, |presentation| {
            let _ = app.emit(
                "translation-progress",
                TranslationProgress {
                    request_id,
                    presentation_epoch: presentation.epoch,
                    sequence,
                    done,
                    result,
                },
            );
        });
}

fn pending_settings_event(
    pending: Option<u64>,
    presentation: translation_requests::Presentation,
) -> Option<OpenSettingsEvent> {
    pending
        .filter(|epoch| *epoch == presentation.epoch)
        .map(|presentation_epoch| OpenSettingsEvent {
            presentation_epoch,
            section: None,
        })
}

const CONFIGURE_SHORTCUTS_FLAG: &str = "--configure-shortcuts";
fn configure_shortcuts_requested(args: &[String]) -> bool {
    args.iter()
        .skip(1)
        .any(|argument| argument == CONFIGURE_SHORTCUTS_FLAG)
}

#[tauri::command]
fn frontend_input_diagnostics_enabled() -> bool {
    frontend_input_diagnostics::enabled()
}

#[tauri::command]
fn record_frontend_input_diagnostic(
    app: tauri::AppHandle,
    record: frontend_input_diagnostics::Record,
) -> Result<(), String> {
    if !frontend_input_diagnostics::enabled() {
        return Ok(());
    }
    static RECORDS: std::sync::OnceLock<Mutex<Vec<frontend_input_diagnostics::Record>>> =
        std::sync::OnceLock::new();
    let mut records = locked(RECORDS.get_or_init(|| Mutex::new(Vec::new())))?;
    frontend_input_diagnostics::append(&mut records, record);
    write_json(
        &app.state::<AppState>()
            .data_dir
            .join("frontend-input-diagnostics.json"),
        &serde_json::json!({"processId":std::process::id(),"recordedAtUnixMs":now(),"entries":&*records}),
    )
}

const PERMISSION_DIAGNOSTICS_FLAG: &str = "--permission-diagnostics";
#[cfg(any(target_os = "macos", target_os = "windows", test))]
const SELECTION_DIAGNOSTICS_FLAG: &str = "--selection-diagnostics";

#[cfg(any(target_os = "macos", target_os = "windows", test))]
fn selection_diagnostics_requested(args: &[String]) -> bool {
    args.iter()
        .skip(1)
        .any(|argument| argument == SELECTION_DIAGNOSTICS_FLAG)
}

#[cfg(any(target_os = "macos", target_os = "windows", test))]
fn selection_diagnostic_payload(diagnostics: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "diagnostic": "last-selection-attempt",
        "recordedAtUnixMs": now(),
        "appVersion": env!("CARGO_PKG_VERSION"),
        "processId": std::process::id(),
        "executablePath": std::env::current_exe().ok().map(|path| path.display().to_string()),
        "diagnostics": diagnostics,
    })
}

// Explicitly export only the process's bounded native metadata to this fixed
// destination. No source/clipboard content and no new selection operation.
#[cfg(any(target_os = "macos", target_os = "windows"))]
fn write_selection_diagnostics(app: &tauri::AppHandle) -> Result<(), String> {
    static WRITE: Mutex<()> = Mutex::new(());
    let _write = locked(&WRITE)?;
    let diagnostics = platform::selection_diagnostics()?;
    write_json(
        &app.state::<AppState>()
            .data_dir
            .join("selection-diagnostics.json"),
        &selection_diagnostic_payload(diagnostics),
    )
}

// Explicit read-only capture-attempt metadata. Never starts OCR or a helper.
#[cfg(any(target_os = "windows", test))]
fn capture_diagnostics_requested(args: &[String]) -> bool {
    args.iter()
        .skip(1)
        .any(|argument| argument == "--capture-diagnostics")
}

#[cfg(any(target_os = "windows", test))]
fn capture_diagnostic_payload(diagnostics: serde_json::Value) -> serde_json::Value {
    let mut safe = serde_json::Map::new();
    for field in [
        "attemptId",
        "attemptStage",
        "resultOk",
        "displayChangedError",
        "helperResponseReceived",
        "helperElapsedMilliseconds",
        "nativeHostReady",
        "nativeHostStopped",
        "nativeHostFailed",
        "hookRunningAfterStop",
        "inputPlaneRemainingAfterCleanup",
        "hostSessionReserved",
        "hostOwnedButtons",
        "hostSessionClosing",
        "hostEndRequested",
        "cancellationRequested",
        "displayInvalidationReason",
        "currentHostSessionReserved",
        "currentHostOwnedButtons",
        "currentHostSessionClosing",
        "currentHostEndRequested",
    ] {
        if let Some(number) = diagnostics.get(field).and_then(serde_json::Value::as_u64) {
            safe.insert(field.to_owned(), serde_json::json!(number));
        }
    }
    serde_json::json!({
        "diagnostic": "last-capture-attempt", "recordedAtUnixMs": now(),
        "appVersion": env!("CARGO_PKG_VERSION"), "processId": std::process::id(),
        "executablePath": std::env::current_exe().ok().map(|path| path.display().to_string()),
        "diagnostics": safe,
    })
}

#[cfg(target_os = "windows")]
fn write_capture_diagnostics(app: &tauri::AppHandle) -> Result<(), String> {
    static WRITE: Mutex<()> = Mutex::new(());
    let _write = locked(&WRITE)?;
    write_json(
        &app.state::<AppState>()
            .data_dir
            .join("capture-diagnostics.json"),
        &capture_diagnostic_payload(platform::capture_diagnostics()?),
    )
}

fn permission_diagnostics_requested(args: &[String]) -> bool {
    args.iter()
        .skip(1)
        .any(|argument| argument == PERMISSION_DIAGNOSTICS_FLAG)
}

fn permission_diagnostic_payload(permissions: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "diagnostic": "permission-status",
        "recordedAtUnixMs": now(),
        "appVersion": env!("CARGO_PKG_VERSION"),
        "processId": std::process::id(),
        "executablePath": std::env::current_exe().ok().map(|path| path.display().to_string()),
        "permissions": permissions,
    })
}

// An explicitly requested support snapshot only. Fixed destination, no capture,
// clipboard, app settings, history, credentials, prompts or background polling.
fn write_permission_diagnostics(app: &tauri::AppHandle) -> Result<(), String> {
    static WRITE: Mutex<()> = Mutex::new(());
    let _write = locked(&WRITE)?;
    let permissions = platform::permission_status()?;
    write_json(
        &app.state::<AppState>()
            .data_dir
            .join("permission-diagnostics.json"),
        &permission_diagnostic_payload(permissions),
    )
}

fn explicit_launch(app: &tauri::AppHandle, args: &[String]) {
    #[cfg(target_os = "windows")]
    if capture_diagnostics_requested(args) {
        let _ = write_capture_diagnostics(app);
        return;
    }
    if configure_shortcuts_requested(args) {
        request_shortcut_settings(app);
        return;
    }
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    if selection_diagnostics_requested(args) {
        let _ = write_selection_diagnostics(app);
        return;
    }
    if permission_diagnostics_requested(args) {
        let _ = write_permission_diagnostics(app);
    } else {
        request_settings(app);
    }
}
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
fn locked<T>(m: &Mutex<T>) -> Result<std::sync::MutexGuard<'_, T>, String> {
    m.lock()
        .map_err(|_| "内部状态锁异常，请重新启动应用".into())
}
fn write_json(path: &Path, value: &impl Serialize) -> Result<(), String> {
    let tmp = path.with_extension("json.tmp");
    let bytes = serde_json::to_vec_pretty(value).map_err(|_| "无法序列化设置")?;
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&tmp)
        .map_err(|_| "无法写入本地数据目录")?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(|_| "无法设置数据文件权限")?;
    }
    use std::io::Write;
    file.write_all(&bytes).map_err(|_| "无法写入本地数据")?;
    file.sync_all().map_err(|_| "无法同步本地数据")?;
    drop(file);
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::ffi::OsStrExt;
        #[link(name = "kernel32")]
        unsafe extern "system" {
            fn MoveFileExW(existing: *const u16, new: *const u16, flags: u32) -> i32;
        }
        let from: Vec<u16> = tmp.as_os_str().encode_wide().chain(Some(0)).collect();
        let to: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        // Atomic same-volume replace; never remove the old settings/history first.
        if unsafe { MoveFileExW(from.as_ptr(), to.as_ptr(), 0x1 | 0x8) } == 0 {
            return Err("无法原子替换本地数据；原文件保留".into());
        }
        Ok(())
    }
    #[cfg(not(target_os = "windows"))]
    {
        fs::rename(tmp, path).map_err(|_| "无法保存本地数据".to_string())
    }
}
fn secret_entry(id: &str) -> Result<keyring::Entry, String> {
    keyring::Entry::new("io.github.blueeeecho.echolingo", id)
        .map_err(|_| "系统凭据库不可用".to_string())
}
#[derive(Serialize, Deserialize)]
struct CredentialEnvelope {
    scope: String,
    secret: String,
}
fn credential_scope(kind: &str, base_url: &str) -> Result<String, String> {
    Ok(format!(
        "{kind}|{}",
        validate_url(base_url)?.origin().ascii_serialization()
    ))
}
fn translation_secret_id(p: &Provider) -> String {
    if translation::native::is_native(&p.kind) {
        // Colons are forbidden in provider IDs, so new accounts cannot collide
        // with any released translation ID or legacy OCR account spelling.
        format!("translation:{}:{}", p.kind, p.id)
    } else {
        p.id.clone()
    }
}
fn translation_credential_scope(p: &Provider) -> Result<String, String> {
    let scope = credential_scope(&p.kind, &p.base_url)?;
    Ok(if translation::native::is_native(&p.kind) {
        format!("translation|{scope}")
    } else {
        scope
    })
}
fn new_ocr_credential_namespace(kind: &str) -> bool {
    matches!(kind, "youdao" | "google")
}
fn ocr_credential_scope(p: &ocr::OcrProvider) -> Result<String, String> {
    let scope = credential_scope(&p.kind, &p.base_url)?;
    Ok(if new_ocr_credential_namespace(&p.kind) {
        format!("ocr|{scope}")
    } else {
        scope
    })
}
fn decode_credential(stored: &str, scope: &str) -> Result<String, String> {
    let envelope: CredentialEnvelope = serde_json::from_str(stored)
        .map_err(|_| "凭据格式已更新，请在服务设置中重新填写密钥".to_string())?;
    // Editing a service to point at another supplier must not forward the
    // previous supplier's credential, even when both use the same protocol.
    Ok(if envelope.scope == scope {
        envelope.secret
    } else {
        String::new()
    })
}
fn encode_credential(scope: String, secret: String) -> Result<String, String> {
    serde_json::to_string(&CredentialEnvelope { scope, secret })
        .map_err(|_| "无法准备系统凭据".to_string())
}
fn translation_credential_key(p: &Provider) -> Result<credential_cache::CredentialKey, String> {
    Ok(credential_cache::CredentialKey::new(
        translation_secret_id(p),
        translation_credential_scope(p)?,
    ))
}
fn ocr_credential_key(p: &ocr::OcrProvider) -> Result<credential_cache::CredentialKey, String> {
    Ok(credential_cache::CredentialKey::new(
        ocr_secret_id(p),
        ocr_credential_scope(p)?,
    ))
}
fn load_key(
    cache: &credential_cache::CredentialCache<String>,
    p: &Provider,
) -> Result<String, String> {
    if local_translation_provider(&p.kind) {
        return Ok(String::new());
    }
    cached_credential(
        cache,
        &translation_secret_id(p),
        &translation_credential_scope(p)?,
        || {
            match secret_entry(&translation_secret_id(p))?.get_password() {
        Ok(key) => Ok(Some(key)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(_) => Err("API 密钥读取未完成，本次运行不会反复申请。请在设置中点击“测试连接”主动重试，或重新保存密钥".into()),
    }
        },
    )
}

fn load_ocr_key(
    cache: &credential_cache::CredentialCache<String>,
    p: &ocr::OcrProvider,
) -> Result<String, String> {
    cached_credential(cache, &ocr_secret_id(p), &ocr_credential_scope(p)?, || {
        match secret_entry(&ocr_secret_id(p))?.get_password() {
        Ok(key) => Ok(Some(key)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(_) => Err("OCR 凭据读取未完成，本次运行不会反复申请。请在设置中点击“测试连接”主动重试，或重新保存凭据".into()),
    }
    })
}

fn cached_credential(
    cache: &credential_cache::CredentialCache<String>,
    account: &str,
    scope: &str,
    read: impl FnOnce() -> Result<Option<String>, String>,
) -> Result<String, String> {
    cache.get_or_load(
        &credential_cache::CredentialKey::new(account, scope),
        || match read()? {
            Some(stored) => decode_credential(&stored, scope),
            None => Ok(String::new()),
        },
    )
}

fn credential_display_state(
    cache: &credential_cache::CredentialCache<String>,
    key: &credential_cache::CredentialKey,
) -> (bool, &'static str) {
    match cache.peek(key) {
        Ok(Some(Ok(value))) if !value.is_empty() => (true, "ready"),
        Ok(Some(Ok(_))) => (false, "missing"),
        Ok(Some(Err(_))) | Err(_) => (false, "blocked"),
        Ok(None) => (false, "unloaded"),
    }
}

fn retry_unavailable_credential(
    cache: &credential_cache::CredentialCache<String>,
    key: &credential_cache::CredentialKey,
) -> Result<(), String> {
    cache.retry_if(key, |value| {
        value.as_ref().map_or(true, |secret| secret.is_empty())
    })?;
    Ok(())
}

fn serialized_credential_read<T>(
    gate: &Mutex<()>,
    current: impl FnOnce() -> Result<bool, String>,
    read: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    let _gate = locked(gate)?;
    if !current()? {
        return Err(translation_requests::CANCELLED.into());
    }
    read()
}

async fn load_translation_key_async(
    app: tauri::AppHandle,
    provider: Provider,
    request_id: Option<u64>,
) -> Result<String, String> {
    if local_translation_provider(&provider.kind) {
        return Ok(String::new());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<AppState>();
        if let Some(id) = request_id {
            // A queued blocking worker can start after its request was hidden
            // or replaced. Never start a new OS read for that stale ticket.
            if !state.translation_requests.is_current(id)? {
                return Err(translation_requests::CANCELLED.into());
            }
        }
        let key = translation_credential_key(&provider)?;
        if let Some(cached) = state.credentials.peek(&key)? {
            if request_id.is_some() || matches!(&cached, Ok(secret) if !secret.is_empty()) {
                return cached;
            }
        }
        // Only one new account read can ask the OS at a time. Cancellation is
        // checked again after waiting, so it cannot queue more dialogs.
        serialized_credential_read(
            &state.credential_reads,
            || request_id.map_or(Ok(true), |id| state.translation_requests.is_current(id)),
            || {
                if request_id.is_none() {
                    retry_unavailable_credential(&state.credentials, &key)?;
                }
                load_key(&state.credentials, &provider)
            },
        )
    })
    .await
    .map_err(|_| "系统凭据读取任务未完成，请在设置中重试".to_string())?
}

async fn load_ocr_key_async(
    app: tauri::AppHandle,
    provider: ocr::OcrProvider,
    explicit_retry: bool,
    cancelled: Option<Arc<AtomicBool>>,
) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<AppState>();
        let still_current = || {
            Ok(!cancelled
                .as_ref()
                .is_some_and(|flag| flag.load(Ordering::Acquire)))
        };
        if !still_current()? {
            return Err(translation_requests::CANCELLED.into());
        }
        let key = ocr_credential_key(&provider)?;
        if let Some(cached) = state.credentials.peek(&key)? {
            if !explicit_retry || matches!(&cached, Ok(secret) if !secret.is_empty()) {
                return cached;
            }
        }
        serialized_credential_read(&state.credential_reads, still_current, || {
            if explicit_retry {
                retry_unavailable_credential(&state.credentials, &key)?;
            }
            load_ocr_key(&state.credentials, &provider)
        })
    })
    .await
    .map_err(|_| "OCR 凭据读取任务未完成，请在设置中重试".to_string())?
}
fn ocr_secret_id(p: &ocr::OcrProvider) -> String {
    // Credentials for a different protocol must never be sent to a new service
    // just because the user edited an existing service entry.
    if new_ocr_credential_namespace(&p.kind) {
        format!("ocr:{}:{}", p.kind, p.id)
    } else {
        format!("ocr-{}-{}", p.id, p.kind)
    }
}
fn ocr_deletion_accounts(p: &ocr::OcrProvider) -> Vec<String> {
    if new_ocr_credential_namespace(&p.kind) {
        return vec![ocr_secret_id(p)];
    }
    // Preserve released protocol cleanup, without guessing any new namespace
    // or removing a colliding legacy account on behalf of a new OCR service.
    let mut accounts: Vec<_> = ["openai-vision", "http-json", "baidu", "tencent"]
        .iter()
        .map(|kind| format!("ocr-{}-{kind}", p.id))
        .collect();
    accounts.push(format!("ocr-{}", p.id));
    accounts
}
#[tauri::command]
fn set_ocr_api_key(state: State<AppState>, provider_id: String, key: String) -> Result<(), String> {
    let provider = locked(&state.settings)?
        .ocr_providers
        .iter()
        .find(|p| p.id == provider_id)
        .cloned()
        .ok_or("请先保存 OCR 服务配置")?;
    if key.is_empty() || key.len() > 8192 {
        return Err("OCR API 凭据为空或超过长度上限".into());
    }
    if ocr_native::is_native(&provider.kind) {
        ocr_native::validate_credentials(&provider.kind, &key)?;
    } else if key.contains(['\r', '\n']) {
        return Err("OCR API 密钥不能包含换行".into());
    }
    let cache_key = ocr_credential_key(&provider)?;
    let stored = encode_credential(ocr_credential_scope(&provider)?, key.clone())?;
    secret_entry(&ocr_secret_id(&provider))?
        .set_password(&stored)
        .map_err(|_| "无法将 OCR 密钥保存到系统凭据库".to_string())?;
    state.credentials.store(&cache_key, Ok(key))
}
#[tauri::command]
fn delete_ocr_api_key(state: State<AppState>, provider_id: String) -> Result<(), String> {
    let provider = locked(&state.settings)?
        .ocr_providers
        .iter()
        .find(|p| p.id == provider_id)
        .cloned()
        .ok_or("OCR 服务不存在")?;
    for account in ocr_deletion_accounts(&provider) {
        delete_stored_key(&state.credentials, &account)?;
    }
    Ok(())
}
#[tauri::command]
async fn test_ocr_provider(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    provider_id: String,
) -> Result<String, String> {
    let _permit = state
        .translation_busy
        .try_acquire()
        .map_err(|_| "请等待当前请求完成后再测试")?;
    let p = locked(&state.settings)?
        .ocr_providers
        .iter()
        .find(|p| p.id == provider_id)
        .cloned()
        .ok_or("OCR 服务不存在")?;
    let start = std::time::Instant::now();
    let key = load_ocr_key_async(app, p.clone(), true, None).await;
    let text = ocr::recognize(
        &state.client,
        &p,
        key,
        include_str!("../../tests/fixtures/ocr-test.base64").trim(),
    )
    .await?;
    Ok(format!(
        "OCR 连接成功 · {} ms · {}",
        start.elapsed().as_millis(),
        text
    ))
}
#[tauri::command]
fn get_settings(state: State<AppState>) -> Result<serde_json::Value, String> {
    let settings = locked(&state.settings)?;
    let mut value = settings_snapshot(&settings, &state.credentials)?;
    value["appVersion"] = serde_json::json!(env!("CARGO_PKG_VERSION"));
    let registered = locked(&state.registered_shortcuts)?;
    let failures = locked(&state.shortcut_failures)?;
    value["shortcutRegistration"] = serde_json::json!(shortcut_registration_snapshot(
        &settings,
        &registered,
        &failures,
        native_binding_active,
    )?);
    Ok(value)
}

// Both Settings and support diagnostics use the current registration snapshot.
// A recovered or removed binding must not retain its old startup warning.
fn shortcut_registration_snapshot(
    settings: &Settings,
    registered: &[Binding],
    failures: &std::collections::BTreeMap<String, String>,
    native_active: impl Fn(Binding) -> bool,
) -> Result<Vec<serde_json::Value>, String> {
    Ok(parsed_shortcuts(&settings.shortcuts)?.into_iter().map(|(action, binding)| {
        let active = registered.iter().any(|actual| actual.id() == binding.id())
            && native_active(binding);
        serde_json::json!({
            "action": action,
            "active": active,
            "combo": settings.shortcuts.pairs().into_iter()
                .find(|(name, _)| *name == action).map(|(_, combo)| combo).unwrap_or(""),
            "error": shortcut_registration_message(active, failures.get(&action).map(String::as_str)),
        })
    }).collect())
}

fn non_binding_installation_error(error: &str, binding_errors: &str) -> Option<String> {
    if !binding_errors.is_empty() && error == binding_errors {
        return None;
    }
    Some(
        error
            .strip_prefix(&format!("{binding_errors}；"))
            .unwrap_or(error)
            .to_owned(),
    )
}

fn current_shortcut_warnings(registrations: &[serde_json::Value]) -> Vec<String> {
    registrations
        .iter()
        .filter_map(|item| {
            let error = item["error"].as_str()?;
            Some(format!(
                "{}（{}）：{}",
                item["action"].as_str().unwrap_or("快捷键"),
                item["combo"].as_str().unwrap_or(""),
                error
            ))
        })
        .collect()
}

// Startup and Settings refresh must never touch Keychain, even for presence
// checks. An unread entry is unknown, not missing. Only explicit use loads it.
fn settings_snapshot(
    settings: &Settings,
    cache: &credential_cache::CredentialCache<String>,
) -> Result<serde_json::Value, String> {
    let mut value = serde_json::to_value(settings).map_err(|_| "无法读取设置".to_string())?;
    for (provider, item) in settings
        .providers
        .iter()
        .zip(value["providers"].as_array_mut().ok_or("设置格式无效")?)
    {
        let (has_key, status) = if local_translation_provider(&provider.kind) {
            (false, "missing")
        } else {
            credential_display_state(cache, &translation_credential_key(provider)?)
        };
        item["hasKey"] = serde_json::json!(has_key);
        item["credentialState"] = serde_json::json!(status);
    }
    for (provider, item) in settings
        .ocr_providers
        .iter()
        .zip(value["ocrProviders"].as_array_mut().ok_or("设置格式无效")?)
    {
        let (has_key, status) = credential_display_state(cache, &ocr_credential_key(provider)?);
        item["hasKey"] = serde_json::json!(has_key);
        item["credentialState"] = serde_json::json!(status);
    }
    Ok(value)
}

fn parsed_shortcuts(s: &Shortcuts) -> Result<Vec<(String, Binding)>, String> {
    shortcut_bindings::prepared(s)
}

fn dispatch_shortcut(app: &tauri::AppHandle, shortcut: &Shortcut, phase: ShortcutState) {
    dispatch_shortcut_id(app, shortcut.id(), phase, None, false, || true);
}
fn dispatch_shortcut_id(
    app: &tauri::AppHandle,
    id: u32,
    phase: ShortcutState,
    recorded_combo: Option<&str>,
    paired: bool,
    still_current: impl Fn() -> bool,
) {
    let state = app.state::<AppState>();
    let delivery = state.shortcut_gate.lock().ok().and_then(|mut gate| {
        let now = Instant::now();
        if paired && !still_current() {
            return None;
        }
        if state.shortcut_updating.load(Ordering::SeqCst) {
            gate.cancel(now);
        }
        // Observe releases even during updates: dropping them leaves a stale
        // held ID which would swallow the next genuine press after saving.
        let delivery = if paired {
            gate.observe_pair(id, now)
        } else {
            gate.observe(id, phase == ShortcutState::Pressed, now)
        };
        if delivery == shortcut_control::ShortcutDelivery::Ignored {
            return None;
        }
        // Bind the accepted release to this route generation while the
        // recording gate is still held. A later update cannot turn it
        // into a different action after cancelling the old press.
        Some((delivery, state.shortcut_routes.snapshot().ok()?))
    });
    let Some((delivery, routes)) = delivery else {
        return;
    };
    // This lookup never takes the settings/registration locks, which may span
    // disk sync or a synchronous visit to the UI thread. Reject stale maps.
    if state.shortcut_updating.load(Ordering::SeqCst)
        || !state.shortcut_routes.is_current(&routes)
        || !still_current()
    {
        return;
    }
    let route = routes.get(&id).cloned();
    match delivery {
        shortcut_control::ShortcutDelivery::Recorded(lease_id) => {
            let combo = route
                .as_ref()
                .map(|route| route.combo.as_str())
                .or(recorded_combo);
            if let Some(combo) = combo {
                if state
                    .shortcut_gate
                    .lock()
                    .is_ok_and(|mut gate| gate.matches_recording(lease_id, Instant::now()))
                {
                    let _ = app.emit(
                        "shortcut-recorded",
                        serde_json::json!({
                            "leaseId": lease_id, "shortcut": combo,
                            "modifiersDown": shortcut_control::recording_modifiers_down()
                        }),
                    );
                }
            }
        }
        shortcut_control::ShortcutDelivery::Action => {
            if let Some(route) = route {
                start_action(app.clone(), route.action);
            }
        }
        shortcut_control::ShortcutDelivery::Ignored => {}
    }
}

fn native_binding_active(binding: Binding) -> bool {
    #[cfg(target_os = "windows")]
    if let Some(bit) = binding.native_bit() {
        return windows_mouse_shortcuts::active(bit);
    }
    let _ = binding;
    true
}
#[cfg(target_os = "windows")]
fn sync_native_shortcut_context(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        windows_mouse_shortcuts::set_context(
            window.hwnd().map(|native| native.0 as isize).unwrap_or(0),
            !app.state::<window_layout::LayoutState>().is_popup(),
        );
    }
}
#[cfg(target_os = "windows")]
fn start_native_shortcuts(app: tauri::AppHandle) -> Result<(), String> {
    let ids = [
        "Alt+D"
            .parse::<Shortcut>()
            .map_err(|_| "默认快捷键无效")?
            .id(),
        "Alt+S"
            .parse::<Shortcut>()
            .map_err(|_| "默认快捷键无效")?
            .id(),
    ];
    let events = windows_mouse_shortcuts::start(ids)?;
    sync_native_shortcut_context(&app);
    std::thread::Builder::new()
        .name("shortcut-input-events".into())
        .spawn(move || {
            while let Ok(event) = events.recv() {
                if event.id == 0 || !windows_mouse_shortcuts::running() {
                    break;
                }
                if !windows_mouse_shortcuts::current(event) {
                    continue;
                }
                let combo = match event.id {
                    mouse_shortcuts::MOUSE_X1_ID => Some("MouseX1"),
                    mouse_shortcuts::MOUSE_X2_ID => Some("MouseX2"),
                    _ => None,
                };
                // Native hooks already accepted one physical down/up pair. Feed
                // both phases under one gate lock, so invalidation cannot leave
                // a synthetic held ID that swallows the following gesture.
                dispatch_shortcut_id(&app, event.id, ShortcutState::Released, combo, true, || {
                    windows_mouse_shortcuts::current(event)
                });
            }
        })
        .map_err(|error| {
            windows_mouse_shortcuts::stop();
            format!("输入事件队列启动失败：{error}")
        })?;
    Ok(())
}

struct ShortcutUpdateGuard<'a>(&'a AtomicBool);
impl Drop for ShortcutUpdateGuard<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}
struct NativeShortcutRegistry<'a> {
    app: &'a tauri::AppHandle,
    known: std::collections::HashMap<u32, Binding>,
    labels: std::collections::HashMap<u32, String>,
    registered: &'a mut Vec<Binding>,
}
impl shortcut_control::Registry for NativeShortcutRegistry<'_> {
    fn register(&mut self, id: u32) -> Result<(), String> {
        let shortcut = *self.known.get(&id).ok_or("未知快捷键")?;
        #[cfg(target_os = "windows")]
        if shortcut
            .keyboard()
            .is_some_and(|value| value.key == tauri_plugin_global_shortcut::Code::F12)
        {
            return Err(format!(
                "{}：Windows 为调试器保留 F12，请选择其他按键",
                self.labels.get(&id).map(String::as_str).unwrap_or("快捷键")
            ));
        }
        let result = match shortcut {
            Binding::Keyboard(shortcut) => self
                .app
                .global_shortcut()
                .on_shortcut(shortcut, |app, binding, event| {
                    dispatch_shortcut(app, binding, event.state());
                })
                .map_err(|error| format!("系统注册失败：{error}")),
            _ => {
                #[cfg(target_os = "windows")]
                {
                    windows_mouse_shortcuts::register(shortcut.native_bit().ok_or("输入绑定无效")?)
                }
                #[cfg(not(target_os = "windows"))]
                {
                    Err("该输入绑定仅支持 Windows".into())
                }
            }
        };
        result.map_err(|error| {
            format!(
                "{}：{error}",
                self.labels.get(&id).map(String::as_str).unwrap_or("快捷键")
            )
        })?;
        // Native hooks may need recovery even while the binding is already
        // present in our last successful snapshot. Do not duplicate that ID.
        if !self.registered.iter().any(|binding| binding.id() == id) {
            self.registered.push(shortcut);
        }
        Ok(())
    }
    fn unregister(&mut self, id: u32) -> Result<(), String> {
        let shortcut = *self.known.get(&id).ok_or("未知快捷键")?;
        match shortcut {
            Binding::Keyboard(shortcut) => self
                .app
                .global_shortcut()
                .unregister(shortcut)
                .map_err(|error| format!("无法移除快捷键：{error}"))?,
            _ => {
                #[cfg(target_os = "windows")]
                windows_mouse_shortcuts::unregister(shortcut.native_bit().ok_or("输入绑定无效")?)?;
                #[cfg(not(target_os = "windows"))]
                return Err("该输入绑定仅支持 Windows".into());
            }
        }
        self.registered.retain(|binding| binding.id() != id);
        Ok(())
    }
}
fn shortcut_registry<'a>(
    app: &'a tauri::AppHandle,
    registered: &'a mut Vec<Binding>,
    next: &[(String, Binding)],
) -> NativeShortcutRegistry<'a> {
    let known = registered
        .iter()
        .chain(next.iter().map(|(_, binding)| binding))
        .map(|binding| (binding.id(), *binding))
        .collect();
    NativeShortcutRegistry {
        app,
        known,
        labels: next
            .iter()
            .map(|(action, binding)| {
                (
                    binding.id(),
                    format!(
                        "{action}（{}）",
                        match binding {
                            Binding::Mouse(button) => button.name().to_owned(),
                            _ => binding.keyboard().unwrap().to_string(),
                        }
                    ),
                )
            })
            .collect(),
        registered,
    }
}
fn retry_inactive_shortcuts(app: &tauri::AppHandle) -> Result<bool, String> {
    let state = app.state::<AppState>();
    let Some(_maintenance) = state
        .shortcut_maintenance
        .try_enter_idle(&state.shortcut_gate, Instant::now())?
    else {
        return Ok(false);
    };
    // Never retain AppState mutexes while invoking the native registry. The
    // global-shortcut plugin dispatches to the UI thread and waits for a reply;
    // synchronous UI commands must remain free to read these snapshots.
    let settings = locked(&state.settings)?.clone();
    let mut registered = locked(&state.registered_shortcuts)?.clone();
    let mut failures = locked(&state.shortcut_failures)?.clone();
    let ids = registered.iter().map(Binding::id).collect::<Vec<_>>();
    let actions = inactive_retry_actions(&settings, &ids, &failures, |binding| {
        native_binding_active(*binding)
    })?;
    if actions.is_empty() {
        return Ok(false);
    }
    let next = parsed_shortcuts(&settings.shortcuts)?;
    let candidates = next
        .iter()
        .filter(|(action, _)| actions.contains(action))
        .map(|(action, binding)| (action.clone(), binding.id()))
        .collect::<Vec<_>>();
    state.shortcut_updating.store(true, Ordering::SeqCst);
    let _update = ShortcutUpdateGuard(&state.shortcut_updating);
    locked(&state.shortcut_gate)?.cancel(Instant::now());
    #[cfg(target_os = "windows")]
    {
        let _ = windows_mouse_shortcuts::recording(0);
        windows_mouse_shortcuts::invalidate();
    }
    let recovered = shortcut_control::recover_bindings(
        &mut shortcut_registry(app, &mut registered, &next),
        &candidates,
        &mut failures,
    );
    *locked(&state.registered_shortcuts)? = registered.clone();
    *locked(&state.shortcut_failures)? = failures;
    sync_shortcut_routes(&state, &settings.shortcuts, &registered, Ok(()))?;
    Ok(recovered)
}

fn schedule_shortcut_retries(app: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(20)).await;
            let retry_app = app.clone();
            // OS registration is blocking; do not occupy a Tokio executor
            // thread, and await completion so timer attempts cannot pile up.
            let recovered = tauri::async_runtime::spawn_blocking(move || {
                retry_inactive_shortcuts(&retry_app).unwrap_or(false)
            })
            .await
            .unwrap_or(false);
            if recovered {
                let _ = app.emit("shortcut-registration-changed", ());
            }
        }
    });
}

fn install_shortcuts(app: &tauri::AppHandle, s: &Shortcuts) -> Result<(), String> {
    let next = parsed_shortcuts(s)?;
    let state = app.state::<AppState>();
    let mut registered = locked(&state.registered_shortcuts)?.clone();
    let mut registry = shortcut_registry(app, &mut registered, &next);
    let mut failures = locked(&state.shortcut_failures)?.clone();
    failures.clear();
    for (action, binding) in &next {
        if registry
            .registered
            .iter()
            .any(|value| value.id() == binding.id())
        {
            continue;
        }
        if let Err(error) = shortcut_control::Registry::register(&mut registry, binding.id()) {
            failures.insert(action.clone(), error);
        }
    }
    let result = if failures.is_empty() {
        Ok(())
    } else {
        Err(failures.values().cloned().collect::<Vec<_>>().join("；"))
    };
    let result = sync_shortcut_routes(&state, s, registry.registered, result);
    *locked(&state.registered_shortcuts)? = registered;
    *locked(&state.shortcut_failures)? = failures;
    result
}

fn sync_shortcut_routes(
    state: &AppState,
    shortcuts: &Shortcuts,
    registered: &[Binding],
    result: Result<(), String>,
) -> Result<(), String> {
    let sync = (|| {
        let canonical = shortcut_bindings::normalized(shortcuts)?;
        let parsed = parsed_shortcuts(&canonical)?;
        let desired = parsed
            .into_iter()
            .map(|(action, binding)| {
                let combo = canonical
                    .pairs()
                    .into_iter()
                    .find(|(name, _)| *name == action)
                    .map(|(_, combo)| combo)
                    .unwrap_or("");
                (
                    binding.id(),
                    shortcut_control::ShortcutRoute {
                        action,
                        combo: combo.to_owned(),
                    },
                )
            })
            .collect::<Vec<_>>();
        state
            .shortcut_routes
            .publish_registered(desired, registered.iter().map(Binding::id))
    })();
    match sync {
        Ok(()) => result,
        Err(error) => Err(match result {
            Ok(()) => error,
            Err(previous) => format!("{previous}；{error}"),
        }),
    }
}

fn cancel_shortcut_recording(app: &tauri::AppHandle) {
    #[cfg(target_os = "windows")]
    let _ = windows_mouse_shortcuts::recording(0);
    if let Ok(mut gate) = app.state::<AppState>().shortcut_gate.lock() {
        if gate.is_recording(Instant::now()) {
            gate.cancel(Instant::now());
        }
    }
}
#[tauri::command]
fn set_shortcut_recording(
    window: tauri::WebviewWindow,
    state: State<AppState>,
    active: bool,
    lease_id: Option<u64>,
) -> Result<u64, String> {
    if window.label() != "main" {
        return Err("快捷键录制只能在设置窗口使用".into());
    }
    if active {
        if !window.is_focused().unwrap_or(false)
            || window.state::<window_layout::LayoutState>().is_popup()
        {
            return Err("请在前台设置窗口中录制快捷键".into());
        }
        let id = state
            .shortcut_maintenance
            .begin_recording(&state.shortcut_gate, Instant::now())?;
        #[cfg(target_os = "windows")]
        {
            sync_native_shortcut_context(&window.app_handle());
            if let Err(error) = windows_mouse_shortcuts::recording(id) {
                locked(&state.shortcut_gate)?.end(id, Instant::now());
                return Err(error);
            }
        }
        Ok(id)
    } else {
        let id = lease_id.ok_or("录制编号缺失")?;
        let ended = locked(&state.shortcut_gate)?.end(id, Instant::now());
        #[cfg(target_os = "windows")]
        if ended {
            windows_mouse_shortcuts::end_recording(id);
        }
        #[cfg(not(target_os = "windows"))]
        let _ = ended;
        Ok(id)
    }
}
fn shortcut_failure_can_retry(error: &str) -> bool {
    !error.contains("保留") && !error.contains("仅支持") && !error.contains("无效")
}

fn friendly_shortcut_error(error: &str) -> String {
    let text = error.trim();
    if text.contains("保留") || text.contains("仅支持") || text.contains("无效") {
        return text.to_owned();
    }
    if text.contains("AlreadyRegistered")
        || text.contains("HotKey")
        || text.contains("1409")
        || text.contains("占用")
    {
        return "系统报告该组合键已被注册。可更换快捷键，或释放占用后等待自动重试。".into();
    }
    if text.contains("监听") {
        return "系统键盘监听没有就绪。请重启应用，或改用其他快捷键。".into();
    }
    text.to_owned()
}

fn shortcut_registration_message(active: bool, stored: Option<&str>) -> Option<String> {
    if active {
        return None;
    }
    Some(match stored {
        Some(error) => friendly_shortcut_error(error),
        None => "快捷键没有注册成功，可能被其他程序占用。".into(),
    })
}

fn inactive_retry_actions(
    settings: &Settings,
    registered_ids: &[u32],
    failures: &std::collections::BTreeMap<String, String>,
    native_active: impl Fn(&Binding) -> bool,
) -> Result<Vec<String>, String> {
    let mut actions = Vec::new();
    for (action, binding) in parsed_shortcuts(&settings.shortcuts)? {
        let active = registered_ids.contains(&binding.id()) && native_active(&binding);
        if active {
            continue;
        }
        if failures
            .get(&action)
            .is_some_and(|error| !shortcut_failure_can_retry(error))
        {
            continue;
        }
        actions.push(action);
    }
    Ok(actions)
}

#[tauri::command]
fn save_settings(
    app: tauri::AppHandle,
    state: State<AppState>,
    mut settings: Settings,
    retry_shortcut_actions: Option<Vec<String>>,
) -> Result<(), String> {
    let _maintenance = state
        .shortcut_maintenance
        .try_enter()
        .ok_or("快捷键正在更新，请稍后再保存。")?;
    validate_settings(&settings)?;
    settings.shortcuts = shortcut_bindings::normalized(&settings.shortcuts)?;
    let next = parsed_shortcuts(&settings.shortcuts)?;
    for p in &mut settings.providers {
        p.has_key = false;
    }
    for p in &mut settings.ocr_providers {
        p.has_key = false;
    }
    let mut current = locked(&state.settings)?.clone();
    let previous = current.clone();
    let mut registered = locked(&state.registered_shortcuts)?.clone();
    let old_ids = registered.iter().map(Binding::id).collect::<Vec<_>>();
    let previous_bindings = parsed_shortcuts(&previous.shortcuts)?;
    let previous_ids = previous_bindings
        .iter()
        .map(|(action, binding)| (action.clone(), binding.id()))
        .collect::<Vec<_>>();
    let next_ids = next
        .iter()
        .map(|(action, binding)| (action.clone(), binding.id()))
        .collect::<Vec<_>>();
    let retry_actions = retry_shortcut_actions.unwrap_or_default();
    if retry_actions.iter().any(|action| {
        !matches!(
            action.as_str(),
            "selection" | "silentOcr" | "capture" | "ocr" | "input"
        )
    }) {
        return Err("未知快捷键操作".into());
    }
    let new_ids =
        shortcut_control::registration_targets(&old_ids, &previous_ids, &next_ids, &retry_actions);
    let bindings_changed = previous.shortcuts.pairs() != settings.shortcuts.pairs();
    // A theme/provider/history save leaves the registrations and recording
    // lease alone. Binding changes suppress in-flight press/release pairs.
    let _update = (bindings_changed || !retry_actions.is_empty()).then(|| {
        state.shortcut_updating.store(true, Ordering::SeqCst);
        ShortcutUpdateGuard(&state.shortcut_updating)
    });
    if bindings_changed || !retry_actions.is_empty() {
        locked(&state.shortcut_gate)?.cancel(Instant::now());
        #[cfg(target_os = "windows")]
        {
            let _ = windows_mouse_shortcuts::recording(0);
            windows_mouse_shortcuts::invalidate();
        }
    }
    let mut registry = shortcut_registry(&app, &mut registered, &next);
    let mut result = shortcut_control::replace_bindings(&mut registry, &old_ids, &new_ids, || {
        // Only persistence owns settings/history locks, after all native calls.
        // Maintenance serializes settings writers; translation completion still
        // reads privacy and appends history under the same lock order.
        let mut latest = locked(&state.settings)?;
        let mut history = locked(&state.history)?;
        let result =
            persist_settings_and_history(&state.data_dir, &mut latest, &mut history, settings);
        current = latest.clone();
        result
    });
    // The existing storage helper can report a double disk-write failure after
    // committing settings. Keep native bindings aligned with that actual state
    // and surface the partial-save error rather than claiming a rollback.
    if result.is_err() && current.shortcuts.pairs() != previous.shortcuts.pairs() {
        let actual = parsed_shortcuts(&current.shortcuts)?;
        let actual_ids = actual
            .iter()
            .map(|(_, binding)| binding.id())
            .collect::<Vec<_>>();
        let ids = registry
            .registered
            .iter()
            .map(Binding::id)
            .collect::<Vec<_>>();
        for (_, binding) in actual {
            registry.known.insert(binding.id(), binding);
        }
        if let Err(recovery) =
            shortcut_control::replace_bindings(&mut registry, &ids, &actual_ids, || Ok(()))
        {
            result = Err(format!(
                "{}；已保存设置的快捷键恢复失败：{recovery}",
                result.unwrap_err()
            ));
        }
    }
    result = sync_shortcut_routes(&state, &current.shortcuts, registry.registered, result);
    if let Ok(mut failures) = state.shortcut_failures.lock() {
        let current_bindings = parsed_shortcuts(&current.shortcuts)?;
        failures.retain(|action, _| {
            current_bindings.iter().any(|(name, binding)| {
                name == action
                    && !registry
                        .registered
                        .iter()
                        .any(|actual| actual.id() == binding.id())
            })
        });
    }
    for account in changed_credential_accounts(&previous, &current) {
        if let Err(error) = state.credentials.invalidate_account(&account) {
            result = Err(match result {
                Ok(()) => error,
                Err(previous) => format!("{previous}；{error}"),
            });
        }
    }
    *locked(&state.registered_shortcuts)? = registered;
    result
}

fn changed_credential_accounts(old: &Settings, next: &Settings) -> Vec<String> {
    let mut changed = std::collections::HashSet::new();
    for provider in &old.providers {
        if local_translation_provider(&provider.kind) {
            continue;
        }
        if !next.providers.iter().any(|candidate| {
            candidate.id == provider.id
                && translation_credential_scope(candidate).ok()
                    == translation_credential_scope(provider).ok()
        }) {
            changed.insert(translation_secret_id(provider));
        }
    }
    for provider in &old.ocr_providers {
        if !next.ocr_providers.iter().any(|candidate| {
            candidate.id == provider.id
                && ocr_credential_scope(candidate).ok() == ocr_credential_scope(provider).ok()
        }) {
            changed.insert(ocr_secret_id(provider));
        }
    }
    changed.into_iter().collect()
}

// The caller holds settings before history, matching translation completion.
// Applying a smaller history limit must be visible and durable immediately,
// without requiring another successful translation or an app restart.
fn persist_settings_and_history(
    data_dir: &Path,
    current: &mut Settings,
    history: &mut Vec<HistoryEntry>,
    settings: Settings,
) -> Result<(), String> {
    let mut updated = history.clone();
    trim_history(&mut updated, settings.max_history);
    let settings_path = data_dir.join("settings.json");
    write_json(&settings_path, &settings)?;
    if updated.len() != history.len() {
        if let Err(error) = write_json(&data_dir.join("history.json"), &updated) {
            if write_json(&settings_path, current).is_err() {
                // Both writes failed independently. Keep memory consistent with
                // the settings that did reach disk and enforce the new limit;
                // startup will retry trimming the older history file.
                *current = settings;
                *history = updated;
                return Err("设置已保存，但历史文件更新失败；本次运行已应用条数限制，请检查本地数据目录后重试".into());
            }
            return Err(format!("历史记录未能更新，设置没有更改：{error}"));
        }
        *history = updated;
    }
    *current = settings;
    Ok(())
}
#[tauri::command]
fn set_api_key(state: State<AppState>, provider_id: String, key: String) -> Result<(), String> {
    let provider = locked(&state.settings)?
        .providers
        .iter()
        .find(|p| p.id == provider_id)
        .cloned()
        .ok_or("请先保存服务配置，再保存密钥")?;
    if local_translation_provider(&provider.kind) {
        return Err("本机翻译无需 API 密钥".into());
    }
    if key.is_empty() || key.len() > 8192 || key.contains(['\r', '\n']) {
        return Err("API 密钥为空、过长或包含换行".into());
    }
    if translation::native::is_native(&provider.kind) {
        translation::native::validate_credentials(&provider.kind, &key)?;
    }
    let cache_key = translation_credential_key(&provider)?;
    let stored = encode_credential(translation_credential_scope(&provider)?, key.clone())?;
    secret_entry(&translation_secret_id(&provider))?
        .set_password(&stored)
        .map_err(|_| "无法保存到系统凭据库；密钥没有保存到文件".to_string())?;
    state.credentials.store(&cache_key, Ok(key))
}
#[tauri::command]
fn delete_api_key(state: State<AppState>, provider_id: String) -> Result<(), String> {
    let provider = locked(&state.settings)?
        .providers
        .iter()
        .find(|p| p.id == provider_id)
        .cloned()
        .ok_or("翻译服务不存在")?;
    if local_translation_provider(&provider.kind) {
        return Err("本机翻译不使用 API 密钥".into());
    }
    delete_stored_key(&state.credentials, &translation_secret_id(&provider))
}
fn delete_stored_key(
    cache: &credential_cache::CredentialCache<String>,
    account: &str,
) -> Result<(), String> {
    match secret_entry(account)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(_) => Err("无法删除凭据库中的密钥".to_string()),
    }?;
    cache.delete_account(account, String::new())
}
#[tauri::command]
fn begin_translation(state: State<AppState>, presentation_epoch: u64) -> Result<u64, String> {
    state.translation_requests.begin(presentation_epoch)
}
#[tauri::command]
fn get_translation_presentation(
    state: State<AppState>,
) -> Result<translation_requests::Presentation, String> {
    state.translation_requests.presentation()
}
#[tauri::command]
fn cancel_translation(state: State<AppState>, request_id: u64) -> Result<(), String> {
    state.translation_requests.cancel(Some(request_id))?;
    Ok(())
}
fn announce_presentation(app: &tauri::AppHandle, presentation: translation_requests::Presentation) {
    #[cfg(target_os = "macos")]
    window_layout::cancel_stale_native_layout(app);
    if let Ok(mut deliveries) = app.state::<AppState>().source_deliveries.lock() {
        deliveries.advance(presentation.epoch);
    }
    #[cfg(target_os = "windows")]
    windows_visibility::disarm();
    let _ = app.emit("translation-presentation", presentation);
}
fn cancel_active_translation(app: &tauri::AppHandle) -> Option<translation_requests::Presentation> {
    if let Ok(presentation) = app.state::<AppState>().translation_requests.presentation() {
        record_popup_health(app, presentation.epoch, "presentationCancelled", None);
    }
    app.state::<AppState>().native_tasks.cancel();
    let presentation = app
        .state::<AppState>()
        .translation_requests
        .suspend()
        .ok()?;
    announce_presentation(app, presentation);
    Some(presentation)
}
#[tauri::command]
async fn translate(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    request_id: u64,
    text: String,
    source_language: String,
    target_language: String,
    provider_id: Option<String>,
) -> Result<Vec<TranslationResult>, String> {
    let mut trace = translation_health::RequestTrace::start(request_id);
    let outcome = async {
        if text.trim().is_empty() {
            return Err("请输入需要翻译的文本".into());
        }
        if text.chars().count() > 20000 {
            return Err("单次最多翻译 20,000 字符".into());
        }
        if source_language.len() > 40 || target_language.len() > 40 || target_language.is_empty() {
            return Err("语言参数无效".into());
        }
        let input_plan = bilingual_input::resolve(&text, &source_language, &target_language)?;
        let _permit = if input_plan == Some(bilingual_input::Plan::Preserve) {
            None
        } else {
            Some(
                state
                    .translation_busy
                    .try_acquire()
                    .map_err(|_| "翻译任务较多，请等待当前请求完成")?,
            )
        };
        let settings = locked(&state.settings)?.clone();
        let providers =
            translation_selection::request_providers(&settings.providers, provider_id.as_deref())?;
        let (resolved_source, resolved_target, results) = state
            .translation_requests
            .execute(request_id, async {
                let detected =
                    bilingual_input::detect_if_needed(input_plan, &source_language, || {
                        platform::detect_language(&text)
                    })
                    .await;
                let (resolved_source, resolved_target, source_resolution) = match input_plan {
                    Some(bilingual_input::Plan::Preserve) => (
                        "auto".to_string(),
                        "auto".to_string(),
                        translation_health::SourceResolution::PreservedStructure,
                    ),
                    Some(bilingual_input::Plan::Translate { source, target }) => (
                        source.to_string(),
                        target.to_string(),
                        translation_health::SourceResolution::BilingualMode,
                    ),
                    None => {
                        let (source, target) = language_detection::resolve_translation_languages(
                            &text,
                            &source_language,
                            &target_language,
                            detected.as_deref(),
                        )?;
                        (
                            source,
                            target,
                            if source_language != "auto" {
                                translation_health::SourceResolution::Explicit
                            } else {
                                translation_health::SourceResolution::StandardDetection
                            },
                        )
                    }
                };
                trace.languages(&resolved_source, &resolved_target);
                trace.source_resolution(source_resolution);
                let jobs = providers.iter().enumerate().map(|(provider_index, p)| {
                    let app = &app;
                    let state = &state;
                    let text = &text;
                    let resolved_source = &resolved_source;
                    let resolved_target = &resolved_target;
                    async move {
                        let mut provider_trace = translation_health::ProviderTrace::start(
                            request_id,
                            provider_index,
                            &p.kind,
                        );
                        let sequence = std::sync::atomic::AtomicU64::new(0);
                        let started = std::time::Instant::now();
                        let result = bilingual_input::dispatch(
                            input_plan,
                            text,
                            |raw| translation::preserved_result(p, raw),
                            || async {
                                let key = load_translation_key_async(
                                    app.clone(),
                                    p.clone(),
                                    Some(request_id),
                                )
                                .await;
                                if p.kind == "offline" {
                                    state
                                        .offline
                                        .translate_result(p, text, resolved_source, resolved_target)
                                        .await
                                } else {
                                    translation::translate_one_streaming(
                                        &state.client,
                                        p,
                                        key,
                                        &text,
                                        &resolved_source,
                                        &resolved_target,
                                        |partial| {
                                            publish_translation_progress(
                                                &app,
                                                &state,
                                                request_id,
                                                sequence.fetch_add(1, Ordering::SeqCst) + 1,
                                                false,
                                                TranslationResult {
                                                    preserved: false,
                                                    provider_id: p.id.clone(),
                                                    provider_name: p.name.clone(),
                                                    text: partial.to_owned(),
                                                    error: None,
                                                    elapsed_ms: started.elapsed().as_millis()
                                                        as u64,
                                                    resolved_languages: None,
                                                },
                                            );
                                        },
                                    )
                                    .await
                                }
                            },
                        )
                        .await;
                        if input_plan == Some(bilingual_input::Plan::Preserve) {
                            provider_trace.preserved();
                        } else {
                            provider_trace.finish(result.error.as_deref());
                        }
                        publish_translation_progress(
                            &app,
                            &state,
                            request_id,
                            sequence.fetch_add(1, Ordering::SeqCst) + 1,
                            true,
                            result.clone(),
                        );
                        result
                    }
                });
                let results = futures_util::future::join_all(jobs).await;
                Ok::<_, String>((resolved_source, resolved_target, results))
            })
            .await??;
        finish_translation(
            &state,
            request_id,
            text,
            resolved_source,
            resolved_target,
            &results,
        )?;
        Ok(results)
    }
    .await;
    trace.finish(outcome.as_ref().err().map(String::as_str));
    outcome
}
fn finish_translation(
    state: &AppState,
    request_id: u64,
    text: String,
    source_language: String,
    target_language: String,
    results: &[TranslationResult],
) -> Result<(), String> {
    state.translation_requests.finish(request_id, || {
        // Read the privacy preference at completion, not from the request snapshot.
        // Holding this lock through persistence orders this against disabling history.
        let current = locked(&state.settings)?;
        if current.save_history
            && current.max_history > 0
            && results.iter().any(|r| r.error.is_none())
        {
            let mut history = locked(&state.history)?;
            let created_at = now();
            let entry = HistoryEntry {
                id: format!(
                    "{created_at}-{}",
                    SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_nanos()
                ),
                text,
                source_language,
                target_language,
                // Setup guidance belongs only to this result's live request.
                results: results
                    .iter()
                    .cloned()
                    .map(|mut result| {
                        result.resolved_languages = None;
                        result
                    })
                    .collect(),
                created_at,
                favorite: false,
            };
            let mut updated = history.clone();
            updated.insert(0, entry);
            trim_history(&mut updated, current.max_history);
            if write_json(&state.data_dir.join("history.json"), &updated).is_ok() {
                *history = updated;
            } else {
                locked(&state.startup_warnings)?
                    .push("最近一次翻译的历史记录保存失败，译文仍正常返回".into());
            }
        }
        Ok(())
    })
}
const MAX_HISTORY_BYTES: usize = 8 * 1024 * 1024;
fn trim_history(history: &mut Vec<HistoryEntry>, max: usize) {
    let mut sizes: Vec<usize> = history
        .iter()
        .map(|h| {
            serde_json::to_vec(h)
                .map(|v| v.len() + 1)
                .unwrap_or(MAX_HISTORY_BYTES + 1)
        })
        .collect();
    // Discard entries that cannot fit alone before evicting healthy records.
    for index in (0..sizes.len()).rev() {
        if sizes[index].saturating_add(1) > MAX_HISTORY_BYTES {
            sizes.remove(index);
            history.remove(index);
        }
    }
    let mut total: usize = sizes
        .iter()
        .sum::<usize>()
        .saturating_add(if history.is_empty() { 2 } else { 1 });
    while history.len() > max || total > MAX_HISTORY_BYTES {
        let Some(index) = history
            .iter()
            .rposition(|h| !h.favorite)
            .or_else(|| history.len().checked_sub(1))
        else {
            break;
        };
        total = total.saturating_sub(sizes.remove(index));
        history.remove(index);
        if history.is_empty() {
            total = 2;
        }
    }
}
#[tauri::command]
async fn test_provider(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    provider_id: String,
) -> Result<String, String> {
    let _permit = state
        .translation_busy
        .try_acquire()
        .map_err(|_| "请等待当前请求完成后再测试")?;
    let p = locked(&state.settings)?
        .providers
        .iter()
        .find(|p| p.id == provider_id)
        .cloned()
        .ok_or("服务不存在")?;
    let key = load_translation_key_async(app, p.clone(), None).await;
    let r = if p.kind == "offline" {
        state
            .offline
            .translate_result(&p, "Hello", "en", "zh-Hans")
            .await
    } else {
        translation::translate_one(&state.client, &p, key, "Hello", "en", "zh-Hans").await
    };
    if let Some(e) = r.error {
        Err(e)
    } else {
        Ok(format!("连接成功 · {} ms · {}", r.elapsed_ms, r.text))
    }
}
#[tauri::command]
fn get_history(state: State<AppState>) -> Result<Vec<HistoryEntry>, String> {
    Ok(locked(&state.history)?.clone())
}
#[tauri::command]
fn toggle_favorite(state: State<AppState>, id: String) -> Result<(), String> {
    let mut h = locked(&state.history)?;
    let mut updated = h.clone();
    let item = updated
        .iter_mut()
        .find(|v| v.id == id)
        .ok_or("历史记录不存在")?;
    item.favorite = !item.favorite;
    write_json(&state.data_dir.join("history.json"), &updated)?;
    *h = updated;
    Ok(())
}
#[tauri::command]
fn delete_history(
    app: tauri::AppHandle,
    state: State<AppState>,
    id: Option<String>,
) -> Result<(), String> {
    // Clearing history must not be undone by an older in-flight request.
    if id.is_none() {
        announce_presentation(&app, state.translation_requests.invalidate()?);
    }
    let mut h = locked(&state.history)?;
    let mut updated = h.clone();
    if let Some(id) = id {
        updated.retain(|v| v.id != id)
    } else {
        updated.clear()
    };
    write_json(&state.data_dir.join("history.json"), &updated)?;
    *h = updated;
    Ok(())
}

fn prepare_input_presentation(
    requests: &translation_requests::TranslationRequests,
) -> Result<translation_requests::Presentation, String> {
    // Explicit input actions need a new identity even if already visible. A
    // delayed focus event from an earlier action must not reuse this epoch.
    let prepared = requests.invalidate()?;
    requests.resume(Some(prepared.epoch))
}

fn show(app: &tauri::AppHandle) -> Result<translation_requests::Presentation, String> {
    app.state::<AppState>().native_tasks.cancel();
    let presentation = prepare_input_presentation(&app.state::<AppState>().translation_requests)?;
    announce_presentation(app, presentation);
    let handle = app.clone();
    app.run_on_main_thread(move || {
        if handle
            .state::<AppState>()
            .translation_requests
            .presentation()
            .ok()
            != Some(presentation)
        {
            return;
        }
        if let Some(window) = handle.get_webview_window("main") {
            if let Err(error) = verify_application_policy(&handle, "beforeInput") {
                let _ = handle.emit("action-error", error);
                return;
            }
            if let Err(error) = platform::ensure_popup_behavior(&window) {
                let _ = handle.emit("action-error", error);
                return;
            }
            if window.show().is_err() || window.unminimize().is_err() || window.set_focus().is_err()
            {
                let _ = handle.emit("action-error", "无法显示输入窗口");
                return;
            }
            // HWND focus does not deliver KEYEVENTF_UNICODE into the editor.
            // WebView2 only accepts that input after controller MoveFocus.
            let webview: &tauri::Webview = window.as_ref();
            if webview.set_focus().is_err() {
                let _ = handle.emit("action-error", "无法显示输入窗口");
                return;
            }
            // Only a still-current native input presentation grants DOM focus.
            // The frontend verifies this exact epoch again after IPC delivery.
            if handle
                .state::<AppState>()
                .translation_requests
                .presentation()
                .ok()
                == Some(presentation)
            {
                let _ = handle.emit("focus-input", presentation);
            }
            wake_outside_watcher(&handle);
        }
    })
    .map_err(|_| "无法显示输入窗口")?;
    Ok(presentation)
}

// Only explicit tray/menu/reopen actions reach this path. The frontend prepares
// the management DOM and geometry before show_management activates the window.
fn request_settings(app: &tauri::AppHandle) {
    request_settings_section(app, false);
}
fn request_shortcut_settings(app: &tauri::AppHandle) {
    request_settings_section(app, true);
}
fn request_settings_section(app: &tauri::AppHandle, shortcuts: bool) {
    let Some(presentation) = cancel_active_translation(app) else {
        return;
    };
    let state = app.state::<AppState>();
    let Ok(mut pending) = state.pending_settings.lock() else {
        return;
    };
    *pending = Some(presentation.epoch);
    state
        .pending_shortcut_settings
        .store(shortcuts, Ordering::SeqCst);
    drop(pending);
    if let Some(window) = app.get_webview_window("main") {
        let _ = platform::hide_webview_window(&window);
    }
    let _ = app.emit(
        "open-settings",
        OpenSettingsEvent {
            presentation_epoch: presentation.epoch,
            section: shortcuts.then_some("shortcuts"),
        },
    );
}

#[tauri::command]
fn get_pending_settings(state: State<AppState>) -> Result<Option<OpenSettingsEvent>, String> {
    let pending = *locked(&state.pending_settings)?;
    Ok(
        pending_settings_event(pending, state.translation_requests.presentation()?).map(
            |mut event| {
                event.section = state
                    .pending_shortcut_settings
                    .load(Ordering::SeqCst)
                    .then_some("shortcuts");
                event
            },
        ),
    )
}

fn prepare_management_presentation(
    requests: &translation_requests::TranslationRequests,
    presentation_epoch: u64,
    management_layout: bool,
) -> Result<translation_requests::Presentation, String> {
    if !management_layout {
        return Err("MANAGEMENT_NOT_READY: 请先准备设置窗口".into());
    }
    requests.resume(Some(presentation_epoch))
}

#[tauri::command]
fn show_management(
    app: tauri::AppHandle,
    presentation_epoch: u64,
) -> Result<translation_requests::Presentation, String> {
    let state = app.state::<AppState>();
    let presentation = prepare_management_presentation(
        &state.translation_requests,
        presentation_epoch,
        !app.state::<window_layout::LayoutState>().is_popup(),
    )?;
    {
        let mut pending = locked(&state.pending_settings)?;
        if *pending == Some(presentation_epoch) {
            *pending = None;
            state
                .pending_shortcut_settings
                .store(false, Ordering::SeqCst);
        }
    }
    announce_presentation(&app, presentation);
    let handle = app.clone();
    app.run_on_main_thread(move || {
        if handle
            .state::<AppState>()
            .translation_requests
            .presentation()
            .ok()
            != Some(presentation)
            || handle.state::<window_layout::LayoutState>().is_popup()
        {
            return;
        }
        if let Some(window) = handle.get_webview_window("main") {
            let _ = verify_application_policy(&handle, "beforeManagement");
            let _ = window.show();
            let _ = window.unminimize();
            let _ = window.set_focus();
            wake_outside_watcher(&handle);
        }
    })
    .map_err(|_| "无法显示设置窗口")?;
    Ok(presentation)
}
fn wake_outside_watcher(app: &tauri::AppHandle) {
    #[cfg(target_os = "windows")]
    sync_native_shortcut_context(app);
    #[cfg(target_os = "windows")]
    {
        let state = app.state::<AppState>();
        if let (Ok(presentation), Some(window)) = (
            state.translation_requests.presentation(),
            app.get_webview_window("main"),
        ) {
            if presentation.presented
                && window.is_visible().unwrap_or(false)
                && app.state::<window_layout::LayoutState>().is_popup()
                && !state.pinned.load(Ordering::SeqCst)
            {
                windows_visibility::arm(
                    presentation.epoch,
                    platform::popup_has_native_foreground(&window),
                    window.hwnd().map(|native| native.0 as isize).unwrap_or(0),
                );
                return;
            }
        }
        windows_visibility::disarm();
    }
    #[cfg(not(target_os = "windows"))]
    if let Ok(thread) = app.state::<AppState>().outside_thread.lock() {
        if let Some(thread) = thread.as_ref() {
            thread.unpark();
        }
    }
}
fn record_popup_health(
    app: &tauri::AppHandle,
    epoch: u64,
    phase: &'static str,
    visible: Option<bool>,
) {
    let state = app.state::<AppState>();
    if let Ok(mut health) = state.popup_health.lock() {
        health.record(epoch, phase, now(), visible);
    };
}

async fn show_prepared_popup(
    app: &tauri::AppHandle,
    expected_epoch: u64,
    focus_input: bool,
    reuse_visible_popup: bool,
) -> Result<translation_requests::Presentation, String> {
    record_popup_health(app, expected_epoch, "showQueued", None);
    let (reply, result) = tokio::sync::oneshot::channel();
    let handle = app.clone();
    app.run_on_main_thread(move || {
        // Resume only after reaching the UI thread. A queued show cannot claim
        // success or revive a task hidden/superseded while it was waiting.
        let operation = (|| {
            let state = handle.state::<AppState>();
            if state.translation_requests.presentation()?.epoch != expected_epoch
                || !handle.state::<window_layout::LayoutState>().is_popup()
            {
                return Err(translation_requests::CANCELLED.to_owned());
            }
            let window = handle.get_webview_window("main").ok_or("窗口不存在")?;
            record_popup_health(&handle, expected_epoch, "showStarted", None);
            verify_application_policy(&handle, "beforePopup")?;
            platform::ensure_popup_behavior(&window)?;
            let presentation = state.translation_requests.resume(Some(expected_epoch))?;
            announce_presentation(&handle, presentation);
            if focus_input {
                window.show().map_err(|_| "WINDOW_SHOW: 无法显示翻译窗口")?;
                window
                    .unminimize()
                    .map_err(|_| "WINDOW_SHOW: 无法恢复翻译窗口")?;
                window
                    .set_focus()
                    .map_err(|_| "WINDOW_FOCUS: 无法聚焦翻译窗口")?;
                let webview: &tauri::Webview = window.as_ref();
                webview
                    .set_focus()
                    .map_err(|_| "WINDOW_FOCUS: 无法聚焦输入框")?;
            } else if popup_needs_native_show(
                reuse_visible_popup,
                window.is_visible().unwrap_or(false),
                handle.state::<window_layout::LayoutState>().is_popup(),
                state.pinned.load(Ordering::SeqCst),
            ) {
                platform::show_without_activation(&window)?;
            }
            if state.translation_requests.presentation()? != presentation {
                return Err(translation_requests::CANCELLED.to_owned());
            }
            // This observation is separate from API success: window managers
            // may still defer painting/order changes. Do not report it as proof
            // of frontmost visibility on the user's current Space.
            if let Ok(mut health) = state.popup_health.lock() {
                health.record_related(
                    expected_epoch,
                    "showCompleted",
                    now(),
                    window.is_visible().ok(),
                    Some(presentation.epoch),
                );
            }
            wake_outside_watcher(&handle);
            Ok(presentation)
        })();
        if let Err(error) = &operation {
            record_popup_health(
                &handle,
                expected_epoch,
                if error.starts_with("CANCELLED:") {
                    "showCancelled"
                } else {
                    "showFailed"
                },
                None,
            );
        }
        let _ = reply.send(operation);
    })
    .map_err(|_| "WINDOW_SHOW: 无法安排翻译窗口显示")?;
    popup_health::await_show(result).await
}

fn popup_needs_native_show(
    reuse_requested: bool,
    visible: bool,
    popup_layout: bool,
    pinned: bool,
) -> bool {
    // Ordinary hotkeys always order the popup forward. NSWindow.isVisible
    // alone cannot establish frontmost ordering or visibility on this Space.
    !(reuse_requested && visible && popup_layout && pinned)
}
fn empty_input_payload(presentation_epoch: u64) -> serde_json::Value {
    serde_json::json!({"text":"","mode":"input","presentationEpoch":presentation_epoch})
}
fn emit_presented_action_error(
    app: &tauri::AppHandle,
    presentation: translation_requests::Presentation,
    message: impl Into<String>,
) {
    let _ = app.emit(
        "action-error",
        serde_json::json!({ "presentationEpoch": presentation.epoch, "message": message.into() }),
    );
}

fn source_with_action_error(
    mut source: serde_json::Value,
    error: Option<String>,
) -> serde_json::Value {
    if let Some(message) = error {
        source["actionError"] = serde_json::json!(message);
    }
    source
}
fn empty_selection_window(app: &tauri::AppHandle, presentation_epoch: u64) {
    emit_source_text(app, empty_selection_payload(presentation_epoch));
}

fn source_delivery_event(
    delivery: source_delivery::Delivery<serde_json::Value>,
) -> serde_json::Value {
    let mut payload = delivery.payload;
    payload["deliveryId"] = serde_json::json!(delivery.id);
    payload["presentationEpoch"] = serde_json::json!(delivery.epoch);
    payload
}

fn emit_source_text(app: &tauri::AppHandle, payload: serde_json::Value) {
    let result = (|| {
        let epoch = payload["presentationEpoch"]
            .as_u64()
            .ok_or("捕获交付缺少展示编号")?;
        let state = app.state::<AppState>();
        if state.translation_requests.presentation()?.epoch != epoch {
            return Err(translation_requests::CANCELLED.to_owned());
        }
        let delivery = locked(&state.source_deliveries)?.publish(epoch, payload)?;
        Ok(source_delivery_event(delivery))
    })();
    match result {
        Ok(payload) => {
            let epoch = payload["presentationEpoch"].as_u64().unwrap_or(0);
            let id = payload["deliveryId"].as_u64().unwrap_or(0);
            record_popup_health(app, epoch, "sourcePublished", None);
            emit_source_attempt(app, payload, epoch);
            let handle = app.clone();
            tauri::async_runtime::spawn(async move {
                // Bounded ACK-driven recovery for a lost runtime event. Reuse
                // the ID so the inbox cannot translate or focus twice. Stop on
                // ACK/new task/hide; never poll indefinitely or resurrect text.
                for delay in [200, 800] {
                    tokio::time::sleep(Duration::from_millis(delay)).await;
                    let pending = {
                        let state = handle.state::<AppState>();
                        let current = state.translation_requests.presentation().ok();
                        let queue = state.source_deliveries.lock().ok();
                        current.and_then(|current| {
                            queue.and_then(|queue| {
                                queue
                                    .retry(id, epoch, current.epoch)
                                    .map(source_delivery_event)
                            })
                        })
                    };
                    let Some(mut payload) = pending else {
                        return;
                    };
                    payload["deliveryRetry"] = serde_json::json!(true);
                    record_popup_health(&handle, epoch, "sourceRetried", None);
                    emit_source_attempt(&handle, payload, epoch);
                }
            });
        }
        Err(error) if error.starts_with("CANCELLED:") => {}
        Err(error) => {
            let _ = app.emit("action-error", error);
        }
    }
}

fn emit_source_attempt(app: &tauri::AppHandle, payload: serde_json::Value, epoch: u64) {
    let phase = if app.emit("source-text", payload).is_ok() {
        "sourceEmitSucceeded"
    } else {
        "sourceEmitFailed"
    };
    record_popup_health(app, epoch, phase, None);
}

#[tauri::command]
fn record_popup_stage(
    window: tauri::WebviewWindow,
    presentation_epoch: u64,
    phase: String,
) -> Result<(), String> {
    if window.label() != "main" {
        return Err("窗口不可用".into());
    }
    let phase = popup_health::frontend_phase(&phase).ok_or("未知窗口阶段")?;
    let app = window.app_handle();
    if app
        .state::<AppState>()
        .translation_requests
        .presentation()?
        .epoch
        == presentation_epoch
    {
        record_popup_health(app, presentation_epoch, phase, None);
    }
    Ok(())
}

#[tauri::command]
fn get_pending_source(
    window: tauri::WebviewWindow,
    state: State<AppState>,
) -> Result<Option<serde_json::Value>, String> {
    if window.label() != "main" {
        return Err("捕获结果只能交付主窗口".into());
    }
    let epoch = state.translation_requests.presentation()?.epoch;
    Ok(locked(&state.source_deliveries)?
        .peek(epoch)
        .map(source_delivery_event))
}

#[tauri::command]
fn ack_source_delivery(
    window: tauri::WebviewWindow,
    state: State<AppState>,
    delivery_id: u64,
    presentation_epoch: Option<u64>,
) -> Result<bool, String> {
    if window.label() != "main" {
        return Err("捕获结果只能由主窗口确认".into());
    }
    let acknowledged = locked(&state.source_deliveries)?.acknowledge(delivery_id);
    let epoch = presentation_epoch.unwrap_or(state.translation_requests.presentation()?.epoch);
    record_popup_health(
        window.app_handle(),
        epoch,
        if acknowledged {
            "sourceAcknowledged"
        } else {
            "sourceRetiredBeforeAck"
        },
        None,
    );
    Ok(acknowledged)
}
fn empty_selection_payload(presentation_epoch: u64) -> serde_json::Value {
    let mut payload = empty_input_payload(presentation_epoch);
    payload["focusInput"] = serde_json::json!(true);
    payload
}
fn actionable_capture_hint(action: &str, error: &str) -> Option<String> {
    if !matches!(action, "capture" | "ocr" | "silentOcr") || !error.starts_with("CANCELLED") {
        return None;
    }
    let body = error
        .split_once(':')
        .map(|(_, rest)| rest.trim())
        .unwrap_or("");
    if body.contains("太小") || body.contains("拖动") || body.contains("超时，已取消") {
        Some("请按住左键拖选要识别的区域。Esc 或右键取消。".into())
    } else {
        None
    }
}

fn visible_action_error(action: &str, error: &str) -> Option<String> {
    if ocr_outcome::is_empty_error(action, error) {
        return None;
    }
    if let Some(hint) = actionable_capture_hint(action, error) {
        return Some(hint);
    }
    if error.starts_with("CANCELLED") {
        return None;
    }
    if action == "selection" {
        // A shortcut with no obtainable selection is also the user's manual
        // input shortcut. Permission setup belongs in Settings, not a toast on
        // an otherwise empty popup. Preserve a warning only if the clipboard
        // could not be restored after our copy fallback changed it, or a sent
        // copy received no response (which does not establish an empty selection).
        return if error.starts_with("COPY_NO_UPDATE:")
            || error.starts_with("SELECTION_UNAVAILABLE:")
        {
            Some(error.to_owned())
        } else if error.starts_with("CLIPBOARD_RESTORE_FAILED") {
            Some("原剪贴板恢复失败，当前剪贴板可能仍是刚才复制的选中文字。".into())
        } else if error.starts_with("CLIPBOARD_RESTORE_SKIPPED") {
            Some(
                "复制未能安全完成，暂未恢复原剪贴板，已保留当前内容。请重试或使用截图识别。".into(),
            )
        } else {
            None
        };
    }
    Some(
        error
            .strip_prefix("PERMISSION:")
            .unwrap_or(error)
            .trim()
            .to_owned(),
    )
}
fn clipboard_restoration_notice(error: &str) -> Option<String> {
    if error.starts_with("CLIPBOARD_RESTORE_FAILED:")
        || error.starts_with("CLIPBOARD_RESTORE_SKIPPED:")
    {
        visible_action_error("selection", error)
    } else {
        None
    }
}
fn finish_native_text<T>(result: Result<T, String>, cancelled: bool) -> Result<T, String> {
    // Restoration is a global safety notice even when a newer task owns the
    // popup. Never convert that warning into an old source presentation.
    if cancelled
        && !result
            .as_ref()
            .err()
            .is_some_and(|error| clipboard_restoration_notice(error).is_some())
    {
        Err(translation_requests::CANCELLED.into())
    } else {
        result
    }
}
struct ActionFailurePresentation {
    source: serde_json::Value,
    error: Option<String>,
}
fn action_failure_presentation(
    action: &str,
    error: &str,
    presentation_epoch: u64,
) -> Option<ActionFailurePresentation> {
    if let Some(message) = actionable_capture_hint(action, error) {
        return Some(ActionFailurePresentation {
            source: empty_input_payload(presentation_epoch),
            error: Some(message),
        });
    }
    if error.starts_with("CANCELLED") {
        return None;
    }
    let mut source = empty_input_payload(presentation_epoch);
    if action == "selection" {
        source["focusInput"] = serde_json::json!(true);
    }
    #[cfg(target_os = "macos")]
    if action == "selection" && error.starts_with("PERMISSION:") {
        // Keep the permission reminder and editable source in one epoch-bound
        // event. The Settings link is explicit; a hotkey never requests access.
        source["permissionRequired"] = serde_json::json!("accessibility");
        return Some(ActionFailurePresentation {
            source,
            error: None,
        });
    }
    if matches!(action, "capture" | "ocr" | "silentOcr") && error.starts_with("PERMISSION:") {
        // Keep permission guidance and the blank capture view in one event so
        // the frontend can prepare both before presenting the inactive popup.
        // Neither this mapping nor a shortcut requests permission or opens
        // System Settings; those remain explicit user actions in the view.
        source["permissionRequired"] = serde_json::json!("screenCapture");
        return Some(ActionFailurePresentation {
            source,
            error: None,
        });
    }
    Some(ActionFailurePresentation {
        source,
        error: visible_action_error(action, error),
    })
}
#[tauri::command]
async fn show_popup(
    app: tauri::AppHandle,
    presentation_epoch: u64,
    focus_input: Option<bool>,
    reuse_visible_popup: Option<bool>,
) -> Result<translation_requests::Presentation, String> {
    show_prepared_popup(
        &app,
        presentation_epoch,
        focus_input.unwrap_or(false),
        reuse_visible_popup.unwrap_or(false),
    )
    .await
}
fn start_action(app: tauri::AppHandle, action: String) {
    if action == "input" {
        if let Err(error) = show(&app) {
            let _ = app.emit("action-error", error);
        }
        return;
    }
    let state = app.state::<AppState>();
    let request = match state.native_tasks.begin() {
        Ok(request) => request,
        Err(error) => {
            let _ = app.emit("action-error", error);
            return;
        }
    };
    let capture = is_capture_action(&action);
    let window = app.get_webview_window("main");
    let keep_popup = state
        .translation_requests
        .presentation()
        .is_ok_and(|current| {
            should_keep_native_popup(
                current,
                app.state::<window_layout::LayoutState>().is_popup(),
                window
                    .as_ref()
                    .is_some_and(|window| window.is_visible().unwrap_or(false)),
                state.pinned.load(Ordering::SeqCst),
            )
        });
    // Capture source identity at the user's request, before waiting for the old
    // picker to finish its owned release drain. Never read a later source app.
    #[cfg(target_os = "windows")]
    let selection_attempt = (action == "selection").then(|| {
        let strategy = locked(&state.settings)
            .map(|settings| settings.windows_selection_strategy)
            .unwrap_or_default();
        (strategy, platform::begin_selection_attempt(strategy))
    });
    #[cfg(target_os = "windows")]
    let source_snapshot = if action == "selection" {
        platform::native_source_snapshot().map(Some)
    } else {
        Ok(None)
    };
    #[cfg(target_os = "windows")]
    if let Some((_, attempt)) = selection_attempt {
        platform::record_selection_source(attempt, source_snapshot.is_ok(), None);
    }
    let presentation = match begin_native_request_presentation(
        &state.native_tasks,
        &request,
        &state.translation_requests,
        keep_popup,
        |presentation| announce_presentation(&app, presentation),
    ) {
        Some(Ok(presentation)) => presentation,
        Some(Err(error)) => {
            state.native_tasks.publish(&request, || {
                let _ = app.emit("action-error", error);
            });
            return;
        }
        None => return,
    };
    record_popup_health(&app, presentation.epoch, "nativeActionPrepared", None);
    tauri::async_runtime::spawn(async move {
        if capture && !keep_popup {
            // Native window work stays on the UI thread, outside the short
            // controller publication lock. Await its acknowledgement before
            // any helper can capture an unhidden own window.
            if let Err(error) = hide_native_capture_window(&app, &request, presentation).await {
                publish_native_result(&app, &request, presentation, keep_popup, || {
                    if let Some(message) = visible_action_error(&action, &error) {
                        emit_presented_action_error(&app, presentation, message);
                    }
                });
                return;
            }
        }
        #[cfg(target_os = "macos")]
        if capture {
            if let Err(error) = verify_capture_application_policy(&app).await {
                publish_native_result(&app, &request, presentation, keep_popup, || {
                    emit_presented_action_error(&app, presentation, error);
                });
                return;
            }
        }
        let worker_app = app.clone();
        let worker_request = request.clone();
        let worker_action = action.clone();
        let result = tauri::async_runtime::spawn_blocking(move || {
            let state = worker_app.state::<AppState>();
            // Only one actual native child owns input/exclusion at a time. A
            // superseded waiter is rejected before launching or reading text.
            let _physical = state.native_tasks.enter(&worker_request)?;
            if !native_request_is_current(&worker_app, &worker_request, presentation, keep_popup) {
                return Err(translation_requests::CANCELLED.to_owned());
            }
            #[cfg(target_os = "windows")]
            let expected_source = source_snapshot?;
            #[cfg(target_os = "windows")]
            if let Some(source) = &expected_source {
                let current = source.is_current();
                if let Some((_, attempt)) = selection_attempt {
                    platform::record_selection_source(attempt, true, Some(current));
                }
                if !current {
                    return Err("CANCELLED: 原选词窗口已改变，请重新选词".into());
                }
            }
            let cloud_ocr = if capture {
                let settings = locked(&state.settings)?;
                settings
                    .active_ocr_provider_id
                    .as_ref()
                    .and_then(|id| {
                        settings
                            .ocr_providers
                            .iter()
                            .find(|provider| &provider.id == id)
                    })
                    .cloned()
            } else {
                None
            };
            if !native_request_is_current(&worker_app, &worker_request, presentation, keep_popup) {
                return Err(translation_requests::CANCELLED.into());
            }
            // Acquire after the physical permit so an old guard's restore can
            // never reset a newer capture's exclusion. Keep it until cleanup.
            #[cfg(target_os = "windows")]
            let exclusion = if capture && keep_popup {
                Some(platform::CaptureWindowExclusion::acquire(
                    window.as_ref().ok_or("窗口不存在")?,
                )?)
            } else {
                None
            };
            #[cfg(not(target_os = "windows"))]
            std::thread::sleep(Duration::from_millis(180));
            if worker_request.cancelled() {
                return Err(translation_requests::CANCELLED.into());
            }
            #[cfg(target_os = "windows")]
            if let Some(source) = &expected_source {
                if !source.is_current() {
                    return Err("CANCELLED: 原选词窗口已改变，请重新选词".into());
                }
            }
            let cancel = worker_request.cancellation();
            let text = match worker_action.as_str() {
                "selection" => {
                    #[cfg(target_os = "windows")]
                    {
                        let (strategy, attempt) = selection_attempt.ok_or("缺少取词任务")?;
                        platform::selected_text_with_strategy_cancelable(cancel, strategy, attempt)
                    }
                    #[cfg(not(target_os = "windows"))]
                    platform::selected_text_cancelable(cancel)
                }
                "clipboard" => platform::clipboard_text(),
                "capture" | "ocr" | "silentOcr" if cloud_ocr.is_some() => {
                    platform::capture_image_cancelable(cancel)
                }
                "capture" | "ocr" | "silentOcr" => platform::capture_ocr_cancelable(cancel),
                _ => Err("未知操作".into()),
            };
            #[cfg(target_os = "windows")]
            if let Some(exclusion) = exclusion {
                exclusion.restore()?;
            }
            #[cfg(target_os = "windows")]
            let source_changed = expected_source.is_some_and(|source| !source.is_current());
            #[cfg(not(target_os = "windows"))]
            let source_changed = false;
            // A later editor inside the same source window is a different
            // selection intent. Discard it without raising/focusing a blank
            // popup; restoration notices retain their global safety path.
            finish_native_text(text, worker_request.cancelled() || source_changed)
                .map(|text| (text, cloud_ocr))
        })
        .await
        .map_err(|_| "系统操作异常".to_string())
        .and_then(|result| result);
        #[cfg(target_os = "windows")]
        if let Some((_, attempt)) = selection_attempt {
            platform::update_selection_attempt(
                attempt,
                4,
                result.is_ok(),
                result
                    .as_ref()
                    .is_ok_and(|(text, _)| !text.trim().is_empty()),
                result.as_ref().err().map(String::as_str),
            );
        }
        if let Err(error) = &result {
            if let Some(message) = clipboard_restoration_notice(error) {
                // No source, epoch, activation or visibility mutation: an old
                // copy's failed restore must remain visible during a new task.
                let _ = app.emit("action-error", message);
                return;
            }
        }
        if !native_request_is_current(&app, &request, presentation, keep_popup) {
            return;
        }
        let result = match result {
            Ok((text, Some(provider))) => {
                let key = load_ocr_key_async(
                    app.clone(),
                    provider.clone(),
                    false,
                    Some(request.cancellation()),
                )
                .await;
                if !native_request_is_current(&app, &request, presentation, keep_popup) {
                    return;
                }
                let state = app.state::<AppState>();
                native_ocr_result(
                    request.cancellation(),
                    ocr::recognize(&state.client, &provider, key, &text),
                )
                .await
            }
            Ok((text, None)) => Ok(text),
            Err(error) => Err(error),
        };
        if !native_request_is_current(&app, &request, presentation, keep_popup) {
            return;
        }
        publish_native_result(&app, &request, presentation, keep_popup, || {
            #[cfg(target_os = "windows")]
            if let Some((_, attempt)) = selection_attempt {
                platform::update_selection_attempt(
                    attempt,
                    5,
                    result.is_ok(),
                    result.as_ref().is_ok_and(|text| !text.trim().is_empty()),
                    result.as_ref().err().map(String::as_str),
                );
            }
            // The request/epoch guard above owns this publication. Empty OCR
            // replaces old source/results even in a pinned popup; cancellation
            // and genuine failures below retain their existing behavior.
            if ocr_outcome::is_empty(&action, &result) {
                emit_source_text(&app, empty_ocr_payload(presentation.epoch, keep_popup));
                return;
            }
            match result {
                Ok(text) if !text.trim().is_empty() => {
                    emit_source_text(
                        &app,
                        captured_source_payload(&action, text, presentation.epoch, keep_popup),
                    );
                }
                Ok(_) if action == "selection" => {
                    // Alt+D is also the manual-input shortcut, including when
                    // the existing translator is pinned. Pin retains the window,
                    // not the previous source after an explicit new input task.
                    empty_selection_window(&app, presentation.epoch);
                }
                Ok(_) => {
                    let message = "没有识别到文字，请选择更清晰的区域";
                    if !keep_popup {
                        emit_source_text(
                            &app,
                            source_with_action_error(
                                empty_input_payload(presentation.epoch),
                                Some(message.to_owned()),
                            ),
                        );
                    } else {
                        emit_presented_action_error(&app, presentation, message);
                    }
                }
                Err(error) => {
                    if keep_popup && action != "selection" {
                        // Failed/cancelled OCR preserves completed content.
                        // Unavailable selection still opens the quiet editor.
                        if let Some(message) = visible_action_error(&action, &error) {
                            emit_presented_action_error(
                                &app,
                                presentation,
                                if capture { error } else { message },
                            );
                        }
                    } else if let Some(failure) =
                        action_failure_presentation(&action, &error, presentation.epoch)
                    {
                        // Keep the hint with the source delivery: an earlier
                        // independent toast could be cleared while this source
                        // waits for presentation/layout IPC acknowledgments.
                        emit_source_text(
                            &app,
                            source_with_action_error(failure.source, failure.error),
                        );
                    }
                }
            }
        });
    });
}
async fn hide_native_capture_window(
    app: &tauri::AppHandle,
    request: &native_tasks::Request,
    presentation: translation_requests::Presentation,
) -> Result<(), String> {
    let (send, receive) = tokio::sync::oneshot::channel();
    let handle = app.clone();
    let request = request.clone();
    app.run_on_main_thread(move || {
        let result = if !native_request_is_current(&handle, &request, presentation, false) {
            Err(translation_requests::CANCELLED.to_owned())
        } else if let Some(window) = handle.get_webview_window("main") {
            platform::hide_webview_window(&window)
        } else {
            Err("窗口不存在".into())
        };
        let _ = send.send(result);
    })
    .map_err(|_| "WINDOW_THREAD: 无法准备截图窗口".to_string())?;
    receive
        .await
        .map_err(|_| "WINDOW_THREAD: 截图窗口准备被中断".to_string())?
}
async fn wait_native_cancellation(cancelled: Arc<AtomicBool>) {
    while !cancelled.load(Ordering::Acquire) {
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}
async fn native_ocr_result<T>(
    cancelled: Arc<AtomicBool>,
    future: impl std::future::Future<Output = Result<T, String>>,
) -> Result<T, String> {
    tokio::select! {
        biased;
        _ = wait_native_cancellation(cancelled) => Err(translation_requests::CANCELLED.into()),
        result = future => result,
    }
}
fn native_request_is_current(
    app: &tauri::AppHandle,
    request: &native_tasks::Request,
    presentation: translation_requests::Presentation,
    retained: bool,
) -> bool {
    app.state::<AppState>().native_tasks.is_current(request)
        && native_action_result_is_current(app, presentation, retained)
}
// The controller lock orders short event publication against a new begin.
// Do not call native_request_is_current here: publish already owns that lock.
fn publish_native_result<R>(
    app: &tauri::AppHandle,
    request: &native_tasks::Request,
    presentation: translation_requests::Presentation,
    retained: bool,
    publication: impl FnOnce() -> R,
) -> Option<R> {
    app.state::<AppState>()
        .native_tasks
        .publish(request, || {
            native_action_result_is_current(app, presentation, retained).then(publication)
        })
        .flatten()
}
fn captured_source_payload(
    action: &str,
    text: String,
    epoch: u64,
    retained: bool,
) -> serde_json::Value {
    let capture = is_capture_action(action);
    let mut payload = serde_json::json!({"text":text,"mode":captured_text_mode(action),"presentationEpoch":epoch,
        "updateVisiblePopup":retained,"reuseVisiblePopup":retained && capture});
    if capture {
        payload["captureOrigin"] = serde_json::json!("ocr");
    }
    payload
}
fn empty_ocr_payload(epoch: u64, retained: bool) -> serde_json::Value {
    // Input mode clears source/results but does not translate empty text, show
    // weak-result guidance, focus the editor or request any permissions.
    serde_json::json!({"text":"", "mode":"input", "captureOrigin":"ocr",
        "presentationEpoch":epoch, "updateVisiblePopup":retained, "reuseVisiblePopup":retained})
}
fn is_capture_action(action: &str) -> bool {
    matches!(action, "capture" | "ocr" | "silentOcr")
}
fn native_action_result_is_current(
    app: &tauri::AppHandle,
    expected: translation_requests::Presentation,
    retained_capture: bool,
) -> bool {
    let current = app
        .state::<AppState>()
        .translation_requests
        .presentation()
        .ok();
    retained_capture_result_is_current(
        expected,
        current,
        retained_capture,
        app.state::<window_layout::LayoutState>().is_popup(),
    )
}
fn retained_capture_result_is_current(
    expected: translation_requests::Presentation,
    current: Option<translation_requests::Presentation>,
    retained_capture: bool,
    popup_layout: bool,
) -> bool {
    current == Some(expected) && (!retained_capture || popup_layout)
}
fn should_keep_native_popup(
    presentation: translation_requests::Presentation,
    popup_layout: bool,
    visible: bool,
    pinned: bool,
) -> bool {
    presentation.presented && popup_layout && visible && pinned
}
fn begin_native_action_presentation(
    requests: &translation_requests::TranslationRequests,
    keep_popup: bool,
) -> Result<translation_requests::Presentation, String> {
    if keep_popup {
        requests.invalidate()
    } else {
        requests.suspend()
    }
}
fn begin_native_request_presentation(
    controller: &native_tasks::Controller,
    request: &native_tasks::Request,
    requests: &translation_requests::TranslationRequests,
    keep_popup: bool,
    announce: impl FnOnce(translation_requests::Presentation),
) -> Option<Result<translation_requests::Presentation, String>> {
    // A stale begin may not invalidate the newer task's presentation. The
    // epoch and its event are published together against concurrent begin().
    controller.publish(request, || {
        let presentation = begin_native_action_presentation(requests, keep_popup)?;
        announce(presentation);
        Ok(presentation)
    })
}
fn captured_text_mode(action: &str) -> &'static str {
    // Owner's “无感 OCR” means capture → source text → automatic translation.
    // Only the explicitly chosen recognition-only action suppresses translation.
    if action == "ocr" {
        "ocr"
    } else {
        "translate"
    }
}
#[cfg(target_os = "windows")]
fn outside_click_watcher(app: tauri::AppHandle) {
    let clicks = match windows_visibility::start() {
        Ok(clicks) => clicks,
        Err(error) => {
            if let Ok(mut warnings) = app.state::<AppState>().startup_warnings.lock() {
                warnings.push(error);
            }
            return;
        }
    };
    std::thread::Builder::new()
        .name("popup-outside-clicks".into())
        .spawn(move || {
            while let Ok(click) = clicks.recv() {
                if !windows_visibility::current(click.token) {
                    continue;
                }
                let handle = app.clone();
                let _ = app.run_on_main_thread(move || {
                    if !windows_visibility::current(click.token) {
                        return;
                    }
                    let Some(window) = handle.get_webview_window("main") else {
                        return;
                    };
                    let state = handle.state::<AppState>();
                    let Ok(current) = state.translation_requests.presentation() else {
                        return;
                    };
                    if !should_hide_observed_popup(
                        translation_requests::Presentation {
                            epoch: click.token.epoch,
                            presented: true,
                        },
                        current,
                        handle.state::<window_layout::LayoutState>().is_popup(),
                        window.is_visible().unwrap_or(false),
                        state.pinned.load(Ordering::SeqCst),
                    ) {
                        return;
                    }
                    if let (Ok(position), Ok(size)) = (window.outer_position(), window.outer_size())
                    {
                        if windows_visibility::outside_bounds(
                            click,
                            position.x,
                            position.y,
                            size.width,
                            size.height,
                        ) {
                            record_popup_health(&handle, current.epoch, "hideOutsideClick", None);
                            cancel_active_translation(&handle);
                            let _ = platform::hide_webview_window(&window);
                        }
                    }
                });
            }
        })
        .ok();
}

// Preserve the established macOS pointer/counter path unchanged.
#[cfg(not(target_os = "windows"))]
fn outside_click_watcher(app: tauri::AppHandle) {
    let owner = app.clone();
    let handle = std::thread::spawn(move || {
        let mut previous = false;
        let mut was_visible = false;
        loop {
            std::thread::sleep(Duration::from_millis(20));
            let Some(window) = app.get_webview_window("main") else {
                break;
            };
            if !window.is_visible().unwrap_or(false)
                || app.state::<AppState>().pinned.load(Ordering::SeqCst)
                || !app.state::<window_layout::LayoutState>().is_popup()
            {
                previous = false;
                was_visible = false;
                std::thread::park_timeout(Duration::from_secs(60));
                continue;
            }
            let Ok(observed_presentation) =
                app.state::<AppState>().translation_requests.presentation()
            else {
                continue;
            };
            let Ok((down, x, y)) = platform::pointer_state() else {
                continue;
            };
            if !was_visible {
                was_visible = true;
                previous = down;
                continue;
            }
            if down && !previous {
                if let (Ok(position), Ok(size), Ok(scale)) = (
                    window.outer_position(),
                    window.outer_size(),
                    window.scale_factor(),
                ) {
                    let (px, py) = if cfg!(target_os = "macos") {
                        (x * scale, y * scale)
                    } else {
                        (x, y)
                    };
                    if px < f64::from(position.x)
                        || py < f64::from(position.y)
                        || px >= f64::from(position.x) + f64::from(size.width)
                        || py >= f64::from(position.y) + f64::from(size.height)
                    {
                        let handle = app.clone();
                        let _ = app.run_on_main_thread(move || {
                            let Some(window) = handle.get_webview_window("main") else {
                                return;
                            };
                            let state = handle.state::<AppState>();
                            let Ok(current) = state.translation_requests.presentation() else {
                                return;
                            };
                            if should_hide_observed_popup(
                                observed_presentation,
                                current,
                                handle.state::<window_layout::LayoutState>().is_popup(),
                                window.is_visible().unwrap_or(false),
                                state.pinned.load(Ordering::SeqCst),
                            ) {
                                record_popup_health(
                                    &handle,
                                    current.epoch,
                                    "hideOutsideClick",
                                    None,
                                );
                                cancel_active_translation(&handle);
                                let _ = platform::hide_webview_window(&window);
                            }
                        });
                    }
                }
            }
            previous = down;
        }
    });
    *owner.state::<AppState>().outside_thread.lock().unwrap() = Some(handle.thread().clone());
}

fn should_hide_observed_popup(
    observed: translation_requests::Presentation,
    current: translation_requests::Presentation,
    popup_layout: bool,
    visible: bool,
    pinned: bool,
) -> bool {
    observed == current && popup_layout && visible && !pinned
}

#[cfg(target_os = "windows")]
fn windows_popup_focus_changed(app: &tauri::AppHandle, focused: bool) {
    let Some(token) = windows_visibility::token() else {
        return;
    };
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    let state = app.state::<AppState>();
    let Ok(current) = state.translation_requests.presentation() else {
        return;
    };
    if !should_hide_observed_popup(
        translation_requests::Presentation {
            epoch: token.epoch,
            presented: true,
        },
        current,
        app.state::<window_layout::LayoutState>().is_popup(),
        window.is_visible().unwrap_or(false),
        state.pinned.load(Ordering::SeqCst),
    ) {
        return;
    }
    if focused {
        if platform::popup_has_native_foreground(&window) {
            windows_visibility::mark_focused(token);
        }
    } else if windows_visibility::may_dismiss_blur(
        token,
        platform::popup_foreground_is_external(&window),
    ) {
        record_popup_health(app, current.epoch, "hideExternalFocus", None);
        cancel_active_translation(app);
        let _ = platform::hide_webview_window(&window);
    }
}

// Keep the IPC name and the existing layout implementation. Only Windows mode
// transitions invalidate queued dismissal observations; fitting never shows or
// focuses a window. Await the UI transaction without blocking the UI event loop.
#[tauri::command(rename = "fit_window")]
async fn fit_window_with_visibility(
    window: tauri::WebviewWindow,
    state: State<'_, window_layout::LayoutState>,
    presentation: String,
    content_height: f64,
    content_width: Option<f64>,
) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    let mode_changed = matches!(presentation.as_str(), "popup" | "management")
        && state.is_popup() != (presentation == "popup");
    #[cfg(target_os = "windows")]
    if mode_changed {
        windows_visibility::disarm();
    }
    #[cfg(target_os = "windows")]
    let app = window.app_handle().clone();
    let result =
        window_layout::fit_window(window, state, presentation, content_height, content_width).await;
    #[cfg(target_os = "windows")]
    if mode_changed {
        wake_outside_watcher(&app);
    }
    result
}
#[tauri::command]
fn run_action(app: tauri::AppHandle, action: String) -> Result<(), String> {
    if !is_native_action(&action) {
        return Err("未知操作".into());
    }
    start_action(app, action);
    Ok(())
}

fn is_native_action(action: &str) -> bool {
    matches!(
        action,
        "selection" | "capture" | "ocr" | "silentOcr" | "input" | "clipboard"
    )
}
#[tauri::command]
async fn copy_text(text: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || platform::copy_text(&text))
        .await
        .map_err(|_| "复制失败".to_string())?
}
#[tauri::command]
async fn set_pinned(app: tauri::AppHandle, pinned: bool) -> Result<(), String> {
    let (reply, result) = tokio::sync::oneshot::channel();
    let handle = app.clone();
    app.run_on_main_thread(move || {
        let operation = (|| {
            let window = handle.get_webview_window("main").ok_or("窗口不存在")?;
            platform::ensure_popup_behavior(&window)?;
            handle
                .state::<AppState>()
                .pinned
                .store(pinned, Ordering::SeqCst);
            wake_outside_watcher(&handle);
            Ok(())
        })();
        let _ = reply.send(operation);
    })
    .map_err(|_| "无法设置浮窗状态")?;
    result.await.map_err(|_| "无法设置浮窗状态".to_string())?
}
#[tauri::command]
fn hide_window(app: tauri::AppHandle) -> Result<(), String> {
    if let Ok(current) = app.state::<AppState>().translation_requests.presentation() {
        record_popup_health(&app, current.epoch, "hideRequested", None);
    }
    cancel_shortcut_recording(&app);
    cancel_active_translation(&app);
    let window = app.get_webview_window("main").ok_or("窗口不存在")?;
    platform::hide_webview_window(&window)
}
#[tauri::command]
async fn diagnostics(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    include_native: Option<bool>,
) -> Result<serde_json::Value, String> {
    let startup_warnings = locked(&state.startup_warnings)?.clone();
    let registrations = {
        let settings = locked(&state.settings)?;
        let registered = locked(&state.registered_shortcuts)?;
        let failures = locked(&state.shortcut_failures)?;
        shortcut_registration_snapshot(&settings, &registered, &failures, native_binding_active)?
    };
    let mut warnings = startup_warnings.clone();
    warnings.extend(current_shortcut_warnings(&registrations));
    let mut value = if include_native.unwrap_or(true) {
        tauri::async_runtime::spawn_blocking(platform::diagnostics)
            .await
            .map_err(|_| "诊断失败")?
    } else {
        serde_json::json!({ "nativeDiagnostics": "notRequested" })
    };
    value["appVersion"] = serde_json::json!(env!("CARGO_PKG_VERSION"));
    value["warnings"] = serde_json::json!(warnings);
    value["startupWarnings"] = serde_json::json!(startup_warnings);
    value["shortcutRegistration"] = serde_json::json!(registrations);
    value["dataDirectory"] = serde_json::json!(state.data_dir.display().to_string());
    value["ocrUpload"] = serde_json::json!(false);
    value["lastTranslation"] = translation_health::snapshot();
    value["popupDelivery"] =
        serde_json::to_value(&*locked(&state.popup_health)?).map_err(|_| "无法读取浮窗诊断")?;
    value["processId"] = serde_json::json!(std::process::id());
    #[cfg(target_os = "windows")]
    {
        value["shortcutInput"] = serde_json::Value::Object(
            windows_mouse_shortcuts::diagnostics()
                .into_iter()
                .map(|(key, value)| (key.to_owned(), serde_json::json!(value)))
                .collect(),
        );
    }
    #[cfg(target_os = "macos")]
    {
        let policy_diagnostics = app.state::<ApplicationPolicyDiagnostics>();
        value["windowPolicy"] = serde_json::to_value(&*locked(&policy_diagnostics.0)?)
            .map_err(|_| "无法读取窗口策略诊断")?;
    }
    #[cfg(not(target_os = "macos"))]
    let _ = app;
    Ok(value)
}
#[tauri::command]
async fn permission_status() -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(platform::permission_status)
        .await
        .map_err(|_| "无法检查系统权限".to_string())?
}

#[tauri::command]
async fn get_system_translation_status(
    source_language: String,
    target_language: String,
) -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(move || {
        platform::system_translation_status(&source_language, &target_language)
    })
    .await
    .map_err(|_| "无法检查系统翻译状态".to_string())?
}

#[tauri::command]
async fn prepare_system_translation(
    source_language: String,
    target_language: String,
) -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(move || {
        platform::prepare_system_translation(&source_language, &target_language)
    })
    .await
    .map_err(|_| "系统翻译准备未能完成".to_string())?
}
#[tauri::command]
async fn request_permission(kind: String) -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(move || platform::request_permission(&kind))
        .await
        .map_err(|_| "无法请求系统权限".to_string())?
}
#[tauri::command]
async fn open_permission_settings(kind: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || platform::open_permission_settings(&kind))
        .await
        .map_err(|_| "无法打开系统权限设置".to_string())?
}

#[tauri::command]
async fn open_service_link(url: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || service_links::open(&url))
        .await
        .map_err(|_| "无法打开服务配置文档".to_string())?
}

// No endpoint, current version, user content or credentials can be supplied by
// the WebView. Preferences come from the persisted native settings.
#[tauri::command]
async fn get_update_status(state: State<'_, AppState>) -> Result<update_notice::Status, String> {
    let include_prereleases = locked(&state.settings)?.include_prerelease_updates;
    Ok(state
        .update_notice
        .status(env!("CARGO_PKG_VERSION"), include_prereleases)
        .await)
}

#[tauri::command]
async fn check_for_updates(
    state: State<'_, AppState>,
    manual: bool,
) -> Result<update_notice::Status, String> {
    let (automatic, include_prereleases) = {
        let settings = locked(&state.settings)?;
        (
            settings.automatic_update_checks,
            settings.include_prerelease_updates,
        )
    };
    Ok(state
        .update_notice
        .check(
            env!("CARGO_PKG_VERSION"),
            include_prereleases,
            manual,
            automatic,
        )
        .await)
}

fn tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
    let definitions = [
        ("settings", "设置与服务"),
        ("input", "打开翻译窗口"),
        ("selection", "划词翻译"),
        ("capture", "截图翻译"),
        ("ocr", "截图 OCR"),
        ("silentOcr", "无感 OCR"),
        ("clipboard", "翻译剪贴板"),
    ];
    let menu = Menu::new(app)?;
    for (id, label) in definitions {
        menu.append(&MenuItem::with_id(app, id, label, true, None::<&str>)?)?;
    }
    menu.append(&PredefinedMenuItem::separator(app)?)?;
    menu.append(&MenuItem::with_id(
        app,
        "quit",
        "退出 EchoLingo",
        true,
        None::<&str>,
    )?)?;
    let mut builder = tauri::tray::TrayIconBuilder::new()
        .menu(&menu)
        .tooltip("EchoLingo · 回声译")
        .on_menu_event(|app, event| {
            if event.id().as_ref() == "quit" {
                app.exit(0);
            } else if event.id().as_ref() == "settings" {
                request_settings(app);
            } else if is_native_action(event.id().as_ref()) {
                // Tauri dispatches all application/window/tray menu events to
                // tray listeners too. Ignore Edit/About/app-settings IDs.
                start_action(app.clone(), event.id().as_ref().to_string());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }
    builder.build(app)?;
    Ok(())
}

#[cfg(target_os = "macos")]
fn management_menu(app: &tauri::AppHandle) -> tauri::Result<()> {
    use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
    // Keep the standard Edit menu and native copy/paste accelerators.
    let menu = Menu::default(app)?;
    if let Some(submenu) = menu.items()?.first().and_then(|item| item.as_submenu()) {
        submenu.insert(
            &MenuItem::with_id(
                app,
                "app-settings",
                "设置与服务…",
                true,
                Some("CmdOrCtrl+,"),
            )?,
            2,
        )?;
        submenu.insert(&PredefinedMenuItem::separator(app)?, 3)?;
    }
    app.set_menu(menu)?;
    app.on_menu_event(|app, event| {
        if event.id().as_ref() == "app-settings" {
            request_settings(app);
        }
    });
    Ok(())
}

fn main() {
    if let Some(code) = shortcut_probe::run_if_requested(&std::env::args().collect::<Vec<_>>()) {
        std::process::exit(code);
    }
    let builder = tauri::Builder::default();
    #[cfg(target_os = "macos")]
    let builder = builder.activate_ignoring_other_apps(false);
    let mut app = builder
        .plugin(tauri_plugin_single_instance::init(|app, args, _| {
            explicit_launch(app, &args)
        }))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            let data_dir = app.path().app_data_dir()?;
            fs::create_dir_all(&data_dir)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                fs::set_permissions(&data_dir, fs::Permissions::from_mode(0o700))?;
            }
            let mut warnings = Vec::new();
            let mut settings = match fs::read(data_dir.join("settings.json")) {
                Ok(bytes) => match serde_json::from_slice::<Settings>(&bytes).map(|mut s| {
                    // Upgrade former defaults before enforcing the new cap.
                    // Otherwise a healthy legacy 200-entry config would be
                    // misclassified as corrupt and lose its provider choices.
                    migrate_core_preferences(&mut s);
                    s
                }) {
                    Ok(s) if validate_settings(&s).is_ok() => s,
                    _ => {
                        warnings.push("设置文件损坏，已使用默认设置；原文件保留".into());
                        Settings::default()
                    }
                },
                Err(_) => Settings::default(),
            };
            add_system_translation_option(&mut settings);
            add_offline_translation_option(&mut settings);
            migrate_language_direction(&mut settings);
            migrate_shortcut_defaults(&mut settings);
            let mut history: Vec<HistoryEntry> = fs::read(data_dir.join("history.json"))
                .ok()
                .and_then(|b| serde_json::from_slice(&b).ok())
                .unwrap_or_default();
            trim_history(&mut history, settings.max_history);
            let client = reqwest::Client::builder()
                .timeout(Duration::from_secs(45))
                .connect_timeout(Duration::from_secs(12))
                .redirect(reqwest::redirect::Policy::none())
                .user_agent("EchoLingo/0.1.0")
                .build()?;
            let layout_data_dir = data_dir.clone();
            app.manage(AppState {
                settings: Mutex::new(settings.clone()),
                credentials: credential_cache::CredentialCache::default(),
                credential_reads: Mutex::new(()),
                history: Mutex::new(history),
                pinned: AtomicBool::new(false),
                native_tasks: native_tasks::Controller::default(),
                shortcut_gate: Mutex::new(shortcut_control::ShortcutGate::default()),
                shortcut_routes: shortcut_control::ShortcutRoutes::default(),
                shortcut_updating: AtomicBool::new(false),
                shortcut_maintenance: shortcut_control::ShortcutMaintenance::default(),
                registered_shortcuts: Mutex::new(Vec::new()),
                shortcut_failures: Mutex::new(std::collections::BTreeMap::new()),
                translation_busy: tokio::sync::Semaphore::new(2),
                translation_requests: translation_requests::TranslationRequests::default(),
                data_dir,
                client,
                update_notice: update_notice::Controller::new(
                    layout_data_dir.join("update-notice.json"),
                ),
                offline: offline_translation::OfflineTranslation::new(
                    app.path().resource_dir()?.join("offline-translation"),
                ),
                startup_warnings: Mutex::new(warnings),
                outside_thread: Mutex::new(None),
                pending_settings: Mutex::new(None),
                source_deliveries: Mutex::new(source_delivery::SourceDeliveries::default()),
                pending_shortcut_settings: AtomicBool::new(false),
                popup_health: Mutex::new(popup_health::PopupHealth::default()),
            });
            app.manage(window_layout::LayoutState::new(layout_data_dir));
            // The first registered OCR shortcut must already have its native
            // input host; startup does not otherwise wait for the frontend.
            #[cfg(target_os = "windows")]
            outside_click_watcher(app.handle().clone());
            #[cfg(target_os = "macos")]
            {
                app.manage(ApplicationPolicyDiagnostics::default());
                if let Err(error) = verify_application_policy(app.handle(), "setup") {
                    app.state::<AppState>()
                        .startup_warnings
                        .lock()
                        .unwrap()
                        .push(error);
                }
            }
            #[cfg(target_os = "windows")]
            if let Err(error) = start_native_shortcuts(app.handle().clone()) {
                app.state::<AppState>()
                    .startup_warnings
                    .lock()
                    .unwrap()
                    .push(error);
            }
            if let Err(e) = install_shortcuts(app.handle(), &settings.shortcuts) {
                // Binding failures already live in shortcut_failures, which is
                // updated by retries and settings saves. Only non-binding
                // installation failures belong in the historical startup list.
                let state = app.state::<AppState>();
                let binding_errors = locked(&state.shortcut_failures)?
                    .values()
                    .cloned()
                    .collect::<Vec<_>>()
                    .join("；");
                if let Some(error) = non_binding_installation_error(&e, &binding_errors) {
                    locked(&state.startup_warnings)?.push(error);
                }
            }
            schedule_shortcut_retries(app.handle().clone());
            tray(app.handle())?;
            #[cfg(target_os = "macos")]
            management_menu(app.handle())?;
            if permission_diagnostics_requested(&std::env::args().collect::<Vec<_>>()) {
                let _ = write_permission_diagnostics(app.handle());
            }
            #[cfg(any(target_os = "macos", target_os = "windows"))]
            if selection_diagnostics_requested(&std::env::args().collect::<Vec<_>>()) {
                let _ = write_selection_diagnostics(app.handle());
            }
            #[cfg(target_os = "windows")]
            if capture_diagnostics_requested(&std::env::args().collect::<Vec<_>>()) {
                let _ = write_capture_diagnostics(app.handle());
            }
            if configure_shortcuts_requested(&std::env::args().collect::<Vec<_>>()) {
                request_shortcut_settings(app.handle());
            }
            #[cfg(not(target_os = "windows"))]
            outside_click_watcher(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| match event {
            tauri::WindowEvent::Focused(focused) if window.label() == "main" => {
                if !*focused {
                    cancel_shortcut_recording(window.app_handle());
                }
                #[cfg(target_os = "windows")]
                windows_popup_focus_changed(window.app_handle(), *focused);
            }
            tauri::WindowEvent::CloseRequested { api, .. } => {
                api.prevent_close();
                cancel_shortcut_recording(window.app_handle());
                cancel_active_translation(window.app_handle());
                let _ = platform::hide_window(window);
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            fit_window_with_visibility,
            window_layout::wait_for_window_sizing,
            window_layout::start_window_drag,
            window_layout::begin_popup_drag,
            window_layout::move_popup_drag,
            window_layout::end_popup_drag,
            window_layout::start_window_resize,
            window_layout::resize_popup_width,
            window_layout::resize_management_window,
            show_popup,
            show_management,
            get_pending_settings,
            get_pending_source,
            ack_source_delivery,
            record_popup_stage,
            get_settings,
            save_settings,
            set_shortcut_recording,
            set_ocr_api_key,
            delete_ocr_api_key,
            test_ocr_provider,
            set_api_key,
            delete_api_key,
            translate,
            begin_translation,
            cancel_translation,
            get_translation_presentation,
            test_provider,
            get_history,
            toggle_favorite,
            delete_history,
            run_action,
            copy_text,
            set_pinned,
            hide_window,
            diagnostics,
            frontend_input_diagnostics_enabled,
            record_frontend_input_diagnostic,
            permission_status,
            get_system_translation_status,
            prepare_system_translation,
            request_permission,
            open_permission_settings,
            open_service_link,
            get_update_status,
            check_for_updates
        ])
        .build(tauri::generate_context!())
        .expect("EchoLingo could not start");
    // App still owns the runtime here, so this seeds Tao's initial launch role
    // before applicationDidFinishLaunching rather than changing it during setup.
    #[cfg(target_os = "macos")]
    macos_startup::configure(&mut app);
    app.run(|app, event| {
        if matches!(&event, tauri::RunEvent::Exit) {
            #[cfg(target_os = "windows")]
            {
                windows_mouse_shortcuts::stop();
                windows_visibility::stop();
            }
            let _ = app.state::<window_layout::LayoutState>().flush();
        }
        #[cfg(target_os = "macos")]
        if let tauri::RunEvent::Reopen { .. } = event {
            let _ = verify_application_policy(app, "reopen");
            request_settings(app);
        }
        #[cfg(not(target_os = "macos"))]
        let _ = (app, event);
    });
}

#[cfg(test)]
mod tests {
    #[test]
    fn capture_export_is_exact_flag_and_numeric_allowlist_only() {
        assert!(super::capture_diagnostics_requested(&[
            "app".into(),
            "--capture-diagnostics".into()
        ]));
        assert!(!super::capture_diagnostics_requested(&[
            "--capture-diagnostics".into()
        ]));
        assert!(!super::capture_diagnostics_requested(&[
            "app".into(),
            "--capture-diagnostics=other.json".into()
        ]));
        let payload = super::capture_diagnostic_payload(serde_json::json!({
            "attemptId": 7, "resultOk": 0, "hostOwnedButtons": 0,
            "displayChangedError": "private", "sourceText": "private", "imageBase64": "private",
        }));
        assert_eq!(payload["diagnostic"], "last-capture-attempt");
        assert_eq!(
            payload["diagnostics"],
            serde_json::json!({"attemptId": 7, "resultOk": 0, "hostOwnedButtons": 0})
        );
        assert!(!payload.to_string().contains("private"));
    }
    use super::*;
    #[test]
    fn explicit_input_always_advances_visible_epoch_and_invalidates_old_requests() {
        let requests = translation_requests::TranslationRequests::default();
        let visible = requests.resume(None).unwrap();
        let first = prepare_input_presentation(&requests).unwrap();
        assert!(first.presented && first.epoch > visible.epoch);
        let old_request = requests.begin(first.epoch).unwrap();
        assert!(requests.is_current(old_request).unwrap());
        let second = prepare_input_presentation(&requests).unwrap();
        assert!(second.presented && second.epoch > first.epoch);
        assert!(!requests.is_current(old_request).unwrap());
        assert!(requests.begin(first.epoch).is_err());
        assert!(requests.finish(old_request, || Ok(())).is_err());
        let hidden = requests.suspend().unwrap();
        let reopened = prepare_input_presentation(&requests).unwrap();
        assert!(reopened.presented && reopened.epoch > hidden.epoch);
    }

    #[test]
    fn ocr_hotkey_fills_translation_while_recognition_only_stays_explicit() {
        assert_eq!(captured_text_mode("silentOcr"), "translate");
        assert_eq!(captured_text_mode("capture"), "translate");
        assert_eq!(captured_text_mode("ocr"), "ocr");
        let empty = empty_selection_payload(12);
        assert_eq!(empty["focusInput"], true);
        assert!(empty["text"].as_str().unwrap().is_empty());
        assert!(empty_input_payload(12).get("focusInput").is_none());
    }
    #[test]
    fn built_in_translation_never_reads_an_api_credential() {
        for p in [
            system_translation_provider(true),
            offline_translation_provider(true),
        ] {
            assert_eq!(
                load_key(&credential_cache::CredentialCache::default(), &p).unwrap(),
                ""
            );
            let mut settings = Settings::default();
            settings.providers = vec![p];
            let snapshot =
                settings_snapshot(&settings, &credential_cache::CredentialCache::default())
                    .unwrap();
            assert_eq!(snapshot["providers"][0]["hasKey"], false);
        }
    }

    #[test]
    fn settings_snapshot_is_memory_only_and_never_contains_cached_secrets() {
        let cache = credential_cache::CredentialCache::default();
        let settings = Settings::default();
        let provider = settings
            .providers
            .iter()
            .find(|p| p.kind == "openai")
            .unwrap();
        let key = translation_credential_key(provider).unwrap();
        let snapshot = settings_snapshot(&settings, &cache).unwrap();
        let item = snapshot["providers"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == provider.id)
            .unwrap();
        assert_eq!(item["credentialState"], "unloaded");
        assert_eq!(item["hasKey"], false);
        let fake = "FIXTURE-ONLY-NOT-A-REAL-KEY";
        cache.store(&key, Ok(fake.to_string())).unwrap();
        let snapshot = settings_snapshot(&settings, &cache).unwrap();
        assert!(!snapshot.to_string().contains(fake));
        let item = snapshot["providers"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == provider.id)
            .unwrap();
        assert_eq!(item["credentialState"], "ready");
        assert_eq!(item["hasKey"], true);
        cache.store(&key, Err("fixture-denied".into())).unwrap();
        let snapshot = settings_snapshot(&settings, &cache).unwrap();
        assert!(!snapshot.to_string().contains("fixture-denied"));
        let item = snapshot["providers"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == provider.id)
            .unwrap();
        assert_eq!(item["credentialState"], "blocked");
        assert_eq!(item["hasKey"], false);
    }

    #[test]
    fn repeated_translation_credential_loads_decode_once_and_respect_scopes() {
        let cache = credential_cache::CredentialCache::default();
        let scope = "openai|https://example.invalid";
        let stored = encode_credential(scope.into(), "fixture-secret".into()).unwrap();
        let reads = std::cell::Cell::new(0);
        for _ in 0..10 {
            let loaded = cached_credential(&cache, "fixture-provider", scope, || {
                reads.set(reads.get() + 1);
                Ok(Some(stored.clone()))
            })
            .unwrap();
            assert_eq!(loaded, "fixture-secret");
        }
        assert_eq!(reads.get(), 1);
        for other in [
            "deepl|https://example.invalid",
            "openai|https://other.invalid",
        ] {
            assert!(
                cached_credential(&cache, "fixture-provider", other, || Ok(Some(
                    stored.clone()
                )))
                .unwrap()
                .is_empty()
            );
        }
        assert_eq!(
            credential_display_state(
                &cache,
                &credential_cache::CredentialKey::new("fixture-provider", scope)
            ),
            (true, "ready")
        );
    }

    #[test]
    fn cancelled_credential_reads_stay_blocked_until_explicit_settings_retry() {
        let cache = credential_cache::CredentialCache::default();
        let account = "fixture-denied-provider";
        let scope = "openai|https://example.invalid";
        let key = credential_cache::CredentialKey::new(account, scope);
        let attempts = std::cell::Cell::new(0);
        for _ in 0..10 {
            assert!(cached_credential(&cache, account, scope, || {
                attempts.set(attempts.get() + 1);
                Err("fixture-user-cancelled".into())
            })
            .is_err());
            assert_eq!(credential_display_state(&cache, &key), (false, "blocked"));
        }
        assert_eq!(attempts.get(), 1);
        retry_unavailable_credential(&cache, &key).unwrap();
        let stored = encode_credential(scope.into(), "fixture-after-retry".into()).unwrap();
        assert_eq!(
            cached_credential(&cache, account, scope, || {
                attempts.set(attempts.get() + 1);
                Ok(Some(stored))
            })
            .unwrap(),
            "fixture-after-retry"
        );
        assert_eq!(attempts.get(), 2);
        retry_unavailable_credential(&cache, &key).unwrap();
        assert_eq!(
            cached_credential(&cache, account, scope, || panic!(
                "ready credential must not be re-read"
            ))
            .unwrap(),
            "fixture-after-retry"
        );
    }

    #[test]
    fn cancelled_queued_account_read_never_reaches_the_os_loader() {
        use std::sync::{Arc, Barrier};
        let gate = Arc::new(Mutex::new(()));
        let requests = Arc::new(translation_requests::TranslationRequests::default());
        let epoch = requests.resume(None).unwrap().epoch;
        let ticket = requests.begin(epoch).unwrap();
        let held = gate.lock().unwrap();
        let started = Arc::new(Barrier::new(2));
        let worker = {
            let gate = gate.clone();
            let requests = requests.clone();
            let started = started.clone();
            std::thread::spawn(move || {
                started.wait();
                serialized_credential_read(
                    &gate,
                    || requests.is_current(ticket),
                    || panic!("cancelled queued credential must not start OS authentication"),
                )
            })
        };
        started.wait();
        requests.cancel(Some(ticket)).unwrap();
        drop(held);
        let result: Result<(), String> = worker.join().unwrap();
        assert_eq!(result.unwrap_err(), translation_requests::CANCELLED);
    }

    #[test]
    fn settings_changes_invalidate_only_removed_or_rebound_credential_accounts() {
        let old = Settings::default();
        let mut next = old.clone();
        let provider = next
            .providers
            .iter_mut()
            .find(|p| p.kind == "openai")
            .unwrap();
        let account = provider.id.clone();
        provider.name = "renamed".into();
        provider.model = "another-model".into();
        provider.base_url = "https://api.openai.com/v9".into();
        assert!(changed_credential_accounts(&old, &next).is_empty());
        next.providers
            .iter_mut()
            .find(|p| p.id == account)
            .unwrap()
            .base_url = "https://other.invalid/v1".into();
        assert_eq!(
            changed_credential_accounts(&old, &next),
            vec![account.clone()]
        );
        next.providers.retain(|p| p.id != account);
        assert_eq!(changed_credential_accounts(&old, &next), vec![account]);
    }

    #[test]
    fn selection_support_dump_requires_exact_opt_in_and_has_no_capture_payload() {
        let args = |items: &[&str]| {
            items
                .iter()
                .map(|item| item.to_string())
                .collect::<Vec<_>>()
        };
        assert!(selection_diagnostics_requested(&args(&[
            "EchoLingo",
            "--selection-diagnostics"
        ])));
        for items in [
            vec!["EchoLingo"],
            vec!["--selection-diagnostics"],
            vec!["EchoLingo", "--selection-diagnostics=/tmp/elsewhere"],
            vec!["EchoLingo", "selection-diagnostics"],
        ] {
            assert!(!selection_diagnostics_requested(&args(&items)));
        }
        let metadata = serde_json::json!({"available": false});
        let payload = selection_diagnostic_payload(metadata.clone());
        assert_eq!(payload["diagnostics"], metadata);
        assert_eq!(payload["diagnostic"], "last-selection-attempt");
        assert_eq!(payload["processId"], std::process::id());
        let fields: std::collections::BTreeSet<_> = payload
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect();
        assert_eq!(
            fields,
            [
                "diagnostic",
                "recordedAtUnixMs",
                "appVersion",
                "processId",
                "executablePath",
                "diagnostics"
            ]
            .into_iter()
            .collect()
        );
    }

    #[test]
    fn permission_diagnostics_require_an_exact_explicit_launch_flag() {
        for args in [
            vec!["EchoLingo", "--permission-diagnostics"],
            vec!["EchoLingo", "other", "--permission-diagnostics"],
        ] {
            assert!(permission_diagnostics_requested(
                &args.into_iter().map(String::from).collect::<Vec<_>>()
            ));
        }
        for args in [
            vec!["EchoLingo"],
            vec!["--permission-diagnostics"],
            vec!["EchoLingo", "--permission-diagnostics=other-path"],
            vec!["EchoLingo", "permission-diagnostics"],
        ] {
            assert!(!permission_diagnostics_requested(
                &args.into_iter().map(String::from).collect::<Vec<_>>()
            ));
        }
    }

    #[test]
    fn permission_diagnostic_contains_only_support_metadata_and_permission_status() {
        let permissions = serde_json::json!({
            "platform":"macos", "supported":true, "identity":"application-process",
            "bundleIdentifier":"io.github.blueeeecho.echolingo", "runningBundledApp":true,
            "processId":std::process::id(), "accessibilityGranted":false, "screenCaptureGranted":false
        });
        let payload = permission_diagnostic_payload(permissions.clone());
        assert_eq!(payload["permissions"], permissions);
        assert_eq!(payload["processId"], std::process::id());
        assert!(payload["recordedAtUnixMs"].as_u64().unwrap() > 0);
        let fields: std::collections::BTreeSet<_> = payload
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect();
        assert_eq!(
            fields,
            [
                "diagnostic",
                "recordedAtUnixMs",
                "appVersion",
                "processId",
                "executablePath",
                "permissions"
            ]
            .into_iter()
            .collect()
        );
    }

    #[test]
    fn stale_outside_click_cannot_hide_management_or_a_reopened_popup() {
        let requests = translation_requests::TranslationRequests::default();
        let old_popup = requests.resume(None).unwrap();
        assert!(should_hide_observed_popup(
            old_popup, old_popup, true, true, false
        ));
        assert!(!should_hide_observed_popup(
            old_popup, old_popup, true, true, true
        ));
        assert!(!should_hide_observed_popup(
            old_popup, old_popup, true, false, false
        ));
        assert!(!should_hide_observed_popup(
            old_popup, old_popup, false, true, false
        ));
        let settings_request = requests.suspend().unwrap();
        let management =
            prepare_management_presentation(&requests, settings_request.epoch, true).unwrap();
        assert!(!should_hide_observed_popup(
            old_popup, management, false, true, false
        ));
        // A subsequent translation has popup layout again, but belongs to a
        // newer presentation than the click the watcher originally observed.
        let hidden = requests.suspend().unwrap();
        let next_popup = requests.resume(Some(hidden.epoch)).unwrap();
        assert!(!should_hide_observed_popup(
            old_popup, next_popup, true, true, false
        ));
    }

    #[tokio::test]
    async fn pinned_native_tasks_cancel_old_work_without_hiding_or_reopening_the_popup() {
        let requests = translation_requests::TranslationRequests::default();
        let mut popup = requests.resume(None).unwrap();
        for action in ["silentOcr", "silentOcr", "capture", "ocr", "selection"] {
            let old_request = requests.begin(popup.epoch).unwrap();
            let keep = should_keep_native_popup(popup, true, true, true);
            assert!(keep);
            let next = begin_native_action_presentation(&requests, keep).unwrap();
            assert!(
                next.presented,
                "{action} must keep the pinned popup presented"
            );
            assert!(next.epoch > popup.epoch);
            assert_eq!(
                requests.begin(popup.epoch).unwrap_err(),
                translation_requests::CANCELLED
            );
            assert_eq!(
                requests.execute(old_request, async {}).await.unwrap_err(),
                translation_requests::CANCELLED
            );
            assert!(!requests
                .publish(old_request, |_| panic!("old progress survived OCR"))
                .unwrap());
            assert!(requests.finish(old_request, || Ok(())).is_err());
            // A cancelled/failed capture leaves this presentation alone. A
            // successful source's show_popup is an idempotent resume, so it
            // cannot add a hidden/reopened transition or focus the window.
            assert_eq!(requests.presentation().unwrap(), next);
            assert_eq!(requests.resume(Some(next.epoch)).unwrap(), next);
            assert!(!popup_needs_native_show(true, true, true, true));
            let current = requests.begin(next.epoch).unwrap();
            assert_eq!(
                requests
                    .execute(current, async { "new OCR" })
                    .await
                    .unwrap(),
                "new OCR"
            );
            assert_eq!(
                requests.finish(current, || Ok("new result")).unwrap(),
                "new result"
            );
            popup = next;
        }
        // A real close remains authoritative, even if OCR has not returned.
        let hidden = requests.suspend().unwrap();
        assert!(!hidden.presented);
        assert_eq!(
            requests.resume(Some(popup.epoch)).unwrap_err(),
            translation_requests::CANCELLED
        );
    }

    #[test]
    fn native_initial_publication_cannot_advance_a_newer_requests_epoch() {
        let controller = native_tasks::Controller::default();
        let requests = translation_requests::TranslationRequests::default();
        requests.resume(None).unwrap();
        let old = controller.begin().unwrap();
        let latest = controller.begin().unwrap();
        let announced = Mutex::new(Vec::new());
        let current = begin_native_request_presentation(
            &controller,
            &latest,
            &requests,
            true,
            |presentation| announced.lock().unwrap().push(presentation),
        )
        .unwrap()
        .unwrap();
        // Reproduce an earlier callback resuming after the newer request has
        // already published. It may neither suspend nor announce another epoch.
        assert!(begin_native_request_presentation(
            &controller,
            &old,
            &requests,
            false,
            |_| panic!("stale initial presentation was announced"),
        )
        .is_none());
        assert_eq!(requests.presentation().unwrap(), current);
        assert_eq!(*announced.lock().unwrap(), vec![current]);
        assert!(controller.is_current(&latest));
    }
    #[test]
    fn native_cancel_preserves_only_clipboard_restoration_safety_notices() {
        for error in [
            "CLIPBOARD_RESTORE_FAILED: Generated original formats unavailable",
            "CLIPBOARD_RESTORE_SKIPPED: Generated copy completion uncertain",
        ] {
            let result = finish_native_text::<String>(Err(error.into()), true);
            assert_eq!(result.unwrap_err(), error);
            let notice = clipboard_restoration_notice(error).unwrap();
            assert!(
                !notice.contains("Generated"),
                "do not expose native details"
            );
        }
        for error in [
            "CLIPBOARD_CHANGED: A newer user copy was preserved",
            "CLIPBOARD_UNAVAILABLE: Generated fixture",
            "CLIPBOARD_RESTORE_FAILED_SUFFIX: Not a restoration failure",
            "NATIVE_CANCEL_SIGNAL: Generated fixture",
            "CANCELLED: Generated fixture",
            "HTTP 503",
        ] {
            assert!(clipboard_restoration_notice(error).is_none());
            assert_eq!(
                finish_native_text::<String>(Err(error.into()), true).unwrap_err(),
                translation_requests::CANCELLED
            );
            assert_eq!(
                finish_native_text::<String>(Err(error.into()), false).unwrap_err(),
                error
            );
        }
        assert_eq!(
            finish_native_text(Ok("old source"), true).unwrap_err(),
            translation_requests::CANCELLED
        );
        assert_eq!(
            finish_native_text(Ok("new source"), false).unwrap(),
            "new source"
        );
    }
    #[test]
    fn pin_retention_applies_only_to_an_already_visible_translation_popup() {
        let requests = translation_requests::TranslationRequests::default();
        let hidden = requests.presentation().unwrap();
        assert!(!should_keep_native_popup(hidden, true, true, true));
        let popup = requests.resume(None).unwrap();
        assert!(should_keep_native_popup(popup, true, true, true));
        for (layout, visible, pinned) in [
            (false, true, true),
            (true, false, true),
            (true, true, false),
        ] {
            assert!(!should_keep_native_popup(popup, layout, visible, pinned));
        }
        assert!(
            !begin_native_action_presentation(&requests, false)
                .unwrap()
                .presented
        );
        assert!(popup_needs_native_show(true, false, true, true));
        assert!(popup_needs_native_show(true, true, false, true));
        assert!(popup_needs_native_show(true, false, false, true));
        for action in ["silentOcr", "capture", "ocr"] {
            assert!(is_capture_action(action));
        }
        for action in ["selection", "clipboard", "input"] {
            assert!(!is_capture_action(action));
        }
    }

    #[test]
    fn retained_native_sources_replace_success_without_turning_pin_into_content_lock() {
        for action in [
            "silentOcr",
            "selection",
            "silentOcr",
            "selection",
            "clipboard",
        ] {
            let payload = captured_source_payload(action, format!("generated {action}"), 8, true);
            assert_eq!(payload["text"], format!("generated {action}"));
            assert_eq!(payload["updateVisiblePopup"], true);
            assert_eq!(payload["reuseVisiblePopup"], is_capture_action(action));
            assert_eq!(payload["presentationEpoch"], 8);
            if is_capture_action(action) {
                assert_eq!(payload["captureOrigin"], "ocr");
            } else {
                assert!(payload.get("captureOrigin").is_none());
            }
            let unpinned = captured_source_payload(action, "new generated source".into(), 9, false);
            assert_eq!(unpinned["updateVisiblePopup"], false);
            assert_eq!(unpinned["reuseVisiblePopup"], false);
        }
    }
    #[tokio::test]
    async fn superseded_cloud_ocr_is_dropped_and_cannot_start_a_cancelled_request() {
        use std::sync::atomic::AtomicUsize;
        struct Cleanup(Arc<AtomicBool>);
        impl Drop for Cleanup {
            fn drop(&mut self) {
                self.0.store(true, Ordering::SeqCst);
            }
        }
        let cancelled = Arc::new(AtomicBool::new(false));
        let dropped = Arc::new(AtomicBool::new(false));
        let started = Arc::new(AtomicUsize::new(0));
        let (ready, entered) = tokio::sync::oneshot::channel();
        let worker = {
            let cancel = cancelled.clone();
            let dropped = dropped.clone();
            let started = started.clone();
            tokio::spawn(async move {
                native_ocr_result(cancel, async move {
                    let _cleanup = Cleanup(dropped);
                    started.fetch_add(1, Ordering::SeqCst);
                    let _ = ready.send(());
                    std::future::pending::<Result<(), String>>().await
                })
                .await
            })
        };
        entered.await.unwrap();
        cancelled.store(true, Ordering::SeqCst);
        let result = tokio::time::timeout(Duration::from_secs(1), worker)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(result.unwrap_err(), translation_requests::CANCELLED);
        assert!(dropped.load(Ordering::SeqCst));
        assert_eq!(started.load(Ordering::SeqCst), 1);
        let result = native_ocr_result(cancelled, async {
            started.fetch_add(1, Ordering::SeqCst);
            Ok(())
        })
        .await;
        assert_eq!(result.unwrap_err(), translation_requests::CANCELLED);
        assert_eq!(
            started.load(Ordering::SeqCst),
            1,
            "cancelled work must not poll/send another request"
        );
    }

    #[test]
    fn action_hint_is_bound_to_its_source_identity_not_an_independent_event() {
        let source = empty_selection_payload(42);
        let plain = source_with_action_error(source.clone(), None);
        assert_eq!(plain, source);
        let hinted = source_with_action_error(
            source,
            Some("COPY_NO_UPDATE: copied text unavailable".into()),
        );
        assert_eq!(hinted["presentationEpoch"], 42);
        assert_eq!(hinted["focusInput"], true);
        assert_eq!(
            hinted["actionError"],
            "COPY_NO_UPDATE: copied text unavailable"
        );
    }

    #[test]
    fn ordinary_shortcuts_raise_even_visible_popups_and_only_pinned_ocr_can_reuse() {
        for pinned in [false, true] {
            for visible in [false, true] {
                assert!(popup_needs_native_show(false, visible, true, pinned));
            }
        }
        assert!(popup_needs_native_show(true, true, true, false));
        assert!(popup_needs_native_show(true, false, true, true));
        assert!(popup_needs_native_show(true, true, false, true));
        assert!(!popup_needs_native_show(true, true, true, true));
    }

    #[test]
    fn retained_capture_cannot_replace_management_or_a_later_presentation() {
        let requests = translation_requests::TranslationRequests::default();
        requests.resume(None).unwrap();
        let capture = begin_native_action_presentation(&requests, true).unwrap();
        assert!(retained_capture_result_is_current(
            capture,
            Some(capture),
            true,
            true
        ));
        // In-popup Settings/history navigation may keep its epoch; the layout
        // check still rejects a cloud OCR completion in that management view.
        assert!(!retained_capture_result_is_current(
            capture,
            Some(capture),
            true,
            false
        ));
        let closed = requests.suspend().unwrap();
        assert!(!retained_capture_result_is_current(
            capture,
            Some(closed),
            true,
            true
        ));
        let reopened = requests.resume(Some(closed.epoch)).unwrap();
        assert!(!retained_capture_result_is_current(
            capture,
            Some(reopened),
            true,
            true
        ));
        assert!(!retained_capture_result_is_current(
            capture, None, true, true
        ));
        // A new explicit non-retained shortcut may leave management normally.
        assert!(retained_capture_result_is_current(
            reopened,
            Some(reopened),
            false,
            false
        ));
    }

    #[test]
    fn tray_dispatch_ignores_unrelated_application_menu_events() {
        for action in [
            "selection",
            "capture",
            "ocr",
            "silentOcr",
            "input",
            "clipboard",
        ] {
            assert!(is_native_action(action));
        }
        for action in ["app-settings", "settings", "quit", "copy", "about", ""] {
            assert!(!is_native_action(action));
        }
    }

    #[test]
    fn pending_settings_recovery_is_epoch_bound_and_cold_start_is_silent() {
        let requests = translation_requests::TranslationRequests::default();
        assert_eq!(
            pending_settings_event(None, requests.presentation().unwrap()),
            None
        );
        let pending = requests.suspend().unwrap();
        let event = pending_settings_event(Some(pending.epoch), pending).unwrap();
        assert_eq!(
            serde_json::to_value(event).unwrap(),
            serde_json::json!({ "presentationEpoch": pending.epoch })
        );
        // Listener startup can recover the same request, while a later hide or
        // selection supersedes it even if the frontend has not handled it yet.
        assert_eq!(
            pending_settings_event(Some(pending.epoch), pending),
            Some(event)
        );
        let replacement = requests.suspend().unwrap();
        assert_eq!(
            pending_settings_event(Some(pending.epoch), replacement),
            None
        );
    }

    #[test]
    fn management_show_requires_prepared_layout_and_current_presentation() {
        let requests = translation_requests::TranslationRequests::default();
        let pending = requests.suspend().unwrap();
        assert!(
            prepare_management_presentation(&requests, pending.epoch, false)
                .unwrap_err()
                .starts_with("MANAGEMENT_NOT_READY:")
        );
        assert_eq!(requests.presentation().unwrap(), pending);
        assert_eq!(
            prepare_management_presentation(&requests, pending.epoch - 1, true).unwrap_err(),
            translation_requests::CANCELLED
        );
        let presented = prepare_management_presentation(&requests, pending.epoch, true).unwrap();
        assert!(presented.presented);
        assert!(presented.epoch > pending.epoch);
        assert_eq!(pending_settings_event(Some(pending.epoch), presented), None);
        requests.suspend().unwrap();
        assert_eq!(
            prepare_management_presentation(&requests, presented.epoch, true).unwrap_err(),
            translation_requests::CANCELLED
        );
    }

    #[test]
    fn history_uses_current_privacy_and_cancelled_requests_cannot_repopulate_it() {
        let directory = std::env::temp_dir().join(format!(
            "echolingo-history-fixture-{}-{}",
            std::process::id(),
            now()
        ));
        fs::create_dir_all(&directory).unwrap();
        let state = AppState {
            settings: Mutex::new(Settings::default()),
            credentials: credential_cache::CredentialCache::default(),
            credential_reads: Mutex::new(()),
            history: Mutex::new(vec![]),
            pinned: AtomicBool::new(false),
            native_tasks: native_tasks::Controller::default(),
            shortcut_gate: Mutex::new(shortcut_control::ShortcutGate::default()),
            shortcut_routes: shortcut_control::ShortcutRoutes::default(),
            shortcut_updating: AtomicBool::new(false),
            shortcut_maintenance: shortcut_control::ShortcutMaintenance::default(),
            registered_shortcuts: Mutex::new(Vec::new()),
            shortcut_failures: Mutex::new(std::collections::BTreeMap::new()),
            translation_busy: tokio::sync::Semaphore::new(2),
            translation_requests: translation_requests::TranslationRequests::default(),
            data_dir: directory.clone(),
            client: reqwest::Client::new(),
            update_notice: update_notice::Controller::new(directory.join("update-notice.json")),
            offline: offline_translation::OfflineTranslation::new(
                directory.join("offline-translation"),
            ),
            startup_warnings: Mutex::new(vec![]),
            outside_thread: Mutex::new(None),
            pending_settings: Mutex::new(None),
            source_deliveries: Mutex::new(source_delivery::SourceDeliveries::default()),
            pending_shortcut_settings: AtomicBool::new(false),
            popup_health: Mutex::new(popup_health::PopupHealth::default()),
        };
        let result = vec![
            TranslationResult {
                preserved: false,
                provider_id: "fixture".into(),
                provider_name: "fixture".into(),
                text: "fixture translation".into(),
                error: None,
                elapsed_ms: 1,
                resolved_languages: None,
            },
            TranslationResult {
                preserved: false,
                provider_id: "system-fixture".into(),
                provider_name: "System fixture".into(),
                text: String::new(),
                error: Some("SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: fixture".into()),
                elapsed_ms: 1,
                resolved_languages: Some(ResolvedLanguages {
                    source_language: "zh-Hant".into(),
                    target_language: "en".into(),
                }),
            },
        ];
        let finish = |id| {
            finish_translation(
                &state,
                id,
                "fixture source".into(),
                "en".into(),
                "zh-Hans".into(),
                &result,
            )
        };
        let epoch = state.translation_requests.resume(None).unwrap().epoch;
        let old = state.translation_requests.begin(epoch).unwrap();
        state.settings.lock().unwrap().save_history = false;
        finish(old).unwrap();
        assert!(state.history.lock().unwrap().is_empty());
        assert!(!directory.join("history.json").exists());
        state.settings.lock().unwrap().save_history = true;
        let cancelled = state.translation_requests.begin(epoch).unwrap();
        state.translation_requests.cancel(None).unwrap();
        assert!(finish(cancelled).is_err());
        assert!(!directory.join("history.json").exists());
        let accepted = state.translation_requests.begin(epoch).unwrap();
        finish(accepted).unwrap();
        assert_eq!(state.history.lock().unwrap().len(), 1);
        let saved: Vec<HistoryEntry> =
            serde_json::from_slice(&fs::read(directory.join("history.json")).unwrap()).unwrap();
        assert_eq!(saved[0].text, "fixture source");
        assert_eq!(saved[0].results.len(), 2);
        assert!(saved[0].results[1].resolved_languages.is_none());
        assert!(result[1].resolved_languages.is_some());
        assert!(!fs::read_to_string(directory.join("history.json"))
            .unwrap()
            .contains("resolvedLanguages"));
        fs::remove_dir_all(directory).unwrap();
    }
    #[test]
    fn shortcut_failures_explain_conflicts_and_only_permanent_errors_skip_retry() {
        assert_eq!(
            friendly_shortcut_error("selection（Alt+D）：系统注册失败：AlreadyRegistered"),
            "系统报告该组合键已被注册。可更换快捷键，或释放占用后等待自动重试。"
        );
        assert!(
            friendly_shortcut_error("Windows 为调试器保留 F12，请选择其他按键").contains("保留")
        );
        assert_eq!(
            shortcut_registration_message(false, None).as_deref(),
            Some("快捷键没有注册成功，可能被其他程序占用。")
        );
        assert_eq!(shortcut_registration_message(true, Some("占用")), None);
        let settings = Settings::default();
        let mut failures = std::collections::BTreeMap::new();
        failures.insert("selection".into(), "AlreadyRegistered".into());
        failures.insert("input".into(), "Windows 为调试器保留 F12".into());
        let actions = inactive_retry_actions(&settings, &[], &failures, |_| true).unwrap();
        assert!(actions.contains(&"selection".to_string()));
        assert!(actions.contains(&"silentOcr".to_string()));
        assert!(!actions.contains(&"input".to_string()));
        assert!(inactive_retry_actions(&settings, &[], &failures, |_| false)
            .unwrap()
            .iter()
            .any(|action| action == "silentOcr"));
    }
    #[test]
    fn shortcut_startup_history_keeps_routing_errors_without_stale_binding_failures() {
        assert_eq!(
            non_binding_installation_error("binding failed", "binding failed"),
            None
        );
        assert_eq!(
            non_binding_installation_error("binding failed；routing failed", "binding failed"),
            Some("routing failed".into())
        );
        assert_eq!(
            non_binding_installation_error("parse failed", ""),
            Some("parse failed".into())
        );
    }

    #[test]
    fn shortcut_diagnostics_clear_recovered_and_removed_startup_failures() {
        let mut settings = Settings::default();
        settings.shortcuts.input = "Alt+A".into();
        let bindings = parsed_shortcuts(&settings.shortcuts).unwrap();
        let registered: Vec<_> = bindings.iter().map(|(_, binding)| *binding).collect();
        let mut failures = std::collections::BTreeMap::new();
        failures.insert("input".into(), "HotKey already registered".into());
        let failed = shortcut_registration_snapshot(&settings, &[], &failures, |_| true).unwrap();
        assert!(current_shortcut_warnings(&failed)
            .iter()
            .any(|warning| warning.starts_with("input（Alt+A）") && warning.contains("已被注册")));
        // Recovery must override even a stale stored message.
        let recovered =
            shortcut_registration_snapshot(&settings, &registered, &failures, |_| true).unwrap();
        assert!(current_shortcut_warnings(&recovered).is_empty());
        assert!(recovered
            .iter()
            .all(|item| item["active"] == true && item["error"].is_null()));
        settings.shortcuts.input.clear();
        let removed = shortcut_registration_snapshot(&settings, &[], &failures, |_| true).unwrap();
        assert!(removed.iter().all(|item| item["action"] != "input"));
        assert!(!current_shortcut_warnings(&removed)
            .iter()
            .any(|warning| warning.contains("Alt+A")));
    }

    #[test]
    fn shortcut_diagnostics_distinguish_registered_id_from_live_native_hook() {
        let settings = Settings::default();
        let bindings = parsed_shortcuts(&settings.shortcuts).unwrap();
        let registered: Vec<_> = bindings.iter().map(|(_, binding)| *binding).collect();
        let failures = std::collections::BTreeMap::new();
        let inactive =
            shortcut_registration_snapshot(&settings, &registered, &failures, |_| false).unwrap();
        assert_eq!(current_shortcut_warnings(&inactive).len(), registered.len());
        assert!(inactive
            .iter()
            .all(|item| item["active"] == false && item["error"].is_string()));
    }

    #[test]
    fn tiny_or_timed_out_region_capture_tells_the_user_how_to_drag() {
        assert_eq!(
            visible_action_error(
                "silentOcr",
                "CANCELLED: 框选区域太小；请按住左键拖动选择区域。"
            )
            .as_deref(),
            Some("请按住左键拖选要识别的区域。Esc 或右键取消。")
        );
        assert_eq!(
            visible_action_error("capture", "CANCELLED: 截图操作超时，已取消。").as_deref(),
            Some("请按住左键拖选要识别的区域。Esc 或右键取消。")
        );
        assert_eq!(
            visible_action_error(
                "silentOcr",
                "CANCELLED: Screenshot selection was cancelled (Escape, right click, display change, or 120-second timeout)."
            ),
            None
        );
        let hint = action_failure_presentation(
            "silentOcr",
            "CANCELLED: 框选区域太小；请按住左键拖动选择区域。",
            3,
        )
        .unwrap();
        assert_eq!(hint.source["mode"], "input");
        assert!(hint.error.unwrap().contains("拖选"));
    }
    #[test]
    fn copy_without_clipboard_update_remains_actionable_through_selection_presentation() {
        let error = "COPY_NO_UPDATE: The target did not update the clipboard";
        assert_eq!(visible_action_error("selection", error), Some(error.into()));
        let failure = action_failure_presentation("selection", error, 44).unwrap();
        assert_eq!(failure.source, empty_selection_payload(44));
        assert_eq!(failure.error.as_deref(), Some(error));
        assert_eq!(
            finish_native_text::<String>(Err(error.into()), false),
            Err(error.into())
        );
        assert_eq!(
            finish_native_text::<String>(Err(error.into()), true),
            Err(translation_requests::CANCELLED.into())
        );
    }
    #[test]
    fn unverifiable_selection_retains_manual_copy_guidance_without_permission_claim() {
        let error = "SELECTION_UNAVAILABLE: Native provider did not expose selection evidence";
        let failure = action_failure_presentation("selection", error, 45).unwrap();
        assert_eq!(failure.source, empty_selection_payload(45));
        assert_eq!(failure.error.as_deref(), Some(error));
        assert!(failure.source.get("permissionRequired").is_none());
    }
    #[test]
    fn empty_selection_is_quiet_but_other_actions_keep_actionable_errors() {
        for error in [
            "NO_SELECTION: Nothing selected",
            "PERMISSION: Accessibility is not granted",
            "SELECTION: Foreground changed",
            "NATIVE_START: Helper unavailable",
            "CLIPBOARD_CHANGED: A newer user copy was preserved",
        ] {
            assert_eq!(visible_action_error("selection", error), None);
        }
        assert_eq!(
            visible_action_error("capture", "CANCELLED: User cancelled"),
            None
        );
        assert_eq!(
            visible_action_error("capture", "PERMISSION: Screen capture is not granted"),
            Some("Screen capture is not granted".into())
        );
        assert!(visible_action_error(
            "selection",
            "CLIPBOARD_RESTORE_FAILED: Original formats unavailable"
        )
        .is_some());
        assert!(visible_action_error(
            "selection",
            "CLIPBOARD_RESTORE_SKIPPED: Copy completion is uncertain"
        )
        .is_some());
    }
    #[test]
    fn empty_ocr_is_blank_quiet_and_does_not_focus_or_translate() {
        for action in ["capture", "ocr", "silentOcr"] {
            let error = "NO_TEXT: No text was recognized";
            assert_eq!(visible_action_error(action, error), None);
            let failed = action_failure_presentation(action, error, 42).unwrap();
            assert_eq!(failed.error, None);
            assert_eq!(failed.source["text"], "");
            assert_eq!(failed.source["mode"], "input");
            for retained in [false, true] {
                let payload = empty_ocr_payload(42, retained);
                assert_eq!(payload["text"], "");
                assert_eq!(payload["mode"], "input");
                assert_eq!(payload["captureOrigin"], "ocr");
                assert_eq!(payload["presentationEpoch"], 42);
                assert_eq!(payload["updateVisiblePopup"], retained);
                assert_eq!(payload["reuseVisiblePopup"], retained);
                for key in ["actionError", "permissionRequired", "focusInput"] {
                    assert!(payload.get(key).is_none());
                }
            }
        }
        assert!(visible_action_error("clipboard", "NO_TEXT: unrelated failure").is_some());
        for error in [
            "OCR: provider request failed",
            "PERMISSION: screen capture denied",
            "CLIPBOARD_RESTORE_FAILED: preserve warning",
        ] {
            assert!(visible_action_error("ocr", error).is_some());
        }
        assert!(action_failure_presentation("ocr", "CANCELLED: user cancelled", 42).is_none());
    }
    #[test]
    fn blocked_capture_presents_permission_guidance_in_one_source_event() {
        for action in ["capture", "ocr", "silentOcr"] {
            for error in [
                "PERMISSION: Screen capture is not granted",
                "PERMISSION: 请在 EchoLingo 设置中开启屏幕录制权限后重试；系统可能要求重新打开应用。",
            ] {
                let failure = action_failure_presentation(action, error, 42).unwrap();
                assert_eq!(
                    failure.source,
                    serde_json::json!({
                        "text":"",
                        "mode":"input",
                        "presentationEpoch":42,
                        "permissionRequired":"screenCapture"
                    })
                );
                // A second action-error event could arrive after presentation
                // and turn this actionable view back into a transient toast.
                assert_eq!(failure.error, None);
            }
        }
    }
    #[test]
    fn action_failure_guidance_preserves_quiet_selection_cancel_and_real_errors() {
        for action in ["selection", "capture", "ocr", "silentOcr"] {
            assert!(action_failure_presentation(action, "CANCELLED: User cancelled", 7).is_none());
        }
        let unavailable =
            action_failure_presentation("selection", "PERMISSION: Accessibility is not granted", 7)
                .unwrap();
        let mut expected = empty_selection_payload(7);
        if cfg!(target_os = "macos") {
            expected["permissionRequired"] = serde_json::json!("accessibility");
        }
        assert_eq!(unavailable.source, expected);
        assert_eq!(unavailable.error, None);

        let restoration = action_failure_presentation(
            "selection",
            "CLIPBOARD_RESTORE_FAILED: Original formats unavailable",
            8,
        )
        .unwrap();
        assert_eq!(restoration.source, empty_selection_payload(8));
        assert!(restoration.error.unwrap().contains("剪贴板恢复失败"));
        let skipped = action_failure_presentation(
            "selection",
            "CLIPBOARD_RESTORE_SKIPPED: Copy completion is uncertain",
            8,
        )
        .unwrap();
        assert_eq!(skipped.source, empty_selection_payload(8));
        assert!(skipped.error.unwrap().contains("暂未恢复原剪贴板"));
        for (action, error) in [
            ("capture", "OCR 服务返回 HTTP 403，请检查服务凭据或额度"),
            ("silentOcr", "NATIVE_START: Helper unavailable"),
            ("clipboard", "PERMISSION: Clipboard unavailable"),
            ("ocr", "PERMISSION_SETTINGS: 无法打开系统设置"),
        ] {
            let failure = action_failure_presentation(action, error, 9).unwrap();
            assert_eq!(failure.source, empty_input_payload(9));
            assert!(failure.error.is_some());
        }
    }
    #[test]
    fn selection_accessibility_guidance_is_mac_only_and_atomic() {
        let failure = action_failure_presentation(
            "selection",
            "PERMISSION: Accessibility is not granted",
            42,
        )
        .unwrap();
        let mut expected = empty_selection_payload(42);
        if cfg!(target_os = "macos") {
            expected["permissionRequired"] = serde_json::json!("accessibility");
        }
        assert_eq!(failure.source, expected);
        assert_eq!(failure.error, None);
        assert_eq!(failure.source["focusInput"], true);
        assert_eq!(failure.source["presentationEpoch"], 42);
    }
    #[test]
    fn selection_nonpermission_failures_do_not_show_accessibility_guidance() {
        for error in [
            "NO_SELECTION: Nothing selected",
            "SELECTION: Foreground changed",
            "CLIPBOARD_CHANGED: A newer copy was preserved",
            "NATIVE_PROTOCOL: Native response was invalid",
            "PERMISSION_SETTINGS: Cannot open Settings",
            "permission: Not a native permission category",
            "NATIVE: PERMISSION: Embedded text is not a permission error",
        ] {
            let failure = action_failure_presentation("selection", error, 43).unwrap();
            assert_eq!(failure.source, empty_selection_payload(43), "{error}");
            assert_eq!(failure.error, None, "{error}");
        }
        assert!(action_failure_presentation(
            "selection",
            "CANCELLED: PERMISSION: A stale request was cancelled",
            43,
        )
        .is_none());
    }
    #[test]
    fn selection_permission_payload_cannot_resume_an_older_presentation() {
        let requests = translation_requests::TranslationRequests::default();
        let old = begin_native_action_presentation(&requests, false).unwrap();
        let failure = action_failure_presentation(
            "selection",
            "PERMISSION: Accessibility is not granted",
            old.epoch,
        )
        .unwrap();
        assert_eq!(failure.source["presentationEpoch"], old.epoch);
        let current = begin_native_action_presentation(&requests, false).unwrap();
        assert!(!retained_capture_result_is_current(
            old,
            Some(current),
            false,
            true,
        ));
        assert_eq!(
            requests.resume(Some(old.epoch)).unwrap_err(),
            translation_requests::CANCELLED,
        );
        assert_eq!(requests.presentation().unwrap(), current);
    }
    #[test]
    fn credentials_do_not_cross_protocols_or_supplier_origins() {
        let scope = credential_scope("openai", "https://API.EXAMPLE.com:443/v1").unwrap();
        let stored = encode_credential(scope.clone(), "fixture-only-secret".into()).unwrap();
        assert_eq!(
            decode_credential(&stored, &scope).unwrap(),
            "fixture-only-secret"
        );
        assert_eq!(
            scope,
            credential_scope("openai", "https://api.example.com/v2/").unwrap()
        );
        for other in [
            credential_scope("openai", "https://different.example.com/v1").unwrap(),
            credential_scope("deepl", "https://api.example.com/v1").unwrap(),
            credential_scope("openai", "https://api.example.com:8443/v1").unwrap(),
        ] {
            assert!(decode_credential(&stored, &other).unwrap().is_empty());
        }
        // Unscoped development credentials must be re-entered, never guessed.
        assert!(decode_credential("old-unscoped-secret", &scope).is_err());
    }
    #[test]
    fn new_official_credentials_separate_translation_and_ocr_legacy_id_collisions() {
        let mt: Provider = serde_json::from_value(serde_json::json!({"id":"ocr-x-youdao","name":"MT fixture","kind":"youdao","baseUrl":"https://openapi.youdao.com/api","enabled":true})).unwrap();
        let image: ocr::OcrProvider = serde_json::from_value(serde_json::json!({"id":"x","name":"OCR fixture","kind":"youdao","baseUrl":"https://openapi.youdao.com/ocrapi","model":"general"})).unwrap();
        let mut settings = Settings {
            providers: vec![mt.clone()],
            ocr_providers: vec![image.clone()],
            ..Settings::default()
        };
        assert!(validate_settings(&settings).is_ok());
        // This valid pair collided under the former account and scope rules.
        assert_eq!(mt.id, format!("ocr-{}-{}", image.id, image.kind));
        assert_eq!(
            credential_scope(&mt.kind, &mt.base_url).unwrap(),
            credential_scope(&image.kind, &image.base_url).unwrap()
        );
        assert_eq!(
            translation_secret_id(&mt),
            "translation:youdao:ocr-x-youdao"
        );
        assert_eq!(ocr_secret_id(&image), "ocr:youdao:x");
        let mt_scope = translation_credential_scope(&mt).unwrap();
        let image_scope = ocr_credential_scope(&image).unwrap();
        assert_ne!(mt_scope, image_scope);
        let stored = encode_credential(mt_scope, "dummy-translation-secret".into()).unwrap();
        assert!(decode_credential(&stored, &image_scope).unwrap().is_empty());

        let cache = credential_cache::CredentialCache::default();
        let mt_key = translation_credential_key(&mt).unwrap();
        let image_key = ocr_credential_key(&image).unwrap();
        cache
            .store(&mt_key, Ok("dummy-translation-secret".into()))
            .unwrap();
        assert_eq!(
            credential_display_state(&cache, &image_key),
            (false, "unloaded")
        );
        cache
            .store(&image_key, Ok("dummy-ocr-secret".into()))
            .unwrap();
        let snapshot = settings_snapshot(&settings, &cache).unwrap();
        assert_eq!(snapshot["providers"][0]["credentialState"], "ready");
        assert_eq!(snapshot["ocrProviders"][0]["credentialState"], "ready");
        assert!(!snapshot.to_string().contains("dummy-"));
        let deletion = ocr_deletion_accounts(&image);
        assert_eq!(deletion, vec!["ocr:youdao:x"]);
        for account in deletion {
            cache.delete_account(&account, String::new()).unwrap();
        }
        assert_eq!(credential_display_state(&cache, &mt_key), (true, "ready"));
        assert_eq!(
            credential_display_state(&cache, &image_key),
            (false, "missing")
        );
        settings.providers[0].id = "translation:youdao:x".into();
        assert!(validate_settings(&settings).is_err());
    }
    #[test]
    fn new_official_credential_namespaces_cover_all_added_adapters() {
        for (kind, url) in [
            (
                "niutrans",
                "https://api.niutrans.com/NiuTransServer/translation",
            ),
            (
                "google-translate",
                "https://translation.googleapis.com/language/translate/v2",
            ),
            (
                "caiyun",
                "https://api.interpreter.caiyunai.com/v1/translator",
            ),
            (
                "baidu",
                "https://fanyi-api.baidu.com/api/trans/vip/translate",
            ),
            ("youdao", "https://openapi.youdao.com/api"),
            (
                "microsoft",
                "https://api.cognitive.microsofttranslator.com/",
            ),
        ] {
            let p: Provider = serde_json::from_value(serde_json::json!({"id":"qa-id","name":"Fixture","kind":kind,"baseUrl":url,"enabled":false})).unwrap();
            assert_eq!(
                translation_secret_id(&p),
                format!("translation:{kind}:qa-id")
            );
            assert_eq!(
                translation_credential_scope(&p).unwrap(),
                format!("translation|{}", credential_scope(kind, url).unwrap())
            );
            assert!(
                translation_credential_key(&p).unwrap()
                    == credential_cache::CredentialKey::new(
                        translation_secret_id(&p),
                        translation_credential_scope(&p).unwrap()
                    )
            );
        }
        for (kind, url) in [
            ("youdao", "https://openapi.youdao.com/ocrapi"),
            ("google", "https://vision.googleapis.com/v1/images:annotate"),
        ] {
            let p: ocr::OcrProvider = serde_json::from_value(
                serde_json::json!({"id":"qa-id","name":"Fixture","kind":kind,"baseUrl":url}),
            )
            .unwrap();
            let account = format!("ocr:{kind}:qa-id");
            assert_eq!(ocr_secret_id(&p), account);
            assert_eq!(
                ocr_credential_scope(&p).unwrap(),
                format!("ocr|{}", credential_scope(kind, url).unwrap())
            );
            assert_eq!(ocr_deletion_accounts(&p), vec![account]);
            assert!(
                ocr_credential_key(&p).unwrap()
                    == credential_cache::CredentialKey::new(
                        ocr_secret_id(&p),
                        ocr_credential_scope(&p).unwrap()
                    )
            );
        }
    }
    #[test]
    fn released_credential_accounts_and_scopes_keep_exact_compatibility() {
        for kind in ["openai", "deepl", "libretranslate"] {
            let p: Provider = serde_json::from_value(serde_json::json!({"id":"legacy-id","name":"Fixture","kind":kind,"baseUrl":"https://example.invalid/v1","enabled":false})).unwrap();
            assert_eq!(translation_secret_id(&p), "legacy-id");
            assert_eq!(
                translation_credential_scope(&p).unwrap(),
                format!("{kind}|https://example.invalid")
            );
        }
        for kind in ["openai-vision", "http-json", "baidu", "tencent"] {
            let p: ocr::OcrProvider = serde_json::from_value(serde_json::json!({"id":"legacy-id","name":"Fixture","kind":kind,"baseUrl":"https://example.invalid/v1"})).unwrap();
            assert_eq!(ocr_secret_id(&p), format!("ocr-legacy-id-{kind}"));
            assert_eq!(
                ocr_credential_scope(&p).unwrap(),
                format!("{kind}|https://example.invalid")
            );
            assert_eq!(
                ocr_deletion_accounts(&p),
                vec![
                    "ocr-legacy-id-openai-vision",
                    "ocr-legacy-id-http-json",
                    "ocr-legacy-id-baidu",
                    "ocr-legacy-id-tencent",
                    "ocr-legacy-id"
                ]
            );
        }
    }
    #[test]
    fn official_kind_changes_invalidate_the_previous_namespaced_accounts() {
        let mt: Provider = serde_json::from_value(serde_json::json!({"id":"qa","name":"MT fixture","kind":"youdao","baseUrl":"https://openapi.youdao.com/api","enabled":false})).unwrap();
        let image: ocr::OcrProvider = serde_json::from_value(serde_json::json!({"id":"qa","name":"OCR fixture","kind":"youdao","baseUrl":"https://openapi.youdao.com/ocrapi","model":"general"})).unwrap();
        let old = Settings {
            providers: vec![mt.clone()],
            ocr_providers: vec![image.clone()],
            ..Settings::default()
        };
        let mut next = old.clone();
        next.providers[0].name = "renamed".into();
        next.ocr_providers[0].name = "renamed".into();
        assert!(changed_credential_accounts(&old, &next).is_empty());
        next.providers[0].kind = "microsoft".into();
        next.providers[0].base_url = "https://api.cognitive.microsofttranslator.com/".into();
        next.ocr_providers[0].kind = "google".into();
        next.ocr_providers[0].base_url = "https://vision.googleapis.com/v1/images:annotate".into();
        next.ocr_providers[0].model = "TEXT_DETECTION".into();
        assert!(validate_settings(&next).is_ok());
        let accounts: std::collections::BTreeSet<_> = changed_credential_accounts(&old, &next)
            .into_iter()
            .collect();
        assert_eq!(
            accounts,
            std::collections::BTreeSet::from([
                "translation:youdao:qa".to_owned(),
                "ocr:youdao:qa".to_owned()
            ])
        );
        let cache = credential_cache::CredentialCache::default();
        let mt_key = translation_credential_key(&mt).unwrap();
        let image_key = ocr_credential_key(&image).unwrap();
        cache.store(&mt_key, Ok("dummy-mt".into())).unwrap();
        cache.store(&image_key, Ok("dummy-ocr".into())).unwrap();
        for account in accounts {
            cache.invalidate_account(&account).unwrap();
        }
        assert!(cache.peek(&mt_key).unwrap().is_none());
        assert!(cache.peek(&image_key).unwrap().is_none());
        assert_eq!(
            credential_display_state(
                &cache,
                &translation_credential_key(&next.providers[0]).unwrap()
            ),
            (false, "unloaded")
        );
        assert_eq!(
            credential_display_state(&cache, &ocr_credential_key(&next.ocr_providers[0]).unwrap()),
            (false, "unloaded")
        );
    }
    #[test]
    fn duplicate_shortcuts_are_rejected() {
        let mut s = Shortcuts::default();
        s.ocr = s.silent_ocr.clone();
        assert!(parsed_shortcuts(&s).is_err());
    }
    #[test]
    fn configure_shortcuts_is_an_explicit_exact_launch_argument() {
        assert!(!configure_shortcuts_requested(&["EchoLingo".into()]));
        assert!(!configure_shortcuts_requested(&[
            CONFIGURE_SHORTCUTS_FLAG.into()
        ]));
        assert!(!configure_shortcuts_requested(&[
            "EchoLingo".into(),
            "--configure-shortcuts=other".into()
        ]));
        assert!(configure_shortcuts_requested(&[
            "EchoLingo".into(),
            CONFIGURE_SHORTCUTS_FLAG.into()
        ]));
    }

    #[test]
    fn empty_shortcut_disables_action() {
        let mut s = Shortcuts::default();
        s.ocr = "Alt+Shift+S".into();
        let before = parsed_shortcuts(&s).unwrap().len();
        s.ocr.clear();
        assert_eq!(parsed_shortcuts(&s).unwrap().len(), before - 1);
    }
    #[test]
    fn settings_history_limit_is_immediate_durable_and_includes_favorites() {
        let directory = std::env::temp_dir().join(format!(
            "echolingo-settings-history-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&directory).unwrap();
        let entry = |id: &str, favorite| HistoryEntry {
            id: id.into(),
            text: "fixture source".into(),
            source_language: "en".into(),
            target_language: "zh-Hans".into(),
            results: vec![],
            created_at: 0,
            favorite,
        };
        let mut current = Settings::default();
        let mut history = vec![
            entry("new", false),
            entry("middle", false),
            entry("favorite", true),
        ];
        let mut changed = current.clone();
        changed.max_history = 2;
        persist_settings_and_history(&directory, &mut current, &mut history, changed).unwrap();
        assert_eq!(current.max_history, 2);
        assert_eq!(
            history
                .iter()
                .map(|entry| entry.id.as_str())
                .collect::<Vec<_>>(),
            ["new", "favorite"]
        );
        let saved: Vec<HistoryEntry> =
            serde_json::from_slice(&fs::read(directory.join("history.json")).unwrap()).unwrap();
        assert_eq!(
            saved
                .iter()
                .map(|entry| entry.id.as_str())
                .collect::<Vec<_>>(),
            ["new", "favorite"]
        );

        // Favorites stay available, but cannot exceed the owner's hard cap.
        history[0].favorite = true;
        let mut changed = current.clone();
        changed.max_history = 1;
        persist_settings_and_history(&directory, &mut current, &mut history, changed).unwrap();
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].id, "new");
        assert!(history[0].favorite);
        let saved_settings: Settings =
            serde_json::from_slice(&fs::read(directory.join("settings.json")).unwrap()).unwrap();
        assert_eq!(saved_settings.max_history, 1);
        let saved: Vec<HistoryEntry> =
            serde_json::from_slice(&fs::read(directory.join("history.json")).unwrap()).unwrap();
        assert_eq!(saved.len(), 1);
        assert_eq!(saved[0].id, "new");
        fs::remove_dir_all(directory).unwrap();
    }
    #[test]
    fn settings_history_write_failure_restores_settings_and_keeps_history() {
        let directory = std::env::temp_dir().join(format!(
            "echolingo-settings-history-failure-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&directory).unwrap();
        let mut current = Settings::default();
        let mut history: Vec<_> = (0..3)
            .map(|index| HistoryEntry {
                id: index.to_string(),
                text: "fixture source".into(),
                source_language: "en".into(),
                target_language: "zh-Hans".into(),
                results: vec![],
                created_at: 0,
                favorite: false,
            })
            .collect();
        let settings_path = directory.join("settings.json");
        let history_path = directory.join("history.json");
        write_json(&settings_path, &current).unwrap();
        write_json(&history_path, &history).unwrap();
        let settings_before = fs::read(&settings_path).unwrap();
        let history_before = fs::read(&history_path).unwrap();
        // A directory reliably blocks the history replacement on both platforms.
        fs::create_dir(history_path.with_extension("json.tmp")).unwrap();
        let mut changed = current.clone();
        changed.max_history = 1;
        assert!(
            persist_settings_and_history(&directory, &mut current, &mut history, changed).is_err()
        );
        assert_eq!(current.max_history, 20);
        assert_eq!(history.len(), 3);
        assert_eq!(fs::read(&settings_path).unwrap(), settings_before);
        assert_eq!(fs::read(&history_path).unwrap(), history_before);
        fs::remove_dir_all(directory).unwrap();
    }
    #[test]
    fn history_prefers_retaining_favorites() {
        let entry = |id: &str, favorite| HistoryEntry {
            id: id.into(),
            text: String::new(),
            source_language: "auto".into(),
            target_language: "zh-Hans".into(),
            results: vec![],
            created_at: 0,
            favorite,
        };
        let mut h = vec![
            entry("new", false),
            entry("middle", false),
            entry("favorite", true),
        ];
        trim_history(&mut h, 2);
        assert_eq!(
            h.iter().map(|h| h.id.as_str()).collect::<Vec<_>>(),
            vec!["new", "favorite"]
        );
    }
}
