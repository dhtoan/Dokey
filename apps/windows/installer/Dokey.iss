; Dokey for Windows - installer (Inno Setup 6.3 or later).
; Copyright (c) 2026 Do Huy Toan. All rights reserved.
;
;   iscc /DAppVersion=0.1.0 /DBinDir=C:\path\to\bin Dokey.iss
; BinDir holds x86\Dokey.exe, x64\Dokey.exe and arm64\Dokey.exe; Setup
; installs the one that runs natively on the target machine.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
; Numeric x.y.z for the file version resource (AppVersion may be 0.5.0-beta).
#ifndef AppNumVersion
  #define AppNumVersion AppVersion
#endif
#ifndef BinDir
  #define BinDir "..\..\..\dist\bin"
#endif
; The repository LICENSE as UTF-8 with a BOM and CRLF line ends (CI makes one),
; shown on the license page and installed as LICENSE.txt.
#ifndef LicenseTxt
  #define LicenseTxt "..\..\..\LICENSE"
#endif

[Setup]
AppId={{8F3C2A51-6B7D-4E2A-9C1F-D0E4B5A7C391}
AppName=Dokey
AppVersion={#AppVersion}
AppVerName=Dokey {#AppVersion}
AppPublisher=Do Huy Toan
AppPublisherURL=https://github.com/dhtoan/Dokey
AppCopyright=© 2026 Do Huy Toan. All rights reserved.
VersionInfoVersion={#AppNumVersion}
VersionInfoDescription=Dokey Setup
VersionInfoCopyright=© 2026 Do Huy Toan. All rights reserved.
LicenseFile={#LicenseTxt}
DefaultDirName={autopf}\Dokey
DefaultGroupName=Dokey
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64os arm64
MinVersion=10.0
OutputBaseFilename=Dokey-{#AppVersion}-Windows-Setup
SetupIconFile=..\res\dokey.ico
UninstallDisplayIcon={app}\Dokey.exe
UninstallDisplayName=Dokey
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup"; Description: "Start Dokey when I sign in to Windows (khởi động cùng Windows)"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#LicenseTxt}"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "{#BinDir}\arm64\Dokey.exe"; DestDir: "{app}"; Check: UseArm64; Flags: ignoreversion
Source: "{#BinDir}\x64\Dokey.exe"; DestDir: "{app}"; Check: UseX64; Flags: ignoreversion
Source: "{#BinDir}\x86\Dokey.exe"; DestDir: "{app}"; Check: UseX86; Flags: ignoreversion

[Icons]
Name: "{group}\Dokey"; Filename: "{app}\Dokey.exe"
Name: "{group}\Uninstall Dokey"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Dokey"; Filename: "{app}\Dokey.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Dokey"; ValueData: """{app}\Dokey.exe"" --background"; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Dokey.exe"; Description: "{cm:LaunchProgram,Dokey}"; Flags: nowait postinstall skipifsilent
; Dokey's own updater runs Setup /SILENT /relaunch=1: start the new Dokey afterwards.
Filename: "{app}\Dokey.exe"; Parameters: "--updated"; Flags: nowait runasoriginaluser; Check: Relaunch

[Code]
const
  WM_CLOSE = $0010;

function UseArm64: Boolean;
begin
  Result := IsArm64;
end;

function UseX64: Boolean;
begin
  Result := (not IsArm64) and IsX64OS;
end;

function UseX86: Boolean;
begin
  Result := (not IsArm64) and (not IsX64OS);
end;

function Relaunch: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;

{ Asks a running Dokey to quit (it removes its hooks and tray icon). }
procedure CloseDokey;
var
  Wnd: HWND;
  I: Integer;
begin
  Wnd := FindWindowByClassName('DokeyMainWindow');
  if Wnd = 0 then Exit;
  PostMessage(Wnd, WM_CLOSE, 0, 0);
  for I := 1 to 30 do begin
    if FindWindowByClassName('DokeyMainWindow') = 0 then Exit;
    Sleep(100);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  CloseDokey;
  Result := '';
end;

function InitializeUninstall: Boolean;
begin
  CloseDokey;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then begin
    { "Start with Windows" may also have been turned on from Dokey's menu. }
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Dokey');
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Dokey');
  end;
end;
