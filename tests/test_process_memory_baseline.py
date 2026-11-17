import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('baseline', Path(__file__).resolve().parents[1] / 'scripts/process-memory-baseline.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def row(pid, parent, started='first', path='/app/engine', cpu=1):
    return dict(pid=pid, parent=parent, started=started, path=path, rssBytes=100, privateBytes=40, cpuSeconds=cpu)


class BaselineTests(unittest.TestCase):
    def test_mac_parser_and_cpu_units(self):
        result = m.parse_mac_rows(' 10 1 512 1-02:03:04.50 Tue Nov 17 10:00:00 2026\n')
        self.assertEqual(result[10]['rssBytes'], 512 * 1024)
        self.assertEqual(result[10]['cpuSeconds'], 93784.5)
        self.assertEqual(m.cpu_seconds('00:01.20'), 1.2)
        with self.assertRaises(m.MeasurementError):
            m.parse_mac_rows('unrecognized output')

    def test_descendants_exclude_unrelated_browser(self):
        rows = {1: row(1, 0), 2: row(2, 1), 3: row(3, 2), 4: row(4, 0)}
        self.assertEqual(m.descendants(rows, {1}), {1, 2, 3})

    @patch.object(m.sys, 'platform', 'win32')
    def test_identity_changes_stop_phase(self):
        anchors = {1: {'identity': (1, 'first'), 'path': '/app/engine'}}
        for rows in ({}, {1: row(1, 0, 'second')}, {1: row(1, 0, path='/different')}):
            with self.assertRaises(m.MeasurementError):
                m.select(rows, anchors, {})

    @patch.object(m.sys, 'platform', 'win32')
    def test_reparented_known_child_and_pid_reuse(self):
        anchors = {1: {'identity': (1, 'first'), 'path': '/app/engine'}}
        known = {}
        m.select({1: row(1, 0), 2: row(2, 1)}, anchors, known)
        selected, skipped = m.select({1: row(1, 0), 2: row(2, 0)}, anchors, known)
        self.assertEqual([r['pid'] for r in selected], [1, 2])
        selected, _ = m.select({1: row(1, 0), 2: row(2, 0, 'reused')}, anchors, known)
        self.assertEqual([r['pid'] for r in selected], [1])
        self.assertNotIn('path', selected[0])

    @patch.object(m.sys, 'platform', 'win32')
    def test_unreadable_child_not_silently_counted(self):
        anchors = {1: {'identity': (1, 'first'), 'path': '/app/engine'}}
        selected, skipped = m.select({1: row(1, 0), 2: row(2, 1, path=None)}, anchors, {})
        self.assertEqual(skipped, [2])
        self.assertEqual(len(selected), 1)

    def test_cpu_only_for_same_identity(self):
        selected = [row(1, 0, cpu=3), row(2, 1, started='new', cpu=10)]
        total = m.summarize_sample(selected, {(1, 'first'): 1, (2, 'old'): 0}, 4)
        self.assertEqual(total['cpuPercentOneCoreObservedIntervals'], 50)
        self.assertEqual(total['summedPrivateBytes'], 80)
        self.assertEqual(total['summedRssBytesNotUnique'], 200)
        self.assertNotIn('cpuPercentOneCore', selected[1])
        self.assertIsNone(m.summarize_sample([], {}, 2)['cpuPercentOneCoreObservedIntervals'])

    def test_platform_gate(self):
        with patch.object(m.sys, 'platform', 'linux'):
            with self.assertRaises(m.MeasurementError):
                m.collect()


if __name__ == '__main__':
    unittest.main()
