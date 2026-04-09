#Requires -Version 5.1
<#
.SYNOPSIS
    One-time setup script for the Intune Win32 App Uploader tool.

.DESCRIPTION
    - Installs required PowerShell modules (IntuneWin32App, MSAL.PS)
    - Downloads IntuneWinAppUtil.exe from Microsoft
    - Creates the folder structure (Config, Templates, Docs, Output)
    - Guides through creating an Entra ID app registration
    - Saves configuration to Config\config.json
    - Tests authentication with delegated permissions (interactive browser login)

.NOTES
    Run once before using Invoke-IntuneUploader.ps1.
    Requires internet access and PowerShell running as Administrator for module installation.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

#region Helpers

function Write-Header {
    param([string]$Text)
    $line = '=' * 60
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$line`n" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host "[*] $Text" -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Text)
    Write-Host "[!!] $Text" -ForegroundColor Red
}

function Read-HostDefault {
    param([string]$Prompt, [string]$Default = '')
    if ($Default) {
        $result = Read-Host "$Prompt [default: $Default]"
        if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
        return $result
    }
    return Read-Host $Prompt
}

function Read-HostPath {
    param([string]$Prompt, [string]$Default = '')
    $value = Read-HostDefault -Prompt $Prompt -Default $Default
    return $value.Trim('"').Trim("'").TrimEnd('\')
}

#endregion

#region Main Setup

Clear-Host
Write-Header 'Intune Win32 App Uploader - Setup'

$ToolRoot = $PSScriptRoot

# Verify not running the wrong working directory
Write-Step "Tool root: $ToolRoot"

#region 1. PowerShell version check
Write-Header 'Step 1: Environment Check'

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Fail 'PowerShell 5.1 or higher is required.'
    exit 1
}
Write-OK "PowerShell $($PSVersionTable.PSVersion)"

# Warn if running as non-admin (modules may still install for current user)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] Not running as Administrator - modules will be installed for current user only.' -ForegroundColor Yellow
}

#endregion

#region 2. Install required modules
Write-Header 'Step 2: Install Required PowerShell Modules'

$requiredModules = @(
    @{ Name = 'IntuneWin32App';  MinVersion = '1.4.0' }
    @{ Name = 'MSAL.PS';         MinVersion = '4.37.0' }
)

$scope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }

foreach ($mod in $requiredModules) {
    Write-Step "Checking $($mod.Name)..."
    $installed = Get-Module -ListAvailable -Name $mod.Name | Sort-Object Version -Descending | Select-Object -First 1
    if ($installed -and $installed.Version -ge [version]$mod.MinVersion) {
        Write-OK "$($mod.Name) $($installed.Version) already installed"
    }
    else {
        Write-Step "Installing $($mod.Name) from PSGallery..."
        try {
            Install-Module -Name $mod.Name -Scope $scope -Repository PSGallery -Force -AllowClobber -SkipPublisherCheck
            Write-OK "$($mod.Name) installed"
        }
        catch {
            Write-Fail "Failed to install $($mod.Name): $_"
            Write-Host "  Try: Install-Module $($mod.Name) -Scope CurrentUser -Force" -ForegroundColor Gray
            exit 1
        }
    }
}

#endregion

#region 3. Download IntuneWinAppUtil.exe
Write-Header 'Step 3: Download IntuneWinAppUtil.exe'

$toolsDir = Join-Path $ToolRoot 'Tools'
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

$utilPath = Join-Path $toolsDir 'IntuneWinAppUtil.exe'

if (Test-Path $utilPath) {
    Write-OK "IntuneWinAppUtil.exe already present at: $utilPath"
}
else {
    Write-Step 'Downloading IntuneWinAppUtil.exe from Microsoft...'
    $downloadUrl = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe'
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($downloadUrl, $utilPath)
        Write-OK "Downloaded to: $utilPath"
    }
    catch {
        Write-Fail "Download failed: $_"
        Write-Host '  Please manually download IntuneWinAppUtil.exe from:' -ForegroundColor Gray
        Write-Host '  https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool' -ForegroundColor Gray
        Write-Host "  and place it in: $toolsDir" -ForegroundColor Gray
        # Not fatal - continue so user can fill in the path manually
    }
}

#endregion

#region 4. Create folder structure
Write-Header 'Step 4: Create Folder Structure'

$folders = @(
    'Config'
    'Templates'
    'Docs'
    'Private'
)

foreach ($folder in $folders) {
    $path = Join-Path $ToolRoot $folder
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Write-OK "Folder ready: $folder"
}

#endregion

#region 5. App Registration guidance
Write-Header 'Step 5: Entra ID App Registration'

Write-Host @'
This tool uses DELEGATED permissions (interactive browser login).
You need an Entra ID (Azure AD) App Registration with:

  1. Go to: https://portal.azure.com > Entra ID > App registrations > New registration
  2. Name:      IntuneWin32Uploader (or any name)
  3. Supported account types: Accounts in this organisational directory only
  4. Redirect URI: Public client/native (mobile & desktop) -> http://localhost
  5. Click Register

  6. Go to API Permissions > Add a permission > Microsoft Graph > Delegated:
       - DeviceManagementApps.ReadWrite.All
       - Group.Read.All
  7. Click "Grant admin consent"

  8. Go to Authentication:
       - Under "Advanced settings", enable "Allow public client flows" -> Yes
       - Save

  9. Copy the Application (client) ID and Directory (tenant) ID from the Overview page.

'@

Read-Host 'Press Enter once your app registration is ready...'

#endregion

#region 6. Collect configuration
Write-Header 'Step 6: Configuration'

# Load existing config if present
$configPath    = Join-Path $ToolRoot 'Config\config.json'
$existingConfig = $null
if (Test-Path $configPath) {
    try { $existingConfig = Get-Content $configPath -Raw | ConvertFrom-Json } catch {}
}

Write-Host 'Enter your configuration details (press Enter to keep existing value where shown).' -ForegroundColor Gray
Write-Host ''

# Safe helper to read a property from a PSCustomObject that may be null
function Get-CfgVal {
    param([string]$Key, [string]$Default = '')
    if ($null -eq $existingConfig) { return $Default }
    $prop = $existingConfig.PSObject.Properties[$Key]
    if ($null -ne $prop -and $prop.Value -ne '' -and $null -ne $prop.Value) { return [string]$prop.Value }
    return $Default
}

$tenantId       = Read-HostDefault -Prompt 'Tenant ID (Directory ID)'    -Default (Get-CfgVal 'TenantID')
$clientId       = Read-HostDefault -Prompt 'Client ID (Application ID)'  -Default (Get-CfgVal 'ClientID')

Write-Host ''
Write-Host 'Default output folder for .intunewin packages (all apps unless overridden per-app):' -ForegroundColor Gray
$defaultOutput  = Read-HostPath -Prompt 'Output folder' -Default (Get-CfgVal 'DefaultOutputPath')

Write-Host ''
Write-Host 'Documentation folder (where app docs/logos are saved):' -ForegroundColor Gray
$defaultDocs    = Read-HostPath -Prompt 'Docs folder'   -Default (Get-CfgVal 'DocumentationPath' (Join-Path $ToolRoot 'Docs'))

Write-Host ''
Write-Host 'Default Intune app template to apply:' -ForegroundColor Gray
$defaultTemplate = Read-HostDefault -Prompt 'Default template name' -Default (Get-CfgVal 'DefaultTemplate' 'PSADT-Default')

# Ensure output/docs folders exist
foreach ($dir in @($defaultOutput, $defaultDocs)) {
    if ($dir -and -not (Test-Path $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-OK "Created folder: $dir"
        }
        catch { Write-Host "[!] Could not create $dir - create it manually." -ForegroundColor Yellow }
    }
}

$config = [ordered]@{
    TenantID            = $tenantId
    ClientID            = $clientId
    DefaultOutputPath   = $defaultOutput
    DocumentationPath   = $defaultDocs
    IntuneWinAppUtilPath = $utilPath
    DefaultTemplate     = $defaultTemplate
}

$config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
Write-OK "Configuration saved to: $configPath"

#endregion

#region 7. Copy example templates if not present
Write-Header 'Step 7: Templates'

$templateSources = @(
    'PSADT-Default.json'
    'Generic-Default.json'
)

foreach ($tpl in $templateSources) {
    $dest = Join-Path $ToolRoot "Templates\$tpl"
    if (-not (Test-Path $dest)) {
        Write-Host "  [!] Template $tpl not found - ensure you have all tool files deployed." -ForegroundColor Yellow
    }
    else {
        Write-OK "Template ready: $tpl"
    }
}

#endregion

#region 8. Test authentication
Write-Header 'Step 8: Test Authentication'

Write-Host 'Testing interactive login to Intune...' -ForegroundColor Gray
Write-Host 'A browser window will open for you to sign in.' -ForegroundColor Gray
Write-Host ''

try {
    Import-Module IntuneWin32App -Force
    Connect-MSIntuneGraph -TenantID $tenantId -ClientID $clientId -Interactive -ErrorAction Stop
    Write-OK 'Authentication successful!'
    Write-Host ''
    Write-Host '  You are now connected to Intune. Run Invoke-IntuneUploader.ps1 to start uploading apps.' -ForegroundColor Green
}
catch {
    Write-Fail "Authentication failed: $_"
    Write-Host '  Check your Tenant ID, Client ID, and app registration permissions.' -ForegroundColor Gray
}

#endregion

Write-Header 'Setup Complete'
Write-Host "  Config:    $configPath" -ForegroundColor Gray
Write-Host "  Templates: $(Join-Path $ToolRoot 'Templates')" -ForegroundColor Gray
Write-Host "  Docs:      $defaultDocs" -ForegroundColor Gray
Write-Host "  Tool:      $utilPath" -ForegroundColor Gray
Write-Host ''
Write-Host '  Run: .\Invoke-IntuneUploader.ps1' -ForegroundColor Cyan
Write-Host ''
