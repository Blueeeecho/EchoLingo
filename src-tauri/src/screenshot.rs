//! Local-only screenshot sessions. Never calls OCR, translation, history or HTTP.
//! Only the current image is retained, and filesystem paths come from native
//! dialogs or the owner's persisted directory, never arbitrary frontend input.
use base64::Engine;
use image::{ImageDecoder, ImageEncoder, ImageFormat, ImageReader, Limits, RgbaImage};
use serde::Serialize;
use std::{fs::{self, OpenOptions}, io::{Cursor, Read, Write}, path::{Path, PathBuf}, sync::{Mutex, atomic::{AtomicBool, Ordering}}};
use tauri::{Emitter, Manager};

pub const MAX_ENCODED_BYTES: usize = 32 * 1024 * 1024;
pub const MAX_PIXELS: u64 = 32_000_000;
pub const MAX_EDGE: u32 = 16_384;
const STALE: &str = "CANCELLED: 截图已关闭或被新操作替换";
const LABEL: &str = "screenshot-editor";

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub id: u64,
    pub png_base64: String,
    pub width: u32,
    pub height: u32,
    pub captured_at: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_name: Option<String>,
}
struct StoredSession { public: Session, file_name: String }
#[derive(Default)]
struct SessionState { intent: Option<u64>, image: Option<StoredSession> }
pub struct Controller { state: Mutex<SessionState>, operations: tokio::sync::Semaphore, dialog_active: AtomicBool }
impl Default for Controller {
    fn default() -> Self { Self { state: Mutex::new(SessionState::default()), operations: tokio::sync::Semaphore::new(1), dialog_active: AtomicBool::new(false) } }
}
impl Controller {
    fn begin(&self, id: u64) -> Result<(), String> {
        *super::locked(&self.state)? = SessionState { intent: Some(id), image: None };
        Ok(())
    }
    fn cancel_pending(&self) {
        if let Ok(mut state) = self.state.lock() {
            // An unrelated translator hide/capture may cancel a pending F1 or
            // Open request, but never discard an already committed document.
            state.intent = state.image.as_ref().map(|image| image.public.id);
        }
    }
    fn current(&self, id: u64) -> bool {
        self.state.lock().is_ok_and(|state| state.intent == Some(id))
    }
    fn with_image<T>(&self, id: u64, operation: impl FnOnce(&StoredSession) -> Result<T,String>) -> Result<T,String> {
        let state = super::locked(&self.state)?;
        let image = state.image.as_ref().filter(|image| state.intent == Some(id) && image.public.id == id).ok_or(STALE)?;
        operation(image)
    }
    #[cfg(test)]
    fn install(&self, session: Session, file_name: String) -> Result<(),String> {
        self.install_and_publish(session, file_name, |_| Ok(()))
    }
    fn install_and_publish(&self, session: Session, file_name: String, publish: impl FnOnce(&Session) -> Result<(),String>) -> Result<(),String> {
        let mut state = super::locked(&self.state)?;
        if state.intent != Some(session.id) { return Err(STALE.into()); }
        let previous = state.image.replace(StoredSession { public: session, file_name });
        let outcome = publish(&state.image.as_ref().ok_or(STALE)?.public);
        if outcome.is_err() {
            state.image = previous;
            state.intent = state.image.as_ref().map(|image| image.public.id);
        }
        outcome
    }
}
fn ensure_editor(window: &tauri::WebviewWindow) -> Result<(),String> {
    if window.label() != LABEL { return Err("SCREENSHOT_WINDOW: 图片只能由截图编辑器访问".into()); }
    Ok(())
}
fn emit_session(app: &tauri::AppHandle, session: &Session) -> Result<(), String> {
    app.emit_to(LABEL, "screenshot-session", session)
        .map_err(|_| "SCREENSHOT_WINDOW: 无法传送图片到编辑器，请重试".to_owned())
}
fn emit_cleared(app: &tauri::AppHandle, id: Option<u64>) {
    if let Some(id) = id { let _ = app.emit_to(LABEL, "screenshot-session-cleared", serde_json::json!({"id": id})); }
}
pub fn cancel_pending(app: &tauri::AppHandle) {
    app.state::<super::AppState>().screenshots.cancel_pending();
}
/// Explicit new screenshot intent discards the previous screenshot document.
pub fn invalidate(app: &tauri::AppHandle) {
    let state = app.state::<super::AppState>();
    let cleared = if let Ok(mut screenshot) = state.screenshots.state.lock() {
        let id = screenshot.image.as_ref().map(|image| image.public.id);
        *screenshot = SessionState::default();
        id
    } else { None };
    emit_cleared(app, cleared);
    // Hiding an AppKit owner while its sheet is open can strand the dialog.
    // The modal completion hides an invalidated editor before releasing its permit.
    if !state.screenshots.dialog_active.load(Ordering::SeqCst) {
        if let Some(window) = app.get_webview_window(LABEL) { let _ = window.hide(); }
    }
}

fn validate_dimensions(width: u32, height: u32) -> Result<(),String> {
    if width == 0 || height == 0 || width > MAX_EDGE || height > MAX_EDGE || u64::from(width) * u64::from(height) > MAX_PIXELS {
        return Err("SCREENSHOT_SIZE: 图片超过 3200 万像素或单边 16384 像素限制".into());
    }
    Ok(())
}
fn bounded_reader(bytes: &[u8], format: ImageFormat) -> ImageReader<Cursor<&[u8]>> {
    let mut reader = ImageReader::with_format(Cursor::new(bytes), format);
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_EDGE);
    limits.max_image_height = Some(MAX_EDGE);
    limits.max_alloc = Some(MAX_PIXELS * 8);
    reader.limits(limits);
    reader
}
fn decode(bytes: &[u8], png_only: bool) -> Result<RgbaImage,String> {
    if bytes.is_empty() || bytes.len() > MAX_ENCODED_BYTES { return Err("SCREENSHOT_SIZE: 图片必须小于 32 MiB".into()); }
    let format = image::guess_format(bytes).map_err(|_| "SCREENSHOT_FORMAT: 请选择 PNG 或 JPEG 图片")?;
    if format != ImageFormat::Png && (png_only || format != ImageFormat::Jpeg) { return Err("SCREENSHOT_FORMAT: 仅支持 PNG 和 JPEG 静态图片".into()); }
    // Check headers before any pixel allocation; decoder limits additionally
    // bound malicious chunk sizes / auxiliary allocations / decompression.
    let mut header = bounded_reader(bytes, format).into_decoder().map_err(|_| "SCREENSHOT_DECODE: 无法读取图片尺寸")?;
    let dimensions = header.dimensions();
    validate_dimensions(dimensions.0, dimensions.1)?;
    let orientation = if format == ImageFormat::Jpeg { header.orientation().ok() } else { None };
    drop(header);
    let mut image = bounded_reader(bytes, format).decode().map_err(|_| "SCREENSHOT_DECODE: 图片损坏或解码超出内存限制")?;
    if let Some(orientation) = orientation { image.apply_orientation(orientation); }
    validate_dimensions(image.width(), image.height())?;
    Ok(image.into_rgba8())
}
struct BoundedWriter(Vec<u8>);
impl Write for BoundedWriter {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        if self.0.len().saturating_add(bytes.len()) > MAX_ENCODED_BYTES { return Err(std::io::Error::other("PNG exceeds 32 MiB")); }
        self.0.extend_from_slice(bytes); Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> { Ok(()) }
}
fn encode(image: &RgbaImage) -> Result<Vec<u8>,String> {
    let mut output = BoundedWriter(Vec::new());
    // Pixels only: no original EXIF, text, ICC metadata or editing layers.
    image::codecs::png::PngEncoder::new(&mut output).write_image(image.as_raw(), image.width(), image.height(), image::ExtendedColorType::Rgba8)
        .map_err(|_| "SCREENSHOT_ENCODE: 无法生成小于 32 MiB 的 PNG 图片")?;
    Ok(output.0)
}
fn from_base64(value: &str, png_only: bool) -> Result<RgbaImage,String> {
    if value.len() > MAX_ENCODED_BYTES.div_ceil(3) * 4 { return Err("SCREENSHOT_SIZE: 图片必须小于 32 MiB".into()); }
    let bytes = base64::engine::general_purpose::STANDARD.decode(value).map_err(|_| "SCREENSHOT_FORMAT: 无效图片数据")?;
    decode(&bytes, png_only)
}
fn make_session(id: u64, bytes: &[u8], captured_at: u64, source_name: Option<String>) -> Result<Session,String> {
    let pixels = decode(bytes, false)?;
    Ok(Session { id, png_base64: base64::engine::general_purpose::STANDARD.encode(encode(&pixels)?), width: pixels.width(), height: pixels.height(), captured_at, source_name })
}
fn capture_file_name(captured_at: u64) -> Result<String,String> {
    let timestamp = i64::try_from(captured_at).map_err(|_| "SCREENSHOT_TIME: 无效截图时间")?;
    let instant = chrono::DateTime::from_timestamp_millis(timestamp).ok_or("SCREENSHOT_TIME: 无效截图时间")?;
    Ok(format!("Screenshot_{}.png", instant.with_timezone(&chrono::Local).format("%Y-%m-%d_%H-%M-%S")))
}
fn read_image(path: &Path) -> Result<Vec<u8>,String> {
    // Reject devices/pipes before opening; O_NONBLOCK also closes the POSIX
    // check/open race if the chosen regular file is replaced with a FIFO.
    if !fs::metadata(path).map_err(|_| "SCREENSHOT_OPEN: 无法读取图片信息")?.is_file() { return Err("SCREENSHOT_OPEN: 请选择普通图片文件".into()); }
    let mut options = OpenOptions::new(); options.read(true);
    #[cfg(unix)]
    { use std::os::unix::fs::OpenOptionsExt; options.custom_flags(libc::O_NONBLOCK); }
    let file = options.open(path).map_err(|error| format!("SCREENSHOT_OPEN: 无法打开图片：{error}"))?;
    if !file.metadata().map_err(|_| "SCREENSHOT_OPEN: 无法读取图片信息")?.is_file() { return Err("SCREENSHOT_OPEN: 请选择普通图片文件".into()); }
    let mut bytes = Vec::new();
    file.take((MAX_ENCODED_BYTES + 1) as u64).read_to_end(&mut bytes).map_err(|error| format!("SCREENSHOT_OPEN: 无法读取图片：{error}"))?;
    if bytes.len() > MAX_ENCODED_BYTES { return Err("SCREENSHOT_SIZE: 图片必须小于 32 MiB".into()); }
    Ok(bytes)
}
/// create_new is the collision authority; checking exists first is not safe.
fn save_new_png(path: &Path, bytes: &[u8]) -> Result<PathBuf,String> {
    let parent = path.parent().ok_or("SCREENSHOT_SAVE: 无效文件夹")?;
    let stem = path.file_stem().and_then(|value| value.to_str()).filter(|s| !s.is_empty()).ok_or("SCREENSHOT_SAVE: 无效文件名")?;
    for suffix in 0..10_000 {
        let candidate = parent.join(if suffix == 0 { format!("{stem}.png") } else { format!("{stem}_{suffix}.png") });
        match OpenOptions::new().write(true).create_new(true).open(&candidate) {
            Ok(mut file) => {
                if let Err(error) = file.write_all(bytes).and_then(|_| file.sync_all()) {
                    // Do not unlink by path: another process could have
                    // replaced it after creation. Report the possible partial
                    // output rather than deleting a file we no longer own.
                    return Err(format!("SCREENSHOT_SAVE: 保存失败（磁盘或权限）；可能留下不完整文件 {}：{error}", candidate.display()));
                }
                return Ok(candidate);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("SCREENSHOT_SAVE: 无法写入所选文件夹：{error}")),
        }
    }
    Err("SCREENSHOT_SAVE: 同名文件过多，请另选文件名或文件夹".into())
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Directory { path: String, is_default: bool }
fn directory(app: &tauri::AppHandle) -> Result<Directory,String> {
    let configured = super::locked(&app.state::<super::AppState>().settings)?.screenshot_save_directory.clone();
    let is_default = configured.is_empty();
    let path = if is_default { app.path().desktop_dir().map_err(|_| "SCREENSHOT_DIRECTORY: 系统桌面不可用，请选择截图文件夹")? } else { PathBuf::from(configured) };
    Ok(Directory { path: path.to_string_lossy().into_owned(), is_default })
}
#[tauri::command]
pub fn get_screenshot_directory(app: tauri::AppHandle) -> Result<Directory,String> { directory(&app) }
fn persist_directory(app: &tauri::AppHandle, path: Option<PathBuf>) -> Result<Directory,String> {
    let state = app.state::<super::AppState>();
    let _maintenance = state.shortcut_maintenance.try_enter().ok_or("设置正在更新，请稍后再选择截图文件夹")?;
    let mut settings = super::locked(&state.settings)?;
    let mut next = settings.clone();
    next.screenshot_save_directory = path.map(|path| path.to_string_lossy().into_owned()).unwrap_or_default();
    super::model::validate_settings(&next)?;
    super::write_json(&state.data_dir.join("settings.json"), &next)?;
    *settings = next;
    drop(settings);
    directory(app)
}
#[tauri::command]
pub fn reset_screenshot_directory(app: tauri::AppHandle) -> Result<Directory,String> { persist_directory(&app, None) }

// Dialog creation stays on AppKit's UI thread on macOS. A later intent is
// checked after the modal result; cancelling a dialog never saves or publishes.
async fn dialog<T: Send + 'static>(app: &tauri::AppHandle, operation: impl FnOnce() -> T + Send + 'static) -> Result<T,String> {
    let (send, receive) = tokio::sync::oneshot::channel();
    app.run_on_main_thread(move || { let _ = send.send(operation()); }).map_err(|_| "SCREENSHOT_DIALOG: 无法打开系统对话框")?;
    receive.await.map_err(|_| "SCREENSHOT_DIALOG: 系统对话框被中断".into())
}
#[cfg(any(target_os = "macos", target_os = "windows"))]
async fn modal_dialog<T: Send + 'static>(app: &tauri::AppHandle, operation: impl FnOnce() -> T + Send + 'static) -> Result<T,String> {
    let handle = app.clone();
    dialog(app, move || {
        let state = handle.state::<super::AppState>();
        state.screenshots.dialog_active.store(true, Ordering::SeqCst);
        let result = operation();
        state.screenshots.dialog_active.store(false, Ordering::SeqCst);
        let cleared = state.screenshots.state.lock().is_ok_and(|image| image.image.is_none());
        if cleared { if let Some(window) = handle.get_webview_window(LABEL) { let _ = window.hide(); } }
        result
    }).await
}
#[tauri::command]
pub async fn choose_screenshot_directory(window: tauri::WebviewWindow, app: tauri::AppHandle) -> Result<Option<Directory>,String> {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
        let state = app.state::<super::AppState>();
        let _operation = state.screenshots.operations.try_acquire().map_err(|_| "SCREENSHOT_BUSY: 请先完成当前图片操作")?;
        let initial = directory(&app).ok().map(|directory| directory.path);
        let path = modal_dialog(&app, move || {
            let mut dialog = rfd::FileDialog::new().set_parent(&window).set_title("选择截图保存文件夹");
            if let Some(initial) = initial { dialog = dialog.set_directory(initial); }
            dialog.pick_folder()
        }).await?;
        path.map(|path| persist_directory(&app, Some(path))).transpose()
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    { let _ = (app, window); Err("截图文件夹选择仅支持 Windows 和 macOS".into()) }
}
#[tauri::command]
pub fn get_screenshot_session(window: tauri::WebviewWindow, state: tauri::State<super::AppState>) -> Result<Option<Session>,String> {
    ensure_editor(&window)?;
    Ok(super::locked(&state.screenshots.state)?.image.as_ref().map(|image| image.public.clone()))
}
#[tauri::command]
pub async fn screenshot_editor_ready(window: tauri::WebviewWindow, app: tauri::AppHandle, session_id: u64) -> Result<(),String> {
    ensure_editor(&window)?;
    let handle = app.clone();
    dialog(&app, move || {
        let state = handle.state::<super::AppState>();
        state.screenshots.with_image(session_id, |_| {
            let window = handle.get_webview_window(LABEL).ok_or("SCREENSHOT_WINDOW: 编辑器窗口不存在")?;
            window.show().and_then(|_| window.unminimize()).and_then(|_| window.set_focus()).map_err(|_| "SCREENSHOT_WINDOW: 无法显示编辑器".to_owned())
        })
    }).await?
}
#[tauri::command]
pub fn close_screenshot_editor(window: tauri::WebviewWindow, app: tauri::AppHandle, session_id: Option<u64>) -> Result<(),String> {
    ensure_editor(&window)?;
    let state = app.state::<super::AppState>();
    let mut screenshot = super::locked(&state.screenshots.state)?;
    if screenshot.intent != session_id { return Err(STALE.into()); }
    *screenshot = SessionState::default();
    // Invalidate only this editor; an unrelated newer OCR task is not cancelled.
    drop(screenshot);
    emit_cleared(&app, session_id);
    window.hide().map_err(|_| "SCREENSHOT_WINDOW: 无法关闭编辑器".into())
}
#[derive(Serialize)]
pub struct SaveResult { path: String }
#[tauri::command]
pub async fn save_screenshot_image(window: tauri::WebviewWindow, app: tauri::AppHandle, session_id: u64, png_base64: String, save_as: bool) -> Result<Option<SaveResult>,String> {
    ensure_editor(&window)?;
    let state = app.state::<super::AppState>();
    let _operation = state.screenshots.operations.try_acquire().map_err(|_| "SCREENSHOT_BUSY: 请先完成当前图片操作")?;
    let name = state.screenshots.with_image(session_id, |image| Ok(image.file_name.clone()))?;
    let destination = directory(&app);
    let path = if save_as {
        #[cfg(any(target_os = "macos", target_os = "windows"))]
        { let handle = app.clone();
          modal_dialog(&app, move || {
            if !handle.state::<super::AppState>().screenshots.current(session_id) { return Err(STALE.to_owned()); }
            let mut picker = rfd::FileDialog::new().set_parent(&window).set_title("另存 PNG（同名文件将自动编号，不覆盖）").add_filter("PNG", &["png"]).set_file_name(name);
            if let Ok(destination) = destination { picker = picker.set_directory(destination.path); }
            Ok(picker.save_file())
        }).await?? }
        #[cfg(not(any(target_os = "macos", target_os = "windows")))]
        { return Err("另存为仅支持 Windows 和 macOS".into()); }
    } else { Some(PathBuf::from(destination?.path).join(name)) };
    let Some(path) = path else { return Ok(None); };
    state.screenshots.with_image(session_id, |_| Ok(()))?;
    let worker_app = app.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let pixels = from_base64(&png_base64, true)?;
        let bytes = encode(&pixels)?;
        // Linearization point: the explicit Save is committed while this ID
        // is current. Disk I/O runs outside the state lock; a subsequent F1 may
        // proceed immediately, but does not undo this already accepted Save.
        worker_app.state::<super::AppState>().screenshots.with_image(session_id, |_| Ok(()))?;
        let saved = save_new_png(&path, &bytes)?;
        Ok(Some(SaveResult { path: saved.to_string_lossy().into_owned() }))
    }).await.map_err(|_| "SCREENSHOT_SAVE: 图片保存被中断".to_owned())?
}
#[tauri::command]
pub async fn copy_screenshot_image(window: tauri::WebviewWindow, app: tauri::AppHandle, session_id: u64, png_base64: String) -> Result<(),String> {
    ensure_editor(&window)?;
    let state = app.state::<super::AppState>();
    let _operation = state.screenshots.operations.try_acquire().map_err(|_| "SCREENSHOT_BUSY: 请先完成当前图片操作")?;
    state.screenshots.with_image(session_id, |_| Ok(()))?;
    let worker_app = app.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let pixels = from_base64(&png_base64, true)?;
        let state = worker_app.state::<super::AppState>();
        let _physical = state.native_tasks.enter_effect()?;
        // Commit only after prior native clipboard restoration has finished.
        // Keep the physical permit, but not the image state/UI lock, for I/O.
        state.screenshots.with_image(session_id, |_| Ok(()))?;
            #[cfg(any(target_os = "macos", target_os = "windows"))]
            {
                let mut clipboard = arboard::Clipboard::new().map_err(|_| "SCREENSHOT_CLIPBOARD: 无法打开图片剪贴板，请稍后重试")?;
                clipboard.set_image(arboard::ImageData { width: pixels.width() as usize, height: pixels.height() as usize, bytes: std::borrow::Cow::Borrowed(pixels.as_raw()) })
                    .map_err(|_| "SCREENSHOT_CLIPBOARD: 无法复制图片，剪贴板可能正被其他应用使用".to_owned())
            }
            #[cfg(not(any(target_os = "macos", target_os = "windows")))]
            { let _ = pixels; Err("图片剪贴板仅支持 Windows 和 macOS".into()) }
    }).await.map_err(|_| "SCREENSHOT_CLIPBOARD: 图片复制被中断".to_owned())?
}

async fn ensure_editor_window(app: &tauri::AppHandle, request: &super::native_tasks::Request) -> Result<(),String> {
    let handle = app.clone();
    let request = request.clone();
    dialog(app, move || {
        let state = handle.state::<super::AppState>();
        if !state.native_tasks.is_current(&request) || !state.screenshots.current(request.id()) { return Err(STALE.to_owned()); }
        if handle.get_webview_window(LABEL).is_none() {
            // Lazy creation keeps startup limited to the translator window.
            // Never await or hold intent/image locks while constructing WebView.
            let configuration = handle.config().app.windows.iter().find(|window| window.label == LABEL).ok_or("SCREENSHOT_WINDOW: 编辑器配置不存在")?;
            tauri::WebviewWindowBuilder::from_config(&handle, configuration)
                .map_err(|_| "SCREENSHOT_WINDOW: 无法配置截图编辑器")?
                .build().map_err(|_| "SCREENSHOT_WINDOW: 无法创建截图编辑器")?;
        }
        Ok(())
    }).await?
}
async fn publish(app: &tauri::AppHandle, request: &super::native_tasks::Request, session: Session) -> Result<(),String> {
    ensure_editor_window(app, request).await?;
    let state = app.state::<super::AppState>();
    state.native_tasks.publish(request, || {
        let file_name = capture_file_name(session.captured_at)?;
        state.screenshots.install_and_publish(session, file_name, |image| emit_session(app, image))
    }).unwrap_or_else(|| Err(STALE.into()))
}
fn restore_after_open(app: &tauri::AppHandle, request: &super::native_tasks::Request) {
    let state = app.state::<super::AppState>();
    state.native_tasks.publish(request, || {
        if let Ok(mut image) = state.screenshots.state.lock() {
            if image.intent == Some(request.id()) {
                image.intent = image.image.as_ref().map(|image| image.public.id);
            }
        }
    });
}
#[tauri::command]
pub async fn open_screenshot_image(window: tauri::WebviewWindow, app: tauri::AppHandle, session_id: Option<u64>) -> Result<Option<Session>,String> {
    if !matches!(window.label(), "main" | LABEL) { return Err("SCREENSHOT_WINDOW: 无效窗口".into()); }
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
        let state = app.state::<super::AppState>();
        let _operation = state.screenshots.operations.try_acquire().map_err(|_| "SCREENSHOT_BUSY: 请先完成当前图片操作")?;
        if let Some(id) = session_id { state.screenshots.with_image(id, |_| Ok(()))?; }
        let request = state.native_tasks.begin()?;
        state.native_tasks.publish(&request, || {
            let mut image = super::locked(&state.screenshots.state)?;
            image.intent = Some(request.id()); // retain prior pixels if Open is cancelled
            Ok::<_,String>(())
        }).ok_or(STALE)??;
        let _ = state.translation_requests.cancel(None);
        let handle = app.clone();
        let dialog_request = request.clone();
        let path = modal_dialog(&app, move || {
            let state = handle.state::<super::AppState>();
            if !state.native_tasks.is_current(&dialog_request) || !state.screenshots.current(dialog_request.id()) { return Err(STALE.to_owned()); }
            Ok(rfd::FileDialog::new().set_parent(&window).set_title("打开本地 PNG / JPEG 图片").add_filter("PNG / JPEG", &["png", "jpg", "jpeg"]).pick_file())
        }).await.and_then(|result| result);
        let path = match path {
            Ok(Some(path)) => path,
            Ok(None) => { restore_after_open(&app, &request); return Ok(None); }
            Err(error) => { restore_after_open(&app, &request); return Err(error); }
        };
        if !state.native_tasks.is_current(&request) || !state.screenshots.current(request.id()) { return Err(STALE.into()); }
        let id = request.id();
        let worker_app = app.clone();
        let worker_request = request.clone();
        let result = tauri::async_runtime::spawn_blocking(move || {
            let state = worker_app.state::<super::AppState>();
            // Await real cancelled-capture/selection cleanup before an imported
            // image can become available for a clipboard mutation.
            let _physical = state.native_tasks.enter(&worker_request)?;
            if !state.screenshots.current(id) { return Err(STALE.into()); }
            let source_name = path.file_name().map(|name| name.to_string_lossy().into_owned());
            make_session(id, &read_image(&path)?, super::now(), source_name)
        }).await.map_err(|_| "SCREENSHOT_OPEN: 图片读取被中断".to_owned()).and_then(|result| result);
        match result {
            Ok(session) => {
                if let Err(error) = publish(&app, &request, session.clone()).await {
                    restore_after_open(&app, &request);
                    return Err(error);
                }
                Ok(Some(session))
            }
            Err(error) => { restore_after_open(&app, &request); Err(error) }
        }
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    { let _ = (app, session_id); Err("本地图片打开仅支持 Windows 和 macOS".into()) }
}

/// F1's only native capture path. It deliberately never reads provider settings
/// and never routes its image through source-text / OCR / translation history.
pub fn start_capture(app: tauri::AppHandle) {
    invalidate(&app);
    super::cancel_active_translation(&app);
    let state = app.state::<super::AppState>();
    let request = match state.native_tasks.begin() {
        Ok(request) => request,
        Err(error) => { let _ = app.emit("action-error", error); return; }
    };
    let Some(Ok(presentation)) = super::begin_native_request_presentation(&state.native_tasks, &request, &state.translation_requests, false, |presentation| super::announce_presentation(&app, presentation)) else { return; };
    if !matches!(state.native_tasks.publish(&request, || state.screenshots.begin(request.id())), Some(Ok(()))) { return; }
    tauri::async_runtime::spawn(async move {
        let state = app.state::<super::AppState>();
        // A new F1 supersedes the old intent immediately, but waits for an
        // explicit native file dialog / committed export to finish before
        // opening its selector. Stale queued captures never launch a helper.
        let Ok(_operation) = state.screenshots.operations.acquire().await else { return; };
        if !state.native_tasks.is_current(&request) { return; }
        let result: Result<Session, String> = async {
            super::hide_native_capture_window(&app, &request, presentation).await?;
            #[cfg(target_os = "macos")]
            super::verify_capture_application_policy(&app).await?;
            let worker_app = app.clone();
            let worker_request = request.clone();
            tauri::async_runtime::spawn_blocking(move || {
                let state = worker_app.state::<super::AppState>();
                let _physical = state.native_tasks.enter(&worker_request)?;
                if !state.screenshots.current(worker_request.id()) { return Err(STALE.into()); }
                let encoded = super::platform::capture_screenshot_cancelable(worker_request.cancellation())?;
                let captured_at = super::now();
                if worker_request.cancelled() { return Err(STALE.into()); }
                if encoded.len() > MAX_ENCODED_BYTES.div_ceil(3) * 4 { return Err("SCREENSHOT_SIZE: 图片过大".into()); }
                let bytes = base64::engine::general_purpose::STANDARD.decode(encoded).map_err(|_| "SCREENSHOT_FORMAT: 无效截图数据")?;
                let session = make_session(worker_request.id(), &bytes, captured_at, None)?;
                if worker_request.cancelled() { return Err(STALE.into()); }
                Ok(session)
            }).await.map_err(|_| "SCREENSHOT_CAPTURE: 截图操作被中断".to_owned())?
        }.await;
        let outcome = match result {
            Ok(session) => publish(&app, &request, session).await,
            Err(error) => Err(error),
        };
        if let Err(error) = outcome {
            super::publish_native_result(&app, &request, presentation, false, || {
                if let Some(failure) = super::action_failure_presentation("screenshot", &error, presentation.epoch) {
                    super::emit_source_text(&app, super::source_with_action_error(failure.source, failure.error));
                }
            });
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    fn png() -> Vec<u8> { encode(&RgbaImage::from_pixel(3, 2, image::Rgba([12,34,56,255]))).unwrap() }
    #[test]
    fn image_round_trip_is_png_pixels_only_and_has_bounded_dimensions() {
        let bytes = png(); let decoded = decode(&bytes, true).unwrap();
        assert_eq!(decoded.dimensions(), (3,2)); assert_eq!(decoded.get_pixel(1,1).0, [12,34,56,255]);
        assert!(validate_dimensions(16_385,1).is_err()); assert!(validate_dimensions(8000,8000).is_err());
        assert!(validate_dimensions(0,1).is_err()); assert!(validate_dimensions(8000,4000).is_ok());
        assert!(decode(b"not a png", false).is_err());
        assert!(decode(b"GIF89a", false).is_err());
        assert!(from_base64("data:image/png;base64,AA==", true).is_err());
    }
    #[test]
    fn jpeg_is_accepted_for_local_open_but_not_flattened_export_input() {
        let image = image::RgbImage::from_pixel(4, 3, image::Rgb([23, 45, 67]));
        let mut bytes = Vec::new();
        image::codecs::jpeg::JpegEncoder::new(&mut bytes).encode(image.as_raw(), 4, 3, image::ExtendedColorType::Rgb8).unwrap();
        assert_eq!(decode(&bytes, false).unwrap().dimensions(), (4, 3));
        assert!(decode(&bytes, true).is_err());
        let session = make_session(1, &bytes, 123, Some("original.jpg".into())).unwrap();
        let normalized = base64::engine::general_purpose::STANDARD.decode(session.png_base64).unwrap();
        assert_eq!(image::guess_format(&normalized).unwrap(), ImageFormat::Png);
    }
    #[test]
    fn jpeg_exif_orientation_is_baked_into_pixels_before_metadata_is_removed() {
        let image = image::RgbImage::from_pixel(4, 3, image::Rgb([23, 45, 67]));
        let mut bytes = Vec::new();
        image::codecs::jpeg::JpegEncoder::new(&mut bytes).encode(image.as_raw(), 4, 3, image::ExtendedColorType::Rgb8).unwrap();
        let mut exif = b"Exif\0\0".to_vec();
        exif.extend_from_slice(&[b'I', b'I', 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0]);
        let mut segment = vec![0xff, 0xe1];
        segment.extend_from_slice(&((exif.len() + 2) as u16).to_be_bytes()); segment.extend_from_slice(&exif);
        bytes.splice(2..2, segment);
        let session = make_session(1, &bytes, 1, None).unwrap();
        assert_eq!((session.width, session.height), (3, 4));
        let exported = base64::engine::general_purpose::STANDARD.decode(session.png_base64).unwrap();
        assert!(!exported.windows(6).any(|part| part == b"Exif\0\0"));
    }
    #[test]
    fn local_open_rejects_directories_without_reading_them() {
        assert!(read_image(&std::env::temp_dir()).is_err());
    }
    #[test]
    fn exported_png_contains_no_original_text_metadata() {
        let mut bytes = png();
        let payload = b"Comment\0private-original-metadata";
        let mut chunk = b"tEXt".to_vec(); chunk.extend_from_slice(payload);
        let mut crc = !0u32;
        for byte in &chunk { crc ^= u32::from(*byte); for _ in 0..8 { crc = (crc >> 1) ^ (0xedb88320u32 & (0u32.wrapping_sub(crc & 1))); } }
        let mut encoded = (payload.len() as u32).to_be_bytes().to_vec();
        encoded.extend_from_slice(&chunk); encoded.extend_from_slice(&(!crc).to_be_bytes());
        bytes.splice(bytes.len() - 12..bytes.len() - 12, encoded);
        let session = make_session(1, &bytes, 1, None).unwrap();
        let flattened = base64::engine::general_purpose::STANDARD.decode(session.png_base64).unwrap();
        assert!(!flattened.windows(payload.len()).any(|window| window == payload));
        assert_eq!(decode(&flattened, true).unwrap().get_pixel(0, 0).0, [12, 34, 56, 255]);
    }
    #[test]
    fn oversized_png_header_is_rejected_before_pixel_decode() {
        let mut bytes = png();
        bytes[16..20].copy_from_slice(&20_000u32.to_be_bytes());
        assert!(decode(&bytes, false).is_err());
    }
    #[test]
    fn bounded_writer_never_retains_an_oversized_output() {
        let mut writer = BoundedWriter(vec![0; MAX_ENCODED_BYTES]);
        assert!(writer.write_all(&[1]).is_err()); assert_eq!(writer.0.len(), MAX_ENCODED_BYTES);
    }
    #[test]
    fn translator_hide_and_cancelled_open_preserve_the_committed_editor_document() {
        let controller = Controller::default(); controller.begin(1).unwrap();
        controller.install(make_session(1, &png(), 1, None).unwrap(), "first.png".into()).unwrap();
        controller.cancel_pending();
        assert!(controller.with_image(1, |_| Ok(())).is_ok());
        controller.state.lock().unwrap().intent = Some(2); // pending native Open
        controller.cancel_pending();
        assert!(controller.with_image(1, |_| Ok(())).is_ok());
        assert!(!controller.current(2));
        controller.begin(3).unwrap(); // explicit new F1 still supersedes
        controller.cancel_pending();
        assert!(!controller.current(3));
        assert!(controller.with_image(1, |_| Ok(())).is_err());
    }
    #[test]
    fn failed_image_delivery_restores_previous_committed_document() {
        let controller = Controller::default(); controller.begin(1).unwrap();
        controller.install(make_session(1, &png(), 1, None).unwrap(), "first.png".into()).unwrap();
        controller.state.lock().unwrap().intent = Some(2);
        assert!(controller.install_and_publish(make_session(2, &png(), 2, None).unwrap(), "second.png".into(), |_| Err("delivery failed".into())).is_err());
        assert!(controller.with_image(1, |_| Ok(())).is_ok());
        assert!(controller.with_image(2, |_| Ok(())).is_err());
    }
    #[cfg(unix)]
    #[test]
    fn local_open_rejects_a_named_pipe_without_waiting_for_a_writer() {
        use std::os::unix::ffi::OsStrExt;
        let path = std::env::temp_dir().join(format!("echolingo-screenshot-pipe-{}-{}", std::process::id(), super::super::now()));
        let name = std::ffi::CString::new(path.as_os_str().as_bytes()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(name.as_ptr(), 0o600) }, 0);
        let result = read_image(&path);
        fs::remove_file(path).unwrap();
        assert!(result.is_err());
    }
    #[test]
    fn stale_image_id_cannot_publish_copy_or_save_after_replacement() {
        let controller = Controller::default(); controller.begin(1).unwrap();
        controller.install(make_session(1, &png(), 1, None).unwrap(), "first.png".into()).unwrap();
        assert!(controller.with_image(1, |_| Ok(())).is_ok());
        controller.begin(2).unwrap();
        assert!(controller.with_image::<()>(1, |_| panic!("stale effect")).is_err());
        assert!(controller.install(make_session(1, &png(), 1, None).unwrap(), "old.png".into()).is_err());
        controller.install(make_session(2, &png(), 2, None).unwrap(), "new.png".into()).unwrap();
        assert!(controller.with_image(2, |_| Ok(())).is_ok());
    }
    #[test]
    fn exports_never_overwrite_source_or_colliding_capture_names() {
        let directory = std::env::temp_dir().join(format!("echolingo-screenshot-{}-{}", std::process::id(), super::super::now()));
        fs::create_dir_all(&directory).unwrap();
        let original = directory.join("Screenshot_2026-10-31_10-11-12.png");
        fs::write(&original, b"original").unwrap();
        let bytes = png();
        let first = save_new_png(&original, &bytes).unwrap();
        let second = save_new_png(&original, &bytes).unwrap();
        assert_eq!(fs::read(&original).unwrap(), b"original"); assert_ne!(first, second);
        assert!(first.ends_with("Screenshot_2026-10-31_10-11-12_1.png"));
        assert_eq!(fs::read(&first).unwrap(), bytes);
        assert!(save_new_png(&directory.join("missing/file.png"), &bytes).is_err());
        fs::remove_dir_all(directory).unwrap();
    }
    #[test]
    fn capture_filename_is_from_stable_capture_timestamp_not_save_time() {
        let first = capture_file_name(1_793_415_000_000).unwrap();
        assert_eq!(first, capture_file_name(1_793_415_000_000).unwrap());
        assert!(first.starts_with("Screenshot_")); assert!(first.ends_with(".png"));
        assert_eq!(first.len(), "Screenshot_2026-10-31_10-11-12.png".len());
    }
}
