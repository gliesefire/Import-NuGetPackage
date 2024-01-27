using namespace System.Linq;
using namespace System.Collections.Generic;
using namespace System;
using namespace System.Reflection;
using namespace System.Runtime.Loader;

class FrameworkDeets {
    [Text.RegularExpressions.Regex] $FrameworkRegex
    [string] $FrameworkName
    [List[string]] $FrameworkHeirarchy

    FrameworkDeets([string] $name, [List[string]] $heirarchy, [Text.RegularExpressions.Regex] $regex) {
        $this.FrameworkRegex = $regex
        $this.FrameworkName = $name
        $this.FrameworkHeirarchy = $heirarchy
    }
}

function Get-Adler32Hash([string] $inputString) {
    $a = 1; $b = 0;
    $MOD_ADLER = 65521;
    $ADLER_CONST2 = 65536;

    for ($i = 0; $i -lt $inputString.Length; $i++) {
        $char = $inputString[$i];
        $charAsInt = [System.Convert]::ToInt32($char);
        $a = ($a + $charAsInt) % $MOD_ADLER;
        $b = ($b + $a) % $MOD_ADLER;
    }

    $finalValue = ($b * $ADLER_CONST2 + $a);
    $finalValue = [Int64]$finalValue;
    return $finalValue.ToString("X");
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

function LogWarning {
    param (
        [Parameter(Mandatory = $true)]
        [object]
        $message
    )

    $oldColor = [System.Console]::ForegroundColor
    [System.Console]::ForegroundColor = [System.ConsoleColor]::DarkYellow
    [System.Console]::WriteLine("");
    [System.Console]::WriteLine("[$([System.DateTime]::Now.ToString())] $message");
    [System.Console]::ForegroundColor = $oldColor
}

$oldSessionStack = [Collections.Stack]::new();
$oldProcessStack = [Collections.Stack]::new();

function Switch-CurrentDirectory([string] $dir) {
    if ($null -ne $dir -and [System.IO.Directory]::Exists($dir)) {
        $oldSessionStack.Push($(Get-Location))

        $processDir = [System.IO.Directory]::GetCurrentDirectory()
        $oldProcessStack.Push($processDir)
        Set-Location $dir
        [System.IO.Directory]::SetCurrentDirectory($dir)
    }
}

function Reset-CurrentDirectory {
    if ($oldSessionStack.Count -eq 0) {
        return;
    }

    $oldSessionDir = $oldSessionStack.Pop()
    if ($null -ne $oldSessionDir -and [System.IO.Directory]::Exists($oldSessionDir)) {
        Set-Location $oldSessionDir
    }

    if ($oldProcessStack.Count -eq 0) {
        return;
    }

    $oldProcessDir = $oldProcessStack.Pop()
    if ($null -ne $oldProcessDir -and [System.IO.Directory]::Exists($oldProcessDir)) {
        [System.IO.Directory]::SetCurrentDirectory($oldProcessDir)
    }
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

function Get-MostRelevantFrameworkVersion([string] $packageBasePath, [FrameworkDeets] $framework) {
    $heirarchyToUse = $framework.FrameworkHeirarchy
    $regexToUse = $framework.FrameworkRegex

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
        LogTrace "Unable to find a matching framework for $packageName. Probably a part of $($framework.FrameworkName)'s base libs"
    }

    return $mostRelevantFramework
}

function Get-RuntimeIdentifier {
    # Run `dotnet --info` and capture the output
    $regex = [System.Text.RegularExpressions.Regex]::new("RID:\s*([^(\s|\n)]+)", [System.Text.RegularExpressions.RegexOptions]::Compiled)
    $dotnetInfoOutput = dotnet --info

    $match = $regex.Match($dotnetInfoOutput)
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    else {
        return "Unknown"
    }
}

function New-PackageDirectory {
    param (
        [string]
        $CallerScriptName
    )

    $homeDir = $HOME
    
    $callerScriptName = $MyInvocation.PSCommandPath
    LogTrace "Invoked by $callerScriptName. Generating a Hash for it"
    $hash = Get-Adler32Hash $callerScriptName
    LogTrace "$hash will be used to refer to $callerScriptName"

    $scriptContents = [System.IO.File]::ReadAllText($callerScriptName)
    $scriptHash = Get-Adler32Hash $scriptContents

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
    return $callerPackagesPath
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
    $null = $buffer.Clear()
    $null = $errorTrace.Clear()
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
            LogWarning "Unable to remove previous cached versions."
        }
    }
}