# Work-Display

A collection of scripts, tools, and projects I’ve built while working in IT (system administration, DevOps, and automation).

Feel free to explore, use anything you find helpful, and reach out if you want something built or improved.

---

## 📂 Repository Structure

### 🔹 App-Code-Files (ATO-Matic)
Contains the majority of the code for **ATO-Matic**, a web app designed for tracking compute assets and their vulnerabilities.

**Key features:**
- Clean, intuitive UI
- Tracks assets and vulnerability data
- Covers **21,000+ STIG rule definitions** across **419+ products**
- Designed to use a **PostgreSQL backend**

> ⚠️ Database template may be added later

---

### 🔹 Functions and Modules

#### 🧠 Custom-Active-Directory
PowerShell functions for simplifying AD operations.

**Copy-AdGroups**
- Copies or adds group memberships from one user to another

Options:
- `-Clone` → Exact copy (removes unmatched groups from target)
- `-Add` → Adds groups without removing existing ones
- `-Type` → `DistributionOnly`, `SecurityOnly`, or `Both` (default)

---

#### 🖥️ Custom-Hyper-V
PowerShell utilities for Hyper-V environments.

**Get-VmInfo**
- Retrieves:
  - VM Name
  - RAM
  - CPU cores
  - Disk sizes
- Works on one, multiple, or all VMs

---

#### 🔐 STIGS
Scripts for processing STIG checklist data for ATO-Matic.

Includes:
- Extraction of STIG checklists from archives
- XML parsing for required data
- Import into PostgreSQL database

Also includes:
- ~140 registry checks
- ~140 auditpol checks
- Associated CSV datasets

---

### 🔹 App-Pkg.ps1
Internal packaging script used in an on-prem Dev environment.

**Functionality:**
- Packages application code
- Increments versioning
- Distributes builds to target locations

> ⚠️ Some related deployment scripts (Azure Boards, pipelines, etc.) are not included

---

### 🔹 Az-Scripts
Azure-focused scripts and automation.

Includes:
- Entra ID / Graph API automation
- Deployment and identity utilities
- Scripts built around real-world admin scenarios

**Example:**
- External MFA (EAM) bulk assignment script using Microsoft Graph  
  → Designed to preload authentication methods for users during migration

---

## 🧠 Purpose of This Repo

This repo is meant to:
- Showcase real-world IT tooling and automation
- Share reusable scripts
- Provide practical solutions to common admin problems

---

## 📬 Requests / Ideas

If you have:
- a repetitive task
- something that should be automated
- or a problem you think could be scripted

Feel free to reach out or open an issue.
