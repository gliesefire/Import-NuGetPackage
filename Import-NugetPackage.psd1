#
# Module manifest for module 'Import-NugetPackage'
#
# Generated by: gliesefire
#
# Generated on: 2025-02-19
#

@{

    # Version number of this module.
    ModuleVersion          = '1.1.1'

    # Supported PSEditions
    CompatiblePSEditions   = @(
        'PowershellCore',
        'Desktop'
    )

    # ID used to uniquely identify this module
    GUID                   = 'a6d701d1-ee92-411e-ba9f-4e547d50b95c'

    # Author of this module
    Author                 = 'gliesefire'

    # Copyright statement for this module
    Copyright              = 'MIT License'

    # Description of the functionality provided by this module
    Description            = 'A better version of Import-Package, that can import any package from a nuget package source, and load the assemblies into the current AppDomain.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion      = '2.0'

    # Minimum version of the PowerShell host required by this module
    PowerShellHostVersion  = '2.0'

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    DotNetFrameworkVersion = '4.5.2'

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport      = @(
        'Import-NugetPackage'
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData            = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags                     = @('nuget', 'import-package', 'load-assemblies')

            # A URL to the license for this module.
            LicenseUri               = 'https://github.com/gliesefire/Import-NuGetPackage/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri               = 'https://github.com/gliesefire/Import-NuGetPackage'

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            RequireLicenseAcceptance = $false
        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    # HelpInfoURI = ''
}