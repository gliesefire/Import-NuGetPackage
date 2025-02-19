using module ./Import-NugetPackage.psm1

using namespace System.Linq;
using namespace System.Collections.Generic;
using namespace System;

$output = Import-NugetPackage -Name "Dapper"
$installedPackages = $output.InstalledPackages

[Console]::WriteLine("Installed packages: ${installedPackages.Length}")