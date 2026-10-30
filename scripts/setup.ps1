<#
.SYNOPSIS
  Native Windows counterpart of `make native`: fetch the game data, then build and run the
  desktop game. Runs from plain PowerShell - no Git Bash, make or unzip.

.DESCRIPTION
  1. checks the toolchain (cargo, and the MSVC C++ build tools + Windows SDK that rustc links with)
  2. fetches the game data (a WoW 1.12.1 client's Data folder, from archive.org - not committed)
     into wow-data\Data, the same place scripts/fetch-data.sh uses; skipped when already present
  3. builds and runs `warcraft-survivors` with WOW_DATA pointing at that folder

  Re-runnable: each step skips what is already done, and an interrupted download resumes.
  The browser (wasm) build is separate and still goes through the bash scripts.

.PARAMETER NoRun
  Build only; do not launch the game.

.PARAMETER DataUrl
  Direct link to a zip holding the client's Data\*.MPQ files. Defaults to $env:WOW_DATA_URL, then
  the same archive.org item as scripts/fetch-data.sh.

.PARAMETER DataDir
  Where the data lives (the MPQs end up in <DataDir>\Data). Defaults to $env:WOW_DATA_DIR, then
  wow-data\ in the repo.

.PARAMETER SkipToolchainCheck
  Skip the MSVC / Windows SDK detection (e.g. if it misfires on an unusual Visual Studio setup).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoRun,
    [string]$DataUrl = $env:WOW_DATA_URL,
    [string]$DataDir = $env:WOW_DATA_DIR,
    [switch]$SkipToolchainCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $Root

# Same default as scripts/fetch-data.sh; keep the two in step.
$DefaultDataUrl = 'https://archive.org/download/WoW_1.12.1-5875/1.12.1-5875_enUS.zip'
if (-not $DataUrl) { $DataUrl = $DefaultDataUrl }
if (-not $DataDir) { $DataDir = Join-Path $Root 'wow-data' }
$DataPath = Join-Path $DataDir 'Data'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Stop-Setup([string]$Message) {
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

# True when Visual Studio / Build Tools with the C++ x64 tools is installed. rustc's msvc target
# needs its link.exe, found through vswhere rather than PATH.
function Test-MsvcBuildTools {
    $pf86 = ${env:ProgramFiles(x86)}
    if (-not $pf86) { return $false }
    $vswhere = Join-Path $pf86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }
    $found = & $vswhere -latest -products '*' -requires 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' -property installationPath
    return [bool]$found
}

function Test-WindowsSdk {
    $pf86 = ${env:ProgramFiles(x86)}
    if (-not $pf86) { return $false }
    return (Test-Path (Join-Path $pf86 'Windows Kits\10\Lib'))
}

# True when $Path opens as a complete zip. A truncated download has no central directory, so this
# tells a finished zip from a partial one without trusting the file's mere existence.
function Test-ZipComplete([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        $zip.Dispose()
        return $true
    } catch {
        return $false
    }
}

# Extract Data/*.MPQ from the zip into $Destination (the unzip pattern fetch-data.sh uses).
# Returns the number of files written. Entries that would land outside $Destination are refused.
function Expand-MpqEntries([string]$ZipPath, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sep = [string][IO.Path]::DirectorySeparatorChar
    $destRoot = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/') + $sep
    $count = 0
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if ($name -notlike 'Data/*.MPQ') { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $name))
            if (-not $target.StartsWith($destRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "refusing to extract outside ${Destination}: $name"
            }
            New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            $count++
        }
    } finally {
        $zip.Dispose()
    }
    return $count
}

# --- 1. toolchain -----------------------------------------------------------------------------
Write-Step 'Checking prerequisites'

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Stop-Setup 'cargo not found. Install Rust from https://rustup.rs, then open a new PowerShell window.'
}

if (Get-Command rustup -ErrorAction SilentlyContinue) {
    # rust-toolchain.toml pins the channel. Installing it up front is a no-op when it is present.
    & rustup toolchain install
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'rustup could not install the pinned toolchain; cargo will say so if it is missing.'
    }
}

if (-not $SkipToolchainCheck) {
    if (-not (Test-MsvcBuildTools) -or -not (Test-WindowsSdk)) {
        Stop-Setup @'
the MSVC C++ build tools and Windows SDK were not found; rustc needs them to link.
Install "Visual Studio Build Tools" with the "Desktop development with C++" workload:
  https://visualstudio.microsoft.com/visual-cpp-build-tools/
or, for example:
  winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
Then run this script again (or pass -SkipToolchainCheck if you are sure they are installed).
'@
    }
}

$link = Get-Command link.exe -All -ErrorAction SilentlyContinue | Select-Object -First 1
if ($link -and ($link.Source -match '[\\/]usr[\\/]bin[\\/]')) {
    Write-Warning "GNU link.exe from Git ($($link.Source)) comes first on PATH. rustc usually finds MSVC's linker on its own; if the build fails at link time, run this from a PowerShell window that does not have Git's usr\bin on PATH."
}

# --- 2. game data -----------------------------------------------------------------------------
$terrain = Join-Path $DataPath 'terrain.MPQ'
$patch = Join-Path $DataPath 'patch.MPQ'

# The two MPQs the game cannot boot without are the canary: both present = data is in.
if ((Test-Path $terrain) -and (Test-Path $patch)) {
    Write-Step "Game data already present at $DataPath"
} else {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

    try {
        $volume = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($DataDir))
        $freeGb = [math]::Round(([IO.DriveInfo]::new($volume)).AvailableFreeSpace / 1GB, 1)
        if ($freeGb -lt 12) {
            Write-Warning "only $freeGb GB free on $volume; the ~5.5 GB zip plus the extracted MPQs needs roughly 11 GB at peak."
        }
    } catch {
        # A network path or unusual volume: skip the check rather than block the setup.
    }

    $zipPath = Join-Path $DataDir ([IO.Path]::GetFileName(([Uri]$DataUrl).AbsolutePath))

    if ((Test-Path $zipPath) -and (Test-ZipComplete $zipPath)) {
        Write-Step "Using the downloaded $zipPath"
    } else {
        Write-Step 'Downloading the game data (a WoW 1.12.1 client, ~5.5 GB)'
        Write-Host "  $DataUrl"
        # curl.exe, not `curl`: in Windows PowerShell 5.1 `curl` is an alias for Invoke-WebRequest.
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (-not $curl) {
            Stop-Setup 'curl.exe not found (it ships with Windows 10 1803 and later, and Windows 11).'
        }
        # --continue-at - resumes a partial file left by an interrupted run.
        & $curl.Source --fail --location --continue-at - --output $zipPath $DataUrl
        if ($LASTEXITCODE -ne 0) {
            Stop-Setup "download failed (curl exit code $LASTEXITCODE). Run this script again to resume; if it keeps failing, delete $zipPath first."
        }
    }

    Write-Step "Extracting MPQs into $DataPath"
    $n = Expand-MpqEntries $zipPath $DataDir
    Write-Host "  extracted $n file(s)"

    if (-not ((Test-Path $terrain) -and (Test-Path $patch))) {
        Stop-Setup "terrain.MPQ and patch.MPQ were not found under $DataPath after extracting; the zip must hold the client's Data\*.MPQ files (see -DataUrl)."
    }

    # The MPQs are what the game reads; drop the zip to reclaim ~5.5 GB.
    Remove-Item -Force $zipPath
    Write-Step "Game data ready at $DataPath"
}

# --- 3. build and run -------------------------------------------------------------------------
# The client finds its install through $env:WOW_DATA (see `make native`).
$env:WOW_DATA = $DataPath

if ($NoRun) {
    Write-Step 'Building warcraft-survivors (release)'
    & cargo build --release -p warcraft-survivors
} else {
    Write-Step 'Building and launching warcraft-survivors (release; the first build takes a while)'
    & cargo run --release -p warcraft-survivors
}
if ($LASTEXITCODE -ne 0) {
    Stop-Setup "cargo exited with code $LASTEXITCODE"
}
