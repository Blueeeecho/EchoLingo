import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { imagePoint, selectionRect } from '../src/screenshot-model';
const wrapper = readFileSync(new URL('./windows-application-smoke.ps1', import.meta.url), 'utf8');
const fixture = readFileSync(new URL('./windows-screenshot-editor-fixture.cs', import.meta.url), 'utf8');
describe('actual Windows screenshot fixture source wiring (not native acceptance)', () => {
  it('retains the ephemeral runner/STA/owned-directory guards and exact helper identity', () => {
    for (const required of ["$env:GITHUB_ACTIONS -ne 'true'", "$env:RUNNER_ENVIRONMENT -ne 'github-hosted'", '[Environment]::UserInteractive', 'ApartmentState]::STA', 'ClaimDirectory(roaming, token, owned)', 'RequireNativeChild', 'NativeHash(actual)==NativeCaptureHash']) expect(wrapper).toContain(required);
    expect(wrapper).toContain("'SCREENSHOT_EDITOR_SCOPE:");
    expect(wrapper).toContain('settings["screenshotSaveDirectory"]=screenshotOutput');
    expect(wrapper).toContain('public static partial class EchoLingoApplicationSmoke');
    expect(wrapper).toContain("'windows-screenshot-editor-fixture.cs'");
  });
  it('runs real F1/native picker and UIAutomation, with pixel assertions rather than mocked IPC', () => {
    for (const required of ['Key(0x70,false),Key(0x70,true)', 'AppOcrReady(form,app.Id,form.Handle', 'InvokePattern.Pattern', 'Clipboard.GetImage()', 'ScreenshotPng(firstPath,copied)', 'GetPixel(x,y).ToArgb()==expected.GetPixel(x,y).ToArgb()', 'ScreenshotCancelFileDialog', 'SourceTopmostModal']) {
      expect(fixture + wrapper).toContain(required);
    }
    expect(fixture).not.toContain('__TAURI_INTERNALS__');
    for (const name of ['escape-cancel', 'drag-redact-crop-copy-save-twice', 'click-window-close-cancel-confirm']) expect(fixture).toContain(`"${name}"`);
  });
  it('bounds exported data and asserts no overwrite, hidden PNG payload, OCR, provider traffic or history', () => {
    for (const required of ['bytes.Length<=32*1024*1024', 'position==bytes.Length', 'kind!="eXIf"', 'kind!="iTXt"', 'File.ReadAllBytes(firstPath)', 'CaptureNumber(after,"ocrInvocationCount")==0', 'server.Connections==0&&server.Count==0&&server.Error==null', 'Deserialize<object[]>(File.ReadAllText(history)).Length==0', 'desktopDirectoryWritten', 'no global packet capture', 'screenshotLocalOpenRequiredCases', 'sourceBytesUnchanged', 'FileMode.CreateNew', 'screenshotEditorSurvivedOwnedFocusLoss']) expect(fixture).toContain(required);
    expect(wrapper).toContain('payload.ContainsKey("ocrInvocationCount")');
  });
  it('dispatches pressed tools through one typed Toggle action, never blind clicks', () => {
    expect(fixture).toContain('TogglePattern.Pattern');
    expect(fixture).toContain('ToggleState.Off');
    expect(fixture).toContain('ToggleState.On');
    expect(fixture).toContain('Assert(tool&&element.TryGetCurrentPattern');
    expect(fixture).toContain('no repeated input sent');
  });
  it('rounds physical pointer targets inward without changing expected image-pixel rectangles', () => {
    expect(fixture).toContain('Math.Ceiling(bounds.X+first.X');
    expect(fixture).toContain('Math.Floor(bounds.X+last.X');
    for (const origin of [100, 100.25, 100.5, 100.75]) for (const scale of [1, 1.25, 1.5, 2]) {
      const bounds = { x: origin, y: origin, width: 640 * scale, height: 110 * scale };
      const size = { width: 640, height: 110 };
      const first = { x: Math.ceil(origin + 10 * scale), y: Math.ceil(origin + 10 * scale) };
      const last = { x: Math.floor(origin + 80 * scale), y: Math.floor(origin + 70 * scale) };
      expect(selectionRect(imagePoint(first, bounds, size), imagePoint(last, bounds, size), size)).toEqual({ x: 10, y: 10, width: 70, height: 60 });
    }
  });
  it('cleans failed runs only after locked generation and exact generated-content ownership checks', () => {
    for (const required of ['FRESH_EMPTY_CLIPBOARD_REQUIRED', 'Guid.NewGuid()', 'ScreenshotClipboardPolicyTests()', 'ScreenshotOwnedClipboard.Cleanup()', 'screenshotOwnedClipboardCleared', 'generation-changed-preserved', 'content-changed-preserved', 'GetClipboardSequenceNumber()==generation&&GetClipboardOwner()==owner', 'LockedDigest(format)==digest', 'ScreenshotPixelsEqual(actual,expected)', 'ScreenshotPixelsEqual(actual,ScreenshotExpectedWindow)', 'ScreenshotCroppedPixels', 'DwmFlush()', 'control.Enabled=false']) expect(fixture).toContain(required);
    expect(fixture).not.toContain('Clipboard.Clear()');
    expect(fixture).not.toContain('Clipboard.SetText(');
    expect(fixture).toContain('return ScreenshotReclaim(SameGeneration,SameContent,EmptyClipboard)');
    expect(fixture).toContain('if(!sameGeneration())return "generation-changed-preserved"');
    expect(fixture).toContain('finally{CloseClipboard();}');
  });
  it('refuses ambiguous accessibility names and releases an owned edit gesture promptly', () => {
    expect(fixture).toContain('Assert(matches.Count<=1');
    expect(fixture).toContain('finally{if(ForegroundPid()==app.Id)');
    expect(fixture).toContain('ForegroundPid()==app.Id&&GetForegroundWindow()==modal');
  });
});
