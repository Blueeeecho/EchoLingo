#!/usr/bin/env python3
"""Fixed release-run attachment diagnosis only; never build or attest release acceptance."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '8ade30e0ed9c5d18c37768cd93ceb72ccfe4603c'
RUN = 41281391324
ORIGINAL_INSPECTOR_SHA = 'f98408dbf82a1ab6cf23817669cbeab3e17e8b3d02c719028643e74792925878'
PATCHED_INSPECTOR_SHA = '16ac78b8ff2d4c3f8cc51ddea14c0f4eb9f665faf3ab081ff063f9da291e3447'
ARTIFACTS = {
    'dmg.zip': (13074130151, 5378384, 'ae7df8549e32cfb7b51d12713b4edeb8917abbd590e4352612168a52ff5573a7'),
    'app.zip': (13073169414, 4327455, '5410896a3a6694e2e81d3175f1b0ba1a7639f84189bc7aad3547fa4b1ed89144'),
}
DMG_SHA = 'c19b1a27d62b4a8c9e24154515f95d5a2b06ba53c7a46283520a777aabf38ad4'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != 'darwin':
        raise ValueError('Actual macOS is required')
    spec = importlib.util.spec_from_file_location('inspector', ROOT / 'scripts/inspect-candidate-package.py')
    inspector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inspector)
    expected = subprocess.check_output(['git', '-C', str(ROOT), 'show', SOURCE + ':scripts/inspect-candidate-package.py'])
    inspector.require(hashlib.sha256(expected).hexdigest() == ORIGINAL_INSPECTOR_SHA, 'Original inspector identity mismatch')
    inspector.require(inspector.sha256(ROOT / 'scripts/inspect-candidate-package.py') == PATCHED_INSPECTOR_SHA, 'Diagnostic must use only the exact reviewed prefix-parser patch')
    for filename, (_, size, digest) in ARTIFACTS.items():
        path = inspector.regular_file(args.inputs / filename)
        inspector.require(path.stat().st_size == size and inspector.sha256(path) == digest, 'Pinned artifact bytes mismatch')
    inspector.require(not args.output.exists() and not args.output.is_symlink(), 'Diagnostic output must be new')
    args.output.mkdir(parents=True)
    dmg = args.output / 'EchoLingo_0.2.8_aarch64.dmg'
    with zipfile.ZipFile(args.inputs / 'dmg.zip') as archive:
        entries = archive.infolist()
        inspector.require(len(entries) == 1 and entries[0].filename == 'dmg/EchoLingo_0.2.8_aarch64.dmg'
                          and entries[0].file_size == 5405948, 'Unexpected original DMG archive')
        data = archive.read(entries[0])
        inspector.require(hashlib.sha256(data).hexdigest() == DMG_SHA, 'Original DMG hash mismatch')
        with dmg.open('xb') as stream:
            stream.write(data)
    original_command = inspector.checked_command
    observations = []

    def capture(command, **kwargs):
        # The reviewed inspector retains stdin, arguments, deadlines, output bounds,
        # strict parsing and its scoped finally-detach. Only copy this tool's result.
        check = kwargs.pop('check', True)
        result = original_command(command, check=False, **kwargs)
        if Path(str(command[0])).name == 'hdiutil':
            verb = str(command[1])
            inspector.require(verb in ('verify', 'attach', 'detach'), 'Unexpected diagnostic verb')
            number = len(observations)
            (args.output / f'{number}-{verb}.stdout').write_bytes(result.stdout)
            (args.output / f'{number}-{verb}.stderr').write_bytes(result.stderr)
            observations.append({'verb': verb, 'exit': result.returncode,
                                 'stdoutBytes': len(result.stdout), 'stderrBytes': len(result.stderr),
                                 'stdoutSha256': hashlib.sha256(result.stdout).hexdigest(),
                                 'stderrSha256': hashlib.sha256(result.stderr).hexdigest()})
        if check:
            inspector.require(result.returncode == 0, inspector.command_failure(result))
        return result

    inspector.checked_command = capture
    report = {'diagnosticOnly': True, 'originalSource': SOURCE, 'originalRun': RUN,
              'originalInspectorSha256': ORIGINAL_INSPECTOR_SHA, 'patchedInspectorSha256': PATCHED_INSPECTOR_SHA,
              'formalReleaseAcceptance': False, 'artifacts': ARTIFACTS,
              'dmgSha256': DMG_SHA, 'commands': observations, 'strictAttachmentPassed': False}
    failed = False
    try:
        # Own-license verification is performed by readonly_dmg before attach.
        # No application is executed, installed, rebuilt or re-signed.
        with inspector.readonly_dmg(dmg, args.output / 'mount'):
            report['strictAttachmentPassed'] = True
    except Exception as error:
        failed = True
        report['primaryError'] = str(error)
        report['errorType'] = type(error).__name__
    finally:
        report['dmgUnchanged'] = inspector.sha256(dmg) == DMG_SHA
        (args.output / 'diagnostic.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    inspector.require(report['dmgUnchanged'], 'Original DMG bytes changed')
    print(json.dumps(report))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
