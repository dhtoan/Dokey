# Dokey for Windows - end-to-end typing test (CI).
# Copyright (c) 2026 Do Huy Toan. All rights reserved.
#
# Starts Dokey and Notepad, types Telex with SendKeys (SendInput) and reads the
# text back from Notepad's edit control.
param([Parameter(Mandatory = $true)][string]$Exe)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class W {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, StringBuilder l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
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
    [System.Windows.Forms.SendKeys]::SendWait("Vieetj Nam dduowngf windows ")
    Start-Sleep -Seconds 1
    $edit = [W]::FindWindowEx($notepad.MainWindowHandle, [IntPtr]::Zero, "Edit", $null)
    $len = [int][W]::SendMessage($edit, 0x000E, [IntPtr]::Zero, [IntPtr]::Zero)
    $sb = New-Object System.Text.StringBuilder ($len + 1)
    [W]::SendMessage($edit, 0x000D, [IntPtr]($len + 1), $sb) | Out-Null
    $text = $sb.ToString()
    $expected = "Vi$([char]0x1EC7)t Nam $([char]0x0111)$([char]0x01B0)$([char]0x1EDD)ng windows "
    $codes = ($text.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
    Write-Host "Typed:    $codes"
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
