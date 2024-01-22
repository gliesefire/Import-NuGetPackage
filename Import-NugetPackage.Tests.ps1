$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.ps1', '.psm1'
Import-Module "$here\$sut"

Describe "Import-NugetPackage" {
    Context "Installation" {
        It "Installs a package with (seemingly) no dependencies" {
            $output = Import-NugetPackage -Name "Microsoft.NETCore.Platforms"
            $installedPackages = $output.InstalledPackages

            # Remove $null values. This is a bug in the output of the function
            $installedPackages = $installedPackages | Where-Object { $_ -ne $null }
        
            $installedPackages.Count | Should -Be 1
            $expectedPackage = $installedPackages[0]
            $expectedPackage[0].Name | Should -Be "Microsoft.NETCore.Platforms"
        }

        It "Installs a package with specific version, with no dependencies" {
            $output = Import-NugetPackage -Name "Microsoft.NETCore.Platforms" -Version "6.0.7"
            $installedPackages = $output.InstalledPackages

            # Remove $null values. This is a bug in the output of the function
            $installedPackages = $installedPackages | Where-Object { $_ -ne $null }
        
            $installedPackages.Count | Should -Be 1
            $expectedPackage = $installedPackages[0]
            $expectedPackage[0].Name | Should -Be "Microsoft.NETCore.Platforms"
            $expectedPackage[0].Version | Should -Be "6.0.7"
        }

        It "Installs a package with 1 or more dependency" {
            $output = Import-NugetPackage -Name "System.Text.Json"
            $installedPackages = $output.InstalledPackages

            $installedPackages.Count -gt 1 | Should -Be $true
            $expectedPackage = $installedPackages[$installedPackages.Count - 1]
            $expectedPackage[0].Name | Should -Be "System.Text.Json"

            $output.Unload();
        }

        It "Installs a package with circular dependency" {
            $output = Import-NugetPackage -Name "Microsoft.Data.Sqlite"
            $installedPackages = $output.InstalledPackages
            
            $circularPackage = $null;
            foreach ($package in $installedPackages) {
                if ($package.Name -eq "SQLitePCLRaw.core") {
                    $circularPackage = $package
                    break;
                }
            }

            $circularPackage -eq $null | Should -Be $false
            $expectedPackage = $installedPackages[$installedPackages.Count - 1]
            $expectedPackage[0].Name | Should -Be "Microsoft.Data.Sqlite"

            $output.Unload();
        }
    }
}
