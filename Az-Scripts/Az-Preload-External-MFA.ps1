<#
.SYNOPSIS
    Preloads (assigns) an External Authentication Method (EAM) to one or more users in Microsoft Entra ID.

.DESCRIPTION
    This script uses Microsoft Graph v1.0 to assign an External Authentication Method (EAM) to users.
    It is intended for migration scenarios where administrators want to pre-stage MFA methods
    instead of requiring users to self-register.

    For each user, the script:
    - Resolves the user by UserPrincipalName
    - Checks if the external authentication method already exists
    - Assigns the method if missing

    Supports -WhatIf for safe dry-run execution.

.PARAMETER UserPrincipalNames
    One or more User Principal Names (UPNs) to assign the External MFA method to.

.PARAMETER ConfigurationId
    The GUID of the External MFA configuration in Entra ID.
    Tip: Run 'Get-MgPolicyAuthenticationMethodPolicyExternalMethodConfiguration | Select-Object Id, DisplayName' to find this.

.PARAMETER DisplayName
    A friendly name for the External MFA method (e.g., "Duo MFA").

.PARAMETER ConnectGraph
    If specified, the script will prompt to connect to Microsoft Graph.

.PARAMETER OutputCsvPath
    Optional path to export results as a CSV file.

.EXAMPLE
    $Params = @{
        UserPrincipalNames = "alice@contoso.com"
        ConfigurationId    = "11111111-2222-3333-4444-555555555555"
        DisplayName        = "Duo MFA"
        WhatIf             = $true
    }
    .\Az-Preload-External-MFA.ps1 @Params

    Performs a dry run using splatting to show actions without making changes.

.EXAMPLE
    $Params = @{
        UserPrincipalNames = "alice@contoso.com", "bob@contoso.com"
        ConfigurationId    = "11111111-2222-3333-4444-555555555555"
        DisplayName        = "Duo MFA"
        ConnectGraph       = $true
    }
    .\Az-Preload-External-MFA.ps1 @Params

    Connects to Graph and assigns the External MFA method to multiple users.

.EXAMPLE
    $UserList = Import-Csv .\users.csv | Select-Object -ExpandProperty UserPrincipalName
    $Params = @{
        UserPrincipalNames = $UserList
        ConfigurationId    = "11111111-2222-3333-4444-555555555555"
        DisplayName        = "Duo MFA"
    }
    .\Az-Preload-External-MFA.ps1 @Params

    Assigns the External MFA method using a CSV input.

.EXAMPLE
    $Params = @{
        UserPrincipalNames = "alice@contoso.com"
        ConfigurationId    = "11111111-2222-3333-4444-555555555555"
        DisplayName        = "Duo MFA"
        OutputCsvPath      = "C:\util\Logs\MFA_results.csv"
    }
    .\Az-Preload-External-MFA.ps1 @Params

    Registers a user and saves the success/failure status to a CSV file for auditing.

.NOTES
    Requirements:
    - External MFA must already be configured in Entra ID
    - Requires Microsoft Graph permission: UserAuthenticationMethod.ReadWrite.All (delegated)
    - Requires appropriate admin role (e.g., Authentication Administrator)

    Official docs:
    - Manage external MFA in Entra:
      https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-authentication-external-method-manage
    - Create externalAuthenticationMethod:
      https://learn.microsoft.com/en-us/graph/api/authentication-post-externalauthenticationmethods?view=graph-rest-1.0
    - List externalAuthenticationMethod:
      https://learn.microsoft.com/en-us/graph/api/authentication-list-externalauthenticationmethods?view=graph-rest-1.0
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$UserPrincipalNames,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigurationId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName,

    [Parameter()]
    [switch]$ConnectGraph,

    [Parameter()]
    [string]$OutputCsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-MgConnection {
    if ($ConnectGraph) {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All" -NoWelcome
    }

    $ctx = Get-MgContext
    if (-not $ctx) {
        throw "No Microsoft Graph connection found. Use -ConnectGraph or connect manually first."
    }
}

function Get-UserByUpn {
    param([Parameter(Mandatory = $true)][string]$UserPrincipalName)

    $escapedUpn = $UserPrincipalName.Replace("'", "''")
    $uri = "https://graph.microsoft.com/v1.0/users?`$filter=userPrincipalName eq '$escapedUpn'&`$select=id,displayName,userPrincipalName"

    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject
    if (-not $resp.value -or $resp.value.Count -eq 0) {
        return $null
    }

    return $resp.value[0]
}

function Get-ExternalMethodsForUser {
    param([Parameter(Mandatory = $true)][string]$UserId)

    $uri = "https://graph.microsoft.com/v1.0/users/$UserId/authentication/externalAuthenticationMethods"
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject

    if ($null -eq $resp.value) {
        return @()
    }

    return @($resp.value)
}

function Add-ExternalMethodToUser {
    param(
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$ConfigurationId,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $uri = "https://graph.microsoft.com/v1.0/users/$UserId/authentication/externalAuthenticationMethods"

    $body = @{
        "@odata.type"  = "#microsoft.graph.externalAuthenticationMethod"
        configurationId = $ConfigurationId
        displayName     = $DisplayName
    } | ConvertTo-Json -Depth 3

    Invoke-MgGraphRequest `
        -Method POST `
        -Uri $uri `
        -Body $body `
        -ContentType "application/json" `
        -OutputType PSObject
}

Ensure-MgConnection

$results = foreach ($upn in $UserPrincipalNames) {
    $result = [ordered]@{
        UserPrincipalName = $upn
        DisplayName       = $null
        UserId            = $null
        Status            = $null
        Message           = $null
        ExistingMethod    = $false
        MethodId          = $null
        ConfigurationId   = $ConfigurationId
        MethodDisplayName = $DisplayName
    }

    try {
        $user = Get-UserByUpn -UserPrincipalName $upn
        if (-not $user) {
            $result.Status = "NotFound"
            $result.Message = "User not found."
            [pscustomobject]$result
            continue
        }

        $result.DisplayName = $user.displayName
        $result.UserId = $user.id

        $existing = Get-ExternalMethodsForUser -UserId $user.id
        $match = $existing | Where-Object {
            $_.configurationId -eq $ConfigurationId
        } | Select-Object -First 1

        if ($match) {
            $result.ExistingMethod = $true
            $result.MethodId = $match.id
            $result.Status = "AlreadyPresent"
            $result.Message = "External MFA already assigned."
            [pscustomobject]$result
            continue
        }

        $target = "$($user.userPrincipalName) [$($user.id)]"
        if ($PSCmdlet.ShouldProcess($target, "Assign External MFA '$DisplayName'")) {
            $created = Add-ExternalMethodToUser -UserId $user.id -ConfigurationId $ConfigurationId -DisplayName $DisplayName
            $result.Status = "Created"
            $result.Message = "External MFA assigned."
            if ($created -and $created.PSObject.Properties.Name -contains 'id') {
                $result.MethodId = $created.id
            }
        }
        else {
            $result.Status = "WhatIf"
            $result.Message = "Dry run only; no change made."
        }

        [pscustomobject]$result
    }
    catch {
        $result.Status = "Error"
        $result.Message = $_.Exception.Message
        [pscustomobject]$result
    }
}

$results | Format-Table -AutoSize

if ($OutputCsvPath) {
    $results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
}
