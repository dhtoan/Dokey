# Dokey for Windows - end-to-end typing test (CI).
# Copyright (c) 2026 Do Huy Toan. All rights reserved.
#
# Starts Dokey and Notepad (or Chrome), types Telex as plain key presses with
# SendInput (like a physical keyboard) and reads the text back: from Notepad's
# edit control, or from the page title, which the test page keeps equal to its
# text box. SendKeys is not used: it calls BlockInput, which also blocks
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
    // Types `text` one key press at a time, `delayMs` apart. '\n' is Enter, '\b' Backspace.
    public static void Type(string text, int delayMs) {
        foreach (char c in text) {
            ushort vk; bool shift = false;
            if (c == '\n') { vk = 0x0D; } else if (c == '\b') { vk = 0x08; } else { short s = VkKeyScan(c); vk = (ushort)(s & 0xFF); shift = (s & 0x100) != 0; }
            if (shift) Key(0x10, false);
            Key(vk, false);
            Key(vk, true);
            if (shift) Key(0x10, true);
            if (delayMs > 0) System.Threading.Thread.Sleep(delayMs);
        }
    }
    // One character as a KEYEVENTF_UNICODE press, like Dokey's output.
    public static void Unicode(char c) {
        INPUT[] i = new INPUT[2];
        i[0].type = 1; i[0].u.ki.wScan = c; i[0].u.ki.dwFlags = 4;
        i[1].type = 1; i[1].u.ki.wScan = c; i[1].u.ki.dwFlags = 6;
        SendInput(2, i, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void Press(ushort vk) { Key(vk, false); Key(vk, true); }
    // Dokey-like edits: 'G' guard U+00B7, 'D' Delete, 'B' Backspace, 'S' U+0111, `gapMs` apart.
    public static void Burst(string spec, int gapMs) {
        foreach (char k in spec) {
            if (k == 'G') Unicode((char)0xB7); else if (k == 'S') Unicode((char)0x111);
            else if (k == 'D') Press(0x2E); else if (k == 'B') Press(0x08);
            if (gapMs > 0) System.Threading.Thread.Sleep(gapMs);
        }
    }
    // A key pressed with a modifier held, e.g. Ctrl+L.
    public static void Chord(ushort modifier, ushort vk) {
        Key(modifier, false); Key(vk, false); Key(vk, true); Key(modifier, true);
    }
    // Lowercase letters and spaces with rollover: each key goes down before
    // the previous one comes up, as in fast real typing.
    public static void TypeRolled(string text, int delayMs) {
        ushort last = 0;
        foreach (char c in text) {
            ushort vk = (ushort)(VkKeyScan(c) & 0xFF);
            Key(vk, false);
            if (last != 0) Key(last, true);
            last = vk;
            if (delayMs > 0) System.Threading.Thread.Sleep(delayMs);
        }
        if (last != 0) Key(last, true);
    }
}
"@

function Start-Dokey([int]$language) {
    # New-Item -Force would recreate the key and drop values set by the caller.
    if (-not (Test-Path HKCU:\Software\Dokey)) { New-Item -Path HKCU:\Software\Dokey | Out-Null }
    Set-ItemProperty -Path HKCU:\Software\Dokey -Name Vietnamese -Value 1 -Type DWord
    Set-ItemProperty -Path HKCU:\Software\Dokey -Name Method -Value 0 -Type DWord
    Set-ItemProperty -Path HKCU:\Software\Dokey -Name Language -Value $language -Type DWord
    $dokey = Start-Process -FilePath $Exe -ArgumentList '--background' -PassThru
    Start-Sleep -Seconds 2
    return $dokey
}

# Starts Dokey with `language` (0 Vietnamese, 1 Korean) and Notepad, runs
# `typing`, and returns Notepad's text.
function Invoke-Case([int]$language, [scriptblock]$typing) {
    $dokey = Start-Dokey $language
    $notepad = Start-Process -FilePath notepad.exe -PassThru
    $notepad.WaitForInputIdle() | Out-Null
    Start-Sleep -Seconds 1
    [W]::SetForegroundWindow($notepad.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 500
    try {
        & $typing
        Start-Sleep -Seconds 2
        $edit = [W]::FindWindowEx($notepad.MainWindowHandle, [IntPtr]::Zero, "Edit", $null)
        $len = [int][W]::SendMessage($edit, 0x000E, [IntPtr]::Zero, [IntPtr]::Zero)
        $sb = New-Object System.Text.StringBuilder ($len + 1)
        [W]::SendMessage($edit, 0x000D, [IntPtr]($len + 1), $sb) | Out-Null
        return $sb.ToString()
    } finally {
        Stop-Process -Id $notepad.Id -Force -ErrorAction SilentlyContinue
        Stop-Process -Id $dokey.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

# A text box that can complete words inline the way address bars do: after a
# typed letter, the rest of the word `ac` is added and selected (caret at the typed end
# when `dir` is backward, like Chrome's address bar).
$page = Join-Path $env:TEMP 'dokey-e2e.html'
Set-Content -Path $page -Encoding UTF8 -Value @'
<!doctype html><meta charset="utf-8"><title>DK:</title>
<textarea id="t" autofocus style="width:90vw;height:40vh"></textarea>
<div id="ce" contenteditable="true" style="width:90vw;height:40vh;border:1px solid"></div>
<script>
const t = document.getElementById('t'), q = new URLSearchParams(location.search);
if (q.get('ce')) {
  // A rich editor (contenteditable), as in Gmail, Messenger, Notion.
  const ce = document.getElementById('ce');
  t.remove();
  ce.focus();
  ce.addEventListener('input', () => { document.title = 'DK:' + ce.innerText.replace(/\u00a0/g, ' ') + '|'; });
}
const ac = q.get('ac') || '', dir = q.get('dir') || 'backward';
t.addEventListener('input', e => {
  const v = t.value, w = v.slice(v.lastIndexOf(' ') + 1);
  if (ac && e.inputType === 'insertText' && w && w.length < ac.length && ac.startsWith(w)) {
    t.value = v + ac.slice(w.length);
    t.setSelectionRange(v.length, t.value.length, dir);
  }
  document.title = 'DK:' + t.value.slice(0, t.selectionStart) + '|';  // | keeps the trailing space
});
</script>
'@

function Get-ChromeWindow {
    Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like 'DK:*' } | Select-Object -First 1
}

# Like Invoke-Case, in a Chrome window on the test page; returns the text up
# to the caret (so a completion still selected does not count).
function Invoke-ChromeCase([string]$query, [scriptblock]$typing) {
    $chrome = @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $chrome) { throw 'Chrome not found' }
    $dokey = Start-Dokey 0
    $profile = Join-Path $env:TEMP ("dokey-chrome-" + [guid]::NewGuid())
    $url = 'file:///' + ($page -replace '\\', '/') + '?' + $query
    Start-Process -FilePath $chrome -ArgumentList "--user-data-dir=$profile", '--no-first-run',
        '--no-default-browser-check', '--disable-sync', "--app=$url" | Out-Null
    try {
        $window = $null
        for ($i = 0; $i -lt 40 -and -not $window; $i++) { Start-Sleep -Milliseconds 500; $window = Get-ChromeWindow }
        if (-not $window) { throw 'Chrome window not found' }
        Start-Sleep -Seconds 2
        [W]::SetForegroundWindow($window.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 500
        & $typing
        Start-Sleep -Seconds 2
        return (Get-ChromeWindow).MainWindowTitle.Substring(3).TrimEnd('|')
    } finally {
        Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Stop-Process -Id $dokey.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

function Test-Text([string]$name, [string]$text, [string]$expected) {
    $codes = ($text.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
    Write-Host "[$name] Typed:    $codes"
    Write-Host "[$name] Text: $text"
    if ($text -ceq $expected) {
        Write-Host "[$name] passed."
        return $true
    }
    $want = ($expected.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
    Write-Host "[$name] Expected: $want"
    return $false
}

$exitCode = 0

# Vietnamese (Telex).
$text = Invoke-Case 0 {
    $line = "Vieetj Nam dduowngf windows Tooi yeeu tieengs Vieetj "
    [W]::Type($line + "`n", 40)  # a normal typist
    [W]::Type($line + "`n", 0)   # as fast as SendInput goes: tests ordering
    # Dokey 0.4: reopen a word with Backspace after its space, and a text shortcut.
    [W]::Type("Haxy xin `bf btw `n", 40)
    # Doubled letters (aa, dd, oo, ee) followed by a tone, fast and with rollover.
    [W]::Type("thaayf ddi hocj bees tooi `n", 0)
    [W]::TypeRolled("thaayf ddi hocj bees tooi ", 15)
}
$viet = "Vi$([char]0x1EC7)t"
$want = "$viet Nam $([char]0x0111)$([char]0x01B0)$([char]0x1EDD)ng windows T$([char]0x00F4)i y$([char]0x00EA)u ti$([char]0x1EBF)ng $viet "
$third = "H$([char]0x00E3)y x$([char]0x00EC)n by the way "
$thay = "th$([char]0x1EA7)y $([char]0x0111)i h$([char]0x1ECD)c b$([char]0x1EBF) t$([char]0x00F4)i "
if (-not (Test-Text 'Vietnamese' $text ($want + "`r`n" + $want + "`r`n" + $third + "`r`n" + $thay + "`r`n" + $thay))) { $exitCode = 1 }

# Chrome: a plain text box, then one that completes "thanhnien" inline (both
# selection directions), the case where Backspace removed the completion
# instead of the letter ("thaayf" gave "thaầy").
$cases = @(
    @{ name = 'Chrome'; query = '' },
    @{ name = 'Chrome autocomplete'; query = 'ac=thanhnien&dir=backward' },
    @{ name = 'Chrome autocomplete (forward)'; query = 'ac=thanhnien&dir=forward' },
    @{ name = 'Chrome autocomplete (d)'; query = 'ac=dantri&dir=backward' },
    @{ name = 'Chrome rich editor'; query = 'ce=1' }
)
foreach ($case in $cases) {
    $text = Invoke-ChromeCase $case.query {
        [W]::Type("thaayf ddi hocj bees tooi ddoox ", 40)
        [W]::Type("thaayf ddi hocj bees tooi ddoox ", 0)
        [W]::TypeRolled("thaayf ddi hocj bees tooi ddoox ", 15)
    }
    $line = $thay + "$([char]0x0111)$([char]0x1ED7) "
    if (-not (Test-Text $case.name $text ($line + $line + $line))) { $exitCode = 1 }
}

# The real address bar of Chrome and Edge, with history so that "d" and "th"
# complete inline (thaayf gave "thaầy", ddoox gave "dđỗ"). Pages are served
# from *.localhost, which the browsers resolve to this machine.
$listener = Start-Job -ScriptBlock {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add('http://+:8123/')
    $l.Start()
    while ($true) {
        $c = $l.GetContext()
        $b = [Text.Encoding]::UTF8.GetBytes('<title>ok</title>ok')
        $c.Response.OutputStream.Write($b, 0, $b.Length)
        $c.Response.Close()
    }
}
Start-Sleep -Seconds 2
$readAddress = Join-Path $env:TEMP 'dokey-address.ps1'
Set-Content -Path $readAddress -Encoding UTF8 -Value @'
param([int]$hwnd, [string]$out)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$hwnd)
$cond = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::Edit)
$edit = $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $cond)
$value = if ($edit) { $edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value } else { '<no edit>' }
[IO.File]::WriteAllText($out, $value, [Text.Encoding]::UTF8)
'@
function Read-Address($hwnd) {
    $out = Join-Path $env:TEMP 'dokey-address.txt'
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $readAddress -hwnd ([int]$hwnd) -out $out | Out-Null
    return [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8)
}
$browsers = @(
    @{ name = 'Chrome'; exe = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"; process = 'chrome' },
    @{ name = 'Edge'; exe = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; process = 'msedge' }
)
foreach ($b in $browsers) {
    if (-not (Test-Path $b.exe)) { Write-Host "[$($b.name) address bar] skipped: not installed"; continue }
    $profile = Join-Path $env:TEMP ("dokey-" + $b.process + "-" + [guid]::NewGuid())
    Start-Process -FilePath $b.exe -ArgumentList "--user-data-dir=$profile", '--no-first-run', '--no-default-browser-check',
        '--disable-sync', '--disable-features=msEdgeOnRampFRE,msUndersideButton', 'about:blank' | Out-Null
    $dokey = $null
    try {
        $window = $null
        for ($i = 0; $i -lt 40 -and -not $window; $i++) {
            Start-Sleep -Milliseconds 500
            $window = Get-Process $b.process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        }
        if (-not $window) { throw "$($b.name) window not found" }
        Start-Sleep -Seconds 3
        $hwnd = $window.MainWindowHandle
        [W]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 500
        # History, typed without Dokey: twice each, so the address bar completes them inline.
        foreach ($i in 1..2) {
            foreach ($site in 'dantri.localhost:8123/', 'thanhnien.localhost:8123/') {
                [W]::Chord(0x11, 0x4C)
                Start-Sleep -Milliseconds 300
                [W]::Type("http://$site`n", 20)
                Start-Sleep -Seconds 2
            }
        }
        [W]::Chord(0x11, 0x4C)
        Start-Sleep -Milliseconds 300
        [W]::Type('d', 0)
        Start-Sleep -Seconds 1
        Write-Host "[$($b.name) address bar] 'd' without Dokey shows: $(Read-Address $hwnd)"
        $words = @(
            @{ keys = 'ddoox'; want = "$([char]0x0111)$([char]0x1ED7)" },
            @{ keys = 'thaayf'; want = "th$([char]0x1EA7)y" },
            @{ keys = 'ddi hocj'; want = "$([char]0x0111)i h$([char]0x1ECD)c" }
        )
        $log = Join-Path $env:TEMP 'dokey-debug.log'
        Remove-Item $log -ErrorAction SilentlyContinue
        Set-ItemProperty -Path HKCU:\Software\Dokey -Name DebugLog -Value 1 -Type DWord
        $dokey = Start-Dokey 0
        [W]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 500
        $failed = $false
        foreach ($w in $words) {
            foreach ($delay in 40, 0) {
                [W]::Chord(0x11, 0x4C)
                Start-Sleep -Milliseconds 300
                [W]::Type($w.keys, $delay)
                Start-Sleep -Seconds 1
                $value = Read-Address $hwnd
                if (-not (Test-Text "$($b.name) address bar: $($w.keys) ($delay ms)" $value $w.want)) { $failed = $true }
            }
        }
        Remove-ItemProperty -Path HKCU:\Software\Dokey -Name DebugLog -ErrorAction SilentlyContinue
        if ($failed) {
            $exitCode = 1
            Get-Content $log -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "[$($b.name) debug log] $_" }
        }
    } finally {
        Get-Process $b.process -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if ($dokey) { Stop-Process -Id $dokey.Id -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
    }
}
Stop-Job $listener -ErrorAction SilentlyContinue

# Korean (2-beolsik), letters read by key position: 안녕하세요 한국, typed normally then fast.
$text = Invoke-Case 1 {
    [W]::Type("dkssudgktpdy gksrnr`n", 40)
    [W]::Type("dkssudgktpdy gksrnr ", 0)
}
$hello = -join ([char[]](0xC548, 0xB155, 0xD558, 0xC138, 0xC694))
$korea = -join ([char[]](0xD55C, 0xAD6D))
if (-not (Test-Text 'Korean' $text "$hello $korea`r`n$hello $korea ")) { $exitCode = 1 }

Set-ItemProperty -Path HKCU:\Software\Dokey -Name Language -Value 0 -Type DWord
if ($exitCode -eq 0) { Write-Host "End-to-end typing test passed." }
exit $exitCode
