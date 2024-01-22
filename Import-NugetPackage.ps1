[CmdletBinding()]
param (
    [Alias('package-name', 'name')]    
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Name of the nuget package."
    )]
    [string]
    $PackageName,

    [Alias('package-version')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Exact version of the package to be installed. If none specified, it will try to install the latest one possible"
    )]
    [string]
    $Version,

    [Alias('source', 'nuget-source')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "A nuget package source to use. If none specified, it will use the default one"
    )]
    [string]
    $NugetSource,

    [Alias('framework', 'tfm', 'target-framework')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Target framework moniker. If none specified, it will use the default one (any)"
    )]
    [string]
    $TargetFramework,

    [Alias('package-directory', 'package-dir', 'dir')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "A directory to install the package into. If none specified, it will use the default one of {HOME}/.add_package/{CALLER_SCRIPT_PATH_HASH}/{CALLER_SCRIPT_CONTENT_HASH}/.nuget/packages/{PACKAGE_NAME}/{PACKAGE_VERSION}"
    )]
    [string]
    $PackageDirectory,

    [Alias('pre-release')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Whether to install a pre-release version of the package. If none specified, it will use the default one (false)"
    )]
    [Switch]
    $PreRelease,

    [Alias('no-cache', 'no-http-cache')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Whether to use the cached version of the package. If none specified, it will use the default one (false)"
    )]
    [Switch]
    $NoHttpCache,

    [Alias('i')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Whether to prompt for user input or not. If none specified, it will use the default one (false)"
    )]
    [Switch]
    $Interactive,

    [Alias('config-file', 'config', 'c')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "A nuget config file to use. If none specified, it will use the default one"
    )]
    [string]
    $ConfigFile,

    [Alias('disable-parallel', 'disable-parallel-processing')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Whether to disable parallel processing or not. If none specified, it will use the default one (false)"
    )]
    [Switch]
    $DisableParallelProcessing,

    [Parameter(
        Mandatory = $false,
        HelpMessage = "Verbosity level. If none specified, it will use the default one (normal)"
    )]
    [string]
    $Verbosity,

    [Alias('assembly-context', 'context-name', 'assembly-context-name', 'context')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "An assembly load context for the assemblies to load. Think of it as 'region' for your assemblies. If none specified, a random one will be assigned"
    )]
    [string]
    $AssemblyContextName,

    
    [Alias('get-help', '?', '-?', '/?', 'menu')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Help menu",
        ParameterSetName = ""
    )]
    [switch]
    $Help
)

Import-Module ./Import-NuGetPackage.psm1
Import-Module ./Show-HelpMenu.psm1

Show-HelpMenu

$helpAliases = @('help', 'get-help', '?', '-?', '/?', 'menu')
if ($helpAliases.Contains($PSBoundParameters.Keys[0])) {
    return
}

$verboseMode = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
if ($verboseMode) {
    $Verbosity = "detailed"
}

$output = Import-NugetPackage -PackageName $PackageName -Version $Version -NugetSource $NugetSource -TargetFramework $TargetFramework -PackageDirectory $PackageDirectory -PreRelease:$PreRelease -NoHttpCache:$NoHttpCache -Interactive:$Interactive -ConfigFile $ConfigFile -DisableParallelProcessing:$DisableParallelProcessing -Verbosity $Verbosity -AssemblyContextName $AssemblyContextName

$requestedPackage = $output.InstalledPackages[$output.InstalledPackages.Count - 1];
Write-Output "Installed package $($requestedPackage.Name) version $($requestedPackage.Version)"