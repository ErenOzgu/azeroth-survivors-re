<#
.SYNOPSIS
  Put the client's .MPQ files under <Dest>\Data, from the game-data zip or from a folder that
  already holds them. Called by the installer (azeroth-survivors.iss), so it is a standalone file.
.PARAMETER Source
  A zip file (its Data/*.MPQ entries are extracted) or the WoW "Data" folder itself (every .MPQ
  under it is copied, keeping sub-folders such as enUS\).
.PARAMETER Dest
  The install folder; the files land in <Dest>\Data.
.NOTES
  Exit code 0 when terrain.MPQ and patch.MPQ are present afterwards, 1 on an error, 2 when the
  source held no such files.
#>
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Dest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $data = Join-Path $Dest 'Data'

    if (Test-Path -LiteralPath $Source -PathType Container) {
        # The WoW Data folder: its MPQs land in <Dest>\Data with the same sub-folder layout.
        $srcRoot = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\', '/')
        $files = Get-ChildItem -LiteralPath $srcRoot -Recurse -File -Filter '*.MPQ'
        foreach ($file in $files) {
            $rel = $file.FullName.Substring($srcRoot.Length).TrimStart('\', '/')
            $target = Join-Path $data $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
    } else {
        # A zip: only Data/*.MPQ, as scripts/fetch-data.sh's unzip pattern does.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $sep = [string][IO.Path]::DirectorySeparatorChar
        $destRoot = [IO.Path]::GetFullPath($Dest).TrimEnd('\', '/') + $sep

        $archive = [IO.Compression.ZipFile]::OpenRead($Source)
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
    }

    if ((Test-Path (Join-Path $data 'terrain.MPQ')) -and (Test-Path (Join-Path $data 'patch.MPQ'))) {
        exit 0
    }
    exit 2
} catch {
    Write-Error $_
    exit 1
}
