#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for Microsoft SQL Server Management Studio (version >= 22.10.1)
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for an entry where DisplayName
    contains the specified application name and version >= 22.10.1.
    The name is matched without a 'Microsoft' prefix because the ARP display name is not
    consistently prefixed across SSMS versions. The version test scopes the match to SSMS 22.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$appDisplayName = 'SQL Server Management Studio'
$requiredVersion = [version]'22.10.1'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { try { $_.DisplayName -like "*$appDisplayName*" -and $_.DisplayVersion -and [version]$_.DisplayVersion -ge $requiredVersion } catch { $false } } |
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
