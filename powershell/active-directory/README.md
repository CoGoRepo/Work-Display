# Active Directory Helpers

PowerShell helper module for common Active Directory administration tasks.

## Copy-AdGroups

Copies or adds group memberships from one user to another.

Common options:

- `-Clone` - exact copy, removing unmatched groups from the target.
- `-Add` - add groups without removing existing memberships.
- `-Type` - `DistributionOnly`, `SecurityOnly`, or `Both`.

## Files

- `CoGoMods.psm1`
- `CoGoMods.psd1`
