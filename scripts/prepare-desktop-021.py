#!/usr/bin/env python3
"""0.2.21 adapter; historical 0.2.18 implementation remains unchanged."""
import argparse
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.2.21'
REVIEWED_SOURCE = 'bc6bd9b5a69dfcfd791c6d4e5db5fa8daa2dde39'
SPEC = importlib.util.spec_from_file_location('desktop_018', ROOT/'scripts/prepare-desktop-release.py')
legacy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(legacy)
legacy.VERSION = VERSION
legacy.REVIEWED_SOURCE = REVIEWED_SOURCE
legacy.MANIFEST_BASELINE = REVIEWED_SOURCE
legacy.BASELINE_VERSION = VERSION
legacy.SUPPORT = {
    'scripts/prepare-desktop-021.py', 'scripts/publish-desktop-021.cjs',
    'scripts/test_prepare_desktop_021.py', 'scripts/test-desktop-021.cjs',
    '.github/workflows/release-desktop-021.yml', 'docs/releases/0.2.21.zh-CN.md',
}

def require(value, reason):
    if not value:
        raise ValueError(reason)

def validate_installed(report, candidate):
    for flag in ('ok', 'windowsRuntimeExecuted', 'installerExecuted', 'realModelExecuted',
                 'rulesRemoved', 'ownedInstallRemoved', 'installedPackageTested', 'installedScreenshotEditorVerified'):
        require(report.get(flag) is True, 'Installed report missing true flag: '+flag)
    require(report.get('mockTranslationUsed') is False, 'Mock translation forbidden')
    require(report.get('installerSha256') == candidate['installer']['sha256']
            and report.get('installerBytes') == candidate['installer']['size']
            and report.get('applicationSha256') == candidate['application']['sha256'], 'Installed bytes differ from publication candidate')
    app = report.get('installedApplication', {})
    require(app.get('ok') is True and app.get('translationBackend') == 'real-bundled-offline-model'
            and app.get('mockRequests') == [] and app.get('defaultCaptureWithoutEnvironmentRequested') is True
            and app.get('captureBackendEnvironmentAbsent') is True
            and app.get('defaultNativeCaptureCompletion', {}).get('nativeCaptureBackend') == 1,
            'Installed application core acceptance incomplete')

def prepare(artifacts, output, run_url):
    # No asset directory is created before strict source and installed-byte checks.
    provenance = legacy.check_source()
    report_path = artifacts/'Windows/echolingo-offline-validation.json'
    report = legacy.verifier().read_json(report_path)
    candidate = legacy.verifier().read_json(artifacts/'Windows/candidate.json')
    validate_installed(report, candidate)
    manifest = legacy.prepare(artifacts, output, run_url)
    manifest['scope']['installerExecuted'] = True
    manifest['windowsInstalledAcceptance'] = {
        'version': VERSION, 'commit': provenance['commit'], 'tree': provenance['tree'],
        'runUrl': run_url, 'ok': True, 'installerExecuted': True,
        'realModelExecuted': True, 'mockTranslationUsed': False,
        'rulesRemoved': True, 'ownedInstallRemoved': True,
        'installedPackageTested': True, 'installedScreenshotEditorVerified': True,
        'installerSha256': report['installerSha256'], 'installerBytes': report['installerBytes'],
        'applicationSha256': report['applicationSha256'], 'evidence': legacy.identity(report_path),
    }
    (output/'RELEASE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    (output/'SHA256SUMS.txt').write_text(''.join(
        f'{legacy.identity(p)["sha256"]}  {p.name}\n'
        for p in sorted(output.iterdir()) if p.name != 'SHA256SUMS.txt'),encoding='utf-8')
    return manifest

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--check-source',action='store_true')
    p.add_argument('--artifacts',type=Path);p.add_argument('--output',type=Path);p.add_argument('--run-url')
    a = p.parse_args()
    if a.check_source:
        print(json.dumps(legacy.check_source()))
    elif a.artifacts and a.output and a.run_url:
        print(json.dumps(prepare(a.artifacts,a.output,a.run_url)))
    else:
        p.error('Provide --check-source or --artifacts, --output and --run-url')
