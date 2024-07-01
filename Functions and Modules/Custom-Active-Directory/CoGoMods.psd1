@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'CoGoMods.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'd6e88f3c-8c2b-4c5c-b0e2-1c2c5a5b8d54'

    # Author of this module
    Author = 'Cody Gore'

    # Company or vendor of this module
    CompanyName = 'Your Company'

    # Copyright statement for this module
    Copyright = '(c) 2024 Cody Gore. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Custom PowerShell Module by Cody Gore'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @('Copy-AdGroups', 'Centralized-Log', 'Centralized-Log2', 'Copy-DirectoryInBackground')

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # List of all files packaged with this module
    FileList = @('CoGoMods.psm1')

    # Private data to pass to the module
    PrivateData = @{}

    # Scripts to run when importing the module
    ScriptsToProcess = @()

    # Type files to load when importing the module
    TypesToProcess = @()

    # Format files to load when importing the module
    FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules = @()
}
