"""Fixture source contracts only; real Windows UIA acceptance remains required."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'tests/windows-screenshot-editor-fixture.cs').read_text()


class ScreenshotSettingsCategoryFixtureContract(unittest.TestCase):
    def test_selects_exact_owned_visible_category_before_open(self):
        body = SOURCE.split('static void ScreenshotSelectCaptureSettings(', 1)[1].split('static Dictionary<string,object> ScreenshotOpenGenerated(', 1)[0]
        for required in ['pid==app.Id&&MainWindow(app.Id)==owner', 'IsWindowVisible(owner)',
                         'IsWindowEnabled(owner)', 'ControlType.TabItem',
                         r'"\u8bc6\u522b\u4e0e\u622a\u56fe"', 'matches.Count<=1',
                         '!tab.Current.IsOffscreen&&tab.Current.IsEnabled',
                         'SelectionItemPattern.Pattern', 'if(!selection.Current.IsSelected)selection.Select()',
                         'return selection.Current.IsSelected;']:
            self.assertIn(required, body)
        self.assertEqual(body.count('selection.Select()'), 1)
        for forbidden in ['SendInput', 'AutomationElement.RootElement', '.Invoke()', 'WebView2', 'catch']:
            self.assertNotIn(forbidden, body)
        open_body = SOURCE.split('static Dictionary<string,object> ScreenshotOpenGenerated(', 1)[1].split('static bool ScreenshotPixelsEqual(', 1)[0]
        self.assertLess(open_body.index('ScreenshotSelectCaptureSettings(app,dialogOwner)'),
                        open_body.index('Actual screenshot settings Open action missing.'))
        self.assertIn('ScreenshotOwnOpenDialog(app,dialogOwner,modal)', open_body)
        self.assertIn('ScreenshotFilenameChain', open_body)
        self.assertIn('ScreenshotPixelsEqual', open_body)

    def test_exact_category_matches_production(self):
        navigation = (ROOT / 'src/settings-navigation.ts').read_text()
        self.assertIn("['capture', '识别与截图',", navigation)
        self.assertIn("tab.setAttribute('role', 'tab')", navigation)
        self.assertIn("document.querySelector('#screenshot-settings')", navigation)
        html = (ROOT / 'index.html').read_text()
        self.assertIn('id="screenshot-open-local">打开本地 PNG / JPEG</button>', html)


if __name__ == '__main__':
    unittest.main()
