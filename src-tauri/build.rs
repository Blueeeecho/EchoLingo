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
    let output = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap())
        .join("echolingo-native-helper");
    let status = std::process::Command::new("/usr/bin/swiftc")
        .args(["native/macos.swift", "-O", "-target", &target])
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
        .expect("Building the macOS native helper requires Xcode Command Line Tools (swiftc)");
    assert!(
        status.success(),
        "Failed to compile the macOS native helper"
    );
}
