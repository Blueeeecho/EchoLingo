// Compiled with windows-application-smoke.ps1's guarded ephemeral-runner fixture.
// Uses the real packaged app/WebView/native picker; never mocks screenshot IPC.
public static partial class EchoLingoApplicationSmoke {
    // This fixture starts with an empty clipboard. A failed assertion may only
    // reclaim its last verified generation, never a newer/foreign clipboard.
    [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll",SetLastError=true)] static extern int CountClipboardFormats();
    [DllImport("kernel32.dll",EntryPoint="SetLastError")] static extern void ScreenshotSetLastError(uint error);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern IntPtr GetClipboardOwner();
    [DllImport("user32.dll")] static extern bool IsClipboardFormatAvailable(uint format);
    [DllImport("user32.dll",SetLastError=true)] static extern uint EnumClipboardFormats(uint previous);
    [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint format,IntPtr data);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint flags,UIntPtr bytes);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr memory);
    [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr memory);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr memory);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr memory);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window,out RECT rect);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref Point point);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] static extern int GetSystemMetricsForDpi(int index,uint dpi);
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct ScreenshotOsVersion {
        public uint size,major,minor,build,platform;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string servicePack;
    }
    [DllImport("ntdll.dll",CharSet=CharSet.Unicode)] static extern int RtlGetVersion(ref ScreenshotOsVersion version);
    static bool ScreenshotClientFrameMatches(int[] insets,int frame,int top) {return frame>0&&insets.Length==4&&insets[0]==frame&&insets[1]==top&&insets[2]==frame&&insets[3]==frame;}
    static bool ScreenshotMeasureClientFrame(IntPtr pin,int expectedPid,Dictionary<string,object> result) {
        uint pid;GetWindowThreadProcessId(pin,out pid);Assert(pid==expectedPid&&IsWindow(pin)&&IsWindowVisible(pin),"Pin frame measurement requires the visible owned pin.");
        // Tao 0.37.2 keeps WS_CAPTION on top-level undecorated windows. Its
        // WM_NCCALCSIZE and util::calculate_insets_for_dpi define the real frame.
        // https://github.com/tauri-apps/tao/blob/tao-v0.37.2/src/platform_impl/windows/util.rs
        long style=GetWindowLongPtr(pin,-16).ToInt64();result["nativePinStyle"]=style;
        RECT outer=new RECT(),client=new RECT();Assert(GetWindowRect(pin,out outer)&&GetClientRect(pin,out client),"Cannot measure owned pin client frame.");
        Point first=new Point(client.left,client.top),last=new Point(client.right,client.bottom);
        Assert(ClientToScreen(pin,ref first)&&ClientToScreen(pin,ref last),"Cannot map owned pin client frame.");
        uint dpi=GetDpiForWindow(pin);ScreenshotOsVersion version=new ScreenshotOsVersion();version.size=(uint)Marshal.SizeOf(typeof(ScreenshotOsVersion));
        Assert(dpi>=96&&dpi<=768&&RtlGetVersion(ref version)==0,"Cannot establish actual pin DPI/Windows build.");
        int frame=GetSystemMetricsForDpi(32,dpi)+GetSystemMetricsForDpi(92,dpi);
        int top=version.build>=22000?(int)Math.Floor(dpi/96.0+0.5):0;
        int[] insets=new int[]{first.X-outer.left,first.Y-outer.top,outer.right-last.X,outer.bottom-last.Y};
        result["nativePinClientFrame"]=new Dictionary<string,object>{{"dpi",dpi},{"windowsBuild",version.build},{"frameThickness",frame},{"insets",insets}};
        Assert(client.left==0&&client.top==0&&client.right>0&&client.bottom>0,"Invalid measured client area.");
        return ScreenshotClientFrameMatches(insets,frame,top);
    }
    static void ScreenshotVerifyPinClientFrame(Form source,Process app,IntPtr pin,Dictionary<string,object> result) {
        Assert(ScreenshotMeasureClientFrame(pin,app.Id,result),"Pinned image has unexpected nonclient/title-bar geometry.");
        Dictionary<string,object> decorated=new Dictionary<string,object>();
        Assert(!ScreenshotMeasureClientFrame(source.Handle,Process.GetCurrentProcess().Id,decorated),"Client-frame oracle accepted the actual decorated generated source.");
        result["nativeDecoratedSourceFrame"]=decorated;
        Dictionary<string,object> metrics=(Dictionary<string,object>)decorated["nativePinClientFrame"];
        int expectedTop=Convert.ToUInt32(metrics["windowsBuild"])>=22000?(int)Math.Floor(Convert.ToUInt32(metrics["dpi"])/96.0+0.5):0;
        Assert((((long)decorated["nativePinStyle"])&0x00C00000L)==0x00C00000L&&((int[])metrics["insets"])[1]>expectedTop,"Generated source negative control lacks an actual caption strip.");
        result["nativeDecoratedSourceRejected"]=true;
        result["nativeBorderlessVerified"]=true;
    }
    static ScreenshotClipboardLease ScreenshotOwnedClipboard;
    static Bitmap ScreenshotExpectedWindow;
    static Rectangle ScreenshotExpectedWindowClient;
    static List<Dictionary<string,object>> ScreenshotNativeOpenObservations,ScreenshotNativeCancelObservations;
    [StructLayout(LayoutKind.Sequential)] struct ScreenshotGuiThreadInfo {public uint size,flags;public IntPtr active,focus,capture,menuOwner,moveSize,caret;public RECT caretRect;}
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref ScreenshotGuiThreadInfo info);
    [DllImport("user32.dll")] static extern bool IsChild(IntPtr parent,IntPtr child);
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr window);
    [DllImport("dwmapi.dll")] static extern int DwmFlush();
    // The native adapter holds OpenClipboard for the entire policy call.
    static string ScreenshotReclaim(Func<bool> sameGeneration,Func<bool> sameContent,Func<bool> clear) {
        if(!sameGeneration())return "generation-changed-preserved";
        if(!sameContent())return "content-changed-preserved";
        if(!sameGeneration())return "generation-changed-preserved";
        return clear()?"verified-owned-generation-cleared":"clear-failed-preserved";
    }
    static int ScreenshotClipboardPolicyTests() {
        int reads=0,clears=0,checks=0;
        Assert(ScreenshotReclaim(delegate{return false;},delegate{reads++;return true;},delegate{clears++;return true;})=="generation-changed-preserved"&&reads==0&&clears==0,"Foreign clipboard cleanup policy read/cleared content.");
        Assert(ScreenshotReclaim(delegate{return true;},delegate{reads++;return false;},delegate{clears++;return true;})=="content-changed-preserved"&&clears==0,"Changed clipboard content cleanup policy cleared data.");
        Assert(ScreenshotReclaim(delegate{return ++checks==1;},delegate{return true;},delegate{clears++;return true;})=="generation-changed-preserved"&&clears==0,"Clipboard generation race cleanup policy cleared data.");
        Assert(ScreenshotReclaim(delegate{return true;},delegate{return true;},delegate{clears++;return true;})=="verified-owned-generation-cleared"&&clears==1,"Verified clipboard cleanup policy did not clear.");
        Assert(ScreenshotReclaim(delegate{return true;},delegate{return true;},delegate{return false;})=="clear-failed-preserved","Clipboard cleanup failure was hidden.");return 5;
    }
    sealed class ScreenshotClipboardLease {
        readonly IntPtr source;uint generation,format;string digest;IntPtr owner;bool initialized;int seedAttempt,copyAttempt,readOnlyObservationRetries;string copyPhase="cancel-baseline";
        public readonly List<Dictionary<string,object>> Observations=new List<Dictionary<string,object>>();
        void Record(Dictionary<string,object> row){Assert(Observations.Count<96,"Screenshot clipboard diagnostic bound exceeded.");row["seedAttempt"]=seedAttempt;row["copyAttempt"]=copyAttempt;row["copyPhase"]=copyPhase;row["leaseFormat"]=format;row["readOnlyObservationRetries"]=readOnlyObservationRetries;Observations.Add(row);}
        public void BeginCopy(string phase){copyAttempt++;copyPhase=phase;readOnlyObservationRetries=0;}
        public bool StableImageRead(uint before,uint after){bool stable=before!=0&&before!=generation&&before==after;if(!stable)readOnlyObservationRetries++;return stable;}
        void RecordState(string phase,bool lockedRead=false){uint sequence=GetClipboardSequenceNumber();IntPtr currentOwner=GetClipboardOwner();bool same=lockedRead&&digest!=null&&generation!=0&&sequence==generation&&currentOwner==owner;
            Record(new Dictionary<string,object>{{"phase",phase},{"expectedSequence",generation},{"observedSequence",sequence},{"ownerMatchesLease",currentOwner==owner},{"ownerIsGeneratedSource",currentOwner==source},{"expectedFormatAvailable",format!=0&&IsClipboardFormatAvailable(format)},{"formatCount",lockedRead?Math.Min(256,CountClipboardFormats()):-1},{"contentCompared",same},{"contentMatches",same&&SameContent()}});}
        static bool SeedFormatsMatch(){bool unicode=false;uint previous=0;int count=0;
            while(true){ScreenshotSetLastError(0);uint next=EnumClipboardFormats(previous);if(next==0){Assert(Marshal.GetLastWin32Error()==0,"Clipboard format enumeration failed; preserved.");break;}
                Assert(++count<=16,"Clipboard format inventory exceeded fixture bound; preserved.");
                // Windows may synthesize ANSI/OEM text and locale from our sole
                // CF_UNICODETEXT publication. No registered/other format allowed.
                if(next!=1&&next!=7&&next!=13&&next!=16)return false;unicode|=next==13;previous=next;}
            return unicode;
        }
        public ScreenshotClipboardLease(IntPtr window){source=window;}
        static string LockedDigest(uint kind) {
            IntPtr memory=GetClipboardData(kind);Assert(memory!=IntPtr.Zero,"Owned clipboard payload disappeared.");
            ulong length=GlobalSize(memory).ToUInt64();Assert(length>0&&length<=32*1024*1024,"Owned clipboard payload exceeds fixture bound.");
            IntPtr pointer=GlobalLock(memory);Assert(pointer!=IntPtr.Zero,"Owned clipboard payload could not be locked.");
            try{byte[] bytes=new byte[(int)length];Marshal.Copy(pointer,bytes,0,bytes.Length);using(var hash=System.Security.Cryptography.SHA256.Create())return Convert.ToBase64String(hash.ComputeHash(bytes));}
            finally{GlobalUnlock(memory);}
        }
        static bool EmptyLocked(){ScreenshotSetLastError(0);int count=CountClipboardFormats();Assert(count!=0||Marshal.GetLastWin32Error()==0,"Clipboard format enumeration failed; preserved.");return count==0;}
        bool SameGeneration(){return digest!=null&&generation!=0&&GetClipboardSequenceNumber()==generation&&GetClipboardOwner()==owner;}
        bool SameContent(){return IsClipboardFormatAvailable(format)&&LockedDigest(format)==digest;}
        public void RequireEmpty(){Assert(OpenClipboard(source),"Initial screenshot clipboard is busy; preserved.");try{Assert(EmptyLocked(),"FRESH_EMPTY_CLIPBOARD_REQUIRED");initialized=true;}finally{CloseClipboard();}}
        public void Seed() {
            seedAttempt++;string text="ECHOLINGO_GENERATED_SCREENSHOT_"+Guid.NewGuid().ToString("N");byte[] bytes=Encoding.Unicode.GetBytes(text+'\0');
            IntPtr memory=GlobalAlloc(0x42,new UIntPtr((uint)bytes.Length));Assert(memory!=IntPtr.Zero,"Could not allocate generated clipboard sentinel.");bool transferred=false,opened=false;
            string publishedDigest=null;uint beforeSet=0,afterSet=0,beforeClose=0;bool publicationClosed=false;
            try{IntPtr pointer=GlobalLock(memory);Assert(pointer!=IntPtr.Zero,"Could not lock generated clipboard sentinel.");try{Marshal.Copy(bytes,0,pointer,bytes.Length);}finally{GlobalUnlock(memory);}
                Assert(OpenClipboard(source),"Screenshot seed clipboard is busy; preserved.");opened=true;RecordState("before-seed",true);
                Assert(initialized&&(digest==null?EmptyLocked():SameGeneration()&&SameContent()),"Screenshot seed refused to overwrite a changed clipboard.");
                Assert(EmptyClipboard(),"Could not publish generated clipboard sentinel.");beforeSet=GetClipboardSequenceNumber();Assert(SetClipboardData(13,memory)!=IntPtr.Zero,"Could not publish generated clipboard sentinel.");transferred=true;afterSet=GetClipboardSequenceNumber();
                publishedDigest=LockedDigest(13);beforeClose=GetClipboardSequenceNumber();
            }finally{if(opened){publicationClosed=CloseClipboard();Record(new Dictionary<string,object>{{"phase","seed-publication-close"},{"sequenceBeforeSet",beforeSet},{"sequenceAfterSet",afterSet},{"sequenceBeforeClose",beforeClose},{"sequenceAfterClose",GetClipboardSequenceNumber()},{"closed",publicationClosed},{"ownerIsGeneratedSource",GetClipboardOwner()==source}});}if(!transferred)GlobalFree(memory);}
            // Publication may advance the sequence at CloseClipboard. Claim only
            // at this one immediate boundary: reopen once, require our exact
            // HWND + unique nonce digest + text-only format inventory, then a
            // stable nonzero sequence. Never rebase a later changed generation.
            Assert(publicationClosed,"Published screenshot seed could not close; preserved.");
            Assert(OpenClipboard(source),"Published screenshot seed could not be verified; preserved.");
            try{uint observed=GetClipboardSequenceNumber();bool own=GetClipboardOwner()==source,formats=own&&SeedFormatsMatch();bool content=formats&&LockedDigest(13)==publishedDigest;
                uint after=GetClipboardSequenceNumber();Record(new Dictionary<string,object>{{"phase","seed-publication-verify"},{"sequenceBeforeClose",beforeClose},{"sequenceOnReopen",observed},{"sequenceAfterRead",after},{"ownerIsGeneratedSource",own},{"formatsMatch",formats},{"contentCompared",formats},{"contentMatches",content}});
                Assert(observed!=0&&observed==after&&own&&formats&&content,"Published screenshot seed identity changed; preserved.");
                generation=observed;format=13;owner=source;digest=publishedDigest;
            }finally{CloseClipboard();RecordState("seed-verified-close");}
            Assert(SameGeneration(),"Verified screenshot seed changed after its read-only close; preserved.");
        }
        public bool SeedUnchanged() {
            Assert(OpenClipboard(source),"Screenshot cancellation clipboard is busy; preserved.");
            try{RecordState("after-cancel",true);return format==13&&SameGeneration()&&SeedFormatsMatch()&&SameContent();}
            finally{CloseClipboard();}
        }
        // Arboard uses a null clipboard owner. Do not mistake an unrelated HWND
        // for our app. Content is claimed only after the guarded Copy action and
        // independent generated-image validation, then hashed under the lock.
        public bool ObserveImage(uint observedGeneration,Func<bool> generatedPixelsMatch) {
            Assert(generatedPixelsMatch(),"Clipboard image does not match the generated fixture content; preserved.");
            if(!OpenClipboard(source)){readOnlyObservationRetries++;return false;}bool claimed=false;
            try{uint current=GetClipboardSequenceNumber();if(!StableImageRead(observedGeneration,current))return false;
                uint imageFormat=IsClipboardFormatAvailable(17)?17U:8U;Assert(IsClipboardFormatAvailable(imageFormat),"Copied image has no bounded DIB payload.");
                string value=LockedDigest(imageFormat);if(!StableImageRead(observedGeneration,GetClipboardSequenceNumber()))return false;
                Record(new Dictionary<string,object>{{"phase","image-claim"},{"sequenceBeforeOleRead",observedGeneration},{"sequenceAfterOleRead",current},{"priorOwnedSequence",generation}});
                generation=observedGeneration;format=imageFormat;owner=GetClipboardOwner();digest=value;claimed=true;RecordState("image-claim-complete",true);return true;
            }finally{CloseClipboard();if(claimed)RecordState("image-verified-close");}
        }
        public string Cleanup() {
            if(!initialized)return "not-initialized-preserved";
            if(!OpenClipboard(source))return "clipboard-busy-preserved";
            try{RecordState("cleanup",true);if(digest==null)return EmptyLocked()?"already-empty":"unclaimed-content-preserved";return ScreenshotReclaim(SameGeneration,SameContent,EmptyClipboard);}
            finally{CloseClipboard();}
        }
    }
    static bool ScreenshotPinOnly;
    const string ScreenshotCanvasName="\u56fe\u7247\u9884\u89c8\uff1b\u4f7f\u7528\u5de5\u5177\u680f\u6dfb\u52a0\u6807\u6ce8";
    static IntPtr ScreenshotWindow(int process) {
        List<IntPtr> candidates=new List<IntPtr>();
        EnumWindows(delegate(IntPtr window,IntPtr unused){
            uint owner;GetWindowThreadProcessId(window,out owner);StringBuilder name=new StringBuilder(256),title=new StringBuilder(256);
            GetClassName(window,name,name.Capacity);GetWindowText(window,title,title.Capacity);
            if(owner==process&&GetAncestor(window,2)==window&&name.ToString()=="Tauri Window"&&title.ToString().IndexOf("\u622a\u56fe",StringComparison.Ordinal)>=0)candidates.Add(window);
            return true;
        },IntPtr.Zero);return candidates.Count==1?candidates[0]:IntPtr.Zero;
    }
    static bool ScreenshotInplaceDimensionsMatch(IntPtr editor,Size pixels) {
        // Match the exact image dimensions, without an extra phase caption.
        AutomationElement dimensions=Element(editor,pixels.Width+" \u00d7 "+pixels.Height);return dimensions!=null&&!dimensions.Current.IsOffscreen;
    }
    static AutomationElement ScreenshotButton(IntPtr window,string name) {
        AutomationElementCollection matches=AutomationElement.FromHandle(window).FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.NameProperty,name),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)));
        Assert(matches.Count<=1,"Screenshot button accessible name is ambiguous: "+name);return matches.Count==1?matches[0]:null;
    }
    static void ScreenshotInvoke(Process app,IntPtr window,string name) {
        AutomationElement element=null;
        WaitFor(delegate{element=ScreenshotButton(window,name);return element!=null&&element.Current.IsEnabled&&!element.Current.IsOffscreen;},10,"Actual screenshot button unavailable: "+name,app);
        object pattern=null;bool tool=name=="\u5b9e\u5fc3\u906e\u6321"||name=="\u88c1\u526a";
        if(!tool){Assert(element.TryGetCurrentPattern(InvokePattern.Pattern,out pattern),"Screenshot action has no InvokePattern: "+name);((InvokePattern)pattern).Invoke();return;}
        Assert(tool&&element.TryGetCurrentPattern(TogglePattern.Pattern,out pattern),"Screenshot tool has no TogglePattern: "+name);
        TogglePattern toggle=(TogglePattern)pattern;Assert(toggle.Current.ToggleState==ToggleState.Off,"Screenshot tool must begin unselected; no repeated input sent.");toggle.Toggle();
        WaitFor(delegate{AutomationElement selected=ScreenshotButton(window,name);object current;return selected!=null&&selected.TryGetCurrentPattern(TogglePattern.Pattern,out current)&&((TogglePattern)current).Current.ToggleState==ToggleState.On;},5,"Screenshot tool did not become selected after its single UIA Toggle.",app);
    }
    static void ScreenshotMove(Process app,IntPtr editor,Point point) {
        Assert(GetForegroundWindow()==editor&&ForegroundPid()==app.Id,"Screenshot edit pointer would target another process; refused.");
        Rectangle desktop=SystemInformation.VirtualScreen;INPUT input=new INPUT();input.data.mouse.dx=(int)Math.Round((point.X-desktop.Left)*65535.0/(desktop.Width-1));input.data.mouse.dy=(int)Math.Round((point.Y-desktop.Top)*65535.0/(desktop.Height-1));input.data.mouse.flags=0x8000|0x4000|1;Send(new INPUT[]{input});
    }
    static void ScreenshotDrag(Process app,IntPtr editor,string tool,Size pixels,Point first,Point last,bool initialTool=false) {
        if(initialTool){WaitFor(delegate{AutomationElement button=ScreenshotButton(editor,tool);object pattern;
            return button!=null&&button.Current.IsEnabled&&!button.Current.IsOffscreen&&button.TryGetCurrentPattern(TogglePattern.Pattern,out pattern)&&((TogglePattern)pattern).Current.ToggleState==ToggleState.On;
        },5,"Web selected tool was not ready in the retained editor.",app);}else ScreenshotInvoke(app,editor,tool);SetForegroundWindow(editor);
        AutomationElement canvas=null;WaitFor(delegate{return (canvas=Element(editor,ScreenshotCanvasName))!=null&&!canvas.Current.IsOffscreen;},10,"Actual image canvas missing from UIAutomation.",app);
        System.Windows.Rect bounds=canvas.Current.BoundingRectangle;Assert(bounds.Width>0&&bounds.Height>0,"Actual image canvas has no screen bounds.");
        Assert(first.X<last.X&&first.Y<last.Y,"Fixture annotation rectangle must be ordered.");
        // Round inward at the intended image-pixel boundaries. A centered
        // canvas may start on a half physical pixel; nearest rounding expands it.
        Assert(bounds.Width>=pixels.Width&&bounds.Height>=pixels.Height,"Fixture requires actual-size or larger image display.");
        Point a=new Point((int)Math.Ceiling(bounds.X+first.X*bounds.Width/pixels.Width),(int)Math.Ceiling(bounds.Y+first.Y*bounds.Height/pixels.Height));
        Point b=new Point((int)Math.Floor(bounds.X+last.X*bounds.Width/pixels.Width),(int)Math.Floor(bounds.Y+last.Y*bounds.Height/pixels.Height));
        long initialAttempt=initialTool?CaptureNumber(ScreenshotCaptureHealth(),"attemptId"):0;
        ScreenshotMove(app,editor,a);INPUT down=new INPUT();down.data.mouse.flags=2;Send(new INPUT[]{down});
        try{Thread.Sleep(60);ScreenshotMove(app,editor,b);Thread.Sleep(60);
            if(initialTool)Assert(IsWindowVisible(editor)&&CaptureNumber(ScreenshotCaptureHealth(),"attemptId")==initialAttempt,"First stroke captured pixels before its owned release.");
        }
        finally{if(ForegroundPid()==app.Id){INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{up});}}
        if(initialTool){WaitFor(delegate{AutomationElement undo=ScreenshotButton(editor,"\u64a4\u9500");return IsWindowVisible(editor)&&ScreenshotWindow(app.Id)==editor&&undo!=null&&undo.Current.IsEnabled;},10,"First released stroke did not render in the same editor.",app);
            Assert(CaptureNumber(ScreenshotCaptureHealth(),"attemptId")==initialAttempt+1,"First released stroke must capture pixels exactly once.");ScreenshotFirstStrokeReleaseChecks++;
        }
    }
    static void ScreenshotContinueOpen(Process app,IntPtr owner) {
        bool confirmed=false;
        WaitFor(delegate{
            IntPtr foreground=GetForegroundWindow();StringBuilder name=new StringBuilder(128);GetClassName(foreground,name,name.Capacity);
            if(ForegroundPid()==app.Id&&foreground!=owner&&name.ToString()=="#32770")return true;
            AutomationElement button=ScreenshotButton(owner,"\u7ee7\u7eed\u6253\u5f00");
            if(!confirmed&&button!=null&&button.Current.IsEnabled&&!button.Current.IsOffscreen){confirmed=true;ScreenshotInvoke(app,owner,"\u7ee7\u7eed\u6253\u5f00");}
            return false;
        },10,"Open did not reach its owned native dialog after optional unsaved-image confirmation.",app);
    }
    static Dictionary<string,object> ScreenshotCancelState(Process app,IntPtr editor,IntPtr modal,string caption) {
        Dictionary<string,object> state=new Dictionary<string,object>{{"ready",false},{"dialogVisible",true},{"editorVisible",false},{"editorEnabled",false},{"savePresent",false},{"saveEnabled",false},{"editorDomInspected",false}};
        try{uint pid,editorPid;uint thread=GetWindowThreadProcessId(modal,out pid);GetWindowThreadProcessId(editor,out editorPid);
            StringBuilder name=new StringBuilder(128),title=new StringBuilder(128);GetClassName(modal,name,name.Capacity);GetWindowText(modal,title,title.Capacity);
            bool exists=modal!=IntPtr.Zero&&IsWindow(modal),own=exists&&pid==app.Id,parent=GetWindow(modal,4)==editor,foreground=GetForegroundWindow()==modal,dialog=name.ToString()=="#32770",expected=title.ToString()==caption;
            state["dialogExists"]=exists;state["dialogVisible"]=exists&&IsWindowVisible(modal);state["dialogEnabled"]=exists&&IsWindowEnabled(modal);state["dialogProcessMatches"]=own;state["ownerIsEditor"]=parent;state["classMatches"]=dialog;state["titleMatchesExpected"]=expected;
            state["foregroundIsDialog"]=foreground;state["foregroundIsEditor"]=GetForegroundWindow()==editor;state["editorVisible"]=IsWindowVisible(editor);state["editorEnabled"]=IsWindowEnabled(editor);state["editorProcessMatches"]=editorPid==app.Id;
            ScreenshotGuiThreadInfo info=new ScreenshotGuiThreadInfo();info.size=(uint)Marshal.SizeOf(typeof(ScreenshotGuiThreadInfo));bool queried=own&&thread!=0&&GetGUIThreadInfo(thread,ref info);bool focus=queried&&info.focus!=IntPtr.Zero&&GetAncestor(info.focus,2)==modal;
            state["focusQuerySucceeded"]=queried;state["focusWithinModal"]=focus;state["guiFlags"]=queried?info.flags:0;
            if(editorPid==app.Id&&IsWindowVisible(editor)&&IsWindowEnabled(editor)){AutomationElement save=ScreenshotButton(editor,"\u4fdd\u5b58\u56fe\u7247");state["editorDomInspected"]=true;state["savePresent"]=save!=null;if(save!=null){state["saveEnabled"]=save.Current.IsEnabled;state["saveOffscreen"]=save.Current.IsOffscreen;}}
            if(!own||!dialog||!expected||!parent||!foreground||!IsWindowVisible(modal)||!IsWindowEnabled(modal)||IsWindowEnabled(editor)||!focus)return state;
            // IDCANCEL is the native dialog cancellation action. Read its typed
            // accessibility readiness; do not invoke it or change keyboard focus.
            AutomationElementCollection buttons=AutomationElement.FromHandle(modal).FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button),new PropertyCondition(AutomationElement.AutomationIdProperty,"2")));
            state["cancelButtonCount"]=Math.Min(buttons.Count,8);if(buttons.Count!=1)return state;
            AutomationElement cancel=buttons[0];object pattern;bool cancelOwn=cancel.Current.ProcessId==app.Id,enabled=cancel.Current.IsEnabled,visible=!cancel.Current.IsOffscreen,supports=cancel.TryGetCurrentPattern(InvokePattern.Pattern,out pattern);
            state["cancelProcessMatches"]=cancelOwn;state["cancelEnabled"]=enabled;state["cancelVisible"]=visible;state["cancelSupportsInvoke"]=supports;state["ready"]=cancelOwn&&enabled&&visible&&supports;
        }catch(Exception error){state["snapshotExceptionHresult"]=error.HResult;}return state;
    }
    static void ScreenshotCancelFileDialog(Process app,IntPtr editor,string buttonName) {
        string phase=buttonName=="\u53e6\u5b58\u4e3a"?"save-as":"open";
        string caption=phase=="save-as"?"\u53e6\u5b58 PNG\uff08\u540c\u540d\u6587\u4ef6\u5c06\u81ea\u52a8\u7f16\u53f7\uff0c\u4e0d\u8986\u76d6\uff09":"\u6253\u5f00\u672c\u5730 PNG / JPEG \u56fe\u7247";
        Assert(ScreenshotNativeCancelObservations.Count<2,"Native cancellation diagnostic bound exceeded.");Dictionary<string,object> observation=new Dictionary<string,object>{{"phase",phase},{"escapePresses",0}};ScreenshotNativeCancelObservations.Add(observation);
        ScreenshotInvoke(app,editor,buttonName);if(phase=="open")ScreenshotContinueOpen(app,editor);IntPtr modal=IntPtr.Zero;
        try{WaitFor(delegate{modal=GetForegroundWindow();Dictionary<string,object> state=ScreenshotCancelState(app,editor,modal,caption);observation["beforeEscape"]=state;return Convert.ToBoolean(state["ready"]);},10,"Native "+phase+" dialog did not become an initialized, focused cancellation target; no key sent.",app);
            Assert(ForegroundPid()==app.Id&&GetForegroundWindow()==modal&&GetWindow(modal,4)==editor&&IsWindowEnabled(modal)&&!IsWindowEnabled(editor),"Native dialog lost ownership before cancellation; no key sent.");
            Send(new INPUT[]{Key(0x1B,false),Key(0x1B,true)});observation["escapePresses"]=1;
            WaitFor(delegate{Dictionary<string,object> state=ScreenshotCancelState(app,editor,modal,caption);observation["afterEscape"]=state;return !Convert.ToBoolean(state["dialogVisible"])&&Convert.ToBoolean(state["editorVisible"])&&Convert.ToBoolean(state["editorEnabled"])&&Convert.ToBoolean(state["savePresent"])&&Convert.ToBoolean(state["saveEnabled"]);},10,"Cancelled native "+phase+" dialog did not restore the editor.",app);
            observation["restored"]=true;
        }catch{observation["failureState"]=ScreenshotCancelState(app,editor,modal,caption);throw;}
    }
    static Dictionary<string,object> ScreenshotOpenControlMetadata(AutomationElement element,int process) {
        bool own=element.Current.ProcessId==process;Dictionary<string,object> row=new Dictionary<string,object>{{"processMatches",own}};if(!own)return row;
        string id=element.Current.AutomationId;int numeric=0;bool digits=id.Length>0&&id.Length<=8;foreach(char c in id)digits=digits&&c>='0'&&c<='9';if(digits)Int32.TryParse(id,out numeric);
        string name=element.Current.ClassName;string[] classes=new string[]{"Edit","ComboBox","ComboBoxEx32","DirectUIHWND","DUIViewWndClassName","#32770"};
        row["controlTypeId"]=element.Current.ControlType.Id;row["numericAutomationId"]=numeric;row["automationIdIsNumeric"]=digits;row["automationIdIsFileNameControlHost"]=id=="FileNameControlHost";row["classKind"]=Array.IndexOf(classes,name)+1;
        row["controlViewElement"]=element.Current.IsControlElement;row["contentViewElement"]=element.Current.IsContentElement;row["offscreen"]=element.Current.IsOffscreen;row["enabled"]=element.Current.IsEnabled;row["keyboardFocus"]=element.Current.HasKeyboardFocus;
        IntPtr window=new IntPtr(element.Current.NativeWindowHandle);row["hasNativeWindow"]=window!=IntPtr.Zero;row["nativeControlId"]=window==IntPtr.Zero?0:GetDlgCtrlID(window);
        object value;bool supports=element.TryGetCurrentPattern(ValuePattern.Pattern,out value);row["supportsValuePattern"]=supports;if(supports)row["readOnly"]=((ValuePattern)value).Current.IsReadOnly;
        // No UIA Name/Value/text or unknown identifier/class string is read out.
        return row;
    }
    static void ScreenshotDescribeOpenDialog(Process app,IntPtr editor,IntPtr modal,string format) {
        if(ScreenshotNativeOpenObservations==null||ScreenshotNativeOpenObservations.Count>=2)return;
        Dictionary<string,object> observation=new Dictionary<string,object>{{"format",format},{"afterSelectorFailure",true}};ScreenshotNativeOpenObservations.Add(observation);
        try{uint pid;GetWindowThreadProcessId(modal,out pid);StringBuilder name=new StringBuilder(128),title=new StringBuilder(128);GetClassName(modal,name,name.Capacity);GetWindowText(modal,title,title.Capacity);
            bool own=pid==app.Id,dialog=name.ToString()=="#32770",caption=title.ToString()=="\u6253\u5f00\u672c\u5730 PNG / JPEG \u56fe\u7247",parent=GetWindow(modal,4)==editor,foreground=GetForegroundWindow()==modal;
            observation["processMatches"]=own;observation["classMatches"]=dialog;observation["titleMatchesExpected"]=caption;observation["ownerIsEditor"]=parent;observation["foregroundMatches"]=foreground;observation["visible"]=IsWindowVisible(modal);
            if(!own||!dialog||!caption||!parent||!foreground)return;
            AutomationElement root=AutomationElement.FromHandle(modal);AutomationElementCollection controls=root.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ComboBox)));
            observation["controlCountCapped"]=Math.Min(controls.Count,32);observation["inventoryTruncated"]=controls.Count>32;List<Dictionary<string,object>> rows=new List<Dictionary<string,object>>();observation["controls"]=rows;int visibleEdits=0,matching1001=0,matching1001VisibleEnabled=0;
            for(int i=0;i<controls.Count&&i<32;i++){
                Dictionary<string,object> row=ScreenshotOpenControlMetadata(controls[i],app.Id);rows.Add(row);
                if(Convert.ToBoolean(row["processMatches"])&&Convert.ToInt32(row["controlTypeId"])==ControlType.Edit.Id){bool visible=!Convert.ToBoolean(row["offscreen"]);if(visible)visibleEdits++;if(Convert.ToInt32(row["numericAutomationId"])==1001){matching1001++;if(visible&&Convert.ToBoolean(row["enabled"]))matching1001VisibleEnabled++;}}
                List<Dictionary<string,object>> ancestors=new List<Dictionary<string,object>>();row["ancestors"]=ancestors;
                AutomationElement current=controls[i];for(int depth=0;depth<4;depth++){current=TreeWalker.RawViewWalker.GetParent(current);if(current==null)break;if(Automation.Compare(current,root)){row["reachedModalRoot"]=true;break;}
                    Dictionary<string,object> ancestor=ScreenshotOpenControlMetadata(current,app.Id);ancestors.Add(ancestor);if(!Convert.ToBoolean(ancestor["processMatches"]))break;}
            }
            observation["visibleEditCount"]=visibleEdits;observation["matching1001Count"]=matching1001;observation["matching1001VisibleEnabledCount"]=matching1001VisibleEnabled;
        }catch(Exception error){observation["diagnosticExceptionHresult"]=error.HResult;}
    }
    static bool ScreenshotOwnOpenDialog(Process app,IntPtr editor,IntPtr modal) {
        uint pid,editorPid;GetWindowThreadProcessId(modal,out pid);GetWindowThreadProcessId(editor,out editorPid);StringBuilder name=new StringBuilder(128),title=new StringBuilder(128);GetClassName(modal,name,name.Capacity);GetWindowText(modal,title,title.Capacity);
        return modal!=IntPtr.Zero&&pid==app.Id&&editorPid==app.Id&&name.ToString()=="#32770"&&title.ToString()=="\u6253\u5f00\u672c\u5730 PNG / JPEG \u56fe\u7247"&&GetWindow(modal,4)==editor&&GetForegroundWindow()==modal&&IsWindowVisible(modal)&&IsWindowEnabled(modal)&&!IsWindowEnabled(editor);
    }
    static bool ScreenshotFilenameNode(AutomationElement node,ControlType type,string className,int process,IntPtr modal) {
        if(node==null||node.Current.ProcessId!=process||node.Current.ControlType!=type||node.Current.ClassName!=className||node.Current.AutomationId!="1148"||!node.Current.IsEnabled||node.Current.IsOffscreen)return false;
        IntPtr window=new IntPtr(node.Current.NativeWindowHandle);uint pid;GetWindowThreadProcessId(window,out pid);
        return window!=IntPtr.Zero&&pid==process&&GetDlgCtrlID(window)==1148&&GetAncestor(window,2)==modal;
    }
    static bool ScreenshotFilenameChain(AutomationElement edit,AutomationElement root,int process,IntPtr modal) {
        // Observed on the same immutable app/runtime in focused run41175312570:
        // Edit1148 -> ComboBox1148 -> ComboBoxEx32/Pane1148 -> exact modal root.
        // Address/search/detail edits in that dialog do not satisfy this chain.
        if(!ScreenshotFilenameNode(edit,ControlType.Edit,"Edit",process,modal))return false;
        AutomationElement combo=TreeWalker.RawViewWalker.GetParent(edit);if(!ScreenshotFilenameNode(combo,ControlType.ComboBox,"ComboBox",process,modal))return false;
        AutomationElement host=TreeWalker.RawViewWalker.GetParent(combo);if(!ScreenshotFilenameNode(host,ControlType.Pane,"ComboBoxEx32",process,modal))return false;
        AutomationElement parent=TreeWalker.RawViewWalker.GetParent(host);return parent!=null&&Automation.Compare(parent,root);
    }
    static Dictionary<string,object> ScreenshotOpenGenerated(Process app,IntPtr editor,string path,string format,Bitmap expected,string output,ProcessStartInfo settingsStart=null,bool saveOpened=true) {
        Assert(File.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"Generated image input is missing or redirected.");
        byte[] original=File.ReadAllBytes(path);Assert(original.Length>0&&original.Length<65536,"Generated image input exceeds its fixture bound.");
        IntPtr dialogOwner=editor;
        if(settingsStart!=null) {
            using(Process secondary=Process.Start(settingsStart))Assert(secondary.WaitForExit(5000)&&secondary.ExitCode==0,"Explicit settings launch did not exit via the existing single-instance route.");
            dialogOwner=MainWindow(app.Id);Assert(dialogOwner!=IntPtr.Zero,"Actual settings window missing.");
            AutomationElement open=null;WaitFor(delegate{return (open=ScreenshotButton(dialogOwner,"\u6253\u5f00\u672c\u5730 PNG / JPEG"))!=null;},10,"Actual screenshot settings Open action missing.",app);
            object scroll;if(open.TryGetCurrentPattern(ScrollItemPattern.Pattern,out scroll))((ScrollItemPattern)scroll).ScrollIntoView();
            ScreenshotInvoke(app,dialogOwner,"\u6253\u5f00\u672c\u5730 PNG / JPEG");
        } else ScreenshotInvoke(app,editor,"\u6253\u5f00\u56fe\u7247");
        ScreenshotContinueOpen(app,dialogOwner);IntPtr modal=IntPtr.Zero;
        WaitFor(delegate{modal=GetForegroundWindow();StringBuilder name=new StringBuilder(128);GetClassName(modal,name,name.Capacity);return modal!=editor&&ForegroundPid()==app.Id&&name.ToString()=="#32770";},10,"Generated file Open did not show an owned native dialog.",app);
        AutomationElement edit=null;
        try{WaitFor(delegate{if(!ScreenshotOwnOpenDialog(app,dialogOwner,modal))return false;AutomationElement root=AutomationElement.FromHandle(modal);AutomationElementCollection edits=root.FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new PropertyCondition(AutomationElement.AutomationIdProperty,"1148")));
            Assert(edits.Count<=1,"Native Open file-name Edit is ambiguous; no blind input was sent.");if(edits.Count==0)return false;edit=edits[0];return ScreenshotFilenameChain(edit,root,app.Id,modal);},10,"Native Open needs the observed unique Edit/ComboBox/ComboBoxEx32 1148 chain; no blind input was sent.",app);}
        catch{ScreenshotDescribeOpenDialog(app,dialogOwner,modal,format);throw;}
        Assert(edit.Current.ProcessId==app.Id,"Native file-name Edit belongs to another process.");object raw;Assert(edit.TryGetCurrentPattern(ValuePattern.Pattern,out raw)&&!((ValuePattern)raw).Current.IsReadOnly,"Native file-name Edit is not writable.");
        Assert(ScreenshotOwnOpenDialog(app,dialogOwner,modal)&&ScreenshotFilenameChain(edit,AutomationElement.FromHandle(modal),app.Id,modal),"Native Open target identity changed before writing the generated path.");
        ((ValuePattern)raw).SetValue(path);edit.SetFocus();
        Assert(ScreenshotOwnOpenDialog(app,dialogOwner,modal)&&edit.Current.HasKeyboardFocus,"Native Open lost focus before submitting the generated path; no key sent.");Send(new INPUT[]{Key(0x0D,false),Key(0x0D,true)});
        WaitFor(delegate{AutomationElement copy=ScreenshotButton(editor,"\u590d\u5236\u56fe\u7247");return !IsWindowVisible(modal)&&IsWindowVisible(editor)&&copy!=null&&copy.Current.IsEnabled&&!copy.Current.IsOffscreen&&ScreenshotInplaceDimensionsMatch(editor,expected.Size);},15,"Successful native Open did not install the generated local image session.",app);
        using(Bitmap copied=ScreenshotClipboard(app,editor,expected.Size,delegate(Bitmap actual){return ScreenshotPixelsEqual(actual,expected);},"local-"+format)) {
            for(int y=0;y<expected.Height;y++)for(int x=0;x<expected.Width;x++)Assert(copied.GetPixel(x,y).ToArgb()==expected.GetPixel(x,y).ToArgb(),"Native local image Open changed generated decoded pixels.");
            if(saveOpened) {
            HashSet<string> existing=new HashSet<string>(Directory.GetFiles(output,"*.png"),StringComparer.OrdinalIgnoreCase);
            ScreenshotInvoke(app,editor,"\u4fdd\u5b58\u56fe\u7247");WaitFor(delegate{return Directory.GetFiles(output,"*.png").Length==existing.Count+1&&ScreenshotButton(editor,"\u4fdd\u5b58\u56fe\u7247").Current.IsEnabled;},15,"Opened local image did not save as a new PNG.",app);
            string saved=Array.Find(Directory.GetFiles(output,"*.png"),delegate(string value){return !existing.Contains(value);});Assert(saved!=null,"New opened-image PNG missing.");ScreenshotPng(saved,copied);
            }
        }
        Assert(Convert.ToBase64String(original)==Convert.ToBase64String(File.ReadAllBytes(path)),"Opening/editing/saving overwrote the original local input.");
        return new Dictionary<string,object>{{"format",format},{"nativeDialogSubmitted",true},{"copiedPixelSize",new int[]{expected.Width,expected.Height}},{"savedFlattenedPngPixelsMatched",saveOpened},{"sourceBytesUnchanged",true},{"ok",true}};
    }
    static bool ScreenshotPixelsEqual(Bitmap actual,Bitmap expected) {
        if(actual.Size!=expected.Size)return false;for(int y=0;y<actual.Height;y++)for(int x=0;x<actual.Width;x++)if(actual.GetPixel(x,y).ToArgb()!=expected.GetPixel(x,y).ToArgb())return false;return true;
    }
    static bool ScreenshotCroppedPixels(Bitmap actual) {
        if(actual.Size!=new Size(624,94))return false;
        for(int y=0;y<actual.Height;y++)for(int x=0;x<actual.Width;x++) {
            Color expected=x>=2&&x<72&&y>=2&&y<62?Color.FromArgb(228,93,104):x<312?Color.FromArgb(23,101,199):Color.FromArgb(210,60,90);
            if(actual.GetPixel(x,y).ToArgb()!=expected.ToArgb())return false;
        }return true;
    }
    static Bitmap ScreenshotClipboard(Process app,IntPtr editor,Size expected,Func<Bitmap,bool> generatedPixelsMatch,string copyPhase,Action<string> observeCopy=null,Action invokeCopy=null) {
        ScreenshotOwnedClipboard.BeginCopy(copyPhase);ScreenshotOwnedClipboard.Seed();AutomationElement inplace=ScreenshotButton(editor,"\u590d\u5236\u622a\u56fe\u5e76\u5b8c\u6210");bool closes=inplace!=null&&!inplace.Current.IsOffscreen;if(observeCopy!=null)observeCopy("beforeInvoke");if(invokeCopy!=null)invokeCopy();else ScreenshotInvoke(app,editor,closes?"\u590d\u5236\u622a\u56fe\u5e76\u5b8c\u6210":"\u590d\u5236\u56fe\u7247");if(observeCopy!=null)observeCopy("afterInvoke");
        Bitmap result=null;bool accepted=false;
        try{WaitFor(delegate{
            uint generation=GetClipboardSequenceNumber();
            // The one UIA Copy is asynchronous. Observe only; never resend it.
            if(!ScreenshotOwnedClipboard.StableImageRead(generation,generation))return false;
            try { if(!Clipboard.ContainsImage())return false;using(Image image=Clipboard.GetImage()){if(image==null)return false;result=new Bitmap(image);}
                uint after=GetClipboardSequenceNumber();
                if(!ScreenshotOwnedClipboard.StableImageRead(generation,after)){result.Dispose();result=null;return false;}
                Assert(result.Size==expected,"Clipboard pixels have wrong dimensions after real crop.");
                if(!ScreenshotOwnedClipboard.ObserveImage(generation,delegate{return generatedPixelsMatch(result);})){result.Dispose();result=null;return false;}return true; }
            catch(System.Runtime.InteropServices.ExternalException){if(result!=null){result.Dispose();result=null;}return false;}
        },10,"Actual editor Copy did not publish an image to the system clipboard.",app);if(closes)WaitFor(delegate{return !IsWindowVisible(editor);},10,"In-place copy did not dismiss capture after clipboard commit.",app);accepted=true;return result;}
        finally{if(!accepted&&result!=null)result.Dispose();}
    }
    static void ScreenshotPng(string path,Bitmap expected) {
        Assert((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"Generated export became a reparse point.");
        byte[] bytes=File.ReadAllBytes(path);Assert(bytes.Length>20&&bytes.Length<=32*1024*1024,"Generated PNG has invalid length.");
        Assert(bytes[0]==137&&bytes[1]==80&&bytes[2]==78&&bytes[3]==71,"Export is not PNG.");
        int position=8;bool ended=false;
        while(position+12<=bytes.Length){uint length=((uint)bytes[position]<<24)|((uint)bytes[position+1]<<16)|((uint)bytes[position+2]<<8)|bytes[position+3];string kind=Encoding.ASCII.GetString(bytes,position+4,4);
            Assert(length<=32*1024*1024&&position+12L+length<=bytes.Length,"PNG chunk exceeds bounds.");
            Assert(kind!="eXIf"&&kind!="tEXt"&&kind!="zTXt"&&kind!="iTXt"&&kind!="iCCP","Flattened PNG retained source/edit metadata.");
            position+=12+(int)length;if(kind=="IEND"){ended=true;break;}}
        Assert(ended&&position==bytes.Length,"Export PNG has trailing hidden data or missing IEND.");
        using(Bitmap actual=new Bitmap(path)) { Assert(actual.Size==expected.Size,"Saved PNG is not the real cropped size.");
            for(int y=0;y<actual.Height;y++)for(int x=0;x<actual.Width;x++)Assert(actual.GetPixel(x,y).ToArgb()==expected.GetPixel(x,y).ToArgb(),"Saved PNG differs from flattened system clipboard pixels."); }
    }
    static bool ScreenshotWindowPixelsMatch(Bitmap actual,Dictionary<string,object> evidence) {
        // Reuse only the already-read clipboard bitmap and owned generated baseline.
        // Export counts/geometry, never pixels, colors, image bytes or content hashes.
        Bitmap expected=ScreenshotExpectedWindow;
        bool sameSize=expected!=null&&actual.Size==expected.Size;evidence["dimensionsEqual"]=sameSize;
        if(!sameSize)return false;
        int count=0,clientCount=0,minX=actual.Width,minY=actual.Height,maxX=-1,maxY=-1;
        for(int y=0;y<actual.Height;y++)for(int x=0;x<actual.Width;x++) {
            if(actual.GetPixel(x,y).ToArgb()==expected.GetPixel(x,y).ToArgb())continue;
            count++;if(ScreenshotExpectedWindowClient.Contains(x,y))clientCount++;
            minX=Math.Min(minX,x);minY=Math.Min(minY,y);maxX=Math.Max(maxX,x);maxY=Math.Max(maxY,y);
        }
        evidence["differentPixels"]=count;evidence["clientDifferentPixels"]=clientCount;evidence["nonclientDifferentPixels"]=count-clientCount;
        evidence["differenceBounds"]=count==0?new int[]{0,0,0,0}:new int[]{minX,minY,maxX-minX+1,maxY-minY+1};
        evidence["exactPixelsMatch"]=count==0;return count==0;
    }
    static void ScreenshotObserveWindowCopy(Form source,Process app,IntPtr editor,Rectangle expectedFrame,string phase,Dictionary<string,object> evidence) {
        IntPtr foreground=GetForegroundWindow();uint pid;GetWindowThreadProcessId(source.Handle,out pid);
        Assert(pid==Process.GetCurrentProcess().Id&&IsWindowVisible(source.Handle),"Window-copy observation lost its generated source.");
        RECT frame=new RECT(),client=new RECT();bool frameOk=DwmGetWindowAttribute(source.Handle,9,out frame,Marshal.SizeOf(typeof(RECT)))==0;
        bool clientOk=GetClientRect(source.Handle,out client);Point first=new Point(client.left,client.top),last=new Point(client.right,client.bottom);
        clientOk=clientOk&&ClientToScreen(source.Handle,ref first)&&ClientToScreen(source.Handle,ref last);
        Dictionary<string,object> state=new Dictionary<string,object>{{"foregroundIsSource",foreground==source.Handle},{"foregroundIsEditor",foreground==editor},{"foregroundIsNull",foreground==IntPtr.Zero},{"sourceFrameMeasured",frameOk},{"sourceFrameUnchanged",frameOk&&Rectangle.FromLTRB(frame.left,frame.top,frame.right,frame.bottom)==expectedFrame},{"sourceClientMeasured",clientOk},{"sourceClientUnchanged",clientOk&&Rectangle.FromLTRB(first.X-expectedFrame.X,first.Y-expectedFrame.Y,last.X-expectedFrame.X,last.Y-expectedFrame.Y)==ScreenshotExpectedWindowClient}};
        uint foregroundPid;GetWindowThreadProcessId(foreground,out foregroundPid);state["foregroundIsApp"]=foreground!=IntPtr.Zero&&foregroundPid==app.Id;
        evidence[phase]=state;
    }
    static Dictionary<string,object> ScreenshotPicker(Form form,Panel image,Process app,Point pointer,uint oldHelper,bool verifyWindow=false) {
        OnUi(form,delegate{form.Activate();SetForegroundWindow(form.Handle);image.Refresh();});RequireForeground(form);MoveGenerated(form,pointer);
        RECT raw;Assert(DwmGetWindowAttribute(form.Handle,9,out raw,Marshal.SizeOf(typeof(RECT)))==0,"Cannot independently measure screenshot source frame.");
        Rectangle frame=Rectangle.FromLTRB(raw.left,raw.top,raw.right,raw.bottom),display=Screen.FromPoint(pointer).Bounds;
        if(verifyWindow) {
            Assert(SystemInformation.VirtualScreen.Contains(frame)&&GetForegroundWindow()==form.Handle,"Generated screenshot baseline is not entirely owned/visible.");
            OnUi(form,delegate{form.Refresh();});Assert(DwmFlush()==0,"Generated source frame paint did not settle.");
            RECT client;Assert(GetClientRect(form.Handle,out client),"Cannot measure generated source client area.");Point firstClient=new Point(client.left,client.top),lastClient=new Point(client.right,client.bottom);
            Assert(ClientToScreen(form.Handle,ref firstClient)&&ClientToScreen(form.Handle,ref lastClient),"Cannot map generated source client area.");
            ScreenshotExpectedWindowClient=Rectangle.FromLTRB(firstClient.X-frame.X,firstClient.Y-frame.Y,lastClient.X-frame.X,lastClient.Y-frame.Y);
            ScreenshotExpectedWindow=new Bitmap(frame.Width,frame.Height,System.Drawing.Imaging.PixelFormat.Format24bppRgb);using(Graphics graphics=Graphics.FromImage(ScreenshotExpectedWindow))graphics.CopyFromScreen(frame.Location,Point.Empty,frame.Size,CopyPixelOperation.SourceCopy);
        }
        Dictionary<string,object> ready=new Dictionary<string,object>();Stopwatch clock=Stopwatch.StartNew();
        Send(new INPUT[]{Key(0x70,false),Key(0x70,true)}); // Exactly one real unmodified F1.
        WaitFor(delegate{return AppOcrReady(form,app.Id,form.Handle,frame,pointer,display,ready,oldHelper,clock);},25,"Actual F1 did not produce verified native hover edges over the generated window.",app);
        ready["shortcut"]="F1";ready["hotkeyPresses"]=1;ready["expectedWindowDimensions"]=new int[]{frame.Width,frame.Height};ready["expectedWindowBounds"]=RectValue(frame);return ready;
    }
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    const string PinnedImageName="\u5df2\u56fa\u5b9a\u7684\u622a\u56fe\uff08\u5305\u542b\u7f16\u8f91\u540e\u7684\u6807\u6ce8\uff09";
    static List<IntPtr> ScreenshotPins(int process) {
        List<IntPtr> result=new List<IntPtr>();
        EnumWindows(delegate(IntPtr window,IntPtr unused){
            uint owner;GetWindowThreadProcessId(window,out owner);StringBuilder title=new StringBuilder(128),name=new StringBuilder(128);
            GetWindowText(window,title,title.Capacity);GetClassName(window,name,name.Capacity);
            if(owner==process&&GetAncestor(window,2)==window&&name.ToString()=="Tauri Window"&&title.ToString()=="\u8d34\u56fe \u00b7 EchoLingo")result.Add(window);
            return true;
        },IntPtr.Zero);return result;
    }
    static bool ScreenshotPinTopmost(IntPtr pin){return (GetWindowLongPtr(pin,-20).ToInt64()&8)!=0;}
    static Rectangle ScreenshotPinBounds(IntPtr pin){RECT r=new RECT();Assert(IsWindow(pin)&&GetWindowRect(pin,out r),"Generated pin HWND disappeared before measurement.");return Rectangle.FromLTRB(r.left,r.top,r.right,r.bottom);}
    static void ScreenshotPinToggle(Process app,IntPtr pin,bool before,Dictionary<string,object> result) {
        string name=before?"\u53d6\u6d88\u7f6e\u9876":"\u7f6e\u9876\u8d34\u56fe";AutomationElement button=null;object pattern=null;
        WaitFor(delegate{button=ScreenshotButton(pin,name);return button!=null&&button.Current.IsEnabled&&!button.Current.IsOffscreen;},10,"Pin toggle not ready in actual WebView.",app);
        Assert(button.TryGetCurrentPattern(TogglePattern.Pattern,out pattern),"Pin toggle has no typed UIA TogglePattern.");
        TogglePattern toggle=(TogglePattern)pattern;Assert(toggle.Current.ToggleState==(before?ToggleState.On:ToggleState.Off),"Pin toggle initial accessibility state disagrees with native topmost state.");toggle.Toggle();
        Dictionary<string,object> observation=new Dictionary<string,object>();result[before?"nativeUnpinObservation":"nativeRepinObservation"]=observation;
        WaitFor(delegate{
            bool exists=IsWindow(pin),visible=IsWindowVisible(pin),topmost=exists&&ScreenshotPinTopmost(pin);
            observation["exists"]=exists;observation["visible"]=visible;observation["topmost"]=topmost;
            AutomationElement expected=exists?ScreenshotButton(pin,before?"\u7f6e\u9876\u8d34\u56fe":"\u53d6\u6d88\u7f6e\u9876"):null;
            AutomationElement prior=exists?ScreenshotButton(pin,name):null;
            observation["expectedLabelPresent"]=expected!=null;observation["priorLabelPresent"]=prior!=null;
            observation["expectedControlDisabled"]=expected!=null&&!expected.Current.IsEnabled;observation["priorControlDisabled"]=prior!=null&&!prior.Current.IsEnabled;
            return visible&&topmost!=before&&expected!=null;
        },10,"Pin UI toggle did not change native WS_EX_TOPMOST.",app);
    }
    static void ScreenshotPinPixels(Process app,IntPtr pin,Size pixels,bool annotated) {
        AutomationElement image=null;WaitFor(delegate{return (image=Element(pin,PinnedImageName))!=null&&!image.Current.IsOffscreen;},10,"Decoded pinned image is missing from actual WebView accessibility.",app);
        System.Windows.Rect box=image.Current.BoundingRectangle;Assert(box.Width>0&&box.Height>0&&ScreenshotPinTopmost(pin)&&IsWindowVisible(pin),"Generated pinned image is not visible/topmost.");
        double scale=Math.Min(box.Width/pixels.Width,box.Height/pixels.Height),left=box.X+(box.Width-pixels.Width*scale)/2,top=box.Y+(box.Height-pixels.Height*scale)/2;
        Point[] samples=new Point[]{new Point(40,40),new Point(150,80),new Point(500,80)};
        Color[] expected=new Color[]{annotated?Color.FromArgb(228,93,104):Color.FromArgb(23,101,199),Color.FromArgb(23,101,199),Color.FromArgb(210,60,90)};
        Assert(DwmFlush()==0,"Generated pin did not settle before bounded pixel observation.");
        for(int sampleIndex=0;sampleIndex<samples.Length;sampleIndex++) {
            Point point=new Point((int)Math.Round(left+samples[sampleIndex].X*scale),(int)Math.Round(top+samples[sampleIndex].Y*scale));Rectangle roi=new Rectangle(point.X-1,point.Y-1,3,3);
            Assert(ScreenshotPinBounds(pin).Contains(roi)&&Screen.FromHandle(pin).WorkingArea.Contains(roi),"Generated pin pixel ROI is outside its owned visible window.");
            for(int y=roi.Top;y<roi.Bottom;y++)for(int x=roi.Left;x<roi.Right;x++) {
                IntPtr visible=GetAncestor(WindowFromPoint(new Point(x,y)),2);uint owner;GetWindowThreadProcessId(visible,out owner);
                Assert(visible==pin&&owner==app.Id,"Generated pin ROI is occluded; no foreign screen pixels read.");
            }
            using(Bitmap sample=new Bitmap(3,3)) { using(Graphics graphics=Graphics.FromImage(sample))graphics.CopyFromScreen(roi.Location,Point.Empty,roi.Size,CopyPixelOperation.SourceCopy);
                Color wanted=expected[sampleIndex];for(int y=0;y<3;y++)for(int x=0;x<3;x++){Color color=sample.GetPixel(x,y);Assert(Math.Abs(color.R-wanted.R)<=3&&Math.Abs(color.G-wanted.G)<=3&&Math.Abs(color.B-wanted.B)<=3,"Pinned raster lost its opaque annotation or untouched generated source pixels.");} }
        }
    }
    // Observe only the owned app's fixed error/status control. Never export its
    // source text, arbitrary UI strings, screenshot bytes or another app's UI.
    static void ScreenshotPreparationObservation(Process app,IntPtr source,IntPtr editor,uint helper,Dictionary<string,object> observation) {
        observation["editorFound"]=editor!=IntPtr.Zero;
        observation["editorVisible"]=editor!=IntPtr.Zero&&IsWindowVisible(editor);
        observation["helperExited"]=ProcessExited(helper);
        observation["foregroundIsApp"]=ForegroundPid()==app.Id;observation["foregroundIsGeneratedSource"]=GetForegroundWindow()==source;
        RECT frame;if(editor!=IntPtr.Zero&&GetWindowRect(editor,out frame))observation["editorPhysicalBounds"]=new int[]{frame.left,frame.top,frame.right-frame.left,frame.bottom-frame.top};
        IntPtr main=MainWindow(app.Id);observation["mainVisible"]=main!=IntPtr.Zero&&IsWindowVisible(main);
        if(main==IntPtr.Zero||!IsWindowVisible(main))return;
        try {
            AutomationElement own=AutomationElement.FromHandle(main);
            Assert(own.Current.ProcessId==app.Id,"Screenshot observation root is not owned.");
            AutomationElement toast=own.FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.AutomationIdProperty,"toast"));
            observation["toastControlFound"]=toast!=null;if(toast==null)return;
            string message=toast.Current.Name??"";
            if(message.Length==0){AutomationElement text=toast.FindFirst(TreeScope.Children,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text));if(text!=null)message=text.Current.Name??"";}
            observation["toastNonempty"]=message.Length>0;
            foreach(string code in new string[]{"SCREENSHOT_BUSY","SCREENSHOT_CAPTURE","SCREENSHOT_DECODE","SCREENSHOT_ENCODE","SCREENSHOT_FORMAT","SCREENSHOT_GEOMETRY","SCREENSHOT_INPUT","SCREENSHOT_SIZE","SCREENSHOT_TIME","SCREENSHOT_WINDOW","WINDOW_HANDLE","WINDOW_SHOW","NATIVE_PROTOCOL","CAPTURE","CAPTURE_DISPLAY_CHANGED","CAPTURE_INPUT_HOST","CAPTURE_OVERLAY","CANCELLED"})
                if(message.StartsWith(code+":",StringComparison.Ordinal))observation["knownActionErrorCode"]=code;
            // Distinguish the production native viewport gate from other geometry
            // failures using fixed source literals, not free-form diagnostics.
            if(message=="SCREENSHOT_GEOMETRY: \u539f\u5730\u622a\u56fe\u7a97\u53e3\u4f4d\u7f6e\u6216 DPI \u5df2\u53d8\u5316\uff0c\u8bf7\u91cd\u65b0\u622a\u56fe")observation["nativeViewportGateFailed"]=true;
        } catch(Exception error){observation["statusObservationErrorType"]=error.GetType().Name;}
    }
    static Dictionary<string,object> ScreenshotPinForeground(Process app,IntPtr source,IntPtr editor,IntPtr pin,IntPtr main) {
        IntPtr foreground=GetForegroundWindow();uint process=0;if(foreground!=IntPtr.Zero)GetWindowThreadProcessId(foreground,out process);
        return new Dictionary<string,object>{{"isGeneratedSource",foreground==source},{"isEditor",editor!=IntPtr.Zero&&foreground==editor},{"isPin",pin!=IntPtr.Zero&&foreground==pin},{"isMain",main!=IntPtr.Zero&&foreground==main},{"isApp",process==app.Id},{"isZero",foreground==IntPtr.Zero}};
    }
    static Func<Dictionary<string,object>> ScreenshotCaptureHealth;
    static long ScreenshotInitialAttempt;
    static int ScreenshotFirstStrokeReleaseChecks;
    static readonly Dictionary<uint,IntPtr> ScreenshotSelectionEditors=new Dictionary<uint,IntPtr>();
    static Rectangle ScreenshotWebSelection(IntPtr editor,Dictionary<string,object> observation=null) {
        AutomationElement canvas=Element(editor,ScreenshotCanvasName);bool offscreen=canvas!=null&&canvas.Current.IsOffscreen;
        if(observation!=null){observation["canvasPresent"]=canvas!=null;observation["canvasOffscreen"]=offscreen;}
        if(canvas==null||offscreen)return Rectangle.Empty;
        System.Windows.Rect box=canvas.Current.BoundingRectangle;
        return new Rectangle((int)Math.Round(box.X),(int)Math.Round(box.Y),(int)Math.Round(box.Width),(int)Math.Round(box.Height));
    }
    static IntPtr ScreenshotRetainedEditor(Process app,uint helper) {
        IntPtr expected;Assert(ScreenshotSelectionEditors.TryGetValue(helper,out expected)&&expected!=IntPtr.Zero&&ScreenshotWindow(app.Id)==expected&&IsWindow(expected),"Persistent screenshot editor HWND was replaced.");return expected;
    }
    static void ScreenshotWaitAdjustment(Form form,Process app,uint helper,Rectangle expected,Dictionary<string,object> evidence) {
        IntPtr editor=IntPtr.Zero;
        WaitFor(delegate{
            editor=ScreenshotWindow(app.Id);if(editor==IntPtr.Zero||!IsWindowVisible(editor)||!ProcessExited(helper)||AppOverlays(app.Id)!=0)return false;
            AutomationElement select=ScreenshotButton(editor,"\u9009\u62e9"),undo=ScreenshotButton(editor,"\u64a4\u9500");object pattern;
            return ScreenshotWebSelection(editor)==expected&&select!=null&&select.Current.IsEnabled&&!select.Current.IsOffscreen&&select.TryGetCurrentPattern(TogglePattern.Pattern,out pattern)&&((TogglePattern)pattern).Current.ToggleState==ToggleState.On&&undo!=null&&!undo.Current.IsEnabled;
        },10,"Released F1 did not hand off exact geometry to the persistent Web editor.",app);
        RequireForeground(form);Assert((GetWindowLongPtr(editor,-20).ToInt64()&0x08000000L)!=0,"Geometry editor lost passive NOACTIVATE style.");
        ScreenshotSelectionEditors[helper]=editor;
        evidence["selectionAttemptId"]=CaptureNumber(ScreenshotCaptureHealth(),"attemptId");evidence["webAdjustmentVisible"]=true;evidence["initialWebAdjustmentPreservedSourceForeground"]=true;evidence["selectionHelperExitedBeforeAdjustment"]=true;
    }
    static void ScreenshotWebPoint(Form form,Process app,IntPtr editor,Point point) {
        MoveGenerated(form,point);RequireForeground(form);IntPtr target=GetAncestor(WindowFromPoint(point),2);uint pid;GetWindowThreadProcessId(target,out pid);
        Assert(target==editor&&pid==app.Id&&IsWindowVisible(target),"Web adjustment input would target a foreign window; refused.");
    }
    static int[] ScreenshotRectObservation(Rectangle rect) {return new int[]{rect.X,rect.Y,rect.Width,rect.Height};}
    static void ScreenshotAdjustmentFailureState(Process app,IntPtr editor,Dictionary<string,object> observation) {
        // Read only this owned editor. Export fixed categories, never UI text.
        try {
            AutomationElement root=AutomationElement.FromHandle(editor);Assert(root.Current.ProcessId==app.Id,"Adjustment diagnostic root is not owned.");
            AutomationElement select=ScreenshotButton(editor,"\u9009\u62e9");object pattern;
            observation["selectPresent"]=select!=null;
            if(select!=null){observation["selectEnabled"]=select.Current.IsEnabled;observation["selectOffscreen"]=select.Current.IsOffscreen;observation["selectOn"]=select.TryGetCurrentPattern(TogglePattern.Pattern,out pattern)&&((TogglePattern)pattern).Current.ToggleState==ToggleState.On;}
            AutomationElement status=root.FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.AutomationIdProperty,"editor-status"));
            observation["statusPresent"]=status!=null;if(status==null)return;
            string message=status.Current.Name??"";if(message.Length==0){AutomationElement text=status.FindFirst(TreeScope.Children,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text));if(text!=null)message=text.Current.Name??"";}
            observation["statusNonempty"]=message.Length!=0;string prefix="\u672a\u8c03\u6574\u9009\u533a\uff1a";
            observation["selectionUpdateError"]=message.StartsWith(prefix,StringComparison.Ordinal);
            if(message.StartsWith(prefix,StringComparison.Ordinal))message=message.Substring(prefix.Length);
            foreach(string code in new string[]{"SCREENSHOT_BUSY","SCREENSHOT_GEOMETRY","SCREENSHOT_SIZE","SCREENSHOT_SESSION","SCREENSHOT_REVISION","SCREENSHOT_WINDOW","CAPTURE_DISPLAY_CHANGED","CANCELLED"})
                if(message.StartsWith(code+":",StringComparison.Ordinal))observation["knownUpdateErrorCode"]=code;
        }catch(Exception){observation["failureStateUnavailable"]=true;}
    }
    static bool ScreenshotObservationScope(bool rootMatches,bool rootPidMatches,bool childRelationship,bool processDescendant) {
        return rootMatches&&rootPidMatches&&childRelationship&&processDescendant;
    }
    static bool ScreenshotOwnedProcess(Process app,uint pid,Dictionary<int,DateTime> known,bool discover) {
        // Reuse the fixture's existing parent query. Names alone do not prove ownership.
        try {
            if(app.HasExited)return false;
            if(pid==app.Id)return true;
            int requested=checked((int)pid);DateTime expected;
            if(known.TryGetValue(requested,out expected)){using(Process cached=Process.GetProcessById(requested))return !cached.HasExited&&cached.StartTime.ToUniversalTime()==expected;}
            if(!discover)return false;
            Dictionary<int,DateTime> path=new Dictionary<int,DateTime>();HashSet<int> visited=new HashSet<int>();int current=requested;DateTime childStarted=DateTime.MaxValue;
            for(int depth=0;depth<4;depth++) {
                if(current<=0||!visited.Add(current))return false;
                using(Process process=Process.GetProcessById(current)) {
                    if(process.HasExited||process.StartTime.ToUniversalTime()>childStarted)return false;
                    childStarted=process.StartTime.ToUniversalTime();
                    if(current==app.Id){if(app.HasExited||childStarted!=app.StartTime.ToUniversalTime())return false;foreach(KeyValuePair<int,DateTime> entry in path)known[entry.Key]=entry.Value;return true;}
                    path[current]=childStarted;
                    current=ParentPid(current);
                }
            }
        }catch(Exception){}
        return false;
    }
    static void ScreenshotCaptureObservation(Process app,IntPtr editor,uint thread,string prefix,Dictionary<string,object> result,Dictionary<int,DateTime> known,bool discover) {
        ScreenshotGuiThreadInfo info=new ScreenshotGuiThreadInfo();info.size=(uint)Marshal.SizeOf(typeof(ScreenshotGuiThreadInfo));bool queried=thread!=0&&GetGUIThreadInfo(thread,ref info);
        result[prefix+"QuerySucceeded"]=queried;
        if(queried){uint pid=0;if(info.capture!=IntPtr.Zero)GetWindowThreadProcessId(info.capture,out pid);
            result[prefix+"Null"]=info.capture==IntPtr.Zero;
            result[prefix+"OwnedEditor"]=info.capture!=IntPtr.Zero&&GetAncestor(info.capture,2)==editor&&(info.capture==editor||IsChild(editor,info.capture))&&ScreenshotOwnedProcess(app,pid,known,discover);
        }
    }
    static Dictionary<string,object> ScreenshotPointerObservation(Process app,IntPtr editor,Point point,bool inspectElement,Dictionary<int,DateTime> known) {
        Dictionary<string,object> result=new Dictionary<string,object>();
        try {
            IntPtr hit=WindowFromPoint(point),root=hit==IntPtr.Zero?IntPtr.Zero:GetAncestor(hit,2);uint pid=0,rootPid=0;uint thread=hit==IntPtr.Zero?0:GetWindowThreadProcessId(hit,out pid),rootThread=root==IntPtr.Zero?0:GetWindowThreadProcessId(root,out rootPid);
            bool descendant=root==editor&&rootPid==app.Id&&(hit==editor||IsChild(editor,hit))&&ScreenshotOwnedProcess(app,pid,known,inspectElement);
            bool owned=ScreenshotObservationScope(root==editor,rootPid==app.Id,hit==editor||IsChild(editor,hit),descendant);
            result["hitOwnedEditor"]=owned;result["hitRootIsEditor"]=root==editor;result["hitPidIsApp"]=pid==app.Id;result["hitNull"]=hit==IntPtr.Zero;result["hitVerifiedDescendant"]=descendant;
            result["hitForeign"]=hit!=IntPtr.Zero&&root!=editor;
            if(owned) {
                result["hitIsRoot"]=hit==root;result["ownedHitHandle"]=hit.ToInt64();result["ownedRootHandle"]=root.ToInt64();
                StringBuilder name=new StringBuilder(128);GetClassName(hit,name,name.Capacity);string value=name.ToString();
                result["ownedHitClass"]=value=="Tauri Window"||value=="Chrome_WidgetWin_0"||value=="Chrome_WidgetWin_1"||value=="Chrome_RenderWidgetHostHWND"||value=="Intermediate D3D Window"?value:"other-owned-class";
                ScreenshotCaptureObservation(app,editor,thread,"childCapture",result,known,inspectElement);ScreenshotCaptureObservation(app,editor,rootThread,"rootCapture",result,known,inspectElement);
                if(inspectElement) {
                    AutomationElement element=AutomationElement.FromPoint(new System.Windows.Point(point.X,point.Y));bool ownProcess=element!=null&&ScreenshotOwnedProcess(app,(uint)element.Current.ProcessId,known,true),rootReached=false;
                    if(ownProcess){AutomationElement cursor=element,editorRoot=AutomationElement.FromHandle(editor);for(int depth=0;cursor!=null&&depth<16;depth++){if(Automation.Compare(cursor,editorRoot)){rootReached=true;break;}cursor=TreeWalker.RawViewWalker.GetParent(cursor);}}
                    bool ownElement=ownProcess&&rootReached;result["uiaProcessOwned"]=ownProcess;result["uiaRootReached"]=rootReached;result["uiaOwned"]=ownElement;
                    if(ownElement){AutomationElement canvas=Element(editor,ScreenshotCanvasName);result["uiaControlTypeId"]=element.Current.ControlType.Id;result["uiaIsCanvas"]=canvas!=null&&Automation.Compare(element,canvas);result["uiaCanvasAutomationId"]=element.Current.AutomationId=="image-canvas";}
                }
            }
            result["canvasRect"]=ScreenshotRectObservation(ScreenshotWebSelection(editor,result));
        }catch(Exception){result["observationUnavailable"]=true;}
        return result;
    }
    static void ScreenshotWebDrag(Form form,Process app,uint helper,Point first,Point last,Rectangle expected,string phase,List<Dictionary<string,object>> observations) {
        Assert(observations.Count<18,"Adjustment diagnostic inventory exceeded the exact move/eight-handle pairs.");
        IntPtr editor=ScreenshotRetainedEditor(app,helper);
        Dictionary<string,object> observation=new Dictionary<string,object>{{"phase",phase},{"before",ScreenshotRectObservation(ScreenshotWebSelection(editor))},{"expected",ScreenshotRectObservation(expected)},{"pointerStart",new int[]{first.X,first.Y}},{"pointerEnd",new int[]{last.X,last.Y}},{"completed",false}};observations.Add(observation);
        Dictionary<int,DateTime> knownProcesses=new Dictionary<int,DateTime>();
        ScreenshotWebPoint(form,app,editor,first);observation["beforeDown"]=ScreenshotPointerObservation(app,editor,first,true,knownProcesses);
        INPUT down=new INPUT();down.data.mouse.flags=2;INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{down});
        try{Thread.Sleep(60);observation["afterDown"]=ScreenshotPointerObservation(app,editor,first,false,knownProcesses);ScreenshotWebPoint(form,app,editor,last);Thread.Sleep(60);observation["afterMoveBeforeUp"]=ScreenshotPointerObservation(app,editor,last,false,knownProcesses);}finally{Send(new INPUT[]{up});}
        try {
            WaitFor(delegate{
                bool same=ScreenshotRetainedEditor(app,helper)==editor,visible=IsWindowVisible(editor);observation["sameEditor"]=same;observation["editorVisible"]=visible;
                if(!same||!visible)return false;
                Rectangle actual=ScreenshotWebSelection(editor,observation);observation["lastObserved"]=ScreenshotRectObservation(actual);return actual==expected;
            },10,"Web adjustment gesture did not adopt exact expected geometry.",app);RequireForeground(form);observation["completed"]=true;
        }catch{ScreenshotAdjustmentFailureState(app,editor,observation);throw;}
    }
    static void ScreenshotWebMoveResize(Form form,Process app,uint helper,Rectangle original,Dictionary<string,object> evidence) {
        long before=CaptureNumber(ScreenshotCaptureHealth(),"attemptId");
        List<Dictionary<string,object>> observations=new List<Dictionary<string,object>>();evidence["webAdjustmentGestures"]=observations;
        Point center=new Point(original.Left+original.Width/2,original.Top+original.Height/2);
        Rectangle moved=new Rectangle(original.X+12,original.Y+8,original.Width,original.Height);
        ScreenshotWebDrag(form,app,helper,center,new Point(center.X+12,center.Y+8),moved,"move",observations);
        ScreenshotWebDrag(form,app,helper,new Point(center.X+12,center.Y+8),center,original,"move-restore",observations);
        string[] handles=new string[]{"n","ne","e","se","s","sw","w","nw"};
        int[,] edges=new int[,]{{0,-1},{1,-1},{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1}};
        for(int i=0;i<8;i++) {
            int horizontal=edges[i,0],vertical=edges[i,1],dx=-horizontal*8,dy=-vertical*8;
            Point handle=new Point(horizontal<0?original.Left:horizontal>0?original.Right:center.X,vertical<0?original.Top:vertical>0?original.Bottom:center.Y);
            Rectangle resized=Rectangle.FromLTRB(original.Left+(horizontal<0?dx:0),original.Top+(vertical<0?dy:0),original.Right+(horizontal>0?dx:0),original.Bottom+(vertical>0?dy:0));
            Point next=new Point(handle.X+dx,handle.Y+dy);
            ScreenshotWebDrag(form,app,helper,handle,next,resized,"resize-"+handles[i],observations);ScreenshotWebDrag(form,app,helper,next,handle,original,"restore-"+handles[i],observations);
        }
        Assert(CaptureNumber(ScreenshotCaptureHealth(),"attemptId")==before,"Adjusting geometry unexpectedly captured pixels.");
        evidence["webAdjustmentHandleCount"]=8;evidence["webAdjustmentMoveResizeVerified"]=true;evidence["webAdjustmentGeometryRestored"]=true;evidence["adjustmentDidNotCapturePixels"]=true;
    }
    static void ScreenshotWebAction(Form form,Process app,uint helper,string action,Dictionary<string,object> evidence) {
        IntPtr editor=ScreenshotRetainedEditor(app,helper);string name=action=="solid"?"\u5b9e\u5fc3\u906e\u6321":action=="select"?"\u9009\u62e9":action=="pin"?"\u56fa\u5b9a\u622a\u56fe\u5230\u684c\u9762":null;
        Assert(name!=null,"Unsupported fixture Web action.");long before=CaptureNumber(ScreenshotCaptureHealth(),"attemptId");AutomationElement button=null;
        WaitFor(delegate{button=ScreenshotButton(editor,name);return button!=null&&button.Current.IsEnabled&&!button.Current.IsOffscreen;},10,"Web screenshot action unavailable.",app);
        System.Windows.Rect r=button.Current.BoundingRectangle;Point center=new Point((int)(r.X+r.Width/2),(int)(r.Y+r.Height/2));
        Assert(r.Width>=4&&r.Height>=4&&Screen.FromHandle(editor).WorkingArea.Contains(center),"Web action is outside usable monitor bounds.");
        Assert((GetWindowLongPtr(editor,-20).ToInt64()&0x08000000L)!=0,"Web action lost NOACTIVATE style.");
        ScreenshotWebPoint(form,app,editor,center);AutomationElement current=ScreenshotButton(editor,name);
        Assert(current!=null&&!current.Current.IsOffscreen&&current.Current.IsEnabled&&current.Current.BoundingRectangle.Contains(center.X,center.Y),"Web action moved before paired click; refused.");
        INPUT down=new INPUT();down.data.mouse.flags=2;INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{down,up});
        evidence["webInitialAction"]=action;evidence["webActionClickCount"]=1;evidence["webActionOwnedTargetVerified"]=true;
        if(action!="pin") {
            WaitFor(delegate{AutomationElement selected=ScreenshotButton(editor,name);object pattern;return selected!=null&&selected.TryGetCurrentPattern(TogglePattern.Pattern,out pattern)&&((TogglePattern)pattern).Current.ToggleState==ToggleState.On;},5,"Web tool did not become selected.",app);
            Assert(CaptureNumber(ScreenshotCaptureHealth(),"attemptId")==before,"Choosing a tool unexpectedly captured pixels.");
            AutomationElement undo=ScreenshotButton(editor,"\u64a4\u9500");Assert(undo!=null&&!undo.Current.IsEnabled,"Choosing a tool created an edit.");evidence["toolSelectionDidNotCapturePixels"]=true;
        } else {evidence["physicalPinClickCount"]=1;evidence["nativeNoActivateBeforePhysicalClick"]=true;evidence["physicalPinClickOwnedTargetVerified"]=true;}
    }
    static void ScreenshotPassiveWindowCopy(Form form,Process app,uint helper,IntPtr editor,Dictionary<string,object> evidence) {
        Assert(ScreenshotRetainedEditor(app,helper)==editor,"Window Copy lost its retained selection editor.");RequireForeground(form);
        Assert((GetWindowLongPtr(editor,-20).ToInt64()&0x08000000L)!=0,"Window Copy requires the passive NOACTIVATE editor.");
        const string name="\u590d\u5236\u622a\u56fe\u5e76\u5b8c\u6210";
        AutomationElement button=ScreenshotButton(editor,name);
        Assert(button!=null&&button.Current.IsEnabled&&!button.Current.IsOffscreen,"Passive window Copy control is unavailable.");
        System.Windows.Rect bounds=button.Current.BoundingRectangle;Point point=new Point((int)(bounds.X+bounds.Width/2),(int)(bounds.Y+bounds.Height/2));
        Assert(SystemInformation.VirtualScreen.Contains(point),"Passive window Copy control is outside the desktop.");
        ScreenshotWebPoint(form,app,editor,point);
        AutomationElement current=ScreenshotButton(editor,name);
        Assert(ScreenshotRetainedEditor(app,helper)==editor&&current!=null&&current.Current.IsEnabled&&!current.Current.IsOffscreen&&current.Current.BoundingRectangle.Contains(point.X,point.Y),"Passive Copy control moved before its single click.");
        evidence["copyPhysicalTargetOwned"]=true;evidence["copyNoActivateVerified"]=true;evidence["copySourceForegroundBefore"]=true;
        INPUT down=new INPUT();down.data.mouse.flags=2;INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{down,up});
        evidence["copyInputMethod"]="owned-passive-physical-click";evidence["copyClickCount"]=1;
        RequireForeground(form);evidence["copySourceForegroundAfterClick"]=true;
    }
    static void ScreenshotRecordCaptureCounts(Dictionary<string,object> report,Dictionary<string,object> after,int selections,int deferred) {
        Assert(VerifiedNativeChildren.Count==selections,"F1 picker identity count differs from exact selection cycles.");
        long attempts=CaptureNumber(after,"attemptId")-ScreenshotInitialAttempt;
        Assert(ScreenshotFirstStrokeReleaseChecks==(ScreenshotPinOnly?1:4),"Exact first-stroke release checks required.");report["verifiedFirstStrokeReleaseChecks"]=ScreenshotFirstStrokeReleaseChecks;
        Assert(attempts==selections+deferred,"Unexpected selected-region capture attempt count.");
        report["verifiedF1SelectionGenerations"]=VerifiedNativeChildren.Count;report["verifiedDeferredPixelCaptures"]=deferred;report["verifiedNativeCaptureAttempts"]=attempts;
    }
    static void ScreenshotRequireDeferredReleased(Dictionary<string,object> health) {
        Assert(CaptureNumber(health,"nativeDeferredCapture")==1&&CaptureNumber(health,"attemptStage")==4&&CaptureNumber(health,"helperResponseReceived")==1&&CaptureNumber(health,"resultOk")==1,"Deferred pixels did not complete successfully.");
        foreach(string field in new string[]{"hookRunningAfterStop","inputPlaneRemainingAfterCleanup","currentHostSessionReserved","currentHostOwnedButtons"})Assert(CaptureNumber(health,field)==0,"Deferred capture retained native input resources.");
    }
    static void ScreenshotInteractAfterCapture(Process app,IntPtr editor,Dictionary<string,object> evidence) {
        Assert(ScreenshotWindow(app.Id)==editor&&IsWindowVisible(editor),"Post-capture interaction lost its editor.");
        AutomationElement button=ScreenshotButton(editor,"\u5b9e\u5fc3\u906e\u6321");object pattern;
        Assert(button!=null&&button.Current.IsEnabled&&!button.Current.IsOffscreen&&button.TryGetCurrentPattern(TogglePattern.Pattern,out pattern)&&((TogglePattern)pattern).Current.ToggleState==ToggleState.On,"Post-capture solid tool must already be selected.");
        System.Windows.Rect bounds=button.Current.BoundingRectangle;Point center=new Point((int)(bounds.X+bounds.Width/2),(int)(bounds.Y+bounds.Height/2));Rectangle desktop=SystemInformation.VirtualScreen;
        Assert(desktop.Contains(center),"Post-capture tool is outside desktop.");
        INPUT move=new INPUT();move.data.mouse.dx=(int)Math.Round((center.X-desktop.Left)*65535.0/(desktop.Width-1));move.data.mouse.dy=(int)Math.Round((center.Y-desktop.Top)*65535.0/(desktop.Height-1));move.data.mouse.flags=0x8000|0x4000|1;Send(new INPUT[]{move});
        IntPtr target=GetAncestor(WindowFromPoint(center),2);uint pid;GetWindowThreadProcessId(target,out pid);AutomationElement current=ScreenshotButton(editor,"\u5b9e\u5fc3\u906e\u6321");
        Assert(target==editor&&pid==app.Id&&IsWindowVisible(editor)&&current!=null&&current.Current.IsEnabled&&!current.Current.IsOffscreen&&current.Current.BoundingRectangle.Contains(center.X,center.Y),"Post-capture tool click would target a foreign surface; refused.");
        INPUT down=new INPUT();down.data.mouse.flags=2;INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{down,up});
        WaitFor(delegate{return GetForegroundWindow()==editor&&ForegroundPid()==app.Id;},5,"Owned post-capture tool interaction did not activate the editor.",app);
        evidence["explicitEditorInteractionVerified"]=true;evidence["postCaptureInteractionTarget"]="selected-solid-tool";evidence["postCaptureInteractionClicks"]=1;
    }
    static Dictionary<string,object> ScreenshotPinCase(Form form,Panel image,Process app,Point first,Point last,Size selected,uint previous,string output,Dictionary<string,object> report,bool annotated) {
        Assert(ScreenshotPins(app.Id).Count==0,"Pin fixture must start without another app-owned reference window.");
        IntPtr main=MainWindow(app.Id);Assert(main!=IntPtr.Zero,"Pin test must bind the exact main HWND before any pin exists.");
        int files=Directory.GetFiles(output).Length;Assert(ScreenshotOwnedClipboard.SeedUnchanged(),"Pin case requires its unchanged owned clipboard sentinel.");
        Dictionary<string,object> result=ScreenshotPicker(form,image,app,first,previous);report["screenshotPinCaptureAttempt"]=result;result["annotationApplied"]=annotated;result["physicalPinClickCount"]=0;result["pinInputMethod"]=annotated?"uia-invoke-from-active-editor":"owned-web-adjustment-click";
        Dictionary<string,object> preparation=new Dictionary<string,object>();report["screenshotPinPreparation"]=preparation;IntPtr pin=IntPtr.Zero,editor=IntPtr.Zero;bool finished=false;
        try {
            MoveGenerated(form,first);INPUT down=new INPUT();down.data.mouse.flags=2;Send(new INPUT[]{down});Thread.Sleep(80);MoveGenerated(form,last);Thread.Sleep(80);INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{up});
            uint helper=Convert.ToUInt32(result["helperProcessId"]);Rectangle selection=Rectangle.FromLTRB(first.X,first.Y,last.X,last.Y);
            ScreenshotWaitAdjustment(form,app,helper,selection,result);
            ScreenshotWebMoveResize(form,app,helper,selection,result);
            editor=ScreenshotRetainedEditor(app,helper);result["persistentEditorIdentityVerified"]=true;
            Assert(ScreenshotOwnedClipboard.SeedUnchanged()&&Directory.GetFiles(output).Length==files,"Web adjustment produced a clipboard/file side effect.");
            if(annotated) {
                ScreenshotWebAction(form,app,helper,"solid",result);
                WaitFor(delegate{
                    editor=ScreenshotWindow(app.Id);ScreenshotPreparationObservation(app,form.Handle,editor,helper,preparation);
                    bool canvas=editor!=IntPtr.Zero&&IsWindowVisible(editor)&&Element(editor,ScreenshotCanvasName)!=null;int overlays=AppOverlays(app.Id);
                    preparation["canvasAccessible"]=canvas;preparation["remainingNativeOverlays"]=overlays;
                    return editor!=IntPtr.Zero&&IsWindowVisible(editor)&&canvas&&overlays==0;
                },25,"Web solid action did not retain the production in-place editor.",app);
                RequireForeground(form);result["initialEditorShowPreservedSourceForeground"]=true;
                ScreenshotDrag(app,editor,"\u5b9e\u5fc3\u906e\u6321",selected,new Point(10,10),new Point(80,70),true);result["webInitialToolSelected"]=true;
                WaitFor(delegate{AutomationElement undo=ScreenshotButton(editor,"\u64a4\u9500");return undo!=null&&undo.Current.IsEnabled;},10,"Pin fixture annotation did not commit.",app);
                Assert(ScreenshotRetainedEditor(app,helper)==editor,"Annotation editor identity changed.");ScreenshotInteractAfterCapture(app,editor,result);
            } else RequireForeground(form);
            result["foregroundBeforePinInvoke"]=ScreenshotPinForeground(app,form.Handle,editor,pin,main);
            if(annotated)ScreenshotInvoke(app,editor,"\u56fa\u5b9a\u622a\u56fe\u5230\u684c\u9762");
            else ScreenshotWebAction(form,app,helper,"pin",result);
            List<IntPtr> created=ScreenshotPins(app.Id);Assert(created.Count<=1,"One pin action created multiple reference windows.");if(created.Count==1)pin=created[0];
            Dictionary<string,object> afterInvoke=ScreenshotPinForeground(app,form.Handle,editor,pin,main);result["foregroundAfterPinInvoke"]=afterInvoke;
            Assert(!Convert.ToBoolean(afterInvoke["isPin"])&&!Convert.ToBoolean(afterInvoke["isMain"]),"Pin invocation activated the pin or main window.");
            if(!annotated)Assert(Convert.ToBoolean(afterInvoke["isZero"])||Convert.ToBoolean(afterInvoke["isGeneratedSource"]),"Passive pin click changed foreground.");
            int foregroundSamples=0;
            // Retain bounded foreground evidence before outer fixture cleanup.
            // Do not reactivate the source after pinning to manufacture a pass.
            WaitFor(delegate{editor=ScreenshotWindow(app.Id);List<IntPtr> pins=ScreenshotPins(app.Id);Assert(pins.Count<=1,"One pin action created multiple reference windows.");if(pins.Count==1)pin=pins[0];
                Assert(editor==ScreenshotRetainedEditor(app,helper),"Deferred capture replaced the persistent editor HWND.");
                bool ready=pin!=IntPtr.Zero&&pin!=editor&&IsWindowVisible(pin)&&Element(pin,PinnedImageName)!=null&&ScreenshotButton(pin,"\u53d6\u6d88\u7f6e\u9876")!=null&&ScreenshotButton(pin,"\u53d6\u6d88\u7f6e\u9876").Current.IsEnabled&&!IsWindowVisible(editor)&&AppOverlays(app.Id)==0&&ProcessExited(helper);
                Dictionary<string,object> foreground=ScreenshotPinForeground(app,form.Handle,editor,pin,main);result["foregroundDuringPinHandoff"]=foreground;result["handoffForegroundSamples"]=++foregroundSamples;
                Assert(!Convert.ToBoolean(foreground["isPin"])&&!Convert.ToBoolean(foreground["isMain"]),"Pin creation activated the pin or main window.");
                if(!annotated)Assert(Convert.ToBoolean(foreground["isZero"])||Convert.ToBoolean(foreground["isGeneratedSource"]),"Passive pin changed foreground to a non-source window.");
                if(!ready)return false;
                if(annotated)return true;
                // Windows can briefly report NULL while the hidden editor loses
                // activation. Only that gap may settle within this same budget;
                // any actual focus theft fails immediately, without refocusing.
                Assert(Convert.ToBoolean(foreground["isZero"])||Convert.ToBoolean(foreground["isGeneratedSource"]),"Pin handoff changed foreground to a non-source window.");
                return Convert.ToBoolean(foreground["isGeneratedSource"]);
            },20,"Pin handoff did not show decoded reference and dismiss capture.",app);
            Dictionary<string,object> completedForeground=ScreenshotPinForeground(app,form.Handle,editor,pin,main);result["foregroundAtVisibleHandoff"]=completedForeground;
            Assert(!Convert.ToBoolean(completedForeground["isPin"])&&!Convert.ToBoolean(completedForeground["isMain"]),"Completed handoff activated the pin or main window.");
            if(!annotated)RequireForeground(form);Assert(ScreenshotPinTopmost(pin),"New reference window is not native topmost.");
            Rectangle work=Screen.FromPoint(first).WorkingArea,initial=ScreenshotPinBounds(pin);Assert(work.Contains(initial),"Pinned outer frame is not clamped to capture monitor work area.");
            ScreenshotPinPixels(app,pin,selected,annotated);result["rasterVisible"]=true;result["editedRasterVisible"]=annotated;result["passiveShowPreservedSourceForeground"]=!annotated;result["pinAndMainNotObservedForeground"]=true;result["decodedReferenceVisibleAndCaptureDismissed"]=true;ScreenshotVerifyPinClientFrame(form,app,pin,result);result["nativeTopmostInitially"]=true;result["initialOuterFrameWithinSourceWorkArea"]=true;
            ScreenshotPinToggle(app,pin,true,result);result["nativeUnpinVerified"]=true;ScreenshotPinToggle(app,pin,false,result);result["nativeRepinVerified"]=true;
            // Native Move/Size exercises actual HWND geometry without a global
            // mouse marathon or accidental drag into a foreign application.
            int width=Math.Min(work.Width-32,initial.Width+80),height=Math.Min(work.Height-32,initial.Height+60);
            int x=Math.Min(work.Right-width-8,Math.Max(work.Left+8,initial.X+24)),y=Math.Min(work.Bottom-height-8,Math.Max(work.Top+8,initial.Y+24));
            Assert(width>200&&height>120&&(x!=initial.X||y!=initial.Y)&&(width!=initial.Width||height!=initial.Height),"Generated monitor cannot support the bounded pin move/resize case.");
            Assert(SetWindowPos(pin,IntPtr.Zero,x,y,width,height,0x0004|0x0010),"Native pin move/resize failed.");
            WaitFor(delegate{Rectangle bounds=ScreenshotPinBounds(pin);return Math.Abs(bounds.X-x)<=2&&Math.Abs(bounds.Y-y)<=2&&Math.Abs(bounds.Width-width)<=2&&Math.Abs(bounds.Height-height)<=2;},10,"Actual pin HWND did not adopt requested move/resize.",app);
            Assert(work.Contains(ScreenshotPinBounds(pin))&&ScreenshotPinTopmost(pin),"Native resized pin escaped work area or lost topmost.");ScreenshotPinPixels(app,pin,selected,annotated);result["nativeMoveResizeVerified"]=true;result["rasterRetainedAfterResize"]=true;
            ScreenshotInvoke(app,pin,"\u5173\u95ed\u8d34\u56fe");WaitFor(delegate{return !IsWindow(pin)&&ScreenshotPins(app.Id).Count==0;},10,"Closing reference hid it instead of destroying its native HWND.",app);result["nativeWindowDestroyed"]=true;
            Assert(ScreenshotOwnedClipboard.SeedUnchanged(),"Pin lifecycle changed the clipboard.");Assert(Directory.GetFiles(output).Length==files,"Pin lifecycle wrote a file.");result["clipboardUnchanged"]=true;result["exportDirectoryUnchanged"]=true;result["case"]=annotated?"inplace-pin-annotated-active-editor":"inplace-pin-passive-physical";result["ok"]=true;finished=true;return result;
        } finally {
            // Existing outer fixture owns/stops the exact app tree on failure;
            // never close another process's window or read its screen pixels.
            if(!finished){result["failedPinWindowStillPresent"]=pin!=IntPtr.Zero&&IsWindow(pin);result["foregroundAtPinFailure"]=ScreenshotPinForeground(app,form.Handle,editor,pin,main);}
        }
    }
    static void ScreenshotEditorWorkflow(Form form,Panel image,Process app,MockServer server,string history,string output,ProcessStartInfo start,string executable,string roaming,string token,List<string> passed,Dictionary<string,object> report,Func<int> sourceEvents) {
        IntPtr source=IntPtr.Zero;OnUi(form,delegate{source=form.Handle;});ScreenshotOwnedClipboard=new ScreenshotClipboardLease(source);bool completed=false;
        report["screenshotClipboardPolicySelfTests"]=ScreenshotClipboardPolicyTests();report["screenshotClipboardObservations"]=ScreenshotOwnedClipboard.Observations;
        ScreenshotNativeOpenObservations=new List<Dictionary<string,object>>();report["screenshotNativeOpenObservations"]=ScreenshotNativeOpenObservations;
        ScreenshotNativeCancelObservations=new List<Dictionary<string,object>>();report["screenshotNativeCancelObservations"]=ScreenshotNativeCancelObservations;
        try{ScreenshotOwnedClipboard.RequireEmpty();ScreenshotEditorWorkflowBody(form,image,app,server,history,output,start,executable,roaming,token,passed,report,sourceEvents);completed=true;}
        finally{string outcome;try{outcome=ScreenshotOwnedClipboard.Cleanup();}catch(Exception error){outcome="cleanup-error-"+error.GetType().Name;}ScreenshotOwnedClipboard=null;ScreenshotCaptureHealth=null;ScreenshotSelectionEditors.Clear();if(ScreenshotExpectedWindow!=null){ScreenshotExpectedWindow.Dispose();ScreenshotExpectedWindow=null;}
            report["screenshotClipboardCleanup"]=outcome;report["screenshotOwnedClipboardCleared"]=outcome=="verified-owned-generation-cleared"||outcome=="already-empty";
            if(completed)Assert(Convert.ToBoolean(report["screenshotOwnedClipboardCleared"]),"Owned screenshot clipboard cleanup did not restore the initial empty state: "+outcome);}
    }
    static void ScreenshotEditorWorkflowBody(Form form,Panel image,Process app,MockServer server,string history,string output,ProcessStartInfo start,string executable,string roaming,string token,List<string> passed,Dictionary<string,object> report,Func<int> sourceEvents) {
        Assert(RustCapture&&server!=null,"Screenshot workflow requires exact native helper and loopback network trap.");
        // This mode never selects text. Disable our generated textbox so its
        // blinking caret cannot make the independent full-window baseline drift.
        OnUi(form,delegate{foreach(Control control in form.Controls)if(control is TextBox)control.Enabled=false;form.Refresh();});
        report["uiAutomationSelectorsUsed"]=true;report["translationBackend"]="not-invoked-local-image-only";report["screenshotOutputIsOwnedTemporaryDirectory"]=true;report["desktopDirectoryWritten"]=false;
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();report["screenshotCases"]=cases;
        ScreenshotCaptureHealth=delegate{return CaptureSnapshot(app,start,executable,roaming,token);};
        ScreenshotFirstStrokeReleaseChecks=0;Dictionary<string,object> before=ScreenshotCaptureHealth();ScreenshotInitialAttempt=before.ContainsKey("attemptId")?CaptureNumber(before,"attemptId"):0;
        Assert(CaptureNumber(before,"ocrInvocationCount")==0,"OCR was invoked before the isolated F1 workflow.");
        Point first=Point.Empty,last=Point.Empty;OnUi(form,delegate{first=image.PointToScreen(new Point(20,20));last=image.PointToScreen(new Point(660,130));});
        Size selected=new Size(last.X-first.X,last.Y-first.Y);Assert(selected==new Size(640,110),"Generated screenshot region dimensions changed.");
        ScreenshotOwnedClipboard.Seed();
        Dictionary<string,object> cancelled=ScreenshotPicker(form,image,app,first,0);uint cancelledPid=Convert.ToUInt32(cancelled["helperProcessId"]);
        RequireForeground(form);Send(new INPUT[]{Key(0x1B,false),Key(0x1B,true)});
        WaitFor(delegate{return AppOverlays(app.Id)==0&&ProcessExited(cancelledPid);},10,"Cancelled F1 left native windows/process behind.",app);
        IntPtr editor=ScreenshotWindow(app.Id);Assert(editor==IntPtr.Zero||!IsWindowVisible(editor),"Cancelled F1 unexpectedly opened the editor.");
        Assert(ScreenshotOwnedClipboard.SeedUnchanged(),"Cancelled F1 mutated the clipboard.");
        Assert(Directory.GetFiles(output).Length==0,"Cancelled F1 saved a file.");cancelled["ok"]=true;cancelled["case"]="escape-cancel";cases.Add(cancelled);

        Dictionary<string,object> passive=ScreenshotPinCase(form,image,app,first,last,selected,cancelledPid,output,report,false);
        report["screenshotPinCases"]=new object[]{passive};
        Dictionary<string,object> pinned=ScreenshotPinCase(form,image,app,first,last,selected,Convert.ToUInt32(passive["helperProcessId"]),output,report,true);
        report["screenshotPinRequiredCases"]=2;report["screenshotPinPassedCases"]=2;report["screenshotPinCases"]=new object[]{passive,pinned};
        report["screenshotPinOnly"]=ScreenshotPinOnly;
        if(ScreenshotPinOnly) {
            Dictionary<string,object> pinAfter=CompletedCaptureSnapshot(app,start,executable,roaming,token,0,report,true);ScreenshotRequireDeferredReleased(pinAfter);
            Assert(CaptureNumber(pinAfter,"ocrInvocationCount")==0&&server.Connections==0&&server.Count==0&&server.Error==null,"Pin-only path invoked OCR/provider traffic.");
            Assert(!File.Exists(history)||new JavaScriptSerializer().Deserialize<object[]>(File.ReadAllText(history)).Length==0,"Pin-only path wrote translation history.");
            Assert(sourceEvents()==0,"Pin-only capture leaked input into source controls.");
            report["screenshotOcrInvocationCount"]=CaptureNumber(pinAfter,"ocrInvocationCount");report["screenshotHttpConnections"]=server.Connections;report["screenshotTranslationHistoryCount"]=0;
            report["screenshotNetworkEvidenceScope"]="configured-loopback-provider-trap; no global packet capture";report["screenshotNativeCompletion"]=pinAfter;
            ScreenshotRecordCaptureCounts(report,pinAfter,3,2);report["screenshotFinalExportCount"]=Directory.GetFiles(output).Length;
            passed.Add("Actual generated F1 passive physical-click pin and annotated active-editor pin -> decoded native HWNDs -> topmost toggle/move/resize -> destroyed; no clipboard/file/provider/history effects");return;
        }
        Dictionary<string,object> dragged=ScreenshotPicker(form,image,app,first,Convert.ToUInt32(pinned["helperProcessId"]));uint dragPid=Convert.ToUInt32(dragged["helperProcessId"]);
        MoveGenerated(form,first);INPUT down=new INPUT();down.data.mouse.flags=2;Send(new INPUT[]{down});Thread.Sleep(80);MoveGenerated(form,last);Thread.Sleep(80);INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{up});
        ScreenshotWaitAdjustment(form,app,dragPid,Rectangle.FromLTRB(first.X,first.Y,last.X,last.Y),dragged);ScreenshotWebAction(form,app,dragPid,"solid",dragged);
        WaitFor(delegate{editor=ScreenshotWindow(app.Id);return editor!=IntPtr.Zero&&IsWindowVisible(editor)&&Element(editor,ScreenshotCanvasName)!=null&&AppOverlays(app.Id)==0;},25,"Web solid action did not retain the actual image editor.",app);
        Assert(Directory.GetFiles(output).Length==0,"Opening an image auto-saved before explicit Save.");
        ScreenshotDrag(app,editor,"\u5b9e\u5fc3\u906e\u6321",selected,new Point(10,10),new Point(80,70),true);
        WaitFor(delegate{AutomationElement undo=ScreenshotButton(editor,"\u64a4\u9500");return undo!=null&&undo.Current.IsEnabled;},10,"Actual solid redaction did not commit an undoable edit.",app);
        ScreenshotDrag(app,editor,"\u88c1\u526a",selected,new Point(8,8),new Point(selected.Width-8,selected.Height-8));
        Size cropped=new Size(selected.Width-16,selected.Height-16);
        WaitFor(delegate{return ScreenshotInplaceDimensionsMatch(editor,cropped);},10,"Actual pixel crop dimensions did not render before export.",app);
        using(Bitmap copied=ScreenshotClipboard(app,editor,cropped,ScreenshotCroppedPixels,"cropped-edits")) {
            Assert(copied.GetPixel(12,12).ToArgb()==Color.FromArgb(228,93,104).ToArgb(),"Real editor solid mask did not replace generated source pixels.");
            Assert(copied.GetPixel(100,70).ToArgb()==Color.FromArgb(23,101,199).ToArgb(),"Generated blue source pixels were not retained outside redaction.");
            Assert(copied.GetPixel(cropped.Width-20,cropped.Height-20).ToArgb()==Color.FromArgb(210,60,90).ToArgb(),"Generated second source color was not retained after crop.");
            string firstPath=null;byte[] firstBytes=null;
            List<Dictionary<string,object>> saveSessions=new List<Dictionary<string,object>>();
            for(int save=0;save<2;save++) {
                Dictionary<string,object> fresh=ScreenshotPicker(form,image,app,first,dragPid);dragPid=Convert.ToUInt32(fresh["helperProcessId"]);saveSessions.Add(fresh);
                MoveGenerated(form,first);Send(new INPUT[]{down});Thread.Sleep(80);MoveGenerated(form,last);Thread.Sleep(80);Send(new INPUT[]{up});
                ScreenshotWaitAdjustment(form,app,dragPid,Rectangle.FromLTRB(first.X,first.Y,last.X,last.Y),fresh);ScreenshotWebAction(form,app,dragPid,"solid",fresh);
                WaitFor(delegate{return IsWindowVisible(editor)&&Element(editor,ScreenshotCanvasName)!=null&&AppOverlays(app.Id)==0;},25,"Fresh Web solid action did not retain in-place editor.",app);
                ScreenshotDrag(app,editor,"\u5b9e\u5fc3\u906e\u6321",selected,new Point(10,10),new Point(80,70),true);
                ScreenshotDrag(app,editor,"\u88c1\u526a",selected,new Point(8,8),new Point(selected.Width-8,selected.Height-8));
                WaitFor(delegate{AutomationElement button=ScreenshotButton(editor,"\u4e0b\u8f7d\u622a\u56fe");return button!=null&&button.Current.IsEnabled&&ScreenshotInplaceDimensionsMatch(editor,cropped);},10,"Fresh cropped save pixels were not ready.",app);
                ScreenshotInvoke(app,editor,"\u4e0b\u8f7d\u622a\u56fe");int expected=save+1;
                WaitFor(delegate{return Directory.GetFiles(output,"*.png").Length==expected&&!IsWindowVisible(editor);},15,"In-place save did not create one PNG then dismiss capture.",app);
                if(save==0){firstPath=Directory.GetFiles(output,"*.png")[0];Assert(Path.GetFileName(firstPath).StartsWith("Screenshot_",StringComparison.Ordinal),"Default filename was not generated by screenshot backend.");ScreenshotPng(firstPath,copied);firstBytes=File.ReadAllBytes(firstPath);}
            }
            dragged["hotkeyPresses"]=3;dragged["recapturedSaveSessions"]=saveSessions;dragged["inplaceCopyAndSavesDismissed"]=true;
            string[] files=Directory.GetFiles(output,"*.png");foreach(string file in files)ScreenshotPng(file,copied);
            Assert(Convert.ToBase64String(firstBytes)==Convert.ToBase64String(File.ReadAllBytes(firstPath)),"First export changed after saving again.");
            dragged["savedPngCount"]=files.Length;dragged["exportNames"]=Array.ConvertAll(files,delegate(string path){return Path.GetFileName(path);});dragged["copiedPixelSize"]=new int[]{copied.Width,copied.Height};dragged["allExportPixelsMatchSystemClipboard"]=true;dragged["noOverwrite"]=true;dragged["noHiddenPngMetadataOrTrailingData"]=true;
        }
        string reopenedPath=Directory.GetFiles(output,"*.png")[0];
        using(Bitmap reopened=new Bitmap(reopenedPath))ScreenshotOpenGenerated(app,editor,reopenedPath,"saved-capture",reopened,output,start,false);
        dragged["savedCaptureReopenedThroughSettings"]=true;
        byte[] reopenedBytes=File.ReadAllBytes(reopenedPath);HashSet<string> beforeCollision=new HashSet<string>(Directory.GetFiles(output,"*.png"),StringComparer.OrdinalIgnoreCase);
        string firstCollisionPath=null,firstCollisionBase=null;int firstCollisionSuffix=0;byte[] firstCollisionBytes=null;
        using(Bitmap reopened=new Bitmap(reopenedPath)) {
            for(int collision=0;collision<2;collision++) {
                HashSet<string> prior=new HashSet<string>(Directory.GetFiles(output,"*.png"),StringComparer.OrdinalIgnoreCase);
                ScreenshotInvoke(app,editor,"\u4fdd\u5b58\u56fe\u7247");int count=beforeCollision.Count+collision+1;
                WaitFor(delegate{return Directory.GetFiles(output,"*.png").Length==count&&ScreenshotButton(editor,"\u4fdd\u5b58\u56fe\u7247").Current.IsEnabled;},15,"Repeated standalone Save did not collision-number its output.",app);
                string saved=Array.Find(Directory.GetFiles(output,"*.png"),delegate(string value){return !prior.Contains(value);});Assert(saved!=null,"Repeated Save output missing.");ScreenshotPng(saved,reopened);
                System.Text.RegularExpressions.Match numbered=System.Text.RegularExpressions.Regex.Match(Path.GetFileNameWithoutExtension(saved),"^(Screenshot_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2})(?:_([0-9]+))?$");
                Assert(numbered.Success,"Repeated Save filename did not have its generated timestamp/optional collision suffix.");int suffix=numbered.Groups[2].Success?Int32.Parse(numbered.Groups[2].Value):0;
                if(collision==0){firstCollisionPath=saved;firstCollisionBase=numbered.Groups[1].Value;firstCollisionSuffix=suffix;firstCollisionBytes=File.ReadAllBytes(saved);}
                else Assert(numbered.Groups[1].Value==firstCollisionBase&&suffix>firstCollisionSuffix&&Convert.ToBase64String(firstCollisionBytes)==Convert.ToBase64String(File.ReadAllBytes(firstCollisionPath)),"Second same-session Save did not number its collision without overwriting first output.");
            }
        }
        Assert(Convert.ToBase64String(reopenedBytes)==Convert.ToBase64String(File.ReadAllBytes(reopenedPath)),"Repeated standalone Save overwrote its original local image.");
        dragged["standaloneCollisionSaveCount"]=2;dragged["standaloneCollisionNumberingVerified"]=true;
        IntPtr management=MainWindow(app.Id);ScreenshotInvoke(app,management,"\u9690\u85cf\u7ba1\u7406\u7a97\u53e3");WaitFor(delegate{return !IsWindowVisible(management);},10,"Settings window did not hide after generated local image Open.",app);
        ScreenshotCancelFileDialog(app,editor,"\u53e6\u5b58\u4e3a");ScreenshotCancelFileDialog(app,editor,"\u6253\u5f00\u56fe\u7247");
        Assert(Directory.GetFiles(output,"*.png").Length==4,"Cancelled native file dialog wrote an unexpected export.");
        using(Bitmap retained=ScreenshotClipboard(app,editor,cropped,ScreenshotCroppedPixels,"after-native-cancel"))Assert(retained.GetPixel(12,12).ToArgb()==Color.FromArgb(228,93,104).ToArgb(),"Cancelled Open discarded edited image pixels.");
        dragged["nativeSaveAsCancelPreservedImage"]=true;dragged["nativeOpenCancelPreservedImage"]=true;
        string inputs=Path.Combine(Path.GetDirectoryName(output),"GeneratedImageInputs");Assert(!Directory.Exists(inputs),"Generated image input directory already exists.");Directory.CreateDirectory(inputs);
        List<Dictionary<string,object>> opened=new List<Dictionary<string,object>>();
        foreach(string format in new string[]{"png","jpeg"}) {
            string path=Path.Combine(inputs,"generated-source."+(format=="png"?"png":"jpg"));
            using(Bitmap generated=new Bitmap(24,16)) {
                using(Graphics graphics=Graphics.FromImage(generated))graphics.Clear(format=="png"?Color.FromArgb(17,177,93):Color.FromArgb(128,128,128));
                using(FileStream file=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None))generated.Save(file,format=="png"?System.Drawing.Imaging.ImageFormat.Png:System.Drawing.Imaging.ImageFormat.Jpeg);
                opened.Add(ScreenshotOpenGenerated(app,editor,path,format,generated,output));
            }
        }
        report["screenshotLocalOpenRequiredCases"]=2;report["screenshotLocalOpenPassedCases"]=opened.Count;report["screenshotLocalOpenCases"]=opened;
        OnUi(form,delegate{form.Activate();SetForegroundWindow(form.Handle);});RequireForeground(form);Thread.Sleep(250);Assert(IsWindowVisible(editor),"Independent editor auto-hid after focus moved to the owned source window.");
        report["screenshotEditorSurvivedOwnedFocusLoss"]=true;SetForegroundWindow(editor);
        ScreenshotInvoke(app,editor,"\u5173\u95ed\u622a\u56fe\u7f16\u8f91\u5668");WaitFor(delegate{return !IsWindowVisible(editor);},10,"Saved editor did not close.",app);
        dragged["case"]="inplace-drag-copy-recapture-save-twice";dragged["ok"]=true;cases.Add(dragged);
        Dictionary<string,object> clicked=ScreenshotPicker(form,image,app,first,dragPid,true);RequireForeground(form);Send(new INPUT[]{down,up});
        int[] frame=(int[])clicked["expectedWindowBounds"];Rectangle sourceFrame=new Rectangle(frame[0],frame[1],frame[2],frame[3]);
        ScreenshotWaitAdjustment(form,app,Convert.ToUInt32(clicked["helperProcessId"]),sourceFrame,clicked);ScreenshotWebAction(form,app,Convert.ToUInt32(clicked["helperProcessId"]),"select",clicked);
        WaitFor(delegate{return IsWindowVisible(editor)&&Element(editor,ScreenshotCanvasName)!=null&&AppOverlays(app.Id)==0;},25,"Click-visible-window native select did not open editor.",app);
        int[] windowSize=(int[])clicked["expectedWindowDimensions"];
        Dictionary<string,object> windowPixels=new Dictionary<string,object>{{"baselineFrame",RectValue(sourceFrame)},{"baselineClientRelativeToFrame",RectValue(ScreenshotExpectedWindowClient)},{"baselineTakenBeforeF1",true},{"baselineSourceForegroundVerified",true}};report["screenshotWindowPixelComparison"]=windowPixels;
        using(Bitmap copy=ScreenshotClipboard(app,editor,new Size(windowSize[0],windowSize[1]),delegate(Bitmap actual){return ScreenshotWindowPixelsMatch(actual,windowPixels);},"clicked-window",delegate(string phase){ScreenshotObserveWindowCopy(form,app,editor,sourceFrame,phase,windowPixels);},delegate{ScreenshotPassiveWindowCopy(form,app,Convert.ToUInt32(clicked["helperProcessId"]),editor,clicked);})) { clicked["visibleWindowPixelSize"]=new int[]{copy.Width,copy.Height};RequireForeground(form);clicked["copySourceForegroundAfterCommit"]=true; }
        Dictionary<string,object> cancelClick=ScreenshotPicker(form,image,app,first,Convert.ToUInt32(clicked["helperProcessId"]));RequireForeground(form);Send(new INPUT[]{down,up});
        ScreenshotWaitAdjustment(form,app,Convert.ToUInt32(cancelClick["helperProcessId"]),sourceFrame,cancelClick);ScreenshotWebAction(form,app,Convert.ToUInt32(cancelClick["helperProcessId"]),"select",cancelClick);
        WaitFor(delegate{return IsWindowVisible(editor)&&Element(editor,ScreenshotCanvasName)!=null&&AppOverlays(app.Id)==0;},25,"Second native select did not prepare cancel-only window capture.",app);
        ScreenshotOwnedClipboard.Seed();ScreenshotInvoke(app,editor,"\u53d6\u6d88\u622a\u56fe");
        WaitFor(delegate{return !IsWindowVisible(editor);},10,"In-place X did not cancel capture.",app);Assert(ScreenshotOwnedClipboard.SeedUnchanged(),"In-place X changed clipboard.");
        clicked["hotkeyPresses"]=2;clicked["cancelSession"]=cancelClick;clicked["inplaceCopyDismissed"]=true;clicked["inplaceCancelPreservedClipboard"]=true;
        Assert(Directory.GetFiles(output,"*.png").Length==6,"Closing an unsaved screenshot auto-saved or lost an earlier explicit export.");report["screenshotFinalExportCount"]=6;clicked["case"]="click-window-copy-then-cancel";clicked["ok"]=true;cases.Add(clicked);
        Dictionary<string,object> after=CompletedCaptureSnapshot(app,start,executable,roaming,token,0,report);RequireCaptureReleased(after);
        Assert(CaptureNumber(after,"ocrInvocationCount")==0,"F1 image editing invoked OCR.");
        Assert(server.Connections==0&&server.Count==0&&server.Error==null,"F1 image editing performed an HTTP/provider request.");
        Assert(!File.Exists(history)||new JavaScriptSerializer().Deserialize<object[]>(File.ReadAllText(history)).Length==0,"F1 image editing wrote translation history.");
        Assert(sourceEvents()==0,"Native F1 click/drag leaked mouse input to generated source controls.");
        report["screenshotOcrInvocationCount"]=CaptureNumber(after,"ocrInvocationCount");report["screenshotHttpConnections"]=server.Connections;report["screenshotNetworkEvidenceScope"]="configured-loopback-provider-trap; no global packet capture";report["screenshotTranslationHistoryCount"]=0;
        report["screenshotRequiredCases"]=3;report["screenshotPassedCases"]=cases.Count;ScreenshotRecordCaptureCounts(report,after,8,6);report["screenshotNativeCompletion"]=after;
        Assert(cases.Count==3&&VerifiedNativeChildren.Count==8,"Screenshot fixture missed a required real native generation.");
        passed.Add("Actual F1 cancel, annotated pin, in-place copy/save dismissal with two fresh save captures, then actual settings local Open and native dialog cancellation; window-click copy plus new capture cancellation; zero OCR/configured-provider HTTP/history (loopback trap, not global packet capture)");
    }
}
