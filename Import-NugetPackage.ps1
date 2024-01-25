[CmdletBinding()]
param (
    [Alias('package-name', 'name')]    
    [Parameter(
        Mandatory = $false,
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

    [Alias('load-into-assembly-context', 'load-into-context')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = 
        "Whether to load the assemblies into the assembly context or not. 
        If none specified, it will load the assemblies into current one via reflection
        This setting is overridden if -AssemblyContextName parameter is specified"
    )]
    [switch]
    $LoadIntoAssemblyContext,

    
    [Alias('get-help', '?', '-?', '/?', 'menu')]
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Help menu",
        ParameterSetName = ""
    )]
    [switch]
    $Help
)

$psm1Path = [System.IO.Path]::Combine($PSScriptRoot, "Import-NuGetPackage.psm1");
$helpMenuPath = [System.IO.Path]::Combine($PSScriptRoot, "Show-HelpMenu.psm1");

Import-Module $psm1Path
Import-Module $helpMenuPath

if ($Help) {
    Show-HelpMenu
    return
}

$verboseMode = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
if ($verboseMode) {
    $Verbosity = "detailed"
}

if ([string]::IsNullOrWhiteSpace($PackageName)) {
    $PackageName = Read-Input -prompt "Enter the name of the nuget package to install"
}

$output = Import-NugetPackage -PackageName $PackageName -Version $Version -NugetSource $NugetSource -TargetFramework $TargetFramework -PackageDirectory $PackageDirectory -PreRelease:$PreRelease -NoHttpCache:$NoHttpCache -Interactive:$Interactive -ConfigFile $ConfigFile -DisableParallelProcessing:$DisableParallelProcessing -Verbosity $Verbosity -AssemblyContextName $AssemblyContextName

$requestedPackage = $output.InstalledPackages[$output.InstalledPackages.Count - 1];
Write-Output "Installed package $($requestedPackage.Name) version $($requestedPackage.Version)"