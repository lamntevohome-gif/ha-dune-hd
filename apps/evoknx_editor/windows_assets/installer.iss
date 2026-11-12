; EvoKNX Editor – Windows installer (Inno Setup 6)
; Built by GitHub Actions: ISCC /DAppVersion=x.y.z /DSourceDir=<Release folder> installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\EvoKNX-Editor"
#endif
#define AppExe "evoknx_editor.exe"

[Setup]
AppId={{8C1E7A52-3F4B-4E3A-9B7D-5A2C1E0B9F11}
AppName=EvoKNX Editor
AppVersion={#AppVersion}
AppVerName=EvoKNX Editor {#AppVersion}
AppPublisher=Evohome
DefaultDirName={autopf}\EvoKNX Editor
DefaultGroupName=EvoKNX
DisableProgramGroupPage=yes
OutputDir=..\installer
OutputBaseFilename=EvoKNX-Editor-Setup-{#AppVersion}
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName=EvoKNX Editor
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ChangesAssociations=yes
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "evoknx_file.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\EvoKNX Editor"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\EvoKNX Editor"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; .evoknx files open in EvoKNX Editor (double-click opens a new window)
Root: HKA; Subkey: "Software\Classes\.evoknx"; ValueType: string; ValueName: ""; ValueData: "EvoKNX.Project"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\EvoKNX.Project"; ValueType: string; ValueName: ""; ValueData: "EvoKNX Project"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\EvoKNX.Project\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\evoknx_file.ico"
Root: HKA; Subkey: "Software\Classes\EvoKNX.Project\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,EvoKNX Editor}"; Flags: nowait postinstall skipifsilent
