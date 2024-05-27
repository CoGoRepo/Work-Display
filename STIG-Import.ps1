# Define database connection details
$database = "Bjorn"
$user = "postgres"
$dbhost = "localhost"
$csvFilePath = "C:\util\DataBase\DB imports\PS-results.csv"

# Set PGCLIENTENCODING environment variable to UTF8
$env:PGCLIENTENCODING = "UTF8"

# Construct the psql command to import CSV data
$importCommand = "\copy vulnerabilities(rule_title, severity, product, group_id, rule_id, check_content, fix_text, rule_version) FROM '$csvFilePath' WITH CSV HEADER;"

# Command to execute psql
$psqlCommand = "psql -U $user -h $dbhost -d $database -c `"$importCommand`""

# Execute the command
Invoke-Expression $psqlCommand

# Optionally, clear the PGCLIENTENCODING environment variable after use
Remove-Item Env:\PGCLIENTENCODING
