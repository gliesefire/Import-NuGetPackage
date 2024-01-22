# Courtesy of https://github.com/danielbohannon/Invoke-Obfuscation/blob/master/Invoke-Obfuscation.ps1

function Show-HelpMenu {
    # Input options to display non-interactive menus or perform actions.
    $MenuInputOptionsShowHelp = @(@('help', 'get-help', '?', '-?', '/?', 'menu'), "Show this <Help> Menu                     `t  " )
    $PackageNameOptionsShowOptions = @(@('package-name', 'name')       , "<Show options> for payload to obfuscate   `t  " )
    $PackageVersionInputOptions = @(@('package-version', 'version')            , "<Clear> screen                            `t  " )
    
    # Add all above input options lists to be displayed in SHOW OPTIONS menu.
    $AllAvailableInputOptionsLists = @()
    $AllAvailableInputOptionsLists += , $MenuInputOptionsShowHelp
    $AllAvailableInputOptionsLists += , $PackageNameOptionsShowOptions
    $AllAvailableInputOptionsLists += , $PackageVersionInputOptions

    # Show Help Menu.
    Write-Host "`n`nHELP MENU" -NoNewLine -ForegroundColor Cyan
    Write-Host " :: Available" -NoNewLine
    Write-Host " options" -NoNewLine -ForegroundColor Yellow
    Write-Host " shown below:`n"
    ForEach ($InputOptionsList in $AllAvailableInputOptionsLists) {
        $InputOptionsCommands = $InputOptionsList[0]
        $InputOptionsDescription = $InputOptionsList[1]

        # Add additional coloring to string encapsulated by <> if it exists in $InputOptionsDescription.
        If ($InputOptionsDescription.Contains('<') -AND $InputOptionsDescription.Contains('>')) {
            $FirstPart = $InputOptionsDescription.SubString(0, $InputOptionsDescription.IndexOf('<'))
            $MiddlePart = $InputOptionsDescription.SubString($FirstPart.Length + 1)
            $MiddlePart = $MiddlePart.SubString(0, $MiddlePart.IndexOf('>'))
            $LastPart = $InputOptionsDescription.SubString($FirstPart.Length + $MiddlePart.Length + 2)
            Write-Host "$LineSpacing $FirstPart" -NoNewLine
            Write-Host $MiddlePart -NoNewLine -ForegroundColor Cyan
            Write-Host $LastPart -NoNewLine
        }
        Else {
            Write-Host "$LineSpacing $InputOptionsDescription" -NoNewLine
        }
        
        $Counter = 0
        ForEach ($Command in $InputOptionsCommands) {
            $Counter++
            Write-Host $Command.ToUpper() -NoNewLine -ForegroundColor Yellow
            If ($Counter -lt $InputOptionsCommands.Count) { Write-Host ',' -NoNewLine }
        }
        Write-Host ''
    }
}