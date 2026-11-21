#!/usr/bin/env python3
"""Bounded Rust/Swift ABI comparison, instrumenting only temporary sources.

Uses the two existing self-test modes, generated OCR pixels and no general
clipboard, captured desktop, permissions or user text. Not device acceptance.
"""
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def prepare(destination):
    source = (ROOT / "src-tauri/native/macos_capture.swift").read_text()
    start = source.index("func captureOCRCancellationSelfTest() throws {")
    end = source.index("private final class CaptureCancellationFixtureResult", start)
    fixture = source[start:end]
    fixture = fixture.replace("func expect(_ value: Bool)", "func expect(_ value: Bool, _ id: String)")
    fixture = fixture.replace("OCR cancellation/metadata fixture failed.", "OCR cancellation/metadata fixture failed: \\(id)")
    lines = fixture.splitlines(keepends=True)
    count = 0
    for index, line in enumerate(lines):
        if "try expect(" in line:
            count += 1
            position = line.rindex(")")
            lines[index] = line[:position] + f', "C{count:02d}"' + line[position:]
    assert count == 10, "Assertion inventory changed; review instrumentation"
    fixture = "".join(lines)
    anchor = "    let first = NativeCaptureTrace(mode: .localOCR)"
    assert fixture.count(anchor) == 1
    fixture = fixture.replace(anchor, """    let fixtureRole = Thread.current.threadDictionary["traceFixtureRole"] as? Int ?? 0
    if fixtureRole == 2 {
        guard traceFixtureReady.wait(timeout: .now() + 10) == .success else {
            throw NativeError("SELF_TEST: BARRIER_READY_TIMEOUT")
        }
    }
    defer { if fixtureRole == 2 { traceFixtureFinished.signal() } }
""" + anchor)
    anchor = "    let latest = NativeCaptureTrace(mode: .cloudImage)"
    assert fixture.count(anchor) == 1
    fixture = fixture.replace(anchor, anchor + """
    if fixtureRole == 1 {
        traceFixtureReady.signal()
        guard traceFixtureFinished.wait(timeout: .now() + 10) == .success else {
            throw NativeError("SELF_TEST: BARRIER_FINISHED_TIMEOUT")
        }
    }
""")
    hooks = """
private let traceFixtureReady = DispatchSemaphore(value: 0)
private let traceFixtureFinished = DispatchSemaphore(value: 0)
@_cdecl("trace_fixture_role")
public func traceFixtureRole(_ role: Int32) {
    Thread.current.threadDictionary["traceFixtureRole"] = Int(role)
}
"""
    (destination / "macos_capture.swift").write_text(source[:start] + fixture + source[end:] + hooks)


RUST = r'''
use std::ffi::{c_char, CString};
unsafe extern "C" {
    fn echolingo_native_run(mode: *const c_char, input: *const u8, len: usize, out: *mut usize) -> *mut u8;
    fn echolingo_native_free(buffer: *mut u8);
    fn trace_fixture_role(role: i32);
}
fn call(mode: &str, role: i32) -> String {
    let mode = CString::new(format!("--{mode}")).unwrap();
    let input = "回声译\0EchoLingo 🪞".as_bytes();
    unsafe {
        trace_fixture_role(role);
        let mut len = 0;
        let ptr = echolingo_native_run(mode.as_ptr(), input.as_ptr(), input.len(), &mut len);
        assert!(!ptr.is_null());
        let text = String::from_utf8(std::slice::from_raw_parts(ptr, len).to_vec()).unwrap();
        echolingo_native_free(ptr);
        text
    }
}
fn success(text: &str) -> bool { text.contains("\"ok\":true") }
fn main() {
    // Workers match the Rust test call context; no main-thread pasteboard test.
    for mode in ["capture-selection-self-test", "self-test"] {
        assert!(success(&std::thread::spawn(move || call(mode, 0)).join().unwrap()), "SERIAL_FAILED");
    }
    println!("SERIAL_BOTH_PASSED");
    let a = std::thread::spawn(|| call("capture-selection-self-test", 1));
    let b = std::thread::spawn(|| call("self-test", 2));
    let a = a.join().unwrap();
    let b = b.join().unwrap();
    assert!(success(&b), "SECOND_ENTRY_FAILED");
    if std::env::args().any(|arg| arg == "--expect-isolated") {
        assert!(success(&a), "ISOLATED_INTERLEAVING_FAILED");
        println!("ISOLATED_INTERLEAVING_BOTH_PASSED");
    } else {
        assert!(a.contains("OCR cancellation/metadata fixture failed: C05"), "EXPECTED_C05_NOT_OBSERVED");
        println!("SHARED_TRACE_OVERWRITE_CONFIRMED_C05");
    }
}
'''


def main():
    assert platform.system() == "Darwin", "Apple toolchain required"
    with tempfile.TemporaryDirectory(prefix="echolingo-trace-") as temporary:
        directory = Path(temporary)
        prepare(directory)
        (directory / "fixture.rs").write_text(RUST)
        sources = [ROOT / "src-tauri/native" / name for name in ("macos.swift", "macos_ocr.swift", "macos_window.swift")]
        subprocess.run(["swiftc", *map(str, sources), str(directory / "macos_capture.swift"),
                        "-O", "-D", "ECHOLINGO_LIBRARY", "-parse-as-library", "-emit-library",
                        "-module-name", "TraceFixture", "-target", platform.machine() + "-apple-macosx12.0",
                        "-framework", "AppKit", "-framework", "Vision", "-framework", "NaturalLanguage",
                        "-framework", "ApplicationServices", "-framework", "CoreText",
                        "-o", str(directory / "libtrace_fixture.dylib")], check=True, timeout=180)
        subprocess.run(["rustc", "--edition=2021", str(directory / "fixture.rs"), "-L", str(directory),
                        "-l", "dylib=trace_fixture", "-C", "link-arg=-Wl,-rpath," + str(directory),
                        "-o", str(directory / "fixture")], check=True, timeout=60)
        arguments = [str(directory / "fixture")]
        if os.environ.get("EXPECT_ISOLATED") == "1":
            arguments.append("--expect-isolated")
        subprocess.run(arguments, check=True, timeout=60)


if __name__ == "__main__":
    main()
