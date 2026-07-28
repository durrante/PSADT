#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for Microsoft Power BI Desktop (version >= 2.156.951.0)
.DESCRIPTION
    Searches both 64-bit and 32-bit Uninstall registry keys for an entry where DisplayName
    matches the 'Microsoft Power ?BI Desktop' pattern (covers both the 'Power BI' and
    'PowerBI' DisplayName variants Microsoft has shipped) and version >= 2.156.951.0.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$appDisplayNamePattern = 'Microsoft Power ?BI Desktop'
$requiredVersion = [version]'2.156.951.0'

$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

try
{
    $app = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $appDisplayNamePattern -and $_.DisplayVersion -and [version]$_.DisplayVersion -ge $requiredVersion } |
        Select-Object -First 1

    if ($app)
    {
        Write-Output "DETECTED (PASS): $($app.DisplayName) $($app.DisplayVersion) meets requirement >= $requiredVersion"
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): $appDisplayNamePattern >= $requiredVersion not found in registry"
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
