"""Only generated clipboard setup may retry an occupied OS clipboard."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parent / 'windows-selection-native-focus-fixture.cs').read_text()


class NativeFocusClipboardFixtureContract(unittest.TestCase):
    def test_generated_seed_uses_small_bounded_os_retries(self):
        seed = SOURCE.split('static ClipboardSeed Seed()', 1)[1].split('static void CheckSeed(', 1)[0]
        self.assertIn('Clipboard.SetDataObject(data,true,5,20)', seed)
        self.assertIn('GENERATED_SEED_NOT_PUBLISHED', seed)
        self.assertIn('CheckSeed(seed);return seed;', seed)
        self.assertNotIn('catch', seed)

    def test_rich_data_and_helper_acceptance_remain_exact(self):
        check = SOURCE.split('static void CheckSeed(', 1)[1].split('static Dictionary<string,object> Call(', 1)[0]
        for required in ('expected.Length==actual.Length', 'expected[i]==actual[i]',
                         'Object.Equals(current.GetData(format,false),seed.Declared.GetData(format,false))'):
            self.assertIn(required, check)
        self.assertNotIn('catch', check)
        self.assertEqual(SOURCE.count('Dictionary<string,object> reply=Call(helper,assembly)'), 1)
        for required in ('HELPER_SELECTION_NOT_EXACT', 'HELPER_CHANGED_SOURCE_FOCUS',
                         'MANUAL_CTRL_C_EXACT_SELECTION', '{"requiredCases",2}'):
            self.assertIn(required, SOURCE)


if __name__ == '__main__':
    unittest.main()
