import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
const source = readFileSync(new URL('./windows-application-smoke.ps1', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
describe.each(['LF', 'CRLF'])('bounded Windows core failure evidence with %s checkout (source contracts, not native acceptance)', (ending) => {
  const checkout = ending === 'CRLF' ? source.replace(/\n/g, '\r\n') : source;
  const wrapper = checkout.replace(/\r\n/g, '\n');
  it('routes only exact capture phases to the existing capture diagnostic', () => {
    const route = wrapper.slice(wrapper.indexOf('static bool IsCoreCaptureFailure('), wrapper.indexOf('// Failure-only generated-fixture'));
    const expression = route.match(/return ([\s\S]+?);/)![1].replaceAll('(string)', '');
    const capture = new Function('stage', 'kind', 'operation', `return ${expression};`);
    for (const [stage, kind, operation, expected] of [
      ['first-region-ocr', null, null, true], ['display-change-cancellation', null, null, true],
      ['latest-intent-workflows', 'pinned-ocr-restart', 'capture', true],
      ['latest-intent-workflows', 'ocr-to-selection', 'capture', true],
      ['latest-intent-workflows', 'ocr-to-selection', 'selection', false],
      ['latest-intent-workflows', 'pinned-selection-one', null, false],
      ['latest-intent-workflows', 'pinned-selection-two', null, false],
      ['first-selected-text-shortcut', null, null, false], ['unknown-ocr', null, null, false],
    ]) expect(capture(stage, kind, operation)).toBe(expected);
    expect(wrapper).toContain('report.ContainsKey("screenshotPinPreparation")||IsCoreCaptureFailure(report)');
  });
  it('keeps the exact history oracle and original OCR timeout unchanged', () => {
    const oracle = wrapper.slice(wrapper.indexOf('static bool HasHistory('), wrapper.indexOf('static void KillOwnTree('));
    expect(oracle).toContain('String.Equals((string)entry["text"], source,');
    expect(oracle).not.toContain('.Trim()');
    expect(oracle).not.toContain('ObserveFailed');
    expect(wrapper).toContain('return HasHistory(history, OcrText, "ocr", providerId) && (!customBindings || AppSourceMatches(app.Id, OcrText, true)); }, 50,');
  });
  it('bounds the owned history read and emits comparisons rather than content', () => {
    const evidence = wrapper.slice(wrapper.indexOf('static void ObserveFailedCoreHistory('), wrapper.indexOf('// One read-only export'));
    for (const required of ['MarkerName))==token', 'FileAttributes.ReparsePoint', 'new char[1048577]', 'length<=1048576', 'entries.Length<=16', '++count<=16', 'exactSource', 'trimmedExactSource', 'expectedProviderResult', 'expectedResultMatches', 'providerErrorPresent', 'exactHistoryPredicateMatched', 'trimmedHistoryPredicateMatched', 'mockResultComparisonApplicable', 'parseFailed']) expect(evidence).toContain(required);
    for (const forbidden of ['error.Message', 'Send(', 'SetForegroundWindow(', 'File.Write', 'Clipboard', '=text;', '=resultText;', '=history;', '=providerId;']) expect(evidence).not.toContain(forbidden);
    expect(evidence).toContain('if(exact)evidence["exactSource"]=true');
    expect(evidence).toContain('if(!result.ContainsKey("error")){if(exact)evidence["exactHistoryPredicateMatched"]=true;if(trimmed)evidence["trimmedHistoryPredicateMatched"]=true;}');
    expect(evidence).toContain('server!=null&&result.TryGetValue("text",out resultText)');
  });
  it('snapshots only allowlisted request kinds under the server lock and distinguishes flushed responses', () => {
    const snapshot = wrapper.slice(wrapper.indexOf('public Dictionary<string,object> FailureSnapshot('), wrapper.indexOf('public volatile string Error;'));
    for (const required of ['lock(gate)', 'i<Requests.Count&&i<16', 'Array.IndexOf(allowed,kind)<0', 'flushed.Count>=16', 'responseFlushIsNotClientReceipt', 'boundExceeded', 'acceptedSourceMatches', 'exactExpected', 'trimmedExactExpected']) expect(snapshot).toContain(required);
    expect(snapshot).not.toContain('body[');
    expect(wrapper).toContain('stream.Flush();\n            lock(gate){if(responseFlushedKinds.Count<17)responseFlushedKinds.Add(kind);}');
  });
  it('compares the existing owned-source UIA value only to generated constants and emits no raw value', () => {
    const observation = wrapper.slice(wrapper.indexOf('static void ObserveFailedWorkflow('), wrapper.indexOf('sealed class PinnedVisibilityWatch'));
    for (const required of ['own.Current.ProcessId==app.Id', 'expectedGeneratedSource!=null', 'value.Length<=20000', 'sourceGeneratedCompared', 'sourceExactGenerated', 'sourceTrimmedExactGenerated']) expect(observation).toContain(required);
    expect(observation).toContain('reader.IsAlive&&budget.ElapsedMilliseconds<2000)reader.Join((int)Math.Max(0,2000-budget.ElapsedMilliseconds))');
    expect(observation).not.toMatch(/snapshot\[[^\]]+\]\s*=\s*value\s*;/);
    expect(wrapper).toContain('String.Equals((string)body["q"],canonical,comparison)');
    expect(wrapper).toContain('String.Equals(((string)body["q"]).Trim(),canonical,comparison)');
  });
  it('observes history before process and directory cleanup, without changing the original error', () => {
    const failure = wrapper.indexOf('report["failedStage"]=stage;report["error"] = error.Message;ObserveFailedCoreHistory(');
    expect(failure).toBeGreaterThan(0);
    expect(wrapper.indexOf('KillOwnTree(app);', failure)).toBeGreaterThan(failure);
    expect(wrapper.indexOf('ObserveFailedWorkflow(report,app', failure)).toBeGreaterThan(failure);
  });
});
