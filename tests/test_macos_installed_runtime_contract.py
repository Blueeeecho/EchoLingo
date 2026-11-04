"""Linux-safe contract tests. These do not run or accept the macOS app."""
from contextlib import contextmanager
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "macos_runtime", Path(__file__).with_name("macos-installed-runtime-smoke.py"))
smoke = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(smoke)


class RuntimeContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def args(self):
        return SimpleNamespace(installer=self.root / "candidate.dmg",
                               built_application=self.root / "EchoLingo.app",
                               run_url="https://github.com/Blueeeecho/EchoLingo/actions/runs/123",
                               native_self_tests_passed=True,
                               native_window_resize_fixture_passed=True)

    def bundle(self):
        app = self.root / "EchoLingo.app"
        binary = app / "Contents/MacOS/echolingo"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"synthetic contract fixture, not executable")
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": smoke.BUNDLE_ID,
                           "CFBundleExecutable": "echolingo",
                           "CFBundleVersion": smoke.VERSION,
                           "CFBundleShortVersionString": smoke.VERSION}, stream)
        return app

    def test_runner_guard_requires_all_three_conditions(self):
        for platform, actions, runner in [("linux", "true", "macOS"),
                                           ("darwin", "false", "macOS"),
                                           ("darwin", "true", "Linux")]:
            with self.subTest(platform=platform, actions=actions, runner=runner):
                with mock.patch.object(smoke.sys, "platform", platform), mock.patch.dict(
                        smoke.os.environ, {"GITHUB_ACTIONS": actions, "RUNNER_OS": runner}):
                    with self.assertRaisesRegex(smoke.SmokeError, "fresh_macos_actions_runner_required"):
                        smoke.require_runner()

    def test_guard_failure_writes_negative_evidence_without_launch(self):
        with mock.patch.object(smoke, "require_runner", side_effect=smoke.SmokeError("guard")), \
                mock.patch.object(smoke.subprocess, "Popen") as launch:
            result = smoke.run(self.args())
        launch.assert_not_called()
        self.assertFalse(result["ok"])
        self.assertTrue(result["cleanupComplete"])
        self.assertEqual(result["failureCode"], "guard")
        for field in ("fakeIpcUsed", "userContentRead", "codexInteractiveSelectionTested",
                      "frontendWebViewReady", "settingsWindowShown", "extractedBundleLaunched"):
            self.assertIs(result[field], False)

    def test_preexisting_state_is_never_read_deleted_or_launched(self):
        path = smoke.state_paths(self.root)[0]
        path.mkdir(parents=True)
        private = path / "history.json"
        private.write_text("private preexisting sentinel")
        with mock.patch.object(smoke, "require_runner", return_value=self.root), \
                mock.patch.object(smoke, "app_pids", return_value=set()), \
                mock.patch.object(smoke, "remove_owned_state") as remove, \
                mock.patch.object(smoke.subprocess, "Popen") as launch:
            result = smoke.run(self.args())
        remove.assert_not_called()
        launch.assert_not_called()
        self.assertEqual(result["failureCode"], "preexisting_app_state")
        self.assertEqual(private.read_text(), "private preexisting sentinel")

    def test_existing_process_refuses_before_state_inspection(self):
        with mock.patch.object(smoke, "require_runner", return_value=self.root), \
                mock.patch.object(smoke, "app_pids", return_value={123}), \
                mock.patch.object(smoke, "state_paths") as state:
            result = smoke.run(self.args())
        state.assert_not_called()
        self.assertEqual(result["failureCode"], "preexisting_app_process")

    def test_other_repository_run_url_refuses(self):
        args = self.args()
        args.run_url = "https://github.com/other/project/actions/runs/123"
        with mock.patch.object(smoke, "require_runner", return_value=self.root):
            report = smoke.run(args)
        self.assertEqual(report["failureCode"], "invalid_run_url")
        self.assertFalse(report["ok"])

    def test_cleanup_failure_cannot_report_success(self):
        with mock.patch.object(smoke, "require_runner", return_value=self.root), \
                mock.patch.object(smoke, "app_pids", return_value=set()), \
                mock.patch.object(smoke, "command", side_effect=RuntimeError("metadata failure")), \
                mock.patch.object(smoke, "remove_owned_state", side_effect=OSError("cleanup failure")):
            report = smoke.run(self.args())
        self.assertFalse(report["ok"])
        self.assertFalse(report["cleanupComplete"])
        self.assertEqual(report["failureCode"], "RuntimeError")

    def test_missing_native_attestation_refuses(self):
        args = self.args()
        args.native_window_resize_fixture_passed = False
        with mock.patch.object(smoke, "require_runner", return_value=self.root), \
                mock.patch.object(smoke, "app_pids") as pids:
            result = smoke.run(args)
        pids.assert_not_called()
        self.assertFalse(result["ok"])
        self.assertEqual(result["failureCode"], "native_prerequisites_missing")

    def test_manifest_detects_bytes_mode_and_missing_files(self):
        app = self.bundle()
        baseline = smoke.bundle_manifest(app)
        binary = smoke.validate_bundle(app)
        binary.write_bytes(b"different")
        self.assertNotEqual(smoke.bundle_manifest(app), baseline)
        binary.write_bytes(b"synthetic contract fixture, not executable")
        self.assertEqual(smoke.bundle_manifest(app), baseline)
        binary.chmod(0o755)
        self.assertNotEqual(smoke.bundle_manifest(app), baseline)
        binary.unlink()
        self.assertNotEqual(smoke.bundle_manifest(app), baseline)

    def test_manifest_rejects_external_symlink(self):
        app = self.bundle()
        (app / "outside").symlink_to(self.root)
        with self.assertRaisesRegex(smoke.SmokeError, "external_bundle_symlink"):
            smoke.bundle_manifest(app)

    def test_identity_rejects_other_version(self):
        app = self.bundle()
        info = app / "Contents/Info.plist"
        values = plistlib.loads(info.read_bytes())
        values["CFBundleVersion"] = "0.0.0"
        info.write_bytes(plistlib.dumps(values))
        with self.assertRaisesRegex(smoke.SmokeError, "bundle_identity_mismatch"):
            smoke.validate_bundle(app)

    def test_real_ready_accepts_settings_not_yet_loaded(self):
        diagnostic = self.root / "frontend-input-diagnostics.json"
        diagnostic.write_text(json.dumps({"processId": 123,
                                         "entries": [{"stage": "ready", "settingsReady": False}]}))
        self.assertTrue(smoke.frontend_ready(diagnostic, 123))
        self.assertFalse(smoke.frontend_ready(diagnostic, 124))

    def test_ready_requires_exact_pid_and_stage_not_arbitrary_event(self):
        diagnostic = self.root / "frontend-input-diagnostics.json"
        for value in ({"processId": 123, "entries": [{"stage": "arrival"}]},
                      {"processId": "123", "entries": [{"stage": "ready"}]},
                      {"processId": 123, "entries": []}, []):
            diagnostic.write_text(json.dumps(value))
            self.assertFalse(smoke.frontend_ready(diagnostic, 123))
        diagnostic.write_text('{"processId":')
        self.assertFalse(smoke.frontend_ready(diagnostic, 123))

    def test_ready_rejects_oversize_and_symlink(self):
        diagnostic = self.root / "diagnostic"
        diagnostic.write_bytes(b"x" * (smoke.MAX_DIAGNOSTIC_BYTES + 1))
        with self.assertRaisesRegex(smoke.SmokeError, "diagnostic_too_large"):
            smoke.frontend_ready(diagnostic, 123)
        link = self.root / "link"
        link.symlink_to(diagnostic)
        self.assertFalse(smoke.frontend_ready(link, 123))

    def test_window_requires_pid_bundle_accessory_and_visible_window(self):
        good = {"bundleIdentifier": smoke.BUNDLE_ID, "processId": 123,
                "onscreenAppWindowCount": 1, "applicationActivationPolicy": 1,
                "applicationIsHidden": False, "screenshotsTaken": False,
                "permissionRequestsMade": False}
        with mock.patch.object(smoke, "command", return_value=json.dumps(good).encode()):
            self.assertTrue(smoke.window_shown("probe", 123))
        for key, value in [("processId", 99), ("bundleIdentifier", "other"),
                           ("onscreenAppWindowCount", 0), ("applicationActivationPolicy", 0),
                           ("applicationIsHidden", True), ("permissionRequestsMade", True)]:
            with mock.patch.object(smoke, "command", return_value=json.dumps({**good, key: value}).encode()):
                self.assertFalse(smoke.window_shown("probe", 123))

    def test_await_ready_does_not_accept_dead_process(self):
        process = mock.Mock(pid=123)
        process.poll.return_value = 0
        with self.assertRaisesRegex(smoke.SmokeError, "release_process_exited_early"):
            smoke.await_ready(process, self.root / "diagnostic", "probe")

    def test_await_ready_is_bounded(self):
        process = mock.Mock(pid=123)
        process.poll.return_value = None
        with self.assertRaisesRegex(smoke.SmokeError, "webview_or_settings_deadline"):
            smoke.await_ready(process, self.root / "diagnostic", "probe", timeout=0)

    def test_cleanup_does_not_follow_symlink(self):
        outside = self.root / "outside"
        outside.mkdir()
        sentinel = outside / "sentinel"
        sentinel.write_text("retain")
        owned = self.root / "owned"
        owned.symlink_to(outside)
        self.assertTrue(smoke.remove_owned_state([owned]))
        self.assertTrue(sentinel.exists())

    def test_cleanup_refuses_symlink_parent(self):
        outside = self.root / "outside"
        outside.mkdir()
        parent = self.root / "parent"
        parent.symlink_to(outside)
        with self.assertRaisesRegex(smoke.SmokeError, "cleanup_symlink_parent"):
            smoke.remove_owned_state([parent / "app"])

    def test_symlink_temp_root_is_canonical_before_probe_and_dmg_mount(self):
        # Model macOS /var -> /private/var without requiring macOS or hdiutil.
        real = self.root / "real"
        real.mkdir()
        alias = self.root / "alias"
        alias.symlink_to(real, target_is_directory=True)
        owned = real / "owned.noindex"
        owned.mkdir()
        self.bundle()
        args = self.args()
        args.installer.write_bytes(b"contract fixture only")
        observed = []

        @contextmanager
        def readonly_dmg(installer, mountpoint):
            observed.append(mountpoint)
            raise RuntimeError("private mount diagnostic must not leak")
            yield  # This injected failure is before a mount is confirmed.

        inspection = SimpleNamespace(readonly_dmg=readonly_dmg)
        spec = SimpleNamespace(loader=SimpleNamespace(exec_module=lambda module: None))
        calls = []

        def command(arguments, timeout=30):
            calls.append(arguments)
            if "rev-parse" in arguments:
                return (("a" * 40) + "\n" + ("b" * 40) + "\n").encode()
            return b""

        with mock.patch.object(smoke, "require_runner", return_value=self.root), \
                mock.patch.object(smoke, "app_pids", return_value=set()), \
                mock.patch.object(smoke, "command", side_effect=command), \
                mock.patch.object(smoke.tempfile, "mkdtemp", return_value=str(alias / owned.name)), \
                mock.patch.object(smoke.importlib.util, "spec_from_file_location", return_value=spec), \
                mock.patch.object(smoke.importlib.util, "module_from_spec", return_value=inspection):
            report = smoke.run(args)
        self.assertEqual(observed, [owned.resolve(strict=True) / "mount"])
        probe_command = next(call for call in calls if call[0] == "xcrun")
        self.assertEqual(probe_command[-1], owned.resolve(strict=True) / "window-probe")
        self.assertFalse(report["ok"])
        self.assertEqual(report["failureStage"], "dmg_mount")
        self.assertEqual(report["failureCode"], "RuntimeError")
        self.assertNotIn("private mount diagnostic", json.dumps(report))
        # An uncertain mount must still prohibit deleting its enclosing root.
        self.assertFalse(report["cleanupComplete"])
        self.assertTrue(owned.exists())

    def test_unexpected_error_never_leaks_exception_message(self):
        with mock.patch.object(smoke, "require_runner", side_effect=ValueError("private sentinel")):
            report = smoke.run(self.args())
        self.assertEqual(report["failureCode"], "ValueError")
        self.assertEqual(report["failureStage"], "runner_preflight")
        self.assertNotIn("private sentinel", json.dumps(report))


if __name__ == "__main__":
    unittest.main()
