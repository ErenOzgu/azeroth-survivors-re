; Azeroth Survivors - Windows installer (Inno Setup 6).
;
; Installs the player build of `warcraft-survivors.exe` into a folder the user picks, then downloads
; the WoW 1.12.1 client data (the same archive.org zip scripts/fetch-data.sh uses) and extracts its
; Data\*.MPQ files beside the exe, where the game looks for them (<exe dir>\Data). Nothing from
; the game client is bundled in the installer.
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

function OnDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  Result := True;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), SetupMessage(msgPreparingDesc), @OnDownloadProgress);
end;

// The two MPQs the game cannot boot without: both present = the data is already installed.
function DataPresent: Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\Data\terrain.MPQ')) and
            FileExists(ExpandConstant('{app}\Data\patch.MPQ'));
end;

// The download runs when the user clicks Install, after the folder is chosen, and goes to {tmp}.
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = wpReady) and (not DataPresent) then
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
  Params: String;
begin
  if (CurStep = ssPostInstall) and (not DataPresent) then
  begin
    ExtractTemporaryFile('extract-data.ps1');
    WizardForm.StatusLabel.Caption := 'Extracting the game data (a few minutes)...';
    WizardForm.FilenameLabel.Caption := '';
    WizardForm.ProgressGauge.Style := npbstMarquee;
    try
      Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\extract-data.ps1') +
                '" -Zip "' + ExpandConstant('{tmp}\wow-data.zip') +
                '" -Dest "' + ExpandConstant('{app}') + '"';
      if (not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE,
                   ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
        SuppressibleMsgBox('The game data could not be extracted (exit code ' + IntToStr(ResultCode) +
                           '). The game itself is installed; run this installer again to retry the data.',
                           mbError, MB_OK, IDOK);
    finally
      WizardForm.ProgressGauge.Style := npbstNormal;
    end;
  end;
end;
