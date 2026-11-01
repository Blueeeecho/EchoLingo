"""Source boundaries; native platform runtime/geometry require separate execution."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text()

class PersistentOverlayContract(unittest.TestCase):
    def test_geometry_session_is_typed_not_empty_png(self):
        source = read('src-tauri/src/screenshot.rs')
        selection = source.split('pub struct SelectionSession {', 1)[1].split('}', 1)[0]
        self.assertNotIn('png_base64', selection)
        self.assertIn('pub revision: u64', selection)
        start = source.split('pub fn start_capture(', 1)[1].split('pub struct SelectionRect', 1)[0]
        self.assertIn('select_screenshot_cancelable', start)
        self.assertNotIn('make_session(', start)
        self.assertNotIn('capture_selected_region_cancelable', start)
        self.assertIn('state.image.is_none() && state.selection.is_none()', source)

    def test_capture_claim_guard_cancel_and_retained_host(self):
        source = read('src-tauri/src/screenshot.rs')
        capture = source.split('pub async fn capture_screenshot_selection(', 1)[1].split('async fn publish_selection(', 1)[0]
        for marker in ('ensure_editor(&window)?', 'try_acquire()', 'selection.public.revision == revision', '!selection.capturing',
                       'selection.capturing = true', 'request.cancelled()', 'stored.intent != Some(session_id)',
                       'screenshot_overlay::suspend(', 'screenshot_overlay::resume('):
            self.assertIn(marker, capture)
        for forbidden in ('screenshot_overlay::prepare(', '.set_focus(', 'emit_session(', 'NSApp.activate'):
            self.assertNotIn(forbidden, capture)
        dismiss = source.split('fn dismiss_current(', 1)[1].split('#[cfg(test)]', 1)[0]
        for newline in ('\n', '\r\n'):
            self.assertIn('selection.request.cancellation().store(true,Ordering::SeqCst);',
                          ''.join(dismiss.replace('\n', newline).split()))

    def test_presentation_export_and_close_guards_are_revision_safe(self):
        source = read('src-tauri/src/screenshot.rs')
        presentation = source.split('pub async fn screenshot_editor_ready(', 1)[1].split('pub async fn close_screenshot_editor(', 1)[0]
        self.assertEqual(presentation.count('.with_presentable_geometry('), 2)
        locked = source.split('fn geometry_operation', 1)[1].split('pub(crate) fn check_image_revision', 1)[0]
        self.assertLess(locked.index('selection.capturing && !allow_capturing'), locked.index('return operation('))
        for name in ('save_screenshot_image', 'copy_screenshot_image'):
            body = source.split('pub async fn ' + name + '(', 1)[1].split('\n}', 1)[0]
            self.assertIn('check_image_revision(session_id, revision.unwrap_or(0))', body)
        self.assertIn('dismiss_revision(session_id, revision,', source)
        pin = read('src-tauri/src/screenshot_pins.rs')
        self.assertIn('check_image_revision(session_id, revision.unwrap_or(0))', pin)

    def test_mac_selection_retains_metadata_only_and_revalidates_final_capture(self):
        source = read('src-tauri/native/macos_capture.swift')
        select = source.split('func selectDeferredScreenshot(', 1)[1].split('func captureDeferredScreenshot(', 1)[0]
        self.assertIn('purpose: .screenshotSelection', select)
        self.assertIn('validateDeferredCapturePlan(snapshot)', select)
        self.assertNotIn('captureNativePlannedImage(', select)
        self.assertNotIn('imageBase64', select)
        capture = source.split('func captureDeferredScreenshot(', 1)[1]
        self.assertEqual(capture.count('validateDeferredCapturePlan(request.plan)'), 2)
        self.assertIn('input.count <= 65536', capture)
        self.assertIn('purpose: .screenshot, operation: cancellation', capture)
        self.assertIn('func echoLingoSuspendScreenshotOverlay', source)
        self.assertIn('host.panel.orderOut(nil)', source)
        focus = source.split('func echoLingoFocusScreenshotOverlay', 1)[1].split('@_cdecl', 1)[0]
        self.assertIn('host.panel.makeKey()', focus)
        self.assertNotIn('activate(', focus)
        resume = source.split('func echoLingoResumeScreenshotOverlay', 1)[1].split('// Temporary capture exclusion', 1)[0]
        for forbidden in ('makeKey(', 'makeFirstResponder(', 'echoLingoPrepareScreenshotOverlay('):
            self.assertNotIn(forbidden, resume)
        initial = source.split('func echoLingoShowScreenshotOverlay', 1)[1].split('@_cdecl("echolingo_resume', 1)[0]
        self.assertIn('host.panel.makeKey()', initial)
        self.assertNotIn('NSApp.activate', initial)


if __name__ == '__main__': unittest.main()
