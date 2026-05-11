param(
    [string]$ArchivePath,
    [string]$SourceDirectory,
    [string]$XccdfDirectory,
    [string]$OutputCsvPath,
    [switch]$SkipImport,
    [switch]$ResetVulnerabilities,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $XccdfDirectory) {
    $XccdfDirectory = Join-Path $projectRoot '.tmp\stig-xccdf'
}
if (-not $OutputCsvPath) {
    $OutputCsvPath = Join-Path $projectRoot 'data\stig-definitions.csv'
}
if (-not $ArchivePath -and -not $SourceDirectory) {
    $ArchivePath = Join-Path $projectRoot 'data\U_SRG-STIG_Library.zip'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-CleanDirectory {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path | Out-Null
}

function Get-SafeFileName {
    param([string]$Name)

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safeName = $Name
    foreach ($char in $invalidChars) {
        $safeName = $safeName.Replace($char, '_')
    }
    return $safeName
}

function Expand-XccdfFromZip {
    param(
        [string]$ZipPath,
        [string]$TargetDirectory
    )

    $zipBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ZipPath)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -like '*Manual-xccdf.xml') {
                $targetName = Get-SafeFileName "$zipBaseName-$($entry.Name)"
                $targetPath = Join-Path $TargetDirectory $targetName
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            }
        }
    } finally {
        $zip.Dispose()
    }
}

function Expand-NestedStigLibrary {
    param(
        [string]$LibraryArchivePath,
        [string]$TargetDirectory
    )

    $nestedZipDirectory = Join-Path $TargetDirectory '_nested-zips'
    New-Item -ItemType Directory -Path $nestedZipDirectory | Out-Null

    $libraryZip = [System.IO.Compression.ZipFile]::OpenRead($LibraryArchivePath)
    try {
        foreach ($entry in $libraryZip.Entries) {
            if ($entry.FullName -like '*.zip') {
                $nestedName = Get-SafeFileName $entry.Name
                $nestedPath = Join-Path $nestedZipDirectory $nestedName
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $nestedPath, $true)
                Expand-XccdfFromZip -ZipPath $nestedPath -TargetDirectory $TargetDirectory
            } elseif ($entry.FullName -like '*Manual-xccdf.xml') {
                $libraryBaseName = [System.IO.Path]::GetFileNameWithoutExtension($LibraryArchivePath)
                $targetName = Get-SafeFileName "$libraryBaseName-$($entry.Name)"
                $targetPath = Join-Path $TargetDirectory $targetName
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            }
        }
    } finally {
        $libraryZip.Dispose()
    }
}

New-CleanDirectory -Path $XccdfDirectory

if ($ArchivePath) {
    if (-not (Test-Path $ArchivePath)) {
        throw "STIG archive was not found: $ArchivePath"
    }
    Expand-NestedStigLibrary -LibraryArchivePath $ArchivePath -TargetDirectory $XccdfDirectory
}

if ($SourceDirectory) {
    if (-not (Test-Path $SourceDirectory)) {
        throw "STIG source directory was not found: $SourceDirectory"
    }
    Get-ChildItem -Path $SourceDirectory -Filter '*.zip' | ForEach-Object {
        Expand-XccdfFromZip -ZipPath $_.FullName -TargetDirectory $XccdfDirectory
    }
}

$xccdfCount = (Get-ChildItem -Path $XccdfDirectory -Filter '*.xml' -File).Count
if ($xccdfCount -eq 0) {
    throw "No Manual-xccdf.xml files were extracted to $XccdfDirectory"
}

Write-Host "Extracted $xccdfCount XCCDF files to $XccdfDirectory"

$extractArgs = @{
    SourceDirectory = $XccdfDirectory
    OutputCsvPath = $OutputCsvPath
}
if ($SkipImport) {
    $extractArgs.SkipImport = $true
}
if ($ResetVulnerabilities) {
    $extractArgs.ResetVulnerabilities = $true
}
if ($Force) {
    $extractArgs.Force = $true
}

& (Join-Path $PSScriptRoot 'STIG-Extract.ps1') @extractArgs
