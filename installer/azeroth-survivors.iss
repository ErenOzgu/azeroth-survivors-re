; Azeroth Survivors - Windows installer (Inno Setup 6).
;
; Installs the player build of `warcraft-survivors.exe` into a folder the user picks, then gets the
; WoW 1.12.1 client data into <exe dir>\Data, where the game looks for it: either downloaded (the
; same archive.org zip scripts/fetch-data.sh uses) or, when the user already has it, taken from a
; folder they point at (the zip, or the .MPQ files). Nothing from the game client is bundled.
;
; Build: see installer\README.md. CI builds it in .github/workflows/windows-installer.yml.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
; The folder holding the release warcraft-survivors.exe.
#ifndef BuildDir
  #define BuildDir "..\target\release"
#endif

#define AppName "Azeroth Survivors"
#define AppExe "warcraft-survivors.exe"
#define DataUrl "https://archive.org/download/WoW_1.12.1-5875/1.12.1-5875_enUS.zip"

[Setup]
AppId={{526506D6-30BC-4538-A661-EF5069A28F21}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
; Per-user install: the game writes its settings to <exe dir>\benilla-config, which must stay
; writable without admin rights, so the default is %LOCALAPPDATA%\Programs and no UAC prompt.
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
DisableDirPage=no
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=output
OutputBaseFilename=AzerothSurvivors-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; The extracted MPQs, which the installer does not carry (approximate: the zip is ~5.5 GB).
ExtraDiskSpaceRequired=6500000000

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked

[Files]
Source: "{#BuildDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE-MIT"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE-APACHE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CONTROLS.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "extract-data.ps1"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The downloaded game data is ours to remove; benilla-config (settings) is left alone.
Type: filesandordirs; Name: "{app}\Data"
Type: dirifempty; Name: "{app}"


[Code]
var
  DownloadPage: TDownloadWizardPage;
  SourcePage: TInputOptionWizardPage;
  FolderPage: TInputDirWizardPage;
  // What FindDataSource found in the folder the user pointed at: a zip file or a folder of MPQs.
  DataSource: String;

function OnDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  Result := True;
end;

// True when the user chose to use game data they already have instead of downloading it.
function UseExistingData: Boolean;
begin
  Result := SourcePage.SelectedValueIndex = 1;
end;

// The two MPQs the game cannot boot without: both present = the data is already installed.
function DataPresent: Boolean;
var
  Data: String;
begin
  Data := AddBackslash(WizardDirValue) + 'Data\';
  Result := FileExists(Data + 'terrain.MPQ') and FileExists(Data + 'patch.MPQ');
end;

// What the folder holds that the game data can come from: the WoW Data folder (or the folder
// above it), or the zip the installer would download, or any other zip. Empty when none.
function FindDataSource(Folder: String): String;
var
  Dir: String;
  FindRec: TFindRec;
begin
  Result := '';
  Dir := RemoveBackslash(Trim(Folder));
  if Dir = '' then
    Exit;
  if FileExists(Dir + '\terrain.MPQ') and FileExists(Dir + '\patch.MPQ') then
  begin
    Result := Dir;
    Exit;
  end;
  if FileExists(Dir + '\Data\terrain.MPQ') and FileExists(Dir + '\Data\patch.MPQ') then
  begin
    Result := Dir + '\Data';
    Exit;
  end;
  if FileExists(Dir + '\1.12.1-5875_enUS.zip') then
  begin
    Result := Dir + '\1.12.1-5875_enUS.zip';
    Exit;
  end;
  if FindFirst(Dir + '\*.zip', FindRec) then
  begin
    try
      Result := Dir + '\' + FindRec.Name;
    finally
      FindClose(FindRec);
    end;
  end;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), SetupMessage(msgPreparingDesc), @OnDownloadProgress);

  SourcePage := CreateInputOptionPage(wpSelectDir, 'Game data',
    'Where should the game data come from?',
    'The game needs the World of Warcraft 1.12.1 client data (about 5.5 GB).', True, False);
  SourcePage.Add('Download it now from archive.org');
  SourcePage.Add('Use game data I already have (skips the download)');
  SourcePage.SelectedValueIndex := 0;

  FolderPage := CreateInputDirPage(SourcePage.ID, 'Existing game data',
    'Where is the game data?',
    'Select the folder that holds 1.12.1-5875_enUS.zip, or the WoW "Data" folder with the .MPQ files, then click Next.',
    False, '');
  FolderPage.Add('');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  // An install that already has its data (a reinstall or upgrade) asks nothing about it.
  if PageID = SourcePage.ID then
    Result := DataPresent
  else if PageID = FolderPage.ID then
    Result := DataPresent or (not UseExistingData);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if CurPageID = FolderPage.ID then
  begin
    DataSource := FindDataSource(FolderPage.Values[0]);
    if DataSource = '' then
    begin
      MsgBox('That folder has no game data in it: no .zip file and no .MPQ files. ' +
             'Pick the folder that holds 1.12.1-5875_enUS.zip, or the WoW "Data" folder.',
             mbError, MB_OK);
      Result := False;
    end;
  end;

  // The download runs when the user clicks Install, after the folder is chosen, and goes to {tmp}.
  if (CurPageID = wpReady) and (not DataPresent) and (not UseExistingData) then
  begin
    DownloadPage.Clear;
    DownloadPage.Add('{#DataUrl}', 'wow-data.zip', '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
      except
        if DownloadPage.AbortedByUser then
          Log('The download was cancelled.')
        else
          SuppressibleMsgBox(AddPeriod(GetExceptionMessage), mbCriticalError, MB_OK, IDOK);
        Result := False;
      end;
    finally
      DownloadPage.Hide;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Source, Params: String;
begin
  if (CurStep = ssPostInstall) and (not DataPresent) then
  begin
    if UseExistingData then
    begin
      Source := DataSource;
      WizardForm.StatusLabel.Caption := 'Copying the game data (a few minutes)...';
    end
    else
    begin
      Source := ExpandConstant('{tmp}\wow-data.zip');
      WizardForm.StatusLabel.Caption := 'Extracting the game data (a few minutes)...';
    end;
    ExtractTemporaryFile('extract-data.ps1');
    WizardForm.FilenameLabel.Caption := '';
    WizardForm.ProgressGauge.Style := npbstMarquee;
    try
      Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\extract-data.ps1') +
                '" -Source "' + Source +
                '" -Dest "' + ExpandConstant('{app}') + '"';
      if (not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE,
                   ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
        SuppressibleMsgBox('The game data could not be set up (exit code ' + IntToStr(ResultCode) +
                           '). The game itself is installed; run this installer again to retry the data.',
                           mbError, MB_OK, IDOK);
    finally
      WizardForm.ProgressGauge.Style := npbstNormal;
    end;
  end;
end;
