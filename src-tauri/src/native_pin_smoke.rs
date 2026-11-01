//! Debug/macOS-only isolated production pin lifecycle smoke. No release entry.
//! No screen capture, user files, arbitrary image/path input, clipboard or providers.
use super::*;
use std::ffi::{c_char, c_void};

type Object = *mut c_void;
type Selector = *const c_void;
#[link(name = "objc")]
unsafe extern "C" {
    fn objc_getClass(name: *const c_char) -> Object;
    fn sel_registerName(name: *const c_char) -> Selector;
    fn objc_msgSend(receiver: Object, selector: Selector);
}
unsafe fn object(receiver: Object, name: &'static [u8]) -> Object {
    let send: unsafe extern "C" fn(Object, Selector) -> Object =
        std::mem::transmute(objc_msgSend as unsafe extern "C" fn(Object, Selector));
    send(receiver, sel_registerName(name.as_ptr().cast()))
}
unsafe fn integer(receiver: Object, name: &'static [u8]) -> isize {
    let send: unsafe extern "C" fn(Object, Selector) -> isize =
        std::mem::transmute(objc_msgSend as unsafe extern "C" fn(Object, Selector));
    send(receiver, sel_registerName(name.as_ptr().cast()))
}
unsafe fn boolean(receiver: Object, name: &'static [u8]) -> bool {
    let send: unsafe extern "C" fn(Object, Selector) -> bool =
        std::mem::transmute(objc_msgSend as unsafe extern "C" fn(Object, Selector));
    send(receiver, sel_registerName(name.as_ptr().cast()))
}
fn foreground_pid() -> i32 {
    // Main-thread metadata only: PID, not application names or user window data.
    unsafe {
        let workspace = object(objc_getClass(c"NSWorkspace".as_ptr()), b"sharedWorkspace\0");
        let front = object(workspace, b"frontmostApplication\0");
        integer(front, b"processIdentifier\0") as i32
    }
}
fn native_state(window: &tauri::WebviewWindow) -> Result<(bool, bool, isize), String> {
    let native = window.ns_window().map_err(|_| "SMOKE_NATIVE_HANDLE")?;
    // Borrowed Tauri NSWindow; called only through main-thread dialog().
    Ok(unsafe {
        (
            boolean(native, b"isVisible\0"),
            boolean(native, b"isKeyWindow\0"),
            integer(native, b"level\0"),
        )
    })
}
fn need(value: bool, message: &str) -> Result<(), String> {
    if value {
        Ok(())
    } else {
        Err(message.into())
    }
}
fn js_callback(send: tokio::sync::oneshot::Sender<bool>) -> impl Fn(String) + Send + 'static {
    // Tauri accepts Fn (not FnOnce): take the one-shot only on first delivery.
    // Late/repeated callbacks after completion or timeout are harmless.
    let pending = Mutex::new(Some(send));
    move |value| {
        if let Ok(mut pending) = pending.lock() {
            if let Some(send) = pending.take() {
                let _ = send.send(value == "true");
            }
        }
    }
}
async fn js(window: &tauri::WebviewWindow, script: &'static str) -> Result<bool, String> {
    let (send, receive) = tokio::sync::oneshot::channel();
    window
        .eval_with_callback(script, js_callback(send))
        .map_err(|_| "SMOKE_JS_SCHEDULE")?;
    tokio::time::timeout(Duration::from_secs(5), receive)
        .await
        .map_err(|_| "SMOKE_JS_TIMEOUT")?
        .map_err(|_| "SMOKE_JS_CLOSED".into())
}
async fn wait_js(window: &tauri::WebviewWindow, script: &'static str) -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if js(window, script).await? {
            return Ok(());
        }
        need(Instant::now() < deadline, "SMOKE_DOM_CONDITION_TIMEOUT")?;
        tokio::time::sleep(Duration::from_millis(40)).await;
    }
}
async fn exercise(app: tauri::AppHandle) -> Result<(), String> {
    let editor = app
        .get_webview_window("screenshot-editor")
        .ok_or("SMOKE_EDITOR")?;
    for id in 1..=2 {
        let png = screenshot::install_native_pin_smoke(&app.state::<AppState>().screenshots, id)?;
        let before = screenshot::dialog(&app, foreground_pid).await?;
        need(
            before > 0 && before != std::process::id() as i32,
            "SMOKE_EXTERNAL_FOREGROUND_REQUIRED",
        )?;
        // Actual production create/session checks and IPC-driven decoded-ready.
        screenshot_pins::pin_screenshot_image(editor.clone(), app.clone(), id, png).await?;
        let pin = app
            .webview_windows()
            .into_values()
            .find(|w| screenshot_pins::is_pin(w.label()))
            .ok_or("SMOKE_PIN_MISSING")?;
        wait_js(&pin, "(()=>{const i=document.querySelector('#pinned-image'),b=document.querySelector('#toggle-pin');if(!i||i.hidden||i.naturalWidth!==128||i.naturalHeight!==96||!b||b.disabled)return false;const c=document.createElement('canvas');c.width=128;c.height=96;const x=c.getContext('2d');x.drawImage(i,0,0);const a=x.getImageData(10,10,1,1).data,z=x.getImageData(100,10,1,1).data;return a[0]===228&&a[1]===93&&a[2]===104&&a[3]===255&&z[0]===23&&z[1]===101&&z[2]===199&&z[3]===255})()").await?;
        need(
            screenshot_pins::native_smoke_counts(&app)? == (1, 0),
            "SMOKE_PAYLOAD_NOT_RELEASED",
        )?;
        let inspect = pin.clone();
        screenshot::dialog(&app, move || {
            let (visible, key, level) = native_state(&inspect)?;
            need(visible && !key && level > 0, "SMOKE_PASSIVE_TOPMOST")?;
            need(foreground_pid() == before, "SMOKE_FOREGROUND_CHANGED")
        })
        .await??;
        need(
            js(
                &pin,
                "(()=>{document.querySelector('#toggle-pin').click();return true})()",
            )
            .await?,
            "SMOKE_UNPIN_CLICK",
        )?;
        wait_js(&pin, "(()=>{const b=document.querySelector('#toggle-pin');return !b.disabled&&b.getAttribute('aria-pressed')==='false'})()").await?;
        let inspect = pin.clone();
        screenshot::dialog(&app, move || {
            need(native_state(&inspect)?.2 == 0, "SMOKE_UNPIN_NATIVE_LEVEL")
        })
        .await??;
        need(
            js(
                &pin,
                "(()=>{document.querySelector('#toggle-pin').click();return true})()",
            )
            .await?,
            "SMOKE_REPIN_CLICK",
        )?;
        wait_js(&pin, "(()=>{const b=document.querySelector('#toggle-pin');return !b.disabled&&b.getAttribute('aria-pressed')==='true'})()").await?;
        let inspect = pin.clone();
        let expected = screenshot::dialog(&app, move || {
            need(native_state(&inspect)?.2 > 0, "SMOKE_REPIN_NATIVE_LEVEL")?;
            let monitor = inspect
                .current_monitor()
                .map_err(|_| "SMOKE_MONITOR")?
                .ok_or("SMOKE_MONITOR")?;
            let scale = monitor.scale_factor();
            let work = monitor.work_area();
            let x = f64::from(work.position.x) / scale + 24.0;
            let y = f64::from(work.position.y) / scale + 24.0;
            inspect
                .set_position(tauri::LogicalPosition::new(x, y))
                .map_err(|_| "SMOKE_MOVE")?;
            inspect
                .set_size(tauri::LogicalSize::new(360.0, 240.0))
                .map_err(|_| "SMOKE_RESIZE")?;
            Ok::<_, String>((x, y))
        })
        .await??;
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let inspect = pin.clone();
            let reached = screenshot::dialog(&app, move || {
                let scale = inspect.scale_factor().map_err(|_| "SMOKE_SCALE")?;
                let size = inspect
                    .inner_size()
                    .map_err(|_| "SMOKE_SIZE")?
                    .to_logical::<f64>(scale);
                let position = inspect
                    .outer_position()
                    .map_err(|_| "SMOKE_POSITION")?
                    .to_logical::<f64>(scale);
                need(foreground_pid() == before, "SMOKE_RESIZE_ACTIVATED_APP")?;
                Ok::<_, String>(
                    (size.width - 360.0).abs() <= 2.0
                        && (size.height - 240.0).abs() <= 2.0
                        && (position.x - expected.0).abs() <= 2.0
                        && (position.y - expected.1).abs() <= 2.0,
                )
            })
            .await??;
            if reached {
                break;
            }
            need(Instant::now() < deadline, "SMOKE_RESIZE_READBACK")?;
            tokio::time::sleep(Duration::from_millis(40)).await;
        }
        // Schedule the real frontend close handler, which invokes production close.
        pin.eval("document.querySelector('#close-pin').click()")
            .map_err(|_| "SMOKE_CLOSE_CLICK")?;
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if screenshot_pins::native_smoke_counts(&app)? == (0, 0)
                && !app
                    .webview_windows()
                    .values()
                    .any(|w| screenshot_pins::is_pin(w.label()))
            {
                break;
            }
            need(Instant::now() < deadline, "SMOKE_CLOSE_CLEANUP_TIMEOUT")?;
            tokio::time::sleep(Duration::from_millis(40)).await;
        }
    }
    Ok(())
}
fn state(directory: PathBuf) -> AppState {
    super::AppState {
        settings: Mutex::new(super::Settings::default()),
        credentials: credential_cache::CredentialCache::default(),
        credential_reads: Mutex::new(()),
        history: Mutex::new(vec![]),
        pinned: AtomicBool::new(false),
        native_tasks: native_tasks::Controller::default(),
        screenshots: screenshot::Controller::default(),
        screenshot_pins: screenshot_pins::Controller::default(),
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
    }
}
pub fn run(mut context: tauri::Context<tauri::Wry>) -> i32 {
    if std::env::args().skip(1).collect::<Vec<_>>()
        != ["--native-pin-smoke", "--isolated-test-session"]
    {
        eprintln!("SMOKE_ISOLATED_EXACT_ARGUMENTS_REQUIRED");
        return 2;
    }
    let directory = std::env::temp_dir().join(format!(
        "echolingo-native-pin-smoke-{}-{}",
        std::process::id(),
        now()
    ));
    if fs::create_dir(&directory).is_err() {
        return 2;
    }
    let setup_directory = directory.clone();
    let result = Arc::new(Mutex::new(None::<Result<(), String>>));
    let run_result = result.clone();
    context.config_mut().identifier = "io.github.blueeeecho.echolingo.native-pin-smoke".into();
    context.config_mut().app.windows.clear();
    context.config_mut().bundle.active = false;
    // Never contact Vite/a possibly unrelated localhost server. CI builds this
    // debug executable with Tauri's custom-protocol embedded production assets.
    context.config_mut().build.dev_url = None;
    let built = tauri::Builder::default()
        .enable_macos_default_menu(false)
        .activate_ignoring_other_apps(false)
        .setup(move |app| {
            app.manage(state(setup_directory.clone()));
            tauri::WebviewWindowBuilder::new(
                app,
                "screenshot-editor",
                tauri::WebviewUrl::External("about:blank".parse()?),
            )
            .visible(false)
            .focused(false)
            .incognito(true)
            .build()?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if matches!(event, tauri::WindowEvent::Destroyed)
                && screenshot_pins::is_pin(window.label())
            {
                screenshot_pins::destroyed(window.app_handle(), window.label());
            }
        })
        .invoke_handler(tauri::generate_handler![
            screenshot_pins::get_pinned_screenshot,
            screenshot_pins::pinned_screenshot_ready,
            screenshot_pins::set_screenshot_pinned,
            screenshot_pins::close_pinned_screenshot,
        ])
        .build(context);
    let code = match built {
        Ok(mut app) => {
            macos_startup::configure(&mut app);
            app.run_return(move |handle, event| {
                if let tauri::RunEvent::ExitRequested {
                    code: None, api, ..
                } = &event
                {
                    // Cleanup removes the final hidden owner before publishing
                    // its result. Only our explicit app.exit(code) ends the run.
                    api.prevent_exit();
                }
                if matches!(event, tauri::RunEvent::Ready) {
                    let app = handle.clone();
                    let output = run_result.clone();
                    tauri::async_runtime::spawn(async move {
                        let outcome =
                            tokio::time::timeout(Duration::from_secs(40), exercise(app.clone()))
                                .await
                                .unwrap_or_else(|_| Err("SMOKE_TOTAL_TIMEOUT".into()));
                        let cleanup = app.clone();
                        let cleaned = screenshot::dialog(&app, move || {
                            for window in cleanup.webview_windows().into_values() {
                                window.destroy().map_err(|_| "SMOKE_FINAL_WINDOW_CLEANUP")?;
                            }
                            Ok::<(), String>(())
                        })
                        .await
                        .and_then(|r| r);
                        let outcome = outcome.and(cleaned);
                        let exit = if outcome.is_ok() { 0 } else { 1 };
                        *output.lock().unwrap() = Some(outcome);
                        app.exit(exit);
                    });
                }
            })
        }
        Err(error) => {
            *result.lock().unwrap() = Some(Err(format!("SMOKE_BUILD: {error}")));
            1
        }
    };
    let outcome = result
        .lock()
        .unwrap()
        .take()
        .unwrap_or_else(|| Err("SMOKE_NO_RESULT".into()));
    let no_exports = fs::read_dir(&directory).is_ok_and(|mut entries| entries.next().is_none());
    let removed = fs::remove_dir(&directory).is_ok();
    let passed = code == 0 && outcome.is_ok() && no_exports && removed;
    println!(
        "{}",
        serde_json::json!({
            "fixture": "native-pin-smoke", "ok": passed, "error": outcome.err(),
            "productionPinCommand": true, "productionPageAndReadyIpc": true,
            "generatedPixelsVerified": passed, "cycles": 2,
            "passiveShowVerified": passed, "nativeToggleResizeCloseVerified": passed,
            "registryAndEncodedPayloadReleased": passed, "ownedDirectoryRemoved": removed,
            "noExportFiles": no_exports, "clipboardAccessed": false, "captureInvoked": false,
            "pluginsRegistered": false, "userSettingsRead": false, "providersInvoked": false,
            "debugOnly": true, "releaseBinaryTested": false, "physicalInputTested": false,
            "externalFullscreenSpaceTested": false, "multiMonitorHardwareTested": false
        })
    );
    if passed {
        0
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::js_callback;

    #[test]
    fn repeated_fn_callback_keeps_first_result() {
        fn invoke_twice(callback: impl Fn(String)) {
            callback("true".into());
            callback("false".into());
        }
        let (send, mut receive) = tokio::sync::oneshot::channel();
        invoke_twice(js_callback(send));
        assert!(receive.try_recv().unwrap());
    }

    #[test]
    fn callback_after_timeout_or_receiver_drop_is_harmless() {
        let (send, receive) = tokio::sync::oneshot::channel();
        let callback = js_callback(send);
        drop(receive);
        callback("true".into());
        callback("false".into());
    }
}
