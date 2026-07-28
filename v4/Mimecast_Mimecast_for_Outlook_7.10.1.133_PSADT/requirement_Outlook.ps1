#Requires -Version 5.1
<#
.SYNOPSIS
    Intune requirement script: verifies 64-bit Outlook is installed.
.DESCRIPTION
    Mimecast for Outlook (x64) has a launch condition requiring 64-bit Outlook.
    Checking for "Office" is not sufficient: OEM preinstalled consumer
    Microsoft 365 (O365HomePremRetail) ships with Outlook excluded, so Office
    is present while Outlook is not. This script tests for the Outlook binary
    and confirms the Click-to-Run platform is x64.

    ---- Intune Configuration ----
    Data type : Boolean
    Operator  : Equals
    Value     : True
    ------------------------------

    The script always exits 0. Intune evaluates STDOUT against the rule above.
#>

$outlookReady = $false

# --- Check 1: 64-bit Click-to-Run Outlook binary ---
$c2rOutlook = Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16\OUTLOOK.EXE'
if (Test-Path -LiteralPath $c2rOutlook)
{
    $c2rPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $platform = (Get-ItemProperty -Path $c2rPath -EA SilentlyContinue).Platform
    if ($platform -eq 'x64')
    {
        $outlookReady = $true
    }
}

# --- Check 2: MSI Outlook fallback (64-bit volume licence installs) ---
if (-not $outlookReady)
{
    $msiOutlook = 'HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\InstallRoot'
    if (Test-Path -LiteralPath $msiOutlook)
    {
        $path = (Get-ItemProperty -Path $msiOutlook -EA SilentlyContinue).Path
        if ($path -and (Test-Path -LiteralPath (Join-Path $path 'OUTLOOK.EXE')))
        {
            $outlookReady = $true
        }
    }
}

Write-Host $outlookReady.ToString()
exit 0