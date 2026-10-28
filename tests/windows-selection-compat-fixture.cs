// Generated source applications only. This fixture deliberately exercises the explicit
// copy strategy without treating unavailable UIA or successful Ctrl+C as selection proof.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using Source = WindowsSelectionDocumentFixture.Source;
using AutomaticMode = WindowsSelectionDocumentFixture.TestMode;

public static class WindowsSelectionCompatibilityFixture {
    const string Selected = "EchoLingo generated document selection 97531 中文";
    const string WholeLine = "Generated whole current line without a selected range 81007";
    enum Mode { NoTextPattern, FocusMetadataFailure, ChangingRuntimeId, KnownPasswordLeaf,
        KnownPasswordAncestor, NativeSelectedEdit, NativeEmptyEdit, NativePasswordEdit,
        NativeSelectedRichEdit, NativeEmptyRichEdit, NoSelectionCopyNoOp, WholeLineCounterexample }
    [StructLayout(LayoutKind.Sequential)] struct GuiThreadInfo {
        public uint Size, Flags; public IntPtr Active, Focus, Capture, Menu, Move, Caret;
        public int Left, Top, Right, Bottom;
    }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GuiThreadInfo info);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength=4*1024*1024 };
    static void Need(bool yes,string error) { if(!yes)throw new InvalidOperationException(error); }
    static long Health(Dictionary<string,object> health,string key) { return health.ContainsKey(key)?Convert.ToInt64(health[key]):-1; }
    static IntPtr NativeFocus(IntPtr window) {
        uint pid;uint thread=GetWindowThreadProcessId(window,out pid);
        GuiThreadInfo info=new GuiThreadInfo();info.Size=(uint)Marshal.SizeOf(typeof(GuiThreadInfo));
        Need(thread!=0&&GetGUIThreadInfo(thread,ref info),"GENERATED_NATIVE_FOCUS_UNAVAILABLE");return info.Focus;
    }
    static DataObject Seed() {
        DataObject data=new DataObject();data.SetData(DataFormats.UnicodeText,false,"Generated compatibility original 2468");
        data.SetData(DataFormats.Html,false,"<p>Generated compatibility rich original 2468</p>");
        data.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated compatibility rich original 2468}");
        Clipboard.SetDataObject(data,true);return data;
    }
    static void ClipboardMatches(DataObject expected) {
        IDataObject actual=Clipboard.GetDataObject();Need(actual!=null,"GENERATED_CLIPBOARD_MISSING");
        foreach(string format in expected.GetFormats(false))
            Need(Object.Equals(expected.GetData(format,false),actual.GetData(format,false)),"GENERATED_RICH_CLIPBOARD_CHANGED");
    }
    static Dictionary<string,object> Call(string helper,string assembly,string cancelName,EventWaitHandle cancel) {
        ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell/v1.0/powershell.exe"));
        start.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+helper+"\" -Mode selected-text -SelectionStrategy copy -NativeAssemblyPath \""+assembly+"\" -NativeCancellationEvent \""+cancelName+"\"";
        start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;
        start.StandardOutputEncoding=new UTF8Encoding(false);
        using(Process process=Process.Start(start)) {
            Task<string> stdout=process.StandardOutput.ReadToEndAsync(),stderr=process.StandardError.ReadToEndAsync();
            try {
                Need(process.WaitForExit(12000),"COPY_COMPAT_HELPER_DEADLINE");
                Need(Task.WaitAll(new Task[]{stdout,stderr},2000),"COPY_COMPAT_PIPE_DEADLINE");
                Need(stdout.Result.Length<=262144&&stderr.Result.Length<=65536,"COPY_COMPAT_OUTPUT_BOUND");
                Dictionary<string,object> reply=Json.Deserialize<Dictionary<string,object>>(stdout.Result.Trim('\ufeff',' ','\r','\n'));
                Need(Convert.ToBoolean(reply["ok"])?process.ExitCode==0:process.ExitCode==1,"COPY_COMPAT_EXIT_REPLY_MISMATCH");return reply;
            } finally {
                if(!process.HasExited) { cancel.Set();if(!process.WaitForExit(2000)) { process.Kill();Need(process.WaitForExit(2000),"COPY_COMPAT_OWN_HELPER_CLEANUP"); } }
            }
        }
    }
    static void Prepare(Source source,Mode mode,out TextBoxBase editor) {
        source.CompatibilityNoTextPatterns=mode==Mode.NoTextPattern;
        source.CompatibilityFocusFailure=mode==Mode.FocusMetadataFailure;
        source.CompatibilityChangingRuntimeId=mode==Mode.ChangingRuntimeId;
        source.CompatibilityCopyNoOp=mode==Mode.NoSelectionCopyNoOp;
        source.CompatibilityCopyText=mode==Mode.WholeLineCounterexample?WholeLine:null;
        AutomaticMode automatic=mode==Mode.KnownPasswordLeaf?AutomaticMode.PasswordLeaf:
            mode==Mode.KnownPasswordAncestor?AutomaticMode.PasswordDocument:
            mode==Mode.WholeLineCounterexample||mode==Mode.NoSelectionCopyNoOp?AutomaticMode.EmptyEditEmptyDocument:AutomaticMode.LinkDocument;
        source.SelectMode(automatic);editor=null;
        bool rich=mode==Mode.NativeSelectedRichEdit||mode==Mode.NativeEmptyRichEdit;
        bool native=rich||mode==Mode.NativeSelectedEdit||mode==Mode.NativeEmptyEdit||mode==Mode.NativePasswordEdit;
        if(native) {
            editor=rich?(TextBoxBase)new RichTextBox():new TextBox();editor.Bounds=new System.Drawing.Rectangle(15,20,600,80);
            editor.Text="Prefix "+Selected+" suffix";source.Controls.Add(editor);
            TextBox password=editor as TextBox;if(mode==Mode.NativePasswordEdit)password.PasswordChar='*';
            bool empty=mode==Mode.NativeEmptyEdit||mode==Mode.NativeEmptyRichEdit;
            editor.Select(7,empty?0:Selected.Length);editor.Focus();SetFocus(editor.Handle);
            Need(editor.SelectionStart==7&&editor.SelectionLength==(empty?0:Selected.Length),"GENERATED_NATIVE_SELECTION_SETUP");
        }
        Need(GetForegroundWindow()==source.Native,"GENERATED_SOURCE_NOT_FOREGROUND");
        Need(NativeFocus(source.Native)==(editor==null?source.Native:editor.Handle),"GENERATED_NATIVE_FOCUS_SETUP");
    }
    // Known-positive protection cases are explicitly metadata-warmed so they
    // test a responsive provider. This is not cold WPS/password acceptance.
    static void WarmKnownPassword(Mode mode) {
        AutomationElement focused=AutomationElement.FocusedElement;Need(focused!=null,"KNOWN_PASSWORD_SETUP_FOCUS");
        if(mode==Mode.KnownPasswordLeaf)Need(focused.Current.IsPassword,"KNOWN_PASSWORD_LEAF_SETUP");
        else { Need(!focused.Current.IsPassword,"KNOWN_PASSWORD_ANCESTOR_LEAF_SETUP");
            AutomationElement parent=TreeWalker.RawViewWalker.GetParent(focused);Need(parent!=null&&parent.Current.IsPassword,"KNOWN_PASSWORD_ANCESTOR_SETUP"); }
    }
    public static Dictionary<string,object> Run(string helper,string assembly) {
        Need(!helper.Contains("\"")&&!assembly.Contains("\""),"COPY_COMPAT_INVALID_PATH");
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();
        Dictionary<string,object> report=new Dictionary<string,object> {
            {"ok",false},{"copyCompatibilityFixture",true},{"selectionStrategy","copy"},{"cases",cases},
            {"requiredCases",Enum.GetValues(typeof(Mode)).Length},{"generatedSourceOnly",true},
            {"actualBrowserTested",false},{"actualWpsTested",false},{"registeredAltDTested",false},
            {"physicalWindowsTested",false},{"userContentRead",false},{"universalSelectionProof",false},
            {"unknownProtectionAllowedByExplicitStrategy",true},{"wholeLineWithoutSelectionBoundaryIncluded",true}
        };
        IDataObject original=Clipboard.GetDataObject();
        Need(original==null||original.GetFormats(false).Length==0,"FRESH_CLIPBOARD_REQUIRED: No existing clipboard was changed.");
        uint ownedSequence=GetClipboardSequenceNumber();
        using(Source source=new Source()) {
            Thread worker=null;source.Shown+=delegate {
                source.Native=source.Handle;worker=new Thread(delegate() {
                    try {
                        foreach(Mode mode in (Mode[])Enum.GetValues(typeof(Mode))) {
                            Dictionary<string,object> test=new Dictionary<string,object>{{"name",mode.ToString()},{"ok",false}};cases.Add(test);
                            TextBoxBase editor=null;DataObject seed=null;
                            string eventName="Local\\EchoLingo-copycompat-cancel-"+Guid.NewGuid().ToString("N");
                            using(EventWaitHandle cancel=new EventWaitHandle(false,EventResetMode.ManualReset,eventName)) {
                                source.Invoke((Action)delegate { source.Cancel=cancel;Prepare(source,mode,out editor);seed=Seed();ownedSequence=GetClipboardSequenceNumber(); });
                                bool knownPassword=mode==Mode.KnownPasswordLeaf||mode==Mode.KnownPasswordAncestor;
                                if(knownPassword)WarmKnownPassword(mode);
                                if(mode==Mode.NoTextPattern) {
                                    Need(source.Leaf.GetPatternProvider(System.Windows.Automation.TextPatternIdentifiers.Pattern.Id)==null&&source.Document.GetPatternProvider(System.Windows.Automation.TextPatternIdentifiers.Pattern.Id)==null,"NO_TEXT_PATTERN_SETUP");
                                    test["generatedProviderTextPatternsUnavailable"]=true;
                                }
                                if(mode==Mode.ChangingRuntimeId) {
                                    int[] first=source.Leaf.GetRuntimeId(),second=source.Leaf.GetRuntimeId();
                                    Need(first[first.Length-1]!=second[second.Length-1],"CHANGING_RUNTIME_ID_SETUP");
                                    test["changingRuntimeIdProviderConfigured"]=true;test["identitySetupUsesDirectGeneratedProviderOnly"]=true;
                                }
                                if(mode==Mode.WholeLineCounterexample||mode==Mode.NoSelectionCopyNoOp) {
                                    Need(source.Leaf.GetSelection()[0].GetText(-1)==""&&source.Document.GetSelection()[0].GetText(-1)=="","NO_SELECTION_COUNTEREXAMPLE_SETUP");
                                    test["generatedProviderExposesNoSelectedRange"]=true;
                                }
                                int copies=source.Copies,queries=source.SelectionQueries,focusCalls=source.ProviderFocusCalls,documentRanges=source.DocumentRangeQueries;
                                int focusFailures=source.CompatibilityFocusFailures,runtimeCalls=source.CompatibilityRuntimeIdCalls;
                                IntPtr nativeFocus=NativeFocus(source.Native);
                                Dictionary<string,object> reply=Call(helper,assembly,eventName,cancel);
                                Need(reply.ContainsKey("nativeBackend")&&Convert.ToString(reply["nativeBackend"])=="precompiled-framework-dll","COPY_COMPAT_NOT_EXACT_NATIVE_DLL");
                                bool empty=mode==Mode.NativeEmptyEdit||mode==Mode.NativeEmptyRichEdit;
                                bool protectedCase=knownPassword||mode==Mode.NativePasswordEdit;
                                bool noOp=mode==Mode.NoSelectionCopyNoOp;
                                bool rejected=empty||protectedCase||noOp;
                                Need(Convert.ToBoolean(reply["ok"])==!rejected,"COPY_COMPAT_UNEXPECTED_RESULT:"+(reply.ContainsKey("error")?reply["error"]:"success"));
                                if(rejected)Need(Convert.ToString(reply["error"]).StartsWith(protectedCase?"PROTECTED:":"NO_SELECTION:"),"COPY_COMPAT_WRONG_REJECTION");
                                else Need(Convert.ToString(reply["text"])==(mode==Mode.WholeLineCounterexample?WholeLine:Selected),"COPY_COMPAT_INEXACT_GENERATED_TEXT");
                                Dictionary<string,object> health=reply.ContainsKey("captureHealth")?reply["captureHealth"] as Dictionary<string,object>:null;
                                Need(health!=null&&Health(health,"copyStrategy")==1&&Health(health,"selectionQueryCount")==0,"COPY_COMPAT_STRATEGY_OR_DEEP_UIA_QUERY");
                                Need(Health(health,"copyDispatchInserted")==((empty||protectedCase)?0:4),"COPY_COMPAT_DISPATCH_ACK_COUNT");
                                if(!empty&&!protectedCase)Need(Health(health,"copyOwnInputObserved")==1,"COPY_COMPAT_OWN_INPUT_NOT_OBSERVED");
                                if(!rejected)Need(Health(health,"copyClipboardRestored")==1&&Health(health,"copyOwnerOutcome")==1&&Health(health,"copyTerminalReason")==1,"COPY_COMPAT_COMPLETION_METADATA");
                                if(rejected)Need(Health(health,"copyTerminalReason")==((protectedCase)?2:3),"COPY_COMPAT_REJECTION_METADATA");
                                if(knownPassword)Need(Health(health,"copyProtectionProbe")==1,"COPY_COMPAT_KNOWN_PASSWORD_NOT_OBSERVED");
                                source.Invoke((Action)delegate {
                                    Need(source.Copies-copies==(empty||protectedCase?0:1),"COPY_COMPAT_REAL_COPY_COUNT");
                                    Need(source.SelectionQueries==queries&&source.DocumentRangeQueries==documentRanges,"COPY_COMPAT_READ_TEXT_PROVIDER_OR_DOCUMENT");
                                    Need(source.ProviderFocusCalls==focusCalls,"COPY_COMPAT_CHANGED_PROVIDER_FOCUS");
                                    Need(GetForegroundWindow()==source.Native&&NativeFocus(source.Native)==nativeFocus,"COPY_COMPAT_NATIVE_SOURCE_FOCUS_CHANGED");
                                    ClipboardMatches(seed);ownedSequence=GetClipboardSequenceNumber();
                                    if(editor!=null){Need(editor.Text=="Prefix "+Selected+" suffix","COPY_COMPAT_NATIVE_SOURCE_CHANGED");editor.Dispose();editor=null;}
                                });
                                test["actualCopies"]=source.Copies-copies;test["textProviderSelectionReads"]=source.SelectionQueries-queries;
                                test["wholeDocumentReads"]=source.DocumentRangeQueries-documentRanges;test["providerFocusCalls"]=source.ProviderFocusCalls-focusCalls;
                                test["focusMetadataFailuresObserved"]=source.CompatibilityFocusFailures-focusFailures;
                                if(mode==Mode.FocusMetadataFailure)Need(source.CompatibilityFocusFailures>focusFailures,"COPY_COMPAT_METADATA_FAULT_PROVIDER_NOT_EXERCISED");
                                test["runtimeIdProviderCallsObserved"]=source.CompatibilityRuntimeIdCalls-runtimeCalls;
                                test["knownPasswordMetadataWarmupUsed"]=knownPassword;test["sourceForegroundAndNativeFocusPreserved"]=true;
                                test["richClipboardPreserved"]=true;test["resultExactlyExpected"]=true;
                                test["selectionVerified"]=mode==Mode.NativeSelectedEdit||mode==Mode.NativeSelectedRichEdit;
                                if(mode==Mode.WholeLineCounterexample){test["knownCompatibilityLimitationDemonstrated"]=true;test["wholeLineCopiedWithoutSelection"]=true;}
                                test["nativeHealth"]=health;
                                test["ok"]=true;
                            }
                        }
                        report["ok"]=true;
                    } catch(Exception error) { while(error.InnerException!=null)error=error.InnerException;report["error"]=error.Message; }
                    finally {
                        report["executedCases"]=cases.Count;report["passedCases"]=cases.FindAll(delegate(Dictionary<string,object> row){return Convert.ToBoolean(row["ok"]);}).Count;
                        source.BeginInvoke((Action)delegate { if(GetClipboardSequenceNumber()==ownedSequence)Clipboard.Clear();source.Close(); });
                    }
                });worker.SetApartmentState(ApartmentState.MTA);worker.Start();
            };
            Application.Run(source);if(worker!=null)Need(worker.Join(5000),"COPY_COMPAT_FIXTURE_WORKER_CLEANUP");
        }
        return report;
    }
}
