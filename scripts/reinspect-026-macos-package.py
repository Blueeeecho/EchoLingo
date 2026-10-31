#!/usr/bin/env python3
"""Reinspect one immutable generated 0.2.6 DMG; never rebuild or launch it."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import zipfile

SOURCE = 'd91b59505f81d766eca25a8cff4764c278542275'
TREE = '2898ee1bad7f1d73d408d2ad5fc136cfc869fe3a'
BUILD_RUN = 'https://github.com/Blueeeecho/EchoLingo/actions/runs/41195400127'
ARTIFACT = {'id': 13041241190, 'name': 'EchoLingo-0.2.6-UNVERIFIED-build-macOS', 'size': 9596150,
            'sha256': 'c877dcf26a6e85d7ee8e3f7682980b20fbb68f3241065efbdb99b86d65377ba8'}
FILES = {
    'EchoLingo.app.tar.gz': (4275008, '49ab083a45b8c1128c698d7e293c7c5041e298a9d0d65b74bbca728d10e2df0c'),
    'EchoLingo_0.2.6_aarch64.dmg': (5349571, '441c7d00fee0701f1942b1e5fc173c79479385d71c8922507fd83163d37c26e7'),
    'inspection.log': (207, '13ecfba8528697b9612c92a43e3cd7705b056de3fd84667d11d973c523d4a120'),
}


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(path):
    with Path(path).open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def extract_inputs(archive, directory):
    require(archive.stat().st_size == ARTIFACT['size'] and digest(archive) == ARTIFACT['sha256'], 'Original artifact bytes changed')
    directory.mkdir()
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        require(len(entries) == 4 and {item.filename for item in entries} == set(FILES) | {'UNVERIFIED-BUILD.json'}, 'Unexpected artifact inventory')
        for item in entries:
            require(not item.is_dir() and item.file_size <= 6_000_000, 'Unexpected artifact member')
            data = bundle.read(item)
            if item.filename in FILES:
                size, sha = FILES[item.filename]
                require(len(data) == size and hashlib.sha256(data).hexdigest() == sha, 'Original build member changed')
            else:
                evidence = json.loads(data)
                require(evidence['sourceCommit'] == SOURCE and evidence['sourceTree'] == TREE and evidence['runUrl'] == BUILD_RUN
                        and evidence['releaseReady'] is False, 'Original build provenance changed')
                require(evidence['files'] == [{'name': name, 'size': value[0], 'sha256': value[1]} for name, value in FILES.items()], 'Original build file pins changed')
            (directory / item.filename).write_bytes(data)
    # This exact generated bundle contains regular files/directories only.
    with tarfile.open(directory / 'EchoLingo.app.tar.gz', 'r:gz') as bundle:
        entries = bundle.getmembers()
        require(len(entries) == 9 and sum(item.size for item in entries) < 9_000_000, 'Unexpected signed bundle inventory')
        seen = set()
        for item in entries:
            path = PurePosixPath(item.name)
            require(not path.is_absolute() and path.parts[0] == 'EchoLingo.app' and '..' not in path.parts
                    and item.name not in seen and (item.isfile() or item.isdir()), 'Unsafe signed bundle member')
            seen.add(item.name)
            target = directory.joinpath(*path.parts)
            if item.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(item) as source, target.open('xb') as output:
                    shutil.copyfileobj(source, output)
                target.chmod(item.mode & 0o777)
    return directory / 'EchoLingo_0.2.6_aarch64.dmg', directory / 'EchoLingo.app/Contents/MacOS/echolingo'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    tooling = Path(__file__).resolve().parents[1]
    source = args.source.resolve(strict=True)
    identity = subprocess.check_output(['git', '-C', source, 'rev-parse', 'HEAD', 'HEAD^{tree}'], text=True).splitlines()
    require(identity == [SOURCE, TREE], 'Wrong original product checkout')
    require(os.environ['GITHUB_REPOSITORY'] == 'Blueeeecho/EchoLingo', 'Wrong repository')
    run_url = f"https://github.com/Blueeeecho/EchoLingo/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    args.output.mkdir()
    installer, application = extract_inputs(args.archive, args.output / 'original')
    spec = importlib.util.spec_from_file_location('candidate_inspector', tooling / 'scripts/inspect-candidate-package.py')
    inspector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inspector)
    checks = inspector.inspect('macOS', installer, application, args.output / 'inspection', run_url,
                               locked_build_passed=True, focused_tests_passed=True, root=source)
    public = args.output / 'candidate'
    public.mkdir()
    shutil.copyfile(installer, public / installer.name)
    subprocess.run(['python3', str(source / 'scripts/verify-candidate-package.py'), '--platform', 'macOS',
                    '--installer', str(public / installer.name), '--application', str(args.output / 'inspection/echolingo'),
                    '--checks-json', str(args.output / 'inspection/checks.json'), '--output', str(public / 'CANDIDATE-MANIFEST.json'),
                    '--run-url', run_url], check=True, cwd=source)
    manifest = {'schemaVersion': 1, 'sourceCommit': SOURCE, 'sourceTree': TREE, 'buildRunUrl': BUILD_RUN,
                'inspectionRunUrl': run_url, 'inspectionCommit': os.environ['GITHUB_SHA'], 'inputArtifact': ARTIFACT,
                'installerSha256': checks['installerSha256'], 'applicationSha256': checks['applicationSha256'],
                'productRebuilt': False, 'binaryModified': False, 'installedAcceptance': False,
                'originalInspectionOutcome': 'failure'}
    (public / 'REINSPECTION-MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Original package bytes passed static reinspection; no build, launch or installed acceptance.')


if __name__ == '__main__':
    main()
