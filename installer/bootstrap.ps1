#Requires -Version 5.1
<#
  Azeroth Survivors - Windows bootstrap.

  Installs what the game needs to build on Windows, clones the source, builds the native
  launcher and records where the user's own WoW 1.12.1 Data folder is.

  It does NOT download or bundle any Blizzard game data. The user supplies their own client.

  Run by AzerothSurvivors.iss, or by hand:
    powershell -ExecutionPolicy Bypass -File bootstrap.ps1 -InstallDir C:\AzerothSurvivors -WowData D:\WoW\Data
#>
param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][string]$WowData,
    [string]$RepoUrl = 'https://github.com/ErenOzgu/azeroth-survivors-re',
    [string]$Ref = 'main'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$RepoDir = Join-Path $InstallDir 'repo'
$TmpDir = Join-Path $env:TEMP 'azeroth-survivors-setup'
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
Start-Transcript -Path (Join-Path $InstallDir 'install.log') -Append | Out-Null

function Step([string]$Message) {
    Write-Host ''
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

# Pick up PATH changes made by installers that ran in this same session.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    $env:Path = "$machine;$user;$cargoBin"
}

function Invoke-Native([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$File $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-File([string]$Url, [string]$Dest) {
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -Headers @{ 'User-Agent' = 'azeroth-survivors-installer' }
}

# --- 1. MSVC Build Tools + Windows SDK (the linker the Rust MSVC target needs) -------------------
function Test-BuildTools {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }
    $vc = & $vswhere -products '*' -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vc) { return $false }
    $sdkLibs = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Lib'
    if (-not (Test-Path $sdkLibs)) { return $false }
    $kernel32 = Get-ChildItem -Path $sdkLibs -Recurse -Filter 'kernel32.lib' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\um\\x64\\' } | Select-Object -First 1
    return [bool]$kernel32
}

function Install-BuildTools {
    if (Test-BuildTools) {
        Write-Host 'MSVC Build Tools and Windows SDK already present.'
        return
    }
    $exe = Join-Path $TmpDir 'vs_BuildTools.exe'
    Get-File 'https://aka.ms/vs/17/release/vs_BuildTools.exe' $exe
    Write-Host 'Installing Visual Studio Build Tools 2022 (C++ tools + Windows SDK). This takes a while and asks for administrator approval.'
    $vsArgs = @(
        '--passive', '--norestart', '--wait',
        '--add', 'Microsoft.VisualStudio.Workload.VCTools',
        '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.22621',
        '--includeRecommended'
    )
    $p = Start-Process -FilePath $exe -ArgumentList $vsArgs -Verb RunAs -Wait -PassThru
    # 0 = ok, 3010 = ok but a reboot is recommended.
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "Visual Studio Build Tools installer exited with code $($p.ExitCode)"
    }
    if (-not (Test-BuildTools)) {
        throw 'Build Tools installed but the MSVC linker or Windows SDK was not detected. A reboot may be needed.'
    }
}

# --- 2. Git ----------------------------------------------------------------------------------------
function Install-Git {
    Update-SessionPath
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host 'Git already present.'
        return
    }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' `
        -Headers @{ 'User-Agent' = 'azeroth-survivors-installer' }
    $asset = $release.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw 'Could not find the Git for Windows 64-bit installer.' }
    $exe = Join-Path $TmpDir $asset.name
    Get-File $asset.browser_download_url $exe
    Write-Host 'Installing Git for Windows (administrator approval required).'
    $p = Start-Process -FilePath $exe -ArgumentList '/VERYSILENT', '/NORESTART', '/SP-' -Verb RunAs -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Git installer exited with code $($p.ExitCode)" }
    Update-SessionPath
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git was installed but is not on PATH.' }
}

# --- 3. Rust ---------------------------------------------------------------------------------------
function Install-Rust {
    Update-SessionPath
    if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
        $exe = Join-Path $TmpDir 'rustup-init.exe'
        Get-File 'https://win.rustup.rs/x86_64' $exe
        Write-Host 'Installing rustup.'
        Invoke-Native $exe @('-y', '--default-toolchain', 'none', '--profile', 'minimal')
        Update-SessionPath
    } else {
        Write-Host 'rustup already present.'
    }
    # Install the exact toolchain the repo pins, so the build does not depend on rustup's auto-install behaviour.
    $toolchainFile = Join-Path $RepoDir 'rust-toolchain.toml'
    $channel = $null
    if (Test-Path $toolchainFile) {
        $m = [regex]::Match((Get-Content $toolchainFile -Raw), 'channel\s*=\s*"([^"]+)"')
        if ($m.Success) { $channel = $m.Groups[1].Value }
    }
    if (-not $channel) { $channel = 'stable' }
    Write-Host "Installing Rust toolchain: $channel"
    Invoke-Native 'rustup' @('toolchain', 'install', $channel, '--profile', 'minimal')
}

# --- 4. Source -------------------------------------------------------------------------------------
function Get-Source {
    if (Test-Path (Join-Path $RepoDir '.git')) {
        Write-Host 'Updating existing source checkout.'
        Invoke-Native 'git' @('-C', $RepoDir, 'fetch', 'origin', $Ref)
        Invoke-Native 'git' @('-C', $RepoDir, 'checkout', '--force', 'FETCH_HEAD')
    } else {
        Write-Host "Cloning $RepoUrl ($Ref)"
        Invoke-Native 'git' @('clone', '--branch', $Ref, $RepoUrl, $RepoDir)
    }
}

# --- 5. Build --------------------------------------------------------------------------------------
function Build-Game {
    Write-Host 'Building the game. The first build is slow; leave this window open.'
    Push-Location $RepoDir
    try {
        Invoke-Native 'cargo' @('build', '--release', '-p', 'warcraft-survivors')
    } finally {
        Pop-Location
    }
    $exe = Join-Path $RepoDir 'target\release\warcraft-survivors.exe'
    if (-not (Test-Path $exe)) { throw "Build finished but $exe was not produced." }
}

# --- 6. Record the user's own game data location ---------------------------------------------------
function Write-Config {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $InstallDir 'wow-data-path.txt'), $WowData, $utf8NoBom)
}

try {
    if (-not (Test-Path (Join-Path $WowData 'terrain.MPQ')) -or -not (Test-Path (Join-Path $WowData 'patch.MPQ'))) {
        throw "WoW Data folder looks wrong (terrain.MPQ / patch.MPQ not found): $WowData"
    }

    Step '1/5  Visual Studio Build Tools'
    Install-BuildTools

    Step '2/5  Git'
    Install-Git

    Step '3/5  Game source'
    Get-Source

    Step '4/5  Rust toolchain'
    Install-Rust

    Step '5/5  Building the game'
    Build-Game
    Write-Config

    Write-Host ''
    Write-Host 'Done. Start the game from the Start Menu or desktop shortcut.' -ForegroundColor Green
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Host ''
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Log: $(Join-Path $InstallDir 'install.log')"
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
