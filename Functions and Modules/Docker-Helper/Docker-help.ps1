<#
Docker helper aliases/functions for PowerShell.

Purpose:
- Shorten common Docker commands.
- Make Docker list-style output easier to work with as PowerShell objects.

Examples:
  d ps
  d images
  dc up -d
  dc down

  d-f ps | Select-Object Names, State, Status
  d-f images | Where-Object Repository -like "*ato*"
  dc-f ps | Select-Object Name, State, Service

Notes:
- d-f and dc-f append Docker's JSON formatter:
    --format "{{json .}}"
- These work best with Docker commands that support --format, such as ps/images.
- Commands that do not support --format will fail normally.
#>

Set-Alias d docker

function dc {
    docker compose @args
}

function d-f {
    docker @args --format "{{json .}}" | ConvertFrom-Json
}

function dc-f {
    docker compose @args --format "{{json .}}" | ConvertFrom-Json
}
