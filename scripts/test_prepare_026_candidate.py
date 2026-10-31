"""Synthetic pinned-candidate preparation only; no native or installed acceptance."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

HERE = Path(__file__).resolve().parent

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

PREP = load('prepare026', HERE / 'prepare-026-candidate.py')
FIX = load('candidate026_fixture_helpers', HERE / 'test_candidate_package.py')
VERIFY = PREP.VERIFY

def sha(data):
    return hashlib.sha256(data).hexdigest()

class PrepareCandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve(strict=True)
        self.root = self.base / 'source'; self.root.mkdir()
        for name in VERIFY.VERSION_PATHS:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((PREP.ROOT / name).read_bytes())
        self.git('init', '-q'); self.git('config', 'user.name', 'Synthetic fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('add', '.'); self.git('commit', '-qm', 'synthetic versions')
        self.commit = self.git('rev-parse', 'HEAD'); self.tree = self.git('rev-parse', 'HEAD^{tree}')
        windows_identity = {**PREP.WINDOWS_APPLICATION_IDENTITY, 'packagedSha256': sha(bytes(FIX.pe())),
                            'expectedNsisSha256': sha(bytes(FIX.pe()))}
        constants = patch.multiple(PREP, SOURCE=self.commit, SOURCE_TREE=self.tree,
                                   MAC_INSTALLER_SHA=sha(FIX.dmg()), MAC_APPLICATION_SHA=sha(FIX.macho()),
                                   WINDOWS_INSTALLER_SHA=sha(bytes(FIX.pe(0x14c))), WINDOWS_APPLICATION_SHA=sha(bytes(FIX.pe())),
                                   WINDOWS_APPLICATION_IDENTITY=windows_identity)
        constants.start(); self.addCleanup(constants.stop)
        self.archives = self.base / 'archives'; self.archives.mkdir()
        self.output = self.base / 'output'
        self.offline_bytes = b'synthetic corresponding source; not a real package'
        self.pins = {'SOURCE': {'size': len(self.offline_bytes), 'sha256': sha(self.offline_bytes)},
                     'ENGINE': {'size': 42, 'sha256': 'e' * 64}, 'BASELINE_COMMIT': 'b' * 40,
                     'BASELINE_TREE': 'c' * 40, 'BASELINE_RUN': 123}
        pin_mock = patch.object(PREP, 'pinned_offline', return_value=self.pins)
        pin_mock.start(); self.addCleanup(pin_mock.stop)
        self.evidence = {'schemaVersion': 1, 'ready': True, 'version': '0.2.6',
                         'repository': PREP.REPOSITORY, 'repositoryId': 1432139657,
                         'sourceCommit': self.commit, 'sourceTree': self.tree, 'runId': PREP.RUN,
                         'sourceBranch': 'fix/025-macos-recovery-integration',
                         'jobs': [{'id': index + 1, 'name': name} for index, name in enumerate(sorted(PREP.JOB_NAMES))], 'artifacts': [],
                         'macOSReinspection': {
                             'runId': 999, 'commit': '1' * 40, 'tree': '2' * 40,
                             'branch': 'verify/026-macos-package', 'workflowPath': '.github/workflows/reinspect-026-macos-package.yml',
                             'job': {'id': 888, 'name': PREP.INSPECTION_JOB}, 'allowedChanges': copy.deepcopy(PREP.INSPECTION_CHANGES),
                             'inputArtifact': copy.deepcopy(PREP.INPUT_ARTIFACT), 'installerSha256': PREP.MAC_INSTALLER_SHA,
                             'applicationSha256': PREP.MAC_APPLICATION_SHA, 'licenseSha256': PREP.LICENSE_SHA}}
        self.evidence['windowsReinspection'] = {
            'runId': 998, 'commit': '3' * 40, 'tree': '4' * 40,
            'branch': 'verify/026-windows-package', 'workflowPath': '.github/workflows/diagnose-026-windows-package.yml',
            'job': {'id': 887, 'name': PREP.WINDOWS_INSPECTION_JOB}, 'allowedChanges': copy.deepcopy(PREP.WINDOWS_INSPECTION_CHANGES),
            'inputArtifact': copy.deepcopy(PREP.WINDOWS_INPUT_ARTIFACT), 'installerSha256': PREP.WINDOWS_INSTALLER_SHA,
            'applicationSha256': PREP.WINDOWS_APPLICATION_SHA, 'applicationIdentity': copy.deepcopy(PREP.WINDOWS_APPLICATION_IDENTITY)}
        self.reinspection = {'schemaVersion': 1, 'sourceCommit': self.commit, 'sourceTree': self.tree,
                             'buildRunUrl': PREP.run_url(PREP.RUN), 'inspectionRunUrl': PREP.run_url(999),
                             'inspectionCommit': '1' * 40, 'inputArtifact': copy.deepcopy(PREP.INPUT_ARTIFACT),
                             'installerSha256': PREP.MAC_INSTALLER_SHA, 'applicationSha256': PREP.MAC_APPLICATION_SHA,
                             'productRebuilt': False, 'binaryModified': False, 'installedAcceptance': False,
                             'originalInspectionOutcome': 'failure'}
        self.windows_reinspection = {
            **self.reinspection, 'inspectionRunUrl': PREP.run_url(998), 'inspectionCommit': '3' * 40,
            'inputArtifact': copy.deepcopy(PREP.WINDOWS_INPUT_ARTIFACT), 'installerSha256': PREP.WINDOWS_INSTALLER_SHA,
            'applicationSha256': PREP.WINDOWS_APPLICATION_SHA, 'applicationIdentity': copy.deepcopy(PREP.WINDOWS_APPLICATION_IDENTITY)}
        self.members = {}; self.manifests = {}
        for index, platform in enumerate(('Windows', 'macOS')):
            artifact = {'platform': platform, 'id': index + 10,
                        'name': 'EchoLingo-0.2.6-candidate-' + platform + '-reinspected',
                        'size': 1, 'sha256': 'a' * 64,
                        'installer': 'EchoLingo_0.2.6_x64-setup.exe' if platform == 'Windows' else 'EchoLingo_0.2.6_aarch64.dmg'}
            installer_bytes = bytes(FIX.pe(0x14c)) if platform == 'Windows' else FIX.dmg()
            app_bytes = bytes(FIX.pe()) if platform == 'Windows' else FIX.macho()
            identity = lambda name, content: {'name': name, 'size': len(content), 'sha256': sha(content)}
            installer = identity(artifact['installer'], installer_bytes)
            application = identity('echolingo.exe' if platform == 'Windows' else 'echolingo', app_bytes)
            run_url = PREP.run_url(998 if platform == 'Windows' else 999)
            assertions = {'schemaVersion': 1, 'platform': platform, 'version': '0.2.6', 'commit': self.commit,
                          'tree': self.tree, 'runUrl': run_url, 'checks': {name: True for name in VERIFY.CHECK_NAMES},
                          'applicationMetadata': {'version': '0.2.6', 'architecture': 'x64' if platform == 'Windows' else 'arm64'},
                          'installerSha256': installer['sha256'], 'applicationSha256': application['sha256'],
                          'extractedApplicationSha256': application['sha256']}
            offline = None
            if platform == 'Windows':
                offline = {'scope': 'unchanged offline engine/models/notices/corresponding-source only',
                           'baselineCommit': self.pins['BASELINE_COMMIT'], 'baselineTree': self.pins['BASELINE_TREE'],
                           'baselineRunId': self.pins['BASELINE_RUN'], 'stagingManifest': identity('baseline-reuse.json', b'synthetic'),
                           'sourceArchive': identity(PREP.OFFLINE, self.offline_bytes), 'engine': self.pins['ENGINE'],
                           'runtimeFilesVerified': 5, 'historicalReportBytesPinned': True,
                           'currentInstallerAcceptanceTransferred': False, 'currentEngineRuntimeExecuted': False}
            manifest = {'schemaVersion': 1, 'validationMode': VERIFY.MODE, 'version': '0.2.6', 'platform': platform,
                        'architecture': 'x64' if platform == 'Windows' else 'arm64',
                        'source': {'commit': self.commit, 'tree': self.tree, 'trackedWorktreeClean': True}, 'runUrl': run_url,
                        'versionManifests': VERIFY.check_versions(self.root), 'installer': installer, 'application': application,
                        'formatHeaders': {'installer': 'PE-x86-installer-stub' if platform == 'Windows' else 'UDIF-header',
                                          'application': 'PE-x64' if platform == 'Windows' else 'Mach-O-arm64-header'},
                        'workflowInspection': {'evidence': identity('checks.json', json.dumps(assertions).encode()), 'assertions': assertions},
                        'offlineResourceReuse': offline, 'scope': copy.deepcopy(PREP.SCOPE)}
            self.evidence['artifacts'].append(artifact)
            self.members[platform] = {artifact['installer']: installer_bytes}
            if platform == 'Windows': self.members[platform][PREP.OFFLINE] = self.offline_bytes
            self.manifests[platform] = manifest
            self.write_archive(platform)

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()

    def write_archive(self, platform, manifest_bytes=None, member_changes=None, checksum=None, extra=None, reinspection_bytes=None):
        artifact = next(a for a in self.evidence['artifacts'] if a['platform'] == platform)
        members = dict(self.members[platform])
        members[PREP.MANIFEST] = manifest_bytes or (json.dumps(self.manifests[platform], indent=3) + '\n').encode()
        if member_changes: members.update(member_changes)
        members[PREP.MANIFEST + '.sha256'] = checksum if checksum is not None else ''.join(f'{sha(data)}  {name}\n' for name, data in members.items()).encode()
        # The reinspection helper adds this AFTER producing the unchanged original
        # candidate checksum inventory. It is pinned by the containing ZIP instead.
        if platform == 'macOS':
            members[PREP.REINSPECTION] = reinspection_bytes if reinspection_bytes is not None else (json.dumps(self.reinspection, indent=2) + '\n').encode()
        else:
            members[PREP.WINDOWS_REINSPECTION] = reinspection_bytes if reinspection_bytes is not None else (json.dumps(self.windows_reinspection, indent=2) + '\n').encode()
        path = self.archives / (artifact['name'] + '.zip')
        with zipfile.ZipFile(path, 'w') as archive:
            for name, data in members.items(): archive.writestr(name, data)
            if extra is not None: archive.writestr(*extra)
        artifact['size'] = path.stat().st_size; artifact['sha256'] = VERIFY.sha256(path)
        return path

    def prepare(self, evidence=None):
        return PREP.prepare(self.archives, self.output, self.commit, self.root, evidence or self.evidence)

    def test_preserves_original_bytes_exact_inventory_and_narrow_scope(self):
        result = self.prepare()
        names = {a['installer'] for a in self.evidence['artifacts']} | {PREP.OFFLINE, 'CANDIDATE-MANIFEST.Windows.json', 'CANDIDATE-MANIFEST.macOS.json', PREP.REINSPECTION, PREP.WINDOWS_REINSPECTION, 'RELEASE-MANIFEST.json', 'SHA256SUMS.txt'}
        self.assertEqual({p.name for p in self.output.iterdir()}, names)
        for platform in ('Windows', 'macOS'):
            expected = (json.dumps(self.manifests[platform], indent=3) + '\n').encode()
            self.assertEqual((self.output / f'CANDIDATE-MANIFEST.{platform}.json').read_bytes(), expected)
        self.assertEqual(result['scope'], PREP.SCOPE)
        self.assertEqual(len(names), 9)
        self.assertEqual((self.output / PREP.REINSPECTION).read_bytes(), (json.dumps(self.reinspection, indent=2) + '\n').encode())
        self.assertEqual((self.output / PREP.WINDOWS_REINSPECTION).read_bytes(), (json.dumps(self.windows_reinspection, indent=2) + '\n').encode())
        self.assertEqual(result['validationRun'], PREP.run_url(PREP.RUN))
        self.assertEqual(result['buildRunConclusion'], 'failure')
        self.assertEqual(result['originalMacOSInspectionConclusion'], 'failure')
        self.assertEqual(result['reinspectionRunUrl'], PREP.run_url(999))
        self.assertEqual(result['reinspectionCommit'], '1' * 40)
        self.assertEqual(result['reinspectionRunConclusion'], 'success')
        self.assertEqual(result['windowsReinspectionRunUrl'], PREP.run_url(998))
        self.assertEqual(result['windowsReinspectionCommit'], '3' * 40)
        self.assertEqual(result['windowsReinspectionRunConclusion'], 'success')
        self.assertEqual(result['originalWindowsInspectionConclusion'], 'failure')
        self.assertIs(result['productRebuilt'], False)
        self.assertIs(result['binaryModified'], False)
        self.assertIs(result['rebuiltAfterValidation'], False)
        self.assertIs(result['installedApplicationAcceptance'], False)
        self.assertEqual(len(result['versionManifests']), 7)
        for line in (self.output / 'SHA256SUMS.txt').read_text().splitlines():
            digest, name = line.split('  '); self.assertEqual(digest, VERIFY.sha256(self.output / name))

    def test_incomplete_or_repurposed_evidence_is_rejected_before_output(self):
        for key, value in [('ready', False), ('ready', 1), ('sourceCommit', 'd' * 40), ('sourceTree', 'f' * 40), ('runId', 42), ('version', '0.2.4'), ('repositoryId', 1), ('sourceBranch', 'main'), ('jobs', [])]:
            changed = copy.deepcopy(self.evidence); changed[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError): self.prepare(changed)
        self.assertFalse(self.output.exists())

    def test_original_archive_digest_and_size_are_pinned(self):
        artifact = self.evidence['artifacts'][0]
        path = self.archives / (artifact['name'] + '.zip')
        path.write_bytes(path.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'ZIP pin'): self.prepare()

    def test_reinspection_requires_complete_exact_original_byte_and_tooling_pins(self):
        for key, value in [('runId', None), ('runId', PREP.RUN), ('commit', PREP.SOURCE), ('tree', None),
                           ('branch', 'main'), ('job', {'id': True, 'name': PREP.INSPECTION_JOB}),
                           ('allowedChanges', []), ('installerSha256', 'f' * 64), ('applicationSha256', 'f' * 64),
                           ('licenseSha256', 'f' * 64), ('inputArtifact', {**PREP.INPUT_ARTIFACT, 'id': 42})]:
            changed = copy.deepcopy(self.evidence); changed['macOSReinspection'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.prepare(changed)
        self.assertFalse(self.output.exists())

    def test_windows_reinspection_requires_exact_original_marker_identity(self):
        for key, value in [('runId', None), ('runId', 999), ('branch', 'main'), ('allowedChanges', []),
                           ('applicationSha256', 'f' * 64), ('inputArtifact', {**PREP.WINDOWS_INPUT_ARTIFACT, 'id': 42}),
                           ('applicationIdentity', {**PREP.WINDOWS_APPLICATION_IDENTITY, 'changedBytes': 4}),
                           ('applicationIdentity', {**PREP.WINDOWS_APPLICATION_IDENTITY, 'actualExecutablesModified': 0}),
                           ('applicationIdentity', {**PREP.WINDOWS_APPLICATION_IDENTITY, 'packagedMarker': '__TAURI_BUNDLE_TYPE_VAR_UNK'})]:
            changed = copy.deepcopy(self.evidence); changed['windowsReinspection'][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError): self.prepare(changed)
        self.assertFalse(self.output.exists())

    def test_windows_manifest_original_failure_and_marker_proof_cannot_be_changed(self):
        original = copy.deepcopy(self.windows_reinspection)
        for key, value in [('originalInspectionOutcome', 'success'), ('productRebuilt', True), ('binaryModified', 0),
                           ('inspectionRunUrl', PREP.run_url(PREP.RUN)), ('inspectionCommit', 'f' * 40),
                           ('applicationIdentity', {**PREP.WINDOWS_APPLICATION_IDENTITY, 'changedBytes': 2}),
                           ('applicationIdentity', {**PREP.WINDOWS_APPLICATION_IDENTITY, 'stageSha256': 'f' * 64}),
                           ('applicationIdentity', {**PREP.WINDOWS_APPLICATION_IDENTITY, 'actualExecutablesModified': True})]:
            self.windows_reinspection = {**original, key: value}; self.write_archive('Windows')
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, 'Reinspection provenance'): self.prepare()
        self.assertFalse(self.output.exists())

    def test_windows_candidate_must_bind_new_run_and_packaged_not_stage_hash(self):
        original = copy.deepcopy(self.manifests['Windows'])
        for mutation in (
                lambda m: m.update(runUrl=PREP.run_url(PREP.RUN)),
                lambda m: m['workflowInspection']['assertions'].update(runUrl=PREP.run_url(PREP.RUN)),
                lambda m: (m['application'].update(sha256=PREP.WINDOWS_APPLICATION_IDENTITY['stageSha256']),
                           m['workflowInspection']['assertions'].update(applicationSha256=PREP.WINDOWS_APPLICATION_IDENTITY['stageSha256'],
                                                                       extractedApplicationSha256=PREP.WINDOWS_APPLICATION_IDENTITY['stageSha256']))):
            self.manifests['Windows'] = copy.deepcopy(original); mutation(self.manifests['Windows']); self.write_archive('Windows')
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): self.prepare()

    def test_reinspection_manifest_cannot_relabel_failure_or_change_identity_scope(self):
        original = copy.deepcopy(self.reinspection)
        for key, value in [('originalInspectionOutcome', 'success'), ('productRebuilt', True),
                           ('productRebuilt', 0), ('binaryModified', True), ('installedAcceptance', True),
                           ('sourceCommit', 'f' * 40), ('inspectionCommit', 'f' * 40),
                           ('inspectionRunUrl', PREP.run_url(PREP.RUN)), ('buildRunUrl', PREP.run_url(999)),
                           ('inputArtifact', {**PREP.INPUT_ARTIFACT, 'sha256': 'f' * 64}),
                           ('applicationSha256', 'f' * 64), ('installerSha256', 'f' * 64), ('extraClaim', True)]:
            self.reinspection = {**original, key: value}; self.write_archive('macOS')
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, 'Reinspection provenance'): self.prepare()
        self.assertFalse(self.output.exists())

    def test_mac_candidate_and_assertions_must_bind_new_run_and_original_binary(self):
        original = copy.deepcopy(self.manifests['macOS'])
        for mutation in (
                lambda m: m.update(runUrl=PREP.run_url(PREP.RUN)),
                lambda m: m['workflowInspection']['assertions'].update(runUrl=PREP.run_url(PREP.RUN)),
                lambda m: (m['application'].update(sha256='f' * 64),
                           m['workflowInspection']['assertions'].update(applicationSha256='f' * 64, extractedApplicationSha256='f' * 64))):
            self.manifests['macOS'] = copy.deepcopy(original); mutation(self.manifests['macOS']); self.write_archive('macOS')
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): self.prepare()

    def test_reinspection_is_separate_from_original_checksum_inventory_and_no_duplicate_json(self):
        for malformed in (b'{}', (json.dumps(self.reinspection).replace('{', '{"schemaVersion":1,', 1)).encode()):
            self.write_archive('macOS', reinspection_bytes=malformed)
            with self.subTest(malformed=malformed), self.assertRaises(ValueError): self.prepare()
        original_checksums = ''.join(f'{sha(data)}  {name}\n' for name, data in {
            **self.members['macOS'], PREP.MANIFEST: (json.dumps(self.manifests['macOS'], indent=3) + '\n').encode()}.items())
        self.write_archive('macOS', checksum=(original_checksums + f'{sha(json.dumps(self.reinspection).encode())}  {PREP.REINSPECTION}\n').encode())
        with self.assertRaisesRegex(ValueError, 'checksum inventory'): self.prepare()

    def test_extra_paths_aliases_and_duplicate_inventory_are_rejected(self):
        for name in ('../evil', '/evil', 'folder/evil', 'CANDIDATE-manifest.json', PREP.MANIFEST, 'evil\\path'):
            with self.subTest(name=name):
                self.write_archive('Windows', extra=(name, b'x'))
                with self.assertRaises(ValueError): self.prepare()

    def test_links_special_types_and_unbounded_members_are_rejected(self):
        artifact = self.evidence['artifacts'][0]
        for mode in (stat.S_IFLNK, stat.S_IFIFO, stat.S_IFDIR):
            path = self.write_archive('Windows')
            with zipfile.ZipFile(path) as z: entries = [(i, z.read(i)) for i in z.infolist()]
            with zipfile.ZipFile(path, 'w') as z:
                for entry, data in entries:
                    if entry.filename == artifact['installer']: entry.external_attr = (mode | 0o600) << 16
                    z.writestr(entry, data)
            artifact['size'] = path.stat().st_size; artifact['sha256'] = VERIFY.sha256(path)
            with self.subTest(mode=mode), self.assertRaises(ValueError): self.prepare()
        self.write_archive('Windows')
        with patch.object(PREP, 'MAX_TOTAL', 1), self.assertRaisesRegex(ValueError, 'total'): self.prepare()

    def test_scope_and_application_hash_binding_cannot_be_promoted(self):
        original = copy.deepcopy(self.manifests['Windows'])
        mutations = [lambda m: m['scope'].update(installerExecuted=True),
                     lambda m: m['scope'].update(releaseAcceptance=0),
                     lambda m: m['application'].update(sha256='f' * 64),
                     lambda m: m['source'].update(commit='f' * 40),
                     lambda m: m['versionManifests'][0].update(sha256='f' * 64),
                     lambda m: m['workflowInspection']['assertions']['checks'].update(lockedBuild=False),
                     lambda m: m['offlineResourceReuse'].update(currentInstallerAcceptanceTransferred=True)]
        for change in mutations:
            self.manifests['Windows'] = copy.deepcopy(original); change(self.manifests['Windows']); self.write_archive('Windows')
            with self.subTest(change=change), self.assertRaises(ValueError): self.prepare()

    def test_original_checksums_must_be_complete_unique_and_correct(self):
        for bad in (b'', b'0' * 64 + b'  CANDIDATE-MANIFEST.json\n', b'bad\n'):
            self.write_archive('Windows', checksum=bad)
            with self.subTest(bad=bad), self.assertRaises(ValueError): self.prepare()

    def test_offline_source_is_rehashed_not_just_asserted(self):
        self.write_archive('Windows', member_changes={PREP.OFFLINE: b'changed source'})
        with self.assertRaisesRegex(ValueError, 'source bytes'): self.prepare()

    def test_duplicate_json_fields_rejected(self):
        data = json.dumps(self.manifests['Windows']).replace('{', '{"schemaVersion":1,', 1).encode()
        self.write_archive('Windows', manifest_bytes=data)
        with self.assertRaisesRegex(ValueError, 'Duplicate JSON'): self.prepare()

    def test_installer_headers_checked_after_matching_hashes(self):
        for platform in ('Windows', 'macOS'):
            manifest = self.manifests[platform]
            name = manifest['installer']['name']; data = bytes(len(self.members[platform][name]))
            manifest['installer']['sha256'] = sha(data)
            manifest['workflowInspection']['assertions']['installerSha256'] = sha(data)
            self.write_archive(platform, member_changes={name: data})
            with self.subTest(platform=platform), self.assertRaises(ValueError): self.prepare()
            # Restore preceding platform to isolate the next header assertion.
            manifest['installer']['sha256'] = sha(self.members[platform][name])
            manifest['workflowInspection']['assertions']['installerSha256'] = manifest['installer']['sha256']
            self.write_archive(platform)

    def test_changed_source_version_or_publisher_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Publisher commit'):
            PREP.prepare(self.archives, self.output, 'f' * 40, self.root, self.evidence)
        (self.root / 'package.json').write_text('{"version":"0.2.4"}')
        with self.assertRaisesRegex(ValueError, 'Tracked source'): self.prepare()

    def test_output_and_symlink_inputs_are_never_overwritten_or_followed(self):
        self.output.mkdir()
        with self.assertRaises(ValueError): self.prepare()
        self.output.rmdir()
        alias = self.base / 'alias'; alias.symlink_to(self.archives, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            PREP.prepare(alias, self.output, self.commit, self.root, self.evidence)

    def test_incomplete_checked_in_schema_always_fails_closed(self):
        evidence = VERIFY.read_json(PREP.ROOT / 'scripts/release-026-evidence.json')
        evidence.update(ready=False, sourceCommit=self.commit, sourceTree=self.tree, artifacts=[])
        with self.assertRaisesRegex(ValueError, 'not ready'): PREP.evidence_check(evidence)

    def test_only_windows_accepts_exact_crlf_checkout_version_hashes(self):
        for item in self.manifests['Windows']['versionManifests']:
            item['sha256'] = sha((self.root / item['path']).read_bytes().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n'))
        self.write_archive('Windows')
        self.prepare()
        import shutil
        shutil.rmtree(self.output)
        item = self.manifests['macOS']['versionManifests'][0]
        item['sha256'] = sha((self.root / item['path']).read_bytes().replace(b'\n', b'\r\n'))
        self.write_archive('macOS')
        with self.assertRaisesRegex(ValueError, 'Version manifest differs'): self.prepare()

if __name__ == '__main__': unittest.main()
