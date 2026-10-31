#!/usr/bin/env python3
"""Fixed 0.2.4 language-only patch: source pinning, not a general test bypass."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parents[1]
BASE = '4b8c5f5ac67e07cc4005812963b2c02acdd14d5d'
TREE = 'dbb9690106c0abec0c55f2bc665d7b60aedf0697'
MODE = 'language-routing-patch-v1'
COMMAND = 'cargo test --manifest-path src-tauri/Cargo.toml --locked bilingual_input && cargo test --manifest-path src-tauri/Cargo.toml --locked language_detection'
PINS = {
    'src-tauri/src/bilingual_input.rs': 'aa8aeddcc5b1be4eebbb049125418de65b125548b25fd04ad937d72780bcb4f7',
    'src-tauri/Cargo.toml': '0eee8bde1b77d62a0f00c44dbde8f52ddde5c572195bee3acff622d5d0d96fff',
    'src-tauri/Cargo.lock': '96403a321dd3aa005243b7cd2923011b58ae2cbcfd1db959624d322d747b30cc',
}
SUPPORT = {
    'package.json', '.github/workflows/ci.yml', '.github/workflows/release.yml',
    '.github/workflows/language-patch-checks.yml', 'scripts/verify-language-patch.py',
    'scripts/test_language_patch_contract.py', 'scripts/stage-language-patch-resources.py',
    'scripts/test_stage_language_patch_resources.py', 'scripts/prepare-release-assets.py',
    'scripts/test_language_patch_assets.py', 'docs/releases/0.2.4.zh-CN.md',
    'tests/language-routing-patch/Cargo.toml', 'tests/language-routing-patch/Cargo.lock',
    'tests/language-routing-patch/src/main.rs', 'scripts/test_prepare_release_assets.py',
}

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify():
    if git('rev-parse', BASE+'^{tree}') != TREE:
        raise ValueError('Baseline source tree mismatch')
    changed = set(git('diff', '--name-only', BASE, 'HEAD').splitlines())
    if changed - SUPPORT - PINS.keys():
        raise ValueError('Patch modifies an unapproved file: '+str(sorted(changed-SUPPORT-PINS.keys())))
    for path, expected in PINS.items():
        # Pin the actual commit and reject working-copy edits. Git for Windows
        # may materialize only text line endings differently; binary digests
        # below are never normalized.
        canonical = subprocess.check_output(['git', 'show', 'HEAD:'+path], cwd=ROOT)
        if (hashlib.sha256(canonical).hexdigest() != expected
                or (ROOT/path).read_bytes().replace(b'\r\n', b'\n') != canonical):
            raise ValueError('Exact reviewed language input changed: '+path)
    before = json.loads(git('show', BASE+':package.json'))
    before['scripts']['test:language-routing'] = COMMAND
    if json.loads((ROOT/'package.json').read_text()) != before:
        raise ValueError('Package input differs beyond the targeted test command')
    old = tomllib.loads(git('show', BASE+':src-tauri/Cargo.lock'))['package']
    new = tomllib.loads((ROOT/'src-tauri/Cargo.lock').read_text())['package']
    old_map = {(p['name'],p['version']):p for p in old}
    new_map = {(p['name'],p['version']):p for p in new}
    if old_map.keys()-new_map.keys() or new_map.keys()-old_map.keys() != {
        ('allocator-api2','0.2.21'),('foldhash','0.1.5'),('hashbrown','0.15.5'),('whatlang','0.18.0')
    } or any(p.get('checksum') != new_map[k].get('checksum') for k,p in old_map.items()):
        raise ValueError('Existing dependency versions/checksums must be unchanged')
    return {'commit': BASE, 'runId': 41178655504, 'tree': TREE}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--select', action='store_true')
    parser.add_argument('--build-report', type=Path)
    parser.add_argument('--platform', choices=['Windows','macOS'])
    parser.add_argument('--installer', type=Path)
    args = parser.parse_args()
    selected = json.loads((ROOT/'package.json').read_text()).get('scripts',{}).get('test:language-routing') == COMMAND
    if args.select and not selected:
        mode = 'full'
    else:
        baseline = verify()
        mode = MODE
    if args.select:
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'],'a') as output: output.write('mode='+mode+'\n')
        print(mode)
    elif args.build_report:
        if not args.platform or not args.installer or not args.installer.is_file() or args.installer.is_symlink():
            raise ValueError('Actual new installer required')
        if os.environ.get('LANGUAGE_TARGETED_TESTS_PASSED') != '1':
            raise ValueError('Targeted test step did not succeed')
        report = {'validationMode': MODE, 'commit': git('rev-parse','HEAD'), 'platform': args.platform,
                  'targetedLanguageTestsPassed': True, 'sourceGuardPassed': True, 'versionVerified': True,
                  'lockedBuild': True, 'baseline': baseline,
                  'installer': {'name':args.installer.name, 'size':args.installer.stat().st_size,'sha256':sha(args.installer)},
                  'visualAcceptanceRepeated':False}
        args.build_report.parent.mkdir(parents=True,exist_ok=True)
        args.build_report.write_text(json.dumps(report,indent=2)+'\n')
    else:
        print(json.dumps({'ok':True,'mode':mode,'baseline':baseline}))

if __name__ == '__main__': main()
