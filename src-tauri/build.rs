mod windows_launcher;

fn main() {
    tauri_build::build();
    println!("cargo:rerun-if-changed=native/macos.swift");
    println!("cargo:rerun-if-changed=native/macos_capture.swift");
    println!("cargo:rerun-if-changed=native/macos_window.swift");
    println!("cargo:rerun-if-changed=native/windows.ps1");
    println!("cargo:rerun-if-changed=windows_launcher.rs");
    println!("cargo:rerun-if-changed=../scripts/build-windows-native-helper.ps1");
    println!("cargo:rerun-if-env-changed=MACOSX_DEPLOYMENT_TARGET");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        build_windows_native_helper();
        build_windows_rust_capture();
        return;
    }

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    let arch = match std::env::var("CARGO_CFG_TARGET_ARCH").as_deref() {
        Ok("aarch64") => "arm64",
        Ok("x86_64") => "x86_64",
        other => panic!("Unsupported macOS architecture: {other:?}"),
    };
    let minimum = std::env::var("MACOSX_DEPLOYMENT_TARGET").unwrap_or_else(|_| "12.0".into());
    let target = format!("{arch}-apple-macosx{minimum}");
    let out_dir = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    let output = out_dir.join("libecholingo_native.a");
    let status = std::process::Command::new("/usr/bin/swiftc")
        .args([
            "native/macos.swift",
            "native/macos_capture.swift",
            "native/macos_window.swift",
            "-O",
            "-target",
            &target,
        ])
        .args([
            "-D",
            "ECHOLINGO_LIBRARY",
            "-parse-as-library",
            "-emit-library",
            "-static",
            "-module-name",
            "EchoLingoNative",
        ])
        .args(["-framework", "AppKit", "-framework", "Vision"])
        .args(["-framework", "NaturalLanguage"])
        .args([
            "-framework",
            "ApplicationServices",
            "-framework",
            "CoreText",
        ])
        .arg("-o")
        .arg(&output)
        .status()
        .expect("Building the macOS native library requires Xcode Command Line Tools (swiftc)");
    assert!(
        status.success(),
        "Failed to compile the macOS native library"
    );
    // Swift object autolink records identify the required system frameworks and
    // Swift runtimes. Link the native code into the application, rather than
    // executing a cached helper with a separate, changing TCC code identity.
    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=echolingo_native");
    // Translation.framework is absent on older supported macOS versions.
    // Swift availability guards keep all Translation symbols out of that path.
    println!("cargo:rustc-link-arg=-Wl,-weak_framework,Translation");
    println!("cargo:rustc-link-arg=-Wl,-weak_framework,ScreenCaptureKit");
    let compiler = std::process::Command::new("/usr/bin/xcrun")
        .args(["--find", "swiftc"])
        .output()
        .expect("Locating the active Swift toolchain requires xcrun");
    assert!(
        compiler.status.success(),
        "Could not locate the active Swift compiler"
    );
    let compiler_path = String::from_utf8(compiler.stdout).expect("Invalid Swift compiler path");
    let swift_library = std::path::Path::new(compiler_path.trim())
        .parent()
        .and_then(std::path::Path::parent)
        .expect("Invalid Swift toolchain directory")
        .join("lib/swift/macosx");
    println!("cargo:rustc-link-search=native={}", swift_library.display());
    println!("cargo:rustc-link-search=native=/usr/lib/swift");
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
}

fn build_windows_native_helper() {
    assert!(
        std::env::var("HOST").is_ok_and(|host| host.contains("windows")),
        "The Windows native helper must be built on Windows with its .NET Framework compiler; cross-compiling the Rust target alone is insufficient"
    );
    let system_root = std::env::var_os("SystemRoot").expect("Windows SystemRoot is unavailable");
    let powershell = std::path::PathBuf::from(system_root)
        .join("System32/WindowsPowerShell/v1.0/powershell.exe");
    let output = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap())
        .join("echolingo-windows-native.dll");
    let launcher = windows_launcher::generate(include_str!("native/windows.ps1"))
        .expect("Packaged Windows launcher generation failed");
    std::fs::write(
        output.with_file_name("echolingo-windows-launcher.ps1"),
        launcher,
    )
    .expect("Could not write packaged Windows launcher");
    let build = std::process::Command::new(powershell)
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-STA",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg("../scripts/build-windows-native-helper.ps1")
        .args(["-HelperPath", "native/windows.ps1", "-OutputPath"])
        .arg(&output)
        .output()
        .expect("Starting the Windows .NET Framework helper compiler failed");
    assert!(
        build.status.success(),
        "Windows native helper compilation failed:\n{}\n{}",
        String::from_utf8_lossy(&build.stdout),
        String::from_utf8_lossy(&build.stderr)
    );
    assert!(
        output.is_file(),
        "Windows native helper compiler produced no DLL"
    );
}

// The isolated capture child has no Tauri dependency and its own target directory.
// Never recursively acquire the application's Cargo target lock from build.rs.
fn build_windows_rust_capture() {
    let manifest_dir = std::path::PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let out_dir = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    let target = std::env::var("TARGET").expect("Windows capture build target is missing");
    let target_dir = out_dir.join("native-capture-target");
    println!("cargo:rerun-if-changed=native-capture");
    for source in [
        "windows_capture_native.rs",
        "windows_capture_ffi.rs",
        "windows_capture_policy.rs",
        "windows_capture_protocol.rs",
    ] {
        println!("cargo:rerun-if-changed=src/{source}");
    }
    let status =
        std::process::Command::new(std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into()))
            .current_dir(&manifest_dir)
            .env_remove("CARGO_MAKEFLAGS")
            .env_remove("MAKEFLAGS")
            .args([
                "build",
                "--release",
                "--jobs=1",
                "--locked",
                "--manifest-path",
                "native-capture/Cargo.toml",
                "--target",
            ])
            .arg(&target)
            .arg("--target-dir")
            .arg(&target_dir)
            .status()
            .expect("Starting the isolated Rust capture child build failed");
    assert!(status.success(), "Isolated Rust capture child build failed");
    let executable = target_dir
        .join(&target)
        .join("release/echolingo-native-capture.exe");
    let bytes = std::fs::read(&executable).expect("Rust capture build produced no executable");
    assert!(
        bytes.len() >= 64 && bytes.starts_with(b"MZ"),
        "Rust capture build did not produce a Windows executable"
    );
    std::fs::write(out_dir.join("echolingo-native-capture.exe"), bytes)
        .expect("Could not stage the exact Rust capture child for embedding");
}
