#![cfg_attr(windows, windows_subsystem = "windows")]
#[cfg(windows)]
#[path = "../../src/windows_capture_native.rs"]
mod capture;
#[path = "../../src/windows_capture_policy.rs"]
mod policy;
#[path = "../../src/windows_capture_protocol.rs"]
mod protocol;
fn main() {
    #[cfg(windows)]
    {
        use base64::Engine;
        let args: Vec<String> = std::env::args().skip(1).collect();
        if args == ["--self-test"] {
            let result = capture::self_test();
            let ok = result.is_ok();
            println!(
                "{}",
                serde_json::json!({"ok":result.is_ok(),"nativeBackend":"rust-win32-capture","memoryPixelSelfTest":result.is_ok(),"error":result.err()})
            );
            if !ok {
                std::process::exit(1);
            }
            return;
        }
        let mut deferred_mode = false;
        let parsed = (|| -> Result<capture::Request, String> {
            let mut host = None;
            let mut token = None;
            let mut cancel = None;
            let mut mode = None;
            let mut owner = None;
            let mut i = 0;
            let mut seen = std::collections::HashSet::new();
            while i < args.len() {
                if !seen.insert(args[i].as_str()) {
                    return Err("CAPTURE_ARGUMENT: Duplicate argument".into());
                }
                let value = args.get(i + 1).ok_or("CAPTURE_ARGUMENT: Missing value")?;
                match args[i].as_str() {
                    "-Mode" => mode = Some(value.clone()),
                    "-CaptureHostThreadId" => {
                        host = Some(
                            value
                                .parse::<u32>()
                                .map_err(|_| "CAPTURE_ARGUMENT: Invalid host")?,
                        )
                    }
                    "-CaptureHostToken" => {
                        token = Some(
                            value
                                .parse::<i64>()
                                .map_err(|_| "CAPTURE_ARGUMENT: Invalid token")?,
                        )
                    }
                    "-NativeCancellationEvent" => cancel = Some(value.clone()),
                    "-CaptureOwnerProcessId" => {
                        owner = Some(
                            value
                                .parse::<u32>()
                                .map_err(|_| "CAPTURE_ARGUMENT: Invalid owner")?,
                        )
                    }
                    _ => return Err("CAPTURE_ARGUMENT: Unsupported argument".into()),
                }
                i += 2;
            }
            let purpose = match mode.as_deref() {
                Some("capture-image") => policy::CapturePurpose::Region,
                Some("capture-screenshot") if owner.is_some_and(|pid| pid > 0) => {
                    policy::CapturePurpose::Screenshot
                }
                Some("select-screenshot" | "capture-selected-region")
                    if owner.is_some_and(|pid| pid > 0) =>
                {
                    policy::CapturePurpose::Screenshot
                }
                _ => {
                    return Err(
                        "CAPTURE_ARGUMENT: Unsupported mode or missing screenshot owner".into(),
                    )
                }
            };
            deferred_mode = mode.as_deref() == Some("capture-selected-region");
            if deferred_mode && (host.is_some() || token.is_some()) {
                return Err("CAPTURE_ARGUMENT: Deferred capture does not accept an input host".into());
            }
            Ok(capture::Request {
                selection_only: mode.as_deref() == Some("select-screenshot"),
                purpose,
                owner_process: owner.unwrap_or(0),
                host_thread: if deferred_mode {
                    0
                } else {
                    host.ok_or("CAPTURE_ARGUMENT: Missing host")?
                },
                host_token: if deferred_mode {
                    0
                } else {
                    token.ok_or("CAPTURE_ARGUMENT: Missing token")?
                },
                cancellation: cancel.ok_or("CAPTURE_ARGUMENT: Missing cancellation")?,
            })
        })();
        let reply = match parsed {
            Ok(request) if deferred_mode => {
                use std::io::Read;
                let mut bytes = Vec::new();
                // One bounded request; never accept an arbitrary file path.
                match std::io::stdin().take(65_537).read_to_end(&mut bytes) {
                    Ok(_) => capture::capture_selected_region(
                        request.owner_process,
                        &request.cancellation,
                        &bytes,
                    ),
                    Err(_) => capture::CapturedResult {
                        result: Err("CAPTURE_ARGUMENT: Deferred request could not be read".into()),
                        health: Default::default(),
                        capture_geometry: None,
                        initial_action: None,
                        capture_screens: Vec::new(),
                        selection_plan: None,
                    },
                }
            }
            Ok(request) => capture::run(request),
            Err(error) => capture::CapturedResult {
                result: Err(error),
                health: Default::default(),
                capture_geometry: None,
                initial_action: None,
                capture_screens: Vec::new(),
                selection_plan: None,
            },
        };
        let ok = reply.result.is_ok();
        let mut output = serde_json::json!({"ok":ok,"nativeBackend":"rust-win32-capture","captureHealth":reply.health});
        if let Some(g) = reply.capture_geometry {
            output["captureGeometry"] = serde_json::json!({"x":g[0], "y":g[1], "width":g[2], "height":g[3],
                "screenX":g[4], "screenY":g[5], "screenWidth":g[6], "screenHeight":g[7], "scale":1.0});
        }
        if ok {
            if let Some(action) = reply.initial_action {
                output["initialAction"] = serde_json::json!(action);
            }
            output["captureScreens"] = serde_json::json!(reply.capture_screens.iter().map(|screen|
                serde_json::json!({"x":screen[0], "y":screen[1], "width":screen[2], "height":screen[3]})).collect::<Vec<_>>());
        }
        let selection_only = reply.selection_plan.is_some();
        if let Some(plan) = reply.selection_plan {
            output["selectionPlan"] = plan;
        }
        match reply.result {
            Ok(_) if selection_only => {}
            Ok(bytes) => {
                output["imageBase64"] =
                    serde_json::json!(base64::engine::general_purpose::STANDARD.encode(bytes))
            }
            Err(error) => output["error"] = serde_json::json!(error),
        }
        println!("{output}");
        if !ok {
            std::process::exit(1);
        }
    }
    #[cfg(not(windows))]
    {
        eprintln!("Windows-only native capture child");
        std::process::exit(1);
    }
}
