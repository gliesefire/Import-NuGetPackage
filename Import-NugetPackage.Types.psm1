using module ./Helper.psm1
using namespace System.Linq;
using namespace System.Collections.Generic;
using namespace System;
using namespace System.Reflection;
using namespace System.Runtime.Loader;
using namespace System.Runtime.InteropServices;

# Get the .NET Framework version used by the PowerShell process
$systemTfmVersion = Get-UnderlyingProcessFramework
$netCoreRegex = [Text.RegularExpressions.Regex]::new("^net(?:coreapp)?[0-9]{1,2}\.[0-9]{1,2}$")
$isDotnetCore = $netCoreRegex.Matches($systemTfmVersion).Count -eq 1

class ImportNugetPackageOutputBase {
    [IEnumerable[NugetPackage]]
    $InstalledPackages

    ImportNugetPackageOutputBase([IEnumerable[NugetPackage]] $packages) {
        $this.InstalledPackages = $packages
    }

    [void] Unload() {
        throw [Exception]::new("Not implemented")
    }

    [object] CreateObjectOfType([string] $typeName, [object[]] $paramss = $null) {
        throw [Exception]::new("Not implemented")
    }
    
    [void] RegisterAssemblies ([System.Func[string, System.Reflection.Assembly]] $AssemblyLoader) {
        foreach ($package in $this.InstalledPackages) {
            foreach ($assembly in $package.Assemblies) {
                if (![System.IO.File]::Exists($assembly)) {
                    # The library must be part of the GAC. No need for us to load it
                    continue
                }
                        
                try {
                    $null = $AssemblyLoader.Invoke($assembly)
                    LogTrace "Loaded assembly $($package.Name) into current context"
                }
                catch {
                    Write-Exception $Error
                    throw [System.Exception]::new("Unable to load assembly $assembly")
                }
            }
        }
    }
    
    [object] ThrowOrReturn ([string] $message, [object]$obj) {
        if ($null -eq $obj) {
            throw [Exception]::new($message)
        }

        return $obj    
    }
}

class NugetPackage {
    [string]
    $Name
    
    [string]
    $Version

    [List[string]]
    $Assemblies


    [List[string]]
    $NativeLibraries

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

class RidImport {
    [string[]]
    [System.Text.Json.Serialization.JsonPropertyName("#import")]
    $imports
}

class RidGraph {
    [Dictionary[string, RidImport]]
    $runtimes
}

if ($isDotnetCore) {
    class ScriptAssemblyContext : System.Runtime.Loader.AssemblyLoadContext {
        [string]
        $Name

        [ImportNugetPackageOutputBase]
        $OutputBase

        ScriptAssemblyContext([ImportNugetPackageOutputBase] $outputBase, [string]$name)
        : base($name, $true) {
            $this.Name = $name;
            $this.OutputBase = $outputBase;
            $this.RegisterAssemblies($outputBase.InstalledPackages)
        }

        # It's imperative that these 2 methods stay within the "context" of ScriptAssemblyContext.
        # Otherwise, we could have just invoked them on the $outputBase object
        [void] RegisterAssemblies ([IEnumerable[NugetPackage]] $InstalledPackages) {
            foreach ($package in $InstalledPackages) {
                foreach ($assembly in $package.Assemblies) {
                    if (![System.IO.File]::Exists($assembly)) {
                        # The library must be part of the GAC. No need for us to load it
                        continue
                    }

                    try {
                        $null = $this.LoadFromAssemblyPath($assembly)
                        LogTrace "Loaded assembly $($package.Name) into current context"
                    }
                    catch {
                        Write-Exception $Error
                        throw [System.Exception]::new("Unable to load assembly $assembly")
                    }
                }
            }
        }

        [object] CreateInstanceOfType(
            [IEnumerable[Assembly]] $assemblies, 
            [string] $typeName, [object[]] $paramss = $null
        ) {
            foreach ($assembly in $assemblies) {
                $type = $assembly.GetType($typeName);
                if ($null -ne $type) {
                    if ($type.IsAbstract -or $type.IsInterface) {
                        throw [Exception]::new("Unable to create an instance of $typeName. It's an abstract class or an interface")
                    }
    
                    if ($null -eq $paramss) {
                        $constructor = $type.GetConstructor([Type]::EmptyTypes)
                        return $constructor.Invoke($null)
                    }

                    # Generate the type.GetConstuctor([Type[]]) method based on object params
                    $paramTypes = $paramss | ForEach-Object { $_.GetType() }
                    if ($paramTypes.Count -eq 1) {
                        $constructor = $type.GetConstructor($paramTypes[0])
                        return $constructor.Invoke($paramss[0])
                    }
                    elseif ($paramTypes.Count -eq 2) {
                        $constructor = $type.GetConstructor($paramTypes[0], $paramTypes[1])
                        return $constructor.Invoke($paramss[0], $paramss[1])
                    }
                    elseif ($paramTypes.Count -eq 3) {
                        $constructor = $type.GetConstructor($paramTypes[0], $paramTypes[1], $paramTypes[2])
                        return $constructor.Invoke($paramss[0], $paramss[1], $paramss[2])
                    }
                    elseif ($paramTypes.Count -eq 4) {
                        $constructor = $type.GetConstructor($paramTypes[0], $paramTypes[1], $paramTypes[2], $paramTypes[3])
                        return $constructor.Invoke($paramss[0], $paramss[1], $paramss[2], $paramss[3])
                    }
                    elseif ($paramTypes.Count -eq 5) {
                        $constructor = $type.GetConstructor($paramTypes[0], $paramTypes[1], $paramTypes[2], $paramTypes[3], $paramTypes[4])
                        return $constructor.Invoke($paramss[0], $paramss[1], $paramss[2], $paramss[3], $paramss[4])
                    }
                    elseif ($paramTypes.Count -eq 6) {
                        $constructor = $type.GetConstructor($paramTypes[0], $paramTypes[1], $paramTypes[2], $paramTypes[3], $paramTypes[4], $paramTypes[5])
                        return $constructor.Invoke($paramss[0], $paramss[1], $paramss[2], $paramss[3], $paramss[4], $paramss[5])
                    }
                    elseif ($paramTypes.Count -eq 7) {
                        $constructor = $type.GetConstructor($paramTypes[0], $paramTypes[1], $paramTypes[2], $paramTypes[3], $paramTypes[4], $paramTypes[5], $paramTypes[6])
                        return $constructor.Invoke($paramss[0], $paramss[1], $paramss[2], $paramss[3], $paramss[4], $paramss[5], $paramss[6])
                    }
                    elseif ($paramTypes.Count -eq 8) {
                        $constructor = $type.GetConstructor($paramTypes[0], $paramTypes[1], $paramTypes[2], $paramTypes[3], $paramTypes[4], $paramTypes[5], $paramTypes[6], $paramTypes[7])
                        return $constructor.Invoke($paramss[0], $paramss[1], $paramss[2], $paramss[3], $paramss[4], $paramss[5], $paramss[6], $paramss[7])
                    }
                    else {
                        throw [Exception]::new("Unable to create an instance of $typeName. Too many parameters")
                    }
                }
            }
    
            return $null;
        }

        [object] CreateObjectOfType([string] $typeName, [object[]] $paramss = $null) {
            $assemblyList = [IEnumerable[Assembly]] $this.Assemblies
            $obj = $this.CreateInstanceOfType($assemblyList, $typeName, $paramss);

            if ($null -ne $obj) {
                return $obj;
            }
            
            $defaultList = [List[Assembly]]::new()
            $([AssemblyLoadContext]::Default.Assemblies) | ForEach-Object { $null = $defaultList.Add($_) }
            $obj = $this.CreateInstanceOfType($defaultList, $typeName, $paramss);

            return $this.OutputBase.ThrowOrReturn("Type $typeName not found in any loaded assembly.", $obj)
        }

        [Assembly] Load([AssemblyName] $assemblyName) {
            return $null;
        }
        
        [IntPtr] LoadUnmanagedDll([string] $unmanagedDllName) {
            # Determine the path to the DLL
            $libraryPath = $this.GetPathToUnmanagedDll($unmanagedDllName);

            try {
                # Check if the library path was resolved
                if (![string]::IsNullOrEmpty($libraryPath)) {
                    # Use NativeLibrary.Load to load the native library from the path
                    $pointer = [NativeLibrary]::Load($libraryPath);
                    $pointer = [IntPtr] $pointer
                    return $pointer;
                }
            }
            catch {
                Write-Exception $global:Error
            }

            # Fallback to default behavior if the path is not resolved
            return base.LoadUnmanagedDll($unmanagedDllName);
        }

        [string] GetPathToUnmanagedDll([string] $unmanagedDllName) {
            # Check for a nuget package that contains the unmanaged DLL name
            $unmanagedDllPath = $null;
            foreach ($package in $this.OutputBase.InstalledPackages) {
                for ($i = 0; $i -lt $package.NativeLibraries.Count; $i++) {
                    $nativeLibraryFilePath = [string] $($package.NativeLibraries[$i]);
                    $nativeLibraryFileName = [System.IO.Path]::GetFileName($nativeLibraryFilePath);
                    if ($nativeLibraryFileName.Contains($unmanagedDllName, [StringComparison]::OrdinalIgnoreCase)) {
                        $unmanagedDllPath = $nativeLibraryFilePath
                        break;
                    }
                }
            }

            return $unmanagedDllPath;
        }
    }

    class DotnetCoreNugetPackageOutput : ImportNugetPackageOutputBase {
        # Public read-only property
        [ScriptAssemblyContext] $AssemblyLoadContext

        DotnetCoreNugetPackageOutput([IEnumerable[NugetPackage]] $packages, [string] $AssemblyLoadContextName = $null)
        : base($packages) {
            if ([string]::IsNullOrWhiteSpace($AssemblyLoadContextName)) {
                $AssemblyLoadContextName = [Guid]::NewGuid().ToString("N")
            }

            $this.AssemblyLoadContext = [ScriptAssemblyContext]::new($this, $AssemblyLoadContextName)
        }

        [void] Unload() {
            try {
                $this.AssemblyLoadContext.Unload()

                # Remove reference to the assembly load context
                $this.AssemblyLoadContext = $null

                # Force garbage collection to ensure that the native library is unloaded
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
            catch {
                LogError "Unable to unload assembly context $($this.AssemblyLoadContext.Name)"
                Write-Exception $global:Error
            }
        }

        [object] CreateObjectOfType([string] $typeName, [object[]] $paramss = $null) {
            if ($null -eq $this.AssemblyLoadContext) {
                throw [Exception]::new("You can't create an object after the assembly context has been unloaded")
            }

            try {
                $obj = $this.AssemblyLoadContext.CreateObjectOfType($typeName, $paramss)
                return $this.ThrowOrReturn("Type $typeName not found in any loaded assembly.", $obj)    
            }
            catch {
                Write-Exception $global:Error
            }
            
            return $null;
        }
    }
}
else {
    class AgnosticNugetPackageOutput : ImportNugetPackageOutputBase {
        [AppDomain] $AppDomain

        AgnosticNugetPackageOutput($packages, $domainName = $null) : base($packages) {
            if ([string]::IsNullOrWhiteSpace($domainName)) {
                $domainName = [Guid]::NewGuid().ToString("N")
            }

            $ads = [AppDomainSetup]::new();
            $ads.ApplicationBase = [AppDomain]::CurrentDomain.BaseDirectory;

            $ads.DisallowBindingRedirects = $false;
            $ads.DisallowCodeDownload = $true;
            $ads.ConfigurationFile = [AppDomain]::CurrentDomain.SetupInformation.ConfigurationFile;

            $this.AppDomain = [AppDomain].CreateDomain($domainName, $null, $ads);
            $this.RegisterAssemblies({ $this.AppDomain.Load($args[0]) });
        }

        [void] Unload() {
            [AppDomain]::Unload($this.AppDomain)
        }

        [object] CreateObjectOfType([string] $typeName, [object[]] $paramss = $null) {
            $obj = CreateObjectOfType $($this.AppDomain.GetAssemblies()) $typeName $paramss { return $null -eq $arg[1] ? $this.AppDomain.CreateInstance($args[0]) : $this.AppDomain.CreateInstance($args[0], $args[1]) }
            return ThrowOrReturn "Type $typeName not found in any loaded assembly." $obj
        }
    }
}