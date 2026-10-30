<#
.SYNOPSIS
  Tests for extract-data.ps1. Run in CI on a Windows runner; it calls the helper through Windows
  PowerShell 5.1 with the same quoting the installer uses, and paths that contain a space.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$extractScript = Join-Path $PSScriptRoot 'extract-data.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ('asv-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$failures = 0

function Assert([bool]$Condition, [string]$Message) {
    if ($Condition) {
        Write-Host "ok   $Message"
    } else {
        Write-Host "FAIL $Message" -ForegroundColor Red
        $script:failures++
    }
}

# A zip whose entries hold a few bytes each, under exactly the names given.
function New-TestZip([string]$Path, [string[]]$Names) {
    $zip = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try {
        foreach ($name in $Names) {
            $entry = $zip.CreateEntry($name)
            $stream = $entry.Open()
            try {
                $bytes = [Text.Encoding]::ASCII.GetBytes("test $name")
                $stream.Write($bytes, 0, $bytes.Length)
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $zip.Dispose()
    }
}

# Runs the helper as the installer does and returns its exit code.
function Invoke-Extract([string]$Source, [string]$Dest) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Source "{1}" -Dest "{2}"' -f $extractScript, $Source, $Dest
    $p = Start-Process -FilePath $ps -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    return $p.ExitCode
}

try {
    # 1. a zip: Data/*.MPQ comes out, anything else stays in
    $zip1 = Join-Path $work 'game data.zip'
    New-TestZip $zip1 @('Data/terrain.MPQ', 'Data/patch.MPQ', 'Data/enUS/base-enUS.MPQ', 'readme.txt', 'Data/notes.txt')
    $dest1 = Join-Path $work 'Install Dir 1'
    Assert ((Invoke-Extract $zip1 $dest1) -eq 0) 'zip: exit code 0'
    Assert (Test-Path (Join-Path $dest1 'Data\terrain.MPQ')) 'zip: terrain.MPQ extracted'
    Assert (Test-Path (Join-Path $dest1 'Data\enUS\base-enUS.MPQ')) 'zip: locale MPQ extracted under Data\enUS'
    Assert (-not (Test-Path (Join-Path $dest1 'readme.txt'))) 'zip: a non-Data file is not extracted'
    Assert (-not (Test-Path (Join-Path $dest1 'Data\notes.txt'))) 'zip: a non-MPQ file is not extracted'

    # 2. a folder: the MPQs are copied with their sub-folders, other files are not
    $src2 = Join-Path $work 'My WoW Data'
    New-Item -ItemType Directory -Path (Join-Path $src2 'enUS') | Out-Null
    foreach ($f in @('terrain.MPQ', 'patch.MPQ', 'enUS\locale-enUS.MPQ', 'wow.exe')) {
        Set-Content -Path (Join-Path $src2 $f) -Value "test $f"
    }
    $dest2 = Join-Path $work 'Install Dir 2'
    Assert ((Invoke-Extract $src2 $dest2) -eq 0) 'folder: exit code 0'
    Assert (Test-Path (Join-Path $dest2 'Data\patch.MPQ')) 'folder: patch.MPQ copied'
    Assert (Test-Path (Join-Path $dest2 'Data\enUS\locale-enUS.MPQ')) 'folder: locale MPQ copied under Data\enUS'
    Assert (-not (Test-Path (Join-Path $dest2 'Data\wow.exe'))) 'folder: a non-MPQ file is not copied'

    # 3. a zip without the two canary MPQs: exit code 2
    $zip3 = Join-Path $work 'wrong.zip'
    New-TestZip $zip3 @('Data/other.MPQ', 'readme.txt')
    Assert ((Invoke-Extract $zip3 (Join-Path $work 'Install Dir 3')) -eq 2) 'a zip without terrain.MPQ and patch.MPQ: exit code 2'

    # 4. an entry that climbs out of the install folder is refused
    $zip4 = Join-Path $work 'evil.zip'
    New-TestZip $zip4 @('Data/terrain.MPQ', 'Data/patch.MPQ', 'Data/../../evil.MPQ')
    Assert ((Invoke-Extract $zip4 (Join-Path $work 'Install Dir 4')) -eq 1) 'zip-slip entry: exit code 1'
    Assert (-not (Test-Path (Join-Path $work 'evil.MPQ'))) 'zip-slip entry: nothing written outside the install folder'

    # 5. a source that does not exist: exit code 1
    Assert ((Invoke-Extract (Join-Path $work 'nope.zip') (Join-Path $work 'Install Dir 5')) -eq 1) 'missing source: exit code 1'
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Host "$failures check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'all checks passed'
