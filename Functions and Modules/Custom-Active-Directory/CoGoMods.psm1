function Copy-AdGroups {
    <#
    .SYNOPSIS
    Copies or adds Active Directory group memberships from one user to another.

    .DESCRIPTION
    The Copy-AdGroups function copies or adds Active Directory group memberships from one user to another.
    Use the -Clone switch to copy memberships exactly, removing any groups from the target user that the source user is not a part of.
    Use the -Add switch to add the target user to the groups the source user is part of, while keeping any pre-existing groups.
    The -Type parameter allows you to specify which types of groups to copy: DistributionOnly, SecurityOnly, or Both (default).

    .PARAMETER Source
    The source user whose group memberships will be copied.

    .PARAMETER Target
    The target user who will be added to the groups.

    .PARAMETER Clone
    Switch to copy memberships exactly, removing any groups from the target user that the source user is not a part of.

    .PARAMETER Add
    Switch to add the target user to the groups the source user is part of, while keeping any pre-existing groups.

    .PARAMETER Type
    Specify which types of groups to copy: DistributionOnly, SecurityOnly, or Both. Default is Both.

    .PARAMETER LogFilePath
    The path to the log file where actions will be recorded. Default is "C:\Logs\GroupCopy.log".

    .EXAMPLE
    Copy-AdGroups -Source "User1" -Target "User2" -Clone
    This command clones the group memberships from User1 to User2, removing any groups from User2 that User1 is not a part of, for both distribution and security groups.

    .EXAMPLE
    Copy-AdGroups -Source "User1" -Target "User2" -Add -Type SecurityOnly
    This command adds User2 to any security groups that User1 is a part of, without removing any pre-existing groups from User2.

    .EXAMPLE
    Copy-AdGroups -Source "User1" -Target "User2" -Clone -Type SecurityOnly
    This command clones the security group memberships from User1 to User2, removing any security groups from User2 that User1 is not a part of, while keeping distribution groups.

    .EXAMPLE
    $list = @("User3", "User4", "User5")
    Foreach ($user in $list) {
        Copy-AdGroups -Source "User1" -Target $user -Add -Type DistributionOnly
    }
    This example adds multiple users (User3, User4, User5) to the distribution groups that User1 is part of.

    .EXAMPLE
    $list | ForEach-Object {
        Copy-AdGroups -Source "User1" -Target $_ -Add
    }
    This example demonstrates using the function in a pipeline to add multiple users to the groups (both security and distribution) that User1 is part of.

    .NOTES
    Author: Cody Gore
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Source,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Target,

        [Parameter()]
        [ValidateSet("DistributionOnly", "SecurityOnly", "Both")]
        [string]$Type = "Both",

        [Parameter(Mandatory=$true, ParameterSetName="Clone")]
        [switch]$Clone,

        [Parameter(Mandatory=$true, ParameterSetName="Add")]
        [switch]$Add,

        [Parameter()]
        [string]$LogFilePath = "C:\Logs\GroupCopy.log"
    )

    process {
        try {
            # Ensure log directory exists
            $logDirectory = Split-Path $LogFilePath
            if (-not (Test-Path -Path $logDirectory)) {
                New-Item -Path $logDirectory -ItemType Directory -Force
            }

            # Set the script scope variable for the log file path
            $script:logFilePath = $LogFilePath

            # Get the groups for the Source user
            $sourceGroups = Get-ADUser -Identity $Source -Property MemberOf | Select-Object -ExpandProperty MemberOf

            # Filter source groups based on type
            if ($Type -eq "DistributionOnly") {
                $sourceGroups = $sourceGroups | Where-Object {
                    (Get-ADGroup -Identity $_).GroupCategory -eq 'Distribution'
                }
            } elseif ($Type -eq "SecurityOnly") {
                $sourceGroups = $sourceGroups | Where-Object {
                    (Get-ADGroup -Identity $_).GroupCategory -eq 'Security'
                }
            }

            # Get the groups for the Target user
            $targetGroups = Get-ADUser -Identity $Target -Property MemberOf | Select-Object -ExpandProperty MemberOf

            # Filter target groups based on type
            if ($Type -eq "DistributionOnly") {
                $targetGroups = $targetGroups | Where-Object {
                    (Get-ADGroup -Identity $_).GroupCategory -eq 'Distribution'
                }
            } elseif ($Type -eq "SecurityOnly") {
                $targetGroups = $targetGroups | Where-Object {
                    (Get-ADGroup -Identity $_).GroupCategory -eq 'Security'
                }
            }

            if ($Clone) {
                # Determine groups to remove and add
                $groupsToRemove = $targetGroups | Where-Object { $_ -notin $sourceGroups }
                $groupsToAdd = $sourceGroups | Where-Object { $_ -notin $targetGroups }

                # Remove Target from groups
                if ($groupsToRemove.Count -gt 0) {
                    Remove-ADGroupMember -Identity $groupsToRemove -Members $Target -Confirm:$false -ErrorAction Stop
                    Centralized-Log "Removed $Target from groups: $($groupsToRemove -join ', ')"
                }

                # Add Target to groups
                if ($groupsToAdd.Count -gt 0) {
                    Add-ADGroupMember -Identity $groupsToAdd -Members $Target -ErrorAction Stop
                    Centralized-Log "Added $Target to groups: $($groupsToAdd -join ', ')"
                }
            }

            if ($Add) {
                # Determine groups to add
                $groupsToAdd = $sourceGroups | Where-Object { $_ -notin $targetGroups }

                # Add Target to groups
                if ($groupsToAdd.Count -gt 0) {
                    Add-ADGroupMember -Identity $groupsToAdd -Members $Target -ErrorAction Stop
                    Centralized-Log "Added $Target to groups: $($groupsToAdd -join ', ')"
                }
            }

        } catch {
            Centralized-Log "An error occurred: $_"
            Write-Error "An error occurred: $_"
        }
    }
}

function Centralized-Log {
    param (
        [string]$message
    )

    $mutex = New-Object System.Threading.Mutex($false, "LogMutex")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp : $message"

    try {
        $mutex.WaitOne() # Wait for the mutex to be free
        Add-Content -Path $script:logFilePath -Value $logEntry -Force
    } finally {
        $mutex.ReleaseMutex() # Release the mutex for other threads
    }

    if ($VerbosePreference -eq "Continue") {
        Write-Verbose $message
    }
}




function Centralized-Log2([string]$message) {
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