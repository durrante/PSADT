#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for FileZilla Client (version >= 3.70.5)
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for a registry key name
    (PSChildName) starting with 'FileZilla' with version >= 3.70.5. Using PSChildName
    avoids false matches against FileZilla Server entries that share a similar DisplayName.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$registryKeyNamePrefix = 'FileZilla'
$requiredVersion = [version]'3.70.5'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like "$registryKeyNamePrefix*" -and $_.DisplayVersion -and [version]$_.DisplayVersion -ge $requiredVersion } |
        Select-Object -First 1

    if ($app)
    {
        Write-Output "DETECTED (PASS): $($app.DisplayName) $($app.DisplayVersion) meets requirement >= $requiredVersion"
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): $registryKeyNamePrefix* >= $requiredVersion not found in registry"
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
