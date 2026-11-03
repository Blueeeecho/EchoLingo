#!/usr/bin/env python3
"""Prepare a new scoped routing prerelease from fresh inspected native packages."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.2.13'
# Final routing source passed both platform jobs in run 41582337748.
REVIEWED_SOURCE = '6809ba1c3c2add353cddfcba89338eadc088ca9a'
MODE = 'automatic-direction-targeted-v1'
SUPPORT = {
    'package.json', 'package-lock.json', 'src-tauri/tauri.conf.json',
    'src-tauri/Cargo.toml', 'src-tauri/Cargo.lock',
    'src-tauri/native-capture/Cargo.toml', 'src-tauri/native-capture/Cargo.lock',
    'scripts/inspect-candidate-package.py', 'scripts/verify-candidate-package.py',
    'scripts/test_inspect_candidate_package.py', 'scripts/test_candidate_package.py',
    'scripts/prepare-routing-release.py', 'scripts/test_prepare_routing_release.py',
    'scripts/publish-routing-release.cjs', 'scripts/test-routing-release.cjs',
    '.github/workflows/release-routing.yml', '.github/workflows/release.yml',
    '.github/workflows/ci.yml', 'docs/releases/0.2.13.zh-CN.md',
}

def module():
    spec = importlib.util.spec_from_file_location('candidate', ROOT/'scripts/verify-candidate-package.py')
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

def check_source():
    if not re.fullmatch('[0-9a-f]{40}', REVIEWED_SOURCE):
        raise ValueError('Set REVIEWED_SOURCE to the final verified routing commit before building')
    subprocess.run(['git','merge-base','--is-ancestor',REVIEWED_SOURCE,'HEAD'],cwd=ROOT,check=True)
    changed=set(git('diff','--name-only',REVIEWED_SOURCE,'HEAD').splitlines())
    if changed-SUPPORT:
        raise ValueError('Unreviewed production changes: '+str(sorted(changed-SUPPORT)))
    # Metadata changes must not silently change dependencies, resources or app configuration.
    for path in module().VERSION_PATHS:
        before=git('show',REVIEWED_SOURCE+':'+path).replace('"0.2.12"','"0.2.13"').strip()
        after=(ROOT/path).read_text().strip()
        if before != after:
            raise ValueError('Unexpected non-version manifest changes: '+path)
    module().check_versions(ROOT)
    return module().source_provenance(ROOT)

def select_ci():
    # This fixed-version source allowlist is not a general test bypass.
    try:
        check_source()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError):
        return 'full'
    return 'routing-release'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def identity(path):
    if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
        raise ValueError('Expected nonempty regular file: '+str(path))
    return {'name':path.name,'size':path.stat().st_size,'sha256':digest(path)}

def validate_report(report, platform, commit, tree, run_url, installer):
    verifier=module()
    if (report.get('version') != VERSION or report.get('platform') != platform
        or report.get('validationMode') != verifier.MODE
        or report.get('source') != {'commit':commit,'tree':tree,'trackedWorktreeClean':True}
        or report.get('runUrl') != run_url or report.get('installer') != identity(installer)):
        raise ValueError('Candidate identity differs from release source/run/bytes')
    scope=report.get('scope',{})
    if scope.get('buildAndStaticPackageEvidenceOnly') is not True or any(scope.get(k) is not False for k in (
        'installerExecuted','installedApplicationAcceptance','interactiveSelectionAcceptance',
        'visualAcceptance','performanceAcceptance','releaseAcceptance','historicalInstallerAcceptanceTransferred')):
        raise ValueError('Candidate claims unsupported runtime acceptance')
    verifier.check_attestations(report['workflowInspection']['assertions'],platform,
        report['source'],run_url,report['installer'],report['application'])
    reuse=report.get('offlineResourceReuse')
    if platform=='Windows' and (not reuse or reuse.get('currentInstallerAcceptanceTransferred') is not False
                               or reuse.get('currentEngineRuntimeExecuted') is not False):
        raise ValueError('Windows offline reuse provenance absent or overstated')
    if platform=='macOS' and reuse is not None:
        raise ValueError('Unexpected macOS offline reuse')

def prepare(artifacts, output, run_url):
    provenance=check_source()
    if not re.fullmatch(r'https://github\.com/Blueeeecho/EchoLingo/actions/runs/[1-9][0-9]*',run_url):
        raise ValueError('Canonical build run URL required')
    if output.exists():
        raise ValueError('Refusing to overwrite publication inputs')
    inputs=[]; reports={}
    for platform, suffix in [('Windows','windows_x64-setup.exe'),('macOS','macos_arm64.dmg')]:
        directory=artifacts/platform
        report=json.loads((directory/'candidate.json').read_text())
        allowed = {f'EchoLingo_{VERSION}_x64-setup.exe'} if platform == 'Windows' else {f'EchoLingo_{VERSION}_aarch64.dmg', f'EchoLingo_{VERSION}_arm64.dmg'}
        if report['installer']['name'] not in allowed:
            raise ValueError('Unexpected platform installer filename')
        installer=directory/report['installer']['name']
        if installer.parent != directory:
            raise ValueError('Unsafe installer name')
        validate_report(report,platform,provenance['commit'],provenance['tree'],run_url,installer)
        reports[platform]=report
        inputs.append((installer,f'EchoLingo_{VERSION}_{suffix}'))
    source=artifacts/'Windows'/'EchoLingo-offline-engine-source.zip'
    if identity(source) != reports['Windows']['offlineResourceReuse']['sourceArchive']:
        raise ValueError('Corresponding source does not match inspected offline resources')
    inputs.append((source,source.name))
    output.mkdir()
    files=[]
    for original,name in inputs:
        target=output/name;shutil.copyfile(original,target);files.append(identity(target))
    manifest={'version':VERSION,'commit':provenance['commit'],'tree':provenance['tree'],
        'reviewedSourceCommit':REVIEWED_SOURCE,'validationRun':run_url,'validationMode':MODE,
        'rebuiltAfterValidation':False,'scope':{'fullRegression':False,'installerExecuted':False,
        'visualAcceptance':False,'focusedTests':True,'staticPackageInspection':True},
        'targetedValidation':reports,'files':files}
    (output/'RELEASE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (output/'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in sorted(output.iterdir())))
    return manifest

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-source',action='store_true')
    parser.add_argument('--select-ci',action='store_true')
    parser.add_argument('--artifacts',type=Path)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--run-url')
    args=parser.parse_args()
    if args.select_ci: print(select_ci())
    elif args.check_source: print(json.dumps(check_source()))
    elif all((args.artifacts,args.output,args.run_url)): print(json.dumps(prepare(args.artifacts,args.output,args.run_url)))
    else: parser.error('Provide --check-source or --artifacts, --output and --run-url')
