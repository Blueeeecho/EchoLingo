#!/usr/bin/env python3
"""Opt-in, read-only process-set sampling. No app launch, arguments or user content."""
from __future__ import annotations
import argparse
import ctypes
import datetime as dt
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time


class MeasurementError(RuntimeError):
    pass


def cpu_seconds(value):
    days, clock = value.split('-', 1) if '-' in value else ('0', value)
    parts = clock.split(':')
    if len(parts) not in (2, 3):
        raise MeasurementError('Invalid CPU time')
    return int(days) * 86400 + float(parts[-1]) + int(parts[-2]) * 60 + (int(parts[0]) * 3600 if len(parts) == 3 else 0)


def parse_mac_rows(output):
    rows = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) != 9:
            raise MeasurementError('Unexpected macOS process table format')
        pid, parent, rss = map(int, fields[:3])
        rows[pid] = dict(pid=pid, parent=parent, rssBytes=rss * 1024,
                         cpuSeconds=cpu_seconds(fields[3]), started=' '.join(fields[4:]))
    return rows


def mac_path(pid):
    lib = ctypes.CDLL('/usr/lib/libproc.dylib')
    lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    lib.proc_pidpath.restype = ctypes.c_int
    buf = ctypes.create_string_buffer(4096)
    if lib.proc_pidpath(pid, buf, len(buf)) <= 0:
        raise MeasurementError('Process path unavailable')
    return os.fsdecode(buf.value)


def collect():
    if sys.platform == 'darwin':
        output = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,rss=,time=,lstart='],
                                capture_output=True, text=True, check=True, env={**os.environ, 'LC_ALL': 'C'}).stdout
        return parse_mac_rows(output)
    if sys.platform == 'win32':
        # No CommandLine, environment, title, settings, screen or input data.
        script = r'''$ErrorActionPreference='Stop'; @(Get-CimInstance Win32_Process | ForEach-Object {
          [pscustomobject]@{pid=[int]$_.ProcessId; parent=[int]$_.ParentProcessId;
            started=if ($_.CreationDate) {$_.CreationDate.ToUniversalTime().ToString('o')} else {''};
            path=$_.ExecutablePath; rssBytes=[long]$_.WorkingSetSize;
            privateBytes=[long]$_.PrivatePageCount; handles=[long]$_.HandleCount;
            cpuSeconds=([double]$_.KernelModeTime + [double]$_.UserModeTime)/10000000}
        }) | ConvertTo-Json -Compress'''
        shell = str(Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe')
        output = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-Command', script],
                                capture_output=True, text=True, check=True).stdout
        values = json.loads(output)
        return {int(row['pid']): row for row in (values if isinstance(values, list) else [values])}
    raise MeasurementError('Native macOS or Windows is required; Linux numbers are not comparable')


def canonical(path):
    return os.path.normcase(os.path.realpath(path))


def identity(row):
    return row['pid'], row['started']


def descendants(rows, anchors):
    chosen = set(anchors)
    while True:
        expanded = chosen | {pid for pid, row in rows.items() if row['parent'] in chosen}
        if expanded == chosen:
            return chosen
        chosen = expanded


def checked(row, expected=None):
    path = row.get('path') if sys.platform == 'win32' else mac_path(row['pid'])
    if not path or not row.get('started'):
        raise MeasurementError('Process identity unavailable')
    if expected and canonical(path) != canonical(expected):
        raise MeasurementError('Process executable does not match the supplied path')
    return canonical(path)


def select(rows, anchors, known):
    """Never continue through a reused root/helper PID. Remember attributed descendants."""
    for pid, anchor in anchors.items():
        row = rows.get(pid)
        if row is None or identity(row) != anchor['identity']:
            raise MeasurementError('Root or explicitly supplied helper exited or changed identity; end this phase')
        checked(row, anchor['path'])
    current = descendants(rows, anchors)
    # A previously observed child may be reparented; only retain exact identity.
    current |= {pid for pid, entry in known.items() if pid in rows and identity(rows[pid]) == entry['identity']}
    selected, skipped = [], []
    for pid in sorted(current):
        row = rows[pid]
        try:
            path = checked(row)
        except MeasurementError:
            skipped.append(pid)
            continue
        prior = known.get(pid)
        if prior and prior['identity'] == identity(row) and prior['path'] != path:
            skipped.append(pid)
            continue
        known[pid] = {'identity': identity(row), 'path': path}
        # Emit basename, not full local path; do not write unrelated process inventory.
        selected.append({key: row[key] for key in ('pid', 'parent', 'started', 'rssBytes', 'privateBytes', 'handles', 'cpuSeconds') if key in row} |
                        {'executable': os.path.basename(path), 'attribution': 'explicit' if pid in anchors else 'observed-descendant'})
    return selected, skipped


def summarize_sample(selected, previous, elapsed):
    cpu = []
    for row in selected:
        old = previous.get(identity(row))
        if old is not None and elapsed > 0:
            row['cpuPercentOneCore'] = max(0, row['cpuSeconds'] - old) / elapsed * 100
            cpu.append(row['cpuPercentOneCore'])
    return {'processCount': len(selected), 'summedRssBytesNotUnique': sum(r['rssBytes'] for r in selected),
            'summedPrivateBytes': sum(r['privateBytes'] for r in selected) if selected and all('privateBytes' in r for r in selected) else None,
            'cpuPercentOneCoreObservedIntervals': sum(cpu) if cpu else None}


def helper(value):
    pid, separator, path = value.partition('=')
    if not separator or not pid.isdigit() or int(pid) <= 0 or not Path(path).is_absolute():
        raise argparse.ArgumentTypeError('Use PID=/absolute/executable/path (Windows: PID=C:\\path\\app.exe)')
    return int(pid), path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', required=True, type=int, help='PID of the already-running EchoLingo main process')
    parser.add_argument('--executable', required=True, help='Exact absolute path of that built executable')
    parser.add_argument('--helper', action='append', default=[], type=helper, help='Explicit verified helper PID=path, e.g. non-descendant WebKit service')
    parser.add_argument('--phase', required=True, help='Neutral phase label; do not include translated text')
    parser.add_argument('--samples', type=int, default=30)
    parser.add_argument('--interval', type=float, default=2)
    parser.add_argument('--output', required=True, type=Path, help='New JSONL file; existing files will never be overwritten')
    args = parser.parse_args()
    if args.pid <= 0 or not Path(args.executable).is_absolute() or not 2 <= args.samples <= 3600 or not 0.5 <= args.interval <= 3600:
        parser.error('Use a positive PID, absolute executable path, 2..3600 samples and 0.5..3600 seconds interval')
    if len({pid for pid, _ in args.helper} | {args.pid}) != len(args.helper) + 1:
        parser.error('Duplicate root/helper PID')
    rows = collect()
    anchors = {}
    for pid, path in [(args.pid, args.executable), *args.helper]:
        if pid not in rows:
            raise MeasurementError('Specified process not running')
        anchors[pid] = {'identity': identity(rows[pid]), 'path': checked(rows[pid], path)}
    metadata = {'schemaVersion': 1, 'platform': platform.platform(), 'phase': args.phase,
                'utc': dt.datetime.now(dt.timezone.utc).isoformat(), 'intervalSeconds': args.interval,
                'limitations': ['Observed process set, NOT guaranteed whole-application footprint. Non-descendant OS/XPC helpers require explicit verified attribution.',
                    'Summed RSS includes shared pages and is NOT unique physical memory. macOS physical footprint is not measured.',
                    'CPU excludes periods before a process is first observed. Short-lived children between samples can be missed.',
                    'Sampling overhead and OS allocator caches affect results; do not infer a leak from one elevated RSS sample.']}
    known, previous, previous_time = {}, {}, time.monotonic()
    with args.output.open('x', encoding='utf-8') as out:
        out.write(json.dumps({'metadata': metadata}, ensure_ascii=False) + '\n')
        for index in range(args.samples):
            if index:
                time.sleep(args.interval)
            try:
                rows = collect()
                selected, skipped = select(rows, anchors, known)
                now = time.monotonic()
                record = {'sample': index, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                          'elapsedSeconds': now - previous_time, 'processes': selected,
                          'unverifiedPids': skipped, 'totals': summarize_sample(selected, previous, now - previous_time)}
                out.write(json.dumps(record, ensure_ascii=False) + '\n'); out.flush()
                previous = {identity(row): row['cpuSeconds'] for row in selected}; previous_time = now
            except (MeasurementError, subprocess.SubprocessError, OSError, ValueError):
                out.write(json.dumps({'sample': index, 'error': 'Native collection or process identity changed; phase incomplete'}) + '\n')
                raise MeasurementError('Sampling stopped; output marks the phase incomplete') from None
    print(f'Wrote {args.samples} samples. Read metadata limitations before comparing totals.')


if __name__ == '__main__':
    try:
        main()
    except (MeasurementError, subprocess.SubprocessError, OSError, ValueError) as exc:
        print(f'Measurement failed: {exc}', file=sys.stderr)
        sys.exit(1)
