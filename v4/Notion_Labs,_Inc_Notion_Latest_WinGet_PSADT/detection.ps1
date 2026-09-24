#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for the Notion package.
.DESCRIPTION
    Notion has no machine-wide installer: it installs into each user's profile and registers itself in HKCU,
    so there is nothing in the HKLM uninstall keys to detect. This package is deployed as SYSTEM and its
    machine-wide part is the per-user install script plus the logon Run value that runs it, so that is what is
    detected here, along with the package tag key.

    Individual users get Notion when they log on, which is after this detection passes. That is expected, and
    is the same model as other machine-wide-installer apps.

    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script, with the app set to install as System.
#>

$tagKey = 'HKLM:\SOFTWARE\PSADTPackages\Notion Labs, Inc\Notion'
$userScriptPath = Join-Path -Path $env:ProgramFiles -ChildPath 'PSADTPackages\Notion\Install-NotionForUser.ps1'
$runValueName = 'NotionUserInstall'
$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'

try
{
    $tag = Get-ItemProperty -LiteralPath $tagKey -ErrorAction SilentlyContinue
    if ($tag.Installed -ne 'True')
    {
        Write-Output "NOT DETECTED (FAIL): package tag [$tagKey] is missing"
        exit 1
    }

    if (!(Test-Path -LiteralPath $userScriptPath -PathType Leaf))
    {
        Write-Output "NOT DETECTED (FAIL): per-user install script [$userScriptPath] is missing"
        exit 1
    }

    if (!(Get-ItemProperty -LiteralPath $runKey -Name $runValueName -ErrorAction SilentlyContinue))
    {
        Write-Output "NOT DETECTED (FAIL): logon entry [$runValueName] is missing"
        exit 1
    }

    Write-Output "DETECTED (PASS): Notion package installed $($tag.InstallDate), version $($tag.Version)"
    exit 0
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
