#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for Audacity
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for an MSI-based entry where DisplayName
    starts with the specified application name (Audacity 4+ ships as an MSI, DisplayName 'Audacity 4.0').
    Legacy Audacity 3.x (Inno Setup EXE) installs are ignored so they get replaced.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$appDisplayName = 'Audacity*'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like $appDisplayName -and $_.WindowsInstaller -eq 1 } |
        Select-Object -First 1

    if ($app)
    {
        Write-Output "DETECTED (PASS): $($app.DisplayName) $($app.DisplayVersion)"
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): MSI install of $appDisplayName not found in registry"
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
