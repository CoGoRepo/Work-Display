#requires -Version 5.1
<#
POC: Preload Microsoft Entra External MFA onto users

Requirements:
- External MFA already configured in Entra
- Valid configurationId for that External MFA configuration
- Delegated Graph permission: UserAuthMethod-External.ReadWrite
  (or higher, if your org prefers broader admin-granted scopes)
- Work/school account, not personal Microsoft account

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
        Connect-MgGraph -Scopes "UserAuthMethod-External.ReadWrite" -NoWelcome
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