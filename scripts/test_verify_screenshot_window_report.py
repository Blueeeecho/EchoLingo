import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest

PATH = Path(__file__).with_name('verify-screenshot-window-report.py')
spec = importlib.util.spec_from_file_location('verify_screenshot_window_report', PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def complete():
    cases = []
    for generation, mode in enumerate(module.EXPECTED_MODES, 1):
        rejected = mode in module.REJECTED
        native = {'ok': not rejected}
        if rejected:
            native['error'] = module.REJECTED[mode] + ' generated fixture rejection'
        case = {'mode': mode, 'ok': True, 'generation': generation,
                'hoverWindowOutlineVerified': True, 'zeroUnderlyingInput': True,
                'helperDiagnostics': native,
                'hostSessionClosure': {'event': 'closed', 'generation': generation,
                    'sessionCloseCalled': True, 'helperDeadlineKilled': False,
                    'hostThreadId': 1, 'helperExitCode': 1 if rejected else 0}}
        if not rejected:
            case.update(imageWidth=80, imageHeight=60)
        cases.append(case)
    return {'ok': True, 'cases': cases, 'screenshotPurpose': True,
            'productionModulesImported': True, 'userContentCaptured': False,
            'clipboardAccessed': False, 'ocrInvoked': False}


class ScreenshotWindowReport(unittest.TestCase):
    def rejects(self, report):
        with self.assertRaises(ValueError):
            module.verify(json.dumps(report))

    def test_complete_and_bom_log_passes(self):
        report = complete()
        self.assertEqual(module.verify('\ufeffcompiler output\n' + json.dumps(report)), report)

    def test_missing_or_duplicate_reports_fail(self):
        with self.assertRaises(ValueError): module.verify('no report')
        with self.assertRaises(ValueError): module.verify(json.dumps(complete()) + '\n' + json.dumps(complete()))

    def test_exact_case_inventory_matches_actual_native_fixture(self):
        fixture = (PATH.parent.parent / 'tests/windows-screenshot-window-smoke.ps1').read_text()
        loop = re.search(r'foreach\(string kind in new string\[\]\{([^}]+)\}', fixture)
        self.assertEqual(tuple(re.findall(r'"([^"]+)"', loop[1])), module.EXPECTED_MODES)

    def test_missing_duplicate_reordered_or_failed_case_fails(self):
        for mode in ('missing', 'duplicate', 'reordered', 'failed'):
            report = complete()
            if mode == 'missing': report['cases'].pop()
            if mode == 'duplicate': report['cases'][1] = copy.deepcopy(report['cases'][0])
            if mode == 'reordered': report['cases'].reverse()
            if mode == 'failed': report['cases'][0]['ok'] = False
            self.rejects(report)

    def test_missing_scope_or_input_ownership_fails(self):
        for field in ('screenshotPurpose', 'productionModulesImported', 'userContentCaptured', 'clipboardAccessed', 'ocrInvoked'):
            report = complete(); del report[field]; self.rejects(report)
        for field in ('hoverWindowOutlineVerified', 'zeroUnderlyingInput'):
            report = complete(); report['cases'][0][field] = False; self.rejects(report)

    def test_generation_must_be_exact_integer(self):
        for value in (True, 0, 2, '1'):
            report = complete(); report['cases'][0]['generation'] = value; self.rejects(report)

    def test_missing_or_killed_closure_fails(self):
        for field, value in [('event', 'other'), ('generation', 2), ('sessionCloseCalled', False),
                             ('helperDeadlineKilled', True), ('hostThreadId', 0), ('helperExitCode', True)]:
            report = complete(); report['cases'][0]['hostSessionClosure'][field] = value; self.rejects(report)
        report = complete(); del report['cases'][0]['hostSessionClosure']; self.rejects(report)

    def test_native_outcome_and_dimensions_must_match_the_case(self):
        report = complete(); report['cases'][0]['helperDiagnostics']['ok'] = False; self.rejects(report)
        report = complete(); report['cases'][3]['helperDiagnostics']['error'] = 'UNRELATED:'; self.rejects(report)
        report = complete(); report['cases'][0]['imageWidth'] = True; self.rejects(report)
        report = complete(); report['cases'][3]['imageWidth'] = 5; self.rejects(report)

    def test_image_or_text_payloads_are_not_report_evidence(self):
        for key in ('imageBase64', 'text'):
            report = complete(); report['cases'][0]['helperDiagnostics'][key] = 'fixture'; self.rejects(report)


if __name__ == '__main__':
    unittest.main()
