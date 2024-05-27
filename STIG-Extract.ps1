# Define source and output paths
$sourceDirectory = 'C:\util\stig stuff\xcddf'
$outputFilePath = 'C:\util\DataBase\DB imports\PS-Results.csv'

# Ensure the output directory exists
$outputDirectory = Split-Path $outputFilePath
if (-not (Test-Path -Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

function Sanitize-ForCSV($text) {
    # Escape double quotes by doubling them for CSV format
    $escapedText = $text -replace '"', '""'
    # Return the text with escaped quotes without altering line breaks
    return $escapedText
}

# Loop through each XML file in the source directory
Get-ChildItem -Path $sourceDirectory -Filter *.xml | ForEach-Object {
    $file_path = $_.FullName
    $xml = [xml](Get-Content -Path $file_path)

    # Initialize namespace manager for XML parsing
    $nsManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsManager.AddNamespace('xccdf', 'http://checklists.nist.gov/xccdf/1.1')
    $nsManager.AddNamespace('dc', 'http://purl.org/dc/elements/1.1/')
    $product_info = $xml.SelectSingleNode('//dc:subject', $nsManager).InnerText
    # Extract and process data from XML
    $data = @()
    foreach ($group in $xml.SelectNodes('//xccdf:Group', $nsManager)) {
    $group_id = $group.id
    
    foreach ($rule in $group.SelectNodes('.//xccdf:Rule', $nsManager)) {
        $version = if ($rule.SelectSingleNode('xccdf:version', $nsManager)) { $rule.SelectSingleNode('xccdf:version', $nsManager).InnerText } else { 'N/A' }

        # Correctly accessing check-content using the xccdf namespace
        $checkContentNode = $rule.SelectSingleNode('xccdf:check/xccdf:check-content', $nsManager)
        $check_content = if ($checkContentNode) { Sanitize-ForCSV $checkContentNode.InnerText } else { 'N/A' }
        # Access to fixtext remains unchanged, applying sanitization
        $fixTextNode = $rule.SelectSingleNode('xccdf:fixtext', $nsManager)
        $fix_text = if ($fixTextNode) { Sanitize-ForCSV $fixTextNode.InnerText } else { 'N/A' }

        $obj = [PSCustomObject]@{
            rule_title    = $rule.SelectSingleNode('xccdf:title', $nsManager).InnerText
            severity      = $rule.severity
            product       = $product_info
            group_id      = $group_id
            rule_id       = $rule.id -replace '_rule$'
            check_content = $check_content
            fix_text      = $fix_text
            rule_version  = $version
        }
        $data += $obj
    }
}

    # Append data to CSV, checking if file exists to include headers only once
    if (Test-Path -Path $outputFilePath) {
        $data | Export-Csv -Path $outputFilePath -NoTypeInformation -Encoding UTF8 -Append
    } else {
        $data | Export-Csv -Path $outputFilePath -NoTypeInformation -Encoding UTF8
    }
}

Write-Host "Data appended to $outputFilePath"
& "C:\util\scripts\import-csv-to-db.ps1"
