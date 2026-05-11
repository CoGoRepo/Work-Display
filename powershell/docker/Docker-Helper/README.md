# Docker Helper

Small PowerShell quality-of-life helpers for Docker and Docker Compose.

## Functions

```powershell
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
```

## Examples

```powershell
d ps
dc up -d
d-f ps | Select-Object Names, State, Status
d-f images | Where-Object Repository -like "*ato*"
```

`d-f` and `dc-f` work with Docker commands that support `--format`.
