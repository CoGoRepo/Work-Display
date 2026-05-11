param(
    [string]$SourceDirectory,
    [string]$OutputCsvPath,
    [switch]$SkipImport,
    [switch]$ResetVulnerabilities,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $SourceDirectory) {
    $SourceDirectory = Join-Path $projectRoot '.tmp\stig-xccdf'
}
if (-not $OutputCsvPath) {
    $OutputCsvPath = Join-Path $projectRoot 'data\stig-definitions.csv'
}

if (-not (Test-Path $SourceDirectory)) {
    throw "XCCDF source directory was not found: $SourceDirectory"
}

$outputDirectory = Split-Path $OutputCsvPath
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}
if (Test-Path $OutputCsvPath) {
    Remove-Item -LiteralPath $OutputCsvPath -Force
}

function Get-XccdfText {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$XPath
    )

    $selectedNode = $Node.SelectSingleNode($XPath)
    if ($selectedNode) {
        return $selectedNode.InnerText.Trim()
    }
    return $null
}

$rows = New-Object System.Collections.Generic.List[object]
$xmlFiles = Get-ChildItem -Path $SourceDirectory -Filter '*.xml' -File

foreach ($file in $xmlFiles) {
    [xml]$xml = Get-Content -Path $file.FullName -Raw
    $product = Get-XccdfText -Node $xml -XPath "//*[local-name()='subject']"
    if (-not $product) {
        $product = Get-XccdfText -Node $xml -XPath "/*[local-name()='Benchmark']/*[local-name()='title']"
    }
    if (-not $product) {
        $product = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    }

    foreach ($group in $xml.SelectNodes("//*[local-name()='Group']")) {
        $groupId = $group.id
        foreach ($rule in $group.SelectNodes(".//*[local-name()='Rule']")) {
            $title = Get-XccdfText -Node $rule -XPath "*[local-name()='title']"
            if (-not $title) {
                continue
            }

            $ruleId = $rule.id -replace '_rule$', ''
            $rows.Add([PSCustomObject]@{
                rule_title    = $title
                severity      = $rule.severity
                product       = $product
                group_id      = $groupId
                rule_id       = $ruleId
                check_content = Get-XccdfText -Node $rule -XPath "*[local-name()='check']/*[local-name()='check-content']"
                fix_text      = Get-XccdfText -Node $rule -XPath "*[local-name()='fixtext']"
                rule_version  = Get-XccdfText -Node $rule -XPath "*[local-name()='version']"
            })
        }
    }
}

if ($rows.Count -eq 0) {
    throw "No STIG rules were extracted from $SourceDirectory"
}

$rows | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $($rows.Count) STIG rules to $OutputCsvPath"

if (-not $SkipImport) {
    $importArgs = @{
        CsvFilePath = $OutputCsvPath
    }
    if ($ResetVulnerabilities) {
        $importArgs.ResetVulnerabilities = $true
    }
    if ($Force) {
        $importArgs.Force = $true
    }

    & (Join-Path $PSScriptRoot 'STIG-Import.ps1') @importArgs
}
