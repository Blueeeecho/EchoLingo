//! Isolated native capture child. No PowerShell/CLR, clipboard, credentials or network.
//! Window procedures enqueue bounded scalar events only; rendering runs outside them.
#[path = "windows_capture_ffi.rs"]
mod w;
use crate::policy::*;
use crate::protocol as wire;
use std::{
    collections::{BTreeMap, HashSet, VecDeque},
    ptr::{null, null_mut},
    sync::{
        atomic::{AtomicBool, AtomicU32, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
type Result<T> = std::result::Result<T, String>;
const TOPMOST: w::H = -1isize as w::H;
const PLANE_EX: u32 = 0x0020_0000 | 0x0800_0000 | 0x80 | 8;
const EDGE_EX: u32 = 0x0008_0000 | 0x20 | 0x0800_0000 | 0x80 | 8;
const LOUPE_EX: u32 = 0x20 | 0x0800_0000 | 0x80 | 8;
const POS: u32 = 0x10 | 0x200;
const SRCCOPY: u32 = 0x00CC0020;
const CAPTUREBLT: u32 = 0x40000000;
const MAX_PIXELS: usize = 32_000_000;
pub struct Request {
    pub purpose: CapturePurpose,
    pub owner_process: u32,
    pub host_thread: u32,
    pub host_token: i64,
    pub cancellation: String,
}
fn error(kind: &str) -> String {
    format!("{kind}: Native screenshot selection stopped safely; retry.")
}
fn from_rect(r: w::Rect) -> Rect {
    Rect::from_ltrb(r.left, r.top, r.right, r.bottom)
}
fn pointer() -> Result<Point> {
    let mut p = w::Point::default();
    if unsafe { w::GetPhysicalCursorPos(&mut p) } == 0 {
        return Err(error("CAPTURE_POINTER"));
    }
    Ok(Point::new(p.x, p.y))
}
fn down(key: i32) -> bool {
    unsafe { w::GetAsyncKeyState(key) < 0 }
}
fn set_bounds(hwnd: w::H, after: w::H, r: Rect, flags: u32) -> Result<()> {
    if unsafe { w::SetWindowPos(hwnd, after, r.x, r.y, r.width, r.height, flags) } == 0 {
        Err(error("CAPTURE_OVERLAY"))
    } else {
        Ok(())
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Role {
    Probe,
    Mailbox,
    Plane(usize),
    Edge(usize),
    Loupe,
}
#[derive(Clone, Copy)]
enum Event {
    Display,
    Dpi {
        role: Role,
        hwnd: isize,
        value: usize,
    },
    Mouse(u32, Point),
    Wire(u32, usize, isize),
    Escape(bool),
    Cancel(u32),
}
struct Inbox {
    events: Mutex<VecDeque<Event>>,
    failed: AtomicBool,
    decorative_cancellations: AtomicU32,
}
impl Default for Inbox {
    fn default() -> Self {
        Self {
            events: Mutex::new(VecDeque::with_capacity(256)),
            failed: AtomicBool::new(false),
            decorative_cancellations: AtomicU32::new(0),
        }
    }
}
impl Inbox {
    fn push(&self, e: Event) {
        if let Ok(mut q) = self.events.try_lock() {
            if q.len() < 256 {
                q.push_back(e);
            } else {
                self.failed.store(true, Ordering::SeqCst);
            }
        } else {
            self.failed.store(true, Ordering::SeqCst);
        }
    }
    fn take(&self) -> VecDeque<Event> {
        let mut next = VecDeque::with_capacity(256);
        if let Ok(mut queue) = self.events.try_lock() {
            std::mem::swap(&mut *queue, &mut next);
        } else {
            self.failed.store(true, Ordering::SeqCst);
        }
        next
    }
}
struct Node {
    role: Role,
    inbox: Arc<Inbox>,
    canvas: Arc<Mutex<Option<Surface>>>,
}
unsafe extern "system" fn window_proc(hwnd: w::H, msg: u32, wp: usize, lp: isize) -> isize {
    if msg == 0x81 {
        let create = &*(lp as *const w::CreateStruct);
        w::SetWindowLongPtrW(hwnd, -21, create.param as isize);
    }
    let node = w::GetWindowLongPtrW(hwnd, -21) as *const Node;
    if node.is_null() {
        return w::DefWindowProcW(hwnd, msg, wp, lp);
    }
    let node = &*node;
    if msg == 0x82 {
        w::SetWindowLongPtrW(hwnd, -21, 0);
        return w::DefWindowProcW(hwnd, msg, wp, lp);
    }
    let work = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| -> Option<isize> {
        if msg == 0x21 {
            return Some(3);
        } // MA_NOACTIVATE
        if msg == 0x84 {
            return Some(if node.role == Role::Loupe { -1 } else { 1 });
        }
        if msg == 0x14 {
            return Some(1);
        }
        if msg == 0x7e {
            node.inbox.push(Event::Display);
            return Some(0);
        }
        if msg == 0x2e0 {
            node.inbox.push(Event::Dpi {
                role: node.role,
                hwnd: hwnd as isize,
                value: wp,
            });
            return Some(0);
        }
        if msg == 0x1f || msg == 0x215 {
            if capture_window_cancels(matches!(node.role, Role::Plane(_)), msg) {
                node.inbox.push(Event::Cancel(msg));
            } else {
                node.inbox
                    .decorative_cancellations
                    .fetch_add(1, Ordering::Relaxed);
            }
            return Some(0);
        }
        if msg >= wire::READY_ACK && msg <= wire::DRAG_EXCURSION {
            node.inbox.push(Event::Wire(msg, wp, lp));
            return Some(0);
        }
        if let Role::Plane(_) = node.role {
            if matches!(msg, 0x201 | 0x202 | 0x204 | 0x205) {
                let mut p = w::Point {
                    x: (lp as u16 as i16) as i32,
                    y: ((lp as usize >> 16) as u16 as i16) as i32,
                };
                if w::ClientToScreen(hwnd, &mut p) != 0 {
                    node.inbox.push(Event::Mouse(msg, Point::new(p.x, p.y)));
                } else {
                    node.inbox.failed.store(true, Ordering::SeqCst);
                }
                return Some(0);
            }
            if (0x200..=0x20e).contains(&msg) {
                return Some(0);
            }
        }
        if msg == 0xf {
            let mut paint: w::Paint = std::mem::zeroed();
            let dc = w::BeginPaint(hwnd, &mut paint);
            if !dc.is_null() {
                if matches!(node.role, Role::Edge(_)) {
                    let brush = w::CreateSolidBrush(w::rgb(45, 145, 255));
                    let mut bounds = w::Rect::default();
                    w::GetClientRect(hwnd, &mut bounds);
                    w::FillRect(dc, &bounds, brush);
                    w::DeleteObject(brush);
                } else if node.role == Role::Loupe {
                    if let Ok(canvas) = node.canvas.lock() {
                        if let Some(canvas) = canvas.as_ref() {
                            w::BitBlt(
                                dc,
                                0,
                                0,
                                canvas.width,
                                canvas.height,
                                canvas.dc,
                                0,
                                0,
                                SRCCOPY,
                            );
                        }
                    }
                }
            }
            w::EndPaint(hwnd, &paint);
            return Some(0);
        }
        Some(w::DefWindowProcW(hwnd, msg, wp, lp))
    }));
    match work {
        Ok(Some(value)) => value,
        _ => {
            node.inbox.failed.store(true, Ordering::SeqCst);
            0
        }
    }
}
struct Class {
    name: Vec<u16>,
    instance: w::H,
}
impl Class {
    fn new() -> Result<Self> {
        let name = w::wide(&format!("EchoLingoNativeCapture-{}", std::process::id()));
        let instance = unsafe { w::GetModuleHandleW(null()) };
        let class = w::WndClass {
            size: std::mem::size_of::<w::WndClass>() as u32,
            style: 0,
            proc: Some(window_proc),
            class_extra: 0,
            window_extra: 0,
            instance,
            icon: null_mut(),
            cursor: unsafe { w::LoadCursorW(null_mut(), 32515usize as _) },
            background: null_mut(),
            menu: null(),
            name: name.as_ptr(),
            small_icon: null_mut(),
        };
        if unsafe { w::RegisterClassExW(&class) } == 0 {
            return Err(error("CAPTURE_WINDOW_CLASS"));
        }
        Ok(Self { name, instance })
    }
}
impl Drop for Class {
    fn drop(&mut self) {
        unsafe {
            w::UnregisterClassW(self.name.as_ptr(), self.instance);
        }
    }
}
struct Window {
    hwnd: w::H,
    node: Box<Node>,
}
impl Window {
    fn new(
        class: &Class,
        role: Role,
        bounds: Rect,
        inbox: Arc<Inbox>,
        canvas: Arc<Mutex<Option<Surface>>>,
    ) -> Result<Self> {
        let mut node = Box::new(Node {
            role,
            inbox,
            canvas,
        });
        let ex = match role {
            Role::Plane(_) => PLANE_EX,
            Role::Edge(_) => EDGE_EX,
            Role::Loupe => LOUPE_EX,
            _ => 0x08000080,
        };
        let title = w::wide(if role == Role::Loupe {
            "EchoLingoCaptureMagnifier"
        } else {
            ""
        });
        let parent = if role == Role::Mailbox {
            -3isize as _
        } else {
            null_mut()
        };
        let hwnd = unsafe {
            w::CreateWindowExW(
                ex,
                class.name.as_ptr(),
                title.as_ptr(),
                0x80000000,
                bounds.x,
                bounds.y,
                bounds.width.max(1),
                bounds.height.max(1),
                parent,
                null_mut(),
                class.instance,
                (&mut *node as *mut Node).cast(),
            )
        };
        if hwnd.is_null() {
            return Err(error("CAPTURE_WINDOW"));
        }
        if matches!(role, Role::Edge(_)) {
            if unsafe { w::SetLayeredWindowAttributes(hwnd, w::rgb(255, 0, 255), 255, 1) } == 0 {
                if unsafe { w::DestroyWindow(hwnd) } == 0 {
                    std::mem::forget(node);
                }
                return Err(error("CAPTURE_EDGE"));
            }
        }
        if role == Role::Loupe {
            unsafe {
                w::EnableWindow(hwnd, 0);
            }
        }
        Ok(Self { hwnd, node })
    }
    fn destroy(&mut self) -> bool {
        if self.hwnd.is_null() {
            return true;
        }
        if unsafe { w::DestroyWindow(self.hwnd) } == 0 {
            return false;
        }
        self.hwnd = null_mut();
        true
    }
    fn hide(&self) {
        unsafe {
            w::ShowWindow(self.hwnd, 0);
        }
    }
    fn visible(&self) -> bool {
        unsafe { w::IsWindowVisible(self.hwnd) != 0 }
    }
    fn bounds(&self) -> Result<Rect> {
        let mut r = w::Rect::default();
        if unsafe { w::GetWindowRect(self.hwnd, &mut r) } == 0 {
            Err(error("CAPTURE_WINDOW_BOUNDS"))
        } else {
            Ok(from_rect(r))
        }
    }
}
impl Drop for Window {
    fn drop(&mut self) {
        if !self.destroy() {
            // Keep callback state alive until process teardown if Windows refused destruction.
            let retained = std::mem::replace(
                &mut self.node,
                Box::new(Node {
                    role: Role::Probe,
                    inbox: Arc::new(Inbox::default()),
                    canvas: Arc::new(Mutex::new(None)),
                }),
            );
            std::mem::forget(retained);
        }
    }
}
struct Surface {
    dc: w::H,
    bitmap: w::H,
    previous: w::H,
    bits: *mut u8,
    width: i32,
    height: i32,
}
// GDI handles and every canvas owner stay on the native UI thread; Surface is
// intentionally not Send/Sync. WM_PAINT borrows it only during synchronous redraw.
impl Surface {
    fn new(width: i32, height: i32) -> Result<Self> {
        Self::allocate(width, height, true)
    }
    fn preview(width: i32, height: i32) -> Result<Self> {
        // Preview pixels stay in GDI: do not force the screen through a
        // CPU-readable DIB on every live frame. PNG output still uses new().
        Self::allocate(width, height, false)
    }
    fn allocate(width: i32, height: i32, readable: bool) -> Result<Self> {
        if width <= 0
            || height <= 0
            || (width as usize)
                .checked_mul(height as usize)
                .is_none_or(|n| n > MAX_PIXELS)
        {
            return Err(error("CAPTURE_TOO_LARGE"));
        }
        let dc = unsafe { w::CreateCompatibleDC(null_mut()) };
        if dc.is_null() {
            return Err(error("CAPTURE_BITMAP"));
        }
        let info = w::BitmapInfo {
            header: w::BitmapHeader {
                size: std::mem::size_of::<w::BitmapHeader>() as u32,
                width,
                height: -height,
                planes: 1,
                bit_count: 32,
                compression: 0,
                size_image: 0,
                x_pels: 0,
                y_pels: 0,
                colors_used: 0,
                colors_important: 0,
            },
            colors: [0],
        };
        let mut bits = null_mut();
        let bitmap = if readable {
            unsafe { w::CreateDIBSection(dc, &info, 0, &mut bits, null_mut(), 0) }
        } else {
            unsafe {
                let screen = w::GetDC(null_mut());
                if screen.is_null() {
                    w::DeleteDC(dc);
                    return Err(error("CAPTURE_BITMAP"));
                }
                // Use the display DC, not the memory DC's initial monochrome
                // bitmap. Acquisition and release remain on this UI thread.
                let bitmap = w::CreateCompatibleBitmap(screen, width, height);
                w::ReleaseDC(null_mut(), screen);
                bitmap
            }
        };
        if bitmap.is_null() || (readable && bits.is_null()) {
            unsafe {
                if !bitmap.is_null() {
                    w::DeleteObject(bitmap);
                }
                w::DeleteDC(dc);
            }
            return Err(error("CAPTURE_BITMAP"));
        }
        let previous = unsafe { w::SelectObject(dc, bitmap) };
        if previous.is_null() || previous as isize == -1 {
            unsafe {
                w::DeleteObject(bitmap);
                w::DeleteDC(dc);
            }
            return Err(error("CAPTURE_BITMAP"));
        }
        Ok(Self {
            dc,
            bitmap,
            previous,
            bits: bits.cast(),
            width,
            height,
        })
    }
    fn clear(&self, color: u32) {
        unsafe {
            let brush = w::CreateSolidBrush(color);
            w::FillRect(
                self.dc,
                &w::Rect {
                    left: 0,
                    top: 0,
                    right: self.width,
                    bottom: self.height,
                },
                brush,
            );
            w::DeleteObject(brush);
        }
    }
    fn copy_screen(&self, target: Point, source: Rect, include_layered: bool) -> Result<()> {
        self.copy_screen_timed(target, source, include_layered)
            .map(|_| ())
    }
    fn copy_screen_timed(
        &self,
        target: Point,
        source: Rect,
        include_layered: bool,
    ) -> Result<[u64; 3]> {
        if source.is_empty() {
            return Ok([0; 3]);
        }
        unsafe {
            let started = Instant::now();
            let screen = w::GetDC(null_mut());
            let acquire = started.elapsed().as_millis().min(10_000_000) as u64;
            if screen.is_null() {
                return Err(error("CAPTURE_PIXELS"));
            }
            let started = Instant::now();
            let ok = w::BitBlt(
                self.dc,
                target.x,
                target.y,
                source.width,
                source.height,
                screen,
                source.x,
                source.y,
                SRCCOPY | if include_layered { CAPTUREBLT } else { 0 },
            );
            let blit = started.elapsed().as_millis().min(10_000_000) as u64;
            let started = Instant::now();
            w::ReleaseDC(null_mut(), screen);
            let release = started.elapsed().as_millis().min(10_000_000) as u64;
            if ok == 0 {
                Err(error("CAPTURE_PIXELS"))
            } else {
                Ok([acquire, blit, release])
            }
        }
    }
    fn png(&mut self) -> Result<Vec<u8>> {
        if self.bits.is_null() {
            return Err(error("CAPTURE_BITMAP_NOT_READABLE"));
        }
        if unsafe { w::GdiFlush() } == 0 {
            return Err(error("CAPTURE_BITMAP_SYNC"));
        }
        let size = (self.width as usize) * (self.height as usize) * 4;
        let rgba = unsafe { std::slice::from_raw_parts_mut(self.bits, size) };
        for pixel in rgba.chunks_exact_mut(4) {
            pixel.swap(0, 2);
            pixel[3] = 255;
        }
        let mut bytes = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut bytes, self.width as u32, self.height as u32);
            encoder.set_color(png::ColorType::Rgba);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder.write_header().map_err(|_| error("CAPTURE_PNG"))?;
            writer
                .write_image_data(rgba)
                .map_err(|_| error("CAPTURE_PNG"))?;
        }
        if bytes.len() > 8 * 1024 * 1024 {
            return Err(error("CAPTURE_TOO_LARGE"));
        }
        Ok(bytes)
    }
}
impl Drop for Surface {
    fn drop(&mut self) {
        unsafe {
            w::SelectObject(self.dc, self.previous);
            w::DeleteObject(self.bitmap);
            w::DeleteDC(self.dc);
        }
    }
}
struct Cancellation(w::H);
impl Cancellation {
    fn open(name: &str) -> Result<Self> {
        if !name.starts_with("Local\\EchoLingo-cancel-")
            || name.len() > 128
            || !name["Local\\EchoLingo-cancel-".len()..]
                .bytes()
                .all(|b| b.is_ascii_hexdigit() || b == b'-')
        {
            return Err(error("NATIVE_CANCEL"));
        }
        let name = w::wide(name);
        let h = unsafe { w::OpenEventW(0x100000, 0, name.as_ptr()) };
        if h.is_null() {
            Err(error("NATIVE_CANCEL"))
        } else {
            Ok(Self(h))
        }
    }
    fn requested(&self) -> Result<bool> {
        match unsafe { w::WaitForSingleObject(self.0, 0) } {
            0 => Ok(true),
            258 => Ok(false),
            _ => Err(error("NATIVE_CANCEL")),
        }
    }
}
impl Drop for Cancellation {
    fn drop(&mut self) {
        unsafe {
            w::CloseHandle(self.0);
        }
    }
}
fn input_desktop() -> Result<()> {
    fn name(h: w::H) -> Option<Vec<u16>> {
        if h.is_null() {
            return None;
        }
        let mut buffer = [0u16; 256];
        let mut needed = 0;
        if unsafe {
            w::GetUserObjectInformationW(h, 2, buffer.as_mut_ptr().cast(), 512, &mut needed)
        } == 0
        {
            return None;
        }
        Some(buffer[..buffer.iter().position(|x| *x == 0).unwrap_or(buffer.len())].to_vec())
    }
    let active = unsafe { w::OpenInputDesktop(0, 0, 1) };
    let a = name(active);
    let b = name(unsafe { w::GetThreadDesktop(w::CurrentThreadId()) });
    if !active.is_null() {
        unsafe {
            w::CloseDesktop(active);
        }
    }
    if a.is_none() || a != b {
        Err(error("CAPTURE_DESKTOP_UNAVAILABLE"))
    } else {
        Ok(())
    }
}
unsafe extern "system" fn enum_monitor(
    monitor: w::H,
    _dc: w::H,
    _rect: *mut w::Rect,
    data: isize,
) -> i32 {
    let list = &mut *(data as *mut Vec<w::Monitor>);
    let mut info: w::Monitor = std::mem::zeroed();
    info.size = std::mem::size_of::<w::Monitor>() as u32;
    if w::GetMonitorInfoW(monitor, &mut info) == 0 {
        return 0;
    }
    list.push(info);
    1
}
fn topology(
    class: &Class,
    inbox: &Arc<Inbox>,
    canvas: &Arc<Mutex<Option<Surface>>>,
) -> Result<CaptureTopologyPolicy> {
    let mut monitors: Vec<w::Monitor> = Vec::new();
    if unsafe {
        w::EnumDisplayMonitors(
            null_mut(),
            null(),
            Some(enum_monitor),
            (&mut monitors as *mut Vec<w::Monitor>) as isize,
        )
    } == 0
    {
        return Err(error("CAPTURE_DISPLAY_CHANGED"));
    }
    let mut displays = Vec::new();
    for monitor in monitors {
        let bounds = from_rect(monitor.rect);
        if !bounds.valid() {
            return Err(error("CAPTURE_DISPLAY_CHANGED"));
        }
        let probe = Window::new(
            class,
            Role::Probe,
            Rect::new(
                bounds.x + bounds.width / 2,
                bounds.y + bounds.height / 2,
                1,
                1,
            ),
            inbox.clone(),
            canvas.clone(),
        )?;
        let dpi = unsafe { w::GetDpiForWindow(probe.hwnd) };
        let len = monitor.device.iter().position(|x| *x == 0).unwrap_or(32);
        displays.push(CaptureDisplaySnapshot {
            device: String::from_utf16_lossy(&monitor.device[..len]),
            bounds,
            dpi,
        });
    }
    CaptureTopologyPolicy::new(displays, unsafe {
        w::GetAwarenessFromDpiAwarenessContext(w::GetThreadDpiAwarenessContext())
    })
    .map_err(str::to_owned)
}
struct EscapeState {
    inbox: Arc<Inbox>,
    initial: AtomicBool,
    ownership: EscOwnership,
    downs: AtomicU32,
    ups: AtomicU32,
}
thread_local! {static ESCAPE:std::cell::RefCell<Option<Arc<EscapeState>>>=const{std::cell::RefCell::new(None)};}
unsafe extern "system" fn escape_hook(code: i32, wp: usize, lp: isize) -> isize {
    if code == 0 && lp != 0 {
        let k = &*(lp as *const w::Keyboard);
        if k.key == 0x1b && k.flags & 2 == 0 {
            let down = matches!(wp, 0x100 | 0x104);
            let up = matches!(wp, 0x101 | 0x105);
            if down || up {
                let consume = ESCAPE.with(|slot| {
                    let slot = slot.borrow();
                    let Some(state) = slot.as_ref() else {
                        return false;
                    };
                    if state.initial.load(Ordering::SeqCst) {
                        if up {
                            state.initial.store(false, Ordering::SeqCst);
                        }
                        return false;
                    }
                    if down && state.ownership.down() {
                        state.downs.fetch_add(1, Ordering::Relaxed);
                        state.inbox.push(Event::Escape(true));
                        true
                    } else if up && state.ownership.up() {
                        state.ups.fetch_add(1, Ordering::Relaxed);
                        state.inbox.push(Event::Escape(false));
                        true
                    } else {
                        false
                    }
                });
                if consume {
                    return 1;
                }
            }
        }
    }
    w::CallNextHookEx(null_mut(), code, wp, lp)
}
struct EscapeListener {
    thread: u32,
    done: std::sync::mpsc::Receiver<()>,
    join: Option<std::thread::JoinHandle<()>>,
    stopping: Arc<AtomicBool>,
    state: Arc<EscapeState>,
    deadline: Instant,
}
impl EscapeListener {
    fn start(inbox: Arc<Inbox>) -> Result<Self> {
        let (initial, thread_done) = std::sync::mpsc::channel();
        let (sent, done) = std::sync::mpsc::channel();
        let state = Arc::new(EscapeState {
            inbox,
            initial: AtomicBool::new(down(0x1b)),
            ownership: EscOwnership::default(),
            downs: AtomicU32::new(0),
            ups: AtomicU32::new(0),
        });
        let stopping = Arc::new(AtomicBool::new(false));
        let thread_stopping = stopping.clone();
        let thread_state = state.clone();
        let hook_state = state.clone();
        let join = std::thread::spawn(move || {
            ESCAPE.with(|slot| *slot.borrow_mut() = Some(thread_state));
            unsafe {
                let mut msg = w::Message::default();
                w::PeekMessageW(&mut msg, null_mut(), 0, 0, 0);
                let hook = if thread_stopping.load(Ordering::SeqCst) {
                    null_mut()
                } else {
                    w::SetWindowsHookExW(13, Some(escape_hook), w::GetModuleHandleW(null()), 0)
                };
                let _ = initial.send((w::CurrentThreadId(), !hook.is_null()));
                if !hook.is_null() {
                    while !thread_stopping.load(Ordering::SeqCst)
                        && !hook_state.ownership.may_exit()
                    {
                        pump();
                        wait_messages(16);
                    }
                    w::UnhookWindowsHookEx(hook);
                }
            }
            ESCAPE.with(|slot| *slot.borrow_mut() = None);
            let _ = sent.send(());
        });
        match thread_done.recv_timeout(Duration::from_secs(3)) {
            Ok((thread, true)) => Ok(Self {
                thread,
                done,
                join: Some(join),
                stopping,
                state,
                deadline: Instant::now() + Duration::from_secs(150),
            }),
            _ => {
                stopping.store(true, Ordering::SeqCst);
                if done.recv_timeout(Duration::from_secs(2)).is_ok() {
                    let _ = join.join();
                }
                Err(error("CAPTURE_INPUT"))
            }
        }
    }
    fn stop(&mut self) -> bool {
        if self.join.is_none() {
            return true;
        }
        self.state.ownership.request_close();
        while self.state.ownership.owned() && Instant::now() < self.deadline {
            std::thread::sleep(Duration::from_millis(5));
        }
        let released = !self.state.ownership.owned();
        if !released {
            self.stopping.store(true, Ordering::SeqCst);
        }
        unsafe {
            w::PostThreadMessageW(self.thread, 0x12, 0, 0);
        }
        if self.done.recv_timeout(Duration::from_secs(2)).is_ok() {
            if let Some(join) = self.join.take() {
                let _ = join.join();
            }
            released
        } else {
            false
        }
    }
}
impl Drop for EscapeListener {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}
struct Host {
    thread: u32,
    token: i64,
    mailbox: w::H,
    ready: bool,
    armed: bool,
    stopped: bool,
    failed: bool,
    last_ack: Instant,
    last_send: Instant,
    last_ping: Instant,
    started: Instant,
}
impl Host {
    fn fail(&mut self) -> String {
        self.failed = true;
        error("CAPTURE_INPUT_HOST")
    }
    fn new(request: &Request, mailbox: w::H) -> Self {
        let now = Instant::now();
        Self {
            thread: request.host_thread,
            token: request.host_token,
            mailbox,
            ready: false,
            armed: false,
            stopped: false,
            failed: false,
            last_ack: now,
            last_send: now - Duration::from_secs(1),
            last_ping: now - Duration::from_secs(1),
            started: now,
        }
    }
    fn send(&mut self, kind: u32) -> Result<()> {
        if unsafe {
            w::PostThreadMessageW(
                self.thread,
                kind,
                self.mailbox as usize,
                self.token as isize,
            )
        } == 0
        {
            return Err(self.fail());
        }
        Ok(())
    }
    fn pulse(&mut self, finishing: bool, may_arm: bool) -> Result<()> {
        let now = Instant::now();
        if !self.ready && self.started.elapsed() > Duration::from_secs(3) {
            return Err(self.fail());
        }
        if self.ready && self.last_ack.elapsed() > Duration::from_millis(1250) {
            return Err(self.fail());
        }
        if now.duration_since(self.last_send) < Duration::from_millis(50) {
            return Ok(());
        }
        self.last_send = now;
        if !self.ready {
            return self.send(wire::READY);
        }
        if finishing {
            if !self.stopped {
                self.send(wire::STOP)?;
            }
            return Ok(());
        }
        if may_arm && !self.armed {
            self.send(wire::ARM)?;
        }
        if self.last_ping.elapsed() >= Duration::from_millis(250) {
            self.send(wire::PING)?;
            self.last_ping = now;
        }
        Ok(())
    }
}
fn pump() {
    unsafe {
        let mut msg = w::Message::default();
        for _ in 0..256 {
            if w::PeekMessageW(&mut msg, null_mut(), 0, 0, 1) == 0 {
                break;
            }
            w::TranslateMessage(&msg);
            w::DispatchMessageW(&msg);
        }
    }
}
fn wait_messages(milliseconds: u32) {
    unsafe {
        w::MsgWaitForMultipleObjects(0, null(), 0, milliseconds, 0x04ff);
    }
}
fn hover_target(pointer: Point, own: &HashSet<isize>, owner: u32) -> Option<CaptureWindowTarget> {
    unsafe {
        let desktop = w::GetDesktopWindow();
        let hit = w::WindowFromPoint(w::Point {
            x: pointer.x,
            y: pointer.y,
        });
        let mut root = w::GetAncestor(hit, 2);
        let mut seen = HashSet::new();
        if own.contains(&(root as isize)) {
            for _ in 0..256 {
                if root.is_null()
                    || root == desktop
                    || !seen.insert(root as isize)
                    || w::IsWindow(root) == 0
                    || w::GetAncestor(root, 2) != root
                {
                    return None;
                }
                if !own.contains(&(root as isize))
                    && w::IsWindowVisible(root) != 0
                    && w::IsIconic(root) == 0
                {
                    let mut bounds = w::Rect::default();
                    if w::GetWindowRect(root, &mut bounds) == 0 {
                        return None;
                    }
                    if from_rect(bounds).contains(pointer) {
                        let ex = w::GetWindowLongPtrW(root, -20);
                        if ex & 0x20 == 0 {
                            break;
                        }
                    }
                }
                root = w::GetWindow(root, 2);
            }
        }
        window_target(root, Some(pointer), own, owner)
    }
}
fn window_target(root: w::H, pointer: Option<Point>, own: &HashSet<isize>, owner: u32) -> Option<CaptureWindowTarget> {
    unsafe {
        if root.is_null()
            || root == w::GetDesktopWindow()
            || root == w::GetShellWindow()
            || own.contains(&(root as isize))
            || w::IsWindowVisible(root) == 0
            || w::IsIconic(root) != 0
        {
            return None;
        }
        let mut pid = 0;
        let thread = w::GetWindowThreadProcessId(root, &mut pid);
        if thread == 0 || pid == 0 || pid == std::process::id() || pid == owner {
            return None;
        }
        let mut name = [0u16; 256];
        let length = w::GetClassNameW(root, name.as_mut_ptr(), 256);
        if length <= 0 {
            return None;
        }
        let name = String::from_utf16_lossy(&name[..length as usize]);
        if CaptureHoverPolicy::shell_class(&name) {
            return None;
        }
        let mut cloak = 0u32;
        let mut frame = w::Rect::default();
        if w::DwmGetWindowAttribute(root, 14, (&mut cloak as *mut u32).cast(), 4) != 0
            || cloak != 0
            || w::DwmGetWindowAttribute(
                root,
                9,
                (&mut frame as *mut w::Rect).cast(),
                std::mem::size_of::<w::Rect>() as u32,
            ) != 0
        {
            return None;
        }
        let mut affinity = 0;
        let affinity_known = w::GetWindowDisplayAffinity(root, &mut affinity) != 0;
        // Microsoft documents failure for ordinary non-layered windows. For a
        // layered window unknown affinity is ambiguous, so do not offer it.
        let layered = w::GetWindowLongPtrW(root, -20) & 0x80000 != 0;
        let excluded = (affinity_known && affinity != 0) || (layered && !affinity_known);
        let mut after = 0;
        let bounds = from_rect(frame);
        if excluded
            || w::IsWindow(root) == 0
            || w::GetAncestor(root, 2) != root
            || w::GetWindowThreadProcessId(root, &mut after) != thread
            || after != pid
            || w::IsWindowVisible(root) == 0 || w::IsIconic(root) != 0
            || !bounds.valid()
            || pointer.is_some_and(|point| !bounds.contains(point))
        {
            None
        } else {
            Some(CaptureWindowTarget { window: root as usize, process: pid, thread, frame: bounds })
        }
    }
}
struct Picker {
    inbox: Arc<Inbox>,
    canvas: Arc<Mutex<Option<Surface>>>,
    _mailbox: Window,
    planes: Vec<Window>,
    edges: Vec<Window>,
    loupe: Window,
    // One fixed-size source bitmap per picker, not a new GDI DC/DIB per frame.
    loupe_sample: Surface,
    own: HashSet<isize>,
    owner_process: u32,
    purpose: CapturePurpose,
    topology: CaptureTopologyPolicy,
    selection: CaptureSelectionState,
    input: CaptureInputPolicy,
    host: Host,
    escape: EscapeListener,
    cancel: Cancellation,
    health: BTreeMap<&'static str, u64>,
    started: Instant,
    first: bool,
    shown: bool,
    last_raise: i64,
    last_render_started: Option<Instant>,
    hover: CaptureHoverPolicy,
    redraw: CaptureRedrawPolicy,
    input_health: CaptureInputHealthPolicy,
    failure: Option<String>,
    finished_at: Option<Instant>,
    cleaned: bool,
    class: Class,
}
impl Picker {
    fn new(request: &Request) -> Result<Self> {
        let started = Instant::now();
        if request.host_thread == 0 || request.host_token <= 0 {
            return Err(error("CAPTURE_ARGUMENT"));
        }
        unsafe {
            let old = w::SetThreadDpiAwarenessContext(-4isize as _);
            if old.is_null() {
                w::SetThreadDpiAwarenessContext(-3isize as _);
            }
            if w::GetAwarenessFromDpiAwarenessContext(w::GetThreadDpiAwarenessContext()) != 2 {
                return Err(error("CAPTURE_DPI"));
            }
        }
        input_desktop()?;
        let mut composition = 0;
        if unsafe { w::DwmIsCompositionEnabled(&mut composition) } != 0 || composition == 0 {
            return Err(error("CAPTURE_INPUT_PLANE"));
        }
        let cancel = Cancellation::open(&request.cancellation)?;
        if cancel.requested()? {
            return Err("CANCELLED: Native task was superseded.".into());
        }
        let class = Class::new()?;
        let inbox = Arc::new(Inbox::default());
        let canvas = Arc::new(Mutex::new(None));
        let topology = topology(&class, &inbox, &canvas)?;
        let selection = CaptureSelectionState::with_purpose(
            topology.displays().iter().map(|d| d.bounds).collect(),
            pointer()?, request.purpose,
        )
        .map_err(str::to_owned)?;
        let mailbox = Window::new(
            &class,
            Role::Mailbox,
            Rect::new(0, 0, 1, 1),
            inbox.clone(),
            canvas.clone(),
        )?;
        let mut planes = Vec::new();
        let mut edges = Vec::new();
        let mut own = HashSet::new();
        for (index, display) in topology.displays().iter().enumerate() {
            let plane = Window::new(
                &class,
                Role::Plane(index),
                display.bounds,
                inbox.clone(),
                canvas.clone(),
            )?;
            own.insert(plane.hwnd as isize);
            planes.push(plane);
            for _ in 0..12 {
                let edge = Window::new(
                    &class,
                    Role::Edge(index),
                    Rect::new(display.bounds.x, display.bounds.y, 1, 1),
                    inbox.clone(),
                    canvas.clone(),
                )?;
                own.insert(edge.hwnd as isize);
                edges.push(edge);
            }
        }
        let loupe = Window::new(
            &class,
            Role::Loupe,
            Rect::new(0, 0, 156, 174),
            inbox.clone(),
            canvas.clone(),
        )?;
        own.insert(loupe.hwnd as isize);
        let loupe_sample =
            Surface::preview(CaptureMagnifierSample::SIDE, CaptureMagnifierSample::SIDE)?;
        *canvas.lock().map_err(|_| error("CAPTURE_BITMAP"))? = Some(Surface::preview(156, 174)?);
        let mut input = CaptureInputPolicy::default();
        input.resync_released_buttons(down(1), down(2));
        input.resync_escape(down(0x1b));
        let escape = EscapeListener::start(inbox.clone())?;
        let host = Host::new(request, mailbox.hwnd);
        let mut health = BTreeMap::new();
        for name in [
            "nativeHostDowns",
            "nativeHostUps",
            "inputPlaneDowns",
            "inputPlaneUps",
            "hookEscapeDowns",
            "hookEscapeUps",
            "hookMouseDowns",
            "hookMouseUps",
            "mouseHookInstalled",
            "hookRunningAfterStop",
            "inputPlaneRemainingAfterCleanup",
            "inputPlaneVisibleCount",
            "captureFrameCount",
            "captureDraggingFrameCount",
            "captureFrameStartGapMillisecondsMax",
            "captureFrameRenderMillisecondsTotal",
            "captureFrameRenderMillisecondsMax",
            "magnifierRenderMillisecondsTotal",
            "magnifierRenderMillisecondsMax",
            "magnifierSampleMillisecondsTotal",
            "magnifierSampleMillisecondsMax",
            "magnifierComposeMillisecondsTotal",
            "magnifierComposeMillisecondsMax",
            "magnifierPresentMillisecondsTotal",
            "magnifierPresentMillisecondsMax",
            "magnifierClearMillisecondsTotal",
            "magnifierClearMillisecondsMax",
            "magnifierGetDcMillisecondsTotal",
            "magnifierGetDcMillisecondsMax",
            "magnifierBitBltMillisecondsTotal",
            "magnifierBitBltMillisecondsMax",
            "magnifierReleaseDcMillisecondsTotal",
            "magnifierReleaseDcMillisecondsMax",
        ] {
            health.insert(name, 0);
        }
        health.insert("inputBackend", 3);
        health.insert("desktopMatched", 1);
        health.insert("knownPointer", 1);
        health.insert("inputPlaneCount", planes.len() as u64);
        health.insert("nativeCaptureBackend", 1);
        Ok(Self {
            class,
            inbox,
            canvas,
            _mailbox: mailbox,
            planes,
            edges,
            loupe,
            loupe_sample,
            own,
            owner_process: request.owner_process,
            purpose: request.purpose,
            topology,
            selection,
            input,
            host,
            escape,
            cancel,
            health,
            started,
            first: true,
            shown: false,
            last_raise: -250,
            last_render_started: None,
            hover: CaptureHoverPolicy::default(),
            redraw: CaptureRedrawPolicy::default(),
            input_health: CaptureInputHealthPolicy::default(),
            failure: None,
            finished_at: None,
            cleaned: false,
        })
    }
    fn increment(&mut self, key: &'static str) {
        *self.health.entry(key).or_default() += 1;
    }
    fn record_render_duration(&mut self, total: &'static str, max: &'static str, started: Instant) {
        let elapsed = started.elapsed().as_millis().min(10_000_000) as u64;
        self.record_duration_value(total, max, elapsed);
    }
    fn record_duration_value(&mut self, total: &'static str, max: &'static str, elapsed: u64) {
        let elapsed = elapsed.min(10_000_000);
        let previous = self.health.get(total).copied().unwrap_or(0);
        self.health
            .insert(total, previous.saturating_add(elapsed).min(10_000_000));
        let previous = self.health.get(max).copied().unwrap_or(0);
        self.health.insert(max, previous.max(elapsed));
    }
    fn invalidate(&mut self, reason: i32, old: u32, new: u32) {
        let phase = if self.selection.finished {
            4
        } else if self.selection.dragging {
            3
        } else if self.shown {
            2
        } else {
            1
        };
        self.topology.invalidate(reason, old, new, phase);
        self.failure = Some(error("CAPTURE_DISPLAY_CHANGED"));
        self.selection.cancel();
    }
    fn validate(&mut self) -> Result<()> {
        pump();
        self.events()?;
        if let Some(e) = self.failure.clone() {
            return Err(e);
        }
        input_desktop()?;
        let current = topology(&self.class, &self.inbox, &self.canvas)?;
        self.health
            .insert("displayObservedCount", current.displays().len() as u64);
        self.health
            .insert("displayObservedAwareness", current.awareness.max(0) as u64);
        if !self.topology.matches(&current) {
            self.invalidate(5, 0, 0);
            return Err(error("CAPTURE_DISPLAY_CHANGED"));
        }
        Ok(())
    }
    fn validate_window(&self) -> Result<()> {
        if let Some(expected) = self.selection.selected_window {
            let current = window_target(expected.window as _, None, &self.own, self.owner_process);
            if !capture_window_is_current(expected, current) {
                return Err(error("CAPTURE_WINDOW_CHANGED"));
            }
        }
        Ok(())
    }
    fn mouse(&mut self, kind: u32, p: Point) -> Result<()> {
        if kind == 0x201 && self.purpose == CapturePurpose::Screenshot && !self.selection.dragging {
            let target = hover_target(p, &self.own, self.owner_process);
            let dpi = self.topology.displays().iter().find(|d| d.bounds.contains(p)).map_or(96, |d| d.dpi);
            self.selection.set_window_candidate(target, dpi);
        }
        self.input.mouse(kind, p, &mut self.selection);
        // Once released, a changed/closed/reused/protected target is an error,
        // not permission to capture the stale coordinates or a replacement.
        if kind == 0x202 { self.validate_window()?; }
        Ok(())
    }
    fn events(&mut self) -> Result<()> {
        for event in self.inbox.take() {
            match event {
                Event::Display => self.invalidate(2, 0, 0),
                Event::Dpi { role, hwnd, value } => {
                    if matches!(role, Role::Probe | Role::Mailbox | Role::Loupe) {
                        continue;
                    }
                    let index = match role {
                        Role::Plane(i) | Role::Edge(i) => i,
                        _ => continue,
                    };
                    let expected = self
                        .topology
                        .displays()
                        .get(index)
                        .ok_or_else(|| error("CAPTURE_DISPLAY_CHANGED"))?;
                    let expected_dpi = expected.dpi;
                    let expected_bounds = expected.bounds;
                    if matches!(role, Role::Plane(_)) && self.shown {
                        let mut r = w::Rect::default();
                        if unsafe { w::GetWindowRect(hwnd as _, &mut r) } == 0
                            || from_rect(r) != expected_bounds
                        {
                            self.invalidate(6, expected_dpi, value as u32 & 0xffff);
                            continue;
                        }
                    }
                    if CaptureTopologyPolicy::dpi_message_changes(expected_dpi, value as i64) {
                        match topology(&self.class, &self.inbox, &self.canvas) {
                            Ok(current) if self.topology.matches(&current) => {
                                self.increment("displayWindowDpiNotificationsVerified")
                            }
                            _ => self.invalidate(
                                if matches!(role, Role::Plane(_)) { 4 } else { 3 },
                                expected_dpi,
                                value as u32 & 0xffff,
                            ),
                        }
                    }
                }
                Event::Cancel(message) => {
                    self.health
                        .insert("inputWindowCancellationMessage", message as u64);
                    self.health.insert(
                        "inputWindowCancellationPhase",
                        if self.selection.finished {
                            4
                        } else if self.selection.dragging {
                            3
                        } else if self.shown {
                            2
                        } else {
                            1
                        },
                    );
                    self.selection.cancel();
                }
                Event::Escape(is_down) => {
                    self.increment(if is_down {
                        "hookEscapeDowns"
                    } else {
                        "hookEscapeUps"
                    });
                    self.input.escape(is_down, !is_down);
                    if self.input.escape_cancelled {
                        self.selection.cancel();
                    }
                }
                Event::Mouse(kind, p) => {
                    self.increment(if kind == 0x201 || kind == 0x204 {
                        "inputPlaneDowns"
                    } else {
                        "inputPlaneUps"
                    });
                    self.mouse(kind, p)?;
                }
                Event::Wire(kind, token, value) => {
                    if token != self.host.token as usize {
                        continue;
                    }
                    self.host.last_ack = Instant::now();
                    match kind {
                        wire::READY_ACK => {
                            self.host.ready = true;
                            self.health.insert("nativeHostReady", 1);
                        }
                        wire::ARM_ACK => {
                            self.host.armed = true;
                            self.health.insert("nativeHostArmed", 1);
                        }
                        wire::STOP_ACK => {
                            self.host.stopped = true;
                            self.health.insert("nativeHostStopped", 1);
                            if value != 0 {
                                return Err(self.host.fail());
                            }
                        }
                        wire::FAILURE => return Err(self.host.fail()),
                        wire::PING_ACK => {
                            if value != 0 {
                                return Err(self.host.fail());
                            }
                        }
                        wire::DRAG_EXCURSION => {
                            self.selection.note_drag_excursion(((value as u64) >> 32) as i32, value as u32 as i32);
                        }
                        wire::MOVE => {
                            self.host.send(wire::MOVE_ACK)?;
                            self.increment("nativeHostMoves");
                            let p = Point::new(((value as u64) >> 32) as i32, value as u32 as i32);
                            self.selection.move_to(p);
                        }
                        wire::LEFT_DOWN | wire::LEFT_UP | wire::RIGHT_DOWN | wire::RIGHT_UP => {
                            let p = Point::new(((value as u64) >> 32) as i32, value as u32 as i32);
                            let mouse = match kind {
                                wire::LEFT_DOWN => 0x201,
                                wire::LEFT_UP => 0x202,
                                wire::RIGHT_DOWN => 0x204,
                                _ => 0x205,
                            };
                            self.increment(if mouse == 0x201 || mouse == 0x204 {
                                "nativeHostDowns"
                            } else {
                                "nativeHostUps"
                            });
                            self.mouse(mouse, p)?;
                        }
                        _ => {}
                    }
                }
            }
        }
        if self.inbox.failed.load(Ordering::SeqCst) {
            return Err(error("CAPTURE_INPUT_QUEUE"));
        }
        Ok(())
    }
    fn render(&mut self, p: Point, hovered: Rect, elapsed: i64) -> Result<()> {
        let frame_started = Instant::now();
        if let Some(previous) = self.last_render_started.replace(frame_started) {
            let gap = previous.elapsed().as_millis().min(10_000_000) as u64;
            let maximum = self
                .health
                .get("captureFrameStartGapMillisecondsMax")
                .copied()
                .unwrap_or(0);
            self.health
                .insert("captureFrameStartGapMillisecondsMax", maximum.max(gap));
        }
        let raise = elapsed - self.last_raise >= 250;
        if !self.shown {
            for plane in &self.planes {
                let r = plane.bounds()?;
                set_bounds(plane.hwnd, TOPMOST, r, POS | 0x40)?;
            }
            self.shown = true;
        }
        let mut first: w::H = null_mut();
        let mut selected = self.selection.selected;
        if !selected.is_empty() {
            selected = Rect::from_ltrb(
                selected.x.saturating_sub(1),
                selected.y.saturating_sub(1),
                selected.right().saturating_add(1),
                selected.bottom().saturating_add(1),
            );
        }
        for (index, display) in self.topology.displays().iter().enumerate() {
            let sets = [
                outline_edges(
                    if self.selection.highlighted == index as i32 {
                        display.bounds
                    } else {
                        Rect::default()
                    },
                    display.bounds,
                ),
                outline_edges(selected, display.bounds),
                outline_edges(hovered, display.bounds),
            ];
            for i in 0..4 {
                for (role, edges) in sets.iter().enumerate() {
                    let edge = &self.edges[index * 12 + role * 4 + i];
                    let bounds = edges[i];
                    if bounds.is_empty() {
                        edge.hide();
                        continue;
                    }
                    let visible = edge.visible();
                    if raise || !visible || edge.bounds()? != bounds {
                        set_bounds(
                            edge.hwnd,
                            TOPMOST,
                            bounds,
                            POS | if !visible { 0x40 } else { 0 }
                                | if !raise && visible { 4 } else { 0 },
                        )?;
                        if raise && first.is_null() {
                            first = edge.hwnd;
                        }
                        unsafe {
                            w::InvalidateRect(edge.hwnd, null(), 0);
                            w::UpdateWindow(edge.hwnd);
                        }
                    }
                }
            }
        }
        if raise {
            if first.is_null() {
                return Err(error("CAPTURE_OVERLAY"));
            }
            for plane in &self.planes {
                set_bounds(plane.hwnd, first, plane.bounds()?, POS | 1 | 2)?;
                let ex = unsafe { w::GetWindowLongPtrW(plane.hwnd, -20) } as u32;
                if ex & PLANE_EX != PLANE_EX || ex & (0x80000 | 0x20) != 0 || !plane.visible() {
                    return Err(error("CAPTURE_INPUT_PLANE"));
                }
            }
            self.last_raise = elapsed;
        }
        if self.first {
            self.health.insert(
                "firstBordersVisibleMilliseconds",
                self.started.elapsed().as_millis() as u64,
            );
        }
        let magnifier_started = Instant::now();
        self.render_loupe(p)?;
        self.record_render_duration(
            "magnifierRenderMillisecondsTotal",
            "magnifierRenderMillisecondsMax",
            magnifier_started,
        );
        self.record_render_duration(
            "captureFrameRenderMillisecondsTotal",
            "captureFrameRenderMillisecondsMax",
            frame_started,
        );
        self.increment("captureFrameCount");
        if self.selection.dragging {
            self.increment("captureDraggingFrameCount");
        }
        if self.first {
            self.health.insert(
                "firstPickerFrameCompleteMilliseconds",
                self.started.elapsed().as_millis() as u64,
            );
            self.first = false;
        }
        Ok(())
    }
    fn render_loupe(&mut self, p: Point) -> Result<()> {
        let sample = CaptureMagnifierSample::new(p, self.selection.desktop);
        let area = self
            .topology
            .displays()
            .iter()
            .find(|d| d.bounds.contains(p))
            .map(|d| d.bounds)
            .unwrap_or(self.selection.desktop);
        let place = magnifier_place(p, sample.bounds, area);
        if self.loupe.visible() && self.loupe.bounds()?.intersect(sample.bounds).valid() {
            set_bounds(self.loupe.hwnd, TOPMOST, place, POS)?;
        }
        if sample.grabbed.width < 4 || sample.grabbed.height < 4 {
            self.loupe.hide();
            return Ok(());
        }
        let sample_started = Instant::now();
        let clear_started = Instant::now();
        self.loupe_sample.clear(w::rgb(22, 26, 34));
        self.record_render_duration(
            "magnifierClearMillisecondsTotal",
            "magnifierClearMillisecondsMax",
            clear_started,
        );
        let times =
            self.loupe_sample
                .copy_screen_timed(sample.copy_offset, sample.grabbed, false)?;
        // No extra flush or native call is added to force a phase boundary.
        // These are wall times in the unchanged synchronous GDI call sequence.
        for ((total, max), elapsed) in [
            (
                "magnifierGetDcMillisecondsTotal",
                "magnifierGetDcMillisecondsMax",
            ),
            (
                "magnifierBitBltMillisecondsTotal",
                "magnifierBitBltMillisecondsMax",
            ),
            (
                "magnifierReleaseDcMillisecondsTotal",
                "magnifierReleaseDcMillisecondsMax",
            ),
        ]
        .into_iter()
        .zip(times)
        {
            self.record_duration_value(total, max, elapsed);
        }
        self.record_render_duration(
            "magnifierSampleMillisecondsTotal",
            "magnifierSampleMillisecondsMax",
            sample_started,
        );
        let compose_started = Instant::now();
        {
            let raw = &self.loupe_sample;
            let canvas = self.canvas.lock().map_err(|_| error("CAPTURE_BITMAP"))?;
            let canvas = canvas.as_ref().ok_or_else(|| error("CAPTURE_BITMAP"))?;
            canvas.clear(w::rgb(22, 26, 34));
            unsafe {
                w::SetStretchBltMode(canvas.dc, 3);
                if w::StretchBlt(canvas.dc, 0, 0, 156, 156, raw.dc, 0, 0, 52, 52, SRCCOPY) == 0 {
                    return Err(error("CAPTURE_MAGNIFIER"));
                }
                let pen = w::CreatePen(0, 1, w::rgb(230, 70, 70));
                let old = w::SelectObject(canvas.dc, pen);
                w::MoveToEx(canvas.dc, 78, 0, null_mut());
                w::LineTo(canvas.dc, 78, 156);
                w::MoveToEx(canvas.dc, 0, 78, null_mut());
                w::LineTo(canvas.dc, 156, 78);
                w::SelectObject(canvas.dc, old);
                w::DeleteObject(pen);
                let frame = w::CreatePen(0, 2, w::rgb(90, 150, 255));
                let old = w::SelectObject(canvas.dc, frame);
                w::MoveToEx(canvas.dc, 1, 1, null_mut());
                w::LineTo(canvas.dc, 154, 1);
                w::LineTo(canvas.dc, 154, 154);
                w::LineTo(canvas.dc, 1, 154);
                w::LineTo(canvas.dc, 1, 1);
                w::SelectObject(canvas.dc, old);
                w::DeleteObject(frame);
                let label =
                    if self.selection.selected.width > 1 && self.selection.selected.height > 1 {
                        format!(
                            "{} × {}",
                            self.selection.selected.width, self.selection.selected.height
                        )
                    } else {
                        "3×".into()
                    };
                let label = w::wide(&label);
                let oldfont = w::SelectObject(canvas.dc, w::GetStockObject(17));
                w::SetTextColor(canvas.dc, w::rgb(255, 255, 255));
                w::SetBkMode(canvas.dc, 1);
                let mut caption = w::Rect {
                    left: 4,
                    top: 157,
                    right: 156,
                    bottom: 174,
                };
                w::DrawTextW(
                    canvas.dc,
                    label.as_ptr(),
                    label.len() as i32 - 1,
                    &mut caption,
                    0x20,
                );
                w::SelectObject(canvas.dc, oldfont);
            }
        }
        self.record_render_duration(
            "magnifierComposeMillisecondsTotal",
            "magnifierComposeMillisecondsMax",
            compose_started,
        );
        let present_started = Instant::now();
        set_bounds(self.loupe.hwnd, TOPMOST, place, POS | 0x40)?;
        unsafe {
            // Disabled once at construction; repeating EnableWindow(false)
            // sends redundant WM_CANCELMODE notifications on every frame.
            w::InvalidateRect(self.loupe.hwnd, null(), 0);
            w::UpdateWindow(self.loupe.hwnd);
        }
        self.record_render_duration(
            "magnifierPresentMillisecondsTotal",
            "magnifierPresentMillisecondsMax",
            present_started,
        );
        Ok(())
    }
    fn select(&mut self) -> Result<Rect> {
        self.validate()?;
        loop {
            pump();
            if let Err(e) = self.events() {
                self.failure = Some(e);
                self.selection.cancel();
            }
            let elapsed = self.started.elapsed().as_millis() as i64;
            if self.cancel.requested()? {
                self.selection.cancel();
            }
            if self.input.escape_cancelled {
                self.selection.cancel();
            }
            if !self.input.armed {
                self.input.resync_released_buttons(down(1), down(2));
            }
            self.selection.expire(elapsed);
            let p = pointer()?;
            if !self.selection.finished {
                self.selection.move_to(p);
            }
            if self.input_health.observe(
                self.input.armed,
                self.selection.finished,
                self.selection.dragging,
                self.input.left_swallowed,
                down(1),
                elapsed,
            ) != 0
            {
                self.failure = Some(error("CAPTURE_INPUT_STATE"));
                self.selection.cancel();
            }
            if let Err(e) = self.host.pulse(
                self.selection.finished,
                self.input.armed && !self.selection.finished,
            ) {
                self.failure = Some(e);
                self.selection.cancel();
            }
            self.health.insert(
                "uiPhase",
                if self.selection.finished {
                    3
                } else if self.selection.dragging {
                    2
                } else if self.input.armed && self.host.armed {
                    1
                } else {
                    0
                },
            );
            self.health
                .insert("inputArmed", u64::from(self.input.armed && self.host.armed));
            self.health
                .insert("leftSwallowed", u64::from(self.input.left_swallowed));
            self.health.insert("physicalLeftDown", u64::from(down(1)));
            self.health
                .insert("dragging", u64::from(self.selection.dragging));
            let frame_action = self.redraw.frame_action(
                self.input.armed && self.host.armed,
                self.selection.finished,
                elapsed,
            );
            if self.selection.finished {
                if self.finished_at.is_none() {
                    self.finished_at = Some(Instant::now());
                    self.loupe.hide();
                    for edge in &self.edges {
                        edge.hide();
                    }
                }
                if self.input.may_stop(true, elapsed) {
                    if self.input.release_grace_exceeded
                        && (self.input.left_swallowed || self.input.right_swallowed)
                        && self.failure.is_none()
                    {
                        self.failure = Some(error("CAPTURE_INPUT_RELEASE"));
                    }
                    break;
                }
            } else if frame_action == CaptureFrameAction::Render {
                self.redraw.presented(elapsed);
                if elapsed - self.last_raise >= 250 {
                    input_desktop()?;
                }
                let hovered = if !self.selection.dragging && self.selection.highlighted >= 0 {
                    if self.hover.begin_query(elapsed) {
                        self.hover.set_frame(hover_target(p, &self.own, self.owner_process).map_or(Rect::default(), |target| target.frame));
                    }
                    self.hover.current(p, elapsed, true)
                } else {
                    self.hover.clear();
                    Rect::default()
                };
                if let Err(e) = self.render(p, hovered, elapsed) {
                    self.failure = Some(e);
                    self.selection.cancel();
                }
            } else if frame_action == CaptureFrameAction::Hide {
                self.loupe.hide();
            }
            // Retain is deliberately a no-op: throttling must never flash the
            // loupe off between updates while pointer/mailbox messages arrive.
            // Re-read the clock after GDI work rather than adding a second
            // complete frame interval after every expensive paint.
            let wait = self.redraw.wait_milliseconds(
                self.input.armed && self.host.armed,
                self.selection.finished,
                self.started.elapsed().as_millis() as i64,
            );
            wait_messages(wait);
        }
        let result = if let Some(e) = self.failure.clone() {
            Err(e)
        } else if self.selection.cancelled {
            Err("CANCELLED: Screenshot selection was cancelled.".into())
        } else {
            Ok(self.selection.selected)
        };
        self.cleanup();
        if let Some(e) = self.failure.clone() {
            Err(e)
        } else {
            result
        }
    }
    fn cleanup(&mut self) {
        if self.cleaned {
            return;
        }
        self.cleaned = true;
        self.loupe.hide();
        for plane in &self.planes {
            plane.hide();
        }
        for edge in &self.edges {
            edge.hide();
        }
        let stop = Instant::now();
        while !self.host.stopped && stop.elapsed() < Duration::from_millis(600) {
            if let Err(e) = self.host.pulse(true, false) {
                self.failure = Some(e);
                break;
            }
            pump();
            if let Err(e) = self.events() {
                self.failure = Some(e);
                break;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        if !self.host.stopped {
            self.failure = Some(self.host.fail());
        }
        self.health
            .insert("nativeHostFailed", u64::from(self.host.failed));
        if !self.escape.stop() {
            self.failure = Some(error("CAPTURE_INPUT"));
        }
        self.health.insert(
            "hookEscapeDowns",
            self.escape.state.downs.load(Ordering::Relaxed) as u64,
        );
        self.health.insert(
            "hookEscapeUps",
            self.escape.state.ups.load(Ordering::Relaxed) as u64,
        );
        self.health.insert(
            "hookRunningAfterStop",
            u64::from(self.escape.join.is_some()),
        );
        self.health.insert(
            "hookEscapeReleaseUnconfirmed",
            u64::from(self.escape.state.ownership.owned()),
        );
        let mut remaining = 0;
        let mut visible = 0;
        for plane in &mut self.planes {
            if !plane.destroy() {
                remaining += 1;
                if plane.visible() {
                    visible += 1;
                }
            }
        }
        for edge in &mut self.edges {
            if !edge.destroy() {
                self.failure = Some(error("CAPTURE_OVERLAY_CLEANUP"));
            }
        }
        if !self.loupe.destroy() {
            self.failure = Some(error("CAPTURE_OVERLAY_CLEANUP"));
        }
        if remaining != 0 {
            self.failure = Some(error("CAPTURE_INPUT_PLANE"));
        }
        self.health.insert(
            "inputPlaneFallbackUsed",
            u64::from(
                self.health.get("inputPlaneDowns").copied().unwrap_or(0)
                    + self.health.get("inputPlaneUps").copied().unwrap_or(0)
                    > 0,
            ),
        );
        self.health.insert(
            "decorativeCancellationNotificationsIgnored",
            self.inbox.decorative_cancellations.load(Ordering::Relaxed) as u64,
        );
        self.health.insert("inputPlaneVisibleCount", visible);
        self.health
            .insert("inputPlaneRemainingAfterCleanup", remaining);
        if let Some(released) = self.finished_at {
            self.health.insert(
                "releaseToCleanupMilliseconds",
                released.elapsed().as_millis() as u64,
            );
        }
        self.health
            .insert("displayExpectedDpi", self.topology.before_dpi as u64);
        self.health
            .insert("displayObservedDpi", self.topology.after_dpi as u64);
        self.health
            .insert("displayAwareness", self.topology.awareness.max(0) as u64);
        self.health
            .insert("displayCount", self.topology.displays().len() as u64);
        self.health
            .insert("displayInvalidationReason", self.topology.reason as u64);
        self.health.insert(
            "displayInvalidationPhase",
            self.topology.invalidation_phase as u64,
        );
    }
}
impl Drop for Picker {
    fn drop(&mut self) {
        self.cleanup();
    }
}
pub fn run(request: Request) -> CapturedResult {
    let mut picker = match Picker::new(&request) {
        Ok(p) => p,
        Err(e) => {
            return CapturedResult {
                result: Err(e),
                health: BTreeMap::new(),
            }
        }
    };
    let result = (|| {
        let selected = picker.select()?;
        if picker.cancel.requested()? {
            return Err("CANCELLED: Native task was superseded.".into());
        }
        unsafe {
            if w::DwmFlush() < 0 {
                return Err(error("CAPTURE_DWM"));
            }
        }
        picker.validate()?;
        picker.validate_window()?;
        let mut image = Surface::new(selected.width, selected.height)?;
        if request.purpose == CapturePurpose::Screenshot {
            // Copy only real display intersections. Offscreen window portions
            // and holes between monitors never become readable hidden content.
            image.clear(w::rgb(255, 255, 255));
            for display in picker.topology.displays() {
                let visible = selected.intersect(display.bounds);
                if visible.valid() {
                    image.copy_screen(Point::new(visible.x - selected.x, visible.y - selected.y), visible, true)?;
                }
            }
        } else {
            image.copy_screen(Point::new(0, 0), selected, true)?;
        }
        picker.validate()?;
        picker.validate_window()?;
        if picker.cancel.requested()? {
            return Err("CANCELLED: Native task was superseded.".into());
        }
        let png = image.png()?;
        if let Some(released) = picker.finished_at {
            picker.health.insert(
                "releaseToPngMilliseconds",
                released.elapsed().as_millis() as u64,
            );
        }
        Ok(png)
    })();
    picker.cleanup();
    if let Some(released) = picker.finished_at {
        picker.health.insert(
            "releaseToReplyMilliseconds",
            released.elapsed().as_millis() as u64,
        );
    }
    CapturedResult {
        result,
        health: picker.health.clone(),
    }
}
pub struct CapturedResult {
    pub result: Result<Vec<u8>>,
    pub health: BTreeMap<&'static str, u64>,
}

/// Explicit memory-only smoke path: never opens a screen DC or starts input interception.
pub fn self_test() -> Result<()> {
    if std::mem::size_of::<usize>() != 8
        || std::mem::size_of::<w::WndClass>() != 80
        || std::mem::size_of::<w::Message>() != 48
        || std::mem::size_of::<w::Paint>() != 72
    {
        return Err(error("CAPTURE_ABI"));
    }
    let mut surface = Surface::new(3, 2)?;
    surface.clear(w::rgb(19, 73, 151));
    let bytes = surface.png()?;
    let decoder = png::Decoder::new(std::io::Cursor::new(bytes));
    let mut reader = decoder
        .read_info()
        .map_err(|_| error("CAPTURE_SELF_TEST"))?;
    let mut rgba = vec![
        0;
        reader
            .output_buffer_size()
            .ok_or_else(|| error("CAPTURE_SELF_TEST"))?
    ];
    let info = reader
        .next_frame(&mut rgba)
        .map_err(|_| error("CAPTURE_SELF_TEST"))?;
    if info.width != 3
        || info.height != 2
        || rgba[..info.buffer_size()]
            .chunks_exact(4)
            .any(|p| p != [19, 73, 151, 255])
    {
        return Err(error("CAPTURE_SELF_TEST"));
    }
    Ok(())
}
