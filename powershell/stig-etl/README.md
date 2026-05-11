# STIG ETL

Support scripts used to prepare STIG definition data for ATO-Matic.

This folder is less of a general STIG scanner and more of an ETL/support pipeline:

```text
STIG archives/checklists
        -> extract
        -> parse/normalize
        -> import into PostgreSQL
        -> generate master checklist data
```

## Scripts

- `STIG-Def-Prep.ps1` - top-level prep workflow.
- `STIG-Extract.ps1` - extracts STIG/checklist content.
- `STIG-Import.ps1` - imports normalized data into PostgreSQL.
- `New-MasterChecklist.ps1` - creates a master checklist dataset.

## Data

- `data/auditpol.csv`
- `data/reg-checks.csv`
- `data/Extracted-Sample-Data.csv`

## Legacy Checks

The `legacy-checks` folder contains older registry and audit policy check scripts from a previous checklist workflow. They are preserved as examples of mapping technical checks back to STIG rule IDs.
