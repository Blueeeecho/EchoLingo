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
import re
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
        self.root=Path(self.tmp.name).resolve(strict=True);self.inputs=self.root/'inputs';self.output=self.root/'out'
        self.reports={}
        for platform,name in [('Windows','EchoLingo_0.2.16_x64-setup.exe'),('macOS','EchoLingo_0.2.16_aarch64.dmg')]:
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
        self.mac={flag:True for flag in R.REQUIRED_MACOS_SMOKE}
        self.mac.update(version=R.VERSION, commit=SHA, tree=TREE, runUrl=RUN,
            installerSha256=self.reports['macOS']['installer']['sha256'],
            applicationSha256=self.reports['macOS']['application']['sha256'],
            fakeIpcUsed=False, userContentRead=False, codexInteractiveSelectionTested=False)
        self.save_mac()
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
    def save_mac(self):
        (self.inputs/'macOS'/'macos-runtime.json').write_text(json.dumps(self.mac))
    def test_mac_runtime_required(self):
        (self.inputs/'macOS'/'macos-runtime.json').unlink()
        with self.assertRaises(ValueError): self.prepare()
        self.assertFalse(self.output.exists())
    def test_mac_runtime_rejections(self):
        bad_values = [(key, False) for key in R.REQUIRED_MACOS_SMOKE]
        bad_values += [(key, True) for key in ('fakeIpcUsed','userContentRead','codexInteractiveSelectionTested')]
        bad_values += [(key, 'wrong') for key in ('version','commit','tree','runUrl','installerSha256','applicationSha256')]
        for key, bad in bad_values:
            for missing in (False,True):
                with self.subTest(key=key, missing=missing):
                    original=copy.deepcopy(self.mac)
                    if missing: del self.mac[key]
                    else: self.mac[key]=bad
                    self.save_mac()
                    with self.assertRaisesRegex(ValueError, 'macOS runtime'): self.prepare()
                    self.assertFalse(self.output.exists())
                    self.mac=original
        self.save_mac()
    def test_mac_runtime_acceptance_preserves_evidence(self):
        result=self.prepare()
        self.assertTrue(result['scope']['macOSRuntimeAcceptance'])
        self.assertEqual(result['macOSRuntimeAcceptance'], self.mac)
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
        path.write_text('{"version":"0.2.16","version":"0.2.16"}')
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



class WorkflowBuildToolTests(unittest.TestCase):
    def test_cargo_has_exact_msvc_linker_even_in_git_bash(self):
        workflow=(R.ROOT/'.github/workflows/release-desktop.yml').read_text(encoding='utf-8')
        self.assertIn("Join-Path $env:VCToolsInstallDir 'bin/HostX64/x64/link.exe'",workflow)
        self.assertIn('Test-Path -LiteralPath $linker -PathType Leaf',workflow)
        self.assertIn('CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER=$linker',workflow)
        self.assertIn('Out-File -FilePath $env:GITHUB_ENV',workflow)
        self.assertLess(workflow.index('Pin the MSVC linker'),workflow.index('Test frontend, actual Rust sources'))
        export='export ECHOLINGO_WORKFLOW_BASH="$(cygpath -w "$BASH")"'
        self.assertIn(export, workflow)
        self.assertLess(workflow.index(export), workflow.index("python -m unittest discover -s scripts -p 'test_prepare_desktop_release.py'"))


class MacRuntimeWorkflowTests(unittest.TestCase):
    def test_native_fixtures_precede_exact_bundle_runtime_gate(self):
        workflow=(R.ROOT/'.github/workflows/release-desktop.yml').read_text(encoding='utf-8')
        start=workflow.index('      - name: Accept extracted Mac bundle')
        end=workflow.index('      - name: Build and accept exact Windows unpack ZIP', start)
        step=workflow[start:end]
        self.assertIn("if: runner.os == 'macOS'", step)
        self.assertIn('set -euo pipefail', step)
        self.assertIn('timeout-minutes: 12', step)
        self.assertLess(step.index('bash tests/macos-native-self-test.sh'), step.index('python3 tests/macos-installed-runtime-smoke.py'))
        self.assertLess(step.index('"$RUNNER_TEMP/desktop-window-size"\n'), step.index('python3 tests/macos-installed-runtime-smoke.py'))
        for arg in ('--installer "${files[0]}"', '--built-application src-tauri/target/release/bundle/macos/EchoLingo.app',
                    '--output "$RUNNER_TEMP/desktop-package/macos-runtime.json"', '--run-url "$RUN_URL"',
                    '--native-self-tests-passed', '--native-window-resize-fixture-passed'):
            self.assertIn(arg, step)
        self.assertLess(end, workflow.index('          name: Desktop-package-${{ runner.os }}'))
        self.assertIn("if: always() && runner.os == 'macOS'", step)
        self.assertIn('name: Mac-runtime-acceptance', step)
        self.assertIn('if-no-files-found: warn', step)


class FixedDesktopRecoveryModeTests(unittest.TestCase):
    def workflow(self):
        return (R.ROOT/'.github/workflows/ci.yml').read_text(encoding='utf-8')
    def run_selector(self, event='pull_request', head='fix/residual-translation-failures',
                     base='main', ref='refs/pull/1/merge', version='0.2.16', check_exit=0):
        import os
        import textwrap
        source=self.workflow()
        selector=source.split('        run: |\n', 1)[1].split('          elif ', 1)[0]
        selector=textwrap.dedent(selector)
        # Execute the exact new branch, replacing only external tools with
        # controlled stand-ins. Older routing is a sentinel rather than a
        # potentially expensive invocation of historical Git/source checks.
        selector+='else\n  echo "mode=full" >> "$GITHUB_OUTPUT"\nfi\n'
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'output'; calls=Path(directory)/'calls'
            environment={**os.environ, 'CI_EVENT':event, 'PR_HEAD':head, 'PR_BASE':base,
                'CI_REF':ref, 'FIXTURE_VERSION':version, 'CHECK_EXIT':str(check_exit),
                'GITHUB_OUTPUT':'output', 'FIXTURE_CALLS':'calls'}
            standins='node() { printf "%s\n" "$FIXTURE_VERSION"; }; python3() { printf "%s\n" "$*" >> "$FIXTURE_CALLS"; return "$CHECK_EXIT"; };\n'
            bash=shutil.which('bash')
            if os.name == 'nt':
                # Windows PATH can resolve System32's WSL launcher. Use the
                # installed Git distribution that also runs Actions bash steps.
                git=shutil.which('git')
                self.assertIsNotNone(git, 'Git for Windows is required by the workflow')
                # Git Bash exposes git.exe under mingw64/bin; ordinary cmd
                # exposes it under cmd or bin. Check the same distribution's
                # ancestors, never System32's unrelated WSL launcher.
                candidates=[parent/relative for parent in list(Path(git).resolve().parents)[:3]
                            for relative in ('bin/bash.exe', 'usr/bin/bash.exe')]
                configured=os.environ.get('ECHOLINGO_WORKFLOW_BASH')
                if configured:
                    self.assertTrue(Path(configured).is_file(), 'Configured workflow Bash must exist')
                    bash=configured
                else:
                    bash=next((str(path) for path in candidates if path.is_file()), None)
            self.assertIsNotNone(bash, 'The workflow Bash executable is required')
            process=subprocess.run([bash,'-e','-c',standins+selector], cwd=directory,
                                   env=environment, capture_output=True, text=True)
            self.assertIn(process.returncode, (0, check_exit),
                          f'Selector shell failed: {process.stderr}')
            return process.returncode, out.read_text() if out.exists() else '', calls.read_text() if calls.exists() else ''
    def test_git_distribution_ancestor_search_covers_native_and_bash_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory).resolve(strict=True)/'Git'
            shell=root/'bin/bash.exe';shell.parent.mkdir(parents=True);shell.touch()
            for relative in ('cmd/git.exe', 'bin/git.exe', 'mingw64/bin/git.exe'):
                git=root/relative;git.parent.mkdir(parents=True, exist_ok=True);git.touch()
                candidates=[parent/path for parent in list(git.resolve().parents)[:3]
                            for path in ('bin/bash.exe', 'usr/bin/bash.exe')]
                found=next((path for path in candidates if path.is_file()), None)
                self.assertEqual(found, shell)
    def test_only_fixed_version_branch_or_main_push_selects_mode(self):
        for arguments in ({}, {'event':'push','head':'','base':'','ref':'refs/heads/main'}):
            with self.subTest(arguments=arguments):
                code, output, calls=self.run_selector(**arguments)
                self.assertEqual(code, 0)
                self.assertEqual(output, 'mode=desktop-recovery\n')
                self.assertEqual(calls, 'scripts/prepare-desktop-release.py --check-source\n')
    def test_other_events_versions_and_branches_do_not_skip_full_suite(self):
        for arguments in ({'event':'workflow_dispatch','ref':'refs/heads/main'},
                {'event':'pull_request_target'}, {'head':'other-branch'}, {'base':'other-base'},
                {'version':'0.2.15'}, {'version':'0.2.17'}, {'version':'0.2.16-beta'},
                {'event':'push','ref':'refs/heads/other'}):
            with self.subTest(arguments=arguments):
                code, output, calls=self.run_selector(**arguments)
                self.assertEqual((code, output, calls), (0, 'mode=full\n', ''))
    def test_failed_source_verification_never_selects_narrow_mode(self):
        code, output, calls=self.run_selector(check_exit=17)
        self.assertEqual(code, 17)
        self.assertEqual(output, '')
        self.assertEqual(calls, 'scripts/prepare-desktop-release.py --check-source\n')
    def test_policy_job_preserves_contracts_and_native_ownership(self):
        source=self.workflow()
        job=source.split('  desktop-recovery-policy:\n',1)[1].split('  automatic-direction-routing:',1)[0]
        self.assertIn("    if: needs.validation-mode.outputs.mode == 'desktop-recovery'", job)
        self.assertIn('    needs: validation-mode',job)
        for command in ('python3 scripts/prepare-desktop-release.py --check-source',
            "python3 -m unittest discover -s tests -p 'test_*.py' -v",
            "python3 -m unittest discover -s scripts -p 'test_*.py' -v",
            'node --test scripts/test-desktop-release.cjs', 'npm run check', 'npm test', 'npm run build',
            'npx playwright install --with-deps chromium', 'node tests/frontend-interactions.mjs'):
            self.assertIn(command,job)
        self.assertNotIn('continue-on-error',job)
        self.assertNotIn('contents: write',job)
        self.assertIn('This job alone is not native acceptance.',job)


class PackageAwareVersionTests(unittest.TestCase):
    def test_production_and_behavioral_fixtures_require_a_new_review_pin(self):
        self.assertEqual(R.REVIEWED_SOURCE, '5d9e883cd292e0722c265155590630f056d09b20')
        for name in ('src/main.ts', 'src-tauri/src/translation_requests.rs',
                     'src-tauri/src/window_layout.rs', 'tests/frontend-interactions.mjs',
                     'tests/test_popup_language_session_contract.py'):
            self.assertNotIn(name, R.SUPPORT)

    def test_released_baseline_is_immutable_and_separate_from_source_pin(self):
        self.assertEqual(R.MANIFEST_BASELINE, 'bd2a42659ad91bb2d3d0792c4650669db336a046')
        self.assertNotEqual(R.MANIFEST_BASELINE, R.REVIEWED_SOURCE)
    def test_same_version_third_party_cargo_entry_is_unchanged(self):
        baseline = 'version = 4\n[[package]]\nname = "echolingo"\nversion = "0.2.15"\n[[package]]\nname = "async-signal"\nversion = "0.2.15"\nsource = "registry+https://github.com/rust-lang/crates.io-index"\nchecksum = "unchanged-checksum"\n'
        current = baseline.replace('name = "echolingo"\nversion = "0.2.15"', 'name = "echolingo"\nversion = "0.2.16"')
        dependency=baseline.split('[[package]]')[2]
        self.assertEqual(current.split('[[package]]')[2], dependency)
        expected=R.expected_version_manifest('src-tauri/Cargo.lock', baseline)
        self.assertEqual(expected['package'][1], R.tomllib.loads(baseline)['package'][1])
        R.check_version_only_manifest('src-tauri/Cargo.lock', baseline, current)
        for modified in (current.replace('name = "async-signal"\nversion = "0.2.15"', 'name = "async-signal"\nversion = "0.2.16"'),
                         current.replace('unchanged-checksum', 'different-checksum'),
                         current.replace('crates.io-index', 'other-index')):
            with self.assertRaisesRegex(ValueError, 'Non-version manifest change'):
                R.check_version_only_manifest('src-tauri/Cargo.lock', baseline, modified)
    def test_npm_dependency_and_unknown_fields_are_not_rewritten(self):
        baseline={'name':'echolingo','version':'0.2.15','custom':'0.2.15','packages':{
            '':{'name':'echolingo','version':'0.2.15'},
            'node_modules/example':{'version':'0.2.15','integrity':'original'}}}
        current=copy.deepcopy(baseline)
        current['version']=current['packages']['']['version']='0.2.16'
        R.check_version_only_manifest('package-lock.json', json.dumps(baseline), json.dumps(current))
        for change in ('dependency','integrity','unknown'):
            bad=copy.deepcopy(current)
            if change=='dependency': bad['packages']['node_modules/example']['version']='0.2.16'
            elif change=='integrity': bad['packages']['node_modules/example']['integrity']='different'
            else: bad['custom']='0.2.16'
            with self.assertRaisesRegex(ValueError, 'Non-version manifest change'):
                R.check_version_only_manifest('package-lock.json', json.dumps(baseline), json.dumps(bad))
    def test_real_baseline_allows_only_project_versions(self):
        for name in R.verifier().VERSION_PATHS:
            with self.subTest(name=name):
                baseline=R.git('show', R.MANIFEST_BASELINE+':'+name)
                R.check_version_only_manifest(name, baseline, (R.ROOT/name).read_text())


class CandidateCliVersionTests(unittest.TestCase):
    def test_both_native_package_clis_accept_release_version_and_reject_unknown(self):
        for name in ('inspect-candidate-package.py', 'verify-candidate-package.py'):
            for version, expected in ((R.VERSION, 0), ('9.9.99', 2)):
                with self.subTest(name=name, version=version):
                    result = subprocess.run([sys.executable, str(R.ROOT/'scripts'/name),
                        '--expected-version', version, '--help'], capture_output=True, text=True)
                    self.assertEqual(result.returncode, expected, result.stderr)


REPOSITORY = "https://github.com/Blueeeecho/EchoLingo"


def current_version():
    return json.loads((R.ROOT / "package.json").read_text(encoding="utf-8"))["version"]


def validate_document(text, version):
    prefix = f"{REPOSITORY}/releases/download/{version}/"
    expected = {prefix + name for name in (
        f"EchoLingo_{version}_windows_x64-unpack.zip",
        f"EchoLingo_{version}_windows_x64-setup.exe",
        f"EchoLingo_{version}_macos_arm64.dmg",
        "SHA256SUMS.txt", "RELEASE-MANIFEST.json",
    )}
    expected |= {f"{REPOSITORY}/releases/tag/{version}", f"{REPOSITORY}/tree/{version}"}
    urls = set(re.findall(r"https://github\.com/Blueeeecho/EchoLingo/[^\s\"'<>)]*", text))
    missing = expected - urls
    if missing:
        raise ValueError("Missing current release links: " + ", ".join(sorted(missing)))
    stale = {url for url in urls if "/releases/download/" in url and not url.startswith(prefix)}
    if stale:
        raise ValueError("Outdated download links: " + ", ".join(sorted(stale)))
    if any("/releases/latest" in url for url in urls):
        raise ValueError("Prerelease downloads must not use the stable Latest endpoint")
    if not any(word in text.lower() for word in ("预发布", "prerelease", "pre-release")):
        raise ValueError("The public download documentation must disclose prerelease status")



class PublicReleaseDocs(unittest.TestCase):
    def document(self):
        version = "0.2.16"
        base = REPOSITORY
        return "Prerelease\n" + "\n".join([
            f"{base}/releases/tag/{version}", f"{base}/tree/{version}",
            *(f"{base}/releases/download/{version}/{name}" for name in (
                f"EchoLingo_{version}_windows_x64-unpack.zip",
                f"EchoLingo_{version}_windows_x64-setup.exe",
                f"EchoLingo_{version}_macos_arm64.dmg",
                "SHA256SUMS.txt", "RELEASE-MANIFEST.json")),
        ])

    def test_current_readmes_match_project_version(self):
        for name in ("README.md", "README.en.md"):
            with self.subTest(name=name):
                validate_document((R.ROOT / name).read_text(encoding="utf-8"), current_version())

    def test_current_links_and_previous_release_notes_are_valid(self):
        validate_document(self.document() + f"\n{REPOSITORY}/releases/tag/0.2.15", "0.2.16")

    def test_a_version_bump_requires_download_documentation_update(self):
        with self.assertRaisesRegex(ValueError, "Missing current release links"):
            validate_document(self.document(), "0.2.17")

    def test_stale_download_is_rejected_even_if_current_download_is_present(self):
        with self.assertRaisesRegex(ValueError, "Outdated download links"):
            validate_document(self.document() + f"\n{REPOSITORY}/releases/download/0.2.15/old.zip", "0.2.16")

    def test_stable_latest_link_cannot_hide_the_prerelease(self):
        with self.assertRaisesRegex(ValueError, "stable Latest"):
            validate_document(self.document() + f"\n{REPOSITORY}/releases/latest", "0.2.16")

    def test_prerelease_label_is_required(self):
        with self.assertRaisesRegex(ValueError, "disclose prerelease"):
            validate_document(self.document().replace("Prerelease", ""), "0.2.16")


class NonBuildDocumentationScopeTests(unittest.TestCase):
    def check_paths(self, names):
        # Execute the real source guard; isolate only Git and manifest I/O.
        def git(*args):
            if args[0] == 'diff': return '\n'.join(names)
            if args[0] == 'show': return 'baseline'
            raise AssertionError(args)
        with patch.object(R, 'git', side_effect=git), \
                patch.object(R.subprocess, 'run'), \
                patch.object(R, 'check_version_only_manifest') as manifests, \
                patch.object(R, 'verifier') as factory:
            factory.return_value.VERSION_PATHS = ['package.json']
            factory.return_value.source_provenance.return_value = {'checked': True}
            result = R.check_source()
            manifests.assert_called_once()
            factory.return_value.check_versions.assert_called_once_with(R.ROOT)
            factory.return_value.source_provenance.assert_called_once_with(R.ROOT)
            return result

    def test_only_exact_readmes_are_non_build_documents(self):
        self.assertEqual(R.NON_BUILD_DOCS, {'README.md', 'README.en.md'})
        self.assertEqual(self.check_paths(['README.md', 'README.en.md']), {'checked': True})

    def test_readme_never_allows_unreviewed_source_or_other_documents(self):
        for name in ('src/main.ts', 'src-tauri/src/main.rs',
                     'src-tauri/src/translation_requests.rs', 'src-tauri/native/macos.swift',
                     'scripts/unknown.py', 'docs/unknown.md', 'README.other.md'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Unexpected post-review changes'):
                self.check_paths(['README.md', name])


if __name__ == '__main__':
    unittest.main()
