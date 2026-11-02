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
    New-Item -Path HKCU:\Software\Dokey -Force | Out-Null
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
<textarea id="t" autofocus style="width:90vw;height:80vh"></textarea>
<script>
const t = document.getElementById('t'), q = new URLSearchParams(location.search);
const ac = q.get('ac') || '', dir = q.get('dir') || 'backward';
t.addEventListener('input', e => {
  const v = t.value, w = v.slice(v.lastIndexOf(' ') + 1);
  if (ac && e.inputType === 'insertText' && w && w.length < ac.length && ac.startsWith(w)) {
    t.value = v + ac.slice(w.length);
    t.setSelectionRange(v.length, t.value.length, dir);
  }
  document.title = 'DK:' + t.value.slice(0, t.selectionStart);
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
        return (Get-ChromeWindow).MainWindowTitle.Substring(3)
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
    @{ name = 'Chrome autocomplete (forward)'; query = 'ac=thanhnien&dir=forward' }
)
foreach ($case in $cases) {
    $text = Invoke-ChromeCase $case.query {
        [W]::Type("thaayf ddi hocj bees tooi ", 40)
        [W]::Type("thaayf ddi hocj bees tooi ", 0)
        [W]::TypeRolled("thaayf ddi hocj bees tooi ", 15)
    }
    if (-not (Test-Text $case.name $text ($thay + $thay + $thay))) { $exitCode = 1 }
}

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
