# Work-Display
Just displaying a few things I've made. Feel free to look around, try some things out, and make a request if you have something you want made.
# App-Code-Files
Contains the majority of the code/files for a web app called ATO-Matic. It's used for Tracking compute assets and their vulnerabilities.

It has a clean and Intuitive UI and provides some metrics. Covers 21,000+ STIG Rule definitions across 419 unique products.
Designed to be used with PostgreSQL. I may upload the database template at some point.

# Functions and modules/Custom-Active-Directory
Contains some really useful functions for AD Operations. I'll expand it as I come across scenarios I want to make easier or a request is made.

The Copy-AdGroups function copies or adds Active Directory group memberships from one user to another.

Use the -Clone switch to copy memberships exactly, removing any groups from the target user that the source user is not a part of.

Use the -Add switch to add the target user to the groups the source user is part of, while keeping any pre-existing groups.

The -Type parameter allows you to specify which types of groups to copy: DistributionOnly, SecurityOnly, or Both (default).

# Functions and modules/Custom-Hyper-V
Has some functions for getting VM info. Will add more upon request or as I come across scenarios I want to make easier.

The Get-VmInfo function retrieves VM Name, RAM, Cores, HD sizes for one, afew, or all VM's.
# Functions and modules/STIGS
Contains 3 scripts for Extracting all STIG checklists from an archive, Parsing the XML files for required data, and importing it to the database for ATO-Matic.
There are two scripts that Cover ~140 Registry and auditpol checks. Each with their associated CSV data in the CSV folder.

# App-Pkg.ps1
This is a script I made for our DevOps Team. Once we publish App code to the respective folders, this script will package it up, increment the versions, and send it where it needs to go.
I have other scripts for pulling required information from Azure Boards, deploying the code that I can't share.


