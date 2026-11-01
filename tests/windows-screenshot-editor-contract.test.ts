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
    for (const name of ['escape-cancel', 'inplace-drag-copy-recapture-save-twice', 'click-window-copy-then-cancel']) expect(fixture).toContain(`"${name}"`);
  });
  it('matches exact current in-place crop dimensions without a phase label', () => {
    const editor = readFileSync(new URL('../src/screenshot-editor.ts', import.meta.url), 'utf8');
    const template = editor.match(/\$\('#overlay-info'\)\.textContent = model \? `([^`]+)`/)?.[1];
    const matcher = fixture.slice(fixture.indexOf('static bool ScreenshotInplaceDimensionsMatch('), fixture.indexOf('static AutomationElement ScreenshotButton('));
    const labels = matcher.match(/pixels\.Width\+"([^"]*)"\+pixels\.Height/);
    expect(template).toBeDefined(); expect(labels).not.toBeNull();
    const actualLabel = `624${JSON.parse(`"${labels![1]}"`)}94`;
    expect(actualLabel).toBe(template!.replace('${model.size.width}', '624').replace('${model.size.height}', '94'));
    expect(matcher).toContain('AutomationElement dimensions=Element(editor,');
    expect(matcher).toContain('dimensions!=null&&!dimensions.Current.IsOffscreen');
    expect(matcher).not.toMatch(/Contains\(|StartsWith\(/);
    expect(fixture.match(/ScreenshotInplaceDimensionsMatch\(editor,cropped\)/g)).toHaveLength(2);
    expect(fixture).toContain('new Size(selected.Width-16,selected.Height-16)');
    expect(fixture).toContain('},10,"Actual pixel crop dimensions did not render before export.",app)');
    expect(fixture).toContain('},10,"Fresh cropped save pixels were not ready.",app)');
  });
  it('uses exact visible compact file actions and dimensions without changing export semantics', () => {
    const html = readFileSync(new URL('../screenshot.html', import.meta.url), 'utf8');
    const decoded = fixture.replace(/\\u([0-9a-fA-F]{4})/g, (_, hex: string) => String.fromCharCode(parseInt(hex, 16)));
    for (const [id, label] of [['copy-image', '复制图片'], ['save-image', '保存图片']]) {
      expect(html).toMatch(new RegExp(`id="${id}"[^>]*aria-label="${label}"`));
      expect(decoded).toContain(`ScreenshotButton(editor,"${label}")`);
    }
    expect(decoded).not.toContain('ScreenshotInvoke(app,editor,"复制")');
    expect(decoded).not.toContain('ScreenshotInvoke(app,editor,"保存")');
    expect(decoded).not.toContain('ScreenshotButton(editor,"复制")');
    expect(decoded).not.toContain('ScreenshotButton(editor,"保存")');
    expect(decoded).toContain('closes?"复制截图并完成":"复制图片"');
    expect(fixture).toContain('copy.Current.IsEnabled&&!copy.Current.IsOffscreen&&ScreenshotInplaceDimensionsMatch(editor,expected.Size)');
    expect(fixture).not.toContain('expected.Height+" px"');
    for (const oracle of ['Repeated standalone Save overwrote its original local image.', 'Native local image Open changed generated decoded pixels.', 'Second same-session Save did not number its collision without overwriting first output.']) expect(fixture).toContain(oracle);
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
  it('claims only its immediate native seed publication after close and reports bounded phase evidence', () => {
    for (const required of ['seed-publication-close', 'sequenceBeforeSet', 'sequenceAfterSet', 'sequenceBeforeClose', 'sequenceAfterClose', 'sequenceOnReopen', 'sequenceAfterRead', 'seedAttempt', 'copyAttempt', 'copyPhase', 'leaseFormat', 'Observations.Count<96', 'ownerIsGeneratedSource', 'formatsMatch', 'contentMatches', 'observed!=0&&observed==after&&own&&formats&&content', 'Never rebase a later changed generation', 'SeedUnchanged()', 'next!=1&&next!=7&&next!=13&&next!=16']) expect(fixture).toContain(required);
    expect(fixture).not.toContain('Clipboard.GetText()');
    expect(fixture).toContain('bool same=lockedRead&&digest!=null');
    expect(fixture).toContain('RecordState("seed-verified-close")');
    expect(fixture).toContain('RecordState("image-verified-close")');
  });
  it('observes asynchronous Copy with stable-generation reads and never resends the UIA action', () => {
    expect(fixture).toContain('before!=0&&before!=generation&&before==after');
    expect(fixture).toContain('StableImageRead(generation,generation)');
    expect(fixture).toContain('StableImageRead(generation,after)){result.Dispose();result=null;return false;}');
    expect(fixture).toContain('if(!StableImageRead(observedGeneration,current))return false;');
    expect(fixture).toContain('if(!StableImageRead(observedGeneration,GetClipboardSequenceNumber()))return false;');
    const copy = fixture.slice(fixture.indexOf('static Bitmap ScreenshotClipboard('), fixture.indexOf('static void ScreenshotPng('));
    expect(copy.match(/ScreenshotInvoke\(/g)).toHaveLength(1);
    expect(copy.indexOf('ScreenshotInvoke(')).toBeLessThan(copy.indexOf('WaitFor(delegate'));
    expect(copy).toContain('},10,');
  });
  it('executes the actual C# stable-read predicate against pending, racing and complete generations', () => {
    // This integer/boolean expression is shared syntax in C# and JavaScript;
    // extract the implementation rather than test a separately copied formula.
    const expression = fixture.match(/public bool StableImageRead\(uint before,uint after\)\{bool stable=([^;]+);/)?.[1];
    expect(expression).toBeDefined();
    const stable = new Function('generation', 'before', 'after', `return ${expression};`) as (generation: number, before: number, after: number) => boolean;
    for (const [before, after, expected] of [[10, 10, false], [10, 15, false], [15, 15, true], [15, 16, false], [0, 0, false]] as const) expect(stable(10, before, after)).toBe(expected);
  });
  it('retains strict post-cancel pin readiness and reports bounded preparation failure evidence', () => {
    expect(fixture).toContain('report["screenshotPinCaptureAttempt"]=result');
    expect(fixture).toContain('report["screenshotPinPreparation"]=preparation');
    expect(fixture).toContain('return editor!=IntPtr.Zero&&IsWindowVisible(editor)&&canvas&&overlays==0');
    expect(fixture).toContain('},25,"Web solid action did not retain');
    expect(wrapper).toContain('report.ContainsKey("inputPlaneStyleFailure")||report.ContainsKey("screenshotPinPreparation")');
    const observation = fixture.slice(fixture.indexOf('static void ScreenshotPreparationObservation'), fixture.indexOf('static Func<Dictionary<string,object>> ScreenshotCaptureHealth'));
    for (const field of ['editorFound', 'editorVisible', 'helperExited', 'editorPhysicalBounds', 'mainVisible', 'knownActionErrorCode', 'nativeViewportGateFailed']) expect(observation).toContain(field);
    expect(observation).toContain('own.Current.ProcessId==app.Id');
    expect(observation).toContain('AutomationElement.AutomationIdProperty,"toast"');
    expect(observation).toContain('observation["knownActionErrorCode"]=code');
    expect(observation).not.toMatch(/observation\[[^\]]+\]=message\s*;/);
    for (const forbidden of ['Send(', 'SetForegroundWindow(', 'CopyFromScreen(', 'ValuePattern']) expect(observation).not.toContain(forbidden);
  });
  it('records native handoff foreground before cleanup without refocusing to manufacture a pass', () => {
    const pin = fixture.slice(fixture.indexOf('static Dictionary<string,object> ScreenshotPinCase('), fixture.indexOf('static void ScreenshotEditorWorkflow('));
    expect(pin).toContain('RequireForeground(form);result["initialEditorShowPreservedSourceForeground"]=true');
    for (const field of ['foregroundBeforePinInvoke', 'foregroundAfterPinInvoke', 'foregroundDuringPinHandoff', 'foregroundAtVisibleHandoff', 'foregroundAtPinFailure']) expect(pin).toContain(field);
    expect(pin).toContain('!IsWindowVisible(editor)&&AppOverlays(app.Id)==0&&ProcessExited(helper)');
    expect(pin).toContain('Assert(Convert.ToBoolean(foreground["isZero"])||Convert.ToBoolean(foreground["isGeneratedSource"]),"Pin handoff changed foreground to a non-source window.")');
    expect(pin).toContain('return Convert.ToBoolean(foreground["isGeneratedSource"]);');
    expect(pin).toContain('},20,"Pin handoff did not show decoded reference and dismiss capture.",app)');
    const handoff = pin.slice(pin.indexOf('result["foregroundAfterPinInvoke"]'));
    expect(handoff).toContain('if(!annotated)RequireForeground(form);Assert(ScreenshotPinTopmost(pin)');
    for (const forbidden of ['SetForegroundWindow(', 'form.Activate(', 'AllowSetForegroundWindow(', 'AttachThreadInput(']) expect(handoff).not.toContain(forbidden);
  });
  it('exercises actual pin HWND lifecycle and bounded generated pixels without mocked IPC', () => {
    for (const value of ['ScreenshotPinCase(', 'ScreenshotPins(app.Id)', 'ScreenshotPinTopmost(pin)', 'ScreenshotPinToggle(app,pin,true,result)', 'ScreenshotPinToggle(app,pin,false,result)', 'SetWindowPos(pin,IntPtr.Zero', '!IsWindow(pin)&&ScreenshotPins(app.Id).Count==0', 'ScreenshotPinPixels(app,pin,selected,annotated)', 'new Bitmap(3,3)', 'ScreenshotOwnedClipboard.SeedUnchanged()', 'inplace-pin-passive-physical', 'inplace-pin-annotated-active-editor']) expect(fixture).toContain(value);
    expect(wrapper).toContain('[switch]$ScreenshotPinTests');
    expect(fixture).toContain('if(ScreenshotPinOnly)');
    expect(fixture).not.toContain('__TAURI_INTERNALS__');
  });
  it('records bounded native toggle state even when visibility is lost without relaxing acceptance', () => {
    const toggle = fixture.slice(fixture.indexOf('static void ScreenshotPinToggle('), fixture.indexOf('static void ScreenshotPinPixels('));
    for (const field of ['exists', 'visible', 'topmost', 'expectedLabelPresent', 'priorLabelPresent', 'expectedControlDisabled', 'priorControlDisabled']) expect(toggle).toContain(`observation["${field}"]`);
    expect(toggle).toContain('result[before?"nativeUnpinObservation":"nativeRepinObservation"]=observation');
    expect(toggle).toContain('return visible&&topmost!=before&&expected!=null;');
    expect(toggle).toContain('},10,"Pin UI toggle did not change native WS_EX_TOPMOST.",app)');
    expect(toggle.match(/toggle\.Toggle\(\)/g)).toHaveLength(1);
    for (const forbidden of ['SetForegroundWindow(', 'SetWindowPos(', '.Current.Name', '.Current.Value']) expect(toggle).not.toContain(forbidden);
  });
  it('separates untouched physical pinning from intentionally active annotation without focus restoration', () => {
    const click = fixture.slice(fixture.indexOf('static void ScreenshotWebAction('), fixture.indexOf('static void ScreenshotInteractAfterCapture('));
    for (const required of ['ScreenshotWebPoint(form,app,editor,center)', 'current.Current.BoundingRectangle.Contains(center.X,center.Y)', '0x08000000L', 'Send(new INPUT[]{down,up})']) expect(click).toContain(required);
    const owned = fixture.slice(fixture.indexOf('static void ScreenshotWebPoint('), fixture.indexOf('static void ScreenshotWebDrag('));
    for (const required of ['MoveGenerated(form,point);RequireForeground(form)', 'GetAncestor(WindowFromPoint(point),2)', 'pid==app.Id', 'target==editor']) expect(owned).toContain(required);
    for (const forbidden of ['ScreenshotInvoke(', 'SetForegroundWindow(', 'SetFocus(', 'Thread.Sleep(']) expect(click).not.toContain(forbidden);
    const pin = fixture.slice(fixture.indexOf('static Dictionary<string,object> ScreenshotPinCase('), fixture.indexOf('static void ScreenshotEditorWorkflow('));
    expect(pin).toContain('IntPtr main=MainWindow(app.Id)');
    expect(pin).toContain('if(annotated)ScreenshotInvoke(');
    expect(pin).toContain('else ScreenshotWebAction(form,app,helper,"pin",result)');
    expect(pin).toContain('if(annotated)return true;');
    expect(pin).toContain('!Convert.ToBoolean(foreground["isPin"])&&!Convert.ToBoolean(foreground["isMain"])');
    expect(pin).toContain('ScreenshotInteractAfterCapture(app,editor,result)');
    expect(pin).not.toContain('SetForegroundWindow(');
    expect(pin).not.toContain('form.Activate(');
    expect(fixture).toContain('report["screenshotPinRequiredCases"]=2;report["screenshotPinPassedCases"]=2');
    expect(fixture).toContain('new object[]{passive,pinned}');
    expect(fixture).toContain('annotated?Color.FromArgb(228,93,104):Color.FromArgb(23,101,199)');
  });
  it('classifies only exact native adjustment roles while cleanup still counts every visible role', () => {
    const roles = wrapper.slice(wrapper.indexOf('static string NativeAdjustmentRole'), wrapper.indexOf('static int[] RectValue'));
    for (const required of ['EchoLingoCaptureResizeHandle', 'EchoLingoCaptureAction:', 'Unknown titled native capture role', 'if(NativeAdjustmentRole(window)==null)count++']) expect(roles).toContain(required);
    const all = wrapper.slice(wrapper.indexOf('static List<AppEdge> AppOverlayWindows'), wrapper.indexOf('static bool IsInputPlane'));
    expect(all).toContain('string role=NativeAdjustmentRole(window)');
    expect(all).toContain('Every visible role is still returned');
    expect(all).toContain('result.Add(new AppEdge');
  });
  it('keeps Web adjustment and first-stroke capture on the same owned editor', () => {
    for (const required of ['ScreenshotWaitAdjustment(', 'ScreenshotWebMoveResize(', 'webAdjustmentGeometryRestored', 'webInitialToolSelected', 'ProcessExited(helper)', 'ScreenshotRetainedEditor(', 'adjustmentDidNotCapturePixels', 'toolSelectionDidNotCapturePixels']) expect(fixture).toContain(required);
    const adjustment = fixture.slice(fixture.indexOf('static void ScreenshotWaitAdjustment('), fixture.indexOf('static void ScreenshotRecordCaptureCounts('));
    expect(adjustment).not.toContain('CopyFromScreen(');
    expect(adjustment).not.toContain('SetForegroundWindow(');
    expect(adjustment).toContain('finally{Send(new INPUT[]{up});}');
    expect(adjustment).toContain('target==editor&&pid==app.Id');
    const drag = fixture.slice(fixture.indexOf('static void ScreenshotDrag('), fixture.indexOf('static void ScreenshotContinueOpen('));
    for (const required of ['First stroke captured pixels before its owned release.', 'ScreenshotWindow(app.Id)==editor', 'initialAttempt+1', 'ScreenshotFirstStrokeReleaseChecks++']) expect(drag).toContain(required);
    expect(drag.indexOf('First stroke captured pixels before')).toBeLessThan(drag.indexOf('finally{'));
    expect(fixture).toContain('ScreenshotRecordCaptureCounts(report,pinAfter,3,2)');
    expect(fixture).toContain('ScreenshotRecordCaptureCounts(report,after,8,6)');
    expect(fixture).not.toContain('verifiedNativeCaptureGenerations');
  });
  it('uses one owned toolbar interaction after deferred resume, never forced activation', () => {
    const interaction = fixture.slice(fixture.indexOf('static void ScreenshotInteractAfterCapture('), fixture.indexOf('static Dictionary<string,object> ScreenshotPinCase('));
    for (const required of ['ToggleState.On', 'GetAncestor(WindowFromPoint(center),2)', 'target==editor&&pid==app.Id', 'current.Current.BoundingRectangle.Contains(center.X,center.Y)', 'Send(new INPUT[]{down,up})', 'explicitEditorInteractionVerified', 'selected-solid-tool', 'postCaptureInteractionClicks']) expect(interaction).toContain(required);
    for (const forbidden of ['SetForegroundWindow(', 'SetFocus(', '.Invoke()', '.Toggle()', 'RequireForeground(form)']) expect(interaction).not.toContain(forbidden);
  });
  it('records bounded owned adjustment geometry without changing the strict gesture predicate', () => {
    const drag = fixture.slice(fixture.indexOf('static void ScreenshotWebDrag('), fixture.indexOf('static void ScreenshotWebMoveResize('));
    for (const value of ['observations.Count<18', '"phase"', '"before"', '"expected"', '"lastObserved"', '"pointerStart"', '"pointerEnd"', 'return actual==expected', '},10,"Web adjustment gesture did not adopt exact expected geometry."', 'ScreenshotAdjustmentFailureState(app,editor,observation);throw;']) expect(drag).toContain(value);
    const failure = fixture.slice(fixture.indexOf('static void ScreenshotAdjustmentFailureState('), fixture.indexOf('static void ScreenshotWebDrag('));
    for (const value of ['root.Current.ProcessId==app.Id', 'selectionUpdateError', 'knownUpdateErrorCode', 'selectEnabled', 'selectOffscreen', 'selectOn']) expect(failure).toContain(value);
    expect(failure).not.toMatch(/observation\[[^\]]+\]=message\s*;/);
    for (const forbidden of ['Send(', 'SetForegroundWindow(', '.Invoke()', '.Toggle()', 'Thread.Sleep']) expect(failure).not.toContain(forbidden);
  });
  it('maps F1 exports to dismiss/re-capture while retaining standalone cancellation and collision oracles', () => {
    for (const value of ['if(closes)WaitFor', 'for(int save=0;save<2;save++)', 'recapturedSaveSessions', 'inplaceCopyAndSavesDismissed', 'savedCaptureReopenedThroughSettings', 'standaloneCollisionNumberingVerified', 'ScreenshotContinueOpen(app,dialogOwner)', 'inplaceCancelPreservedClipboard']) expect(fixture).toContain(value);
    expect(fixture).not.toContain('ScreenshotInvoke(app,editor,"100%")');
  });
  it('observes a failed owned native Open selector without logging names, values or changing input', () => {
    const describe = fixture.slice(fixture.indexOf('static Dictionary<string,object> ScreenshotOpenControlMetadata('), fixture.indexOf('static Dictionary<string,object> ScreenshotOpenGenerated('));
    for (const required of ['titleMatchesExpected', 'ownerIsEditor', 'foregroundMatches', 'numericAutomationId', 'nativeControlId', 'ControlType.Edit', 'ControlType.ComboBox', 'depth<4', 'i<32', 'ScreenshotNativeOpenObservations.Count>=2']) expect(describe).toContain(required);
    for (const forbidden of ['.Current.Name', '.Current.Value', '.SetValue(', '.Invoke()', 'Send(', '.SetFocus(']) expect(describe).not.toContain(forbidden);
    expect(fixture).toContain('catch{ScreenshotDescribeOpenDialog(app,dialogOwner,modal,format);throw;}');
    expect(fixture).toContain('AutomationElement.AutomationIdProperty,"1148"');
  });
  it('waits for an owned initialized native Cancel target before one Escape and preserves its phases', () => {
    const cancellation = fixture.slice(fixture.indexOf('static Dictionary<string,object> ScreenshotCancelState('), fixture.indexOf('static Dictionary<string,object> ScreenshotOpenControlMetadata('));
    for (const required of ['ownerIsEditor', 'titleMatchesExpected', 'focusWithinModal', 'cancelSupportsInvoke', 'IsWindowEnabled(editor)', 'AutomationElement.AutomationIdProperty,"2"', 'beforeEscape', 'afterEscape', 'failureState', 'escapePresses', 'ScreenshotNativeCancelObservations.Count<2']) expect(cancellation).toContain(required);
    expect(cancellation.match(/Send\(new INPUT/g)).toHaveLength(1);
    expect(cancellation).not.toContain('.Invoke()');
    expect(cancellation).not.toContain('.SetFocus(');
    expect(cancellation).not.toContain('Thread.Sleep');
    expect(cancellation.match(/},10,/g)).toHaveLength(2);
  });
  it('selects only the observed native filename1148 Edit/ComboBox/ComboBoxEx32 chain', () => {
    const selector = fixture.slice(fixture.indexOf('static bool ScreenshotOwnOpenDialog('), fixture.indexOf('static bool ScreenshotPixelsEqual('));
    for (const required of ['node.Current.AutomationId!="1148"', 'GetDlgCtrlID(window)==1148', 'GetAncestor(window,2)==modal', 'ControlType.Edit,"Edit"', 'ControlType.ComboBox,"ComboBox"', 'ControlType.Pane,"ComboBoxEx32"', 'Automation.Compare(parent,root)', 'ScreenshotOwnOpenDialog(app,dialogOwner,modal)', 'Assert(edits.Count<=1', 'edit.Current.HasKeyboardFocus']) expect(selector).toContain(required);
    expect(selector).not.toContain('AutomationIdProperty,"1001"');
    expect(selector.match(/\.SetValue\(path\)/g)).toHaveLength(1);
    expect(selector.match(/Send\(new INPUT/g)).toHaveLength(1);
    expect(selector).not.toContain('ControlType.Edit),Condition.TrueCondition');
  });
  it('executes the actual filename-node identity predicates against observed and unrelated edits', () => {
    const nodeCode = fixture.slice(fixture.indexOf('static bool ScreenshotFilenameNode('), fixture.indexOf('static bool ScreenshotFilenameChain('));
    const rejected = nodeCode.match(/if\(([^;]+)\)return false;/)?.[1];
    const native = nodeCode.match(/return (window!=[^;]+);/)?.[1];
    expect(rejected).toBeDefined(); expect(native).toBeDefined();
    const identity = new Function('node', 'type', 'className', 'process', `return !(${rejected});`);
    const nativeIdentity = new Function('window', 'pid', 'process', 'modal', 'GetDlgCtrlID', 'GetAncestor', 'IntPtr', `return ${native};`);
    const current = { ProcessId: 42, ControlType: 50004, ClassName: 'Edit', AutomationId: '1148', IsEnabled: true, IsOffscreen: false };
    expect(identity({ Current: current }, 50004, 'Edit', 42)).toBe(true);
    for (const patch of [{ AutomationId: '1001' }, { AutomationId: '' }, { ControlType: 50003 }, { ClassName: 'ComboBox' }, { ProcessId: 43 }, { IsEnabled: false }, { IsOffscreen: true }]) expect(identity({ Current: { ...current, ...patch } }, 50004, 'Edit', 42)).toBe(false);
    expect(nativeIdentity(101, 42, 42, 100, () => 1148, () => 100, { Zero: 0 })).toBe(true);
    for (const [window, pid, id, root] of [[0, 42, 1148, 100], [101, 43, 1148, 100], [101, 42, 1001, 100], [101, 42, 1148, 999]]) expect(nativeIdentity(window, pid, 42, 100, () => id, () => root, { Zero: 0 })).toBe(false);
  });
  it('refuses ambiguous accessibility names and releases an owned edit gesture promptly', () => {
    expect(fixture).toContain('Assert(matches.Count<=1');
    expect(fixture).toContain('finally{if(ForegroundPid()==app.Id)');
    expect(fixture).toContain('ForegroundPid()==app.Id&&GetForegroundWindow()==modal');
  });
});
