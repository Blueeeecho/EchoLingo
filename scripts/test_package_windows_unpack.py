"""Focused packaging tests; synthetic bytes are not Windows runtime acceptance."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location('unpack', Path(__file__).with_name('package-windows-unpack.py'))
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)


class UnpackPackageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.file = self.root/'input'
        self.file.write_bytes(b'fixture')

    def test_archive_roundtrip_and_existing_output_refused(self):
        archive = self.root/'output.zip'
        PACK.write_archive(archive, {'echolingo.exe': self.file, 'offline-translation/model.bin': self.file})
        with zipfile.ZipFile(archive) as zip_file:
            self.assertEqual(zip_file.read('echolingo.exe'), b'fixture')
            self.assertEqual(len(zip_file.namelist()), 2)
        with self.assertRaises(FileExistsError):
            PACK.write_archive(archive, {'echolingo.exe': self.file})

    def test_unsafe_names_rejected_before_writing(self):
        for name in ('../settings.json', '/absolute', 'x/../../key', 'x\\key', 'x:secret', 'x//y', 'x./y'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                PACK.write_archive(self.root/'bad.zip', {name: self.file})
            self.assertFalse((self.root/'bad.zip').exists())

    def test_case_alias_rejected(self):
        with self.assertRaises(ValueError):
            PACK.write_archive(self.root/'bad.zip', {'Echo.exe': self.file, 'echo.exe': self.file})

    def test_symlink_rejected(self):
        link = self.root/'link'
        try:
            link.symlink_to(self.file)
        except OSError:
            self.skipTest('Symlink privilege unavailable on this Windows runner')
        with self.assertRaises(ValueError):
            PACK.write_archive(self.root/'bad.zip', {'echolingo.exe': link})

    def test_missing_or_empty_input_rejected(self):
        self.file.write_bytes(b'')
        with self.assertRaises(ValueError):
            PACK.write_archive(self.root/'bad.zip', {'echolingo.exe': self.file})

    def test_package_only_includes_explicit_inputs(self):
        def write(name, data):
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            return path
        write('package.json', b'{"version":"0.2.13"}')
        write('src-tauri/tauri.windows.conf.json', json.dumps({'bundle': {'resources': {
            '../resources/offline-translation/manifest.json': 'offline-translation/manifest.json',
            '../resources/offline-translation/licenses/': 'offline-translation/licenses/'}}}).encode())
        write('resources/offline-translation/manifest.json', b'{}')
        write('resources/offline-translation/license-files.json', b'{"files":[{"path":"licenses/LICENSE"}]}')
        write('resources/offline-translation/licenses/secret.key', b'never package this')
        write('resources/offline-translation/licenses/LICENSE', b'license')
        write('resources/offline-translation/settings.json', b'never package this')
        write('LICENSE', b'license')
        write('packaging/windows/Start-EchoLingo.cmd', b'fixture')
        write('packaging/windows/README-Windows.txt', b'fixture')
        application = write('build/echolingo.exe', b'MZsynthetic-not-a-real-application')
        write('build/history.json', b'never package this')
        write('build/secret.key', b'never package this')
        source = self.root/'source.zip'
        with zipfile.ZipFile(source, 'w') as archive:
            for name in ('scripts/offline-engine/main.cpp', 'scripts/offline-engine/sources.lock.json'):
                write(name, b'source')
                archive.writestr(name, b'source')
        with patch.object(PACK, 'ROOT', self.root), patch.object(PACK, 'audit_module', return_value=SimpleNamespace(inventory=lambda **_: {'ok': True}, REQUIRED_NOTICES={'LICENSE'})), patch.object(PACK.subprocess, 'check_output', return_value='0'*40):
            PACK.package(application, source, self.root/'out')
        with zipfile.ZipFile(self.root/'out/EchoLingo_0.2.13_windows_x64-unpack.zip') as archive:
            self.assertEqual(set(archive.namelist()), {'echolingo.exe', 'LICENSE.txt', 'Start-EchoLingo.cmd', 'README-Windows.txt', 'offline-translation/manifest.json', 'offline-translation/licenses/LICENSE'})
        manifest = json.loads((self.root/'out/WINDOWS-ZIP-MANIFEST.json').read_text())
        self.assertFalse(manifest['userDataPortable'])
        self.assertEqual(manifest['webview2'], 'external-evergreen-runtime-required')
        self.assertEqual(manifest['files'][2]['path'], 'Start-EchoLingo.cmd')

    def test_storage_and_launcher_contract(self):
        main = (PACK.ROOT/'src-tauri/src/main.rs').read_text()
        cargo = (PACK.ROOT/'src-tauri/Cargo.toml').read_text()
        self.assertIn('let data_dir = app.path().app_data_dir()?;', main)
        self.assertIn('app.path().resource_dir()?.join("offline-translation")', main)
        self.assertIn('features = ["windows-native"]', cargo)
        launcher = (PACK.ROOT/'packaging/windows/Start-EchoLingo.cmd').read_text()
        self.assertIn('{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', launcher)
        self.assertIn("$v -gt [version]'0.0.0.0'", launcher)
        self.assertIn('HKLM:', launcher)
        self.assertIn('HKCU:', launcher)
        self.assertNotIn('ExecutionPolicy', launcher)
        self.assertNotIn('Invoke-WebRequest', launcher)
        self.assertNotIn('Set-ItemProperty', launcher)


if __name__ == '__main__':
    unittest.main()
