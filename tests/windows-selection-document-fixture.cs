// Real UIA provider topology + real Ctrl+C/clipboard, generated data only.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Provider;
using System.Windows.Automation.Text;
using System.Windows.Forms;
using System.Web.Script.Serialization;
public static class WindowsSelectionDocumentFixture {
    const string Selected="EchoLingo generated document selection 97531 中文";
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr hwnd,uint kind);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    static JavaScriptSerializer json=new JavaScriptSerializer { MaxJsonLength=4*1024*1024 };
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    static void Need(bool yes,string message){if(!yes)throw new InvalidOperationException(message);}
    internal enum TestMode { LinkDocument, EmptyLeafDocument, EmptyDocumentCopy250, EmptyEdit, EmptyEditEmptyDocument, EmptyEditNoDocument, EmptyEditPasswordDocument, SelectedEdit, PasswordLeaf, PasswordDocument, PasswordAncestorSelectedLeaf, NonTextNoDocument, StaleRange, CancelAfterCopy250, ExcludedSource }
    internal sealed class Source : Form {
        public TestMode Mode;public int Copies,SelectionQueries,LeafSelectionQueries,DocumentSelectionQueries,DocumentRangeQueries,ProviderFocusCalls;public Bridge Root,Document,Leaf;public IntPtr Native;
        // Opt-in fault controls used only by the separate explicit-copy fixture.
        // The existing automatic-selection modes and their fifteen expectations stay unchanged.
        public bool CompatibilityNoTextPatterns=false,CompatibilityFocusFailure=false,CompatibilityChangingRuntimeId=false,CompatibilityCopyNoOp=false;
        public int CompatibilityFocusFailures=0,CompatibilityRuntimeIdCalls=0;public string CompatibilityCopyText=null;
        public int NextCompatibilityRuntimeId(){return Interlocked.Increment(ref CompatibilityRuntimeIdCalls);}
        public void RecordCompatibilityFocusFailure(){Interlocked.Increment(ref CompatibilityFocusFailures);}
        public Rect Physical;public System.Windows.Forms.Timer Publication;public EventWaitHandle Cancel;
        public void RecordSelection(int node){Interlocked.Increment(ref SelectionQueries);if(node==1)Interlocked.Increment(ref DocumentSelectionQueries);if(node==2)Interlocked.Increment(ref LeafSelectionQueries);}
        public void RecordDocumentRange(){Interlocked.Increment(ref DocumentRangeQueries);}
        public void RecordFocus(){Interlocked.Increment(ref ProviderFocusCalls);}
        public bool NoDocument {get{return Mode==TestMode.NonTextNoDocument||Mode==TestMode.EmptyEditNoDocument;}}
        public bool EditLeaf {get{return Mode==TestMode.EmptyEdit||Mode==TestMode.EmptyEditEmptyDocument||Mode==TestMode.EmptyEditNoDocument||Mode==TestMode.EmptyEditPasswordDocument||Mode==TestMode.SelectedEdit||Mode==TestMode.PasswordLeaf;}}
        public Source(){Text="EchoLingo generated document provider";StartPosition=FormStartPosition.CenterScreen;ClientSize=new System.Drawing.Size(640,340);Root=new Bridge(this,0);Document=new Bridge(this,1);Leaf=new Bridge(this,2);}
        protected override void WndProc(ref Message message){
            if(message.Msg==0x003d&&message.LParam.ToInt64()==AutomationInteropProvider.RootObjectId){message.Result=AutomationInteropProvider.ReturnRawElementProvider(Handle,message.WParam,message.LParam,Root);return;}base.WndProc(ref message);
        }
        protected override bool ProcessCmdKey(ref Message message,Keys key){
            if(key==(Keys.Control|Keys.C)){
                Copies++;if(CompatibilityCopyNoOp)return true;Clipboard.Clear();if(Mode==TestMode.CancelAfterCopy250)Cancel.Set();
                Publication=new System.Windows.Forms.Timer();Publication.Interval=250;Publication.Tick+=delegate {Publication.Stop();Publication.Dispose();Publication=null;Clipboard.SetText(CompatibilityCopyText??Selected,TextDataFormat.UnicodeText);};Publication.Start();return true;
            }return base.ProcessCmdKey(ref message,key);
        }
        public void SelectMode(TestMode mode){Mode=mode;Native=Handle;Rectangle r=Bounds;Physical=new Rect(r.X,r.Y,r.Width,r.Height);Activate();SetForegroundWindow(Handle);SetFocus(Handle);AutomationInteropProvider.RaiseAutomationEvent(AutomationElementIdentifiers.AutomationFocusChangedEvent,Leaf,new AutomationEventArgs(AutomationElementIdentifiers.AutomationFocusChangedEvent));}
        protected override void Dispose(bool disposing){if(disposing&&Publication!=null){Publication.Stop();Publication.Dispose();Publication=null;}base.Dispose(disposing);}
    }
    [ComVisible(true),ClassInterface(ClassInterfaceType.None)]
    public sealed class Bridge : IRawElementProviderSimple,IRawElementProviderFragment,IRawElementProviderFragmentRoot,ITextProvider {
        readonly Source owner;readonly int kind;
        internal Bridge(Source source,int node){owner=source;kind=node;}
        bool LeafText {get{return owner.Mode==TestMode.EmptyLeafDocument||owner.EditLeaf||owner.Mode==TestMode.PasswordAncestorSelectedLeaf;}}
        public ProviderOptions ProviderOptions {get{return ProviderOptions.ServerSideProvider;}}
        public IRawElementProviderSimple HostRawElementProvider {get{return kind==0?AutomationInteropProvider.HostProviderFromHandle(owner.Native):null;}}
        public object GetPatternProvider(int id){return !owner.CompatibilityNoTextPatterns&&id==TextPatternIdentifiers.Pattern.Id&&(kind==1||kind==2&&LeafText)?this:null;}
        public object GetPropertyValue(int id){
            if(id==AutomationElementIdentifiers.IsPasswordProperty.Id&&kind==2&&owner.CompatibilityFocusFailure){owner.RecordCompatibilityFocusFailure();throw new InvalidOperationException("Generated focus protection metadata failure");}
            if(id==AutomationElementIdentifiers.ControlTypeProperty.Id)return kind==0?ControlType.Window.Id:kind==1?ControlType.Document.Id:owner.EditLeaf?ControlType.Edit.Id:owner.Mode==TestMode.EmptyLeafDocument?ControlType.Custom.Id:owner.NoDocument?ControlType.Button.Id:ControlType.Hyperlink.Id;
            if(id==AutomationElementIdentifiers.NativeWindowHandleProperty.Id){IntPtr native=owner.Native;return kind==0?native.ToInt32():0;}
            if(id==AutomationElementIdentifiers.ProcessIdProperty.Id)return Process.GetCurrentProcess().Id;
            if(id==AutomationElementIdentifiers.NameProperty.Id)return "Generated UIA node "+kind;
            if(id==AutomationElementIdentifiers.AutomationIdProperty.Id)return "echolingo-generated-document-"+kind;
            if(id==AutomationElementIdentifiers.IsPasswordProperty.Id)return kind==2&&owner.Mode==TestMode.PasswordLeaf||kind==1&&(owner.Mode==TestMode.PasswordDocument||owner.Mode==TestMode.PasswordAncestorSelectedLeaf||owner.Mode==TestMode.EmptyEditPasswordDocument);
            if(id==AutomationElementIdentifiers.HasKeyboardFocusProperty.Id)return kind==2&&GetForegroundWindow()==owner.Native;
            if(id==AutomationElementIdentifiers.IsKeyboardFocusableProperty.Id)return kind==2;
            if(id==AutomationElementIdentifiers.IsEnabledProperty.Id||id==AutomationElementIdentifiers.IsControlElementProperty.Id||id==AutomationElementIdentifiers.IsContentElementProperty.Id)return true;
            if(id==AutomationElementIdentifiers.IsOffscreenProperty.Id)return false;
            if(id==AutomationElementIdentifiers.IsTextPatternAvailableProperty.Id)return !owner.CompatibilityNoTextPatterns&&(kind==1||kind==2&&LeafText);
            return null;
        }
        public IRawElementProviderFragment Navigate(NavigateDirection direction){
            if(direction==NavigateDirection.Parent)return kind==0?null:kind==1?(IRawElementProviderFragment)owner.Root:owner.NoDocument?owner.Root:owner.Document;
            if(direction==NavigateDirection.FirstChild||direction==NavigateDirection.LastChild)return kind==0?(owner.NoDocument?owner.Leaf:owner.Document):kind==1&&!owner.NoDocument?owner.Leaf:null;
            return null;
        }
        public int[] GetRuntimeId(){return kind==0?null:owner.CompatibilityChangingRuntimeId?new int[]{AutomationInteropProvider.AppendRuntimeId,kind+100,owner.NextCompatibilityRuntimeId()}:new int[]{AutomationInteropProvider.AppendRuntimeId,kind+100};}
        public Rect BoundingRectangle {get{return owner.Physical;}}
        public IRawElementProviderSimple[] GetEmbeddedFragmentRoots(){return null;}
        public void SetFocus(){owner.RecordFocus();throw new InvalidOperationException("Fixture provider focus must not be changed by acquisition.");}
        public IRawElementProviderFragmentRoot FragmentRoot {get{return owner.Root;}}
        public IRawElementProviderFragment ElementProviderFromPoint(double x,double y){return owner.Leaf;}
        public IRawElementProviderFragment GetFocus(){if(owner.CompatibilityFocusFailure){owner.RecordCompatibilityFocusFailure();throw new InvalidOperationException("Generated focus metadata failure");}return owner.Leaf;}
        public ITextRangeProvider DocumentRange {get{owner.RecordDocumentRange();return new Range(this,"WHOLE DOCUMENT MUST NEVER BE READ",false);}}
        public SupportedTextSelection SupportedTextSelection {get{return SupportedTextSelection.Single;}}
        public ITextRangeProvider[] GetSelection(){
            owner.RecordSelection(kind);bool empty=kind==2&&owner.Mode!=TestMode.PasswordAncestorSelectedLeaf&&owner.Mode!=TestMode.SelectedEdit||owner.Mode==TestMode.EmptyDocumentCopy250||owner.Mode==TestMode.CancelAfterCopy250||owner.Mode==TestMode.EmptyEditEmptyDocument;
            return new ITextRangeProvider[]{new Range(this,empty?"":Selected,owner.Mode==TestMode.StaleRange)};
        }
        public ITextRangeProvider[] GetVisibleRanges(){throw new NotSupportedException();}
        public ITextRangeProvider RangeFromChild(IRawElementProviderSimple child){throw new NotSupportedException();}
        public ITextRangeProvider RangeFromPoint(System.Windows.Point point){throw new NotSupportedException();}
    }
    [ComVisible(true),ClassInterface(ClassInterfaceType.None)]
    public sealed class Range : ITextRangeProvider {
        readonly Bridge provider;readonly string text;readonly bool stale;
        internal Range(Bridge owner,string value,bool unavailable){provider=owner;text=value;stale=unavailable;}
        public string GetText(int maximum){if(stale)throw new ElementNotAvailableException("Generated stale range");return maximum<0||maximum>=text.Length?text:text.Substring(0,maximum);}
        public ITextRangeProvider Clone(){return new Range(provider,text,stale);}public bool Compare(ITextRangeProvider range){return Object.ReferenceEquals(this,range);}
        public int CompareEndpoints(TextPatternRangeEndpoint endpoint,ITextRangeProvider target,TextPatternRangeEndpoint targetEndpoint){return 0;}
        public void ExpandToEnclosingUnit(TextUnit unit){throw new NotSupportedException();}public ITextRangeProvider FindAttribute(int attribute,object value,bool backward){throw new NotSupportedException();}public ITextRangeProvider FindText(string value,bool backward,bool ignoreCase){throw new NotSupportedException();}
        public object GetAttributeValue(int attribute){return AutomationElement.NotSupported;}public double[] GetBoundingRectangles(){return new double[0];}public IRawElementProviderSimple GetEnclosingElement(){return provider;}
        public int Move(TextUnit unit,int count){throw new NotSupportedException();}public void MoveEndpointByRange(TextPatternRangeEndpoint endpoint,ITextRangeProvider target,TextPatternRangeEndpoint targetEndpoint){throw new NotSupportedException();}public int MoveEndpointByUnit(TextPatternRangeEndpoint endpoint,TextUnit unit,int count){throw new NotSupportedException();}
        public void Select(){throw new NotSupportedException();}public void AddToSelection(){throw new NotSupportedException();}public void RemoveFromSelection(){throw new NotSupportedException();}public void ScrollIntoView(bool align){throw new NotSupportedException();}public IRawElementProviderSimple[] GetChildren(){return new IRawElementProviderSimple[0];}
    }
    static Dictionary<string,object> Call(string helper,string assembly,string cancelName,EventWaitHandle cancel,bool excluded){
        ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell/v1.0/powershell.exe"));
        start.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+helper+"\" -Mode selected-text -SelectionStrategy auto -NativeAssemblyPath \""+assembly+"\" -NativeCancellationEvent \""+cancelName+"\""+(excluded?" -ExcludedSourceProcessId "+Process.GetCurrentProcess().Id:"");
        start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;start.StandardOutputEncoding=new UTF8Encoding(false);
        using(Process process=Process.Start(start)){
            Task<string> stdout=process.StandardOutput.ReadToEndAsync(),stderr=process.StandardError.ReadToEndAsync();
            try {
                Need(process.WaitForExit(12000),"Generated helper exceeded bounded fixture deadline.");
                Need(Task.WaitAll(new Task[]{stdout,stderr},2000),"Generated helper pipe did not close after exit.");
                Need(stdout.Result.Length<=262144&&stderr.Result.Length<=65536,"Generated helper exceeded fixture output bounds.");
                Dictionary<string,object> result=json.Deserialize<Dictionary<string,object>>(stdout.Result.Trim('\ufeff',' ','\r','\n'));
                Need(Convert.ToBoolean(result["ok"])?process.ExitCode==0:process.ExitCode==1,"Helper actual exit disagrees with reply.");
                return result;
            } finally {
                // Every helper is this fixture's own process and only handles
                // generated clipboard data. First request cooperative cleanup;
                // bounded hard cleanup is a fixture failure, never a pass.
                if(!process.HasExited){cancel.Set();if(!process.WaitForExit(2000)){process.Kill();Need(process.WaitForExit(2000),"Owned helper cleanup failed.");}}
            }
        }
    }
    static DataObject Seed(){DataObject data=new DataObject();data.SetData(DataFormats.UnicodeText,false,"Generated original clipboard 2468");data.SetData(DataFormats.Html,false,"<p>Generated rich original 2468</p>");data.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated rich original 2468}");Clipboard.SetDataObject(data,true);return data;}
    static void ClipboardMatches(DataObject expected){IDataObject actual=Clipboard.GetDataObject();foreach(string format in expected.GetFormats(false))Need(Object.Equals(expected.GetData(format,false),actual.GetData(format,false)),"Original generated rich clipboard was not restored.");}
    public static Dictionary<string,object> Run(string helper,string assembly){
        Need(!helper.Contains("\"")&&!assembly.Contains("\""),"Invalid fixture path.");List<Dictionary<string,object>> results=new List<Dictionary<string,object>>();Dictionary<string,object> report=new Dictionary<string,object>{{"ok",false},{"cases",results},{"requiredCaseCount",Enum.GetValues(typeof(TestMode)).Length},{"requiredCases",Enum.GetNames(typeof(TestMode))},{"generatedProviderTopology",true},{"realBrowserTested",false},{"userContentRead",false}};
        // The outer PS permits only a fresh disposable test desktop/account.
        IDataObject original=Clipboard.GetDataObject();Need(original==null||original.GetFormats(false).Length==0,"FRESH_CLIPBOARD_REQUIRED: This generated fixture only runs with an empty clipboard; existing contents were not read or changed.");
        uint ownedSequence=GetClipboardSequenceNumber();
        using(Source source=new Source()){
            Thread worker=null;source.Shown+=delegate{
                source.Native=source.Handle;
                worker=new Thread(delegate(){
                    try{
                        foreach(TestMode mode in (TestMode[])Enum.GetValues(typeof(TestMode))){
                            Dictionary<string,object> test=new Dictionary<string,object>{{"mode",mode.ToString()},{"ok",false}};results.Add(test);
                            string eventName="Local\\EchoLingo-cancel-"+Guid.NewGuid().ToString("N");
                            using(EventWaitHandle cancel=new EventWaitHandle(false,EventResetMode.ManualReset,eventName)){
                                DataObject seed=null;int copies=0,queries=0,leafQueries=0,documentQueries=0;
                                source.Invoke((Action)delegate {source.Cancel=cancel;source.SelectMode(mode);copies=source.Copies;queries=source.SelectionQueries;seed=Seed();ownedSequence=GetClipboardSequenceNumber();});
                                Need(GetForegroundWindow()==source.Native,"Generated source is not foreground.");
                                AutomationElement focused=AutomationElement.FocusedElement;Need(focused!=null&&focused.Current.ProcessId==Process.GetCurrentProcess().Id,"Actual UIA focus is not fixture-owned.");
                                string role=focused.Current.ControlType.ProgrammaticName;string expectedRole=source.EditLeaf?"ControlType.Edit":mode==TestMode.EmptyLeafDocument?"ControlType.Custom":mode==TestMode.NonTextNoDocument?"ControlType.Button":"ControlType.Hyperlink";
                                Need(role==expectedRole,"Actual generated focused role differs from required topology.");
                                if(mode==TestMode.EmptyLeafDocument||mode==TestMode.EmptyEdit||mode==TestMode.EmptyEditEmptyDocument||mode==TestMode.EmptyEditNoDocument){object ownPattern;Need(focused.TryGetCurrentPattern(TextPattern.Pattern,out ownPattern)&&((TextPattern)ownPattern).GetSelection()[0].GetText(-1)=="","Focused provider did not expose the required empty range.");}
                                if(mode==TestMode.LinkDocument||mode==TestMode.EmptyLeafDocument||mode==TestMode.EmptyEdit||mode==TestMode.EmptyEditEmptyDocument){AutomationElement parent=TreeWalker.RawViewWalker.GetParent(focused);string selected=mode==TestMode.EmptyEditEmptyDocument?"":Selected;Need(parent.Current.ControlType==ControlType.Document&&((TextPattern)parent.GetCurrentPattern(TextPattern.Pattern)).GetSelection()[0].GetText(-1)==selected,"Actual parent document does not expose the required generated selection.");}
                                queries=source.SelectionQueries;leafQueries=source.LeafSelectionQueries;documentQueries=source.DocumentSelectionQueries;test["actualFocusedRole"]=role;test["actualFocusRuntimeIdPresent"]=focused.GetRuntimeId().Length>0;
                                Dictionary<string,object> reply=Call(helper,assembly,eventName,cancel,mode==TestMode.ExcludedSource);
                                Need(reply.ContainsKey("nativeBackend")&&(string)reply["nativeBackend"]=="precompiled-framework-dll","Actual exact packaged assembly backend was not used.");
                                bool copy=mode==TestMode.EmptyDocumentCopy250||mode==TestMode.CancelAfterCopy250;bool reject=mode==TestMode.EmptyEditEmptyDocument||mode==TestMode.EmptyEditNoDocument||mode==TestMode.EmptyEditPasswordDocument||mode==TestMode.PasswordLeaf||mode==TestMode.PasswordDocument||mode==TestMode.PasswordAncestorSelectedLeaf||mode==TestMode.NonTextNoDocument||mode==TestMode.StaleRange||mode==TestMode.ExcludedSource;
                                Need((bool)reply["ok"]==(!reject&&mode!=TestMode.CancelAfterCopy250),"Unexpected generated-provider result: "+(reply.ContainsKey("error")?reply["error"]:"success"));
                                if((bool)reply["ok"])Need((string)reply["text"]==Selected,"Selection was not exactly generated selected text.");
                                if(reject){string prefix=mode==TestMode.PasswordLeaf||mode==TestMode.PasswordDocument||mode==TestMode.PasswordAncestorSelectedLeaf||mode==TestMode.EmptyEditPasswordDocument?"PROTECTED:":mode==TestMode.StaleRange?"SELECTION:":"NO_SELECTION:";Need(reply.ContainsKey("error")&&Convert.ToString(reply["error"]).StartsWith(prefix),"Generated negative case was not rejected for its specific guard.");}
                                if(mode==TestMode.CancelAfterCopy250)Need(Convert.ToString(reply["error"]).StartsWith("CANCELLED:"),"Copy cancellation was not reported after cleanup.");
                                source.Invoke((Action)delegate {Need(source.Copies-copies==(copy?1:0),"Wrong real Ctrl+C count; no key retries permitted.");ClipboardMatches(seed);ownedSequence=GetClipboardSequenceNumber();if(mode==TestMode.ExcludedSource)Need(source.SelectionQueries==queries,"Excluded source reached a text selection provider.");Need(source.DocumentRangeQueries==0&&source.ProviderFocusCalls==0,"Acquisition read whole DocumentRange or changed provider focus.");});
                                if(mode==TestMode.EmptyEdit||mode==TestMode.EmptyEditEmptyDocument)Need(source.LeafSelectionQueries-leafQueries==1&&source.DocumentSelectionQueries-documentQueries==1,"Empty Edit must read only its own selection and the validated ancestor Document selection once.");
                                if(mode==TestMode.EmptyEditNoDocument||mode==TestMode.SelectedEdit)Need(source.LeafSelectionQueries-leafQueries==1&&source.DocumentSelectionQueries-documentQueries==0,"No-document empty Edit or selected Edit must not query unrelated document selections.");
                                if(mode==TestMode.EmptyEditPasswordDocument)Need(source.SelectionQueries==queries,"Protected Document ancestry must be rejected before reading the leaf or document selection.");
                                test["leafSelectionQueries"]=source.LeafSelectionQueries-leafQueries;test["documentSelectionQueries"]=source.DocumentSelectionQueries-documentQueries;
                                Need(GetForegroundWindow()==source.Native,"Acquisition activated another window.");test["copies"]=source.Copies-copies;test["providerSelectionQueries"]=source.SelectionQueries-queries;test["richClipboardRestored"]=true;test["sourceForegroundPreserved"]=true;test["wholeDocumentRangeRead"]=false;test["ok"]=true;
                            }
                        }report["ok"]=true;
                    }catch(Exception error){while(error.InnerException!=null)error=error.InnerException;report["error"]=error.Message;}
                    finally{report["executedCaseCount"]=results.Count;report["passedCaseCount"]=results.FindAll(delegate(Dictionary<string,object> value){return Convert.ToBoolean(value["ok"]);}).Count;source.BeginInvoke((Action)delegate{if(GetClipboardSequenceNumber()==ownedSequence)Clipboard.Clear();source.Close();});}
                });worker.SetApartmentState(ApartmentState.MTA);worker.Start();
            };Application.Run(source);if(worker!=null)Need(worker.Join(5000),"Generated provider worker did not finish.");
        }return report;
    }
}
