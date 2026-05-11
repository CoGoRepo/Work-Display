param(
    [string]$CsvFilePath,
    [string]$Database = $(if ($env:DB_NAME) { $env:DB_NAME } else { 'Bjorn' }),
    [string]$User = $(if ($env:DB_USER) { $env:DB_USER } else { 'postgres' }),
    [string]$DbHost = $(if ($env:DB_HOST) { $env:DB_HOST } else { 'localhost' }),
    [int]$Port = $(if ($env:DB_PORT) { [int]$env:DB_PORT } else { 5432 }),
    [switch]$ResetVulnerabilities,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $CsvFilePath) {
    $CsvFilePath = Join-Path $projectRoot 'data\stig-definitions.csv'
}
if (-not (Test-Path $CsvFilePath)) {
    throw "CSV file was not found: $CsvFilePath"
}

$psql = Get-Command psql -ErrorAction SilentlyContinue
if (-not $psql) {
    throw 'psql was not found on PATH. Install PostgreSQL client tools or add psql to PATH.'
}

if ($env:DB_PASSWORD) {
    $env:PGPASSWORD = $env:DB_PASSWORD
}
$env:PGCLIENTENCODING = 'UTF8'

function Invoke-PsqlScalar {
    param([string]$Sql)

    $result = & psql -h $DbHost -p $Port -U $User -d $Database -t -A -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql command failed: $Sql"
    }
    return ($result | Select-Object -First 1).Trim()
}

try {
    $existingCount = [int](Invoke-PsqlScalar -Sql 'SELECT COUNT(*) FROM vulnerabilities;')
    if ($existingCount -gt 0 -and -not $ResetVulnerabilities -and -not $Force) {
        throw "The vulnerabilities table already has $existingCount rows. Re-run with -ResetVulnerabilities to truncate vulnerabilities with CASCADE, or -Force to append anyway."
    }

    if ($ResetVulnerabilities) {
        Write-Host 'Truncating vulnerabilities with CASCADE before import...'
        & psql -h $DbHost -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -c 'TRUNCATE TABLE vulnerabilities RESTART IDENTITY CASCADE;'
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to truncate vulnerabilities.'
        }
    }

    $copyPath = $CsvFilePath.Replace('\', '/').Replace("'", "''")
    $copyCommand = "\copy vulnerabilities(rule_title, severity, product, group_id, rule_id, check_content, fix_text, rule_version) FROM '$copyPath' WITH CSV HEADER"

    Write-Host "Importing STIG rules from $CsvFilePath..."
    & psql -h $DbHost -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -c $copyCommand
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to import STIG CSV.'
    }

    & psql -h $DbHost -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -c 'SELECT update_av_table();'
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to refresh asset vulnerability links.'
    }

    $newCount = Invoke-PsqlScalar -Sql 'SELECT COUNT(*) FROM vulnerabilities;'
    Write-Host "Vulnerability definitions ready: $newCount rows."
} finally {
    Remove-Item Env:\PGCLIENTENCODING -ErrorAction SilentlyContinue
}
