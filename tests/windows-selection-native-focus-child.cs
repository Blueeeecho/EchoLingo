// Generated child HWND only. The same implementation can run in a second STA
// thread or in a separate, fixture-owned process. No desktop enumeration.
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class WindowsSelectionNativeFocusChild {
    public const string Selected="Generated cross process selected text 61843";
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll")] static extern IntPtr SetParent(IntPtr child,IntPtr parent);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern short GetKeyState(int key);
    [DllImport("user32.dll")] static extern IntPtr GetFocus();
    public const int DiagnosticMessage=0x8501;
    public sealed class ChildBox:TextBox {
        readonly IntPtr host;
        int keyDowns,keyUps,cDowns,cUps,copyMessages,copyCharacters,controlAtCDown,focusAtCDown,preprocessCalls,commandCopyCalls,focusGained,focusLost,mouseDownsCompleted,mouseUpsCompleted;
        public ChildBox(IntPtr parent) {host=parent;Multiline=true;Text="Prefix "+Selected+" suffix";Font=new Font("Consolas",12);}
        protected override CreateParams CreateParams {get{CreateParams cp=base.CreateParams;cp.Parent=host;cp.Style|=0x40000000|0x10000000;cp.Style&=unchecked((int)~0x80000000U);return cp;}}
        public override bool PreProcessMessage(ref Message message){preprocessCalls++;return base.PreProcessMessage(ref message);}
        protected override bool ProcessCmdKey(ref Message message,Keys key){if(key==(Keys.Control|Keys.C))commandCopyCalls++;return base.ProcessCmdKey(ref message,key);}
        protected override void WndProc(ref Message message) {
            if(message.Msg==DiagnosticMessage){int[] values={keyDowns,keyUps,cDowns,cUps,copyMessages,copyCharacters,controlAtCDown,focusAtCDown,preprocessCalls,commandCopyCalls,focusGained,focusLost,TextLength,mouseDownsCompleted,mouseUpsCompleted};int index=message.WParam.ToInt32();message.Result=new IntPtr(index>=0&&index<values.Length?values[index]:-1);return;}
            if(message.Msg==0x100||message.Msg==0x104){keyDowns++;if(message.WParam.ToInt32()==0x43){cDowns++;controlAtCDown=(GetKeyState(0x11)&0x8000)!=0?1:0;focusAtCDown=GetFocus()==Handle?1:0;}}
            if(message.Msg==0x101||message.Msg==0x105){keyUps++;if(message.WParam.ToInt32()==0x43)cUps++;}
            if(message.Msg==0x301)copyMessages++;
            if(message.Msg==0x102&&message.WParam.ToInt32()==3)copyCharacters++;
            if(message.Msg==7)focusGained++;if(message.Msg==8)focusLost++;
            if(message.Msg==0x10){Dispose();Application.ExitThread();return;}
            bool leftDown=message.Msg==0x201,leftUp=message.Msg==0x202;
            base.WndProc(ref message);
            // Publish completion only after native selection tracking has
            // finished, not merely when focus first appears on button-down.
            if(leftDown)mouseDownsCompleted++;if(leftUp)mouseUpsCompleted++;
        }
    }
    public static void Run(IntPtr host,uint parentProcess,Action<IntPtr> ready) {
        uint owner;GetWindowThreadProcessId(host,out owner);if(host==IntPtr.Zero||owner==0||owner!=parentProcess)throw new InvalidOperationException("GENERATED_HOST_OWNERSHIP_MISMATCH");
        SetThreadDpiAwarenessContext(new IntPtr(-4));
        using(ChildBox box=new ChildBox(host)) {
            IntPtr handle=box.Handle;SetParent(handle,host);if(GetParent(handle)!=host)throw new InvalidOperationException("GENERATED_CHILD_PARENT_MISMATCH");
            if(!SetWindowPos(handle,IntPtr.Zero,10,10,620,95,0x14))throw new InvalidOperationException("GENERATED_CHILD_POSITION_FAILED");
            box.Select(7,Selected.Length);ready(handle);Application.Run();
        }
    }
    [STAThread]
    public static int Main(string[] args) {
        try {if(args.Length!=2)return 2;SetProcessDpiAwarenessContext(new IntPtr(-4));
            Run(new IntPtr(Int64.Parse(args[0])),UInt32.Parse(args[1]),delegate(IntPtr window){Console.Out.WriteLine(window.ToInt64());Console.Out.Flush();});return 0;
        }catch{Console.Error.WriteLine("GENERATED_CHILD_FAILED");return 1;}
    }
}
