using namespace System;
using namespace System.Collections.Generic;
using namespace System.Text.RegularExpressions;
using namespace System.IO;

function Show-HelpMenu {
    # Input options to display non-interactive menus or perform actions.
    $regexOptions = [RegexOptions]::Multiline -bor [RegexOptions]::IgnoreCase -bor [RegexOptions]::Compiled -bor [RegexOptions]::Global
    $parameterParseRegex = [Regex]::new('(?:\[Alias\((?<aliases>[^\)]*)\)\])?[\r\n\t\s]*\[Parameter\([\r\n\t\s]*(?:Mandatory = \$(?:(?:\bfalse\b)|(?:\btrue\b))),[\r\n\t\s]*HelpMessage = "(?<helpMessage>[^"]*)"[\r\n\t\s]*\)\][\r\n\t\s]*\[[a-zA-Z]+\][\r\n\t\s]*\$(?<variableName>[a-zA-Z]+)', $regexOptions);

    # Read the script itself and parse all the options
    $script = [IO.File]::ReadAllText("./Import-NuGetPackage.psm1");
    $regexMatches = $parameterParseRegex.Matches($script);

    # Create a list of all the options
    $AllOptions = @();

    ForEach ($match in $regexMatches) {
        $variableName = $match.Groups['variableName'].Value;
        $aliasMatch = $match.Groups['aliases'].Value;
        if ([string]::IsNullOrWhiteSpace($aliasMatch)) {
            $aliasMatch = $variableName;
        }
        else
        {
            $aliasMatch = $aliasMatch + ", '$variableName'";
        }

        $aliasMatch = $aliasMatch.ToUpper().Trim();

        $helpMessage = $match.Groups['helpMessage'].Value;

        # if help message is more than 50 characters, wrap it to the next line
        $helpMessage = Convert-TextToWrappedLines $helpMessage 70 $true
        if ($helpMessage.GetType().Name -eq 'String') {
            $x = [List[string]]::new();
            $x.Add($helpMessage);
            $helpMessage = $x;
        }

        $aliasLines = Convert-TextToWrappedLines $aliasMatch 50 $false

        if ($aliasLines.GetType().Name -eq 'String') {
            $x = [List[string]]::new();
            $x.Add($aliasLines);
            $aliasLines = $x;
        }

        $AllOptions += , @($aliasLines, $helpMessage);
    }

    WriteToConsoleWithColor -text "`n`nHELP MENU" -color $([ConsoleColor]::Cyan)
    WriteToConsoleWithColor -text " :: Available" -insertNewLine $false
    WriteToConsoleWithColor -text " options" -color $([ConsoleColor]::Yellow) -insertNewLine $false
    WriteToConsoleWithColor -text " shown below:`n"

    ForEach ($options in $AllOptions) {
        $aliases = $options[0]
        $helpMessage = $options[1]

        $maxLines = [Math]::Max($aliases.Count, $helpMessage.Count);

        for ($i = 0; $i -lt $maxLines; $i++) {

            $line = ""
            
            if ($i -lt $helpMessage.Count) {
                $line += $helpMessage[$i] + "   `t"
            }

            WriteToConsoleWithColor -text $line -insertNewLine $false
            $line = ""
            if ($i -lt $aliases.Count) {
                $currentAlias = $aliases[$i]
                $line += $currentAlias
            }

            WriteCodeToConsole -text $line
        }
    }
}

function Convert-TextToWrappedLines {
    param(
        [Parameter()]
        [string]
        $text,

        [Parameter()]
        [int]
        $maxLineLength,

        [Parameter()]
        [bool]
        $addIndentation = $true
    )

    $words = $text.Split(' ');
    $wrappedLines = [List[string]]::new();

    for ($i = 0; $i -lt $words.Length; $i++) {
        $firstWord = $words[$i];
        if ($addIndentation) {
            if ($i -eq 0) {
                $currentLine = "[*]`t$firstWord";
            }
            else {
                $currentLine = "   `t$firstWord";
            }
        }
        else {
            $currentLine = $firstWord;
        }

        $currentLineLength = $currentLine.Length;

        while ($i + 1 -lt $words.Length -and $currentLineLength + $words[$i + 1].Length + 1 -le $maxLineLength) {
            $trimmedWord = $words[$i + 1].Trim();
            if ($trimmedWord.Length -eq 0)
            {
                $i++;
                continue;
            }

            $i++;
            $currentLine += " " + $trimmedWord;
            $currentLineLength = $currentLine.Length;
        }

        if ($addIndentation) {
            $currentLine = [string]::Format("{0,-$maxLineLength}", $currentLine);
        }

        $wrappedLines.Add($currentLine);
    }

    return $wrappedLines;
}

function WriteCodeToConsole {
    param(
        [Parameter()]
        [string]
        $text,

        [Parameter()]
        [bool]
        $insertNewLine = $true
    )

    WriteToConsoleWithColor -text $text -color $([ConsoleColor]::Yellow) -insertNewLine $insertNewLine
}

function WriteToConsoleWithColor {
    param(
        [Parameter()]
        [string]
        $text,

        [Parameter()]
        [ConsoleColor]
        $color = [ConsoleColor]::White,

        [Parameter()]
        [bool]
        $insertNewLine = $true
    )

    $oldForegroundColor = [Console]::ForegroundColor;
    [Console]::ForegroundColor = $color;

    if ($insertNewLine) {
        [Console]::WriteLine($text);
    }
    else {
        [Console]::Write($text);
    }

    [Console]::ForegroundColor = $oldForegroundColor;
}