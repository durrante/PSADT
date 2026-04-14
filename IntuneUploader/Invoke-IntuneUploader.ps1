#Requires -Version 7.0
<#
.SYNOPSIS
    Intune Win32 App Uploader — launches the GUI.

.DESCRIPTION
    Entry point for the tool. Loads config, dot-sources all private functions,
    then opens the WPF main window.

    IMPORTANT: Must be run in PowerShell 7 (pwsh.exe), NOT Windows PowerShell 5.1
    (powershell.exe). Running in 5.1 loads the wrong version of the IntuneWin32App
    module and causes locale-specific DateTime parsing failures on non-US systems.

    Run Setup-IntuneUploader.ps1 first to install prerequisites and create config.json.

.PARAMETER BulkFile
    Optionally supply a bulk JSON file path to trigger a headless (no-GUI) bulk upload.
    Useful for scheduled or scripted runs.

.EXAMPLE
    pwsh .\Invoke-IntuneUploader.ps1

.EXAMPLE
    pwsh .\Invoke-IntuneUploader.ps1 -BulkFile C:\Apps\BulkList.json
#>

[CmdletBinding()]
param(
    [string]$BulkFile = ''
)

$ErrorActionPreference = 'Stop'

# Belt-and-braces check in case the #Requires line is somehow bypassed
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error ("This tool requires PowerShell 7 (pwsh.exe).`n" +
                 "You are running PowerShell $($PSVersionTable.PSVersion).`n`n" +
                 "Start the tool with:  pwsh `"$PSCommandPath`"")
    exit 1
}

$ToolRoot = $PSScriptRoot

#region Load private functions
$privateScripts = @(
    'Private\Repair-IntuneWin32AppModule.ps1'
    'Private\Invoke-TenantGraphRequest.ps1'
    'Private\Get-PSADTMetadata.ps1'
    'Private\New-IntunePackage.ps1'
    'Private\Add-IntuneApplication.ps1'
    'Private\New-AppDocumentation.ps1'
    'Private\Show-AppUploadForm.ps1'
    'Private\Show-BulkManager.ps1'
    'Private\Show-MainWindow.ps1'
)

foreach ($script in $privateScripts) {
    $fullPath = Join-Path $ToolRoot $script
    if (-not (Test-Path $fullPath)) {
        Write-Error "Missing required file: $fullPath`nEnsure all tool files are present and run from the IntuneUploader folder."
        exit 1
    }
    . $fullPath
}
#endregion

#region Load config
$configPath = Join-Path $ToolRoot 'Config\config.json'
if (-not (Test-Path $configPath)) {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show(
        "Configuration not found:`n$configPath`n`nPlease run Setup-IntuneUploader.ps1 first.",
        'Setup Required', 'OK', 'Warning')
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

$templateFolder = Join-Path $ToolRoot 'Templates'
#endregion

#region Shared processing functions
# These are called from both the GUI and the headless bulk path.

function Invoke-ProcessApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AppConfig,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [string]$TemplateFolder = ''
    )

    try {
        # Resolve template
        $tplName = $AppConfig.Template ?? $Config.DefaultTemplate ?? 'PSADT-Default'
        $tplPath = Join-Path $TemplateFolder "$tplName.json"
        if (-not (Test-Path $tplPath)) {
            Write-Warning "Template '$tplName' not found, falling back to Generic-Default."
            $tplPath = Join-Path $TemplateFolder 'Generic-Default.json'
        }

        # Setup file: PSADT provides it; otherwise caller must have set it
        if (-not $AppConfig.SetupFile -and $AppConfig.IsPSADT) {
            $meta = Get-PSADTMetadata -SourceFolder $AppConfig.SourceFolder
            if ($meta) { $AppConfig.SetupFile = $meta.SetupFile }
        }
        if (-not $AppConfig.SetupFile) {
            throw "SetupFile is required but was not specified."
        }

        # Output folder
        $outputFolder = $AppConfig.OutputFolder
        if (-not $outputFolder) { $outputFolder = $Config.DefaultOutputPath }
        if (-not $outputFolder) {
            $outputFolder = Join-Path $ToolRoot 'Output'
            New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
        }

        # 1. Package
        $intunewinPath = New-IntunePackage `
            -SourceFolder         $AppConfig.SourceFolder `
            -SetupFile            $AppConfig.SetupFile `
            -OutputFolder         $outputFolder `
            -IntuneWinAppUtilPath $Config.IntuneWinAppUtilPath

        # Rename to <AppName>_<Version>_<Type>.intunewin for easy identification
        $safeName    = ($AppConfig.DisplayName -replace '[^\w]', '_') -replace '_+', '_'
        $safeVersion = if ($AppConfig.Version)  { ($AppConfig.Version -replace '[^\w\.\-]', '_') } else { 'NoVersion' }
        $appType     = if ($AppConfig.IsPSADT)  { 'PSADT' } else { 'Win32' }
        $renamedFile = Join-Path $outputFolder "${safeName}_${safeVersion}_${appType}.intunewin"

        if (Test-Path $renamedFile) { Remove-Item $renamedFile -Force }
        Rename-Item -Path $intunewinPath -NewName (Split-Path $renamedFile -Leaf)
        $intunewinPath = $renamedFile
        Write-Host "  [OK] Package renamed: $(Split-Path $intunewinPath -Leaf)" -ForegroundColor Green

        # Patch the inner ZIP so the Intune portal shows the correct filename instead of "IntunePackage.intunewin"
        $innerName = Split-Path $intunewinPath -Leaf
        Update-IntunewinPackageName -IntunewinPath $intunewinPath -DesiredName $innerName
        Write-Host "  [OK] Inner content renamed: $innerName" -ForegroundColor Green

        # 2. Upload + Assign
        $intuneApp = Add-IntuneApplication `
            -AppConfig     $AppConfig `
            -IntunewinPath $intunewinPath `
            -TemplatePath  $tplPath `
            -ClientID      $Config.ClientID `
            -TenantID      $Config.TenantID

        # 3. Document
        $docsPath = $Config.DocumentationPath
        if (-not $docsPath) { $docsPath = Join-Path $ToolRoot 'Docs' }

        $docPath = New-AppDocumentation `
            -AppConfig         $AppConfig `
            -IntuneApp         $intuneApp `
            -DocumentationPath $docsPath `
            -IntunewinPath     $intunewinPath

        return @{ Success = $true; App = $intuneApp; DocPath = $docPath }
    }
    catch {
        return @{ Success = $false; Error = $_ }
    }
}

function ConvertFrom-AppJson {
    param([PSCustomObject]$AppJson)

    $cfg = @{}
    $AppJson.PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value }

    # Normalise nested objects (PSCustomObject → hashtable)
    foreach ($key in @('Detection','Assignment','Requirements','RequirementScript')) {
        if ($cfg[$key] -is [PSCustomObject]) {
            $h = @{}
            $cfg[$key].PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
            $cfg[$key] = $h
        }
    }

    # Flatten Requirements into top-level fields
    if ($cfg.Requirements) {
        if (-not $cfg.Architecture)                   { $cfg.Architecture = $cfg.Requirements.Architecture }
        if (-not $cfg.MinimumSupportedWindowsRelease) { $cfg.MinimumSupportedWindowsRelease = $cfg.Requirements.MinimumOS }
    }

    # Validate source folder
    if (-not $cfg.SourceFolder -or -not (Test-Path $cfg.SourceFolder)) {
        Write-Warning "SourceFolder missing or invalid: $($cfg.SourceFolder)"
        return $null
    }

    # Auto-fill from PSADT v4 for flagged apps
    if ($cfg.IsPSADT) {
        $meta = Get-PSADTMetadata -SourceFolder $cfg.SourceFolder
        if ($meta) {
            if (-not $cfg.SetupFile)            { $cfg.SetupFile            = $meta.SetupFile }
            if (-not $cfg.DisplayName)          { $cfg.DisplayName          = $meta.AppName }
            if (-not $cfg.Version)              { $cfg.Version              = $meta.AppVersion }
            if (-not $cfg.Publisher)            { $cfg.Publisher            = $meta.AppVendor }
            if (-not $cfg.Author)               { $cfg.Author               = $meta.AppScriptAuthor }
            if (-not $cfg.InstallCommandLine)   { $cfg.InstallCommandLine   = $meta.InstallCommandLine }
            if (-not $cfg.UninstallCommandLine) { $cfg.UninstallCommandLine = $meta.UninstallCommandLine }
            if (-not $cfg.InternalNote)         { $cfg.InternalNote         = "PSADT v4 package ($($meta.AppName))" }
        }
    }

    # Required field check
    $missing = @()
    if (-not $cfg.DisplayName)          { $missing += 'DisplayName' }
    if (-not $cfg.SetupFile)            { $missing += 'SetupFile' }
    if (-not $cfg.InstallCommandLine)   { $missing += 'InstallCommandLine' }
    if (-not $cfg.UninstallCommandLine) { $missing += 'UninstallCommandLine' }
    if (-not $cfg.Detection)            { $missing += 'Detection' }

    if ($missing.Count -gt 0) {
        Write-Warning "App '$($cfg.DisplayName ?? $cfg.SourceFolder)' missing: $($missing -join ', ')"
        return $null
    }

    return $cfg
}
#endregion

#region Headless bulk mode (no GUI)
if ($BulkFile) {
    if (-not (Test-Path $BulkFile)) {
        Write-Error "Bulk file not found: $BulkFile"
        exit 1
    }

    Write-Host "`nIntune Win32 App Uploader — Bulk Mode" -ForegroundColor Cyan
    Write-Host "File: $BulkFile`n" -ForegroundColor Gray

    Import-Module IntuneWin32App -Force
    Connect-MSIntuneGraph -TenantID $config.TenantID -ClientID $config.ClientID -Interactive

    $apps = Get-Content $BulkFile -Raw | ConvertFrom-Json
    if ($apps -isnot [array]) { $apps = @($apps) }

    $ok = 0; $fail = 0; $idx = 0
    foreach ($appJson in $apps) {
        $idx++
        $appConfig = ConvertFrom-AppJson -AppJson $appJson
        if (-not $appConfig) { $fail++; continue }

        Write-Host "[$idx/$($apps.Count)] $($appConfig.DisplayName)" -ForegroundColor White
        $result = Invoke-ProcessApp -AppConfig $appConfig -Config $config -TemplateFolder $templateFolder

        if ($result.Success) {
            Write-Host "  OK — App ID: $($result.App.id)" -ForegroundColor Green
            $ok++
        }
        else {
            Write-Host "  FAILED — $($result.Error)" -ForegroundColor Red
            $fail++
        }
    }

    Write-Host "`nDone: $ok succeeded, $fail failed`n" -ForegroundColor $(if ($fail -gt 0) { 'Yellow' } else { 'Green' })
    exit 0
}
#endregion

#region Apply module patches (runs before any Import-Module IntuneWin32App)
$patched = Repair-IntuneWin32AppModule
if ($patched) {
    Write-Host '[OK] IntuneWin32App module patched (locale DateTime fix applied to all installed versions).' -ForegroundColor Green
    # Force unload so the connect button's Import-Module -Force picks up the patched file
    Remove-Module IntuneWin32App -Force -ErrorAction SilentlyContinue
}
#endregion

#region Launch GUI
Show-MainWindow -Config $config -TemplateFolder $templateFolder -ToolRoot $ToolRoot
#endregion
