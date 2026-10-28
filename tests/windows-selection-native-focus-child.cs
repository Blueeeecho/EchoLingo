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
    public sealed class ChildBox:TextBox {
        readonly IntPtr host;
        public ChildBox(IntPtr parent) {host=parent;Multiline=true;Text="Prefix "+Selected+" suffix";Font=new Font("Consolas",12);}
        protected override CreateParams CreateParams {get{CreateParams cp=base.CreateParams;cp.Parent=host;cp.Style|=0x40000000|0x10000000;cp.Style&=unchecked((int)~0x80000000U);return cp;}}
        protected override void WndProc(ref Message message) {if(message.Msg==0x10){Dispose();Application.ExitThread();return;}base.WndProc(ref message);}
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
