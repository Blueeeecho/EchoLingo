"""Offline synthetic tests only; no installation or publication is performed."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
R=load('release021','prepare-desktop-021.py')
H=load('historical_fixtures','test_prepare_desktop_release.py')

class InstalledPreparation(unittest.TestCase):
    def setUp(self):
        self.old=H.R;H.R=R.legacy;self.addCleanup(setattr,H,'R',self.old)
        self.f=H.PreparationTests(methodName='runTest');self.f.setUp();self.addCleanup(self.f.doCleanups)
        for platform in ('Windows','macOS'):
            c=self.f.reports[platform];old=self.f.inputs/platform/c['installer']['name']
            new=old.with_name(old.name.replace('0.2.18','0.2.21'));old.rename(new)
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
        for name in ('scripts/prepare-desktop-release.py','scripts/publish-desktop-release.cjs','scripts/test-desktop-release.cjs','scripts/test_prepare_desktop_release.py','.github/workflows/release-desktop.yml','.github/workflows/ci.yml','scripts/windows-offline-translation-test.ps1'):
            expected=subprocess.check_output(['git','show',R.REVIEWED_SOURCE+':'+name],cwd=ROOT)
            current=(ROOT/name).read_bytes().replace(b'\r\n',b'\n')
            if name == '.github/workflows/ci.yml' and current != expected:
                self.assertEqual(hashlib.sha256(current).hexdigest(),'e056c7d9579ffffff69a9a6ed4eda31fdafd453c7af237d3dba104406ed7fd2c',name)
                continue
            if name == 'scripts/test_prepare_desktop_release.py' and current != expected:
                # The reviewed README sync changes only download-link fixture expectations.
                approved=subprocess.check_output(
                    ['git','show','3f00bf23a25b1ad49f81a9bcdc0948ca22b2cece:'+name],cwd=ROOT
                )
                self.assertTrue(current == approved or
                    hashlib.sha256(current).hexdigest() == '1872a26c00630380ca53f7d91b33d26b0f6b7abf156c24e4744c8ef828228e7c')
                continue
            self.assertEqual(current,expected)
    def test_explicit_same_installer_and_original_script(self):
        s=(ROOT/'.github/workflows/release-desktop-021.yml').read_text()
        self.assertIn('-InstallerPath $installers[0].FullName',s)
        self.assertIn('-File scripts/windows-offline-translation-test.ps1',s)
        self.assertIn("-NativeCapturePath '${{ steps.windows_native_candidate.outputs.capturePath }}'",s)
        self.assertIn('if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }',s)
        self.assertNotIn('continue-on-error:',s)
        self.assertIn('npm audit --audit-level=high',s)
        self.assertIn('test_prepare_desktop_release.py',s)
        self.assertIn('test-desktop-release.cjs',s)
        self.assertIn('--expected-version 0.2.21 --installer',s)
        self.assertIn('needs: [build, browser]',s)
        self.assertIn("  browser:\n    if: github.repository == 'Blueeeecho/EchoLingo'",s)
        self.assertIn('tests/macos-header-event-route.swift',s)
    def test_support_does_not_allow_application_or_historical_changes(self):
        self.assertEqual(R.legacy.SUPPORT,{'scripts/prepare-desktop-021.py','scripts/publish-desktop-021.cjs','scripts/test_prepare_desktop_021.py','scripts/test-desktop-021.cjs','.github/workflows/release-desktop-021.yml','docs/releases/0.2.21.zh-CN.md'})

if __name__=='__main__':unittest.main()
