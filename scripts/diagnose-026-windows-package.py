#!/usr/bin/env python3
"""Compare immutable generated installer bytes; do not launch or rebuild them."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE_SHA = '4787f328c08f8b9e4afd9a2881efcac192047cc38e73c5a9ae3add1b86116618'
SOURCE = 'd91b59505f81d766eca25a8cff4764c278542275'
TREE = '2898ee1bad7f1d73d408d2ad5fc136cfc869fe3a'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def sections(data):
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional = pe + 24
    opt_size = struct.unpack_from('<H', data, pe + 20)[0]
    result = []
    for index in range(count):
        offset = optional + opt_size + index * 40
        name = data[offset:offset + 8].rstrip(b'\0').decode('ascii', errors='replace')
        length, start = struct.unpack_from('<II', data, offset + 16)
        result.append({'name': name, 'offset': start, 'size': length, 'sha256': sha(data[start:start + length])})
    return {'peOffset': pe, 'checksumOffset': optional + 64, 'checksum': struct.unpack_from('<I', data, optional + 64)[0],
            'sections': result}


def main():
    temporary = Path(os.environ['RUNNER_TEMP'])
    archive = temporary / 'original-windows-build.zip'
    assert archive.stat().st_size == 79796541 and sha(archive.read_bytes()) == ARCHIVE_SHA
    output = temporary / 'windows-package-byte-diagnosis'
    output.mkdir()
    expected = {'EchoLingo_0.2.6_x64-setup.exe', 'echolingo.exe', '7z-listing.txt', 'inspection.log', 'UNVERIFIED-BUILD.json'}
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        assert len(entries) == len(expected) and {item.filename for item in entries} == expected
        manifest = json.loads(bundle.read('UNVERIFIED-BUILD.json'))
        assert manifest['sourceCommit'] == SOURCE and manifest['sourceTree'] == TREE and manifest['releaseReady'] is False
        pins = {item['name']: item for item in manifest['files']}
        assert set(pins) == expected - {'UNVERIFIED-BUILD.json'}
        for item in entries:
            assert item.file_size <= 100_000_000 and not item.is_dir()
            data = bundle.read(item)
            if item.filename in pins:
                assert len(data) == pins[item.filename]['size'] and sha(data) == pins[item.filename]['sha256']
            (output / item.filename).write_bytes(data)
    spec = importlib.util.spec_from_file_location('inspector', ROOT / 'scripts/inspect-candidate-package.py')
    inspector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inspector)
    original = (output / 'echolingo.exe').read_bytes()
    listing = inspector.checked_command([inspector.tool('7z'), 'l', '-slt', '-sccUTF-8', '--', output / 'EchoLingo_0.2.6_x64-setup.exe']).stdout.decode('utf-8')
    member = inspector.parse_7z_listing(listing, len(original))
    target = output / 'extracted-echolingo.exe'
    inspector.extract_windows_member(inspector.tool('7z'), output / 'EchoLingo_0.2.6_x64-setup.exe', member, target)
    extracted = target.read_bytes()
    repeated = output / 'repeated-echolingo.exe'
    inspector.extract_windows_member(inspector.tool('7z'), output / 'EchoLingo_0.2.6_x64-setup.exe', member, repeated)
    version = inspector.checked_command([inspector.tool('7z'), 'i']).stdout.decode('utf-8', errors='replace').splitlines()[:8]
    offsets = [index for index, (a, b) in enumerate(zip(original, extracted)) if a != b]
    ranges = []
    for offset in offsets:
        if ranges and offset == ranges[-1][1] + 1:
            ranges[-1][1] = offset
        else:
            ranges.append([offset, offset])
    report = {'schemaVersion': 1, 'sourceCommit': SOURCE, 'sourceTree': TREE, 'buildRun': 41195400127,
              'inputArtifact': 13040982741, 'archiveSha256': ARCHIVE_SHA, 'literalMember': member['Path'],
              'extractorVersion': version, 'extractorSha256': sha(Path(inspector.tool('7z')).read_bytes()),
              'repeatedExtractionMatches': sha(repeated.read_bytes()) == sha(extracted),
              'original': {'size': len(original), 'sha256': sha(original), **sections(original)},
              'extracted': {'size': len(extracted), 'sha256': sha(extracted), **sections(extracted)},
              'differingBytes': len(offsets), 'rangeCount': len(ranges), 'firstRanges': ranges[:64], 'lastRanges': ranges[-16:],
              'differenceSamples': [{'offset': offset, 'original': original[offset:offset + 8].hex(),
                                     'extracted': extracted[offset:offset + 8].hex()} for offset in offsets[:32]],
              'packageAccepted': False, 'appExecuted': False, 'productRebuilt': False}
    (output / 'BYTE-DIAGNOSIS.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
