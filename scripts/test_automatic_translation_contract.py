"""Source contract for dispatch, separate from actual engine acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AutomaticTranslationContract(unittest.TestCase):
    def test_apple_same_language_pair_still_reaches_translation_session(self):
        source = (ROOT / 'src-tauri/native/macos.swift').read_text(encoding='utf-8')
        start = source.index('func translateWithSystem(')
        body = source[start:source.index('\n}', start) + 2]
        self.assertIn('let session = TranslationSession(', body)
        self.assertIn('try await session.translate(text)', body)
        self.assertNotIn('systemLanguagesEquivalent(', body)
        self.assertNotIn('return ["text": text,', body)

    def test_rust_request_path_has_no_original_text_success_shortcut(self):
        source = (ROOT / 'src-tauri/src/main.rs').read_text(encoding='utf-8')
        start = source.index('async fn translate(')
        body = source[start:source.index('\nfn finish_translation(', start)]
        self.assertIn('translation_selection::request_providers(', body)
        self.assertIn('translation::translate_one_streaming(', body)
        self.assertIn('.translate_result(p, text, resolved_source, resolved_target)', body)
        self.assertNotIn('preserved_result(', body)
        self.assertNotIn('Plan::Preserve', body)


if __name__ == '__main__':
    unittest.main()
