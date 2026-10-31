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
        let parsed = (|| -> Result<capture::Request, String> {
            let mut host = None;
            let mut token = None;
            let mut cancel = None;
            let mut mode = None;
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
                    _ => return Err("CAPTURE_ARGUMENT: Unsupported argument".into()),
                }
                i += 2;
            }
            if mode.as_deref() != Some("capture-image") {
                return Err("CAPTURE_ARGUMENT: Unsupported mode".into());
            }
            Ok(capture::Request {
                host_thread: host.ok_or("CAPTURE_ARGUMENT: Missing host")?,
                host_token: token.ok_or("CAPTURE_ARGUMENT: Missing token")?,
                cancellation: cancel.ok_or("CAPTURE_ARGUMENT: Missing cancellation")?,
            })
        })();
        let reply = match parsed {
            Ok(request) => capture::run(request),
            Err(error) => capture::CapturedResult {
                result: Err(error),
                health: Default::default(),
            },
        };
        let ok = reply.result.is_ok();
        let mut output = serde_json::json!({"ok":ok,"nativeBackend":"rust-win32-capture","captureHealth":reply.health});
        match reply.result {
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
