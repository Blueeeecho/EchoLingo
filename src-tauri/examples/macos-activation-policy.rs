//! Standalone Tauri activation-policy fixture, never part of the bundled app.
//! Run with --mode=setup or --mode=before-run and --window=none|hidden|floating.
//! The default creates no windows; optional windows contain generated text.
//! It installs no plugins and only queries its own native application/windows.

#[cfg(target_os = "macos")]
#[path = "../src/macos_startup.rs"]
mod macos_startup;

#[cfg(target_os = "macos")]
mod fixture {
    use serde::Serialize;
    use std::{
        ffi::{c_char, c_void, CStr},
        path::PathBuf,
        sync::{
            atomic::{AtomicBool, Ordering},
            Arc, Mutex,
        },
        time::Duration,
    };
    use tauri::Manager;

    type Object = *mut c_void;
    type Selector = *mut c_void;

    #[link(name = "objc")]
    extern "C" {
        fn objc_getClass(name: *const c_char) -> Object;
        fn object_getClassName(object: Object) -> *const c_char;
        fn sel_registerName(name: *const c_char) -> Selector;
        fn objc_msgSend();
    }

    extern "C" {
        fn echolingo_ensure_popup_behavior(window: Object) -> i32;
    }

    // All calls happen on the Tauri main thread. These selectors only query
    // this process; no AX, screenshots, clipboard or external app data.
    unsafe fn integer(receiver: Object, selector: &'static [u8]) -> isize {
        let send: unsafe extern "C" fn(Object, Selector) -> isize =
            std::mem::transmute(objc_msgSend as unsafe extern "C" fn());
        send(receiver, sel_registerName(selector.as_ptr().cast()))
    }

    unsafe fn boolean(receiver: Object, selector: &'static [u8]) -> bool {
        let send: unsafe extern "C" fn(Object, Selector) -> bool =
            std::mem::transmute(objc_msgSend as unsafe extern "C" fn());
        send(receiver, sel_registerName(selector.as_ptr().cast()))
    }

    unsafe fn is_kind_of(receiver: Object, class: Object) -> bool {
        let send: unsafe extern "C" fn(Object, Selector, Object) -> bool =
            std::mem::transmute(objc_msgSend as unsafe extern "C" fn());
        send(
            receiver,
            sel_registerName(c"isKindOfClass:".as_ptr()),
            class,
        )
    }

    unsafe fn order_front_without_activation(receiver: Object) {
        let send: unsafe extern "C" fn(Object, Selector) =
            std::mem::transmute(objc_msgSend as unsafe extern "C" fn());
        send(receiver, sel_registerName(c"orderFrontRegardless".as_ptr()));
    }

    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct WindowObservation {
        native_class: String,
        is_ns_panel: bool,
        level: isize,
        collection_behavior: isize,
        style_mask: isize,
        visible: bool,
        key: bool,
        main: bool,
        on_active_space: bool,
    }

    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Observation {
        phase: &'static str,
        #[serde(flatten)]
        native: crate::macos_startup::ApplicationPolicyMetadata,
        tauri_webview_window_count: usize,
        windows: Vec<WindowObservation>,
    }

    fn observe(phase: &'static str, app: &tauri::AppHandle) -> Observation {
        unsafe {
            let windows = app
                .webview_windows()
                .into_values()
                .map(|window| {
                    let native = window.ns_window().expect("Own fixture window must exist");
                    WindowObservation {
                        native_class: CStr::from_ptr(object_getClassName(native))
                            .to_string_lossy()
                            .into_owned(),
                        is_ns_panel: is_kind_of(native, objc_getClass(c"NSPanel".as_ptr())),
                        level: integer(native, b"level\0"),
                        collection_behavior: integer(native, b"collectionBehavior\0"),
                        style_mask: integer(native, b"styleMask\0"),
                        visible: boolean(native, b"isVisible\0"),
                        key: boolean(native, b"isKeyWindow\0"),
                        main: boolean(native, b"isMainWindow\0"),
                        on_active_space: boolean(native, b"isOnActiveSpace\0"),
                    }
                })
                .collect();
            Observation {
                phase,
                native: crate::macos_startup::application_policy_metadata()
                    .expect("Own application metadata must be read on main thread"),
                tauri_webview_window_count: app.webview_windows().len(),
                windows,
            }
        }
    }

    fn write_report(path: &Option<PathBuf>, report: &serde_json::Value) {
        if let Some(path) = path {
            let temporary = path.with_extension("json.tmp");
            std::fs::write(&temporary, serde_json::to_vec_pretty(report).unwrap())
                .and_then(|()| std::fs::rename(&temporary, path))
                .expect("Could not write explicitly requested fixture report");
        }
    }

    fn generated_page_html() -> &'static str {
        // Served only by an in-process custom URI handler: no network, local
        // assets, optional data-URL feature, application IPC or browser session.
        let html = r#"<!doctype html><html><head><meta charset="utf-8"><title>EchoLingo independent popup fixture</title><style>html,body{margin:0;min-height:100%;background:#eef0ff;color:#202030;font-family:system-ui}body{box-sizing:border-box;padding:20px;border:3px solid #7564cc}h1{font-size:19px;margin:0 0 8px}p{font-size:13px;margin:0 0 14px}input{box-sizing:border-box;width:100%;font:16px system-ui;padding:10px;border:2px solid #7564cc;border-radius:6px;background:white;color:#202030}</style></head><body><h1>EchoLingo independent popup</h1><p>Generated test content only. No OCR, API or clipboard access.</p><label for="fixture-input">First-click input test</label><input id="fixture-input" type="text" placeholder="Click here and type fixture text" autocomplete="off"></body></html>"#;
        html
    }

    pub fn run() {
        let mode = std::env::args()
            .skip(1)
            .find_map(|arg| arg.strip_prefix("--mode=").map(str::to_owned))
            .unwrap_or_else(|| "setup".into());
        if mode != "setup" && mode != "before-run" {
            eprintln!("Expected --mode=setup or --mode=before-run");
            std::process::exit(2);
        }
        let window_mode = std::env::args()
            .skip(1)
            .find_map(|arg| arg.strip_prefix("--window=").map(str::to_owned))
            .unwrap_or_else(|| "none".into());
        let mut hold_ms = std::env::args()
            .skip(1)
            .find_map(|arg| {
                arg.strip_prefix("--hold-ms=")
                    .and_then(|value| value.parse::<u64>().ok())
            })
            .unwrap_or(250);
        if !["none", "hidden", "floating"].contains(&window_mode.as_str())
            || !(250..=30_000).contains(&hold_ms)
        {
            eprintln!("Expected --window=none|hidden|floating --hold-ms=250..30000");
            std::process::exit(2);
        }
        if window_mode != "none" {
            // A cold native WebKit process needs an event loop to finish the
            // page; don't exit before checking the generated DOM callback.
            hold_ms = hold_ms.max(1500);
        }
        let report_path = std::env::args()
            .skip(1)
            .find_map(|arg| arg.strip_prefix("--report=").map(PathBuf::from));
        if report_path.as_ref().is_some_and(|path| {
            !path.is_absolute()
                || path.extension().is_none_or(|extension| extension != "json")
                || path.parent().is_none_or(|parent| !parent.is_dir())
        }) {
            eprintln!("--report must name an absolute .json path in an existing fixture directory");
            std::process::exit(2);
        }

        let completed = Arc::new(AtomicBool::new(false));
        let watchdog = completed.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(hold_ms + 5_000));
            if !watchdog.load(Ordering::Acquire) {
                eprintln!("ACTIVATION_FIXTURE_TIMEOUT: own event loop exceeded bounded hold");
                std::process::exit(124);
            }
        });

        let observations = Arc::new(Mutex::new(Vec::<Observation>::new()));
        let setup_observations = observations.clone();
        let setup_mode = mode.clone();
        let setup_window_mode = window_mode.clone();
        let page_verified = Arc::new(AtomicBool::new(false));
        let setup_page_verified = page_verified.clone();
        // The context is compile-time repository configuration only. Override
        // identity and remove every configured window BEFORE runtime setup. No
        // main-program setup, app-data path, settings or credential read runs.
        let mut context = tauri::generate_context!();
        context.config_mut().identifier =
            "io.github.blueeeecho.echolingo.activation-policy-fixture".into();
        context.config_mut().app.windows.clear();
        context.config_mut().bundle.active = false;

        let mut app = tauri::Builder::default()
            .enable_macos_default_menu(false)
            .activate_ignoring_other_apps(false)
            .register_uri_scheme_protocol("echo-fixture", |_context, _request| {
                tauri::http::Response::builder()
                    .header("Content-Type", "text/html; charset=utf-8")
                    .body(generated_page_html().as_bytes().to_vec())
                    .expect("Generated fixture response must be valid")
            })
            .setup(move |app| {
                setup_observations
                    .lock()
                    .unwrap()
                    .push(observe("setupBeforeSetter", app.handle()));
                if setup_mode == "setup" {
                    // Exact existing production call, intentionally not the
                    // AppHandle setter, so this fixture tests that path.
                    app.set_activation_policy(tauri::ActivationPolicy::Accessory);
                }
                if setup_window_mode != "none" {
                    let window = tauri::WebviewWindowBuilder::new(
                        app,
                        "generated-fixture",
                        tauri::WebviewUrl::External("echo-fixture://localhost/index.html".parse().unwrap()),
                    )
                    .title("EchoLingo independent popup fixture")
                    .inner_size(420.0, 210.0)
                    .visible(false)
                    .focused(false)
                    .decorations(false)
                    .always_on_top(true)
                    .visible_on_all_workspaces(true)
                    .accept_first_mouse(true)
                    .incognito(true)
                    .background_color(tauri::window::Color(238, 240, 255, 255))
                    .on_page_load(move |window, payload| {
                        if payload.event() == tauri::webview::PageLoadEvent::Finished {
                            let verified = setup_page_verified.clone();
                            if window
                                .eval_with_callback("Boolean(document.getElementById('fixture-input') && document.body && getComputedStyle(document.body).backgroundColor === 'rgb(238, 240, 255)')", move |value| {
                                    verified.store(value == "true", Ordering::Release);
                                })
                                .is_err()
                            {
                                eprintln!(
                                    "FIXTURE_PAGE: Generated page injection could not be scheduled"
                                );
                            }
                        }
                    })
                    .build()?;
                    let native = window.ns_window()?;
                    let result = unsafe { echolingo_ensure_popup_behavior(native) };
                    if result != 0 {
                        return Err(std::io::Error::other(format!(
                            "Production popup policy failed: {result}"
                        ))
                        .into());
                    }
                    if setup_window_mode == "floating" {
                        // Explicit opt-in only, for the root's coordinated UI
                        // test against its separate generated fullscreen host.
                        unsafe { order_front_without_activation(native) };
                    }
                }
                setup_observations
                    .lock()
                    .unwrap()
                    .push(observe("setupAfterSetter", app.handle()));
                Ok(())
            })
            .build(context)
            .expect("Could not build isolated activation-policy fixture");
        observations
            .lock()
            .unwrap()
            .push(observe("buildBeforeSetter", app.handle()));
        if mode == "before-run" {
            // App::runtime is still present here: this seeds Tao launch policy
            // rather than prematurely sending a runtime-only handle setter.
            crate::macos_startup::configure(&mut app);
        }
        observations
            .lock()
            .unwrap()
            .push(observe("buildAfterSetter", app.handle()));

        let run_observations = observations.clone();
        let run_report_path = report_path.clone();
        let mut main_events_recorded = false;
        let exit_code = app.run_return(move |handle, event| match event {
            tauri::RunEvent::Ready => {
                run_observations
                    .lock()
                    .unwrap()
                    .push(observe("ready", handle));
                let next_handle = handle.clone();
                let next_observations = run_observations.clone();
                let next_report_path = run_report_path.clone();
                std::thread::spawn(move || {
                    // Let Cocoa's common-mode loop refresh NSRunningApplication
                    // metadata. Never block the main loop while waiting.
                    let mut elapsed_ms = 0;
                    loop {
                        let delay = (hold_ms - elapsed_ms).min(250);
                        std::thread::sleep(Duration::from_millis(delay));
                        elapsed_ms += delay;
                        let terminal = elapsed_ms >= hold_ms;
                        let exit_handle = next_handle.clone();
                        let tick_observations = next_observations.clone();
                        let tick_report_path = next_report_path.clone();
                        next_handle
                            .run_on_main_thread(move || {
                                let mut rows = tick_observations.lock().unwrap();
                                rows.push(observe(
                                    if terminal { "nextMainLoop" } else { "live" },
                                    &exit_handle,
                                ));
                                write_report(
                                    &tick_report_path,
                                    &serde_json::json!({
                                        "phase": if terminal { "exiting" } else { "live" },
                                        "processId": std::process::id(),
                                        "observations": *rows,
                                        "userConfigAccessed": false,
                                        "permissionQueriesMade": false,
                                        "screenshotsTaken": false,
                                        "physicalFullScreenVisualTested": false
                                    }),
                                );
                                drop(rows);
                                if terminal {
                                    exit_handle.exit(0);
                                }
                            })
                            .expect("Could not schedule fixture readback");
                        if terminal {
                            break;
                        }
                    }
                });
            }
            tauri::RunEvent::MainEventsCleared if !main_events_recorded => {
                main_events_recorded = true;
                run_observations
                    .lock()
                    .unwrap()
                    .push(observe("firstMainEventsCleared", handle));
            }
            _ => {}
        });
        let observations = observations.lock().unwrap();
        let required_phases = ["setupAfterSetter", "ready", "nextMainLoop"];
        let passed = exit_code == 0
            && (window_mode == "none" || page_verified.load(Ordering::Acquire))
            && required_phases.iter().all(|phase| {
                observations
                    .iter()
                    .any(|row| row.phase == *phase && row.native.ns_application_policy == 1)
            })
            && observations.iter().all(|row| {
                row.native.main_thread
                    && !row.native.application_active
                    && if window_mode == "none" {
                        row.native.own_native_window_count == 0
                            && row.tauri_webview_window_count == 0
                    } else {
                        row.tauri_webview_window_count <= 1
                            && row.windows.iter().all(|window| {
                                !window.key
                                    && !window.main
                                    && (window_mode != "hidden" || !window.visible)
                            })
                    }
            });
        let report = serde_json::json!({
            "ok": passed,
            "mode": mode,
            "windowMode": window_mode,
            "holdMs": hold_ms,
            "processId": std::process::id(),
            "tauriVersion": "2.12.5",
            "exitCode": exit_code,
            "observations": *observations,
            "windowsCreated": window_mode != "none",
            "pluginsRegistered": false,
            "permissionQueriesMade": false,
            "screenshotsTaken": false,
            "clipboardAccessed": false,
            "userConfigAccessed": false,
            "startupHelperSharedWithProduction": mode == "before-run",
            "applicationMetadataSharedWithProduction": true,
            "popupPolicySharedWithProduction": window_mode != "none",
                "fullScreenVisualTested": false,
                "generatedPageDelivery": "in-process echo-fixture URI handler; Finished DOM boolean readback",
                "generatedInputAndBackgroundVerified": page_verified.load(Ordering::Acquire),
            "bundledContext": std::env::current_exe().ok().is_some_and(|path| {
                path.parent().is_some_and(|parent| parent.ends_with("Contents/MacOS"))
            })
        });
        write_report(&report_path, &report);
        println!("{report}");
        completed.store(true, Ordering::Release);
        if !passed {
            std::process::exit(1);
        }
    }
}

fn main() {
    #[cfg(target_os = "macos")]
    fixture::run();
    #[cfg(not(target_os = "macos"))]
    {
        eprintln!("This isolated fixture only runs on macOS.");
        std::process::exit(2);
    }
}
