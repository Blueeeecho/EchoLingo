#!/usr/bin/env python3
"""Prepare 0.2.14 using current-run native packages and accepted Windows ZIP bytes."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.2.14'
REVIEWED_SOURCE = '22e0267a7f333b84a73b596940ff7452a0e9f755'
MODE = 'desktop-settings-routing-unpack-v1'
SUPPORT = {
    'package.json', 'package-lock.json', 'src-tauri/tauri.conf.json',
    'src-tauri/Cargo.toml', 'src-tauri/Cargo.lock',
    'src-tauri/native-capture/Cargo.toml', 'src-tauri/native-capture/Cargo.lock',
    'scripts/inspect-candidate-package.py', 'scripts/verify-candidate-package.py',
    'scripts/test_inspect_candidate_package.py', 'scripts/test_candidate_package.py',
    'scripts/prepare-desktop-release.py', 'scripts/test_prepare_desktop_release.py',
    'scripts/publish-desktop-release.cjs', 'scripts/test-desktop-release.cjs',
    '.github/workflows/release-desktop.yml', '.github/workflows/release-routing.yml',
    '.github/workflows/ci.yml',
    'scripts/test_prepare_routing_release.py', 'scripts/test_prepare_release_assets.py',
    'docs/releases/0.2.14.zh-CN.md',
    'tests/macos-screenshot-native-fixture.swift',
    'tests/test_macos_pin_readiness_fixture_contract.py',
}


def verifier():
    spec = importlib.util.spec_from_file_location('desktop_candidate', ROOT/'scripts/verify-candidate-package.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    result.VERSION = VERSION
    return result


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True, encoding='utf-8').strip()


def check_source():
    if re.fullmatch('[0-9a-f]{40}', REVIEWED_SOURCE) is None:
        raise ValueError('Final verified integration commit must be pinned before release')
    subprocess.run(['git', 'merge-base', '--is-ancestor', REVIEWED_SOURCE, 'HEAD'], cwd=ROOT, check=True)
    changed = set(git('diff', '--name-only', REVIEWED_SOURCE, 'HEAD').splitlines())
    if changed-SUPPORT:
        raise ValueError('Unexpected post-review changes: '+str(sorted(changed-SUPPORT)))
    value = verifier()
    for name in value.VERSION_PATHS:
        before = git('show', REVIEWED_SOURCE+':'+name).replace('"0.2.13"', '"0.2.14"').strip()
        if before != (ROOT/name).read_text(encoding='utf-8').strip():
            raise ValueError('Non-version manifest change: '+name)
    value.check_versions(ROOT)
    return value.source_provenance(ROOT)


def identity(path):
    return verifier().identity(path)


def validate_candidate(report, platform, provenance, run_url, installer):
    value = verifier()
    if (report.get('version') != VERSION or report.get('platform') != platform
            or report.get('validationMode') != value.MODE or report.get('source') != provenance
            or report.get('runUrl') != run_url or report.get('installer') != identity(installer)):
        raise ValueError('Native candidate source/run/package mismatch')
    scope = report.get('scope', {})
    if scope.get('buildAndStaticPackageEvidenceOnly') is not True or any(scope.get(k) is not False for k in (
            'installerExecuted', 'installedApplicationAcceptance', 'interactiveSelectionAcceptance',
            'visualAcceptance', 'performanceAcceptance', 'releaseAcceptance', 'historicalInstallerAcceptanceTransferred')):
        raise ValueError('Native package inspection must not claim unsupported acceptance')
    value.check_attestations(report['workflowInspection']['assertions'], platform, provenance,
                             run_url, report['installer'], report['application'])
    reuse = report.get('offlineResourceReuse')
    if platform == 'Windows' and (not reuse or reuse.get('currentInstallerAcceptanceTransferred') is not False
                                  or reuse.get('currentEngineRuntimeExecuted') is not False):
        raise ValueError('Offline-resource reuse scope is invalid')
    if platform == 'macOS' and reuse is not None:
        raise ValueError('Unexpected macOS resource reuse')


REQUIRED_SMOKE = ('ok', 'windowsRuntimeExecuted', 'settingsWebViewReady', 'expectedLocalWebViewProfileCreated',
                  'roamingDirectoryAvailable', 'packageUnchangedAfterRun', 'realTranslationBothDirections',
                  'embeddedCaptureMemorySelfTest', 'peDependencyChecks', 'launcherMissingZeroPresentMocks')


def validate_zip(directory, provenance, source, windows_candidate):
    value = verifier()
    manifest = value.read_json(directory/'WINDOWS-ZIP-MANIFEST.json')
    smoke = value.read_json(directory/'windows-unpack-smoke.json')
    archive = directory/f'EchoLingo_{VERSION}_windows_x64-unpack.zip'
    if (manifest.get('version') != VERSION or manifest.get('commit') != provenance['commit']
            or manifest.get('formatVersion') != 1 or manifest.get('kind') != 'windows-unpack'
            or manifest.get('userDataPortable') is not False
            or manifest.get('webview2') != 'external-evergreen-runtime-required'):
        raise ValueError('ZIP manifest source/version/scope mismatch')
    if manifest.get('archives') != [identity(archive), identity(source)]:
        raise ValueError('ZIP/source identity mismatch')
    if (smoke.get('version') != VERSION or smoke.get('archiveSha256') != identity(archive)['sha256']
            or any(smoke.get(flag) is not True for flag in REQUIRED_SMOKE)
            or smoke.get('interactiveCaptureTested') is not False or smoke.get('networkIsolationTested') is not False
            or smoke.get('cleanupComplete') is False):
        raise ValueError('Required bounded Windows ZIP runtime evidence did not pass')
    entries = manifest.get('files', [])
    files = {}
    for entry in entries:
        name = entry['path']
        if (not isinstance(name, str) or not name or '\\' in name or ':' in name
                or any(part in ('', '.', '..') for part in name.split('/')) or name.casefold() in files):
            raise ValueError('Unsafe/duplicate ZIP member')
        files[name.casefold()] = entry
    if not files or len(files) != len(entries):
        raise ValueError('Missing ZIP inventory')
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        if len(members) != len(files) or {m.filename for m in members} != {e['path'] for e in entries}:
            raise ValueError('ZIP inventory differs from manifest')
        for member in members:
            entry = files[member.filename.casefold()]
            if (member.file_size != entry['size'] or member.file_size <= 0 or member.file_size > 256*1024*1024
                    or member.flag_bits & 1 or (member.external_attr >> 16) & 0o170000 == 0o120000):
                raise ValueError('Unsafe or wrong-sized ZIP member')
            with bundle.open(member) as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != entry['sha256']:
                    raise ValueError('ZIP member hash mismatch')
    for name, field in [('echolingo.exe', 'applicationSha256'),
                        ('offline-translation/bin/echolingo-offline-engine.exe', 'engineSha256')]:
        if (name not in files or re.fullmatch('[0-9a-f]{64}', smoke.get(field, '')) is None
                or files[name]['sha256'] != smoke[field]):
            raise ValueError('Executed ZIP application/engine differs from delivered bytes')
    with zipfile.ZipFile(archive) as bundle:
        application = bundle.read('echolingo.exe')
    marker = b'__TAURI_BUNDLE_TYPE_VAR_UNK'
    if application.count(marker) != 1:
        raise ValueError('Exactly one Tauri bundle marker required in ZIP application')
    nsis_application = application.replace(marker, b'__TAURI_BUNDLE_TYPE_VAR_NSS')
    if hashlib.sha256(nsis_application).hexdigest() != windows_candidate['application']['sha256']:
        raise ValueError('ZIP and NSIS application differ beyond the exact Tauri bundle marker')
    if re.fullmatch('[0-9a-f]{64}', smoke.get('captureSha256', '')) is None:
        raise ValueError('Exact embedded capture identity missing')
    return archive, manifest, smoke


def prepare(artifacts, output, run_url):
    provenance = check_source()
    if re.fullmatch(r'https://github\.com/Blueeeecho/EchoLingo/actions/runs/[1-9][0-9]*', run_url) is None:
        raise ValueError('Canonical build run URL required')
    if output.exists():
        raise ValueError('Refusing to overwrite publication inputs')
    value = verifier()
    reports = {}; inputs = []
    for platform, suffix in [('Windows', 'windows_x64-setup.exe'), ('macOS', 'macos_arm64.dmg')]:
        directory = artifacts/platform
        report = value.read_json(directory/'candidate.json')
        allowed = {f'EchoLingo_{VERSION}_x64-setup.exe'} if platform == 'Windows' else {
            f'EchoLingo_{VERSION}_aarch64.dmg', f'EchoLingo_{VERSION}_arm64.dmg'}
        if report['installer']['name'] not in allowed:
            raise ValueError('Unexpected platform installer name')
        installer = directory/report['installer']['name']
        validate_candidate(report, platform, provenance, run_url, installer)
        reports[platform] = report
        inputs.append((installer, f'EchoLingo_{VERSION}_{suffix}'))
    source = artifacts/'Windows'/'EchoLingo-offline-engine-source.zip'
    if identity(source) != reports['Windows']['offlineResourceReuse']['sourceArchive']:
        raise ValueError('Corresponding source mismatch')
    archive, zip_manifest, smoke = validate_zip(artifacts/'Windows', provenance, source, reports['Windows'])
    settings = value.read_json(artifacts/'Windows'/'windows-settings.json')
    focus = value.read_json(artifacts/'Windows'/'windows-native-focus.json')
    if (settings.get('ok') is not True or settings.get('actualSettingsUiTested') is not True
            or settings.get('fakeIpcUsed') is not False or settings.get('userContentRead') is not False
            or settings.get('applicationSha256') != smoke['applicationSha256']):
        raise ValueError('Actual Windows settings evidence missing or bound to another application')
    if (focus.get('ok') is not True or focus.get('generatedSourceOnly') is not True
            or focus.get('expectCrossProcessSuccess') is not True or focus.get('passedCases') != 2
            or focus.get('executedCases') != 2 or focus.get('userContentRead') is not False
            or focus.get('actualApplicationTested') is not False
            or re.fullmatch('[0-9a-f]{64}', focus.get('nativeAssemblySha256', '')) is None):
        raise ValueError('Generated native focus evidence is incomplete or overstated')
    inputs += [(archive, archive.name), (source, source.name),
               (artifacts/'Windows'/'WINDOWS-ZIP-MANIFEST.json', 'WINDOWS-ZIP-MANIFEST.json')]
    output.mkdir()
    for original, name in inputs:
        shutil.copyfile(original, output/name)
    manifest = {'version': VERSION, 'commit': provenance['commit'], 'tree': provenance['tree'],
                'reviewedSourceCommit': REVIEWED_SOURCE, 'validationRun': run_url, 'validationMode': MODE,
                'rebuiltAfterValidation': False, 'scope': {'fullRegression': False, 'installerExecuted': False,
                'macOSRuntimeAcceptance': False, 'windowsZipRuntimeAcceptance': True,
                'interactiveCaptureAcceptance': False, 'networkIsolationAcceptance': False},
                'nativePackageInspection': reports, 'windowsZipRuntime': smoke,
                'windowsSettingsAcceptance': {'actualSettingsUiTested': True, 'fakeIpcUsed': False,
                    'applicationSha256': settings['applicationSha256'],
                    'evidence': identity(artifacts/'Windows'/'windows-settings.json')},
                'windowsGeneratedFocusAcceptance': {'generatedSourceOnly': True,
                    'actualApplicationTested': False, 'passedCases': 2,
                    'nativeAssemblySha256': focus['nativeAssemblySha256'],
                    'evidence': identity(artifacts/'Windows'/'windows-native-focus.json')},
                'files': [identity(output/name) for _, name in inputs]}
    (output/'RELEASE-MANIFEST.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    (output/'SHA256SUMS.txt').write_text(''.join(
        f'{identity(path)["sha256"]}  {path.name}\n' for path in sorted(output.iterdir())), encoding='utf-8')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-source', action='store_true')
    parser.add_argument('--artifacts', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--run-url')
    args = parser.parse_args()
    if args.check_source:
        print(json.dumps(check_source()))
    elif all((args.artifacts, args.output, args.run_url)):
        print(json.dumps(prepare(args.artifacts, args.output, args.run_url)))
    else:
        parser.error('Provide --check-source or --artifacts, --output and --run-url')
