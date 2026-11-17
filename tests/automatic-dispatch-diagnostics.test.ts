import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
import ts from 'typescript';

function diagnosticFixture(enabled: boolean, pending = 0) {
  const code = readFileSync(new URL('../src/main.ts', import.meta.url), 'utf8');
  const parsed = ts.createSourceFile('main.ts', code, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(node => ts.isFunctionDeclaration(node) && node.name?.text === 'recordInputDiagnostic');
  if (!declaration) throw new Error('Missing production diagnostic');
  const invoke = vi.fn().mockResolvedValue(undefined);
  const factory = new Function('invoke', 'inputDiagnosticsEnabled', 'inputDiagnosticsPending', `
    let inputDiagnosticSequence = 0, inputDiagnosticQueue = Promise.resolve();
    const source = {value: 'private captured text'}, document = {activeElement: null};
    const translationPresentation = {epoch: 8}, generation = 12, sourceComposing = false, translating = false, settingsReady = true;
    ${ts.transpile(declaration.getText(parsed), { target: ts.ScriptTarget.ES2022 })}
    return {record: recordInputDiagnostic, flush: () => inputDiagnosticQueue};`);
  return { invoke, ...factory(invoke, enabled, pending) };
}

describe('automatic dispatch diagnostic metadata', () => {
  it('remains opt-in and bounded', async () => {
    for (const [enabled, pending] of [[false, 0], [true, 32]] as const) {
      const fixture = diagnosticFixture(enabled, pending);
      fixture.record('automaticDispatchSkipped', undefined, {epoch: 7, generation: 11}, 'generationChanged');
      await fixture.flush();
      expect(fixture.invoke).not.toHaveBeenCalled();
    }
  });
  it('reports a fixed reason without text or error messages', async () => {
    const fixture = diagnosticFixture(true);
    fixture.record('automaticDispatchSkipped', undefined, {epoch: 7, generation: 11}, 'generationChanged');
    await fixture.flush();
    expect(fixture.invoke).toHaveBeenCalledTimes(1);
    const [command, {record}] = fixture.invoke.mock.calls[0];
    expect(command).toBe('record_frontend_input_diagnostic');
    expect(record).toMatchObject({stage: 'automaticDispatchSkipped', skipReason: 'generationChanged', requestEpoch: 7, requestGeneration: 11});
    expect(JSON.stringify(record)).not.toContain('private captured text');
    expect(record).not.toHaveProperty('text');
    expect(record).not.toHaveProperty('error');
  });
  it('does not throw or retry after diagnostic transmission failure', async () => {
    const fixture = diagnosticFixture(true);
    fixture.invoke.mockRejectedValue(new Error('diagnostic unavailable'));
    fixture.record('automaticDispatchSkipped', undefined, {epoch: 7, generation: 11}, 'modalActive');
    await expect(fixture.flush()).resolves.toBeUndefined();
    expect(fixture.invoke).toHaveBeenCalledTimes(1);
  });
});
