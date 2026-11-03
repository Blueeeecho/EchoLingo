"""Synthetic preparer checks; no native execution or release acceptance is implied."""
import copy
import hashlib
import zipfile
import ast
import subprocess
import shutil
import sys
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('desktop_release',Path(__file__).with_name('prepare-desktop-release.py'))
R=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(R)
SHA='a'*40;TREE='b'*40;RUN='https://github.com/Blueeeecho/EchoLingo/actions/runs/123'

class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.inputs=self.root/'inputs';self.output=self.root/'out'
        self.reports={}
        for platform,name in [('Windows','EchoLingo_0.2.14_x64-setup.exe'),('macOS','EchoLingo_0.2.14_aarch64.dmg')]:
            directory=self.inputs/platform;directory.mkdir(parents=True)
            installer=directory/name;installer.write_bytes(b'not-a-native-installer-'+platform.encode())
            app={'name':'echolingo','size':len(b'synthetic-application__TAURI_BUNDLE_TYPE_VAR_NSS'),'sha256':hashlib.sha256(b'synthetic-application__TAURI_BUNDLE_TYPE_VAR_NSS').hexdigest()}
            assertions={'schemaVersion':1,'platform':platform,'version':R.VERSION,'commit':SHA,'tree':TREE,
                'runUrl':RUN,'checks':{name:True for name in R.verifier().CHECK_NAMES},
                'applicationMetadata':{'version':R.VERSION,'architecture':'x64' if platform=='Windows' else 'arm64'},
                'installerSha256':R.identity(installer)['sha256'],'applicationSha256':app['sha256'],'extractedApplicationSha256':app['sha256']}
            report={'version':R.VERSION,'platform':platform,'validationMode':R.verifier().MODE,
                'source':{'commit':SHA,'tree':TREE,'trackedWorktreeClean':True},'runUrl':RUN,
                'installer':R.identity(installer),'application':app,'workflowInspection':{'assertions':assertions},
                'scope':{'buildAndStaticPackageEvidenceOnly':True,**{k:False for k in ('installerExecuted',
                'installedApplicationAcceptance','interactiveSelectionAcceptance','visualAcceptance',
                'performanceAcceptance','releaseAcceptance','historicalInstallerAcceptanceTransferred')}},
                'offlineResourceReuse':None}
            if platform=='Windows':
                source=directory/'EchoLingo-offline-engine-source.zip';source.write_bytes(b'synthetic-source')
                report['offlineResourceReuse']={'sourceArchive':R.identity(source),
                    'currentInstallerAcceptanceTransferred':False,'currentEngineRuntimeExecuted':False}
            self.reports[platform]=report;self.save(platform)
        self.directory=self.inputs/'Windows'
        self.archive=self.directory/f'EchoLingo_{R.VERSION}_windows_x64-unpack.zip'
        self.payload={'echolingo.exe':b'synthetic-application__TAURI_BUNDLE_TYPE_VAR_UNK',
                      'offline-translation/bin/echolingo-offline-engine.exe':b'synthetic-engine'}
        self.manifest={'version':R.VERSION,'commit':SHA,'formatVersion':1,'kind':'windows-unpack',
                       'userDataPortable':False,'webview2':'external-evergreen-runtime-required'}
        self.smoke={flag:True for flag in R.REQUIRED_SMOKE}
        self.smoke.update(version=R.VERSION,interactiveCaptureTested=False,networkIsolationTested=False,
                          captureSha256='c'*64)
        self.rebuild_zip()
        self.settings={'ok':True,'actualSettingsUiTested':True,'fakeIpcUsed':False,
                       'userContentRead':False,'applicationSha256':self.smoke['applicationSha256']}
        self.focus={'ok':True,'generatedSourceOnly':True,'expectCrossProcessSuccess':True,
                    'passedCases':2,'executedCases':2,'userContentRead':False,
                    'actualApplicationTested':False,'nativeAssemblySha256':'d'*64}
        self.save_acceptance()
        self.p=patch.object(R,'check_source',return_value={'commit':SHA,'tree':TREE,'trackedWorktreeClean':True});self.p.start();self.addCleanup(self.p.stop)
    def save(self,platform):
        (self.inputs/platform/'candidate.json').write_text(json.dumps(self.reports[platform]))
    def prepare(self):
        return R.prepare(self.inputs,self.output,RUN)
    def test_exact_seven_files_and_scope(self):
        result=self.prepare()
        self.assertEqual(len(list(self.output.iterdir())),7)
        self.assertFalse(result['scope']['installerExecuted'])
        self.assertFalse(result['scope']['fullRegression'])
        self.assertEqual(len((self.output/'SHA256SUMS.txt').read_text().splitlines()),6)
    def test_no_overwrite(self):
        self.prepare()
        with self.assertRaises(ValueError):self.prepare()
    def test_wrong_commit(self):
        self.reports['Windows']['source']['commit']='d'*40;self.save('Windows')
        with self.assertRaises(ValueError):self.prepare()
    def test_modified_installer(self):
        (self.inputs/'Windows'/self.reports['Windows']['installer']['name']).write_bytes(b'changed')
        with self.assertRaises(ValueError):self.prepare()
    def test_modified_source(self):
        (self.inputs/'Windows'/'EchoLingo-offline-engine-source.zip').write_bytes(b'changed')
        with self.assertRaises(ValueError):self.prepare()
    def test_failed_focused_tests(self):
        self.reports['macOS']['workflowInspection']['assertions']['checks']['focusedTestsPassed']=False;self.save('macOS')
        with self.assertRaises(ValueError):self.prepare()
    def test_overstated_runtime(self):
        self.reports['Windows']['scope']['installerExecuted']=True;self.save('Windows')
        with self.assertRaises(ValueError):self.prepare()
    def test_historical_acceptance_not_transferred(self):
        self.reports['Windows']['offlineResourceReuse']['currentInstallerAcceptanceTransferred']=True;self.save('Windows')
        with self.assertRaises(ValueError):self.prepare()
    def test_wrong_run(self):
        self.reports['macOS']['runUrl']=RUN+'4';self.save('macOS')
        with self.assertRaises(ValueError):self.prepare()
    def test_path_traversal(self):
        self.reports['macOS']['installer']['name']='../evil';self.save('macOS')
        with self.assertRaises(ValueError):self.prepare()
    def save_acceptance(self):
        for filename,report in [('windows-settings.json',self.settings),('windows-native-focus.json',self.focus)]:
            (self.directory/filename).write_text(json.dumps(report),encoding='utf-8')
    def test_missing_acceptance_reports(self):
        for filename in ('windows-settings.json','windows-native-focus.json'):
            with self.subTest(filename=filename):
                self.save_acceptance();(self.directory/filename).unlink()
                with self.assertRaises(ValueError): self.prepare()
                self.assertFalse(self.output.exists())
    def test_settings_evidence_rejections(self):
        for field,bad in [('ok',False),('actualSettingsUiTested',False),('fakeIpcUsed',True),
                          ('userContentRead',True),('applicationSha256','f'*64)]:
            for missing in (False,True):
                with self.subTest(field=field,missing=missing):
                    original=copy.deepcopy(self.settings)
                    if missing: del self.settings[field]
                    else: self.settings[field]=bad
                    self.save_acceptance()
                    with self.assertRaisesRegex(ValueError,'settings evidence'): self.prepare()
                    self.assertFalse(self.output.exists());self.settings=original
    def test_focus_evidence_rejections(self):
        for field,bad in [('ok',False),('generatedSourceOnly',False),('expectCrossProcessSuccess',False),
                          ('passedCases',1),('executedCases',3),('userContentRead',True),
                          ('actualApplicationTested',True),('nativeAssemblySha256','invalid')]:
            for missing in (False,True):
                with self.subTest(field=field,missing=missing):
                    original=copy.deepcopy(self.focus)
                    if missing: del self.focus[field]
                    else: self.focus[field]=bad
                    self.save_acceptance()
                    with self.assertRaisesRegex(ValueError,'native focus evidence'): self.prepare()
                    self.assertFalse(self.output.exists());self.focus=original
    def test_acceptance_manifest_is_bounded_and_hash_bound(self):
        result=self.prepare()
        settings=result['windowsSettingsAcceptance'];focus=result['windowsGeneratedFocusAcceptance']
        self.assertTrue(settings['actualSettingsUiTested']);self.assertFalse(settings['fakeIpcUsed'])
        self.assertEqual(settings['applicationSha256'],self.smoke['applicationSha256'])
        self.assertTrue(focus['generatedSourceOnly']);self.assertFalse(focus['actualApplicationTested'])
        self.assertEqual(focus['passedCases'],2)
        self.assertEqual(settings['evidence'],R.identity(self.directory/'windows-settings.json'))
        self.assertEqual(focus['evidence'],R.identity(self.directory/'windows-native-focus.json'))
    def save_zip_metadata(self):
        (self.directory/'WINDOWS-ZIP-MANIFEST.json').write_text(json.dumps(self.manifest),encoding='utf-8')
        (self.directory/'windows-unpack-smoke.json').write_text(json.dumps(self.smoke),encoding='utf-8')
    def rebuild_zip(self, symlink=None):
        with zipfile.ZipFile(self.archive,'w') as bundle:
            for name,data in self.payload.items():
                info=zipfile.ZipInfo(name)
                if name==symlink: info.create_system=3;info.external_attr=0o120777<<16
                bundle.writestr(info,data)
        self.manifest['files']=[{'path':name,'size':len(data),'sha256':hashlib.sha256(data).hexdigest()}
                                for name,data in self.payload.items()]
        self.manifest['archives']=[R.identity(self.archive),R.identity(self.directory/'EchoLingo-offline-engine-source.zip')]
        self.smoke['archiveSha256']=R.identity(self.archive)['sha256']
        self.smoke['applicationSha256']=hashlib.sha256(self.payload.get('echolingo.exe',b'')).hexdigest()
        self.smoke['engineSha256']=hashlib.sha256(self.payload.get('offline-translation/bin/echolingo-offline-engine.exe',b'')).hexdigest()
        self.save_zip_metadata()
    def reject_zip(self):
        self.save_zip_metadata()
        with self.assertRaises((ValueError,KeyError)): self.prepare()
        self.assertFalse(self.output.exists())
    def test_placeholder_fails_closed(self):
        self.p.stop()
        with patch.object(R,'REVIEWED_SOURCE','PENDING_FINAL_VERIFIED_INTEGRATION'):
            with self.assertRaisesRegex(ValueError,'pinned'): R.check_source()
    def test_invalid_run_url(self):
        with self.assertRaises(ValueError): R.prepare(self.inputs,self.output,'https://example.com/runs/123')
    def test_each_runtime_flag_required(self):
        for flag in R.REQUIRED_SMOKE:
            for value in (False,None,1,'true'):
                with self.subTest(flag=flag,value=value):
                    self.smoke[flag]=value;self.reject_zip()
            self.smoke[flag]=True
    def test_runtime_scope_and_identities(self):
        for field,value in [('version','0.2.13'),('archiveSha256','f'*64),
                            ('applicationSha256','f'*64),('engineSha256','f'*64),
                            ('captureSha256','not-a-hash'),('cleanupComplete',False),
                            ('interactiveCaptureTested',True),('networkIsolationTested',True)]:
            with self.subTest(field=field):
                original=copy.deepcopy(self.smoke);self.smoke[field]=value;self.reject_zip();self.smoke=original
    def test_manifest_scope_and_source(self):
        for field,value in [('commit','f'*40),('version','0.2.13'),('kind','other'),
                            ('formatVersion',2),('userDataPortable',True),('webview2','bundled')]:
            with self.subTest(field=field):
                original=copy.deepcopy(self.manifest);self.manifest[field]=value;self.reject_zip();self.manifest=original
    def test_archive_identity(self):
        self.manifest['archives'][0]['sha256']='f'*64;self.reject_zip()
    def test_source_archive_identity(self):
        self.manifest['archives'][1]['sha256']='f'*64;self.reject_zip()
    def test_member_hash(self):
        self.manifest['files'][0]['sha256']='f'*64;self.reject_zip()
    def test_member_size(self):
        self.manifest['files'][0]['size']+=1;self.reject_zip()
    def test_missing_manifest_member(self):
        self.manifest['files'].pop();self.reject_zip()
    def test_extra_manifest_member(self):
        self.manifest['files'].append({'path':'extra','size':1,'sha256':'f'*64});self.reject_zip()
    def test_case_aliased_members(self):
        self.payload['ECHOLINGO.EXE']=b'alias';self.rebuild_zip();self.reject_zip()
    def test_traversal_member(self):
        self.payload['../escape']=b'escape';self.rebuild_zip();self.reject_zip()
    def test_absolute_member(self):
        self.payload['/escape']=b'escape';self.rebuild_zip();self.reject_zip()
    def test_symlink_member(self):
        self.payload['link']=b'echolingo.exe';self.rebuild_zip(symlink='link');self.reject_zip()
    def test_empty_member(self):
        self.payload['empty']=b'';self.rebuild_zip();self.reject_zip()
    def test_duplicate_json_field(self):
        path=self.directory/'WINDOWS-ZIP-MANIFEST.json'
        path.write_text('{"version":"0.2.14","version":"0.2.14"}')
        with self.assertRaises(ValueError): self.prepare()
    def test_candidate_tree_and_assertion_provenance(self):
        self.reports['Windows']['workflowInspection']['assertions']['tree']='f'*40;self.save('Windows')
        with self.assertRaises(ValueError): self.prepare()

    def test_missing_executed_application_and_engine(self):
        self.payload={'README.txt':b'no executable'};self.rebuild_zip()
        del self.smoke['applicationSha256'];del self.smoke['engineSha256']
        self.reject_zip()
    def test_zip_application_differs_from_installer_application(self):
        self.payload['echolingo.exe']=b'different app__TAURI_BUNDLE_TYPE_VAR_UNK';self.rebuild_zip()
        self.reject_zip()

    def test_missing_tauri_bundle_marker(self):
        self.payload['echolingo.exe']=b'app-without-marker';self.rebuild_zip();self.reject_zip()
    def test_duplicate_tauri_bundle_marker(self):
        self.payload['echolingo.exe']=b'__TAURI_BUNDLE_TYPE_VAR_UNK'*2;self.rebuild_zip();self.reject_zip()
    def test_missing_capture_identity(self):
        del self.smoke['captureSha256'];self.reject_zip()
    def test_missing_required_application_hash(self):
        del self.smoke['applicationSha256'];self.reject_zip()
    def test_missing_required_engine_hash(self):
        del self.smoke['engineSha256'];self.reject_zip()

if __name__=='__main__': unittest.main()
