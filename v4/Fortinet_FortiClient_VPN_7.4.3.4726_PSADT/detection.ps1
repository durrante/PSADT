#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for FortiClient VPN (version = 7.4.3.4726)
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for an entry where DisplayName
    matches the specified application name exactly and DisplayVersion equals 7.4.3.4726.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.

    NOTE: an exact version match is used deliberately instead of '>='. FortiClient VPN build
    numbers are not sequential - 7.4.3.4726 (built March 2026) is newer than the previously
    deployed 7.4.3.8758 (built December 2025). A '>=' check would report 7.4.3.8758 devices
    as compliant and they would never be upgraded.
#>

$appDisplayName = 'FortiClient VPN'
$requiredVersion = '7.4.3.4726'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $appDisplayName -and $_.DisplayVersion -eq $requiredVersion } |
        Select-Object -First 1

    if ($app)
    {
        Write-Output "DETECTED (PASS): $($app.DisplayName) $($app.DisplayVersion) matches required version $requiredVersion"
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): $appDisplayName $requiredVersion not found in registry"
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
