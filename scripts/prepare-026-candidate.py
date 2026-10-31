#!/usr/bin/env python3
"""Prepare pinned 0.2.6 candidate bytes only; never build or execute a package.

The checked-in evidence must be complete. Source manifests are read from the
exact candidate Git commit, not from the later publisher checkout. Application
hashes are existing static-inspection assertions: bare applications are not in
these artifacts and are not re-extracted or executed here.
"""
import argparse
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'd91b59505f81d766eca25a8cff4764c278542275'
SOURCE_TREE = '2898ee1bad7f1d73d408d2ad5fc136cfc869fe3a'
RUN = 41195400127
REPOSITORY = 'Blueeeecho/EchoLingo'
REPOSITORY_ID = 1432139657
SOURCE_BRANCH = 'fix/025-macos-recovery-integration'
JOB_NAMES = {'native-selection-recovery',
             'Compile Windows host and focused input policies (no package output)',
             'Build and inspect 0.2.6 candidate (macos-latest)',
             'Build and inspect 0.2.6 candidate (windows-latest)'}
MAX_ARCHIVE = 512 * 1024 * 1024
MAX_TOTAL = 768 * 1024 * 1024
MANIFEST = 'CANDIDATE-MANIFEST.json'
REINSPECTION = 'REINSPECTION-MANIFEST.json'
INSPECTION_JOB = 'Reinspect the original 0.2.6 macOS bytes without rebuilding'
INSPECTION_CHANGES = [
    {'status': 'A', 'path': '.github/workflows/reinspect-026-macos-package.yml'},
    {'status': 'A', 'path': 'scripts/reinspect-026-macos-package.py'},
    {'status': 'M', 'path': 'scripts/inspect-candidate-package.py'},
    {'status': 'M', 'path': 'scripts/test_inspect_candidate_package.py'},
]
INPUT_ARTIFACT = {'id': 13041241190, 'name': 'EchoLingo-0.2.6-UNVERIFIED-build-macOS',
                  'size': 9596150, 'sha256': 'c877dcf26a6e85d7ee8e3f7682980b20fbb68f3241065efbdb99b86d65377ba8'}
MAC_INSTALLER_SHA = '441c7d00fee0701f1942b1e5fc173c79479385d71c8922507fd83163d37c26e7'
MAC_APPLICATION_SHA = '112c4888c2d6c3dd801f808364ccb2dc2d23ffd23219052822e0d50f6fbaaf17'
LICENSE_SHA = '20ce870fd3c179bf06c2d28e32264a30e2a7b34e5d317d7aafe2ee0176849e71'
WINDOWS_REINSPECTION = 'REINSPECTION-MANIFEST.Windows.json'
WINDOWS_INSPECTION_JOB = 'Reinspect the original 0.2.6 Windows bytes without rebuilding'
WINDOWS_INSPECTION_CHANGES = [
    {'status': 'A', 'path': '.github/workflows/diagnose-026-windows-package.yml'},
    {'status': 'A', 'path': 'scripts/diagnose-026-windows-package.py'},
    {'status': 'M', 'path': 'scripts/inspect-candidate-package.py'},
    {'status': 'M', 'path': 'scripts/test_inspect_candidate_package.py'},
]
WINDOWS_INPUT_ARTIFACT = {'id': 13040982741, 'name': 'EchoLingo-0.2.6-UNVERIFIED-build-Windows',
                        'size': 79796541, 'sha256': '4787f328c08f8b9e4afd9a2881efcac192047cc38e73c5a9ae3add1b86116618'}
WINDOWS_INSTALLER_SHA = 'd6849ba7dd241ca690b7b787cc7c50c4d1ff779100dc955ffed17ae7fb6973ae'
WINDOWS_APPLICATION_SHA = '159ffa2b057b1e106d64022acd554f7cf2d75f9e4e0294b916e043f55414e653'
WINDOWS_APPLICATION_IDENTITY = {
    'schemaVersion': 1, 'method': 'tauri-cli-2.12.4-nsis-bundle-marker',
    'stageSha256': '5027e0162754b53689219b15d710680c49579fe4974bb5acf6bc2204469c03f4',
    'packagedSha256': WINDOWS_APPLICATION_SHA, 'expectedNsisSha256': WINDOWS_APPLICATION_SHA,
    'markerOffset': 7402725, 'stageMarker': '__TAURI_BUNDLE_TYPE_VAR_UNK',
    'packagedMarker': '__TAURI_BUNDLE_TYPE_VAR_NSS', 'changedBytes': 3, 'comparedBytes': 8223744,
    'actualExecutablesModified': False,
}
OFFLINE = 'EchoLingo-offline-engine-source.zip'
SCOPE = {'buildAndStaticPackageEvidenceOnly': True, 'installerExecuted': False,
         'installedApplicationAcceptance': False, 'interactiveSelectionAcceptance': False,
         'visualAcceptance': False, 'performanceAcceptance': False, 'releaseAcceptance': False,
         'historicalInstallerAcceptanceTransferred': False}
SPEC = importlib.util.spec_from_file_location('candidate_026_verifier', ROOT / 'scripts/verify-candidate-package.py')
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def positive(value):
    return type(value) is int and value > 0


def commit_id(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{40}', value) is not None


def run_url(run):
    return f'https://github.com/{REPOSITORY}/actions/runs/{run}'


def exact(value, expected, message):
    # JSON booleans must not be accepted as integer 0/1.
    require(json.dumps(value, sort_keys=True) == json.dumps(expected, sort_keys=True), message)


def evidence_check(evidence):
    require(set(evidence) == {'schemaVersion', 'ready', 'version', 'repository', 'repositoryId',
            'sourceCommit', 'sourceTree', 'runId', 'sourceBranch', 'jobs', 'artifacts', 'macOSReinspection',
            'windowsReinspection'}, 'Unexpected evidence schema')
    exact({key: evidence[key] for key in ('schemaVersion', 'ready', 'version', 'repository', 'sourceCommit', 'sourceTree', 'runId')},
          {'schemaVersion': 1, 'ready': True, 'version': '0.2.6', 'repository': REPOSITORY,
           'sourceCommit': SOURCE, 'sourceTree': SOURCE_TREE, 'runId': RUN}, 'Evidence is not ready for this exact candidate')
    require(type(evidence['repositoryId']) is int and evidence['repositoryId'] == REPOSITORY_ID
            and evidence['sourceBranch'] == SOURCE_BRANCH, 'Invalid repository/branch identity')
    jobs = evidence['jobs']
    require(isinstance(jobs, list) and len(jobs) == 4, 'Exactly four pinned jobs are required')
    for job in jobs:
        require(set(job) == {'id', 'name'} and positive(job['id']) and isinstance(job['name'], str)
                and job['name'].strip() == job['name'] and job['name'] and not any(ord(c) < 32 for c in job['name']), 'Invalid job pin')
    require(len({j['id'] for j in jobs}) == 4 and {j['name'] for j in jobs} == JOB_NAMES, 'Unexpected or duplicate job pin')
    inspection = evidence['macOSReinspection']
    require(isinstance(inspection, dict) and set(inspection) == {'runId', 'commit', 'tree', 'branch',
            'workflowPath', 'job', 'allowedChanges', 'inputArtifact', 'installerSha256', 'applicationSha256',
            'licenseSha256'}, 'Unexpected reinspection evidence schema')
    require(positive(inspection['runId']) and inspection['runId'] != RUN and commit_id(inspection['commit'])
            and inspection['commit'] != SOURCE and commit_id(inspection['tree']), 'Incomplete reinspection identity')
    exact({key: inspection[key] for key in ('branch', 'workflowPath', 'inputArtifact', 'installerSha256',
          'applicationSha256', 'licenseSha256')},
          {'branch': 'verify/026-macos-package', 'workflowPath': '.github/workflows/reinspect-026-macos-package.yml',
           'inputArtifact': INPUT_ARTIFACT, 'installerSha256': MAC_INSTALLER_SHA,
           'applicationSha256': MAC_APPLICATION_SHA, 'licenseSha256': LICENSE_SHA}, 'Original macOS bytes/license pin changed')
    require(isinstance(inspection['job'], dict) and set(inspection['job']) == {'id', 'name'}
            and positive(inspection['job']['id']) and inspection['job']['name'] == INSPECTION_JOB,
            'Unexpected reinspection job')
    changes = inspection['allowedChanges']
    require(isinstance(changes, list) and all(isinstance(c, dict) and set(c) == {'status', 'path'}
            and isinstance(c['status'], str) and isinstance(c['path'], str) for c in changes), 'Invalid reinspection delta')
    exact(sorted(changes, key=lambda c: (c['status'], c['path'])), INSPECTION_CHANGES, 'Unexpected reinspection delta')
    windows = evidence['windowsReinspection']
    require(isinstance(windows, dict) and set(windows) == {'runId', 'commit', 'tree', 'branch',
            'workflowPath', 'job', 'allowedChanges', 'inputArtifact', 'installerSha256', 'applicationSha256',
            'applicationIdentity'}, 'Unexpected Windows reinspection evidence schema')
    require(positive(windows['runId']) and windows['runId'] not in (RUN, inspection['runId'])
            and commit_id(windows['commit']) and windows['commit'] != SOURCE and commit_id(windows['tree']),
            'Incomplete Windows reinspection identity')
    exact({key: windows[key] for key in ('branch', 'workflowPath', 'inputArtifact', 'installerSha256',
          'applicationSha256', 'applicationIdentity')},
          {'branch': 'verify/026-windows-package', 'workflowPath': '.github/workflows/diagnose-026-windows-package.yml',
           'inputArtifact': WINDOWS_INPUT_ARTIFACT, 'installerSha256': WINDOWS_INSTALLER_SHA,
           'applicationSha256': WINDOWS_APPLICATION_SHA, 'applicationIdentity': WINDOWS_APPLICATION_IDENTITY},
          'Original Windows bytes/bundle-marker identity changed')
    require(isinstance(windows['job'], dict) and set(windows['job']) == {'id', 'name'}
            and positive(windows['job']['id']) and windows['job']['name'] == WINDOWS_INSPECTION_JOB,
            'Unexpected Windows reinspection job')
    changes = windows['allowedChanges']
    require(isinstance(changes, list) and all(isinstance(c, dict) and set(c) == {'status', 'path'}
            and isinstance(c['status'], str) and isinstance(c['path'], str) for c in changes), 'Invalid Windows reinspection delta')
    exact(sorted(changes, key=lambda c: (c['status'], c['path'])), WINDOWS_INSPECTION_CHANGES, 'Unexpected Windows reinspection delta')
    artifacts = evidence['artifacts']
    require(isinstance(artifacts, list) and len(artifacts) == 2, 'Exactly two platform artifacts required')
    for item in artifacts:
        require(set(item) == {'platform', 'id', 'name', 'size', 'sha256', 'installer'}, 'Unexpected artifact pin')
        require(item['platform'] in {'Windows', 'macOS'} and positive(item['id']) and positive(item['size'])
                and item['size'] <= MAX_ARCHIVE and digest(item['sha256']), 'Incomplete artifact pin')
        require(item['name'] == 'EchoLingo-0.2.6-candidate-' + item['platform'] + '-reinspected', 'Unexpected artifact name')
        require(item['installer'] in ({'EchoLingo_0.2.6_x64-setup.exe'} if item['platform'] == 'Windows'
                else {'EchoLingo_0.2.6_aarch64.dmg'}), 'Unexpected installer pin')
    require({a['platform'] for a in artifacts} == {'Windows', 'macOS'} and len({a['id'] for a in artifacts}) == 2,
            'Duplicate artifact identity')
    return evidence


def file_identity(value, expected_name=None):
    require(isinstance(value, dict) and set(value) == {'name', 'size', 'sha256'}, 'Invalid file identity fields')
    require(positive(value['size']) and digest(value['sha256']) and isinstance(value['name'], str)
            and re.fullmatch(r'[A-Za-z0-9_.-]+', value['name']), 'Invalid file identity')
    if expected_name is not None:
        require(value['name'] == expected_name, 'Unexpected file identity name')
    return value


def source_versions(root, temporary, publisher):
    provenance = VERIFY.source_provenance(root)
    require(provenance['commit'] == publisher, 'Publisher commit differs from clean checked-out HEAD')
    require(VERIFY.git(root, 'rev-parse', SOURCE + '^{tree}') == SOURCE_TREE, 'Candidate source/tree mismatch')
    source = temporary / 'version-source'
    for name in VERIFY.VERSION_PATHS:
        target = source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(subprocess.check_output(['git', 'show', SOURCE + ':' + name], cwd=root))
    versions = VERIFY.check_versions(source)
    windows_hashes = {name: {VERIFY.sha256(source / name),
                      hashlib.sha256((source / name).read_bytes().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')).hexdigest()}
                      for name in VERIFY.VERSION_PATHS}
    return versions, windows_hashes


def extract_pinned(path, destination, artifact):
    path = VERIFY.no_links(path)
    require(path.is_file() and path.stat().st_nlink == 1, 'Artifact hardlink/alias is forbidden')
    require(VERIFY.identity(path) == {'name': artifact['name'] + '.zip', 'size': artifact['size'],
                                      'sha256': artifact['sha256']}, 'Original artifact ZIP pin mismatch')
    expected = {artifact['installer'], MANIFEST, MANIFEST + '.sha256'}
    if artifact['platform'] == 'Windows':
        expected.update((OFFLINE, WINDOWS_REINSPECTION))
    else:
        expected.add(REINSPECTION)
    with zipfile.ZipFile(path) as archive:
        members = archive.infolist()
        require(len(members) == len(expected), 'Unexpected ZIP member count')
        require({m.filename for m in members} == expected, 'ZIP must contain the exact flat inventory')
        seen, total = set(), 0
        for member in members:
            name = member.filename
            require(member.orig_filename == name and name not in seen and name.casefold() not in seen,
                    'ZIP alias or duplicate member')
            seen.update((name, name.casefold()))
            require(not member.is_dir() and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG)
                    and not member.flag_bits & 1 and member.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
                    'ZIP links, special files or encryption are forbidden')
            limit = 4 * 1024 * 1024 if name == MANIFEST else 16384 if name in (REINSPECTION, WINDOWS_REINSPECTION) else 4096 if name.endswith('.sha256') else MAX_ARCHIVE
            require(0 < member.file_size <= limit, 'ZIP member size exceeds bound')
            total += member.file_size
            require(total <= MAX_TOTAL, 'ZIP total exceeds bound')
        destination.mkdir()
        for member in members:
            written = 0
            with archive.open(member) as incoming, (destination / member.filename).open('xb') as outgoing:
                for chunk in iter(lambda: incoming.read(1024 * 1024), b''):
                    written += len(chunk)
                    require(written <= member.file_size, 'ZIP expansion exceeds declared size')
                    outgoing.write(chunk)
            require(written == member.file_size, 'ZIP expansion size mismatch')
    require(VERIFY.sha256(path) == artifact['sha256'] and path.stat().st_size == artifact['size'], 'Original ZIP changed during extraction')


def pinned_offline(root):
    path = VERIFY.no_links(root / 'scripts/stage-language-patch-resources.py')
    contents = path.read_bytes().replace(b'\r\n', b'\n')
    require(hashlib.sha256(contents).hexdigest() == VERIFY.STAGER_SHA256, 'Reviewed offline stager changed')
    names = {'SOURCE', 'ENGINE', 'BASELINE_COMMIT', 'BASELINE_TREE', 'BASELINE_RUN'}
    values = {}
    for node in ast.parse(contents).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) and node.targets[0].id in names:
            values[node.targets[0].id] = ast.literal_eval(node.value)
    require(set(values) == names, 'Missing pinned offline constants')
    return values


def check_candidate(folder, artifact, versions, offline_pins, windows_hashes, reinspection):
    data = VERIFY.read_json(folder / MANIFEST)
    require(set(data) == {'schemaVersion', 'validationMode', 'version', 'platform', 'architecture', 'source', 'runUrl',
            'versionManifests', 'installer', 'application', 'formatHeaders', 'workflowInspection', 'offlineResourceReuse', 'scope'}, 'Candidate manifest schema changed')
    platform = artifact['platform']
    candidate_run = run_url(reinspection['runId'])
    exact({key: data[key] for key in ('schemaVersion', 'validationMode', 'version', 'platform', 'architecture', 'source', 'runUrl', 'scope')},
          {'schemaVersion': 1, 'validationMode': VERIFY.MODE, 'version': '0.2.6', 'platform': platform,
           'architecture': 'x64' if platform == 'Windows' else 'arm64',
           'source': {'commit': SOURCE, 'tree': SOURCE_TREE, 'trackedWorktreeClean': True}, 'runUrl': candidate_run,
           'scope': SCOPE}, 'Candidate identity, versions or acceptance scope differs')
    manifests = data['versionManifests']
    require(isinstance(manifests, list) and len(manifests) == len(versions), 'Version manifest inventory differs')
    for declared, original in zip(manifests, versions):
        require(isinstance(declared, dict) and set(declared) == {'path', 'sha256'}
                and declared['path'] == original['path'], 'Version manifest path/order differs')
        allowed = windows_hashes[original['path']] if platform == 'Windows' else {original['sha256']}
        require(declared['sha256'] in allowed, 'Version manifest differs from pinned Git blob/checkout bytes')
    installer = file_identity(data['installer'], artifact['installer'])
    exact(VERIFY.identity(folder / installer['name']), installer, 'Installer bytes differ from original manifest')
    application = file_identity(data['application'], 'echolingo.exe' if platform == 'Windows' else 'echolingo')
    inspection = data['workflowInspection']
    require(isinstance(inspection, dict) and set(inspection) == {'evidence', 'assertions'}, 'Inspection schema changed')
    file_identity(inspection['evidence'], 'checks.json')
    VERIFY.check_attestations(inspection['assertions'], platform, data['source'], candidate_run, installer, application)
    if platform == 'Windows':
        headers = {'installer': VERIFY.check_pe(folder / installer['name']), 'application': 'PE-x64'}
    else:
        path = folder / installer['name']
        require(path.stat().st_size > 512, 'Truncated UDIF installer')
        with path.open('rb') as stream:
            stream.seek(-512, 2)
            trailer = stream.read(512)
        require(trailer[:4] == b'koly' and struct.unpack_from('>II', trailer, 4) == (4, 512), 'Invalid UDIF installer header')
        headers = {'installer': 'UDIF-header', 'application': 'Mach-O-arm64-header'}
    exact(data['formatHeaders'], headers, 'Original format evidence mismatch')
    checksum_names = {installer['name'], MANIFEST}
    if platform == 'Windows':
        offline = data['offlineResourceReuse']
        require(isinstance(offline, dict) and set(offline) == {'scope', 'baselineCommit', 'baselineTree', 'baselineRunId', 'stagingManifest',
                'sourceArchive', 'engine', 'runtimeFilesVerified', 'historicalReportBytesPinned',
                'currentInstallerAcceptanceTransferred', 'currentEngineRuntimeExecuted'}, 'Offline scope schema differs')
        file_identity(offline['stagingManifest'], 'baseline-reuse.json')
        expected_source = {'name': OFFLINE, **offline_pins['SOURCE']}
        file_identity(offline['sourceArchive'], OFFLINE)
        exact(offline['sourceArchive'], expected_source, 'Windows offline source pin differs')
        exact(VERIFY.identity(folder / OFFLINE), expected_source, 'Windows offline source bytes differ')
        exact({key: offline[key] for key in ('scope', 'baselineCommit', 'baselineTree', 'baselineRunId', 'engine',
              'historicalReportBytesPinned', 'currentInstallerAcceptanceTransferred', 'currentEngineRuntimeExecuted')},
              {'scope': 'unchanged offline engine/models/notices/corresponding-source only',
               'baselineCommit': offline_pins['BASELINE_COMMIT'], 'baselineTree': offline_pins['BASELINE_TREE'],
               'baselineRunId': offline_pins['BASELINE_RUN'], 'engine': offline_pins['ENGINE'],
               'historicalReportBytesPinned': True, 'currentInstallerAcceptanceTransferred': False,
               'currentEngineRuntimeExecuted': False}, 'Offline evidence claims changed')
        require(positive(offline['runtimeFilesVerified']), 'Missing static offline inventory evidence')
        checksum_names.add(OFFLINE)
    else:
        require(data['offlineResourceReuse'] is None, 'macOS cannot inherit Windows offline acceptance')
    require(installer['sha256'] == reinspection['installerSha256']
            and application['sha256'] == reinspection['applicationSha256'], 'Original ' + platform + ' binary identity changed')
    # These additional provenance files are separately pinned by their original ZIP;
    # neither alters the original CANDIDATE manifest/checksum inventory.
    proof = {'schemaVersion': 1, 'sourceCommit': SOURCE, 'sourceTree': SOURCE_TREE,
             'buildRunUrl': run_url(RUN), 'inspectionRunUrl': candidate_run,
             'inspectionCommit': reinspection['commit'], 'inputArtifact': reinspection['inputArtifact'],
             'installerSha256': installer['sha256'], 'applicationSha256': application['sha256'],
             'productRebuilt': False, 'binaryModified': False, 'installedAcceptance': False,
             'originalInspectionOutcome': 'failure'}
    if platform == 'Windows':
        proof['applicationIdentity'] = reinspection['applicationIdentity']
    exact(VERIFY.read_json(folder / (WINDOWS_REINSPECTION if platform == 'Windows' else REINSPECTION)),
          proof, 'Reinspection provenance/unchanged-byte scope differs')
    checksums = {}
    for line in (folder / (MANIFEST + '.sha256')).read_text(encoding='ascii').splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9_.-]+)', line)
        require(match is not None and match[2] not in checksums, 'Invalid original checksum inventory')
        checksums[match[2]] = match[1]
    require(set(checksums) == checksum_names, 'Original checksum inventory differs')
    for name, value in checksums.items():
        require(VERIFY.sha256(folder / name) == value, 'Original checksum mismatch: ' + name)
    return data


def prepare(archive_directory, output, publisher_commit, root=ROOT, evidence=None):
    require(isinstance(publisher_commit, str) and re.fullmatch(r'[0-9a-f]{40}', publisher_commit), 'Exact publisher commit required')
    evidence = evidence_check(VERIFY.read_json(root / 'scripts/release-026-evidence.json') if evidence is None else evidence)
    archive_directory, output = VERIFY.no_links(archive_directory), VERIFY.no_links(output)
    require(archive_directory.is_dir() and not output.exists() and output.parent.is_dir(), 'Inputs must exist and output must be a new directory')
    require(output != archive_directory and archive_directory not in output.parents, 'Output must not alias artifact inputs')
    with tempfile.TemporaryDirectory(prefix='echolingo-026-publish-', dir=output.parent) as temporary:
        temporary = Path(temporary).resolve(strict=True)  # Only our own newly-created temporary directory.
        versions, windows_hashes = source_versions(root, temporary, publisher_commit)
        offline = pinned_offline(root)
        staged = temporary / 'staged'
        staged.mkdir()
        candidates = []
        for artifact in evidence['artifacts']:
            folder = temporary / artifact['platform']
            extract_pinned(archive_directory / (artifact['name'] + '.zip'), folder, artifact)
            candidate = check_candidate(folder, artifact, versions, offline, windows_hashes,
                                        evidence['windowsReinspection' if artifact['platform'] == 'Windows' else 'macOSReinspection'])
            copied = [artifact['installer']] + ([OFFLINE, WINDOWS_REINSPECTION] if artifact['platform'] == 'Windows' else [REINSPECTION])
            for name in copied:
                shutil.copyfile(folder / name, staged / name)
            target = staged / ('CANDIDATE-MANIFEST.' + artifact['platform'] + '.json')
            shutil.copyfile(folder / MANIFEST, target)  # Preserve original bytes; rename only.
            candidates.append({'platform': artifact['platform'], 'originalArtifact': artifact,
                               'originalCandidateManifest': VERIFY.identity(folder / MANIFEST),
                               'publishedCandidateManifest': VERIFY.identity(target),
                               'installer': candidate['installer'], 'application': candidate['application']})
        manifest = {'schemaVersion': 1, 'version': '0.2.6', 'releaseScope': 'unchanged-testing-candidate-bytes',
                    'sourceCommit': SOURCE, 'sourceTree': SOURCE_TREE, 'publisherCommit': publisher_commit,
                    'repository': REPOSITORY, 'repositoryId': evidence['repositoryId'], 'runId': RUN,
                    'runUrl': run_url(RUN), 'validationRun': run_url(RUN), 'buildRunConclusion': 'failure',
                    'reinspectionRunUrl': run_url(evidence['macOSReinspection']['runId']),
                    'reinspectionCommit': evidence['macOSReinspection']['commit'], 'reinspectionRunConclusion': 'success',
                    'windowsReinspectionRunUrl': run_url(evidence['windowsReinspection']['runId']),
                    'windowsReinspectionCommit': evidence['windowsReinspection']['commit'], 'windowsReinspectionRunConclusion': 'success',
                    'originalWindowsInspectionConclusion': 'failure',
                    'originalMacOSInspectionConclusion': 'failure', 'productRebuilt': False, 'binaryModified': False,
                    'workflowEvidencePolicy': 'publisher must verify live native success, original platform inspection failures, and both separate reinspection successes before publication',
                    'macOSReinspection': evidence['macOSReinspection'], 'windowsReinspection': evidence['windowsReinspection'],
                    'rebuiltAfterValidation': False, **SCOPE, 'sourceBranch': evidence['sourceBranch'],
                    'jobs': evidence['jobs'], 'candidates': candidates, 'versionManifests': versions, 'scope': SCOPE,
                    'versionManifestHashPolicy': 'pinned Git blobs; Windows also permits deterministic CRLF checkout only',
                    'applicationHashVerification': 'original static-inspection assertions; applications not re-extracted or executed',
                    'assets': [VERIFY.identity(path) for path in sorted(staged.iterdir())]}
        (staged / 'RELEASE-MANIFEST.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n', encoding='utf-8')
        (staged / 'SHA256SUMS.txt').write_text(''.join(f'{VERIFY.sha256(path)}  {path.name}\n' for path in sorted(staged.iterdir())), encoding='ascii')
        # Recheck immutable original archives and checked-out source before output.
        for artifact in evidence['artifacts']:
            path = archive_directory / (artifact['name'] + '.zip')
            exact(VERIFY.identity(path), {'name': path.name, 'size': artifact['size'], 'sha256': artifact['sha256']}, 'Artifact changed during preparation')
        require(VERIFY.source_provenance(root)['commit'] == publisher_commit, 'Publisher source changed during preparation')
        VERIFY.no_links(output)
        shutil.copytree(staged, output)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive_directory', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('publisher_commit')
    args = parser.parse_args()
    print(json.dumps(prepare(args.archive_directory, args.output, args.publisher_commit), sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, struct.error, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        raise SystemExit('Candidate preparation failed: ' + str(error))
