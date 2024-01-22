using namespace System.Linq;
using namespace System.Collections.Generic;

Import-Module ./Show-HelpMenu.psm1

function Import-NuGetPackage {
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

        [Alias('assembly-context', 'context-name', 'assembly-context-name', 'context')]
        [Parameter(
            Mandatory = $false,
            HelpMessage = "An assembly load context for the assemblies to load. Think of it as 'region' for your assemblies. If none specified, a random one will be assigned"
        )]
        [string]
        $assemblyContextName,

        
        [Alias('get-help', '?', '-?', '/?', 'menu')]
        [Parameter(
            Mandatory = $false,
            HelpMessage = "Help menu",
            ParameterSetName = ""
        )]
        [string]
        $help
    )

    $assemblyContext = $null
    try {
        if ($null -eq $assemblyContextName -or $assemblyContextName -eq '') {
            $assemblyContextName = [System.Guid]::NewGuid().ToString("N")
        }

        $assemblyContext = [System.Runtime.Loader.AssemblyLoadContext]::new($assemblyContextName, $true);
        $global:isVerboseMode = $false
        if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
            $global:isVerboseMode = $true
        }
        
        # Get the .NET Framework version used by the PowerShell process
        $global:systemTfmVersion = Get-UnderlyingProcessFramework
        Write-Debug "TFM version used is $systemTfmVersion."

        $global:netFrameworkRegex = [System.Text.RegularExpressions.Regex]::new("^net[0-9]{2,3}$")
        $global:netCoreRegex = [System.Text.RegularExpressions.Regex]::new("^net(?:coreapp)?[0-9]{1,2}\.[0-9]{1,2}$")
        $global:csprojFrameworkRegex = [System.Text.RegularExpressions.Regex]::new("\s+<TargetFramework>([^<]+.)")
        $global:semverRegex = [System.Text.RegularExpressions.Regex]::new("(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?")
        
        
        $global:isDotFramework = $netFrameworkRegex.Matches($systemTfmVersion).Count -eq 1
        $global:isDotnetCore = $netCoreRegex.Matches($systemTfmVersion).Count -eq 1
    
        if ($isDotFramework -eq $false -and $isDotnetCore -eq $false) {
            throw [System.Exception]::new("Unsupported framework")
        }

        if ($isDotFramework) {
            $global:msBuildPath = Get-MsBuildPath
        }

        $global:nugetInstallationDir = Get-NuGetInstallationDirectory

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

        if ($PSVersionTable.PSEdition -ne 'Core') {
            [System.Console]::WriteLine("You are running Powershell version $($PSVersionTable.PSVersion)")
            [System.Console]::WriteLine("It's recommmended to install Powershell core (or Powershell 6 or later.)")
            [System.Console]::WriteLine("You can download it here https://github.com/PowerShell/PowerShell/releases")
        }

        $homeDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    
        $callerScriptName = $MyInvocation.PSCommandPath
        LogTrace "Invoked by $callerScriptName. Generating a Hash for it"
        $hash = Get-MD5Hash $callerScriptName
        LogTrace "$hash will be used to refer to $callerScriptName"

        $scriptContents = [System.IO.File]::ReadAllText($callerScriptName)
        $scriptHash = Get-MD5Hash $scriptContents
    
        LogTrace "$scriptHash has been generated for $callerScriptName as form of tracking it's contents"

        # We use the script file's contents to determine, whether to add packages on top of existing ones, or to do a "clean" install
        # This is to factor all the cases where-in you might have changed sdks, upgraded / downgraded versiosns, added / removed packages etc.
        $basePath = [System.IO.Path]::Combine($homeDir, ".add_package", $hash)
        $callerPackagesPath = [System.IO.Path]::Combine($homeDir, ".add_package", $hash, $scriptHash)

        $created = [System.IO.Directory]::CreateDirectory($callerPackagesPath)

        if ($created) {
            LogTrace "Cache directory {HOME}/.add_package/$hash/$scriptHash doesn't exist yet. Created."
        }

        DeleteAllFoldersExcept $basePath $callerPackagesPath
        LogTrace "Deleted all previous versions of {HOME}/.add_package/$hash"

        Switch-CurrentDirectory $callerPackagesPath
        $dependencies = [System.Collections.Generic.List[NugetPackage]]::new()
        if ($isDotFramework) {
            Write-Progress -Activity "Installing Nuget package $packageName" -PercentComplete 30
            $nugetPackagesPath = [System.IO.Path]::Combine($callerPackagesPath, ".nuget", "packages")
            if ([string]::IsNullOrWhiteSpace($version)) {
                $output = (nuget install $packageName -OutputDirectory $nugetPackagesPath)
            }
            else {
                $output = (nuget install $packageName -Version $version -OutputDirectory $nugetPackagesPath)
            }
            Write-Progress -Activity "Installing Nuget package $packageName" -PercentComplete 50
            LogTrace $output

            $childDirs = [System.IO.Directory]::EnumerateDirectories($nugetPackagesPath)
            foreach ($dir in $childDirs) {
                $splits = $dir.Split([System.IO.Path]::DirectorySeparatorChar)
                $packageNameWithVersion = $splits[$splits.Count - 1]
                
                $matches = $semverRegex.Matches($packageNameWithVersion)
                if ($matches.Count -eq 0) {
                    throw [System.Exception]::new("Unable to parse version for $packageNameWithVersion")
                }

                $version = $matches[0].Value
                $packageNameLength = $packageNameWithVersion.Length - $version.Length - 1
                $packageName = $packageNameWithVersion.Substring(0, $packageNameLength)

                $package = [NugetPackage]::new()
                $package.Name = $packageName
                $package.Version = $version

                $assemblyBasePath = [System.IO.Path]::Combine($dir, "lib")
                $mostRelevantFramework = Get-MostRelevantFrameworkVersion $assemblyBasePath
                
                $self.Assemblies = [System.Collections.Generic.List[string]]::new()
                if ($null -ne $mostRelevantFramework) {
                    LogTrace "$mostRelevantFramework is the most 'closet' framework to current TFM $systemTfmVersion. Loading this version for $packageName"
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
            $requestedPackageIndex = $dependencies.IndexOf({ $_.Name -eq $packageName })
            $requestedPackage = $dependencies[$requestedPackageIndex]
            $removed = $dependencies.RemoveAt($requestedPackage)
            $dependencies.Insert($dependencies.Count - 1, $requestedPackage)
        }
        else {                    
            $lockFilePath = [System.IO.Path]::Combine($callerPackagesPath, "packages.lock.json")
            $csprojFilePath = [System.IO.Path]::Combine($callerPackagesPath, "$scriptHash.csproj")
            if ([System.IO.File]::Exists($csprojFilePath) -eq $false) {
                LogTrace "A project file doesn't exist yet. Creating one"
                $output = (dotnet new console)

                # Remove unnecessary build files & Program.cs. We only care about packages.lock.json file & csproj file.
                # Rest all of them are auxillary
                Remove-ProjectFolder $callerPackagesPath
            }
    
            Add-PackageLockIfNotExists $csprojFilePath
            LogTrace "Generated lock file for $csprojFilePath"

            Write-Progress -Activity "Installing Nuget package $packageName" -PercentComplete 30

            if ([string]::IsNullOrWhiteSpace($version)) {
                $output = (dotnet add package $packageName)
            }
            else {
                $output = (dotnet add package $packageName --version $version)
            }
            Write-Progress -Activity "Installing Nuget package $packageName" -PercentComplete 50

            $flattedDependencies = Convert-NugetPackageLockFile $lockFilePath
            $buildOutputPath = [System.IO.Path]::Combine($callerPackagesPath, "output")
            $output = (dotnet build --configuration release --no-restore -o $buildOutputPath)
            LogTrace($output)
        
            foreach ($package in $flattedDependencies) {
                for ($i = 0; $i -lt $package.Assemblies.Count; $i++) {
                    $assemblyName = [System.IO.Path]::GetFileName($package.Assemblies[$i])
                    $package.Assemblies[$i] = [System.IO.Path]::Combine($buildOutputPath, $assemblyName)
                }
            }

            $dependencies = $flattedDependencies
        }
        
        Register-Assemblies $dependencies
        Write-Progress -Activity "Installing Nuget package $packageName" -PercentComplete 90

        $output = [ImportNugetPackageOutput]::new()
        $output.InstalledPackages = $dependencies
        $output.AssemblyLoadContext = $assemblyContext
        Write-Progress -Activity "Installing Nuget package $packageName" -PercentComplete 100
        return $output
    }
    catch {
        Write-Exception $global:Error
        
        if ($null -ne $assemblyContext) {
            try {
                $assemblyContext.Unload()
            }
            catch {

            }
        }
        return $null
    }
    finally {
        Reset-CurrentDirectory
    }
}

function InstallMsBuildLocator {
    InstallNuget
    $locatorPath = "$env:UserProfile\.nuget\packages\microsoft.build.locator\1.6.10\lib\net46\Microsoft.Build.Locator.dll"

    if (![System.IO.File]::Exists($locatorPath)) {
        $output = (nuget install Microsoft.Build.Locator -Version 1.6.10 -OutputDirectory "$env:UserProfile\.nuget\packages")
        LogTrace $output
    }

    $loaded = [System.Reflection.Assembly]::LoadFile($locatorPath)
}

function Get-MsBuildPath {
    InstallMsBuildLocator
    $msBuildPath = [Microsoft.Build.Locator.MSBuildLocator]::RegisterDefaults().MSBuildPath;

    if ([string]::IsNullOrWhiteSpace($msBuildPath)) {
        $msBuildPath = [Microsoft.Build.Locator.MSBuildLocator]::QueryVisualStudioInstances().OrderByDescending({ $_.Version }).First().MSBuildPath;
        if ([string]::IsNullOrWhiteSpace($msBuildPath)) {
            throw [System.Exception]::new("Unable to locate MSBuild. Please install it from https://visualstudio.microsoft.com/downloads/")
        }
    }

    return $msBuildPath
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

function Get-NuGetInstallationDirectory() {
    # Run the "dotnet nuget locals" command to get the global packages directory
    $nugetGlobalPackagesDir = (dotnet nuget locals global-packages --list | Select-String -Pattern "global-packages: ").ToString().TrimStart("global-packages: ")
    return $nugetGlobalPackagesDir
}

function Get-UnderlyingProcessFramework() {
    $descriptiveVersion = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription

    if ($null -eq $descriptiveVersion -or '' -eq $descriptiveVersion) {
        # the code doesn't even support .NET standard 1.1. Must be a legacy .NET framework of net40 tops
        return "net40"
    }

    LogTrace "Underlying process framework is $descriptiveVersion"
    if ($descriptiveVersion.StartsWith(".NET 8")) {
        return "net8.0"
    }
    elseif ($descriptiveVersion.StartsWith(".NET 7")) {
        return "net7.0"
    }
    elseif ($descriptiveVersion.StartsWith(".NET 6")) {
        return "net6.0"
    }
    elseif ($descriptiveVersion.StartsWith(".NET 5")) {
        return "net5.0"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Framework 2.0.")) {
        return "net20"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Framework 3.5.")) {
        return "net35"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Framework 4.0.")) {
        return "net40"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Framework 4.5.")) {
        return "net452"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Framework 4.6.")) {
        return "net462"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Framework 4.7.")) {
        return "net472"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Framework 4.8.")) {
        return "net48"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Core 3.0")) {
        return "netcoreapp3.0"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Core 3.1")) {
        return "netcoreapp3.1"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Core 2.2")) {
        return "netcoreapp2.2"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Core 2.1")) {
        return "netcoreapp2.1"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Core 2.0")) {
        return "netcoreapp2.0"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Core 1.1")) {
        return "netcoreapp1.1"
    }
    elseif ($descriptiveVersion.StartsWith(".NET Core 1.0")) {
        return "netcoreapp1.0"
    }
}

function Get-MostRelevantFrameworkVersion([string] $packageBasePath) {
    $heirarchyToUse = $netCoreHeirarchy
    $regexToUse = $netCoreRegex
    if ($isDotFramework) {
        $heirarchyToUse = $netFrameworkHeirarchy
        $regexToUse = $netFrameworkRegex
    }

    $minKey = [System.Byte]::MaxValue
    $mostRelevantFramework = $null;

    if ([System.IO.Directory]::Exists($packageBasePath) -eq $false) {
        # This either means, that the package is a meta package, or it's a package which is part of the build process rather than a runtime dependency
        return $mostRelevantFramework
    }

    $childDirs = [System.IO.Directory]::EnumerateDirectories($packageBasePath)
    foreach ($dir in $childDirs) {
        $splits = $dir.Split([System.IO.Path]::DirectorySeparatorChar)
        $tfm = $splits[$splits.Count - 1]

        # Only .net framework, .net core & .net standard libraries are supported
        if (!$tfm.StartsWith("net")) {
            continue;
        }

        $isMatching = $regexToUse.Matches($tfm).Count -eq 1
        $isNetStandard = $tfm.StartsWith("netstandard")
        if ($isMatching -or $isNetStandard) {
            $index = $heirarchyToUse.IndexOf($tfm)
            if ($index -lt $minKey) {
                $minKey = $index
            }

            $mostRelevantFramework = $tfm
            if ($index -eq 0) {
                break;
            }
        }
    }

    if ($null -eq $mostRelevantFramework) {
        throw [System.Exception]::new("No supported framework for $packageName")
    }

    return $mostRelevantFramework
}

function Register-Assemblies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "List of all assemblies to load")]
        [List[NugetPackage]]
        $packagesToLoad
    )

    foreach ($package in $packagesToLoad) {
        foreach ($assembly in $package.Assemblies) {
            if (![System.IO.File]::Exists($assembly)) {
                # The library must be part of the GAC. No need for us to load it
                continue
            }
                    
            try {
                $loaded = [System.Reflection.Assembly]::LoadFile($assembly)
                LogTrace "Loaded assembly $($package.Name) into current context"
            }
            catch {
                Write-Exception $Error
                throw [System.Exception]::new("Unable to load assembly $assembly")
            }
        }
    }
}

function Convert-NugetPackageLockFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $packageFilePath
    )
    $jsonContents = [System.IO.File]::ReadAllText($packageFilePath)
    $packageLock = [System.Text.Json.JsonSerializer]::Deserialize($jsonContents, [NugetPackageLock]);
    $packageLock = [NugetPackageLock] $packageLock
    LogTrace "Parsed lock file $packageFilePath. Version: $($packageLock.version) Dependencies : $($packageLock.dependencies.Keys.Count)"
    
    Write-Progress -Activity "Installing Nuget package $packageName" -PercentComplete 60
    $packageDeets = Get-PackageDeets $packageLock $packageName
    Write-Progress -Activity "Installing Nuget package $packageName" -PercentComplete 80
    $flattedDependencies = Convert-FromNestedListToFlatList $packageDeets
    return $flattedDependencies
}

class ImportNugetPackageOutput {
    [List[NugetPackage]]
    $InstalledPackages

    [System.Runtime.Loader.AssemblyLoadContext]
    $AssemblyLoadContext

    [void] Unload() {
        $this.AssemblyLoadContext.Unload()
    }
}

class NugetPackage {
    [string]
    $Name
    
    [string]
    $Version

    [List[string]]
    $Assemblies

    [List[NugetPackage]]
    $Dependants
}

class ResolvedNugetPackage {
    [string]
    $type
	
    [string]
    $requested
	
    [string]
    $resolved
	
    [string]
    $contentHash
	
    [Dictionary[string, string]]
    $dependencies
}

class NugetPackageLock {

    [int]
    $version
		
    [Dictionary[string, Dictionary[string, ResolvedNugetPackage]]]
    $dependencies
}

function Convert-FromNestedListToFlatList {
    [OutputType([System.Collections.Generic.List[NugetPackage]])]
    param (
        [NugetPackage]
        $package
    )
    
    $flattenedList = [System.Collections.Generic.List[NugetPackage]]::new()
    $stack = [System.Collections.Generic.Stack[NugetPackage]]::new()

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

function Get-PackageDeets {
    [OutputType([NugetPackage])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "A JObject containing the package.lock file")]
        [NugetPackageLock]
        $packageJson,

        [Parameter(Mandatory = $true, HelpMessage = "Name of the nuget package you want to load into your current assembly")]
        [string]
        $packageName,

        [System.Collections.Generic.List[string]] # to prevent endless / useless loops
        $traversedPackagesList = $null
    )

    if ($null -eq $traversedPackagesList) {
        $traversedPackagesList = [System.Collections.Generic.List[string]]::new()
    }

    LogTrace "Retrieving package details for $packageName"
    $tfmsUsed = $packageJson.dependencies.Keys
    if ($tfmsUsed.Count -gt 1) {
        throw [System.Exception]::new("Multiple TFM's found. This is not supported yet")
    }

    # A hacky way to get the first element from a Dictionary. Somehow .Keys.First() doesn't work
    $tfmUsed = $null
    foreach ($tfm in $tfmsUsed) {
        $tfmUsed = $tfm
        break;
    }

    $package = $packageJson.dependencies[$tfmUsed][$packageName]
    $package = [ResolvedNugetPackage] $package
    $self = [NugetPackage]::new()
    $self.Name = $packageName
    $self.Version = $package.resolved

    $childDependencies = [System.Collections.Generic.List[NugetPackage]]::new()
    if ($package.dependencies) {
        foreach ($dependentPackageName in $package.dependencies.Keys) {
            LogTrace "$packageName is dependant on $dependentPackageName. Parsing it too."
            if ($traversedPackagesList.Contains($dependentPackageName)) {
                continue
            }
            $details = Get-PackageDeets $packageJson $dependentPackageName $traversedPackagesList
            $childDependencies.Add($details)
        }
    }

    $self.Dependants = $childDependencies

    $packageBasePath = [System.IO.Path]::Combine($nugetInstallationDir, $self.Name.ToLower(), $self.Version, "lib")
    $mostRelevantFramework = Get-MostRelevantFrameworkVersion $packageBasePath

    $self.Assemblies = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $mostRelevantFramework) {
        LogTrace "$mostRelevantFramework is the most 'closet' framework to current TFM $systemTfmVersion. Loading this version for $packageName"
        $assemblyDir = [System.IO.Path]::Combine($packageBasePath, $mostRelevantFramework)
        $childAssemblies = [System.IO.Directory]::EnumerateFiles($assemblyDir, "*.dll")

        foreach ($assembly in $childAssemblies) {
            $self.Assemblies.Add($assembly.ToString())
        }
    }

    if ($self.Assemblies.Count -eq 0) {
        LogTrace "No runtime dependencies found for $packageName. It's either a meta package, or it's a package which is part of the build process rather than a runtime dependency, or it's already part of the GAC."
    }
    
    LogTrace "Parsed $packageName. $([System.Environment]::NewLine)Name: $packageName $([System.Environment]::NewLine)Version: $($package.resolved) $([System.Environment]::NewLine)Dependants: $($childDependencies.Count) $([System.Environment]::NewLine)Assemblies: $($childAssemblies.Count)"
    $traversedPackagesList.Add($packageName)
    return $self
}

function Write-Exception {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $errorTrace
    )
    $buffer = [System.Text.StringBuilder]::new()
    foreach ($err in $errorTrace) {
        if ($null -ne $err.ScriptStackTrace) {
            $buffer.AppendLine($err.ScriptStackTrace.ToString()) 
        }

        if ($null -ne $err.Exception) {
            $buffer.AppendLine($err.Exception.ToString())
        }
    }

    $fullTrace = $buffer.ToString()

    LogError $fullTrace
    $cleared = $buffer.Clear()
    $cleared = $errorTrace.Clear()
}

function DeleteAllFoldersExcept ([string] $basePath, [string] $excludePath) {
    $childDirectories = [System.IO.Directory]::EnumerateDirectories($basePath)

    foreach ($directory in $childDirectories) {
        if ($directory = $excludePath) { continue; }
        try {
            $output = (Remove-Item -Path $directory -Recurse -Force)
            LogTrace $output
        }
        catch {
            # Ignore if unable to delete the directory due to lock issues
            # But not an issue since this is not a mandatory setup
            Write-Warning "Unable to remove previous cached versions."
        }
    }
}

function Remove-ProjectFolder([string] $path) {
    Push-Location $path
    $output = (dotnet clean)

    $programFilePath = [System.IO.Path]::Combine($path, "Program.cs")
    if ([System.IO.File]::Exists($programFilePath)) {
        [System.IO.File]::Delete($programFilePath)
    }

    $binFolder = [System.IO.Path]::Combine($path, "bin")
    $objFolder = [System.IO.Path]::Combine($path, "obj")

    if ([System.IO.Directory]::Exists($binFolder)) {
        $output = (Remove-Item -Path $binFolder -Recurse -Force)
    }

    if ([System.IO.Directory]::Exists($objFolder)) {
        $output = (Remove-Item -Path $objFolder -Recurse -Force)
    }
}

function Switch-CurrentDirectory([string] $dir) {
    if ($null -ne $dir -and [System.IO.Directory]::Exists($dir)) {
        $global:oldSessionDir = Get-Location
        $global:oldProcessDir = [System.IO.Directory]::GetCurrentDirectory();
        Set-Location $dir
        [System.IO.Directory]::SetCurrentDirectory($dir)
    }
}

function Reset-CurrentDirectory {
    if ($null -ne $global:oldSessionDir -and [System.IO.Directory]::Exists($global:oldSessionDir)) {
        Set-Location $global:oldSessionDir
    }

    if ($null -ne $global:oldProcessDir -and [System.IO.Directory]::Exists($global:oldProcessDir)) {
        [System.IO.Directory]::SetCurrentDirectory($global:oldProcessDir)
    }
    
    $global:oldProcessDir = $null;
    $global:oldSessionDir = $null;
}


function Add-PackageLockIfNotExists([string] $csprojPath) {
    # Load the .csproj file as XML
    $csprojXml = New-Object System.Xml.XmlDocument
    $csprojXml.Load($csprojPath)

    # Check if the RestorePackagesWithLockFile element already exists
    $propertyGroup = $csprojXml.SelectSingleNode("//Project/PropertyGroup[RestorePackagesWithLockFile]")
    if ($null -eq $propertyGroup) {
        # If not, create and add the element
        $newProperty = $csprojXml.CreateElement("RestorePackagesWithLockFile")
        $newProperty.InnerText = "true"
        $csprojXml.DocumentElement.Item("PropertyGroup").AppendChild($newProperty)
    
        # Save the changes back to the .csproj file
        $csprojXml.Save($csprojPath)
    }
}

function Get-MD5Hash([string] $inputString) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hashBytes = $md5.ComputeHash($inputBytes)
    $md5.Dispose()

    return [BitConverter]::ToString($hashBytes).ToLower() -replace '-', ''
}

function LogTrace {
    param (
        [Parameter(Mandatory = $true)]
        [object]
        $message
    )

    if (!$isVerboseMode) {
        return;
    }

    [System.Console]::WriteLine("[$([System.DateTime]::Now.ToString())] $message");
}

function LogInfo {
    param (
        [Parameter(Mandatory = $true)]
        [object]
        $message
    )
    [System.Console]::WriteLine("[$([System.DateTime]::Now.ToString())] $message");
}

function LogError {
    param (
        [Parameter(Mandatory = $true)]
        [object]
        $message
    )

    $oldColor = [System.Console]::ForegroundColor
    [System.Console]::ForegroundColor = [System.ConsoleColor]::Red
    [System.Console]::WriteLine("");
    [System.Console]::WriteLine("[$([System.DateTime]::Now.ToString())] $message");
    [System.Console]::ForegroundColor = $oldColor
}