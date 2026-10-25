#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod model;
mod ocr;
mod ocr_native;
mod platform;
mod translation;
mod window_layout;

use model::*;
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{Emitter, Manager, State};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

struct AppState {
    settings: Mutex<Settings>,
    history: Mutex<Vec<HistoryEntry>>,
    pinned: AtomicBool,
    native_busy: AtomicBool,
    translation_busy: tokio::sync::Semaphore,
    data_dir: PathBuf,
    client: reqwest::Client,
    startup_warnings: Mutex<Vec<String>>,
    outside_thread: Mutex<Option<std::thread::Thread>>,
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
fn load_key(p: &Provider) -> Result<String, String> {
    match secret_entry(&p.id)?.get_password() {
        Ok(key) => decode_credential(&key, &credential_scope(&p.kind, &p.base_url)?),
        Err(keyring::Error::NoEntry) => Ok(String::new()),
        Err(_) => Err("无法读取系统凭据库中的 API 密钥".into()),
    }
}

fn load_ocr_key(p: &ocr::OcrProvider) -> Result<String, String> {
    match secret_entry(&ocr_secret_id(p))?.get_password() {
        Ok(k) => decode_credential(&k, &credential_scope(&p.kind, &p.base_url)?),
        Err(keyring::Error::NoEntry) => Ok(String::new()),
        Err(_) => Err("无法读取系统凭据库中的 OCR 密钥".into()),
    }
}
fn ocr_secret_id(p: &ocr::OcrProvider) -> String {
    // Credentials for a different protocol must never be sent to a new service
    // just because the user edited an existing service entry.
    format!("ocr-{}-{}", p.id, p.kind)
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
    if matches!(provider.kind.as_str(), "baidu" | "tencent") {
        ocr_native::validate_credentials(&provider.kind, &key)?;
    } else if key.contains(['\r', '\n']) {
        return Err("OCR API 密钥不能包含换行".into());
    }
    let stored = encode_credential(credential_scope(&provider.kind, &provider.base_url)?, key)?;
    secret_entry(&ocr_secret_id(&provider))?
        .set_password(&stored)
        .map_err(|_| "无法将 OCR 密钥保存到系统凭据库".into())
}
#[tauri::command]
fn delete_ocr_api_key(provider_id: String) -> Result<(), String> {
    for kind in ["openai-vision", "http-json", "baidu", "tencent"] {
        delete_api_key(format!("ocr-{provider_id}-{kind}"))?;
    }
    // Remove the unscoped entry used by development builds as well.
    delete_api_key(format!("ocr-{provider_id}"))
}
#[tauri::command]
async fn test_ocr_provider(
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
    let text = ocr::recognize(
        &state.client,
        &p,
        load_ocr_key(&p),
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
fn get_settings(state: State<AppState>) -> Result<Settings, String> {
    let mut settings = locked(&state.settings)?.clone();
    for p in &mut settings.providers {
        p.has_key = load_key(p).map(|k| !k.is_empty()).unwrap_or(false);
    }
    for p in &mut settings.ocr_providers {
        p.has_key = load_ocr_key(p).map(|k| !k.is_empty()).unwrap_or(false);
    }
    Ok(settings)
}

fn parsed_shortcuts(s: &Shortcuts) -> Result<Vec<(String, Shortcut)>, String> {
    let mut out = Vec::new();
    let mut ids = std::collections::HashSet::new();
    for (action, key) in s.pairs() {
        if key.is_empty() {
            continue;
        }
        let shortcut: Shortcut = key.parse().map_err(|_| format!("快捷键无效：{key}"))?;
        if !ids.insert(shortcut.id()) {
            return Err("不同操作不能使用相同快捷键".into());
        }
        out.push((action.into(), shortcut));
    }
    Ok(out)
}
fn install_shortcuts(app: &tauri::AppHandle, s: &Shortcuts) -> Result<(), String> {
    let shortcuts = parsed_shortcuts(s)?;
    app.global_shortcut()
        .unregister_all()
        .map_err(|e| format!("无法更新快捷键：{e}"))?;
    for (action, shortcut) in shortcuts {
        app.global_shortcut()
            .on_shortcut(shortcut, move |app, _, event| {
                if event.state() == ShortcutState::Released {
                    start_action(app.clone(), action.clone());
                }
            })
            .map_err(|e| format!("快捷键已被占用或无法注册：{e}"))?;
    }
    Ok(())
}
#[tauri::command]
fn save_settings(
    app: tauri::AppHandle,
    state: State<AppState>,
    mut settings: Settings,
) -> Result<(), String> {
    validate_settings(&settings)?;
    parsed_shortcuts(&settings.shortcuts)?;
    for p in &mut settings.providers {
        p.has_key = false;
    }
    for p in &mut settings.ocr_providers {
        p.has_key = false;
    }
    let mut old = locked(&state.settings)?;
    if let Err(e) = install_shortcuts(&app, &settings.shortcuts) {
        let _ = install_shortcuts(&app, &old.shortcuts);
        return Err(e);
    }
    if let Err(e) = write_json(&state.data_dir.join("settings.json"), &settings) {
        let _ = install_shortcuts(&app, &old.shortcuts);
        return Err(e);
    }
    *old = settings;
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
    if key.is_empty() || key.len() > 8192 || key.contains(['\r', '\n']) {
        return Err("API 密钥为空、过长或包含换行".into());
    }
    let stored = encode_credential(credential_scope(&provider.kind, &provider.base_url)?, key)?;
    secret_entry(&provider_id)?
        .set_password(&stored)
        .map_err(|_| "无法保存到系统凭据库；密钥没有保存到文件".into())
}
#[tauri::command]
fn delete_api_key(provider_id: String) -> Result<(), String> {
    match secret_entry(&provider_id)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(_) => Err("无法删除凭据库中的密钥".into()),
    }
}
#[tauri::command]
async fn translate(
    state: State<'_, AppState>,
    text: String,
    source_language: String,
    target_language: String,
) -> Result<Vec<TranslationResult>, String> {
    if text.trim().is_empty() {
        return Err("请输入需要翻译的文本".into());
    }
    if text.chars().count() > 20000 {
        return Err("单次最多翻译 20,000 字符".into());
    }
    if source_language.len() > 40 || target_language.len() > 40 || target_language.is_empty() {
        return Err("语言参数无效".into());
    }
    let _permit = state
        .translation_busy
        .try_acquire()
        .map_err(|_| "翻译任务较多，请等待当前请求完成")?;
    let settings = locked(&state.settings)?.clone();
    let providers: Vec<_> = settings
        .providers
        .iter()
        .filter(|p| p.enabled)
        .cloned()
        .collect();
    if providers.is_empty() {
        return Err("请在设置中添加并启用翻译服务".into());
    }
    let keys: Vec<_> = providers.iter().map(load_key).collect();
    let jobs = providers.iter().zip(keys).map(|(p, key)| {
        translation::translate_one(
            &state.client,
            p,
            key,
            &text,
            &source_language,
            &target_language,
        )
    });
    let results = futures_util::future::join_all(jobs).await;
    if settings.save_history
        && settings.max_history > 0
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
            results: results.clone(),
            created_at,
            favorite: false,
        };
        let mut updated = history.clone();
        updated.insert(0, entry);
        trim_history(&mut updated, settings.max_history);
        if write_json(&state.data_dir.join("history.json"), &updated).is_ok() {
            *history = updated;
        } else {
            locked(&state.startup_warnings)?
                .push("最近一次翻译的历史记录保存失败，译文仍正常返回".into());
        }
    }
    Ok(results)
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
    let mut total: usize = sizes.iter().sum();
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
    }
}
#[tauri::command]
async fn test_provider(state: State<'_, AppState>, provider_id: String) -> Result<String, String> {
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
    let r =
        translation::translate_one(&state.client, &p, load_key(&p), "Hello", "en", "zh-Hans").await;
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
fn delete_history(state: State<AppState>, id: Option<String>) -> Result<(), String> {
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

fn show(app: &tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_focus();
        wake_outside_watcher(app);
    }
}
fn wake_outside_watcher(app: &tauri::AppHandle) {
    if let Ok(thread) = app.state::<AppState>().outside_thread.lock() {
        if let Some(thread) = thread.as_ref() {
            thread.unpark();
        }
    }
}
fn show_inactive(app: &tauri::AppHandle) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Some(window) = handle.get_webview_window("main") {
            let _ = platform::show_without_activation(&window);
            wake_outside_watcher(&handle);
        }
    });
}
fn empty_selection_window(app: &tauri::AppHandle) {
    let _ = app.emit("source-text", serde_json::json!({"text":"","mode":"input"}));
}
fn visible_action_error(action: &str, error: &str) -> Option<String> {
    if error.starts_with("CANCELLED") {
        return None;
    }
    if action == "selection" {
        // A shortcut with no obtainable selection is also the user's manual
        // input shortcut. Permission setup belongs in Settings, not a toast on
        // an otherwise empty popup. Preserve a warning only if the clipboard
        // could not be restored after our copy fallback changed it.
        return error
            .starts_with("CLIPBOARD_RESTORE_FAILED")
            .then(|| "原剪贴板恢复失败，当前剪贴板可能仍是刚才复制的选中文字。".into());
    }
    Some(
        error
            .strip_prefix("PERMISSION:")
            .unwrap_or(error)
            .trim()
            .to_owned(),
    )
}
#[tauri::command]
fn show_popup(app: tauri::AppHandle) {
    show_inactive(&app);
}
fn start_action(app: tauri::AppHandle, action: String) {
    if action == "input" {
        show(&app);
        let _ = app.emit("focus-input", ());
        return;
    }
    let state = app.state::<AppState>();
    if state.native_busy.swap(true, Ordering::SeqCst) {
        return;
    }
    let cloud_ocr = if matches!(action.as_str(), "capture" | "ocr" | "silentOcr") {
        let settings = state.settings.lock().unwrap();
        let provider = settings
            .active_ocr_provider_id
            .as_ref()
            .and_then(|id| settings.ocr_providers.iter().find(|p| &p.id == id))
            .cloned();
        if let Some(w) = app.get_webview_window("main") {
            let _ = w.hide();
        }
        provider
    } else {
        None
    };
    tauri::async_runtime::spawn(async move {
        let action2 = action.clone();
        let use_cloud = cloud_ocr.is_some();
        let result = tauri::async_runtime::spawn_blocking(move || {
            std::thread::sleep(Duration::from_millis(180));
            match action2.as_str() {
                "selection" => platform::selected_text(),
                "clipboard" => platform::clipboard_text(),
                "capture" | "ocr" | "silentOcr" if use_cloud => platform::capture_image(),
                "capture" | "ocr" | "silentOcr" => platform::capture_ocr(),
                _ => Err("未知操作".into()),
            }
        })
        .await
        .map_err(|_| "系统操作异常".to_string())
        .and_then(|r| r);
        let result = if let (Some(provider), Ok(image)) = (&cloud_ocr, &result) {
            let state = app.state::<AppState>();
            ocr::recognize(&state.client, provider, load_ocr_key(provider), image).await
        } else {
            result
        };
        match result {
            Ok(text) if !text.trim().is_empty() => {
                if action == "silentOcr" {
                    let copied =
                        tauri::async_runtime::spawn_blocking(move || platform::copy_text(&text))
                            .await;
                    if !matches!(copied, Ok(Ok(()))) {
                        show_inactive(&app);
                        let _ = app.emit("action-error", "OCR 已完成，但复制到剪贴板失败");
                    } else {
                        let _ = app.emit("ocr-copied", ());
                    }
                } else {
                    let mode = if action == "ocr" { "ocr" } else { "translate" };
                    let _ = app.emit("source-text", serde_json::json!({"text":text,"mode":mode}));
                }
            }
            Ok(_) if action == "selection" => empty_selection_window(&app),
            Ok(_) => {
                empty_selection_window(&app);
                let _ = app.emit("action-error", "没有识别到文字，请选择更清晰的区域");
            }
            Err(e) if e.starts_with("CANCELLED") => {}
            Err(e) => {
                empty_selection_window(&app);
                if let Some(message) = visible_action_error(&action, &e) {
                    let _ = app.emit("action-error", message);
                }
            }
        }
        app.state::<AppState>()
            .native_busy
            .store(false, Ordering::SeqCst);
    });
}
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
                        let _ = window.hide();
                    }
                }
            }
            previous = down;
        }
    });
    *owner.state::<AppState>().outside_thread.lock().unwrap() = Some(handle.thread().clone());
}
#[tauri::command]
fn run_action(app: tauri::AppHandle, action: String) -> Result<(), String> {
    if ![
        "selection",
        "capture",
        "ocr",
        "silentOcr",
        "input",
        "clipboard",
    ]
    .contains(&action.as_str())
    {
        return Err("未知操作".into());
    }
    start_action(app, action);
    Ok(())
}
#[tauri::command]
async fn copy_text(text: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || platform::copy_text(&text))
        .await
        .map_err(|_| "复制失败".to_string())?
}
#[tauri::command]
fn set_pinned(app: tauri::AppHandle, state: State<AppState>, pinned: bool) -> Result<(), String> {
    app.get_webview_window("main")
        .ok_or("窗口不存在")?
        .set_always_on_top(true)
        .map_err(|_| "无法设置窗口置顶")?;
    state.pinned.store(pinned, Ordering::SeqCst);
    wake_outside_watcher(&app);
    Ok(())
}
#[tauri::command]
fn hide_window(app: tauri::AppHandle) -> Result<(), String> {
    app.get_webview_window("main")
        .ok_or("窗口不存在")?
        .hide()
        .map_err(|_| "无法隐藏窗口".into())
}
#[tauri::command]
async fn diagnostics(state: State<'_, AppState>) -> Result<serde_json::Value, String> {
    let warnings = locked(&state.startup_warnings)?.clone();
    let mut value = tauri::async_runtime::spawn_blocking(platform::diagnostics)
        .await
        .map_err(|_| "诊断失败")?;
    value["appVersion"] = serde_json::json!(env!("CARGO_PKG_VERSION"));
    value["warnings"] = serde_json::json!(warnings);
    value["dataDirectory"] = serde_json::json!(state.data_dir.display().to_string());
    value["ocrUpload"] = serde_json::json!(false);
    Ok(value)
}
#[tauri::command]
async fn permission_status() -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(platform::permission_status)
        .await
        .map_err(|_| "无法检查系统权限".to_string())?
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

fn tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
    let definitions = [
        ("input", "打开翻译窗口"),
        ("selection", "划词翻译"),
        ("capture", "截图翻译"),
        ("ocr", "截图 OCR"),
        ("silentOcr", "静默 OCR → 剪贴板"),
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
            } else {
                start_action(app.clone(), event.id().as_ref().to_string());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }
    builder.build(app)?;
    Ok(())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| show(app)))
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
            let settings = match fs::read(data_dir.join("settings.json")) {
                Ok(bytes) => match serde_json::from_slice::<Settings>(&bytes) {
                    Ok(s) if validate_settings(&s).is_ok() => s,
                    _ => {
                        warnings.push("设置文件损坏，已使用默认设置；原文件保留".into());
                        Settings::default()
                    }
                },
                Err(_) => Settings::default(),
            };
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
            app.manage(AppState {
                settings: Mutex::new(settings.clone()),
                history: Mutex::new(history),
                pinned: AtomicBool::new(false),
                native_busy: AtomicBool::new(false),
                translation_busy: tokio::sync::Semaphore::new(2),
                data_dir,
                client,
                startup_warnings: Mutex::new(warnings),
                outside_thread: Mutex::new(None),
            });
            app.manage(window_layout::LayoutState::default());
            if let Err(e) = install_shortcuts(app.handle(), &settings.shortcuts) {
                app.state::<AppState>()
                    .startup_warnings
                    .lock()
                    .unwrap()
                    .push(e);
            }
            tray(app.handle())?;
            outside_click_watcher(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| match event {
            tauri::WindowEvent::CloseRequested { api, .. } => {
                api.prevent_close();
                let _ = window.hide();
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            window_layout::fit_window,
            window_layout::start_window_drag,
            show_popup,
            get_settings,
            save_settings,
            set_ocr_api_key,
            delete_ocr_api_key,
            test_ocr_provider,
            set_api_key,
            delete_api_key,
            translate,
            test_provider,
            get_history,
            toggle_favorite,
            delete_history,
            run_action,
            copy_text,
            set_pinned,
            hide_window,
            diagnostics,
            permission_status,
            request_permission,
            open_permission_settings
        ])
        .run(tauri::generate_context!())
        .expect("EchoLingo could not start");
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn empty_selection_is_quiet_but_other_actions_keep_actionable_errors() {
        for error in [
            "NO_SELECTION: Nothing selected",
            "PERMISSION: Accessibility is not granted",
            "SELECTION: Foreground changed",
            "NATIVE_START: Helper unavailable",
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
    fn duplicate_shortcuts_are_rejected() {
        let mut s = Shortcuts::default();
        s.ocr = s.capture.clone();
        assert!(parsed_shortcuts(&s).is_err());
    }
    #[test]
    fn empty_shortcut_disables_action() {
        let mut s = Shortcuts::default();
        s.ocr.clear();
        assert_eq!(parsed_shortcuts(&s).unwrap().len(), 4);
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
