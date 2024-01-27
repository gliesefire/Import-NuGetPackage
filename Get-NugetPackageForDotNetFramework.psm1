using module ./Helper.psm1
using module ./Import-NugetPackage.Types.psm1

using namespace System.Linq;
using namespace System.Collections.Generic;
using namespace System;
using namespace System.Reflection;
using namespace System.Runtime.Loader;

function Get-NugetPackageForDotNetFramework (
    [string] $PackageName, [string] $Version, [string] $NugetSource, [string] $TargetFramework,
    [string] $PackageDirectory, [bool] $PreRelease, [bool] $NoHttpCache,
    [bool] $Interactive, [string] $ConfigFile, [bool] $DisableParallelProcessing, [string] $Verbosity
) {
    try {
        if ($Help) {
            Show-HelpMenu
            return
        }

        # Get the .NET Framework version used by the PowerShell process
        $global:systemTfmVersion = Get-UnderlyingProcessFramework
        Write-Debug "TFM version used is $systemTfmVersion."

        $global:netFrameworkRegex = [System.Text.RegularExpressions.Regex]::new("^net[0-9]{2,3}$")
        $global:semverRegex = [System.Text.RegularExpressions.Regex]::new("(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?")
        
        $global:isDotFramework = $netFrameworkRegex.Matches($systemTfmVersion).Count -eq 1
    
        if ($isDotFramework -eq $false) {
            throw [System.Exception]::new("Unsupported framework")
        }

        # This is sort of like a bitmap of backward compatible versions of each SDK. For any particular TFM in the below list, all the versions to the "right side" of it are supported by it.
        # Theoritically, .net8.0 supports all the .net versions, whereas netcoreapp1.0 only supports itself, and net standard versions <= 1.6
        $netFrameworkHeirarchy = [List[string]]::new()
        $temp = @(
            "net48", "net472", "net471", "net47", "net462", "net461",
            "netstandard2.0", "netstandard1.6", "netstandard1.5", "netstandard1.4",
            "net46", "netstandard1.3", "net452", "net451", "netstandard1.2", "net45",
            "netstandard1.1", "netstandard1.0", "net40", "net35", "net30", "net20", "net11", "net10"
        )

        foreach ($x in $temp) {
            $netFrameworkHeirarchy.Add($x)
        }

        $callerPackagesPath = New-PackageDirectory($MyInvocation.PSCommandPath)
        if ([string]::IsNullOrWhiteSpace($PackageDirectory)) {
            $PackageDirectory = [System.IO.Path]::Combine($callerPackagesPath, ".nuget", "packages")
            $null = New-Item -Path $PackageDirectory -ItemType Directory -Force
        }
    
        Switch-CurrentDirectory $callerPackagesPath
        $dependencies = [List[NugetPackage]]::new()

        InstallNuget
        Write-Progress -Activity "Installing Nuget package $PackageName" -PercentComplete 30

        $command = Build-NugetCliCommand `
            -PackageName $PackageName `
            -Version $Version `
            -NugetSources $NugetSource `
            -TargetFramework $TargetFramework `
            -PackageDirectory $PackageDirectory `
            -PreRelease $PreRelease `
            -NoCache $NoHttpCache `
            -Interactive $Interactive `
            -ConfigFile $ConfigFile `
            -DisableParallelProcessing $DisableParallelProcessing `
            -Verbosity $Verbosity

        $output = $command | Invoke-Expression
        Write-Progress -Activity "Installing Nuget package $PackageName" -PercentComplete 50
        LogTrace $output

        $childDirs = [System.IO.Directory]::EnumerateDirectories($nugetPackagesPath)
        foreach ($dir in $childDirs) {
            $splits = $dir.Split([System.IO.Path]::DirectorySeparatorChar)
            $packageNameWithVersion = $splits[$splits.Count - 1]
        
            $result = $semverRegex.Matches($packageNameWithVersion)
            if ($result.Count -eq 0) {
                throw [System.Exception]::new("Unable to parse version for $packageNameWithVersion")
            }

            $installedVersion = $result[0].Value
            $packageNameLength = $packageNameWithVersion.Length - $installedVersion.Length - 1
            $packageName = $packageNameWithVersion.Substring(0, $packageNameLength)

            $package = [NugetPackage]::new()
            $package.Name = $packageName
            $package.Version = $installedVersion

            $assemblyBasePath = [System.IO.Path]::Combine($dir, "lib")
            $mostRelevantFramework = Get-MostRelevantFrameworkVersion $assemblyBasePath $([FrameworkDeets]::new($tfmUsed, $netFrameworkHeirarchy, $netFrameworkRegex))
        
            $self.Assemblies = [List[string]]::new()
            if ($null -ne $mostRelevantFramework) {
                LogTrace "$mostRelevantFramework is the most 'closet' framework to current TFM $systemTfmVersion. Loading this version for $PackageName"
                $assemblyDir = [System.IO.Path]::Combine($assemblyBasePath, $mostRelevantFramework)
                $childAssemblies = [System.IO.Directory]::EnumerateFiles($assemblyDir, "*.dll")
    
                foreach ($assembly in $childAssemblies) {
                    $self.Assemblies.Add($assembly.ToString())
                }
            }

            $dependencies.Add($package)
        }
    
        # Move the dependent packages to the top of the list, so that they get loaded first
        # Though this doesn't guarantee that the dependent packages will be loaded first, it's a good enough heuristic
        $requestedPackageIndex = $dependencies.IndexOf({ $_.Name -eq $PackageName })
        $requestedPackage = $dependencies[$requestedPackageIndex]
        $null = $dependencies.RemoveAt($requestedPackage)
        $dependencies.Insert($dependencies.Count - 1, $requestedPackage)

        return $dependencies;
    }
    catch {
        Write-Exception $global:Error
    }
    finally {
        Reset-CurrentDirectory
    }
}

function Build-NugetCliCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $PackageName,

        [Parameter]
        [string]
        $Version,

        [Parameter]
        [string]
        $NugetSources,

        [Parameter]
        [string]
        $TargetFramework,

        [Parameter]
        [string]
        $PackageDirectory,

        [Parameter]
        [bool]
        $PreRelease,

        [Parameter]
        [bool]
        $NoHttpCache,

        [Parameter]
        [bool]
        $Interactive,

        [Parameter]
        [string]
        $ConfigFile,

        [Parameter]
        [bool]
        $DisableParallelProcessing,

        [Parameter]
        [string]
        $Verbosity
    )

    $command = "nuget install $PackageName"

    if ([string]::IsNullOrWhiteSpace($Version) -eq $false) {
        $command = "$command -Version $Version"
    }

    if ([string]::IsNullOrWhiteSpace($NugetSources) -eq $false) {
        $command = "$command -Source $NugetSources"
    }

    if ([string]::IsNullOrWhiteSpace($TargetFramework) -eq $false) {
        $command = "$command -Framework $TargetFramework"
    }

    if ([string]::IsNullOrWhiteSpace($PackageDirectory) -eq $false) {
        $command = "$command -OutputDirectory $PackageDirectory"
    }

    if ($PreRelease) {
        $command = "$command -Prerelease"
    }

    if ($NoHttpCache) {
        $command = "$command -NoHttpCache"
    }

    if ($Interactive) {
        $command = "$command -Interactive"
    }

    if ([string]::IsNullOrWhiteSpace($ConfigFile) -eq $false) {
        $command = "$command -ConfigFile $ConfigFile"
    }

    if ($DisableParallelProcessing) {
        $command = "$command -DisableParallelProcessing"
    }

    if ([string]::IsNullOrWhiteSpace($Verbosity) -eq $false) {
        $command = "$command -Verbosity $Verbosity"
    }

    return $command
}

function InstallNuget {
    $sourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    $targetNugetExe = "$env:UserProfile\nuget.exe"
    
    if (![System.IO.File]::Exists($targetNugetExe)) {
        LogInfo "Downloading Nuget from $sourceNugetExe to $targetNugetExe"
        $output = (Invoke-WebRequest $sourceNugetExe -OutFile $targetNugetExe)
        LogTrace $output
        LogInfo "Download completed"
    }
    else {
        LogInfo "Nuget already exists at $targetNugetExe. Setting alias for it"
    }

    # switch case for possible values of Get-CimInstance -ClassName CIM_OperatingSystem
    # https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem


    $currentOs = (Get-CimInstance -ClassName CIM_OperatingSystem).Caption
    if (!$currentOs.Contains("Microsoft Windows")) {
        throw [System.Exception]::new("Why are you even trying to run this on a non-windows OS?")
    }

    Set-Alias -Name "nuget" -Value "$targetNugetExe" -Scope Global
    LogTrace "Set alias for nuget.exe to $targetNugetExe"
}