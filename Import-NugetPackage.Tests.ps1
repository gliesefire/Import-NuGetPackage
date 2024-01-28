$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.ps1', '.psm1'
Import-Module "$here\$sut"

Describe "Import-NugetPackage" {
    Context "Loading into separate context" {
        It "Loads a package into separate assembly context, for package with native libraries and circular dependency" {
            $contextName = [System.Guid]::NewGuid().ToString("N")
            $output = Import-NugetPackage -Name "Microsoft.Data.Sqlite" -LoadIntoAssemblyContext -AssemblyContextName $contextName

            $noClassError = $false
            try {
                $obj = [Microsoft.Data.Sqlite.SqliteConnection] $null;
            }
            catch {
                $noClassError = $true
            }

            $noClassError | Should -Be $true
            $output.AssemblyLoadContext.Name | Should -Be $contextName

            $obj = $output.CreateObjectOfType("Microsoft.Data.Sqlite.SqliteConnection", ("Data Source=hello.db"))
            $obj | Should -Not -Be $null

            $obj.Open();
            $obj.State | Should -Be "Open"
            
            $output.Unload();

            # and once it's unloaded, the class should not be available
            $noClassError = $false
            $obj = $null
            try {
                $obj = $output.CreateObjectOfType("Microsoft.Data.Sqlite.SqliteConnection", ("Data Source=hello.db"))
            }
            catch {
                $noClassError = $true
            }

            $obj | Should -Be $null
            $noClassError | Should -Be $true
        }
    }

    Context "Loading into current context" {
        It "Loads a package with 1 or more dependencies" {
            Import-NugetPackage -Name "MessagePack"

            $errorThrown = $false
            try
            {
                $obj = [MessagePack.MessagePackSerializer] $null
            }
            catch
            {
                $errorThrown = $true
            }
            
            $errorThrown | Should -Be $false
            $obj | Should -Be $null
            [MessagePack.MessagePackSerializer].Assembly.GetName().Name | Should -Be "MessagePack"
        }

        It "Loads a package with pre-release version" {
            Import-NugetPackage -Name "Dapper" -Version "1.50.4-alpha1-00070" -PreRelease
            $obj = [Dapper.SqlMapper] $null
            $obj | Should -Be $null
            
            # Assembly versions are not the same as package versions. It's rounded up to the nearest whole version
            [Dapper.SqlMapper].Assembly.GetName().Version.ToString() | Should -Be "1.50.4.0"
        }
    }

    Context "Installation" {
        It "Installs a package with (seemingly) no dependencies" {
            $output = Import-NugetPackage -Name "Microsoft.NETCore.Platforms"
            $installedPackages = $output.InstalledPackages

            # Remove $null values. This is a bug in the output of the function
            $installedPackages = $installedPackages | Where-Object { $_ -ne $null }
        
            $installedPackages.Count -ge 1 | Should -Be $true
            $expectedPackage = $installedPackages[$installedPackages.Count - 1]
            $expectedPackage[0].Name | Should -Be "Microsoft.NETCore.Platforms"
        }

        It "Installs a package with specific version, with no dependencies" {
            $output = Import-NugetPackage -Name "Microsoft.NETCore.Platforms" -Version "6.0.7"
            $installedPackages = $output.InstalledPackages

            # Remove $null values. This is a bug in the output of the function
            $installedPackages = $installedPackages | Where-Object { $_ -ne $null }
        
            $installedPackages.Count -eq 1 | Should -Be $true
            $expectedPackage = $installedPackages[$installedPackages.Count - 1]
            $expectedPackage[0].Name | Should -Be "Microsoft.NETCore.Platforms"
            $expectedPackage[0].Version | Should -Be "6.0.7"
        }

        It "Installs a package with more than 1 dependency" {
            $output = Import-NugetPackage -Name "MessagePack"
            $installedPackages = $output.InstalledPackages

            $installedPackages.Count -gt 1 | Should -Be $true
            $expectedPackage = $installedPackages[$installedPackages.Count - 1]
            $expectedPackage[0].Name | Should -Be "MessagePack"
        }

        It "Installs a package which is part of the .NET Core SDK" {
            $output = Import-NugetPackage -Name "System.Runtime"
            $installedPackages = $output.InstalledPackages

            $installedPackages.Count -ge 1 | Should -Be $true
            $expectedPackage = $installedPackages[$installedPackages.Count - 1]
            $expectedPackage[0].Name | Should -Be "System.Runtime"
        }

        It "Installs a package into a separate output directory" {
            $outputDir = [System.IO.Path]::Combine($PSScriptRoot, $([System.Guid]::NewGuid().ToString("N")))
            Import-NugetPackage -Name "Dapper" -PackageDirectory $outputDir

            $packageOutputDir = [System.IO.Path]::Combine($outputDir, "dapper")
            $outputDirExists = [System.IO.Directory]::Exists($packageOutputDir)
            $outputDirExists | Should -Be $true
        }
    }
}
