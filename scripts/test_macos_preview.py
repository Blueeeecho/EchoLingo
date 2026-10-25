"""Installer safety/rollback tests using disposable bundles, never the real app."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("macos_preview", Path(__file__).with_name("macos-preview.py"))
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class PreviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="echolingo-preview-test-")
        self.root = Path(self.temp.name).resolve()
        self.source = self.fixture(self.root / "build/EchoLingo.app", b"new preview")
        self.destination = self.fixture(self.root / "Applications/EchoLingo.app", b"old preview")
        self.stopped = 0

    def tearDown(self):
        self.temp.cleanup()

    def fixture(self, path, contents, bundle_id=preview.BUNDLE_ID):
        (path / "Contents/MacOS").mkdir(parents=True)
        binary = path / "Contents/MacOS/echolingo"
        binary.write_bytes(contents)
        binary.chmod(0o700)
        with (path / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": bundle_id, "CFBundleExecutable": "echolingo",
                          "CFBundleShortVersionString": "0.0.0-fixture"}, stream)
        return path

    def verify(self, path):
        metadata = preview.bundle_metadata(path)
        metadata["executable_sha256"] = preview.file_sha256(Path(metadata["executable"]))
        return metadata

    def stop(self):
        self.stopped += 1

    def install(self, **kwargs):
        return preview.transactional_install(self.source, self.destination,
                                             verifier=kwargs.get("verifier", self.verify),
                                             copier=kwargs.get("copier", shutil.copytree),
                                             stop=kwargs.get("stop", self.stop))

    def binary(self, path):
        return (path / "Contents/MacOS/echolingo").read_bytes()

    def assert_clean(self):
        self.assertFalse((self.destination.parent / ".EchoLingo.preview-install.lock").exists())
        self.assertFalse(list(self.destination.parent.glob(".echolingo-stage-*")))

    def test_installs_and_keeps_old_backup_and_source(self):
        result = self.install()
        self.assertEqual(self.binary(self.destination), b"new preview")
        self.assertEqual(self.binary(Path(result["backup"])), b"old preview")
        self.assertEqual(self.binary(self.source), b"new preview")
        self.assertEqual(self.stopped, 1)
        self.assert_clean()

    def test_signature_stage_failure_does_not_stop_or_touch_old_app(self):
        def verify(path):
            if path.parent.name.startswith(".echolingo-stage-"):
                raise preview.PreviewError("simulated invalid staged signature")
            return self.verify(path)
        with self.assertRaisesRegex(preview.PreviewError, "signature"):
            self.install(verifier=verify)
        self.assertEqual(self.binary(self.destination), b"old preview")
        self.assertEqual(self.stopped, 0)
        self.assert_clean()

    def test_corrupt_copy_is_rejected_even_if_metadata_matches(self):
        def copy(source, destination):
            shutil.copytree(source, destination)
            (destination / "Contents/MacOS/echolingo").write_bytes(b"corruption")
        with self.assertRaisesRegex(preview.PreviewError, "differs"):
            self.install(copier=copy)
        self.assertEqual(self.binary(self.destination), b"old preview")
        self.assertEqual(self.stopped, 0)
        self.assert_clean()

    def test_post_move_validation_failure_restores_old_app(self):
        def verify(path):
            if path == self.destination and self.binary(path) == b"new preview":
                raise preview.PreviewError("simulated post-move signature failure")
            return self.verify(path)
        with self.assertRaisesRegex(preview.PreviewError, "post-move"):
            self.install(verifier=verify)
        self.assertEqual(self.binary(self.destination), b"old preview")
        self.assertEqual(self.binary(self.source), b"new preview")
        self.assert_clean()

    def test_post_move_failure_with_no_old_app_removes_failed_copy(self):
        shutil.rmtree(self.destination)
        def verify(path):
            if path == self.destination:
                raise preview.PreviewError("simulated new install failure")
            return self.verify(path)
        with self.assertRaisesRegex(preview.PreviewError, "new install"):
            self.install(verifier=verify)
        self.assertFalse(self.destination.exists())
        self.assert_clean()

    def test_stop_failure_aborts_before_renaming(self):
        def stop():
            raise preview.PreviewError("simulated app refuses to exit")
        with self.assertRaisesRegex(preview.PreviewError, "refuses"):
            self.install(stop=stop)
        self.assertEqual(self.binary(self.destination), b"old preview")
        self.assert_clean()

    def test_failure_to_move_old_app_leaves_it_intact(self):
        rename = Path.rename
        def fail_old_move(path, target):
            if path == self.destination:
                raise OSError("simulated old-app rename failure")
            return rename(path, target)
        with patch.object(Path, "rename", fail_old_move):
            with self.assertRaisesRegex(OSError, "old-app rename"):
                self.install()
        self.assertEqual(self.binary(self.destination), b"old preview")
        self.assert_clean()

    def test_failure_to_move_new_app_restores_old_app(self):
        rename = Path.rename
        def fail_new_move(path, target):
            if path.parent.name.startswith(".echolingo-stage-"):
                raise OSError("simulated new-app rename failure")
            return rename(path, target)
        with patch.object(Path, "rename", fail_new_move):
            with self.assertRaisesRegex(OSError, "new-app rename"):
                self.install()
        self.assertEqual(self.binary(self.destination), b"old preview")
        self.assert_clean()

    def test_failed_rollback_preserves_backup_stage_and_recovery_journal(self):
        rename = Path.rename
        def fail_new_and_restore(path, target):
            if path.parent.name.startswith(".echolingo-stage-") or path.name.startswith(".EchoLingo.backup-"):
                raise OSError("simulated filesystem refusal")
            return rename(path, target)
        with patch.object(Path, "rename", fail_new_and_restore):
            with self.assertRaisesRegex(preview.PreviewError, "rollback failed"):
                self.install()
        backups = list(self.destination.parent.glob(".EchoLingo.backup-*.app"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(self.binary(backups[0]), b"old preview")
        self.assertEqual(len(list(self.destination.parent.glob(".echolingo-stage-*"))), 1)
        self.assertTrue((self.destination.parent / ".EchoLingo.preview-install.lock/transaction.json").exists())

    def test_refuses_unverified_process_without_signaling_any_pid(self):
        with patch.object(preview.os, "kill") as kill:
            with self.assertRaisesRegex(preview.PreviewError, "unverifiable"):
                preview.stop_verified([{"verified": True, "pid": 123, "executable": "/dummy/echolingo"},
                                       {"verified": False, "pid": 124, "executable": "/other/echolingo"}])
            kill.assert_not_called()

    def test_skips_reused_pid(self):
        with patch.object(preview, "process_path", return_value=Path("/unrelated/program")):
            with patch.object(preview.os, "kill") as kill:
                preview.stop_verified([{"verified": True, "pid": 123, "executable": "/dummy/echolingo"}])
                kill.assert_not_called()

    def test_second_launch_refused_before_spawning(self):
        with patch.object(preview, "echolingo_processes", return_value=[{"pid": 123}]):
            with patch.object(preview, "run") as launch:
                with self.assertRaisesRegex(preview.PreviewError, "second launch"):
                    preview.silent_launch({"executable": "/dummy/echolingo"})
                launch.assert_not_called()

    def test_ancestor_symlink_uses_resolved_bundle_and_install_identity(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        aliased_source = alias / "build/EchoLingo.app"
        aliased_destination = alias / "Applications/EchoLingo.app"
        metadata = preview.bundle_metadata(aliased_source)
        self.assertEqual(Path(metadata["path"]), self.source)
        self.assertEqual(Path(metadata["executable"]), self.source / "Contents/MacOS/echolingo")
        self.assertEqual(preview.install_paths(aliased_source, aliased_destination), (self.source, self.destination))
        result = preview.transactional_install(aliased_source, aliased_destination,
                                               verifier=self.verify, copier=shutil.copytree, stop=self.stop)
        self.assertEqual(Path(result["installed"]["path"]), self.destination)
        self.assertEqual(self.binary(self.destination), b"new preview")
        self.assertEqual(self.binary(Path(result["backup"])), b"old preview")
        self.assert_clean()

    def test_ancestor_symlink_sampling_matches_resolved_process_path(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        canonical_binary = self.source / "Contents/MacOS/echolingo"
        aliased_binary = alias / "build/EchoLingo.app/Contents/MacOS/echolingo"
        with patch.object(preview, "process_path", return_value=canonical_binary):
            with patch.object(preview, "run", return_value=preview.subprocess.CompletedProcess([], 0, "1024 0:00.02\n")):
                sample = preview.process_sample(123, aliased_binary)
        self.assertEqual(sample["rss_kib"], 1024)
        self.assertEqual(sample["cpu_seconds"], .02)

    def test_background_bundle_launch_with_ancestor_symlink_observes_canonical_pid(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        aliased_bundle = alias / "build/EchoLingo.app"
        canonical_binary = self.source / "Contents/MacOS/echolingo"
        metadata = {"path": str(aliased_bundle), "executable": str(aliased_bundle / "Contents/MacOS/echolingo")}
        with patch.object(preview, "echolingo_processes", side_effect=[[], [{"verified": True, "pid": 123, "executable": str(canonical_binary)}]]):
            with patch.object(preview, "run") as launch:
                with patch.object(preview, "process_sample", return_value={"rss_kib": 1024}) as sample:
                    pid, elapsed = preview.silent_launch(metadata)
        launch.assert_called_once_with(["/usr/bin/open", "-g", "-j", str(self.source)], timeout=10)
        sample.assert_called_once_with(123, canonical_binary)
        self.assertEqual(pid, 123)
        self.assertGreaterEqual(elapsed, 0)

    def test_rejects_different_app_identity(self):
        path = self.fixture(self.root / "unrelated/EchoLingo.app", b"unrelated", "example.unrelated")
        with self.assertRaisesRegex(preview.PreviewError, "identifier"):
            preview.bundle_metadata(path)
        shutil.rmtree(self.destination)
        path.rename(self.destination)
        with self.assertRaisesRegex(preview.PreviewError, "identifier"):
            self.install()
        self.assertEqual(self.binary(self.destination), b"unrelated")
        self.assertEqual(self.stopped, 0)

    def test_rejects_symlink_destination_and_source(self):
        linked = self.root / "linked/EchoLingo.app"
        linked.parent.mkdir()
        linked.symlink_to(self.destination, target_is_directory=True)
        with self.assertRaisesRegex(preview.PreviewError, "symlink"):
            preview.install_paths(self.source, linked)
        with self.assertRaisesRegex(preview.PreviewError, "symlink"):
            preview.bundle_metadata(linked)
        self.assertEqual(self.binary(self.destination), b"old preview")

    def test_rejects_identical_nested_and_wrong_named_destinations(self):
        for destination in (self.source, self.source / "Contents/EchoLingo.app", self.root / "Other.app"):
            with self.subTest(destination=destination):
                with self.assertRaises(preview.PreviewError):
                    preview.install_paths(self.source, destination)

    def test_rejects_executable_traversal_and_symlink(self):
        info = self.source / "Contents/Info.plist"
        with info.open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": preview.BUNDLE_ID, "CFBundleExecutable": "../../outside"}, stream)
        with self.assertRaisesRegex(preview.PreviewError, "executable"):
            preview.bundle_metadata(self.source)
        with info.open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": preview.BUNDLE_ID, "CFBundleExecutable": "echolingo"}, stream)
        binary = self.source / "Contents/MacOS/echolingo"
        binary.unlink()
        binary.symlink_to(self.destination / "Contents/MacOS/echolingo")
        with self.assertRaisesRegex(preview.PreviewError, "unsafe"):
            preview.bundle_metadata(self.source)

    def test_keeps_lock_if_another_install_already_has_it(self):
        lock = self.destination.parent / ".EchoLingo.preview-install.lock"
        lock.mkdir()
        with self.assertRaisesRegex(preview.PreviewError, "holds"):
            self.install()
        self.assertTrue(lock.exists())
        self.assertEqual(self.binary(self.destination), b"old preview")
        self.assertEqual(self.stopped, 0)

    def test_inventory_is_bounded_and_does_not_delete_copies(self):
        hidden_build = self.fixture(self.root / "node_modules/fixture/EchoLingo.app", b"ignored")
        found = preview.find_bundles([self.root], 2)
        self.assertEqual(set(found), {self.source, self.destination})
        self.assertTrue(hidden_build.exists())
        self.assertEqual(self.binary(self.destination), b"old preview")

    def test_cpu_time_formats(self):
        for text, seconds in (("0:00.01", .01), ("2:03.25", 123.25), ("1:02:03.50", 3723.5), ("2-1:02:03.50", 176523.5)):
            with self.subTest(text=text):
                self.assertEqual(preview.parse_cpu_time(text), seconds)


if __name__ == "__main__":
    unittest.main()
