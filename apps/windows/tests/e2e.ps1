# Dokey for Windows - end-to-end typing test (CI).
# Copyright (c) 2026 Do Huy Toan. All rights reserved.
#
# Starts Dokey and Notepad, types Telex as plain key presses with SendInput
# (like a physical keyboard) and reads the text back from Notepad's edit
# control. SendKeys is not used: it calls BlockInput, which also blocks
# Dokey's own SendInput.
param([Parameter(Mandatory = $true)][string]$Exe)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class W {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, StringBuilder l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern short VkKeyScan(char c);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
    static void Key(ushort vk, bool up) {
        INPUT[] i = new INPUT[1];
        i[0].type = 1;
        i[0].u.ki.wVk = vk;
        i[0].u.ki.wScan = (ushort)MapVirtualKey(vk, 0);
        i[0].u.ki.dwFlags = up ? 2u : 0u;
        SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
    }
    // Types `text` one key press at a time, `delayMs` apart. '\n' is Enter.
    public static void Type(string text, int delayMs) {
        foreach (char c in text) {
            ushort vk; bool shift = false;
            if (c == '\n') { vk = 0x0D; } else { short s = VkKeyScan(c); vk = (ushort)(s & 0xFF); shift = (s & 0x100) != 0; }
            if (shift) Key(0x10, false);
            Key(vk, false);
            Key(vk, true);
            if (shift) Key(0x10, true);
            if (delayMs > 0) System.Threading.Thread.Sleep(delayMs);
        }
    }
}
"@

New-Item -Path HKCU:\Software\Dokey -Force | Out-Null
Set-ItemProperty -Path HKCU:\Software\Dokey -Name Vietnamese -Value 1 -Type DWord
Set-ItemProperty -Path HKCU:\Software\Dokey -Name Method -Value 0 -Type DWord

$dokey = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds 2
$notepad = Start-Process -FilePath notepad.exe -PassThru
$notepad.WaitForInputIdle() | Out-Null
Start-Sleep -Seconds 1
[W]::SetForegroundWindow($notepad.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500

$exitCode = 0
try {
    $line = "Vieetj Nam dduowngf windows Tooi yeeu tieengs Vieetj "
    [W]::Type($line + "`n", 40)  # a normal typist
    [W]::Type($line, 0)          # as fast as SendInput goes: tests ordering
    Start-Sleep -Seconds 2
    $edit = [W]::FindWindowEx($notepad.MainWindowHandle, [IntPtr]::Zero, "Edit", $null)
    $len = [int][W]::SendMessage($edit, 0x000E, [IntPtr]::Zero, [IntPtr]::Zero)
    $sb = New-Object System.Text.StringBuilder ($len + 1)
    [W]::SendMessage($edit, 0x000D, [IntPtr]($len + 1), $sb) | Out-Null
    $text = $sb.ToString()
    $viet = "Vi$([char]0x1EC7)t"
    $want = "$viet Nam $([char]0x0111)$([char]0x01B0)$([char]0x1EDD)ng windows T$([char]0x00F4)i y$([char]0x00EA)u ti$([char]0x1EBF)ng $viet "
    $expected = $want + "`r`n" + $want
    $codes = ($text.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
    Write-Host "Typed:    $codes"
    Write-Host "Text: $text"
    if ($text -ceq $expected) {
        Write-Host "End-to-end typing test passed."
    } else {
        $want = ($expected.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
        Write-Host "Expected: $want"
        $exitCode = 1
    }
} finally {
    Stop-Process -Id $notepad.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $dokey.Id -Force -ErrorAction SilentlyContinue
}
exit $exitCode
