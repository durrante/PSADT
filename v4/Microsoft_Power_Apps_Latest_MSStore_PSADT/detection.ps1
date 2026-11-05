#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for Microsoft Power Apps (Microsoft Store app, provisioned for all users).
.DESCRIPTION
    Detected when the Power Apps package is provisioned on the device, i.e. Windows installs it
    for every user. The version isn't checked: the package always provisions the latest Store
    version, and the Store keeps each user's copy up to date afterwards.

    Get-AppxProvisionedPackage needs a 64-bit process, so the script relaunches itself as 64-bit
    if Intune runs it as 32-bit.

    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

$packageName = 'MicrosoftCorporationII.PowerAppsforWindows10'

if ([System.Environment]::Is64BitOperatingSystem -and -not [System.Environment]::Is64BitProcess)
{
    $powershell64 = Join-Path -Path $env:WINDIR -ChildPath 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

try
{
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction Stop |
        Where-Object { $_.DisplayName -eq $packageName } |
        Sort-Object -Property { [System.Version]$_.Version } -Descending |
        Select-Object -First 1

    if ($provisioned)
    {
        Write-Output "DETECTED (PASS): $packageName $($provisioned.Version) is provisioned for all users."
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): $packageName is not provisioned."
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
