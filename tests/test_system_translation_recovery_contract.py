"""Source wiring checks; behavior runs in macOS --system-translation-self-test."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'src-tauri/native/macos.swift').read_text()

class SystemTranslationRecoveryContract(unittest.TestCase):
    def test_retries_only_recreate_installed_sessions_without_preparation(self):
        body = SOURCE.split('func translateWithSystem(', 1)[1].split('struct SystemTranslationPreparationView', 1)[0]
        self.assertEqual(body.count('session.translate(text)'), 1)
        self.assertEqual(body.count('TranslationSession(installedSource:'), 1)
        self.assertLess(body.index('withInstalledSystemTranslationRecovery(trace: trace)'), body.index('TranslationSession(installedSource:'))
        self.assertIn('guard !session.canRequestDownloads', body)
        self.assertNotIn('prepareTranslation()', body)
        self.assertNotIn('LanguageAvailability()', body)
        self.assertNotIn('.activate(', body)
        self.assertIn('trace.failure(finalError)', body)
        self.assertIn('trace.translationFailureKind(kind)', body)
        failure = body.split('} catch {', 1)[1]
        self.assertNotIn('await ', failure)
        self.assertIn('throw systemTranslationFailure(finalError)', failure)
        self.assertIn('Task.isCancelled ? CancellationError() : error', failure)

    def test_injected_retry_policy_is_bounded_and_cancellable(self):
        helper = SOURCE.split('func withInstalledSystemTranslationRecovery<T>(', 1)[1].split('func systemInstalledTranslationContractSelfTest()', 1)[0]
        self.assertIn('let retryDelays: [UInt64] = [1_000_000_000, 4_000_000_000]', helper)
        self.assertIn('for index in 0...retryDelays.count', helper)
        self.assertIn('guard kind == "notInstalled", index < retryDelays.count else { throw error }', helper)
        self.assertIn('Task.sleep(nanoseconds: $0)', helper)
        self.assertGreaterEqual(helper.count('try Task.checkCancellation()'), 4)
        self.assertLess(helper.index('let result = try await attempt()'), helper.index('try Task.checkCancellation()', helper.index('let result =')))
        self.assertIn('try await wait(delay)\n            try Task.checkCancellation()', helper)
        self.assertNotIn('trace.failure(', helper)
        self.assertNotIn('TranslationSession(', helper)
        self.assertNotIn('LanguageAvailability', helper)
        self.assertNotIn('prepareTranslation', helper)

    def test_entire_logical_operation_keeps_one_ticket_and_timeout(self):
        body = SOURCE.split('func translateWithSystem(', 1)[1].split('struct SystemTranslationPreparationView', 1)[0]
        self.assertEqual(body.count('systemTranslationRecovery.begin('), 1)
        success = body.index('systemTranslationRecovery.finish(recoveryTicket, outcome: .succeeded)')
        self.assertGreater(success, body.index('}, onCancel: { session.cancel() })'))
        self.assertIn('try Task.checkCancellation()\n        systemTranslationRecovery.finish', body)
        self.assertEqual(body.count('systemTranslationRecovery.finish('), 2)
        self.assertIn('awaitSystemTranslation(seconds: 45, operationId: request.operationId)', SOURCE)

    def test_retry_behavior_runs_shared_helper_with_real_apple_errors(self):
        fixture = SOURCE.split('func systemInstalledTranslationRetrySelfTest()', 1)[1].split('func systemTranslationStatusPayload(', 1)[0]
        self.assertIn('withInstalledSystemTranslationRecovery(trace: trace', fixture)
        self.assertIn('let notInstalled = TranslationError.notInstalled', fixture)
        self.assertIn('scenario([], attempts: 1, waits: [])', fixture)
        self.assertIn('scenario([notInstalled], attempts: 2, waits: [1_000_000_000])', fixture)
        self.assertIn('scenario([notInstalled, notInstalled], attempts: 3', fixture)
        self.assertIn('scenario([notInstalled, notInstalled, notInstalled, notInstalled], attempts: 3', fixture)
        self.assertIn('TranslationError.alreadyCancelled, CancellationError()', fixture)
        self.assertIn('waitingTask.cancel()', fixture)
        self.assertIn('try await Task.sleep(nanoseconds: delay)', fixture)
        self.assertIn('lateTask.cancel()', fixture)
        self.assertIn('await late.releaseResponse()', fixture)
        self.assertIn('Cancelled stale result retried or cleared preparation state.', fixture)
        self.assertNotIn('TranslationSession(', fixture)
        self.assertNotIn('.translate(', fixture)
        self.assertIn('try await systemInstalledTranslationRetrySelfTest()', SOURCE)

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
        self.assertIn('systemTranslationInstalledRetryFixturePassed', script)
        self.assertIn('systemTranslationInstalledRetryFixtureSkipped', script)
        self.assertIn('compiler >= (6, 2) and macos_major >= 26', script)
        self.assertIn('checks.get("translationEngineCalled") is False', script)
        self.assertIn('checks.get("languageDownloadRequested") is False', script)
        self.assertIn('Capable runner skipped installed-only/recovery policy tests', script)

    def test_release_verifier_requires_executed_retry_fixture(self):
        script = (Path(__file__).resolve().parent / 'macos-native-self-test.sh').read_text()
        verifier = script.split("<<'PY_SYSTEM'\n", 1)[1].split('\nPY_SYSTEM', 1)[0]

        def verify(*, capable=True, strict=True, passed=None, skipped=None):
            checks = {key: True for key in ('systemTranslationPolicyFixturePassed',
                'systemTranslationTraceRecoveryFixturePassed', 'systemTranslationOutputFixturePassed',
                'systemTranslationCancellationFixturePassed')}
            checks.update(translationEngineCalled=False, languageDownloadRequested=False,
                          systemTranslationInstalledOnlyFixturePassed=capable)
            if passed is not None:
                checks['systemTranslationInstalledRetryFixturePassed'] = passed
            if skipped is not None:
                checks['systemTranslationInstalledRetryFixtureSkipped'] = skipped
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'report.json').write_text(json.dumps({'ok': True, 'diagnostics': checks}))
                (root / 'swift.txt').write_text('Apple Swift version 6.2' if capable else 'Apple Swift version 6.1')
                (root / 'macos.txt').write_text('26.0' if capable else '15.0')
                environment = dict(os.environ)
                environment['ECHOLINGO_REQUIRE_SYSTEM_TRANSLATION_RECOVERY'] = '1' if strict else '0'
                return subprocess.run([sys.executable, '-', str(root / 'report.json'), str(root / 'swift.txt'),
                    str(root / 'macos.txt')], input=verifier, text=True, capture_output=True, env=environment)

        for passed, skipped in ((None, None), (False, False), (True, True), (True, None)):
            with self.subTest(passed=passed, skipped=skipped):
                self.assertNotEqual(verify(passed=passed, skipped=skipped).returncode, 0)
        accepted = verify(passed=True, skipped=False)
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        self.assertNotEqual(verify(capable=False, passed=False, skipped=True).returncode, 0)
        unsupported = verify(capable=False, strict=False, passed=False, skipped=True)
        self.assertEqual(unsupported.returncode, 0, unsupported.stderr)
        self.assertIn('checks skipped', unsupported.stdout)

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
        self.assertIn('"firstAttemptFailure"', body)
        self.assertIn('"translationAttemptCount"', body)
        self.assertIn('"scheduledRetryWaitMs"', body)
        self.assertIn('Bounded retry diagnostics lost first failure, leaked content or marked recovery failed.', SOURCE)
        self.assertIn('Late cancellation or retry changed terminal timeout diagnostics.', SOURCE)

    def test_last_failure_is_separate_bounded_and_excludes_cancellation(self):
        trace = SOURCE.split('final class SystemTranslationTrace:', 1)[1].split('func systemTranslationTraceSelfTest()', 1)[0]
        start = trace.split('init() {', 1)[1].split('func phase(', 1)[0]
        phase = trace.split('func phase(', 1)[1].split('func translationAttempt(', 1)[0]
        self.assertIn('private static var lastFailure: [String: Any] = [:]', trace)
        self.assertNotIn('lastFailure', start)
        self.assertNotIn('lastFailure', phase)
        self.assertEqual(trace.count('Self.lastFailure = Self.latest'), 1)
        self.assertIn('if !cancelled && Self.latest["translationErrorKind"] as? String != "cancelled"', trace)
        self.assertIn('snapshot["lastFailure"] = lastFailure', trace)
        self.assertNotIn('latest["lastFailure"]', trace)
        self.assertIn('Success or stale failure erased retained translation failure.', SOURCE)
        self.assertIn('User cancellation erased retained translation failure.', SOURCE)
        self.assertIn('New translation failure was not retained safely.', SOURCE)

    def test_framework_cancellation_is_classified_before_failure_is_retained(self):
        translate = SOURCE.split('func translateWithSystem(', 1)[1].split('struct SystemTranslationPreparationView', 1)[0]
        failure = translate.split('} catch {', 1)[1]
        self.assertLess(failure.index('trace.translationFailureKind(kind)'), failure.index('trace.failure(finalError)'))

if __name__ == '__main__':
    unittest.main()
