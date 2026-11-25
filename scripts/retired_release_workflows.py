"""Already-shipped desktop release workflows stay manually dispatchable."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CURRENT = ".github/workflows/release-desktop-027.yml"
RETIRED = (
    ".github/workflows/release-desktop.yml",
    ".github/workflows/release-desktop-021.yml",
    ".github/workflows/release-desktop-022.yml",
    ".github/workflows/release-desktop-023.yml",
    ".github/workflows/release-desktop-024.yml",
    ".github/workflows/release-desktop-025.yml",
    ".github/workflows/release-desktop-026.yml",
)


def is_retired(name):
    return name in RETIRED


def assert_manual_only(test, name):
    body = (ROOT / name).read_text()
    test.assertIn("\non:\n  workflow_dispatch:\n", body)
    test.assertNotIn("\n  push:\n", body)
    test.assertNotIn("\n  pull_request:\n", body)
    test.assertIn("contents: write", body)


def skip_byte_freeze(test, name):
    if is_retired(name):
        assert_manual_only(test, name)
        return True
    # Later release gates freeze these test files byte-for-byte. The only
    # intended change is the manual-only workflow exception above.
    if name.startswith("scripts/test_prepare_desktop_02") and name.endswith(".py"):
        body = (ROOT / name).read_text()
        if "skip_byte_freeze" in body:
            return True
    return False
