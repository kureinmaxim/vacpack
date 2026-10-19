; Inno Setup script. Build through `scripts\windows.ps1 -Mode installer`,
; which passes AppVersion, SourceDir (published folder) and OutputDir.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\.build\windows\Vacpack"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\.build\windows"
#endif

[Setup]
AppId={{B7D3F2A1-5C94-4E08-8A6B-1F0E92C47D53}
AppName=Vacpack
AppVersion={#AppVersion}
AppVerName=Vacpack {#AppVersion}
AppPublisher=Vacpack
DefaultDirName={autopf}\Vacpack
DefaultGroupName=Vacpack
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Vacpack.exe
SetupIconFile=..\Vacpack.Windows\Resources\Vacpack.ico
LicenseFile=..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=Vacpack-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Vacpack"; Filename: "{app}\Vacpack.exe"
Name: "{autodesktop}\Vacpack"; Filename: "{app}\Vacpack.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Vacpack.exe"; Description: "{cm:LaunchProgram,Vacpack}"; Flags: nowait postinstall skipifsilent
