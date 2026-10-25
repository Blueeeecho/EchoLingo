//! Stable menu-bar application identity. Configure the App before `run`, while
//! Tao still owns its launch configuration; never toggle policy for a popup.

use serde::Serialize;

pub fn configure(app: &mut tauri::App) {
    app.set_activation_policy(tauri::ActivationPolicy::Accessory);
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplicationPolicyMetadata {
    pub schema_version: i64,
    pub ns_application_policy: i64,
    pub ns_running_application_policy: i64,
    pub ls_ui_element: Option<bool>,
    pub application_active: bool,
    pub own_native_window_count: i64,
    pub process_id: i64,
    pub main_thread: bool,
}

/// Read only this process's AppKit/bundle metadata on its main thread. The
/// NSApplication getter is authoritative; NSRunningApplication may be cached.
pub fn application_policy_metadata() -> Result<ApplicationPolicyMetadata, String> {
    unsafe extern "C" {
        fn echolingo_application_policy_metadata(output: *mut i64, count: i32) -> i32;
    }
    let mut fields = [0_i64; 8];
    // SAFETY: The statically linked ABI checks the main thread and buffer size;
    // the mutable array is valid for all eight signed 64-bit output fields.
    let result =
        unsafe { echolingo_application_policy_metadata(fields.as_mut_ptr(), fields.len() as i32) };
    match result {
        0 => Ok(ApplicationPolicyMetadata {
            schema_version: fields[0],
            ns_application_policy: fields[1],
            ns_running_application_policy: fields[2],
            ls_ui_element: match fields[3] {
                0 => Some(false),
                1 => Some(true),
                _ => None,
            },
            application_active: fields[4] != 0,
            own_native_window_count: fields[5],
            process_id: fields[6],
            main_thread: fields[7] != 0,
        }),
        -1 => Err("WINDOW_THREAD: Application policy requires the application main thread.".into()),
        _ => Err("WINDOW_POLICY: Cannot read this application's native startup policy.".into()),
    }
}
