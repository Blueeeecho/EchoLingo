"""Prepare the explicitly authorized macOS-only 0.2.1 release from pinned tested bytes."""
import hashlib
import json
import pathlib
import subprocess
import sys
import zipfile

SOURCE = '67672e98379408afa933cd2f62c3f006f3bec838'
RUN = 41024566310
ARTIFACT = 12963525648
ARCHIVE_SHA = '672b8f43959e5051bdbe4437b5b6bd63b13868202ed401763975cf673e5552bd'
DMG_SHA = '52640e24b30f2979cf0299e99cb42496b3056251df616d451a75b04841d99146'
ENTRY = 'dmg/EchoLingo_0.2.1_aarch64.dmg'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def tested_dmg(archive):
    if digest(archive) != ARCHIVE_SHA:
        raise ValueError('Pinned artifact digest mismatch')
    import io
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        if z.namelist() != [ENTRY] or z.getinfo(ENTRY).file_size != 4918215:
            raise ValueError('Unexpected artifact inventory or size')
        data = z.read(ENTRY)
    if digest(data) != DMG_SHA:
        raise ValueError('Tested DMG digest mismatch')
    return data

def prepare(archive_path, output, publisher):
    if len(publisher) != 40 or any(c not in '0123456789abcdef' for c in publisher):
        raise ValueError('Invalid publisher commit')
    data = tested_dmg(pathlib.Path(archive_path).read_bytes())
    output = pathlib.Path(output)
    if output.exists():
        raise ValueError('Refusing to overwrite publication inputs')
    output.mkdir()
    dmg = output / 'EchoLingo_0.2.1_macos_arm64.dmg'
    dmg.write_bytes(data)
    source = output / 'EchoLingo_0.2.1_source.zip'
    subprocess.run(['git', 'archive', '--format=zip', '--prefix=EchoLingo-0.2.1-source/', '-o', str(source.resolve()), SOURCE], check=True)
    files = [{'name': p.name, 'size': p.stat().st_size, 'sha256': digest(p.read_bytes())} for p in [dmg, source]]
    manifest = {'version': '0.2.1', 'releaseScope': 'macos-only', 'commit': SOURCE, 'sourceCommit': SOURCE,
                'publisherCommit': publisher, 'platforms': ['macos-arm64'],
                'windows': {'published': False, 'latestPublishedVersion': '0.2.0', 'reason': 'Windows resize acceptance is unresolved'},
                'verification': {'runId': RUN, 'runUrl': f'https://github.com/Blueeeecho/EchoLingo/actions/runs/{RUN}',
                                 'macosJobId': 123959559790, 'frontendJobId': 123959559755,
                                 'macosJobConclusion': 'success', 'frontendJobConclusion': 'success',
                                 'overallRunConclusion': 'failure', 'windowsAcceptancePassed': False,
                                 'artifactId': ARTIFACT, 'artifactArchiveSha256': ARCHIVE_SHA}, 'files': files}
    (output / 'RELEASE-MANIFEST.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    (output / 'SHA256SUMS.txt').write_text(''.join(f'{digest(p.read_bytes())}  {p.name}\n' for p in sorted(output.iterdir())))
    return manifest

if __name__ == '__main__':
    prepare(*sys.argv[1:])
