"""Offline synthetic tests only; no installation or publication is performed."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
R=load('release026','prepare-desktop-026.py')
H=load('historical_fixtures','test_prepare_desktop_release.py')

class InstalledPreparation(unittest.TestCase):
    def setUp(self):
        self.old=H.R;H.R=R.legacy;self.addCleanup(setattr,H,'R',self.old)
        self.f=H.PreparationTests(methodName='runTest');self.f.setUp();self.addCleanup(self.f.doCleanups)
        for platform in ('Windows','macOS'):
            c=self.f.reports[platform];old=self.f.inputs/platform/c['installer']['name']
            new=old.with_name(old.name.replace('0.2.18','0.2.26'));old.rename(new)
            c['installer']=R.legacy.identity(new);self.f.save(platform)
        c=self.f.reports['Windows']
        self.report={k:True for k in ('ok','windowsRuntimeExecuted','installerExecuted','realModelExecuted','rulesRemoved','ownedInstallRemoved','installedPackageTested','installedScreenshotEditorVerified')}
        self.report.update(mockTranslationUsed=False,installerSha256=c['installer']['sha256'],installerBytes=c['installer']['size'],applicationSha256=c['application']['sha256'],installedApplication={'ok':True,'translationBackend':'real-bundled-offline-model','mockRequests':[],'defaultCaptureWithoutEnvironmentRequested':True,'captureBackendEnvironmentAbsent':True,'defaultNativeCaptureCompletion':{'nativeCaptureBackend':1}})
        self.path=self.f.inputs/'Windows/echolingo-offline-validation.json';self.save()
    def save(self):self.path.write_text(json.dumps(self.report))
    def prepare(self):return R.prepare(self.f.inputs,self.f.output,H.RUN)
    def test_complete_same_byte_manifest_and_sums(self):
        result=self.prepare();self.assertTrue(result['scope']['installerExecuted']);a=result['windowsInstalledAcceptance']
        self.assertEqual(a['commit'],H.SHA);self.assertEqual(a['runUrl'],H.RUN)
        self.assertEqual(a['evidence'],R.legacy.identity(self.path))
        self.assertEqual(len(list(self.f.output.iterdir())),7)
        for line in (self.f.output/'SHA256SUMS.txt').read_text().splitlines():
            sha,name=line.split(maxsplit=1);self.assertEqual(sha,hashlib.sha256((self.f.output/name).read_bytes()).hexdigest())
    def test_missing_report_never_creates_assets(self):
        self.path.unlink()
        with self.assertRaises((ValueError,FileNotFoundError)):self.prepare()
        self.assertFalse(self.f.output.exists())
    def test_all_flags_required(self):
        for key in ('ok','windowsRuntimeExecuted','installerExecuted','realModelExecuted','rulesRemoved','ownedInstallRemoved','installedPackageTested','installedScreenshotEditorVerified'):
            for bad in (False,None,'true'):
                old=self.report[key];self.report[key]=bad;self.save()
                with self.subTest(key=key,bad=bad),self.assertRaises(ValueError):self.prepare()
                self.assertFalse(self.f.output.exists());self.report[key]=old
    def test_wrong_bytes_never_transfer(self):
        for key,bad in [('installerSha256','0'*64),('installerBytes',1),('applicationSha256','0'*64)]:
            old=self.report[key];self.report[key]=bad;self.save()
            with self.subTest(key=key),self.assertRaises(ValueError):self.prepare()
            self.assertFalse(self.f.output.exists());self.report[key]=old
    def test_mock_or_incomplete_core_rejected(self):
        for key,bad in [('mockRequests',['fake']),('translationBackend','mock'),('defaultCaptureWithoutEnvironmentRequested',False),('captureBackendEnvironmentAbsent',False)]:
            old=self.report['installedApplication'][key];self.report['installedApplication'][key]=bad;self.save()
            with self.subTest(key=key),self.assertRaises(ValueError):self.prepare()
            self.assertFalse(self.f.output.exists());self.report['installedApplication'][key]=old
    def test_legacy_macos_gate_remains(self):
        (self.f.inputs/'macOS/macos-runtime.json').unlink()
        with self.assertRaises((ValueError,FileNotFoundError)):self.prepare()
        self.assertFalse(self.f.output.exists())
    def test_no_overwrite(self):
        self.prepare()
        with self.assertRaises(ValueError):self.prepare()

class StaticContracts(unittest.TestCase):
    def test_historical_and_normal_gates_unchanged(self):
        names=('scripts/prepare-desktop-release.py','scripts/publish-desktop-release.cjs','scripts/test-desktop-release.cjs',
               'scripts/test_prepare_desktop_release.py','.github/workflows/release-desktop.yml','.github/workflows/ci.yml',
               'scripts/windows-offline-translation-test.ps1')
        for version in ('021','022','023','024','025'):
            names += (f'.github/workflows/release-desktop-{version}.yml', f'scripts/prepare-desktop-{version}.py',
                      f'scripts/publish-desktop-{version}.cjs', f'scripts/test_prepare_desktop_{version}.py',
                      f'scripts/test-desktop-{version}.cjs')
        for name in names:
            with self.subTest(path=name):
                expected=subprocess.check_output(['git','show',R.REVIEWED_SOURCE+':'+name],cwd=ROOT)
                current=(ROOT/name).read_bytes().replace(b'\r\n',b'\n')
                # Prior fixture bytes or the exact additive 0.2.27 CLI compatibility review.
                approved_version_cli_fixtures={
                    'scripts/test_prepare_desktop_022.py': '495a498da2fc47ec47112a98bdc2c9cf62aa3778c8071b9de83e5b65b091d9d4',
                    'scripts/test_prepare_desktop_023.py': 'b041a2ff3a2a60ddff7ca3aafb982cec8e3ee4f9503e6a578d31001a302670a8',
                    'scripts/test_prepare_desktop_024.py': '1872ef75ab00bf6b721bee606476c59b703456b422dbedee04f68ee9e315c906',
                    'scripts/test_prepare_desktop_025.py': '08d85b5d38e39a00bd2f437eb6e177047f7205189218fc028594fee1f3e8df23',
                }
                if name in approved_version_cli_fixtures and current != expected:
                    self.assertEqual(hashlib.sha256(current).hexdigest(),approved_version_cli_fixtures[name])
                else:
                    self.assertEqual(current,expected)

    def test_reviewed_app_version_inputs_are_exact(self):
        self.assertEqual(R.REVIEWED_APP, '315c47f6f3d733cf7c95a449d13f2430bb524f22')
        self.assertEqual(len(R.VERSION_INPUTS), 14)
        from unittest.mock import patch
        with patch.object(R.legacy, 'check_source') as publish_guard:
            R.check_source()
        publish_guard.assert_called_once_with()

    def test_reviewed_app_validation_rejects_missing_or_changed_scope(self):
        # The real immutable commits are checked above; this proves scope failure
        # stops preparation even when the historical version guard would pass.
        from unittest.mock import patch
        for output in ('', '\n'.join(sorted(R.VERSION_INPUTS | {'src-tauri/native/macos.swift'}))):
            with patch.object(R.legacy, 'git', return_value=output), \
                    patch.object(R.legacy, 'check_source') as publish_guard, \
                    self.assertRaisesRegex(ValueError, 'Unexpected changes to audited application source'):
                R.check_source()
            publish_guard.assert_not_called()

    def test_explicit_same_installer_and_original_script(self):
        s=(ROOT/'.github/workflows/release-desktop-026.yml').read_text()
        self.assertIn('-InstallerPath $installers[0].FullName',s)
        self.assertIn('-File scripts/windows-offline-translation-test.ps1',s)
        self.assertIn("-NativeCapturePath '${{ steps.windows_native_candidate.outputs.capturePath }}'",s)
        self.assertIn('if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }',s)
        self.assertNotIn('continue-on-error:',s)
        self.assertIn('npm audit --audit-level=high',s)
        self.assertIn('test_prepare_desktop_release.py',s)
        self.assertIn('test-desktop-release.cjs',s)
        self.assertIn('--expected-version 0.2.26 --installer',s)
        self.assertIn('needs: [build, browser]',s)
        self.assertIn("  browser:\n    if: github.repository == 'Blueeeecho/EchoLingo' && github.ref == 'refs/heads/main'",s)
        self.assertNotIn('  pull_request:',s)
        self.assertIn('settings-navigation screenshot-editor',s)
        self.assertIn('tests/macos-header-event-route.swift',s)
    def test_support_does_not_allow_application_or_historical_changes(self):
        self.assertEqual(R.legacy.SUPPORT, {'scripts/prepare-desktop-026.py','scripts/publish-desktop-026.cjs','scripts/test_prepare_desktop_026.py','scripts/test-desktop-026.cjs','.github/workflows/release-desktop-026.yml','docs/releases/0.2.26.zh-CN.md'})

class RuntimeIntegrityContracts(unittest.TestCase):
    def test_only_live_workers_reuse_offline_model_validation(self):
        path = 'src-tauri/src/offline_translation.rs'
        baseline = subprocess.check_output(
            ['git', 'show', R.legacy.MANIFEST_BASELINE+':'+path], cwd=ROOT
        )
        # The known-good implementation validates each new worker and only
        # reuses a child after a complete valid response.
        self.assertEqual((ROOT/path).read_bytes().replace(b'\r\n', b'\n'), baseline)

    def test_debounce_and_shutdown_keep_shared_lock_during_disk_write(self):
        path = 'src-tauri/src/window_layout.rs'
        baseline = subprocess.check_output(
            ['git', 'show', R.legacy.MANIFEST_BASELINE+':'+path], cwd=ROOT, text=True
        )
        current = (ROOT/path).read_text(encoding='utf-8')
        def persistence_methods(source):
            start = source.index('    fn schedule_save(')
            stop = source.index('\n}\n', start)
            return source[start:stop]
        # Restoring the old serialization leaves unrelated geometry and
        # observer improvements intact.
        self.assertEqual(persistence_methods(current), persistence_methods(baseline))
        self.assertNotIn('saved_revision', current)


class VersionCLIContracts(unittest.TestCase):
    def test_helpers_are_only_additive_relative_to_previous_public_sources(self):
        for path in ('scripts/inspect-candidate-package.py',
                     'scripts/verify-candidate-package.py',
                     'tests/macos-installed-runtime-smoke.py'):
            with self.subTest(path=path):
                before=subprocess.check_output(['git','show',R.legacy.MANIFEST_BASELINE+':'+path],cwd=ROOT)
                old=b'"0.2.25"), default=VERSION)'
                self.assertEqual(before.count(old),1)
                released=subprocess.check_output(['git','show','3a64d2e2a6c9cf038326132aafff58693931e7f5:'+path],cwd=ROOT)
                self.assertEqual(released,before.replace(old,b'"0.2.25", "0.2.26"), default=VERSION)',1))
                with26=released
                tail26=b'"0.2.26"), default=VERSION)'
                self.assertEqual(with26.count(tail26),1)
                with27=with26.replace(tail26,b'"0.2.26", "0.2.27"), default=VERSION)',1)
                current=(ROOT/path).read_bytes().replace(b'\r\n',b'\n')
                self.assertIn(current,(released,with27))

    def test_version_cli_reaches_real_validation_and_rejects_unknown_version(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'runtime.json'
            common=['--installer','nonexistent-installer','--run-url','invalid-run-url']
            cases=[
                ('scripts/inspect-candidate-package.py',
                 ['--platform','Windows','--built-application','unbuilt','--output-dir',directory],
                 'Locked build and focused-test attestations are required'),
                ('scripts/verify-candidate-package.py',
                 ['--platform','Windows','--application','unbuilt','--checks-json','missing',
                  '--output',str(output)],
                 'A canonical candidate build run URL is required'),
            ]
            # This macOS-only probe imports the POSIX pwd module. Both shared
            # package tools still run on Windows; macOS CI runs this extra case.
            if sys.platform != 'win32':
                cases.append(('tests/macos-installed-runtime-smoke.py',
                              ['--built-application','unbuilt','--output',str(output)],None))
            for path, arguments, detail in cases:
                for version in ('0.2.24','0.2.25','0.2.26','0.2.999'):
                    with self.subTest(path=path, version=version):
                        if output.exists(): output.unlink()
                        run=subprocess.run([sys.executable,str(ROOT/path),'--expected-version',
                                            version,*common,*arguments],cwd=ROOT,capture_output=True,text=True)
                        if version == '0.2.999':
                            self.assertEqual(run.returncode,2)
                            self.assertIn('invalid choice',run.stderr)
                            self.assertFalse(output.exists())
                        else:
                            self.assertEqual(run.returncode,1,run.stderr)
                            if detail is not None:
                                self.assertIn(detail,run.stderr)
                            else:
                                report=json.loads(output.read_text())
                                self.assertEqual(report['version'],version)
                                self.assertEqual(report['failureStage'],'runner_preflight')
                                self.assertFalse(report['ok'])
                                self.assertFalse(report['extractedBundleLaunched'])


if __name__=='__main__':unittest.main()
