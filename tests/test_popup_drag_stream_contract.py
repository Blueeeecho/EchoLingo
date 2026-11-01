"""Ensure the tested native-token policy is wired to both DOM loss events."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
PANEL = (ROOT / 'src/panel-layout.ts').read_text()

class PopupDragStreamContract(unittest.TestCase):
    def test_cancel_and_implicit_capture_loss_share_the_tested_policy(self):
        self.assertIn("document.addEventListener('pointercancel', lostPopupCapture)", PANEL)
        self.assertIn("document.addEventListener('lostpointercapture', lostPopupCapture)", PANEL)
        self.assertIn('popupDrag.retainsAfterStreamLoss(event.pointerId, event.pointerType)', PANEL)
        self.assertNotIn("document.addEventListener('pointercancel', cancelPopupDrag)", PANEL)

    def test_blur_and_disposal_still_cancel(self):
        self.assertIn("window.addEventListener('blur', cancelPopupDrag)", PANEL)
        self.assertIn("document.removeEventListener('pointercancel', lostPopupCapture)", PANEL)
        self.assertIn('presentationWait?.abort(); cancelPopupDrag();', PANEL)

    def test_native_toolbar_drag_accepts_mouse_only(self):
        toolbar = PANEL.split('const dragTarget =')[1].split('// Custom commands')[0]
        self.assertIn("if (event.pointerType !== 'mouse') return;", toolbar)
        self.assertLess(toolbar.index("event.pointerType !== 'mouse'"), toolbar.index('popupDrag.press('))

if __name__ == '__main__': unittest.main()
