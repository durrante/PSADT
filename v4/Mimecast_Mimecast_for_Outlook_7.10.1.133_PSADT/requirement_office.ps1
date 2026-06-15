#Requires -Version 5.1
<#
.SYNOPSIS
    Intune requirement script: verifies that Microsoft Office is installed.
.DESCRIPTION
    Detects any version of Microsoft Office (Click-to-Run or MSI-based).
    Covers Microsoft 365 Apps, Office 2021, 2019, 2016, and earlier MSI installs.

    ---- Intune Configuration ----
    Data type : Boolean
    Operator  : Equals
    Value     : True
    ------------------------------

    The script always exits 0 - exit code signals script execution success.
    Intune evaluates the STDOUT output ("True"/"False") against the rule above.
#>

$officeFound = $false

# --- Check 1: Click-to-Run (Microsoft 365 Apps, Office 2019 / 2021 retail) ---
# VersionToReport is populated as soon as C2R Office is installed.
$c2rPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
if (Test-Path $c2rPath)
{
    $c2rConfig = Get-ItemProperty -Path $c2rPath -ErrorAction SilentlyContinue
    if ($c2rConfig.VersionToReport)
    {
        $officeFound = $true
    }
}

# --- Check 2: MSI Office 16.0 InstallRoot (Office 2016 / 2019 volume license) ---
if (-not $officeFound)
{
    $installRootPath = 'HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot'
    if (Test-Path $installRootPath)
    {
        $installRoot = Get-ItemProperty -Path $installRootPath -ErrorAction SilentlyContinue
        if ($installRoot.Path)
        {
            $officeFound = $true
        }
    }
}

# --- Check 3: Uninstall registry fallback (older MSI Office / any remaining version) ---
if (-not $officeFound)
{
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $msiOffice = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Microsoft Office*' -and $_.Publisher -like 'Microsoft*' } |
        Select-Object -First 1
    if ($msiOffice)
    {
        $officeFound = $true
    }
}

# Output "True" or "False" - Intune evaluates this against the Boolean rule.
# Always exit 0; non-zero exit codes signal a script execution failure to Intune.
Write-Host $officeFound.ToString()
exit 0
