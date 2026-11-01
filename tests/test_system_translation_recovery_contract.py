"""Source wiring checks; behavior runs in macOS --system-translation-self-test."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'src-tauri/native/macos.swift').read_text()

class SystemTranslationRecoveryContract(unittest.TestCase):
    def test_failed_translation_never_prepares_or_retries(self):
        body = SOURCE.split('func translateWithSystem(', 1)[1].split('struct SystemTranslationPreparationView', 1)[0]
        self.assertEqual(body.count('session.translate(text)'), 1)
        self.assertNotIn('prepareTranslation()', body)
        self.assertIn('trace.failure(error)', body)
        self.assertIn('trace.translationFailureKind(kind)', body)
        failure = body.split('} catch {', 1)[1]
        self.assertNotIn('await ', failure)
        self.assertNotIn('LanguageAvailability()', failure)
        self.assertIn('throw systemTranslationFailure(error)', failure)

    def test_status_keeps_installed_fact_but_enables_explicit_recovery(self):
        self.assertIn('available = !recoveryRequired; requiresSetup = recoveryRequired', SOURCE)
        self.assertIn('recoveryRequired: systemTranslationRecovery.needsPreparation(source: source, target: request.target)', SOURCE)
        body = SOURCE.split('func prepareSystemTranslation(', 1)[1].split('#endif', 1)[0]
        self.assertIn('preparation.show(source: source, target: request.target)', body)
        self.assertIn('if state["status"] as? String == "unsupported"', body)
        self.assertIn('SYSTEM_TRANSLATION_FAILED: 无法确认', body)
        self.assertIn('systemTranslationRecovery.finish(recoveryTicket, outcome: .succeeded)', body)
        self.assertIn('New requests, other pairs or generic errors cleared recovery.', SOURCE)
        self.assertIn('Stale success cleared newer recovery.', SOURCE)

    def test_recovery_is_separate_bounded_and_generation_guarded(self):
        recovery = SOURCE.split('final class SystemTranslationRecovery:', 1)[1].split('func systemTranslationRecoverySelfTest()', 1)[0]
        trace = SOURCE.split('final class SystemTranslationTrace:', 1)[1].split('func systemTranslationTraceSelfTest()', 1)[0]
        self.assertNotIn('requiresPreparation', trace)
        self.assertIn('entries.count < capacity', recovery)
        self.assertIn('entry.generation == ticket.generation', recovery)
        self.assertIn('case .unchanged: break', recovery)
        self.assertIn('Stale failure overwrote successful recovery.', SOURCE)
        self.assertIn('Capacity handling erased unresolved recovery.', SOURCE)
        status = SOURCE.split('func availableSystemTranslation(', 1)[1].split('func systemTargetLanguageMatches', 1)[0]
        self.assertNotIn('.finish(', status)
        self.assertNotIn('.begin(', status)

    def test_rejected_preparation_does_not_supersede_active_operation(self):
        body = SOURCE.split('func prepareSystemTranslation(', 1)[1].split('#endif', 1)[0]
        guard = body.index('guard activeSystemTranslationPreparation == nil')
        begin = body.index('recoveryTicket = try systemTranslationRecovery.begin(')
        show = body.index('activeSystemTranslationPreparation = preparation')
        self.assertLess(guard, begin)
        self.assertLess(begin, show)
        self.assertEqual(body.count('systemTranslationRecovery.begin('), 1)
        self.assertIn('var recoveryTicket: SystemTranslationRecovery.Ticket?', body)
        self.assertIn('entry.generation == ticket.generation, entry.active', SOURCE)
        self.assertIn('entry.active = false', SOURCE)
        self.assertIn('A completed failure ticket was accepted twice.', SOURCE)

    def test_existing_native_job_runs_system_policy_checks(self):
        script = (Path(__file__).resolve().parent / 'macos-native-self-test.sh').read_text()
        self.assertEqual(script.count('swiftc "$repo_root/src-tauri/native/macos.swift"'), 1)
        self.assertEqual(script.count('swiftc "$repo_root/src-tauri/native/macos_ocr.swift"'), 1)
        self.assertIn('--system-translation-self-test', script)
        self.assertIn('systemTranslationTraceRecoveryFixturePassed', script)
        self.assertIn('compiler >= (6, 2) and macos_major >= 26', script)
        self.assertIn('checks.get("translationEngineCalled") is False', script)
        self.assertIn('checks.get("languageDownloadRequested") is False', script)
        self.assertIn('Capable runner skipped installed-only/recovery policy tests', script)

    def test_observations_use_existing_completed_calls_only(self):
        status = SOURCE.split('func availableSystemTranslation(', 1)[1].split('func systemTargetLanguageMatches', 1)[0]
        self.assertEqual(status.count('await LanguageAvailability().status('), 1)
        self.assertLess(status.index('await LanguageAvailability().status('), status.index('availabilityObserved('))
        prepare = SOURCE.split('func prepareSystemTranslation(', 1)[1].split('#endif', 1)[0]
        self.assertLess(prepare.index('try waiter.wait(seconds: 180)'), prepare.index('preparationObserved('))
        self.assertLess(prepare.index('preparationObserved('), prepare.index('} catch {'))
        translate = SOURCE.split('func translateWithSystem(', 1)[1].split('struct SystemTranslationPreparationView', 1)[0]
        self.assertIn('session.sourceLanguage?.minimalIdentifier', translate)
        self.assertIn('session.targetLanguage?.maximalIdentifier', translate)
        self.assertNotIn('await ', translate.split('} catch {', 1)[1])
        self.assertIn('lastCompletedAvailabilityQuery', SOURCE)
        self.assertIn('lastSuccessfulExplicitPreparation', SOURCE)
        self.assertIn('Translation observations lost exact metadata or retained content.', SOURCE)

    def test_diagnostics_remain_content_free(self):
        body = SOURCE.split('final class SystemTranslationTrace:', 1)[1].split('func systemTranslationTraceSelfTest()', 1)[0]
        self.assertIn('if validSystemLanguage(source), validSystemLanguage(target)', body)
        self.assertNotIn('localizedDescription', body)
        self.assertNotIn('native.userInfo', body)
        self.assertNotIn('"availabilityAfterFailure"', body)
        self.assertIn('"translationErrorKind"', body)

if __name__ == '__main__':
    unittest.main()
