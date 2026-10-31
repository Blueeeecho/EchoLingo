import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const source = readFileSync(new URL('./windows-application-smoke.ps1', import.meta.url), 'utf8');
const readiness = source.split('    static bool AppOcrReady(', 2)[1].split('    static void WaitFor(', 1)[0];

// These scalar C# expressions also have JavaScript syntax. Execute the actual
// fixture predicates, not a separately maintained model, without a Win32 desktop.
const readyExpression = readiness.match(/bool ready = ([^;]+);/)![1];
const firstBorderExpression = readiness.match(/actual\.Exists\(delegate\(AppEdge edge\)\{return ([^;]+);\}\)/)![1];
const firstBorderEligible = new Function('edge', 'rejectedHelper', `return ${firstBorderExpression};`) as
  (edge: { ProcessId: number }, rejectedHelper: number) => boolean;
const exactPicker = {
  helper: 202, rejectedHelper: 101, validSource: true,
  screen: { Count: 4 }, hover: { Count: 4 }, oneHelper: true,
  exactGeometry: true, remaining: { Count: 0 }, exactPlanes: true,
  throughPlane: true, rawPlane: true, rawThin: false, rawLoupe: false,
};
const evaluateReady = new Function(...Object.keys(exactPicker), `return ${readyExpression};`);
type Picker = typeof exactPicker;
type Probe = { firstBorder?: number };
function poll(state: Picker, visibleHelpers: number[], elapsed: number, probe: Probe) {
  if (probe.firstBorder === undefined && visibleHelpers.some(ProcessId => firstBorderEligible({ ProcessId }, state.rejectedHelper))) {
    probe.firstBorder = elapsed;
  }
  const ready = evaluateReady(...Object.values(state)) as boolean;
  // Mirrors the mandatory ready-only assertion below, whose source wiring is
  // checked separately. A pending old picker must not reach this assertion.
  if (ready && probe.firstBorder === undefined) throw new Error('Ready capture did not record its first-border timing.');
  return ready;
}

describe('actual Windows app picker generation readiness', () => {
  it('keeps an exact old picker pending before its replacement appears', () => {
    const probe: Probe = {};
    expect(poll({ ...exactPicker, helper: 101 }, [101], 1, probe)).toBe(false);
    expect(probe.firstBorder).toBeUndefined();
    expect(poll(exactPicker, [202], 2, probe)).toBe(true);
    expect(probe.firstBorder).toBe(2);
  });

  it('cannot accept the old picker just because a new border was previously observed', () => {
    const probe: Probe = {};
    expect(poll({ ...exactPicker, oneHelper: false }, [101, 202], 3, probe)).toBe(false);
    expect(probe.firstBorder).toBe(3);
    expect(poll({ ...exactPicker, helper: 101 }, [101], 4, probe)).toBe(false);
    expect(poll(exactPicker, [202], 5, probe)).toBe(true);
    expect(probe.firstBorder).toBe(3);
  });

  it('requires a nonzero helper for cold capture and a different helper for restart', () => {
    expect(evaluateReady(...Object.values({ ...exactPicker, helper: 0, rejectedHelper: 0 }))).toBe(false);
    expect(evaluateReady(...Object.values({ ...exactPicker, helper: 0 }))).toBe(false);
    const probe: Probe = {};
    expect(poll({ ...exactPicker, rejectedHelper: 0 }, [202], 0, probe)).toBe(true);
    expect(probe.firstBorder).toBe(0);
  });

  it.each<[string, Partial<Picker>]>([
    ['source', { validSource: false }],
    ['screen perimeter', { screen: { Count: 3 } }],
    ['hover perimeter', { hover: { Count: 3 } }],
    ['one helper', { oneHelper: false }],
    ['edge geometry', { exactGeometry: false }],
    ['all expected edges', { remaining: { Count: 1 } }],
    ['input planes and magnifier', { exactPlanes: false }],
    ['transparent-skipping hit', { throughPlane: false }],
    ['verified raw hit', { rawPlane: false, rawThin: false, rawLoupe: false }],
  ])('still requires %s', (_name, changes) => {
    expect(poll({ ...exactPicker, ...changes }, [202], 6, {})).toBe(false);
  });

  it('retains timing assertions and independent caller identity/exit gates', () => {
    expect(readiness).toContain('if(ready&&sinceHotkey!=null)');
    expect(readiness).toContain('Assert(probe.ContainsKey("hotkeyToFirstBorderObservedMilliseconds"),"Ready capture did not record its first-border timing.");');
    expect(readiness).toContain('!Double.IsNaN(firstBorder)&&!Double.IsInfinity(firstBorder)&&firstBorder>=0');
    expect(source).toContain('probe,rejectedPid,time)&&Convert.ToUInt32(probe["helperProcessId"])!=rejectedPid;},25,');
    expect(source).toContain('Assert(Convert.ToUInt32(second["helperProcessId"])!=oldPid,');
    expect(source).toContain('return ProcessExited(oldPid);},5,');
  });
});
