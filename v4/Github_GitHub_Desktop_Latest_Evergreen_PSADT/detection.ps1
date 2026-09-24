#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for GitHub Desktop
.DESCRIPTION
    Detects the machine-wide MSI ("GitHub Desktop Deployment Tool"), which is what this package
    installs as SYSTEM. The per-user copies live in each user's HKCU and install at logon, so they
    are deliberately not part of detection.
    Searches both 64-bit and 32-bit Uninstall registry keys (the MSI registers under WOW6432Node).
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$appDisplayName = 'GitHub Desktop Deployment Tool'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $appDisplayName } |
        Select-Object -First 1

    if ($app)
    {
        Write-Output "DETECTED (PASS): $($app.DisplayName) $($app.DisplayVersion)"
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): $appDisplayName not found in registry"
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
