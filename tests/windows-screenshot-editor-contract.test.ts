import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
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
  it('refuses ambiguous accessibility names and releases an owned edit gesture promptly', () => {
    expect(fixture).toContain('Assert(matches.Count<=1');
    expect(fixture).toContain('finally{if(ForegroundPid()==app.Id)');
    expect(fixture).toContain('ForegroundPid()==app.Id&&GetForegroundWindow()==modal');
  });
});
