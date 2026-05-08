# Work-Display

A collection of some scripts, tools, and projects I have built while working in IT, system administration, DevOps, security compliance, and automation.

Feel free to explore, use anything you find helpful, and reach out if you want something built or improved.

---

## Repository Structure

### ato-matic-v1

Docker-based deployment bundle for **ATO-Matic**, a local web app for working with STIG-based vulnerability data, assets, and POA&M tracking.

This bundle is intended to let someone spin up their own local instance with Docker Compose.

Includes:
- `docker-compose.yml` for the app and PostgreSQL database
- `.env.example` for local configuration
- Seeded PostgreSQL init dump with STIG definitions
- Default admin account for first login
- Unique STIG product list for reference

Default login:
- Username: `ato-admin`
- Email: `Dadmin@ato-matic.com`
- Password: `TemPWD2026!!`

Basic startup:

```powershell
copy .env.example .env
docker compose up -d
```

Then open:

```text
http://localhost:8000
```

Important:
- Change the default admin password after first login.
- Update `.env` secrets before using this for anything beyond local testing.
- The database is initialized the first time the Docker volume is created.

---

### Functions and Modules

Reusable PowerShell functions and modules grouped by platform or use case.

---

#### Custom-Active-Directory

PowerShell functions for simplifying Active Directory operations.

**Copy-AdGroups**
- Copies or adds group memberships from one user to another

Options:
- `-Clone` - exact copy, removes unmatched groups from target
- `-Add` - adds groups without removing existing ones
- `-Type` - `DistributionOnly`, `SecurityOnly`, or `Both`

---

#### Custom-Hyper-V

PowerShell utilities for Hyper-V environments.

**Get-VmInfo**
- Retrieves VM name, RAM, CPU cores, and disk sizes
- Works on one VM, multiple VMs, or all VMs

---

#### STIGS

Scripts for processing STIG checklist data for ATO-Matic.

Includes:
- Extraction of STIG checklists from archives
- XML parsing for required data
- Import into PostgreSQL
- Registry check datasets
- Audit policy check datasets
- Associated CSV files

---

### App-Pkg.ps1

Internal packaging script used in an on-prem development environment.

Functionality:
- Packages application code
- Increments versioning
- Distributes builds to target locations

> Some related deployment scripts, Azure Boards integrations, and pipeline pieces are not included.

---

### Az-Scripts

Azure-focused scripts and automation.

Includes:
- Entra ID and Microsoft Graph automation
- Deployment and identity utilities
- Scripts built around real-world admin scenarios

Example:
- External MFA / EAM bulk assignment script using Microsoft Graph
- Designed to preload authentication methods for users during migration

---

## Purpose of This Repo

This repo is meant to:
- Showcase real-world IT tooling and automation
- Share reusable scripts
- Provide practical solutions to common admin problems
- Document projects I have built while solving operational problems

---

## Requests / Ideas

If you have:
- a repetitive task
- something that should be automated
- a workflow that needs cleanup
- or a problem you think could be scripted

Feel free to reach out or open an issue.
