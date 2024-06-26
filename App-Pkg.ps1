param (
    [ValidateSet("AAS", "ACAS-ANALYSIS", "ACAS-ANALYSIS-DOMAIN", "B2ADMINISTRATION", "B2ADMINISTRATION-DOMAIN", "CHADD", "CHADD-DOMAIN", "CITIS", "CITIS-DOMAIN", "INFOSEC", "LMDS", "LMDS-DOMAIN", "OPSEC", "PURCHASETRACKER", "ROOMSCHEDULER","SPIRIT", "TEMS", "USACC")]
    [string]$AppName = "LMDS",
    [string]$ReleaseDir = "\\Hidden-Path-1\$AppName",
    [string]$DevDir = "\\Hidden-Path-2\DEV$\$AppName",
    [ValidateSet("minor", "patch")]
    [string]$VersionIncrementType = "minor"
)

$AppName = $AppName.ToUpper()
$ReleaseDir1 = "\\Hidden-Path-3\Elma-Release-Archive"
$Report = "\Hidden-Path-1\logs\Automation"
$LogFilePath = "$ReleaseDir1\logs\$AppName\$(GET-DATE -F MM-dd-yy).txt"

function Centralized-Log([string]$message) {
    $mutex = New-Object System.Threading.Mutex($false, "LogMutex")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp : $message"

    try {
        $mutex.WaitOne() # Wait for the mutex to be free
        Add-Content -Path $logFilePath -Value $logEntry -Force
    } finally {
        $mutex.ReleaseMutex() # Release the mutex for other threads
    }
}

function Increment-Version([Version]$version, [string]$incrementType) {
    switch ($incrementType) {
        "major" { return [Version]::new($version.Major + 1, 0, 0) }
        "minor" { return [Version]::new($version.Major, $version.Minor + 1, 0) }
        "patch" { return [Version]::new($version.Major, $version.Minor, $version.Build + 1) }
        default { throw "Invalid version increment type" }
    }
}


function Copy-DirectoryInBackground([string]$sourcePath, [string]$destinationPath) {
    while ((Get-Job -State Running).Count -ge 20) {
        Start-Sleep -Seconds 3 # Wait for 3 seconds before checking again
    }

    Start-Job -ScriptBlock {
        param($sourcePath, $destinationPath)
        try {
            Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse
        } catch {
            Centralized-Log "Failed to copy file $($_.Exception.ItemName): $($_.Exception.Message)"
        }
    } -ArgumentList $sourcePath, $destinationPath
}

$startTime = Get-Date

try {
    $Pattern = "$AppName-(\d+\.\d+\.\d+)"
    $LatestVersion = [Version]::new("0.0.0")
    $FolderNames = Get-ChildItem -Path $ReleaseDir -Directory | Where-Object { $_.Name -match $Pattern }

    foreach ($FolderName in $FolderNames) {
        $VersionMatch = [Regex]::Match($FolderName.Name, $Pattern)
        if ($VersionMatch.Success) {
            $Version = [Version]$VersionMatch.Groups[1].Value
            if ($Version -gt $LatestVersion) {
                $LatestVersion = $Version
            }
        }
    }

    $CurrentVersion = $LatestVersion
    $NewVersion = Increment-Version $CurrentVersion $VersionIncrementType
    $NewVersionDir = "$AppName-$($NewVersion.ToString())"
    $NewDir = Join-Path $ReleaseDir $NewVersionDir
    $OldDir = "$ReleaseDir\$AppName-$($CurrentVersion.ToString())"
    $Creation = @($NewDir, "$NewDir\SQL-Prior")

    ForEach ($x in $Creation) {
    mkdir $x
    Centralized-Log "Created directory $x"
    }

    $DevDirCopy = Get-ChildItem -Path "$DevDir"

    foreach ($dir in $DevDirCopy) {
        $sourcePath = $dir.FullName
        $destinationPath = Join-Path "$NewDir" $dir.Name
        Centralized-Log "Started Copy for $($dir.Name)"
        Copy-DirectoryInBackground $sourcePath $destinationPath
    }

    # Wait for all copy jobs to complete
    Get-Job | Wait-Job
    Get-Job | Remove-Job

    if (Test-Path "$ReleaseDir\$AppName-$($CurrentVersion.ToString())\SQL-Prior") {
    $sqlPriorDirs = Get-ChildItem -Path "$ReleaseDir\$AppName-$($CurrentVersion.ToString())\SQL-Prior" -Directory

    foreach ($dir in $sqlPriorDirs) {
        $sourcePath = $dir.FullName
        $destinationPath = Join-Path "$NewDir\SQL-Prior" $dir.Name
        Centralized-Log "Started Copy for $($dir.Name)"
        Copy-DirectoryInBackground $sourcePath $destinationPath
    }
    } Else {Centralized-Log "SQL-Prior did not exist in the previous version. Nothing to copy"}


    # Wait for all copy jobs to complete
    Get-Job | Wait-Job
    Get-Job | Remove-Job

    ###testing this addition.
    if ($DevDir -match "-domain$") {
    $DevDir = $DevDir -replace "-domain$", ""
    }

    if (Test-Path "$($DevDir)-release") {
    gci "$($DevDir)-release" | Copy-Item -Destination $NewDir -Recurse
    }

    if (Test-Path "$newDir\SQL") {
    Rename-Item -Path "$NewDir\SQL" -NewName "$NewDir\SQL-$($NewVersion.Minor)"
    Centralized-Log "Renamed SQL to SQL-$($NewVersion.Minor)"
    }

    "$($NewVersion.ToString()) - $(get-date -Format MM/dd/yy)" > $NewDir\Version.txt
    "$($NewVersion.ToString()) - $(get-date -Format MM/dd/yy)" > $NewDir\content\Version.txt
    Centralized-Log "Created Version.txt in two directories."

    "$AppName Version $($NewVersion.ToString())

$(get-date -format MM/dd/yyyy) Release notes
" > "$NewDir\rel-$($NewVersion.ToString()).txt"
    Get-Content -Path "$NewDir\releasenotes.txt" >> "$NewDir\rel-$($NewVersion.ToString()).txt"

    Remove-Item -Path "$NewDir\releasenotes.txt"
    
    Rename-Item -Path "$NewDir\web.config" -NewName "$NewDir\web.config-dev"
    if (Test-Path "$olddir\sql-$($CurrentVersion.minor)") {
    copy-item -Path $olddir\sql-$($CurrentVersion.minor) -destination $newdir\sql-prior -Recurse
    }
    Start-Sleep -Seconds 3

    Compress-Archive -Path $NewDir -DestinationPath "$NewDir.zip"

    Start-Sleep -Seconds 3

    if ($AppName -like "*domain*" -or $AppName -like "*AAS*" -or $AppName -like "*INFOSEC*" -or $AppName -like "*USACC*" ) {
    Centralized-Log "Copying $Newdir.zip to 2licnet"
    Copy-Item "$NewDir.Zip" -Destination "O:\Hidden-path-4\DTA\Folder\"
    }

    $endTime = Get-Date
    $totalTime = $endTime - $startTime
    Centralized-Log "Script completed in $($totalTime.ToString())"

    # Update Automation Report.
    $data = Import-Csv $Report\Report.csv
    [float]$A = $data[0].EstimatedTime
    [int]$B = $data[0].timesrun
    $B+=1
    $C = $A * $B
    $data[0].timesrun = $B
    $data[0].TotalManHoursSaved = $C
    $data | Export-Csv $Report\Report.csv -NoTypeInformation
} catch {
    Centralized-Log "Error occurred: $_"
}
