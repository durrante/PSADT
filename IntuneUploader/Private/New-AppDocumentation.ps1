<#
.SYNOPSIS
    Generates a Markdown documentation file for a deployed Intune Win32 application.

.DESCRIPTION
    Creates a per-app .md file in the documentation folder containing:
      - Application details (name, version, publisher, author)
      - Packaging info (source folder, setup file, .intunewin path)
      - Install and uninstall commands, with PSADT note if applicable
      - Detection method summary
      - Requirement rules
      - Assignment details
      - Intune App ID and upload timestamp
      - Logo copied alongside the doc file
      - Template used

    The doc file is named: <DisplayName>_<Version>_<YYYYMMDD>.md
    Logo is copied as:      <DisplayName>_Logo.<ext>
#>

function New-AppDocumentation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AppConfig,

        [Parameter(Mandatory)]
        [PSCustomObject]$IntuneApp,

        [Parameter(Mandatory)]
        [string]$DocumentationPath,

        # Path to the .intunewin file that was uploaded
        [string]$IntunewinPath = ''
    )

    # Ensure docs folder exists
    New-Item -ItemType Directory -Path $DocumentationPath -Force | Out-Null

    $safeName    = $AppConfig.DisplayName -replace '[\\/:*?"<>|]', '_'
    $safeVersion = ($AppConfig.Version ?? 'NoVersion') -replace '[\\/:*?"<>|]', '_'
    $dateStr     = Get-Date -Format 'yyyyMMdd'
    $docFileName = "${safeName}_${safeVersion}_${dateStr}.md"
    $docPath     = Join-Path $DocumentationPath $docFileName

    # Copy logo
    $logoRelPath = ''
    if ($AppConfig.LogoPath -and (Test-Path $AppConfig.LogoPath)) {
        $logoExt     = [System.IO.Path]::GetExtension($AppConfig.LogoPath)
        $logoDestName = "${safeName}_Logo${logoExt}"
        $logoDest    = Join-Path $DocumentationPath $logoDestName
        Copy-Item -Path $AppConfig.LogoPath -Destination $logoDest -Force
        $logoRelPath = $logoDestName
    }

    #region Build detection summary
    $det = $AppConfig.Detection
    $detSummary = switch ($det.Type) {
        'Script' {
            $scriptName = Split-Path $det.ScriptPath -Leaf
            "**PowerShell Script**: ``$scriptName``  `n" +
            "- Enforce signature check: $($det.EnforceSignatureCheck)  `n" +
            "- Run as 32-bit: $($det.RunAs32Bit)"
        }
        'MSI' {
            $verLine = if ($det.ProductVersion) { "`n- Version: $($det.ProductVersionOperator) $($det.ProductVersion)" } else { '' }
            "**MSI Product Code**: ``$($det.ProductCode)``$verLine"
        }
        'Registry' {
            $valueLine  = if ($det.ValueName) { "`n- Value name: $($det.ValueName)" } else { '' }
            $opLine     = if ($det.Value)      { "`n- Operator / Value: $($det.Operator) ``$($det.Value)``" } else { '' }
            "**Registry**: ``$($det.KeyPath)``  `n" +
            "- Detection type: $($det.DetectionType)$valueLine$opLine  `n" +
            "- Check 32-bit: $($det.Check32BitOn64System)"
        }
        'File' {
            $opLine = if ($det.Value) { "`n- Operator / Value: $($det.Operator) ``$($det.Value)``" } else { '' }
            "**File/Folder**: ``$($det.Path)\$($det.FileOrFolder)``  `n" +
            "- Detection type: $($det.DetectionType)$opLine  `n" +
            "- Check 32-bit: $($det.Check32BitOn64System)"
        }
        default { "Unknown ($($det.Type))" }
    }
    #endregion

    #region Build assignment summary
    $asg = $AppConfig.Assignment
    $asgSummary = if ($asg) {
        $groupPart = if ($asg.Type -eq 'Group') {
            " (Group: $($asg.GroupName ?? $asg.GroupID))"
        } else { '' }
        "**$($asg.Type)**$groupPart — Intent: $($asg.Intent ?? 'required'), Notification: $($asg.Notification ?? 'showAll')"
    } else { 'Not configured' }
    #endregion

    #region Build requirement summary
    $reqSummary  = "- Architecture: **$($AppConfig.Architecture ?? 'x64')**  `n"
    $reqSummary += "- Minimum Windows: **$($AppConfig.MinimumSupportedWindowsRelease ?? 'W10_2004')**"
    if ($AppConfig.RequirementScript) {
        $rsName = Split-Path $AppConfig.RequirementScript.ScriptPath -Leaf
        $reqSummary += "  `n- Additional script requirement: ``$rsName``"
    }
    #endregion

    #region PSADT note
    $psadtNote = ''
    if ($AppConfig.IsPSADT) {
        $psadtNote = @"

> **PSADT Package** ($($AppConfig.PSADTVersion ?? 'v3'))
> Install and uninstall commands use the PSAppDeployToolkit framework.
> Silent mode is enforced; the toolkit handles all UI suppression and logging.

"@
    }
    #endregion

    #region Logo section
    $logoSection = if ($logoRelPath) {
        "![$($AppConfig.DisplayName) Logo]($logoRelPath)`n"
    } else { '_No logo provided_' }
    #endregion

    #region Intunewin info
    $intunewinSection = if ($IntunewinPath -and (Test-Path $IntunewinPath)) {
        "``$IntunewinPath``  ($('{0:N2}' -f ((Get-Item $IntunewinPath).Length / 1MB)) MB)"
    } else { '_Not recorded_' }
    #endregion

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $appId     = $IntuneApp.id          ?? '_Unknown_'
    $appGrUrl  = "https://intune.microsoft.com/#blade/Microsoft_Intune_Apps/SettingsMenu/0/appId/$appId"

    $markdown = @"
# $($AppConfig.DisplayName)

$logoSection

| Field       | Value |
|-------------|-------|
| Display Name | $($AppConfig.DisplayName) |
| Version     | $($AppConfig.Version ?? '-') |
| Publisher   | $($AppConfig.Publisher ?? '-') |
| Author      | $($AppConfig.Author ?? '-') |
| Notes       | $($AppConfig.Notes ?? '-') |
| Intune App ID | ``$appId`` |
| Uploaded    | $timestamp |
| Template    | $($AppConfig.Template ?? '-') |

[View in Intune Portal]($appGrUrl)

---

## Packaging

| Field        | Value |
|--------------|-------|
| Source Folder | ``$($AppConfig.SourceFolder)`` |
| Setup File   | ``$($AppConfig.SetupFile)`` |
| .intunewin   | $intunewinSection |
$psadtNote
---

## Commands
$psadtNote
| Command     | Value |
|-------------|-------|
| Install     | ``$($AppConfig.InstallCommandLine)`` |
| Uninstall   | ``$($AppConfig.UninstallCommandLine)`` |

---

## Detection Method

$detSummary

---

## Requirements

$reqSummary

---

## Assignment

$asgSummary

---

_Generated by Intune Win32 App Uploader on $timestamp_
"@

    $markdown | Set-Content -Path $docPath -Encoding UTF8
    Write-Host "  [OK] Documentation saved: $docPath" -ForegroundColor Green

    return $docPath
}
