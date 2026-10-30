"""Source wiring checks complement the production C# z-order self-test.

The self-test executes the coordinator and checks every simulated native move;
these checks prevent RegionPicker from bypassing it with the old public raise.
"""
from pathlib import Path
import unittest

NATIVE = (Path(__file__).resolve().parents[1] / "src-tauri/native/windows.ps1").read_text()


class CaptureZOrderContract(unittest.TestCase):
    def test_picker_uses_coordinator_not_direct_plane_raise(self):
        picker = NATIVE.split("    void UpdateFrame(bool moved) {", 1)[1].split("    void DisplaysChanged", 1)[0]
        self.assertIn("CaptureZOrderPolicy.Present(raise,", picker)
        self.assertIn("planes.EnsurePresented", picker)
        self.assertIn("planes.PresentBelow", picker)
        self.assertNotIn("planes.Present(", picker)

    def test_input_surface_has_no_public_unanchored_raise(self):
        plane = NATIVE.split("sealed class CaptureInputPlanes", 1)[1].split("sealed class CaptureDelegatedInput", 1)[0]
        self.assertIn("public bool EnsurePresented() { return Present(false, new IntPtr(-1)); }", plane)
        self.assertIn("return Present(true, bottomHint);", plane)
        self.assertNotIn("public bool Present(bool raise)", plane)


if __name__ == "__main__":
    unittest.main()
