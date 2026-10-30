// Standalone native tests: no Tauri, WebView, helper process or model downloads.
#[cfg(all(windows, test))]
#[path = "../../../src-tauri/src/windows_ocr.rs"]
mod windows_ocr;
#[cfg(all(not(windows), test))]
#[path = "../../../src-tauri/src/windows_ocr_layout.rs"]
mod windows_ocr_layout;
