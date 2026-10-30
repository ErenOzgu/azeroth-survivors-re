; Azeroth Survivors - Windows setup wizard (Inno Setup 6).
; Compile with: ISCC.exe AzerothSurvivors.iss   (output: Output\AzerothSurvivors-Setup.exe)
;
; The wizard asks for the user's OWN WoW 1.12.1 (build 5875) Data folder. It does not bundle or
; download any Blizzard content. Build tools, Rust and the game source are fetched by bootstrap.ps1.

#define AppName "Azeroth Survivors"
#define AppVersion "0.1.0"
#define RepoUrl "https://github.com/OutThisLife/azeroth-survivors-re"

[Setup]
AppId={{7AE0CE40-185E-4716-A5B0-E1D338DA1345}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\AzerothSurvivors
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Runs as the normal user; bootstrap.ps1 asks for administrator approval only for Build Tools and Git.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
OutputBaseFilename=AzerothSurvivors-Setup
UninstallDisplayName={#AppName}
; Placeholder, not measured: the Rust build directory is large. Replace with a measured value.
ExtraDiskSpaceRequired=10737418240

[Files]
Source: "bootstrap.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "launch.cmd"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\launch.cmd"; WorkingDir: "{app}\repo"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\launch.cmd"; WorkingDir: "{app}\repo"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[UninstallDelete]
Type: filesandordirs; Name: "{app}\repo"
Type: files; Name: "{app}\wow-data-path.txt"
Type: files; Name: "{app}\install.log"

[Code]
var
  DataPage: TInputDirWizardPage;

procedure InitializeWizard;
begin
  DataPage := CreateInputDirPage(wpSelectDir,
    'WoW 1.12.1 game data',
    'Select your World of Warcraft 1.12.1 Data folder',
    'This game needs the Data folder of your own World of Warcraft 1.12.1 (build 5875) client. ' +
    'It is not included in this installer and is not downloaded by it. ' +
    'Select either the WoW folder or its Data folder.',
    False, '');
  DataPage.Add('');
end;

{ Returns the Data folder (the one holding terrain.MPQ and patch.MPQ), or '' if not found. }
function ResolveDataDir(const Path: String): String;
var
  Base: String;
begin
  Result := '';
  Base := AddBackslash(Path);
  if FileExists(Base + 'terrain.MPQ') and FileExists(Base + 'patch.MPQ') then
    Result := RemoveBackslash(Path)
  else if FileExists(Base + 'Data\terrain.MPQ') and FileExists(Base + 'Data\patch.MPQ') then
    Result := Base + 'Data';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = DataPage.ID then
  begin
    if ResolveDataDir(DataPage.Values[0]) = '' then
    begin
      MsgBox('terrain.MPQ and patch.MPQ were not found in that folder. ' +
        'Please select the Data folder of a WoW 1.12.1 (build 5875) client.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Params: String;
begin
  if CurStep = ssPostInstall then
  begin
    Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\bootstrap.ps1') + '"' +
      ' -InstallDir "' + ExpandConstant('{app}') + '"' +
      ' -WowData "' + ResolveDataDir(DataPage.Values[0]) + '"' +
      ' -RepoUrl "{#RepoUrl}"';
    WizardForm.StatusLabel.Caption := 'Installing build tools and building the game. This can take a long time...';
    if (not Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
      MsgBox('The setup script did not finish successfully. See the log for details:' + #13#10 +
        ExpandConstant('{app}\install.log'), mbError, MB_OK);
  end;
end;
