#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for Advanced IP Scanner (version >= 2.5.4594.1)
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for an entry where DisplayName
    starts with the specified application name (registry DisplayName includes a version
    suffix, e.g. "Advanced IP Scanner 2.5.1") and DisplayVersion >= 2.5.4594.1.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$appDisplayName = 'Advanced IP Scanner'
$requiredVersion = [version]'2.5.4594.1'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { try { $_.DisplayName -like "$appDisplayName*" -and $_.DisplayVersion -and [version]$_.DisplayVersion -ge $requiredVersion } catch { $false } } |
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
