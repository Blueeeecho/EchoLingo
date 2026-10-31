// Compiled with windows-application-smoke.ps1's guarded ephemeral-runner fixture.
// Uses the real packaged app/WebView/native picker; never mocks screenshot IPC.
public static partial class EchoLingoApplicationSmoke {
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
    static AutomationElement ScreenshotButton(IntPtr window,string name) {
        AutomationElementCollection matches=AutomationElement.FromHandle(window).FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.NameProperty,name),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)));
        Assert(matches.Count<=1,"Screenshot button accessible name is ambiguous: "+name);return matches.Count==1?matches[0]:null;
    }
    static void ScreenshotInvoke(Process app,IntPtr window,string name) {
        AutomationElement element=null;
        WaitFor(delegate{element=ScreenshotButton(window,name);return element!=null&&element.Current.IsEnabled&&!element.Current.IsOffscreen;},10,"Actual screenshot button unavailable: "+name,app);
        object pattern;Assert(element.TryGetCurrentPattern(InvokePattern.Pattern,out pattern),"Screenshot button has no InvokePattern.");((InvokePattern)pattern).Invoke();
    }
    static void ScreenshotMove(Process app,IntPtr editor,Point point) {
        Assert(GetForegroundWindow()==editor&&ForegroundPid()==app.Id,"Screenshot edit pointer would target another process; refused.");
        Rectangle desktop=SystemInformation.VirtualScreen;INPUT input=new INPUT();input.data.mouse.dx=(int)Math.Round((point.X-desktop.Left)*65535.0/(desktop.Width-1));input.data.mouse.dy=(int)Math.Round((point.Y-desktop.Top)*65535.0/(desktop.Height-1));input.data.mouse.flags=0x8000|0x4000|1;Send(new INPUT[]{input});
    }
    static void ScreenshotDrag(Process app,IntPtr editor,string tool,Size pixels,Point first,Point last) {
        ScreenshotInvoke(app,editor,tool);SetForegroundWindow(editor);
        AutomationElement canvas=null;WaitFor(delegate{return (canvas=Element(editor,ScreenshotCanvasName))!=null&&!canvas.Current.IsOffscreen;},10,"Actual image canvas missing from UIAutomation.",app);
        System.Windows.Rect bounds=canvas.Current.BoundingRectangle;Assert(bounds.Width>0&&bounds.Height>0,"Actual image canvas has no screen bounds.");
        Point a=new Point((int)Math.Round(bounds.X+first.X*bounds.Width/pixels.Width),(int)Math.Round(bounds.Y+first.Y*bounds.Height/pixels.Height));
        Point b=new Point((int)Math.Round(bounds.X+last.X*bounds.Width/pixels.Width),(int)Math.Round(bounds.Y+last.Y*bounds.Height/pixels.Height));
        ScreenshotMove(app,editor,a);INPUT down=new INPUT();down.data.mouse.flags=2;Send(new INPUT[]{down});
        try{Thread.Sleep(60);ScreenshotMove(app,editor,b);Thread.Sleep(60);}
        finally{if(ForegroundPid()==app.Id){INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{up});}}
    }
    static void ScreenshotCancelFileDialog(Process app,IntPtr editor,string buttonName) {
        ScreenshotInvoke(app,editor,buttonName);IntPtr modal=IntPtr.Zero;
        WaitFor(delegate{modal=GetForegroundWindow();StringBuilder name=new StringBuilder(128);GetClassName(modal,name,name.Capacity);return modal!=editor&&ForegroundPid()==app.Id&&name.ToString()=="#32770";},10,"Native screenshot file dialog did not own the expected process foreground.",app);
        Assert(ForegroundPid()==app.Id&&GetForegroundWindow()==modal,"Native dialog lost ownership before cancellation; no key sent.");
        Send(new INPUT[]{Key(0x1B,false),Key(0x1B,true)});
        WaitFor(delegate{AutomationElement save=ScreenshotButton(editor,"\u4fdd\u5b58");return !IsWindowVisible(modal)&&IsWindowVisible(editor)&&save!=null&&save.Current.IsEnabled;},10,"Cancelled native screenshot file dialog did not restore the editor.",app);
    }
    static Dictionary<string,object> ScreenshotOpenGenerated(Process app,IntPtr editor,string path,string format,Bitmap expected,string output) {
        Assert(File.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"Generated image input is missing or redirected.");
        byte[] original=File.ReadAllBytes(path);Assert(original.Length>0&&original.Length<65536,"Generated image input exceeds its fixture bound.");
        ScreenshotInvoke(app,editor,"\u6253\u5f00\u56fe\u7247");IntPtr modal=IntPtr.Zero;
        WaitFor(delegate{modal=GetForegroundWindow();StringBuilder name=new StringBuilder(128);GetClassName(modal,name,name.Capacity);return modal!=editor&&ForegroundPid()==app.Id&&name.ToString()=="#32770";},10,"Generated file Open did not show an owned native dialog.",app);
        AutomationElement edit=null;
        WaitFor(delegate{AutomationElementCollection edits=AutomationElement.FromHandle(modal).FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new PropertyCondition(AutomationElement.AutomationIdProperty,"1001")));
            Assert(edits.Count<=1,"Native Open file-name Edit is ambiguous; no blind input was sent.");if(edits.Count==0)return false;edit=edits[0];return edit.Current.IsEnabled&&!edit.Current.IsOffscreen;},10,"Native Open needs one verified file-name Edit (AutomationId 1001); no blind input was sent.",app);
        Assert(edit.Current.ProcessId==app.Id,"Native file-name Edit belongs to another process.");object raw;Assert(edit.TryGetCurrentPattern(ValuePattern.Pattern,out raw)&&!((ValuePattern)raw).Current.IsReadOnly,"Native file-name Edit is not writable.");
        ((ValuePattern)raw).SetValue(path);edit.SetFocus();
        Assert(GetForegroundWindow()==modal&&ForegroundPid()==app.Id,"Native Open lost focus before submitting the generated path; no key sent.");Send(new INPUT[]{Key(0x0D,false),Key(0x0D,true)});
        WaitFor(delegate{AutomationElement copy=ScreenshotButton(editor,"\u590d\u5236");return !IsWindowVisible(modal)&&IsWindowVisible(editor)&&copy!=null&&copy.Current.IsEnabled&&Element(editor,expected.Width+" \u00d7 "+expected.Height+" px")!=null;},15,"Successful native Open did not install the generated local image session.",app);
        using(Bitmap copied=ScreenshotClipboard(app,editor,expected.Size)) {
            for(int y=0;y<expected.Height;y++)for(int x=0;x<expected.Width;x++)Assert(copied.GetPixel(x,y).ToArgb()==expected.GetPixel(x,y).ToArgb(),"Native local image Open changed generated decoded pixels.");
            HashSet<string> existing=new HashSet<string>(Directory.GetFiles(output,"*.png"),StringComparer.OrdinalIgnoreCase);
            ScreenshotInvoke(app,editor,"\u4fdd\u5b58");WaitFor(delegate{return Directory.GetFiles(output,"*.png").Length==existing.Count+1&&ScreenshotButton(editor,"\u4fdd\u5b58").Current.IsEnabled;},15,"Opened local image did not save as a new PNG.",app);
            string saved=Array.Find(Directory.GetFiles(output,"*.png"),delegate(string value){return !existing.Contains(value);});Assert(saved!=null,"New opened-image PNG missing.");ScreenshotPng(saved,copied);
        }
        Assert(Convert.ToBase64String(original)==Convert.ToBase64String(File.ReadAllBytes(path)),"Opening/editing/saving overwrote the original local input.");
        return new Dictionary<string,object>{{"format",format},{"nativeDialogSubmitted",true},{"copiedPixelSize",new int[]{expected.Width,expected.Height}},{"savedFlattenedPngPixelsMatched",true},{"sourceBytesUnchanged",true},{"ok",true}};
    }
    static Bitmap ScreenshotClipboard(Process app,IntPtr editor,Size expected) {
        Clipboard.SetText("ECHOLINGO_GENERATED_IMAGE_COPY_SENTINEL");ScreenshotInvoke(app,editor,"\u590d\u5236");
        Bitmap result=null;WaitFor(delegate{
            try { if(!Clipboard.ContainsImage())return false;using(Image image=Clipboard.GetImage()){if(image==null)return false;result=new Bitmap(image);}return true; }
            catch(System.Runtime.InteropServices.ExternalException){return false;}
        },10,"Actual editor Copy did not publish an image to the system clipboard.",app);
        Assert(result.Size==expected,"Clipboard pixels have wrong dimensions after real crop.");return result;
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
    static Dictionary<string,object> ScreenshotPicker(Form form,Panel image,Process app,Point pointer,uint oldHelper) {
        OnUi(form,delegate{form.Activate();SetForegroundWindow(form.Handle);image.Refresh();});RequireForeground(form);MoveGenerated(form,pointer);
        RECT raw;Assert(DwmGetWindowAttribute(form.Handle,9,out raw,Marshal.SizeOf(typeof(RECT)))==0,"Cannot independently measure screenshot source frame.");
        Rectangle frame=Rectangle.FromLTRB(raw.left,raw.top,raw.right,raw.bottom),display=Screen.FromPoint(pointer).Bounds;
        Dictionary<string,object> ready=new Dictionary<string,object>();Stopwatch clock=Stopwatch.StartNew();
        Send(new INPUT[]{Key(0x70,false),Key(0x70,true)}); // Exactly one real unmodified F1.
        WaitFor(delegate{return AppOcrReady(form,app.Id,form.Handle,frame,pointer,display,ready,oldHelper,clock);},25,"Actual F1 did not produce verified native hover edges over the generated window.",app);
        ready["shortcut"]="F1";ready["hotkeyPresses"]=1;ready["expectedWindowDimensions"]=new int[]{frame.Width,frame.Height};return ready;
    }
    static void ScreenshotEditorWorkflow(Form form,Panel image,Process app,MockServer server,string history,string output,ProcessStartInfo start,string executable,string roaming,string token,List<string> passed,Dictionary<string,object> report,Func<int> sourceEvents) {
        Assert(RustCapture&&server!=null,"Screenshot workflow requires exact native helper and loopback network trap.");
        report["uiAutomationSelectorsUsed"]=true;report["translationBackend"]="not-invoked-local-image-only";report["screenshotOutputIsOwnedTemporaryDirectory"]=true;report["desktopDirectoryWritten"]=false;
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();report["screenshotCases"]=cases;
        Dictionary<string,object> before=CaptureSnapshot(app,start,executable,roaming,token);
        Assert(CaptureNumber(before,"ocrInvocationCount")==0,"OCR was invoked before the isolated F1 workflow.");
        Point first=Point.Empty,last=Point.Empty;OnUi(form,delegate{first=image.PointToScreen(new Point(20,20));last=image.PointToScreen(new Point(660,130));});
        Size selected=new Size(last.X-first.X,last.Y-first.Y);Assert(selected==new Size(640,110),"Generated screenshot region dimensions changed.");
        Clipboard.SetText("ECHOLINGO_GENERATED_F1_CANCEL_SENTINEL");
        Dictionary<string,object> cancelled=ScreenshotPicker(form,image,app,first,0);uint cancelledPid=Convert.ToUInt32(cancelled["helperProcessId"]);
        RequireForeground(form);Send(new INPUT[]{Key(0x1B,false),Key(0x1B,true)});
        WaitFor(delegate{return AppOverlays(app.Id)==0&&ProcessExited(cancelledPid);},10,"Cancelled F1 left native windows/process behind.",app);
        IntPtr editor=ScreenshotWindow(app.Id);Assert(editor==IntPtr.Zero||!IsWindowVisible(editor),"Cancelled F1 unexpectedly opened the editor.");
        Assert(Clipboard.ContainsText()&&Clipboard.GetText()=="ECHOLINGO_GENERATED_F1_CANCEL_SENTINEL","Cancelled F1 mutated the clipboard.");
        Assert(Directory.GetFiles(output).Length==0,"Cancelled F1 saved a file.");cancelled["ok"]=true;cancelled["case"]="escape-cancel";cases.Add(cancelled);

        Dictionary<string,object> dragged=ScreenshotPicker(form,image,app,first,cancelledPid);uint dragPid=Convert.ToUInt32(dragged["helperProcessId"]);
        MoveGenerated(form,first);INPUT down=new INPUT();down.data.mouse.flags=2;Send(new INPUT[]{down});Thread.Sleep(80);MoveGenerated(form,last);Thread.Sleep(80);INPUT up=new INPUT();up.data.mouse.flags=4;Send(new INPUT[]{up});
        WaitFor(delegate{editor=ScreenshotWindow(app.Id);return editor!=IntPtr.Zero&&IsWindowVisible(editor)&&Element(editor,ScreenshotCanvasName)!=null&&AppOverlays(app.Id)==0;},25,"Real F1 drag did not show the actual image editor.",app);
        Assert(Directory.GetFiles(output).Length==0,"Opening an image auto-saved before explicit Save.");
        ScreenshotInvoke(app,editor,"100%");ScreenshotDrag(app,editor,"\u5b9e\u5fc3\u906e\u6321",selected,new Point(10,10),new Point(80,70));
        WaitFor(delegate{AutomationElement undo=ScreenshotButton(editor,"\u64a4\u9500");return undo!=null&&undo.Current.IsEnabled;},10,"Actual solid redaction did not commit an undoable edit.",app);
        ScreenshotDrag(app,editor,"\u88c1\u526a",selected,new Point(8,8),new Point(selected.Width-8,selected.Height-8));
        Size cropped=new Size(selected.Width-16,selected.Height-16);
        WaitFor(delegate{return Element(editor,cropped.Width+" \u00d7 "+cropped.Height+" px")!=null;},10,"Actual pixel crop dimensions did not render before export.",app);
        using(Bitmap copied=ScreenshotClipboard(app,editor,cropped)) {
            Assert(copied.GetPixel(12,12).ToArgb()==Color.FromArgb(228,93,104).ToArgb(),"Real editor solid mask did not replace generated source pixels.");
            Assert(copied.GetPixel(100,70).ToArgb()==Color.FromArgb(23,101,199).ToArgb(),"Generated blue source pixels were not retained outside redaction.");
            Assert(copied.GetPixel(cropped.Width-20,cropped.Height-20).ToArgb()==Color.FromArgb(210,60,90).ToArgb(),"Generated second source color was not retained after crop.");
            ScreenshotInvoke(app,editor,"\u4fdd\u5b58");WaitFor(delegate{return Directory.GetFiles(output,"*.png").Length==1&&ScreenshotButton(editor,"\u4fdd\u5b58").Current.IsEnabled;},15,"Explicit actual Save did not create a PNG in the selected owned folder.",app);
            string firstPath=Directory.GetFiles(output,"*.png")[0];Assert(Path.GetFileName(firstPath).StartsWith("Screenshot_",StringComparison.Ordinal),"Default filename was not generated by the screenshot backend.");ScreenshotPng(firstPath,copied);byte[] firstBytes=File.ReadAllBytes(firstPath);
            ScreenshotInvoke(app,editor,"\u4fdd\u5b58");WaitFor(delegate{return Directory.GetFiles(output,"*.png").Length==2&&ScreenshotButton(editor,"\u4fdd\u5b58").Current.IsEnabled;},15,"Second explicit Save overwrote rather than collision-numbering.",app);
            string[] files=Directory.GetFiles(output,"*.png");foreach(string file in files)ScreenshotPng(file,copied);
            Assert(Convert.ToBase64String(firstBytes)==Convert.ToBase64String(File.ReadAllBytes(firstPath)),"First export changed after saving again.");
            dragged["savedPngCount"]=files.Length;dragged["exportNames"]=Array.ConvertAll(files,delegate(string path){return Path.GetFileName(path);});dragged["copiedPixelSize"]=new int[]{copied.Width,copied.Height};dragged["allExportPixelsMatchSystemClipboard"]=true;dragged["noOverwrite"]=true;dragged["noHiddenPngMetadataOrTrailingData"]=true;
        }
        ScreenshotCancelFileDialog(app,editor,"\u53e6\u5b58\u4e3a");ScreenshotCancelFileDialog(app,editor,"\u6253\u5f00\u56fe\u7247");
        Assert(Directory.GetFiles(output,"*.png").Length==2,"Cancelled native file dialog wrote an unexpected export.");
        using(Bitmap retained=ScreenshotClipboard(app,editor,cropped))Assert(retained.GetPixel(12,12).ToArgb()==Color.FromArgb(228,93,104).ToArgb(),"Cancelled Open discarded edited image pixels.");
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
        dragged["case"]="drag-redact-crop-copy-save-twice";dragged["ok"]=true;cases.Add(dragged);
        Dictionary<string,object> clicked=ScreenshotPicker(form,image,app,first,dragPid);RequireForeground(form);Send(new INPUT[]{down,up});
        WaitFor(delegate{return IsWindowVisible(editor)&&Element(editor,ScreenshotCanvasName)!=null&&AppOverlays(app.Id)==0;},25,"Click-visible-window F1 did not open editor.",app);
        int[] windowSize=(int[])clicked["expectedWindowDimensions"];using(Bitmap copy=ScreenshotClipboard(app,editor,new Size(windowSize[0],windowSize[1]))) { clicked["visibleWindowPixelSize"]=new int[]{copy.Width,copy.Height}; }
        ScreenshotInvoke(app,editor,"\u5173\u95ed\u622a\u56fe\u7f16\u8f91\u5668");ScreenshotInvoke(app,editor,"\u7ee7\u7eed\u7f16\u8f91");Assert(IsWindowVisible(editor),"Cancel in unsaved close discarded the editor.");
        ScreenshotInvoke(app,editor,"\u5173\u95ed\u622a\u56fe\u7f16\u8f91\u5668");ScreenshotInvoke(app,editor,"\u4e22\u5f03\u5e76\u5173\u95ed");WaitFor(delegate{return !IsWindowVisible(editor);},10,"Explicit discard did not close unsaved editor.",app);
        Assert(Directory.GetFiles(output,"*.png").Length==4,"Closing an unsaved screenshot auto-saved or lost an earlier explicit export.");report["screenshotFinalExportCount"]=4;clicked["case"]="click-window-close-cancel-confirm";clicked["ok"]=true;cases.Add(clicked);
        Dictionary<string,object> after=CompletedCaptureSnapshot(app,start,executable,roaming,token,0,report);RequireCaptureReleased(after);
        Assert(CaptureNumber(after,"ocrInvocationCount")==0,"F1 image editing invoked OCR.");
        Assert(server.Connections==0&&server.Count==0&&server.Error==null,"F1 image editing performed an HTTP/provider request.");
        Assert(!File.Exists(history)||new JavaScriptSerializer().Deserialize<object[]>(File.ReadAllText(history)).Length==0,"F1 image editing wrote translation history.");
        Assert(sourceEvents()==0,"Native F1 click/drag leaked mouse input to generated source controls.");
        report["screenshotOcrInvocationCount"]=CaptureNumber(after,"ocrInvocationCount");report["screenshotHttpConnections"]=server.Connections;report["screenshotNetworkEvidenceScope"]="configured-loopback-provider-trap; no global packet capture";report["screenshotTranslationHistoryCount"]=0;
        report["screenshotRequiredCases"]=3;report["screenshotPassedCases"]=cases.Count;report["verifiedNativeCaptureGenerations"]=VerifiedNativeChildren.Count;report["screenshotNativeCompletion"]=after;
        Assert(cases.Count==3&&VerifiedNativeChildren.Count>=3,"Screenshot fixture missed a required real native generation.");
        passed.Add("Actual F1 cancel, native hover/drag and window-click -> dedicated real WebView editor -> opaque pixels/crop -> system image clipboard -> collision-safe PNG files in owned temp folder; zero OCR/configured-provider HTTP/history (loopback trap, not global packet capture)");
        Clipboard.Clear();
    }
}
