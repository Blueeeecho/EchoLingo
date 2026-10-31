import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import ts from 'typescript';

// Execute the actual registered callback, without initializing unrelated Tauri
// services. Browser integration coverage lives in frontend-interactions.mjs.
function themeListener() {
  const source = readFileSync(new URL('../src/main.ts', import.meta.url), 'utf8');
  const parsed = ts.createSourceFile('main.ts', source, ts.ScriptTarget.Latest, true);
  const statement = parsed.statements.find(node => node.getText(parsed).startsWith("$<HTMLSelectElement>('#theme-select').addEventListener"));
  if (!statement) throw new Error('Theme listener registration is missing');
  return ts.transpile(statement.getText(parsed), { target: ts.ScriptTarget.ES2022 });
}

describe('queued theme preference', () => {
  it('retains a newer choice when an older save re-renders the same control', async () => {
    let listener!: (event: { target: typeof control }) => void;
    const control = { value: 'light', addEventListener: (_name: string, callback: typeof listener) => { listener = callback; } };
    let release!: () => void;
    const held = new Promise<void>(resolve => { release = resolve; });
    let queue = Promise.resolve(), writes: string[] = [], settings = { theme: 'light' };
    const run = (task: () => Promise<void>) => { void task(); };
    const updateSettings = (mutate: (next: typeof settings) => void) => {
      queue = queue.then(async () => {
        const next = { ...settings }; mutate(next); writes.push(next.theme);
        if (writes.length === 1) await held;
        settings = next; control.value = settings.theme;
      });
      return queue;
    };
    new Function('$', 'run', 'updateSettings', themeListener())(() => control, run, updateSettings);
    control.value = 'dark'; listener({ target: control });
    await Promise.resolve();
    expect(writes).toEqual(['dark']);
    control.value = 'system'; listener({ target: control });
    release(); await queue;
    expect(writes).toEqual(['dark', 'system']);
    expect(settings.theme).toBe('system');
    expect(control.value).toBe('system');
  });
});
