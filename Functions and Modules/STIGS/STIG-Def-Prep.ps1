$sourceDirectory = 'C:\util\STIG STUFF\U_SRG-STIG_Library'
$targetDirectory = 'C:\util\stig stuff\xcddf'

# Ensure target directory exists
if (-not (Test-Path -Path $targetDirectory)) {
    New-Item -ItemType Directory -Path $targetDirectory | Out-Null
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

Get-ChildItem -Path $sourceDirectory -Filter *.zip | ForEach-Object {
    $zipPath = $_.FullName
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)

    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -like "*Manual-xccdf.xml") {
            $filePath = Join-Path $targetDirectory $entry.Name
            # Ensure directory for file exists
            if (-not (Test-Path $(Split-Path -Path $filePath))) {
                New-Item -ItemType Directory -Path $(Split-Path -Path $filePath) | Out-Null
            }
            # Extract file
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $filePath, $true)
        }
    }

    $zip.Dispose()
}
# Call the second script after the first one completes
& "C:\util\scripts\multi-stig-extract.ps1"
