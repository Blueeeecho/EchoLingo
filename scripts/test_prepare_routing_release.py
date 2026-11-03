"""Synthetic preparer checks; no native execution or release acceptance is implied."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('routing_release',Path(__file__).with_name('prepare-routing-release.py'))
R=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(R)
SHA='a'*40;TREE='b'*40;RUN='https://github.com/Blueeeecho/EchoLingo/actions/runs/123'

class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.inputs=self.root/'inputs';self.output=self.root/'out'
        self.reports={}
        for platform,name in [('Windows','EchoLingo_0.2.13_x64-setup.exe'),('macOS','EchoLingo_0.2.13_aarch64.dmg')]:
            directory=self.inputs/platform;directory.mkdir(parents=True)
            installer=directory/name;installer.write_bytes(b'not-a-native-installer-'+platform.encode())
            app={'name':'echolingo','size':1,'sha256':'c'*64}
            assertions={'schemaVersion':1,'platform':platform,'version':R.VERSION,'commit':SHA,'tree':TREE,
                'runUrl':RUN,'checks':{name:True for name in R.module().CHECK_NAMES},
                'applicationMetadata':{'version':R.VERSION,'architecture':'x64' if platform=='Windows' else 'arm64'},
                'installerSha256':R.digest(installer),'applicationSha256':app['sha256'],'extractedApplicationSha256':app['sha256']}
            report={'version':R.VERSION,'platform':platform,'validationMode':R.module().MODE,
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
        self.p=patch.object(R,'check_source',return_value={'commit':SHA,'tree':TREE,'trackedWorktreeClean':True});self.p.start();self.addCleanup(self.p.stop)
    def save(self,platform):
        (self.inputs/platform/'candidate.json').write_text(json.dumps(self.reports[platform]))
    def prepare(self):
        return R.prepare(self.inputs,self.output,RUN)
    def test_exact_five_files_and_scope(self):
        result=self.prepare()
        self.assertEqual(len(list(self.output.iterdir())),5)
        self.assertFalse(result['scope']['installerExecuted'])
        self.assertFalse(result['scope']['fullRegression'])
        self.assertEqual(len((self.output/'SHA256SUMS.txt').read_text().splitlines()),4)
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
    def test_placeholder_fails_closed(self):
        self.p.stop()
        with patch.object(R,'REVIEWED_SOURCE','REPLACE_WITH_FINAL_VERIFIED_ROUTING_COMMIT'):
            with self.assertRaisesRegex(ValueError,'final verified'):R.check_source()
    def test_ci_select_requires_successful_guard(self):
        self.assertEqual(R.select_ci(),'routing-release')
        with patch.object(R,'check_source',side_effect=ValueError('unreviewed source')):
            self.assertEqual(R.select_ci(),'full')
    def test_production_paths_are_not_release_support(self):
        for name in ['src-tauri/src/main.rs','src-tauri/native/macos.swift',
                     'src-tauri/src/language_detection.rs','src/main.ts',
                     'resources/offline-translation/manifest.json']:
            self.assertNotIn(name,R.SUPPORT)
    def test_reviewed_source_pin_is_exact(self):
        self.assertEqual(R.REVIEWED_SOURCE,'6809ba1c3c2add353cddfcba89338eadc088ca9a')
    def test_trigger_and_ci_scope_contract(self):
        old=(R.ROOT/'.github/workflows/release.yml').read_text().split('permissions:')[0]
        self.assertIn('workflow_dispatch:',old)
        self.assertNotIn('  push:',old)
        new=(R.ROOT/'.github/workflows/release-routing.yml').read_text()
        self.assertIn('branches: [main]',new)
        self.assertIn('paths: [package.json, .github/workflows/release-routing.yml]',new)
        ci=(R.ROOT/'.github/workflows/ci.yml').read_text()
        self.assertIn('scripts/prepare-routing-release.py --select-ci',ci)
        self.assertIn('[ "$CI_EVENT" = push ]',ci)
        self.assertIn('[ "$CI_EVENT" = pull_request ]',ci)
        self.assertEqual(ci.count("if: needs.validation-mode.outputs.mode != 'language-routing-patch-v1'"),6)
        self.assertEqual(ci.count("&& needs.validation-mode.outputs.mode != 'routing-release'"),6)
    def test_all_eight_versions(self):
        self.assertEqual(len(R.module().check_versions(R.ROOT)),7)

if __name__=='__main__':unittest.main()
