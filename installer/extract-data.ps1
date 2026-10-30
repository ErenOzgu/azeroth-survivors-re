<#
.SYNOPSIS
  Extract the client's Data\*.MPQ files from the downloaded zip into <Dest>\Data. Called by the
  installer (azeroth-survivors.iss); the same extraction scripts/setup.ps1 does, as its own file
  because the installer carries it standalone.
.NOTES
  Exit code 0 when terrain.MPQ and patch.MPQ are present afterwards, 1 on an error, 2 when the zip
  held no such files.
#>
param(
    [Parameter(Mandatory)][string]$Zip,
    [Parameter(Mandatory)][string]$Dest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sep = [string][IO.Path]::DirectorySeparatorChar
    $destRoot = [IO.Path]::GetFullPath($Dest).TrimEnd('\', '/') + $sep

    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if ($name -notlike 'Data/*.MPQ') { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Dest $name))
            # The zip is downloaded content: refuse an entry that would land outside $Dest.
            if (-not $target.StartsWith($destRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "refusing to extract outside ${Dest}: $name"
            }
            New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    } finally {
        $archive.Dispose()
    }

    $data = Join-Path $Dest 'Data'
    if ((Test-Path (Join-Path $data 'terrain.MPQ')) -and (Test-Path (Join-Path $data 'patch.MPQ'))) {
        exit 0
    }
    exit 2
} catch {
    Write-Error $_
    exit 1
}
