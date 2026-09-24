#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection script for Bicep CLI (version >= 0.47.16)
.DESCRIPTION
    Checks for the machine-wide bicep.exe in Program Files\Bicep CLI and verifies its file version >= 0.47.16.
    The package copies the standalone binary rather than running the per-user setup, so there is no
    Uninstall registry entry to check.
    Returns exit 0 (detected) or exit 1 (not detected).
    Configure in Intune as a custom PowerShell detection script.
#>

# ProgramW6432 always points at the 64-bit Program Files, even if Intune runs this script as a 32-bit process.
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$bicepExePath = Join-Path -Path $programFiles -ChildPath 'Bicep CLI\bicep.exe'
$requiredVersion = [version]'0.47.16'

try
{
    if (-not (Test-Path -LiteralPath $bicepExePath -PathType Leaf))
    {
        Write-Output "NOT DETECTED (FAIL): $bicepExePath not found"
        exit 1
    }

    $versionInfo = (Get-Item -LiteralPath $bicepExePath).VersionInfo
    $fileVersion = [version]::new($versionInfo.FileMajorPart, $versionInfo.FileMinorPart, $versionInfo.FileBuildPart, $versionInfo.FilePrivatePart)

    if ($fileVersion -ge $requiredVersion)
    {
        Write-Output "DETECTED (PASS): $bicepExePath $fileVersion meets requirement >= $requiredVersion"
        exit 0
    }
    else
    {
        Write-Output "NOT DETECTED (FAIL): $bicepExePath $fileVersion is below required $requiredVersion"
        exit 1
    }
}
catch
{
    Write-Output "NOT DETECTED (FAIL): Detection error: $($_.Exception.Message)"
    exit 1
}
