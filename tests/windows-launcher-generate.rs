//! Fixture bridge to the exact production build-time launcher generator.
#[path = "../src-tauri/windows_launcher.rs"]
mod windows_launcher;
fn main() {
    let output = std::env::args_os().nth(1).expect("output path required");
    let source = include_str!("../src-tauri/native/windows.ps1");
    let launcher =
        windows_launcher::generate(source).expect("production launcher generation failed");
    use std::io::Write;
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(output)
        .expect("new owned launcher path required");
    file.write_all(launcher.as_bytes())
        .expect("launcher write failed");
}
