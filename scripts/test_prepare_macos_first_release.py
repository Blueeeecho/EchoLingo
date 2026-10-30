import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('macrelease', pathlib.Path(__file__).with_name('prepare-macos-first-release.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class MacReleaseTests(unittest.TestCase):
    def archive(self, entries):
        out = io.BytesIO()
        with zipfile.ZipFile(out, 'w') as z:
            for name, data in entries:
                z.writestr(name, data)
        return out.getvalue()

    def test_changed_archive_fails_before_extraction(self):
        with self.assertRaisesRegex(ValueError, 'artifact digest'):
            m.tested_dmg(b'changed')

    def test_exact_inventory_rejects_extra_or_traversal_entries(self):
        for entries in [[('../evil', b'x')], [(m.ENTRY, b'x'), ('unexpected.exe', b'x')]]:
            archive = self.archive(entries)
            with patch.object(m, 'ARCHIVE_SHA', m.digest(archive)):
                with self.assertRaisesRegex(ValueError, 'inventory'):
                    m.tested_dmg(archive)

    def test_dmg_hash_checked_independently(self):
        archive = self.archive([(m.ENTRY, b'x' * 4918215)])
        with patch.object(m, 'ARCHIVE_SHA', m.digest(archive)):
            with self.assertRaisesRegex(ValueError, 'DMG digest'):
                m.tested_dmg(archive)

    def test_manifest_is_mac_only_and_source_is_not_publisher(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            archive = root / 'artifact.zip'; archive.write_bytes(b'fixture')
            output = root / 'out'
            def archive_source(args, check):
                self.assertEqual(args[-1], m.SOURCE)
                pathlib.Path(args[args.index('-o') + 1]).write_bytes(b'exact source fixture')
            with patch.object(m, 'tested_dmg', return_value=b'tested dmg'), patch.object(m.subprocess, 'run', side_effect=archive_source):
                manifest = m.prepare(archive, output, 'a' * 40)
            self.assertEqual(manifest['commit'], m.SOURCE)
            self.assertEqual(manifest['publisherCommit'], 'a' * 40)
            self.assertEqual(manifest['platforms'], ['macos-arm64'])
            self.assertFalse(manifest['windows']['published'])
            self.assertFalse(manifest['verification']['windowsAcceptancePassed'])
            self.assertEqual(manifest['verification']['overallRunConclusion'], 'failure')
            self.assertEqual(len(list(output.iterdir())), 4)
            self.assertEqual(len((output / 'SHA256SUMS.txt').read_text().splitlines()), 3)
            self.assertFalse(any(p.suffix == '.exe' for p in output.iterdir()))
            with patch.object(m, 'tested_dmg', return_value=b'tested dmg'):
                with self.assertRaisesRegex(ValueError, 'overwrite'):
                    m.prepare(archive, output, 'a' * 40)

    def test_invalid_publisher_rejected(self):
        with self.assertRaisesRegex(ValueError, 'publisher'):
            m.prepare('missing', 'missing', 'not-a-sha')

if __name__ == '__main__': unittest.main()
