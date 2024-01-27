using module ./Import-NugetPackage.Types.psm1
using module ./Helper.psm1
using namespace System.Linq;
using namespace System.Collections.Generic;
using namespace System;
using namespace System.Reflection;
using namespace System.Runtime.CompilerServices;

$helpMenuPath = [System.IO.Path]::Combine($PSScriptRoot, "Show-HelpMenu.psm1");
Import-Module $helpMenuPath

function Import-NuGetPackage {
    [OutputType([ImportNugetPackageOutputBase])]
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
            HelpMessage = "A directory to install the package into. If none specified, it will use the default one of {HOME}/.add_package/{CALLER_PATH_HASH}/{CALLER_CONTENT_HASH}/.nuget/packages/{PACKAGE_NAME}/{PACKAGE_VERSION}"
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

        [Alias('load-into-assembly-context', 'load-into-context')]
        [Parameter(
            Mandatory = $false,
            HelpMessage = 
            "Whether to load the assemblies into the assembly context or not. 
            If none specified, it will load the assemblies into current one via reflection"
        )]
        [switch]
        $LoadIntoAssemblyContext,
        
        [Alias('assembly-context', 'context-name', 'assembly-context-name', 'context')]
        [Parameter(
            Mandatory = $false,
            HelpMessage = "A 'region' for your assemblies if you want to isolate it from your current domain. If none specified, a random one will be assigned"
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

    try {
        if ($Help) {
            Show-HelpMenu
            return
        }

        $global:isVerboseMode = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

        # Get the .NET Framework version used by the PowerShell process
        $global:systemTfmVersion = Get-UnderlyingProcessFramework
        Write-Debug "TFM version used is $systemTfmVersion."

        $global:netFrameworkRegex = [System.Text.RegularExpressions.Regex]::new("^net[0-9]{2,3}$")
        $global:netCoreRegex = [System.Text.RegularExpressions.Regex]::new("^net(?:coreapp)?[0-9]{1,2}\.[0-9]{1,2}$")
        
        $global:isDotFramework = $netFrameworkRegex.Matches($systemTfmVersion).Count -eq 1
        $global:isDotnetCore = $netCoreRegex.Matches($systemTfmVersion).Count -eq 1
    
        if ($isDotFramework -eq $false -and $isDotnetCore -eq $false) {
            throw [System.Exception]::new("Unsupported framework")
        }

        $dependencies = [List[NugetPackage]]::new()
        
        if ($isDotFramework) {
            $netFrameworkModulePath = [System.IO.Path]::Combine($PSScriptRoot, "Get-NugetPackageForDotNetFramework.psm1")
            Import-Module $netFrameworkModulePath
            $dependencies = Get-NugetPackageForDotNetFramework -PackageName $PackageName `
                -Version $Version `
                -NugetSource $NugetSource `
                -TargetFramework $TargetFramework `
                -PackageDirectory $PackageDirectory `
                -PreRelease:$PreRelease `
                -NoHttpCache:$NoHttpCache `
                -Interactive:$Interactive `
                -ConfigFile $ConfigFile `
                -DisableParallelProcessing:$DisableParallelProcessing `
                -Verbosity $Verbosity `
                -AssemblyContextName $AssemblyContextName `
                -LoadIntoAssemblyContext:$LoadIntoAssemblyContext
        }
        else {
            $netCoreModulePath = [System.IO.Path]::Combine($PSScriptRoot, "Get-NugetPackageForDotNetCore.psm1")
            Import-Module $netCoreModulePath
            $dependencies = Get-NugetPackageForDotNetCore -PackageName $PackageName `
                -Version $Version `
                -NugetSource $NugetSource `
                -TargetFramework $TargetFramework `
                -PackageDirectory $PackageDirectory `
                -PreRelease:$PreRelease `
                -NoHttpCache:$NoHttpCache `
                -Interactive:$Interactive `
                -ConfigFile $ConfigFile `
                -DisableParallelProcessing:$DisableParallelProcessing `
                -Verbosity $Verbosity `
                -AssemblyContextName $AssemblyContextName `
                -LoadIntoAssemblyContext:$LoadIntoAssemblyContext
        }

        $dependencies = [List[NugetPackage]] $dependencies

        Write-Progress -Activity "Installing Nuget package $PackageName" -PercentComplete 90

        if ($LoadIntoAssemblyContext) {
            if ($isDotFramework) {
                return [AgnosticNugetPackageOutput]::new($dependencies, $AssemblyContextName)
            }
            else {
                return [DotnetCoreNugetPackageOutput]::new($dependencies, $AssemblyContextName)
            }
        }
        else {
            # Check if the dependencies have a runtime lib
            $flattedDependencies | ForEach-Object {
                if ($_.NativeLibraries.Count -gt 0) {
                    # TODO: Try to implement this
                    throw [System.Exception]::new("Directly loading native libraries is not supported yet. Please use the -LoadIntoAssemblyContext switch, and create the object via reflection")
                }
            }

            $output = [ImportNugetPackageOutputBase]::new($dependencies)
            $output.RegisterAssemblies({ [System.Reflection.Assembly]::LoadFile($args[0]) })
            return $output
        }
    }
    catch {
        Write-Exception $global:Error
    }
    finally {
        Write-Progress -Activity "Installing Nuget package $PackageName" -PercentComplete 100
    }
}


Export-ModuleMember -Function Import-NugetPackage