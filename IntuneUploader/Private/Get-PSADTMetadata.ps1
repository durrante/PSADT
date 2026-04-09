<#
.SYNOPSIS
    Parses a PSADT v4 Invoke-AppDeployToolkit.ps1 and returns application metadata.

.DESCRIPTION
    PSADT v4 stores app info in the $adtSession hashtable.
    Author/Owner is searched across multiple patterns since it's not a standard v4 field.

    Field mapping to Intune:
        AppVendor       → Publisher
        AppName         → DisplayName
        AppVersion      → AppVersion
        AppScriptAuthor → Owner  (searched via multiple patterns)
#>

function Get-PSADTMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$SourceFolder
    )

    $script = Get-ChildItem -Path $SourceFolder -Filter 'Invoke-AppDeployToolkit.ps1' -Depth 1 |
              Select-Object -First 1

    if (-not $script) {
        Write-Warning "No Invoke-AppDeployToolkit.ps1 found in: $SourceFolder"
        return $null
    }

    $content = Get-Content -Path $script.FullName -Raw

    # Parse $adtSession hashtable values
    function Get-HashVal {
        param([string]$Key)
        if ($content -match "(?m)^\s*$Key\s*=\s*['""]([^'""]*)['""]") {
            return $Matches[1].Trim()
        }
        return ''
    }

    $appVendor   = Get-HashVal 'AppVendor'
    $appName     = Get-HashVal 'AppName'
    $appVersion  = Get-HashVal 'AppVersion'
    $appArch     = Get-HashVal 'AppArch'
    $appLang     = Get-HashVal 'AppLang'
    $appRevision = Get-HashVal 'AppRevision'

    # --- Author / Owner search (multiple patterns) ---
    $appOwner = ''

    # 1. Non-standard AppScriptAuthor or AppOwner field inside $adtSession or anywhere
    if ($content -match "(?m)^\s*AppScriptAuthor\s*=\s*['""]([^'""]*)['""]") {
        $appOwner = $Matches[1].Trim()
    }
    if (-not $appOwner -and $content -match "(?m)^\s*AppOwner\s*=\s*['""]([^'""]*)['""]") {
        $appOwner = $Matches[1].Trim()
    }

    # 2. Comment-style: # Author: value  /  # Owner: value  /  # Created by: value
    if (-not $appOwner) {
        $authorPatterns = @(
            '(?mi)^[\s#]*Author[:\s]+([^#\r\n]+)'
            '(?mi)^[\s#]*Owner[:\s]+([^#\r\n]+)'
            '(?mi)^[\s#]*Created[\s]+[Bb]y[:\s]+([^#\r\n]+)'
            '(?mi)^[\s#]*Maintainer[:\s]+([^#\r\n]+)'
        )
        foreach ($pat in $authorPatterns) {
            if ($content -match $pat) {
                $appOwner = $Matches[1].Trim().TrimEnd('#').Trim()
                if ($appOwner) { break }
            }
        }
    }

    # 3. .NOTES block: look for an "Author" or "Created By" line within it
    if (-not $appOwner -and $content -match '(?ms)\.NOTES.+?\.(?:LINK|SYNOPSIS|DESCRIPTION|EXAMPLE|END)') {
        $notesBlock = $Matches[0]
        if ($notesBlock -match '(?mi)^[\s#]*(Author|Owner|Created[- ]?[Bb]y)[:\s]+([^\r\n]+)') {
            $appOwner = $Matches[2].Trim()
        }
    }

    # 4. Fallback: old v3 variable style sometimes left in converted scripts
    if (-not $appOwner -and $content -match "(?m)^\s*\[string\]\s*\`$appScriptAuthor\s*=\s*['""]([^'""]*)['""]") {
        $appOwner = $Matches[1].Trim()
    }

    # Setup file: prefer compiled .exe, fall back to .ps1
    $setupFile = if (Test-Path (Join-Path $SourceFolder 'Invoke-AppDeployToolkit.exe')) {
        'Invoke-AppDeployToolkit.exe'
    } else {
        'Invoke-AppDeployToolkit.ps1'
    }

    return @{
        AppVendor            = $appVendor
        AppName              = $appName
        AppVersion           = $appVersion
        AppArch              = $appArch
        AppLang              = $appLang
        AppRevision          = $appRevision
        AppOwner             = $appOwner   # maps to Intune Owner field
        ScriptPath           = $script.FullName
        SetupFile            = $setupFile
        InstallCommandLine   = "$setupFile -DeployMode Silent"
        UninstallCommandLine = "$setupFile -DeploymentType Uninstall -DeployMode Silent"
    }
}

function Test-IsPSADTv4 {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFolder
    )
    return [bool](Get-ChildItem -Path $SourceFolder -Filter 'Invoke-AppDeployToolkit.ps1' -Depth 1 -ErrorAction SilentlyContinue)
}
