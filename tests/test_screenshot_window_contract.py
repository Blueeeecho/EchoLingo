"""Static integration/privacy guardrails; native runtime fixtures remain mandatory."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / path).read_text()

class ScreenshotWindowContract(unittest.TestCase):
    def test_f1_is_explicit_and_does_not_change_ocr_mode(self):
        platform = read('src-tauri/src/platform.rs')
        self.assertIn('image_response(run_cancelable("capture-image", cancel)?)', platform)
        self.assertIn('image_response(run_cancelable("capture-screenshot", cancel)?)', platform)
        native = read('src-tauri/native-capture/src/main.rs')
        self.assertIn('Some("capture-image") => policy::CapturePurpose::Region', native)
        self.assertIn('Some("capture-screenshot") if owner.is_some_and', native)
        swift = read('src-tauri/native/macos.swift')
        self.assertIn('case "--capture-image": return ["ok": true, "imageBase64": try captureImage()]', swift)
        self.assertIn('captureImage(purpose: .screenshot, cancellation: operation)', swift)

    def test_windows_revalidates_before_and_after_visible_pixel_copy(self):
        native = read('src-tauri/src/windows_capture_native.rs')
        capture = native.split('pub fn run(request: Request)', 1)[1].split('pub struct CapturedResult', 1)[0]
        self.assertEqual(capture.count('picker.validate_window()?;'), 2)
        self.assertIn('selected.intersect(display.bounds)', capture)
        self.assertIn('image.copy_screen(', capture)
        self.assertNotIn('PrintWindow', native)
        self.assertNotIn('SetForegroundWindow', native)
        self.assertIn('after != pid', native)
        self.assertIn('!= thread', native)
        self.assertIn('CAPTURE_WINDOW_CHANGED', native)

    def test_drag_maximum_is_independent_of_coalesced_moves(self):
        host = read('src-tauri/src/windows_capture_input.rs')
        start = host.index('if d.message == LEFT_DOWN')
        end = host.index('s.move_pending.swap', start)
        fragment = host[start:end]
        self.assertIn('drag_max_x.fetch_max', fragment)
        self.assertRegex(fragment, r'post\(\s*target,\s*DRAG_EXCURSION')
        self.assertNotIn('GetWindow', fragment)
        self.assertNotIn('SetForeground', fragment)
        policy = read('src-tauri/src/windows_capture_policy.rs')
        self.assertIn('self.drag_exceeded |=', policy)
        self.assertIn('self.pressed_window', policy)

    def test_macos_uses_public_metadata_without_titles_or_isolated_window_images(self):
        swift = read('src-tauri/native/macos_capture.swift')
        candidate = swift.split('func captureWindowTarget(', 1)[1].split('func captureRectangle(', 1)[0]
        self.assertIn('kCGWindowSharingState', candidate)
        self.assertIn('kCGWindowOwnerPID', candidate)
        self.assertIn('kCGWindowNumber', candidate)
        self.assertNotIn('kCGWindowName', candidate)
        self.assertIn('.optionOnScreenOnly, .excludeDesktopElements', candidate)
        self.assertIn('SCContentFilter(display: display, excludingWindows: ownWindows)', swift)
        self.assertNotIn('desktopIndependentWindow:', swift)
        self.assertIn('captureWindowIsCurrent(expected', candidate)
        self.assertIn('screenshotWindowPolicyFixturePassed', read('src-tauri/native/macos.swift'))

    def test_macos_hover_uses_actual_hit_identity_not_foreign_bounding_boxes(self):
        swift = read('src-tauri/native/macos_capture.swift')
        hover = swift.split('func captureHoverWindow(', 1)[1].split('func captureCurrentWindows()', 1)[0]
        self.assertIn('NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: below)', hover)
        self.assertIn('seen.insert(hit).inserted', hover)
        self.assertIn('matches.count == 1', hover)
        self.assertIn('min(records.count + 1, 64)', hover)
        self.assertIn('record[kCGWindowOwnerPID as String]) == Double(excludingPID)', hover)
        self.assertIn('captureWindowTarget(record', hover)
        self.assertIn('target.frame.contains(point)', hover)
        self.assertNotIn('com.apple.dock', hover)
        self.assertNotIn('SetForeground', hover)
        self.assertIn('queriedBelow == [0, 53, 54]', swift)
        self.assertIn('loopQueries == 2', swift)

    def test_cancel_is_registered_before_watching_and_scoped_to_operation(self):
        platform = read('src-tauri/src/platform.rs')
        fn = platform.split('fn run_macos_screenshot_cancelable', 1)[1].split('#[derive(Clone, Copy)]', 1)[0]
        self.assertLess(fn.index('begin-native-capture'), fn.index('let watcher'))
        self.assertIn('cancel-native-capture', fn)
        self.assertIn('end-native-capture', fn)
        swift = read('src-tauri/native/macos_capture.swift')
        self.assertIn('session.lifetime === lifetime', swift)
        self.assertIn('operations.removeValue(forKey: id)', swift)
        self.assertIn('operation?.isCancelled != true', swift)
        self.assertIn('cancelled: operation.map', swift)

    def test_new_windows_gate_is_separate_and_all_cases_are_required(self):
        existing = read('tests/windows-native-capture-smoke.ps1')
        new = read('tests/windows-screenshot-window-smoke.ps1')
        self.assertRegex(existing, r'foreach\(string kind in new string\[\]\{')
        modes = re.search(r'foreach\(string kind in new string\[\]\{([^}]+)\}', new)
        self.assertIsNotNone(modes)
        names = re.findall(r'"([^"]+)"', modes[1])
        self.assertEqual(len(names), 10)
        self.assertEqual(len(set(names)), 10)
        self.assertIn('ok&&cases.Count==10', new)
        self.assertIn('ISOLATION_REQUIRED', new)
        self.assertIn('zeroUnderlyingInput', new)
        self.assertIn('image.Width==expected.Width&&image.Height==expected.Height', new)
        self.assertIn('CAPTURE_WINDOW_CHANGED:', new)
        self.assertNotIn('SetWindowDisplayAffinity', read('src-tauri/src/windows_capture_native.rs'))

    def test_generated_windows_are_ready_before_any_input_or_capture(self):
        existing = read('tests/windows-native-capture-smoke.ps1')
        setup = existing.split('public Sources(Dictionary<string,object> report=null)', 1)[1].split('void Prepare(', 1)[0]
        self.assertIn('A.BeginInvoke((Action)delegate', setup)
        self.assertIn('SetWindowPos(Background.Handle,BH', setup)
        wait = setup.split('Stopwatch visible=Stopwatch.StartNew()', 1)[1].split('Send(new INPUT[]{Move(First)})', 1)[0]
        self.assertIn('visible.ElapsedMilliseconds<2000', wait)
        self.assertIn('consecutive==3&&GetAncestor(WindowFromPoint(First),2)==AH', wait)
        self.assertIn('GetAncestor(WindowFromPoint(Last),2)==BH', wait)
        self.assertNotIn('SetWindowPos(', wait)
        self.assertNotIn('SetForegroundWindow(', wait)
        self.assertNotIn('Send(', wait)
        self.assertIn('report["generatedSourceSetup"]=setup', setup)
        self.assertIn('source=new Sources(report);', read('tests/windows-screenshot-window-smoke.ps1'))


class ScreenshotWindowWorkflowContract(unittest.TestCase):
    def test_normal_and_release_require_built_child_fixture_and_raw_inventory(self):
        for name in ['ci.yml', 'release-checks.yml']:
            source = read('.github/workflows/' + name)
            self.assertIn('id: windows_screenshot_window', source)
            self.assertIn("screenshotWindow = '${{ steps.windows_screenshot_window.outcome }}'", source)
            self.assertIn('scripts/verify-screenshot-window-report.py', source)
            self.assertIn('echolingo-screenshot-window.log', source)
            self.assertIn("-NativeCapturePath '${{ steps.windows_native_candidate.outputs.capturePath }}'", source)
            self.assertIn('scripts/verify-native-capture-report.py', source)
            self.assertIn("nativeCaptureContinuity = '${{ steps.windows_native_capture_continuity.outcome }}'", source)

if __name__ == '__main__':
    unittest.main()
