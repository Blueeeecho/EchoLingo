fn main() {
    tauri_build::build();
    println!("cargo:rerun-if-changed=native/macos.swift");
    println!("cargo:rerun-if-changed=native/windows.ps1");
    println!("cargo:rerun-if-env-changed=MACOSX_DEPLOYMENT_TARGET");

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
        .args(["native/macos.swift", "-O", "-target", &target])
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
