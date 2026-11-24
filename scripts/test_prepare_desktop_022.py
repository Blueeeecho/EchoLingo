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
R=load('release022','prepare-desktop-022.py')
H=load('historical_fixtures','test_prepare_desktop_release.py')

class InstalledPreparation(unittest.TestCase):
    def setUp(self):
        self.old=H.R;H.R=R.legacy;self.addCleanup(setattr,H,'R',self.old)
        self.f=H.PreparationTests(methodName='runTest');self.f.setUp();self.addCleanup(self.f.doCleanups)
        for platform in ('Windows','macOS'):
            c=self.f.reports[platform];old=self.f.inputs/platform/c['installer']['name']
            new=old.with_name(old.name.replace('0.2.18','0.2.22'));old.rename(new)
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
        for name in ('scripts/prepare-desktop-release.py','scripts/publish-desktop-release.cjs','scripts/test-desktop-release.cjs','scripts/test_prepare_desktop_release.py','.github/workflows/release-desktop.yml','.github/workflows/ci.yml','scripts/windows-offline-translation-test.ps1','.github/workflows/release-desktop-021.yml','scripts/prepare-desktop-021.py','scripts/publish-desktop-021.cjs','scripts/test_prepare_desktop_021.py','scripts/test-desktop-021.cjs'):
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
            if name == 'scripts/test_prepare_desktop_021.py' and current != expected:
                # Exact 0.2.21 test update for the reviewed README fixture; no other variant.
                self.assertIn(hashlib.sha256(current).hexdigest(), (
                    '419138ab3ce0ce0c335d0bbec20b3342f30eca870d59934fe8030206df611188',
                    '00a392296b8523a244a418f38370cb3a23de705d269eb55126916de2df9317bd',
                ))
                continue
            self.assertEqual(current,expected)
    def test_explicit_same_installer_and_original_script(self):
        s=(ROOT/'.github/workflows/release-desktop-022.yml').read_text()
        self.assertIn('-InstallerPath $installers[0].FullName',s)
        self.assertIn('-File scripts/windows-offline-translation-test.ps1',s)
        self.assertIn("-NativeCapturePath '${{ steps.windows_native_candidate.outputs.capturePath }}'",s)
        self.assertIn('if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }',s)
        self.assertNotIn('continue-on-error:',s)
        self.assertIn('npm audit --audit-level=high',s)
        self.assertIn('test_prepare_desktop_release.py',s)
        self.assertIn('test-desktop-release.cjs',s)
        self.assertIn('--expected-version 0.2.22 --installer',s)
        self.assertIn('needs: [build, browser]',s)
        self.assertIn("  browser:\n    if: github.repository == 'Blueeeecho/EchoLingo'",s)
        self.assertIn('tests/macos-header-event-route.swift',s)
    def test_support_does_not_allow_application_or_historical_changes(self):
        self.assertEqual(R.legacy.SUPPORT,{'scripts/prepare-desktop-022.py','scripts/publish-desktop-022.cjs','scripts/test_prepare_desktop_022.py','scripts/test-desktop-022.cjs','.github/workflows/release-desktop-022.yml','docs/releases/0.2.22.zh-CN.md'})

class VersionCLIContracts(unittest.TestCase):
    def test_helpers_are_only_additive_relative_to_previous_public_sources(self):
        for path in ('scripts/inspect-candidate-package.py',
                     'scripts/verify-candidate-package.py',
                     'tests/macos-installed-runtime-smoke.py'):
            with self.subTest(path=path):
                before=subprocess.check_output(['git','show',R.legacy.MANIFEST_BASELINE+':'+path],cwd=ROOT)
                old=b'"0.2.21"), default=VERSION)'
                self.assertEqual(before.count(old),1)
                # Keep the original 0.2.22 assertion exact on its released bytes.
                released=subprocess.check_output(['git','show','c29c15bbcc60ec1c9f4aa0576c896469f8e3b9e7:'+path],cwd=ROOT)
                self.assertEqual(released,before.replace(old,b'"0.2.21", "0.2.22"), default=VERSION)',1))
                # Live source permits only the exact reviewed additions, in order.
                tail22=b'"0.2.22"), default=VERSION)'
                self.assertEqual(released.count(tail22),1)
                with23=released.replace(tail22,b'"0.2.22", "0.2.23"), default=VERSION)',1)
                tail23=b'"0.2.23"), default=VERSION)'
                self.assertEqual(with23.count(tail23),1)
                with24=with23.replace(tail23,b'"0.2.23", "0.2.24"), default=VERSION)',1)
                tail24=b'"0.2.24"), default=VERSION)'
                self.assertEqual(with24.count(tail24),1)
                with25=with24.replace(tail24,b'"0.2.24", "0.2.25"), default=VERSION)',1)
                tail25=b'"0.2.25"), default=VERSION)'
                self.assertEqual(with25.count(tail25),1)
                with26=with25.replace(tail25,b'"0.2.25", "0.2.26"), default=VERSION)',1)
                tail26=b'"0.2.26"), default=VERSION)'
                self.assertEqual(with26.count(tail26),1)
                with27=with26.replace(tail26,b'"0.2.26", "0.2.27"), default=VERSION)',1)
                current=(ROOT/path).read_bytes().replace(b'\r\n',b'\n')
                self.assertIn(current,(released,with23,with24,with25,with26,with27))

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
                for version in ('0.2.21','0.2.22','0.2.999'):
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
