//! Small documented Win32 surface for the isolated native capture process.
#![allow(non_snake_case, dead_code)]
use std::ffi::c_void;
pub type H = *mut c_void;
pub type Proc = unsafe extern "system" fn(H, u32, usize, isize) -> isize;
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Point {
    pub x: i32,
    pub y: i32,
}
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Rect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}
#[repr(C)]
pub struct WndClass {
    pub size: u32,
    pub style: u32,
    pub proc: Option<Proc>,
    pub class_extra: i32,
    pub window_extra: i32,
    pub instance: H,
    pub icon: H,
    pub cursor: H,
    pub background: H,
    pub menu: *const u16,
    pub name: *const u16,
    pub small_icon: H,
}
#[repr(C)]
pub struct CreateStruct {
    pub param: *mut c_void,
    pub instance: H,
    pub menu: H,
    pub parent: H,
    pub cy: i32,
    pub cx: i32,
    pub y: i32,
    pub x: i32,
    pub style: i32,
    pub name: *const u16,
    pub class: *const u16,
    pub ex_style: u32,
}
#[repr(C)]
#[derive(Default)]
pub struct Message {
    pub hwnd: H,
    pub message: u32,
    pub wparam: usize,
    pub lparam: isize,
    pub time: u32,
    pub point: Point,
    pub private: u32,
}
#[repr(C)]
pub struct Paint {
    pub dc: H,
    pub erase: i32,
    pub rect: Rect,
    pub restore: i32,
    pub update: i32,
    pub reserved: [u8; 32],
}
#[repr(C)]
pub struct Monitor {
    pub size: u32,
    pub rect: Rect,
    pub work: Rect,
    pub flags: u32,
    pub device: [u16; 32],
}
#[repr(C)]
pub struct BitmapHeader {
    pub size: u32,
    pub width: i32,
    pub height: i32,
    pub planes: u16,
    pub bit_count: u16,
    pub compression: u32,
    pub size_image: u32,
    pub x_pels: i32,
    pub y_pels: i32,
    pub colors_used: u32,
    pub colors_important: u32,
}
#[repr(C)]
pub struct BitmapInfo {
    pub header: BitmapHeader,
    pub colors: [u32; 1],
}
#[repr(C)]
pub struct Keyboard {
    pub key: u32,
    pub scan: u32,
    pub flags: u32,
    pub time: u32,
    pub extra: usize,
}
#[link(name = "user32")]
unsafe extern "system" {
    pub fn RegisterClassExW(class: *const WndClass) -> u16;
    pub fn UnregisterClassW(name: *const u16, instance: H) -> i32;
    pub fn CreateWindowExW(
        ex: u32,
        class: *const u16,
        title: *const u16,
        style: u32,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        parent: H,
        menu: H,
        instance: H,
        param: *mut c_void,
    ) -> H;
    pub fn DefWindowProcW(hwnd: H, message: u32, w: usize, l: isize) -> isize;
    pub fn DestroyWindow(hwnd: H) -> i32;
    pub fn IsWindow(hwnd: H) -> i32;
    pub fn IsWindowVisible(hwnd: H) -> i32;
    pub fn IsIconic(hwnd: H) -> i32;
    pub fn EnableWindow(hwnd: H, enable: i32) -> i32;
    pub fn SetWindowLongPtrW(hwnd: H, index: i32, value: isize) -> isize;
    pub fn GetWindowLongPtrW(hwnd: H, index: i32) -> isize;
    pub fn ShowWindow(hwnd: H, cmd: i32) -> i32;
    pub fn SetWindowPos(hwnd: H, after: H, x: i32, y: i32, w: i32, h: i32, flags: u32) -> i32;
    pub fn SetLayeredWindowAttributes(hwnd: H, key: u32, alpha: u8, flags: u32) -> i32;
    pub fn GetWindowRect(hwnd: H, rect: *mut Rect) -> i32;
    pub fn GetClientRect(hwnd: H, rect: *mut Rect) -> i32;
    pub fn BeginPaint(hwnd: H, paint: *mut Paint) -> H;
    pub fn EndPaint(hwnd: H, paint: *const Paint) -> i32;
    pub fn FillRect(dc: H, rect: *const Rect, brush: H) -> i32;
    pub fn InvalidateRect(hwnd: H, rect: *const Rect, erase: i32) -> i32;
    pub fn UpdateWindow(hwnd: H) -> i32;
    pub fn GetDC(hwnd: H) -> H;
    pub fn ReleaseDC(hwnd: H, dc: H) -> i32;
    pub fn LoadCursorW(instance: H, name: *const u16) -> H;
    pub fn ClientToScreen(hwnd: H, point: *mut Point) -> i32;
    pub fn GetPhysicalCursorPos(point: *mut Point) -> i32;
    pub fn GetAsyncKeyState(key: i32) -> i16;
    pub fn GetWindowThreadProcessId(hwnd: H, pid: *mut u32) -> u32;
    pub fn PeekMessageW(msg: *mut Message, hwnd: H, min: u32, max: u32, remove: u32) -> i32;
    pub fn GetMessageW(msg: *mut Message, hwnd: H, min: u32, max: u32) -> i32;
    pub fn TranslateMessage(msg: *const Message) -> i32;
    pub fn DispatchMessageW(msg: *const Message) -> isize;
    pub fn MsgWaitForMultipleObjects(
        count: u32,
        handles: *const H,
        all: i32,
        ms: u32,
        wake: u32,
    ) -> u32;
    pub fn PostMessageW(hwnd: H, msg: u32, w: usize, l: isize) -> i32;
    pub fn PostThreadMessageW(thread: u32, msg: u32, w: usize, l: isize) -> i32;
    pub fn SetWindowsHookExW(
        kind: i32,
        callback: Option<unsafe extern "system" fn(i32, usize, isize) -> isize>,
        module: H,
        thread: u32,
    ) -> H;
    pub fn UnhookWindowsHookEx(hook: H) -> i32;
    pub fn CallNextHookEx(hook: H, code: i32, w: usize, l: isize) -> isize;
    pub fn EnumDisplayMonitors(
        dc: H,
        clip: *const Rect,
        callback: Option<unsafe extern "system" fn(H, H, *mut Rect, isize) -> i32>,
        data: isize,
    ) -> i32;
    pub fn GetMonitorInfoW(monitor: H, info: *mut Monitor) -> i32;
    pub fn SetThreadDpiAwarenessContext(context: H) -> H;
    pub fn GetThreadDpiAwarenessContext() -> H;
    pub fn GetAwarenessFromDpiAwarenessContext(context: H) -> i32;
    pub fn GetDpiForWindow(hwnd: H) -> u32;
    pub fn OpenInputDesktop(flags: u32, inherit: i32, access: u32) -> H;
    pub fn GetThreadDesktop(thread: u32) -> H;
    pub fn CloseDesktop(desktop: H) -> i32;
    pub fn GetUserObjectInformationW(
        object: H,
        index: i32,
        info: *mut c_void,
        length: u32,
        needed: *mut u32,
    ) -> i32;
    pub fn WindowFromPoint(point: Point) -> H;
    pub fn GetAncestor(hwnd: H, flags: u32) -> H;
    pub fn GetWindow(hwnd: H, cmd: u32) -> H;
    pub fn GetDesktopWindow() -> H;
    pub fn GetShellWindow() -> H;
    pub fn GetClassNameW(hwnd: H, text: *mut u16, max: i32) -> i32;
    pub fn GetWindowDisplayAffinity(hwnd: H, affinity: *mut u32) -> i32;
    pub fn DrawTextW(dc: H, text: *const u16, len: i32, rect: *mut Rect, format: u32) -> i32;
}
#[link(name = "gdi32")]
unsafe extern "system" {
    pub fn CreateCompatibleDC(dc: H) -> H;
    pub fn DeleteDC(dc: H) -> i32;
    pub fn CreateCompatibleBitmap(dc: H, width: i32, height: i32) -> H;
    pub fn CreateDIBSection(
        dc: H,
        info: *const BitmapInfo,
        usage: u32,
        bits: *mut *mut c_void,
        section: H,
        offset: u32,
    ) -> H;
    pub fn SelectObject(dc: H, obj: H) -> H;
    pub fn DeleteObject(obj: H) -> i32;
    pub fn CreateSolidBrush(color: u32) -> H;
    pub fn GdiFlush() -> i32;
    pub fn BitBlt(
        dest: H,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        source: H,
        sx: i32,
        sy: i32,
        rop: u32,
    ) -> i32;
    pub fn StretchBlt(
        dest: H,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        source: H,
        sx: i32,
        sy: i32,
        sw: i32,
        sh: i32,
        rop: u32,
    ) -> i32;
    pub fn SetStretchBltMode(dc: H, mode: i32) -> i32;
    pub fn CreatePen(style: i32, width: i32, color: u32) -> H;
    pub fn MoveToEx(dc: H, x: i32, y: i32, old: *mut Point) -> i32;
    pub fn LineTo(dc: H, x: i32, y: i32) -> i32;
    pub fn Rectangle(dc: H, left: i32, top: i32, right: i32, bottom: i32) -> i32;
    pub fn SetTextColor(dc: H, color: u32) -> u32;
    pub fn SetBkMode(dc: H, mode: i32) -> i32;
    pub fn GetStockObject(index: i32) -> H;
}
#[link(name = "kernel32")]
unsafe extern "system" {
    pub fn GetModuleHandleW(name: *const u16) -> H;
    #[link_name = "GetCurrentThreadId"]
    pub fn CurrentThreadId() -> u32;
    pub fn OpenEventW(access: u32, inherit: i32, name: *const u16) -> H;
    pub fn WaitForSingleObject(handle: H, ms: u32) -> u32;
    pub fn CloseHandle(handle: H) -> i32;
}
#[link(name = "dwmapi")]
unsafe extern "system" {
    pub fn DwmIsCompositionEnabled(enabled: *mut i32) -> i32;
    pub fn DwmGetWindowAttribute(hwnd: H, attribute: u32, value: *mut c_void, size: u32) -> i32;
    pub fn DwmFlush() -> i32;
}
pub fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(Some(0)).collect()
}
pub fn rgb(r: u8, g: u8, b: u8) -> u32 {
    u32::from(r) | (u32::from(g) << 8) | (u32::from(b) << 16)
}
