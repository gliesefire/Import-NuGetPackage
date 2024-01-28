using module ./Helper.psm1
using module ./Import-NugetPackage.Types.psm1

using namespace System.Linq;
using namespace System.Collections.Generic;
using namespace System;
using namespace System.Reflection;
using namespace System.Runtime.Loader;

function Get-NugetPackageForDotNetCore (
    [string] $PackageName, [string] $Version, [string] $NugetSource, [string] $TargetFramework,
    [string] $PackageDirectory, [bool] $PreRelease, [bool] $NoHttpCache,
    [bool] $Interactive, [string] $ConfigFile, [bool] $DisableParallelProcessing, [string] $Verbosity
) {
    try {
        if ($Help) {
            Show-HelpMenu
            return
        }

        $netCoreRegex = [System.Text.RegularExpressions.Regex]::new("^net(?:coreapp)?[0-9]{1,2}\.[0-9]{1,2}$")
        $systemTfmVersion = Get-UnderlyingProcessFramework
        $isDotnetCore = $netCoreRegex.Matches($systemTfmVersion).Count -eq 1
        if ($isDotnetCore -eq $false) {
            throw [System.Exception]::new("Unsupported framework")
        }

        # This is sort of like a bitmap of backward compatible versions of each SDK. For any particular TFM in the below list, all the versions to the "right side" of it are supported by it.
        # Theoritically, .net8.0 supports all the .net versions, whereas netcoreapp1.0 only supports itself, and net standard versions <= 1.6
        $netCoreHeirarchy = [List[string]]::new()
        $temp = @(
            "net8.0", "net7.0", "net6.0", "net5.0", "netcoreapp3.1",
            "netcoreapp3.0", "netstandard2.1", "netcoreapp2.2", "netcoreapp2.0", "netstandard2.0",
            "netcoreapp1.1", "netcoreapp1.0", "netstandard1.6", "netstandard1.5", "netstandard1.4",
            "netstandard1.3", "netstandard1.2", "netstandard1.1", "netstandard1.0"
        )

        foreach ($x in $temp) {
            $netCoreHeirarchy.Add($x)
        }

        $callerPackagesPath = New-PackageDirectory($MyInvocation.PSCommandPath)

        if ([string]::IsNullOrWhiteSpace($PackageDirectory)) {
            $PackageDirectory = Get-DefaultNuGetInstallationDirectory

            # TODO: Install packages to script directory, instead of global packages directory
            # This is a hack, as default reflection context doesn't load assemblies from a custom directory (as it doesn't know about it)
            # $PackageDirectory = [System.IO.Path]::Combine($callerPackagesPath, ".nuget", "packages")
            # $null = New-Item -Path $PackageDirectory -ItemType Directory -Force
        }
        else {
            # if the caller has specified the package directory, then in order to ensure that the packages are created in that directory
            # we need to ignore the global packages directory            
            $NoHttpCache = $true
        }
    
        Switch-CurrentDirectory $callerPackagesPath

        $lockFilePath = [System.IO.Path]::Combine($callerPackagesPath, "packages.lock.json")
        $dirName = $callerPackagesPath.Split([System.IO.Path]::DirectorySeparatorChar)[-1]
        $csprojFilePath = [System.IO.Path]::Combine($callerPackagesPath, "$dirName.csproj")
        if ([System.IO.File]::Exists($csprojFilePath) -eq $false) {
            LogTrace "A project file doesn't exist yet. Creating one"
            $output = dotnet new console

            # Remove unnecessary build files & Program.cs. We only care about packages.lock.json file & csproj file.
            # Rest all of them are auxillary
            Remove-ProjectFolder $callerPackagesPath
        }
    
        Add-PackageLockIfNotExists $csprojFilePath
        LogTrace "Generated lock file for $csprojFilePath"

        Write-Progress -Activity "Installing Nuget package xxx" -PercentComplete 30


        $command = Build-DotnetAddPackageCommand `
            -PackageName $PackageName `
            -Version $Version `
            -NugetSources $NugetSource `
            -TargetFramework $TargetFramework `
            -PackageDirectory $PackageDirectory `
            -PreRelease $PreRelease

        $output = $command | Invoke-Expression
        LogTrace($output)

        Write-Progress -Activity "Installing Nuget package $PackageName" -PercentComplete 50

        $command = Build-DotnetRestoreCommand `
            -Verbosity $Verbosity `
            -ConfigFile $ConfigFile `
            -DisableParallelProcessing $DisableParallelProcessing `
            -NoHttpCache $NoHttpCache `
            -Interactive $Interactive `
            -PackageDirectory $PackageDirectory

        $output = $command | Invoke-Expression
        LogTrace($output)

        $flattedDependencies = [List[NugetPackage]] $(Convert-NugetPackageLockFile $lockFilePath $PackageName $PackageDirectory)

        # When the package that you are restoring exists in the global packages directory
        # it doesn't get restored (or copied) to the local packages directory
        # Hence it's possible, that the package that you are restoring, is not present in the local packages directory
        # Hence perform a build, and do a "fallback" check to see if the package is present in the build output directory
        $buildOutputPath = [System.IO.Path]::Combine($callerPackagesPath, "output") 

        # It is completely feasible to get the list of all assemblies needed for a nuget package from the build output directory
        # But the "problem", is that it doesn't give you the dependency tree. 
        # Also when it comes to native runtimes, they are not .NET dlls either. They are just "native" files, like .so, .dylib, .dll, etc.
        # Hence it's necesary to use the package.lock.json file to get the dependency tree, and then load the assemblies from the build output directory
        $output = (dotnet build --configuration release --no-restore -o $buildOutputPath)
        LogTrace($output)

        foreach ($package in $flattedDependencies) {
            if ($package.Assemblies.Count -gt 0) {
                continue
            }

            $lookingFor = [System.IO.Path]::Combine($buildOutputPath, "$($package.Name).dll")
            if ([System.IO.File]::Exists($lookingFor)) {
                $package.Assemblies.Add($lookingFor)
            }
        }

        return $flattedDependencies
    }
    catch {
        Write-Exception $global:Error
    }
    finally {
        Reset-CurrentDirectory
    }
}

function Build-DotnetRestoreCommand {
    param (
        [string]
        $Verbosity,

        [string]
        $ConfigFile,

        [bool]
        $DisableParallelProcessing,

        [bool]
        $NoHttpCache,

        [bool]
        $Interactive,

        [string]
        $PackageDirectory
    )

    $command = "dotnet restore"

    if ([string]::IsNullOrWhiteSpace($Verbosity) -eq $false) {
        $command = "$command --verbosity $Verbosity"
    }
    else {
        $command = "$command --verbosity normal"
    }

    if ([string]::IsNullOrWhiteSpace($ConfigFile) -eq $false) {
        $command = "$command --configfile ""$ConfigFile"""
    }

    if ($DisableParallelProcessing) {
        $command = "$command --disable-parallel"
    }

    if ($NoHttpCache) {
        $command = "$command --no-cache"
    }

    if ($Interactive) {
        $command = "$command --interactive"
    }

    if ([string]::IsNullOrWhiteSpace($PackageDirectory) -eq $false) {
        $command = "$command --packages ""$PackageDirectory"""
    }

    return $command
}

function Get-NearestRID {
    param (
        [string]
        $rid,

        [string]
        $libPath
    )

    $packageSupportedRidPaths = [System.IO.Directory]::EnumerateDirectories($libPath)
    $packageSupportedRids = $packageSupportedRidPaths | ForEach-Object { $_.Split([System.IO.Path]::DirectorySeparatorChar)[-1] }
    $runtimeGraphJsonPath = [System.IO.Path]::Combine($PSScriptRoot, "runtime.json")
    $runtimeGraphJsonContents = [System.IO.File]::ReadAllText($runtimeGraphJsonPath)
    $ridGraph = [System.Text.Json.JsonSerializer]::Deserialize($runtimeGraphJsonContents, [RidGraph])
    $runtimes = [Dictionary[string, RidImport]] $($ridGraph.runtimes)

    $ridFallbacks = [List[string]]::new()
    $importStack = [Stack[string]]::new()
    do {
        $currentRid = $null
        if ($runtimes.TryGetValue($rid, [ref]$currentRid) -eq $false) {
            throw [System.Exception]::new("Unable to find RID $rid in runtime graph")
        }

        $ridFallbacks.Add($rid)
        for ($i = 0; $i -lt $currentRid.imports.Count; $i++) {
            $importStack.Push($currentRid.imports[$i])
        }

        if ($importStack.Count -eq 0) {
            break
        }

        $rid = $importStack.Pop()
    } while ($true);

    # Check for intersection between the package supported RID's and the RID fallbacks
    $nearestRid = $null
    foreach ($rid in $ridFallbacks) {
        if ($packageSupportedRids.Contains($rid)) {
            $nearestRid = $rid
            break
        }
    }

    if ($null -eq $nearestRid -and $ridFallbacks.Count -gt 0 -and $ridFallbacks.Contains("any")) {
        $firstRid = $packageSupportedRids[0]
        LogWarning "No ""supported"" RID found for $rid. Falling back to 'any' RID. i.e. the first supported RID $firstRid"
        $nearestRid = $firstRid
    }

    return $nearestRid
}

function Build-DotnetAddPackageCommand {
    param (
        [Parameter()]
        [string]
        $PackageName,

        [Parameter()]
        [string]
        $Version,

        [Parameter()]
        [string[]]
        $NugetSources,

        [Parameter()]
        [string]
        $TargetFramework,

        [Parameter()]
        [string]
        $PackageDirectory,

        [Parameter()]
        [bool]
        $PreRelease
    )

    $command = "dotnet add package $PackageName --no-restore"

    if ([string]::IsNullOrWhiteSpace($Version) -eq $false) {
        $command = "$command --version ""$Version"""
    }

    foreach ($source in $NugetSources) {
        if ([string]::IsNullOrWhiteSpace($source) -eq $false) {
            $command = "$command --source ""$source"""
        }
    }

    if ([string]::IsNullOrWhiteSpace($TargetFramework) -eq $false) {
        $command = "$command --framework $TargetFramework"
    }

    if ([string]::IsNullOrWhiteSpace($PackageDirectory) -eq $false) {
        $command = "$command --package-directory ""$PackageDirectory"""
    }

    if ($PreRelease -and $([string]::IsNullOrWhiteSpace($Version) -eq $true)) {
        $command = "$command --prerelease"
    }

    return $command
}


function Convert-NugetPackageLockFile {
    param (
        [string]
        $PackageLockFilePath,

        [string]
        $PackageName,

        [string]
        $PackageDirectory
    )

    if ([System.IO.File]::Exists($PackageLockFilePath) -eq $false) {
        throw [System.Exception]::new("Lock file $PackageLockFilePath doesn't exist")
    }

    if ([System.IO.Directory]::Exists($PackageDirectory) -eq $false) {
        throw [System.Exception]::new("Package directory $PackageDirectory doesn't exist")
    }

    $jsonContents = [System.IO.File]::ReadAllText($PackageLockFilePath)
    $packageLock = $null
    try {
        $packageLock = [NugetPackageLock] $([System.Text.Json.JsonSerializer]::Deserialize($jsonContents, [NugetPackageLock]));
        LogTrace "Parsed lock file $PackageLockFilePath. Version: $($packageLock.version) Dependencies : $($packageLock.dependencies.Keys.Count)"
    }
    catch {
        throw [System.Exception]::new("Unable to parse lock file $PackageLockFilePath. Error: $_")
    }

    Write-Progress -Activity "Installing Nuget package $PackageName" -PercentComplete 60
    $packageDeets = Get-PackageDeets $packageLock $PackageName $PackageDirectory
    Write-Progress -Activity "Installing Nuget package $PackageName" -PercentComplete 80
    $flattedDependencies = Convert-FromNestedListToFlatList $packageDeets
    return $flattedDependencies
}

function Convert-FromNestedListToFlatList {
    [OutputType([List[NugetPackage]])]
    param (
        [NugetPackage]
        $package
    )
    
    $flattenedList = [List[NugetPackage]]::new()
    $stack = [Stack[NugetPackage]]::new()

    # Push the root node onto the stack
    $stack.Push($package);

    while ($stack.Count -gt 0) {
        $currentNode = [NugetPackage]$stack.Pop();
        $flattenedList.Add($currentNode);

        # Push child nodes onto the stack in reverse order (to traverse from the bottom up)
        $currentNode.Dependants.Reverse()
        foreach ($child in $currentNode.Dependants) {
            $stack.Push($child);
        }
    }

    $flattenedList.Reverse()
    return $flattenedList;
}

function Get-DefaultNuGetInstallationDirectory() {
    # Run the "dotnet nuget locals" command to get the global packages directory
    $nugetGlobalPackagesDir = (dotnet nuget locals global-packages --list | Select-String -Pattern "global-packages: ").ToString().TrimStart("global-packages: ")
    return $nugetGlobalPackagesDir
}

function Get-PackageDeets {
    [OutputType([NugetPackage])]
    param (
        [NugetPackageLock]
        $PackageJson,

        [string]
        $PackageName,

        [string]
        $NugetInstallationDir,

        [List[string]] # to prevent endless / useless loops
        $TraversedPackagesList = $null
    )

    if ($null -eq $TraversedPackagesList) {
        $TraversedPackagesList = [List[string]]::new()
    }

    LogTrace "Retrieving package details for $PackageName"
    $tfmsUsed = $PackageJson.dependencies.Keys
    if ($tfmsUsed.Count -gt 1) {
        # TODO: Support multiple TFM's (is this even possible?)
        throw [System.Exception]::new("Multiple TFM's found. This is not supported yet")
    }

    # A hacky way to get the first element from a Dictionary. Somehow .Keys.First() doesn't work
    $tfmUsed = $null
    foreach ($tfm in $tfmsUsed) {
        $tfmUsed = $tfm
        break;
    }

    $package = $PackageJson.dependencies[$tfmUsed][$PackageName]
    $package = [ResolvedNugetPackage] $package
    $self = [NugetPackage]::new()
    $self.Name = $PackageName
    $self.Version = $package.resolved

    $childDependencies = [List[NugetPackage]]::new()
    if ($package.dependencies) {
        foreach ($dependentPackageName in $package.dependencies.Keys) {
            LogTrace "$PackageName is dependant on $dependentPackageName. Parsing it too."
            if ($TraversedPackagesList.Contains($dependentPackageName)) {
                continue
            }
            $details = Get-PackageDeets $PackageJson $dependentPackageName $NugetInstallationDir $TraversedPackagesList
            $childDependencies.Add($details)
        }
    }

    $self.Dependants = $childDependencies
    $packageBasePath = [System.IO.Path]::Combine($NugetInstallationDir, $self.Name.ToLower(), $self.Version)
    $managedLibrariesBasePath = [System.IO.Path]::Combine($NugetInstallationDir, $self.Name.ToLower(), $self.Version, "lib")
    $netCoreRegex = [System.Text.RegularExpressions.Regex]::new("^net(?:coreapp)?[0-9]{1,2}\.[0-9]{1,2}$")
    $mostRelevantFramework = Get-MostRelevantFrameworkVersion $managedLibrariesBasePath $([FrameworkDeets]::new($tfmUsed, $netCoreHeirarchy, $netCoreRegex))

    $self.Assemblies = [List[string]]::new()
    $self.NativeLibraries = [List[string]]::new()

    if ($null -ne $mostRelevantFramework) {
        LogTrace "$mostRelevantFramework is the most 'closet' framework to current TFM $systemTfmVersion. Loading this version for $PackageName"
        $assemblyDir = [System.IO.Path]::Combine($managedLibrariesBasePath, $mostRelevantFramework)
        $childAssemblies = [System.IO.Directory]::EnumerateFiles($assemblyDir, "*.dll")

        foreach ($assembly in $childAssemblies) {
            $self.Assemblies.Add($assembly.ToString())
        }
    }

    if ($self.Assemblies.Count -eq 0) {
        LogTrace "No managed libraries found for $PackageName. Checking for native runtimes"
        $rid = [string] $(Get-RuntimeIdentifier)

        if ($rid -eq "Unknown") {
            throw [System.Exception]::new("Unable to determine runtime identifier")
        }
    
        if ($rid.StartsWith("browser")) {
            # TODO: Support browser based runtimes
            throw [System.Exception]::new("Unable to load browser based runtimes")
        }

        $supportedRidsBasePath = [System.IO.Path]::Combine($packageBasePath, "runtimes")
        if ([System.IO.Directory]::Exists($supportedRidsBasePath) -eq $true) {
            $nearestRid = Get-NearestRID $rid $supportedRidsBasePath
            if ($null -eq $nearestRid) {
                throw [System.Exception]::new("This nuget package doesn't support the current runtime identifier $rid")
            }

            $nativeRuntimePath = [System.IO.Path]::Combine($supportedRidsBasePath, $nearestRid, "native")
            LogTrace "Found native runtimes for $PackageName"
            $nativeRuntimes = [System.IO.Directory]::EnumerateFiles($nativeRuntimePath, "*.*")

            foreach ($nativeRuntime in $nativeRuntimes) {
                $self.NativeLibraries.Add($nativeRuntime.ToString())
            }
        }
        else {
            LogTrace "No native runtimes found for $PackageName"
        }
    }

    if ($self.Assemblies.Count -eq 0 -and $self.NativeLibraries.Count -eq 0) {
        LogTrace "No libraries (managed or un-managed) found for $PackageName, for TFM $systemTfmVersion.
        It's either a meta package, or it's a package which is part of the build process rather than a runtime dependency, or it's already part of the GAC."
    }
    
    LogTrace "Parsed $PackageName. $([System.Environment]::NewLine)Name: $PackageName $([System.Environment]::NewLine)Version: $($package.resolved) $([System.Environment]::NewLine)Dependants: $($childDependencies.Count) $([System.Environment]::NewLine)Assemblies: $($childAssemblies.Count)"
    $TraversedPackagesList.Add($PackageName)
    return $self
}

function Remove-ProjectFolder([string] $path) {
    Push-Location $path
    $null = dotnet clean

    $binFolder = [System.IO.Path]::Combine($path, "bin")
    $objFolder = [System.IO.Path]::Combine($path, "obj")

    if ([System.IO.Directory]::Exists($binFolder)) {
        $null = (Remove-Item -Path $binFolder -Recurse -Force)
    }

    if ([System.IO.Directory]::Exists($objFolder)) {
        $null = (Remove-Item -Path $objFolder -Recurse -Force)
    }
}

function Add-PackageLockIfNotExists([string] $csprojPath) {
    # Load the .csproj file as XML
    $csprojXml = New-Object System.Xml.XmlDocument
    $null = $csprojXml.Load($csprojPath)

    # Check if the RestorePackagesWithLockFile element already exists
    $propertyGroup = $csprojXml.SelectSingleNode("//Project/PropertyGroup[RestorePackagesWithLockFile]")
    if ($null -eq $propertyGroup) {
        # If not, create and add the element
        $newProperty = $csprojXml.CreateElement("RestorePackagesWithLockFile")
        $newProperty.InnerText = "true"
        $null = $csprojXml.DocumentElement.Item("PropertyGroup").AppendChild($newProperty)
    
        # Save the changes back to the .csproj file
        $null = $csprojXml.Save($csprojPath)
    }
}