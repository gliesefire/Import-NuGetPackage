# Import-NuGetPackage v1.0

## Introduction

Import-NuGetPackage is a PowerShell v2.0+ compatible PowerShell command, and a nuget package installer for powershell scripts.
That being said, I haven't tested the script much with Legacy powershell & .NET framework systems. Feel free to raise a bug if you find one.

It's recommended to use [powershell core](https://github.com/PowerShell/PowerShell/releases/latest)

## Background

----------
As I began to write more and more powershell scripts, I realized that consuming NuGet packages was becoming more and more of a hassle.
`Install-Package` has issues of it's own. As of Jan 2024, it still doesn't support installing packages with cyclic dependencies, depends on nuget.exe instead of dotnet nuget and doesn't load the assemblies automatically.

The last point is particularly annoying, as if the package has multiple dependencies, you have to manually load them one by one, while figuring out what those dependencies are, their version, TFM and everything.

## Purpose

The script's sole purpose to provide a seamless way to install any package, while also implicitly loading all the associated assemblies on installation.
The ideal scenario, is for the script to work exactly the same as a combination of `dotnet restore + dotnet build`

## Usage

There is only one function as the entrypoint, `Import-NugetPackage`. This can be also used as a "direct" function, similar to `Import-Package` by keeping this in a common place.

It accepts almost all the parameters supported by [dotnet restore](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-restore)

## Installation

The source code for Import-NugetPackage is hosted at Github, and you may
download, fork and review it from [this](https://github.com/gliesefire/Import-NugetPackage) repository. Please report issues
or feature requests through Github's bug tracker associated with this project.

Run the following commands to use it in your script / session / module.

```powershell
Import-Module ./Import-NugetPackage.psm1
Import-NugetPackage
```

### Note

If you are using windows, and not using [powershell core](https://github.com/PowerShell/PowerShell/releases/latest), then you will see an error message regarding digital signature. You can bypass that by running the below command.

```powershell
Set-executionpolicy -Scope Process remotesigned
```

or if you have written a script which consumes this as a module, then you can run the below command to do the same

```bash
powershell.exe -noprofile -executionpolicy bypass -file /your/script/location/which/consumes/Import-NugetPackage/Module.ps1
```

## License

Import-NugetPackage is released under the MIT license

## Release Notes

v1.0 - 2024-01-24 First release
