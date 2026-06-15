#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for WinSCP
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for an entry where DisplayName
    starts with 'WinSCP' and DisplayVersion is 6.5.6 or higher.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$appDisplayNamePrefix  = 'WinSCP'
$appMinimumVersion     = [version]'6.5.6'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "$appDisplayNamePrefix*" -and [version]$_.DisplayVersion -ge $appMinimumVersion } |
        Select-Object -First 1

    if ($app)
    {
        Write-Output "DETECTED (PASS): $($app.DisplayName) $($app.DisplayVersion)"
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): $appDisplayNamePrefix $appMinimumVersion or higher not found in registry"
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
