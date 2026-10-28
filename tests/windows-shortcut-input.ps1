# Generated-key/registered-conflict owner for the isolated packaged-app test.
[CmdletBinding()]
param([ValidateSet('send','hold','probe')][string]$Mode, [int]$ApplicationProcessId, [uint32]$Modifiers, [uint32]$Key)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class EchoLingoShortcutInput {
    delegate bool Enumerate(IntPtr window, IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(Enumerate callback, IntPtr unused);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, INPUT[] input, int size);
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct DATA { [FieldOffset(0)] public MOUSE mouse; [FieldOffset(0)] public KEY key; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public DATA data; }
    static void One(ushort key, bool up) { INPUT value=new INPUT();value.type=1;value.data.key.vk=key;value.data.key.flags=up?2U:0U; if(SendInput(1,new INPUT[]{value},Marshal.SizeOf(typeof(INPUT)))!=1)throw new Exception("Own fixture key was rejected."); }
    public static void Send(int owner, uint modifiers, uint key) {
        IntPtr target=IntPtr.Zero;int count=0;
        EnumWindows(delegate(IntPtr window,IntPtr unused){uint pid;GetWindowThreadProcessId(window,out pid);StringBuilder name=new StringBuilder(256);GetClassName(window,name,name.Capacity);if(pid==owner&&IsWindowVisible(window)&&name.ToString()=="Tauri Window"){target=window;count++;}return true;},IntPtr.Zero);
        if(target==IntPtr.Zero||count!=1)throw new Exception("Expected one visible own Tauri main window.");
        SetForegroundWindow(target);Thread.Sleep(50);uint foreground;GetWindowThreadProcessId(GetForegroundWindow(),out foreground);
        if(foreground!=owner)throw new Exception("Refused key outside the own application.");
        bool ctrl=(modifiers&2)!=0,alt=(modifiers&1)!=0,shift=(modifiers&4)!=0;
        try {if(ctrl)One(0x11,false);if(alt)One(0x12,false);if(shift)One(0x10,false);One((ushort)key,false);Thread.Sleep(40);One((ushort)key,true);}
        finally {if(shift)One(0x10,true);if(alt)One(0x12,true);if(ctrl)One(0x11,true);}
    }
}
'@
if ($Mode -eq 'probe') {
    if ([EchoLingoShortcutInput]::RegisterHotKey([IntPtr]::Zero, 17032, $Modifiers, $Key)) {
        if (-not [EchoLingoShortcutInput]::UnregisterHotKey([IntPtr]::Zero, 17032)) { throw 'Probe cleanup failed.' }
        [Console]::Out.WriteLine('AVAILABLE')
    } elseif ([Runtime.InteropServices.Marshal]::GetLastWin32Error() -eq 1409) { [Console]::Out.WriteLine('CONFLICT') }
    else { throw 'Availability probe returned an unknown Windows error.' }
} elseif ($Mode -eq 'hold') {
    if (-not [EchoLingoShortcutInput]::RegisterHotKey([IntPtr]::Zero, 17032, $Modifiers, $Key)) { throw 'Cannot own fixture conflict.' }
    try { [Console]::Out.WriteLine('READY'); [Console]::Out.Flush(); $null = [Console]::In.ReadLine() }
    finally { if (-not [EchoLingoShortcutInput]::UnregisterHotKey([IntPtr]::Zero, 17032)) { throw 'Fixture conflict cleanup failed.' } }
} else { [EchoLingoShortcutInput]::Send($ApplicationProcessId, $Modifiers, $Key) }
