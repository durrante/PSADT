#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for TeamViewer (version >= 15.81.6)
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for an entry where DisplayName
    starts with the specified application name and version >= 15.81.6.
    'TeamViewer Host' entries are excluded so a Host install is not treated as a match.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$appDisplayName = 'TeamViewer'
$requiredVersion = [version]'15.81.6'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { try { $_.DisplayName -like "$appDisplayName*" -and $_.DisplayName -notlike "$appDisplayName Host*" -and $_.DisplayVersion -and [version]$_.DisplayVersion -ge $requiredVersion } catch { $false } } |
        Select-Object -First 1

    if ($app)
    {
        Write-Output "DETECTED (PASS): $($app.DisplayName) $($app.DisplayVersion) meets requirement >= $requiredVersion"
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): $appDisplayName >= $requiredVersion not found in registry"
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
