# App-Pkg

Legacy/internal PowerShell packaging automation from an on-prem development environment.

This module is preserved as a portfolio example of packaging/versioning automation. Paths have been sanitized and related deployment infrastructure is not included.

## Current Version

- `App-Pkg.psm1` - newer module-style version with `Pkg-Apps`.
- `App-Pkg-legacy.ps1` - older direct-run script kept for comparison/history.

## What It Does

- finds the latest release folder version
- increments minor or patch version
- copies application folders into a new release directory
- carries forward prior SQL folders
- writes version/release files
- compresses the release folder
- updates a simple automation report

## Note

This script was built for a specific internal environment. Treat it as reference material unless you adapt the paths and workflow to your own setup.
