#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for FileZilla Client (version >= 3.70.5)
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for the 'FileZilla Client'
    registry key name (PSChildName) with version >= 3.70.5. Using PSChildName avoids
    false matches against FileZilla Server entries that share a similar DisplayName.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$registryKeyName = 'FileZilla'
$requiredVersion = [version]'3.70.5'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -eq $registryKeyName -and $_.DisplayVersion -and [version]$_.DisplayVersion -ge $requiredVersion } |
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
