"""Source contracts for packaged UI readiness, not Windows runtime evidence."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class WindowsUnpackReadinessContract(unittest.TestCase):
    def test_general_controls_match_current_settings(self):
        source = (ROOT / 'tests/windows-unpack-smoke.ps1').read_text()
        ready = source.split('public static bool Ready(int pid) {', 1)[1].split("\n}\n'@", 1)[0]
        self.assertIn('AutomationElement.ProcessIdProperty,pid', ready)
        self.assertIn('if(w.Current.IsOffscreen)continue;', ready)
        self.assertIn('ControlType.TabItem', ready)
        self.assertIn(r'"\u5e38\u89c4"', ready)
        self.assertIn('ControlType.ComboBox', ready)
        self.assertIn(r'"\u754c\u9762\u4e3b\u9898"', ready)
        self.assertIn('!tab.Current.IsOffscreen && tab.Current.IsEnabled', ready)
        self.assertIn('!theme.Current.IsOffscreen && theme.Current.IsEnabled', ready)
        self.assertNotIn('ControlType.Button', ready)
        navigation = (ROOT / 'src/settings-navigation.ts').read_text()
        html = (ROOT / 'index.html').read_text()
        self.assertIn("let current: SettingsCategory = 'general'", navigation)
        self.assertIn("['general', '常规',", navigation)
        self.assertIn("tab.setAttribute('role', 'tab')", navigation)
        self.assertIn('<span>界面主题</span><select id="theme-select">', html)

    def test_packaged_runtime_and_hash_gates_remain_required(self):
        source = (ROOT / 'tests/windows-unpack-smoke.ps1').read_text()
        for requirement in [
            'Archive identity mismatch.', 'Package file bytes changed.',
            'Settings WebView UI did not become ready.',
            'Expected local WebView profile missing.',
            'Second launch did not forward to existing app.',
            '[UnpackDesktop]::Ready($application.Id)',
            'Check-Payload; $report.packageUnchangedAfterRun = $true',
        ]:
            self.assertIn(requirement, source)


if __name__ == '__main__':
    unittest.main()
