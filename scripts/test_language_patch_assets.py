import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from test_prepare_release_assets import RELEASE
import test_prepare_release_assets as full_fixtures


class LanguagePatchAssetsTests(unittest.TestCase):
    def setUp(self):
        fixture = full_fixtures.ReleaseAssetsTests('test_versions_are_consistent')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.fixture = fixture
        self.evidence = fixture.artifacts / 'EchoLingo-language-patch-evidence'
        self.evidence.mkdir()
        self.source = self.evidence / fixture.source.name
        self.source.write_bytes(fixture.source.read_bytes())
        fixture.report.update(installerSha256=RELEASE.LANGUAGE_PATCH_INSTALLER['sha256'],
                              installerBytes=RELEASE.LANGUAGE_PATCH_INSTALLER['size'])
        self.raw_report = self.evidence / 'baseline-offline-validation.json'
        self.raw_report.write_text(json.dumps(fixture.report))
        self.ident = lambda p: {'size': p.stat().st_size, 'sha256': RELEASE.sha256(p)}
        for name, value in [('LANGUAGE_PATCH_SOURCE', self.ident(self.source)),
                            ('LANGUAGE_PATCH_REPORT', self.ident(self.raw_report))]:
            mock = patch.object(RELEASE, name, value)
            mock.start()
            self.addCleanup(mock.stop)
        self.baseline = {
            'ok': True, 'validationMode': RELEASE.LANGUAGE_PATCH_MODE,
            'baselineCommit': RELEASE.LANGUAGE_PATCH_BASELINE['commit'],
            'baselineTree': RELEASE.LANGUAGE_PATCH_BASELINE['tree'],
            'baselineRunId': RELEASE.LANGUAGE_PATCH_BASELINE['runId'],
            'baselineArtifacts': copy.deepcopy(RELEASE.LANGUAGE_PATCH_ARTIFACTS),
            'baselineInstaller': dict(RELEASE.LANGUAGE_PATCH_INSTALLER),
            'baselineInstallerSha256': RELEASE.LANGUAGE_PATCH_INSTALLER['sha256'],
            'baselineReport': self.ident(self.raw_report), 'sourceArchive': self.ident(self.source),
            'baselineInstalledAcceptanceVerified': True, 'baselineInstalledScreenshotEditorVerified': True,
            'offlineResourcesVerified': True,
            'resourceAudit': {s: {'ok': True, 'stagedPayloadChecked': True} for s in ('extracted', 'staged')},
            **{s: False for s in ('visualAcceptanceRepeated', 'oldApplicationStaged', 'newInstallerAccepted',
                                  'installerExecuted', 'engineExecuted', 'visualTestsExecuted')},
        }
        self.reports = {}
        for platform, name, installer in [('Windows', 'windows-build.json', fixture.windows),
                                           ('macOS', 'macos-build.json', fixture.macos)]:
            self.reports[name] = {'validationMode': RELEASE.LANGUAGE_PATCH_MODE, 'commit': 'a' * 40,
                'platform': platform, 'visualAcceptanceRepeated': False,
                'targetedLanguageTestsPassed': True, 'sourceGuardPassed': True,
                'versionVerified': True, 'lockedBuild': True, 'baseline': dict(RELEASE.LANGUAGE_PATCH_BASELINE),
                'installer': {'name': installer.name, **self.ident(installer)}}
        self.write()

    def write(self):
        (self.evidence / 'baseline-reuse.json').write_text(json.dumps(self.baseline))
        for name, report in self.reports.items():
            (self.evidence / name).write_text(json.dumps(report))

    def prepare(self):
        return RELEASE.prepare(self.fixture.artifacts, self.fixture.output, 'a' * 40,
            'https://github.com/Blueeeecho/EchoLingo/actions/runs/123', language_patch=True)

    def test_manifest_distinguishes_fresh_targeted_builds_from_old_installed_evidence(self):
        result = self.prepare()
        self.assertEqual(result['validationMode'], 'language-routing-patch-v1')
        for field in ('windowsInstalledAcceptanceVerified', 'windowsInstalledScreenshotEditorVerified',
                      'visualAcceptanceRepeated', 'rebuiltAfterValidation'):
            self.assertIs(result[field], False)
        self.assertEqual(set(result['targetedValidation']), {'Windows', 'macOS'})
        self.assertEqual(result['reusedBaseline']['commit'], RELEASE.LANGUAGE_PATCH_BASELINE['commit'])
        self.assertEqual(result['reusedBaseline']['artifacts'], RELEASE.LANGUAGE_PATCH_ARTIFACTS)
        self.assertEqual(result['reusedBaseline']['installer'], RELEASE.LANGUAGE_PATCH_INSTALLER)
        self.assertEqual(result['reusedBaseline']['sourceArchive'], RELEASE.LANGUAGE_PATCH_SOURCE)
        self.assertEqual(len(result['files']), 3)
        for line in (self.fixture.output / 'SHA256SUMS.txt').read_text().splitlines():
            digest, name = line.split('  ', 1)
            self.assertEqual(digest, RELEASE.sha256(self.fixture.output / name))

    def test_rejects_each_wrong_build_identity_or_gate_for_either_platform(self):
        for name in self.reports:
            for field, value in [('commit', 'b'*40), ('platform', 'other'), ('validationMode', 'full'),
                                 ('baseline', {}), ('installer', {}), ('targetedLanguageTestsPassed', False),
                                 ('sourceGuardPassed', False), ('versionVerified', False), ('lockedBuild', False),
                                 ('visualAcceptanceRepeated', True)]:
                with self.subTest(name=name, field=field):
                    original = self.reports[name][field]
                    self.reports[name][field] = value
                    self.write()
                    with self.assertRaises(ValueError): self.prepare()
                    self.assertFalse(self.fixture.output.exists())
                    self.reports[name][field] = original

    def test_rejects_unpinned_or_execution_claiming_baseline(self):
        for field, value in [('baselineCommit', 'b'*40), ('baselineTree', 'b'*40), ('baselineRunId', 1),
                             ('baselineArtifacts', {}), ('baselineInstaller', {}), ('baselineReport', {}),
                             ('sourceArchive', {}), ('resourceAudit', {}), ('offlineResourcesVerified', False),
                             ('visualAcceptanceRepeated', True), ('newInstallerAccepted', True)]:
            with self.subTest(field=field):
                original = self.baseline[field]
                self.baseline[field] = value
                self.write()
                with self.assertRaises(ValueError): self.prepare()
                self.baseline[field] = original

    def test_rejects_tampered_fresh_installer_and_raw_baseline_report(self):
        original = self.fixture.macos.read_bytes()
        self.fixture.macos.write_bytes(b'changed')
        with self.assertRaises(ValueError): self.prepare()
        self.fixture.macos.write_bytes(original)
        self.raw_report.write_text('{}')
        with self.assertRaises(ValueError): self.prepare()

    def test_historical_versions_cannot_opt_into_patch_mode(self):
        with patch.object(RELEASE, 'VERSION', '0.2.2'), self.assertRaises(ValueError):
            self.prepare()


if __name__ == '__main__':
    unittest.main()
