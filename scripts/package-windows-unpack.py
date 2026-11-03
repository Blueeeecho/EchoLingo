#!/usr/bin/env python3
"""Create an allowlisted unpack-and-run ZIP, never a snapshot of user/build folders."""
import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import shutil
import stat
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCOPE_BASE = '3cc3e9fe7077e3bfea0c85e2714db9cacf087192'
SCOPE_FILES = {
    '.gitattributes', '.github/workflows/ci.yml', '.github/workflows/windows-unpack.yml',
    'packaging/windows/Start-EchoLingo.cmd', 'packaging/windows/README-Windows.txt',
    'scripts/package-windows-unpack.py', 'scripts/test_package_windows_unpack.py',
    'tests/windows-unpack-smoke.ps1', 'docs/windows-unpack.zh-CN.md', 'docs/build.md',
    'src-tauri/src/main.rs', 'src-tauri/src/startup_launch.rs',
}


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def regular(path):
    path = Path(path).absolute()
    for item in [*path.parents, path]:
        info = item.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
            raise ValueError('Links/reparse points are not package inputs')
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError('Missing or empty package input: ' + path.name)
    return path


def checked_name(name):
    if (not name or '\\' in name or any(part in ('', '.', '..') or part[-1:] in (' ', '.')
        or any(c in ':*?<>|"' or ord(c) < 32 for c in part) for part in name.split('/'))):
        raise ValueError('Unsafe package member')
    return name


def write_archive(path, files):
    names = set()
    for name, source in files.items():
        checked_name(name)
        if name.casefold() in names:
            raise ValueError('Case-aliased package member')
        names.add(name.casefold())
        regular(source)
    with zipfile.ZipFile(path, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, source in sorted(files.items()):
            archive.write(source, name)
    with zipfile.ZipFile(path) as archive:
        if set(archive.namelist()) != set(files) or archive.testzip() is not None:
            raise ValueError('ZIP round-trip verification failed')
        for name, source in files.items():
            with archive.open(name) as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != digest(source):
                    raise ValueError('ZIP member differs from package input')


def audit_module():
    spec = importlib.util.spec_from_file_location('unpack_audit', ROOT/'scripts/audit-windows-resources.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def package(application, source_archive, output):
    application, source_archive = regular(application), regular(source_archive)
    if application.read_bytes()[:2] != b'MZ':
        raise ValueError('Application is not a Windows executable')
    version = json.loads((ROOT/'package.json').read_text())['version']
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?', version):
        raise ValueError('Unsafe package version')
    auditor = audit_module()
    inventory = auditor.inventory(staged=True)
    resources = ROOT/'resources/offline-translation'
    notices = json.loads((resources/'license-files.json').read_text(encoding='utf-8'))
    license_names = {entry['path'] for entry in notices['files']} | {'licenses/' + name for name in auditor.REQUIRED_NOTICES}
    mapping = json.loads((ROOT/'src-tauri/tauri.windows.conf.json').read_text())['bundle']['resources']
    files = {'echolingo.exe': application, 'LICENSE.txt': ROOT/'LICENSE'}
    for source, destination in mapping.items():
        if source.endswith('/'):
            if destination != 'offline-translation/licenses/':
                raise ValueError('Unexpected directory resource mapping')
            for name in sorted(license_names):
                files['offline-translation/' + checked_name(name)] = regular(resources/name)
        else:
            files[destination] = regular(ROOT/'src-tauri'/source)
    for name in ('Start-EchoLingo.cmd', 'README-Windows.txt'):
        files[name] = ROOT/'packaging/windows'/name
    # The source offer requires a corresponding source archive, not a placeholder.
    with zipfile.ZipFile(source_archive) as archive:
        for name in ('scripts/offline-engine/main.cpp', 'scripts/offline-engine/sources.lock.json'):
            if archive.read(name).replace(b'\r\n', b'\n') != (ROOT/name).read_bytes().replace(b'\r\n', b'\n'):
                raise ValueError('Offline engine source does not match the packaged inputs')
    output.mkdir(parents=True, exist_ok=False)
    archive = output/f'EchoLingo_{version}_windows_x64-unpack.zip'
    write_archive(archive, files)
    source = output/'EchoLingo-offline-engine-source.zip'
    shutil.copyfile(source_archive, source)
    manifest = {'formatVersion': 1, 'version': version, 'kind': 'windows-unpack',
                'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'webview2': 'external-evergreen-runtime-required', 'userDataPortable': False,
                'resourceAudit': inventory,
                'files': [{'path': name, 'size': path.stat().st_size, 'sha256': digest(path)}
                          for name, path in sorted(files.items())],
                'archives': [{'name': path.name, 'size': path.stat().st_size, 'sha256': digest(path)}
                             for path in (archive, source)]}
    (output/'WINDOWS-ZIP-MANIFEST.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    sums = [*manifest['archives'], {'name': 'WINDOWS-ZIP-MANIFEST.json', 'sha256': digest(output/'WINDOWS-ZIP-MANIFEST.json')}]
    (output/'SHA256SUMS.txt').write_text(''.join(f"{entry['sha256']}  {entry['name']}\n" for entry in sums), encoding='utf-8')
    print(json.dumps({'archive': archive.name, 'files': len(files), 'bytes': archive.stat().st_size}))


def check_scope():
    subprocess.run(['git', 'merge-base', '--is-ancestor', SCOPE_BASE, 'HEAD'], cwd=ROOT, check=True)
    changed = set(subprocess.check_output(['git', 'diff', '--name-only', SCOPE_BASE, 'HEAD'], cwd=ROOT, text=True).splitlines())
    if not changed or changed-SCOPE_FILES:
        raise ValueError('Unpack-only checks cannot cover production or unrelated changes')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--application', type=Path)
    parser.add_argument('--source-archive', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--check-scope', action='store_true')
    args = parser.parse_args()
    if args.check_scope:
        check_scope()
    elif all((args.application, args.source_archive, args.output)):
        package(args.application, args.source_archive, args.output)
    else:
        parser.error('Supply --application, --source-archive and --output')


if __name__ == '__main__':
    main()
