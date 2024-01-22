[CmdletBinding()]
param (
    [Alias('package-name', 'name')]    
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Name of the nuget package. The name should be exactly same as what you would pass to ``dotnet add package``"
    )]
    [string]
    $packageName,

    [Alias('package-version')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Exact version of the package to be installed. If none specified, it will try to install the latest one possible"
    )]
    [string]
    $version,

    
    [Alias('get-help', '?', '-?', '/?', 'menu')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Help menu",
        ParameterSetName = ""
    )]
    [string]
    $help
)

Import-Module ./Import-NuGetPackage.psm1
Import-Module ./Show-HelpMenu.psm1

Show-HelpMenu
$verboseMode = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
$installedPackage = Import-NugetPackage $packageName -Verbose:$verboseMode
$requestedPackage = $installedPackage[$installedPackage.Count - 1];
Write-Output "Installed package $($requestedPackage.Name) version $($requestedPackage.Version)"