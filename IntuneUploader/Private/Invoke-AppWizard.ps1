<#
.SYNOPSIS
    Interactive wizard that collects all information needed to package and upload
    a single Win32 application to Intune.

.DESCRIPTION
    Walks the user through:
      1. Source folder selection
      2. PSADT auto-detection and metadata parsing (v3/v4)
      3. Template selection
      4. Metadata confirmation/override
      5. Logo selection
      6. Detection method configuration
      7. Requirement rules
      8. Assignment
      9. Preview and confirm

    Returns a fully populated AppConfig hashtable ready for Add-IntuneApplication
    and New-IntunePackage, or $null if the user cancels.
#>

function Invoke-AppWizard {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Pre-populated values for bulk/automation use (any missing will be prompted)
        [hashtable]$Defaults = @{},
        [string]$TemplateFolder,
        [string]$DefaultOutputPath,
        [string]$DefaultTemplate = 'PSADT-Default'
    )

    Add-Type -AssemblyName System.Windows.Forms | Out-Null

    #region UI Helpers

    function Read-HostDefault {
        param([string]$Prompt, [string]$Default = '', [switch]$AllowEmpty)
        if ($Default) { $displayPrompt = "$Prompt [default: $Default]" }
        else          { $displayPrompt = $Prompt }
        $val = Read-Host $displayPrompt
        if ([string]::IsNullOrWhiteSpace($val)) {
            if ($Default)     { return $Default }
            if ($AllowEmpty)  { return '' }
            # Re-prompt once
            $val = Read-Host $displayPrompt
            if ([string]::IsNullOrWhiteSpace($val) -and $AllowEmpty) { return '' }
        }
        return $val.Trim()
    }

    function Show-Menu {
        param([string]$Title, [string[]]$Options)
        Write-Host "`n  $Title" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host "    [$($i+1)] $($Options[$i])"
        }
        do {
            $choice = Read-Host '  Choose'
            $idx = [int]$choice - 1
        } while ($idx -lt 0 -or $idx -ge $Options.Count)
        return $idx
    }

    function Browse-Folder {
        param([string]$Description = 'Select folder', [string]$InitialPath = '')
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $Description
        $dlg.ShowNewFolderButton = $false
        if ($InitialPath -and (Test-Path $InitialPath)) { $dlg.SelectedPath = $InitialPath }
        $result = $dlg.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
        return $null
    }

    function Browse-File {
        param([string]$Title = 'Select file', [string]$Filter = 'All files (*.*)|*.*', [string]$InitialDir = '')
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = $Title
        $dlg.Filter = $Filter
        if ($InitialDir -and (Test-Path $InitialDir)) { $dlg.InitialDirectory = $InitialDir }
        $result = $dlg.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
        return $null
    }

    function Write-WizardStep {
        param([int]$Step, [int]$Total, [string]$Name)
        Write-Host "`n  --- Step $Step of $Total : $Name ---" -ForegroundColor Cyan
    }

    #endregion

    $cfg = @{}
    $totalSteps = 9

    #---------------------------------------------------------------------------
    # STEP 1 - Source folder
    #---------------------------------------------------------------------------
    Write-WizardStep 1 $totalSteps 'Source Folder'

    if ($Defaults.SourceFolder -and (Test-Path $Defaults.SourceFolder)) {
        $sourceFolder = $Defaults.SourceFolder
        Write-Host "  Using: $sourceFolder" -ForegroundColor Gray
    }
    else {
        Write-Host '  Select the application source folder (browse dialog opening...)' -ForegroundColor Gray
        $sourceFolder = Browse-Folder -Description 'Select application source folder'
        if (-not $sourceFolder) {
            Write-Host '  Cancelled.' -ForegroundColor Yellow
            return $null
        }
    }
    $cfg.SourceFolder = $sourceFolder

    #---------------------------------------------------------------------------
    # STEP 2 - PSADT detection and metadata
    #---------------------------------------------------------------------------
    Write-WizardStep 2 $totalSteps 'Application Type & Metadata'

    $isPSADT = $false
    $psadtMeta = $null

    # Auto-detect PSADT
    $hasV4 = Test-Path (Join-Path $sourceFolder 'Invoke-AppDeployToolkit.ps1')
    $hasV3 = Test-Path (Join-Path $sourceFolder 'Deploy-Application.ps1')

    if ($hasV4 -or $hasV3) {
        Write-Host "  PSADT package detected ($( if ($hasV4) {'v4'} else {'v3'} ))." -ForegroundColor Green
        $answer = Read-HostDefault -Prompt '  Use PSADT template and auto-fill metadata? (Y/N)' -Default 'Y'
        $isPSADT = $answer -match '^[Yy]'
    }
    else {
        $answer = Read-HostDefault -Prompt '  Is this a PSADT package? (Y/N)' -Default 'N'
        $isPSADT = $answer -match '^[Yy]'
    }

    $cfg.IsPSADT = $isPSADT

    if ($isPSADT) {
        Write-Host '  Parsing PSADT metadata...' -ForegroundColor Gray
        $psadtMeta = Get-PSADTMetadata -SourceFolder $sourceFolder
        if ($psadtMeta) {
            Write-Host "  Found: $($psadtMeta.AppVendor) $($psadtMeta.AppName) $($psadtMeta.AppVersion) [$($psadtMeta.PSADTVersion)]" -ForegroundColor Green
            $cfg.PSADTVersion     = $psadtMeta.PSADTVersion
            $cfg.SetupFile        = $psadtMeta.SetupFile
        }
        else {
            Write-Host '  [!] Could not parse PSADT metadata - you will be prompted for all fields.' -ForegroundColor Yellow
            $isPSADT = $false
            $cfg.IsPSADT = $false
        }
    }

    # Setup file (non-PSADT or override)
    if (-not $cfg.SetupFile) {
        if ($Defaults.SetupFile) {
            $cfg.SetupFile = $Defaults.SetupFile
        }
        else {
            $sfAnswer = Read-HostDefault -Prompt '  Setup file name (relative to source folder)' -Default 'setup.exe'
            $cfg.SetupFile = $sfAnswer
        }
    }

    #---------------------------------------------------------------------------
    # STEP 3 - Template
    #---------------------------------------------------------------------------
    Write-WizardStep 3 $totalSteps 'Template'

    $templates = @()
    if ($TemplateFolder -and (Test-Path $TemplateFolder)) {
        $templates = Get-ChildItem -Path $TemplateFolder -Filter '*.json' |
                     Select-Object -ExpandProperty BaseName
    }

    if ($Defaults.Template -and $templates -contains $Defaults.Template) {
        $selectedTemplate = $Defaults.Template
        Write-Host "  Using template: $selectedTemplate" -ForegroundColor Gray
    }
    elseif ($templates.Count -gt 0) {
        $tplDefault = if ($isPSADT) { 'PSADT-Default' } else { 'Generic-Default' }
        if ($templates -notcontains $tplDefault) { $tplDefault = $templates[0] }

        $tplIdx = Show-Menu -Title 'Select template' -Options $templates
        $selectedTemplate = $templates[$tplIdx]
    }
    else {
        $selectedTemplate = if ($isPSADT) { 'PSADT-Default' } else { 'Generic-Default' }
        Write-Host "  No templates found - using default name: $selectedTemplate" -ForegroundColor Yellow
    }

    $cfg.Template = $selectedTemplate

    # Load template JSON
    $templateData = $null
    $templatePath = Join-Path $TemplateFolder "$selectedTemplate.json"
    if (Test-Path $templatePath) {
        $templateData = Get-Content $templatePath -Raw | ConvertFrom-Json
    }

    #---------------------------------------------------------------------------
    # STEP 4 - Metadata confirmation/override
    #---------------------------------------------------------------------------
    Write-WizardStep 4 $totalSteps 'Application Metadata'
    Write-Host '  Press Enter to accept values in [brackets].' -ForegroundColor Gray

    function Get-MetaDefault {
        param([string]$Key, [string]$PSADTKey = '')
        $v = ''
        if ($Defaults.$Key)                         { $v = $Defaults.$Key }
        if (-not $v -and $PSADTKey -and $psadtMeta) { $v = $psadtMeta.$PSADTKey }
        return $v
    }

    $cfg.DisplayName  = Read-HostDefault -Prompt '  Display Name'  -Default (Get-MetaDefault 'DisplayName' 'AppName')
    $cfg.Version      = Read-HostDefault -Prompt '  Version'       -Default (Get-MetaDefault 'Version' 'AppVersion') -AllowEmpty
    $cfg.Publisher    = Read-HostDefault -Prompt '  Publisher'     -Default (Get-MetaDefault 'Publisher' 'AppVendor') -AllowEmpty
    $cfg.Description  = Read-HostDefault -Prompt '  Description'   -Default (Get-MetaDefault 'Description') -AllowEmpty
    $cfg.Author       = Read-HostDefault -Prompt '  Author'        -Default (Get-MetaDefault 'Author' 'AppScriptAuthor') -AllowEmpty
    $cfg.Notes        = Read-HostDefault -Prompt '  Notes'         -Default (Get-MetaDefault 'Notes') -AllowEmpty

    # Install/Uninstall commands - from PSADT metadata or template
    $defaultInstall   = if ($psadtMeta) { $psadtMeta.InstallCommandLine }
                        elseif ($templateData.InstallCommandLine) { $templateData.InstallCommandLine }
                        else { '' }
    $defaultUninstall = if ($psadtMeta) { $psadtMeta.UninstallCommandLine }
                        elseif ($templateData.UninstallCommandLine) { $templateData.UninstallCommandLine }
                        else { '' }

    if ($isPSADT) {
        Write-Host "  Install command   : $defaultInstall  [PSADT default - not editable]" -ForegroundColor DarkGray
        Write-Host "  Uninstall command : $defaultUninstall  [PSADT default - not editable]" -ForegroundColor DarkGray
        $cfg.InstallCommandLine   = $defaultInstall
        $cfg.UninstallCommandLine = $defaultUninstall
    }
    else {
        $cfg.InstallCommandLine   = Read-HostDefault -Prompt '  Install command'   -Default ($Defaults.InstallCommandLine   ?? $defaultInstall)
        $cfg.UninstallCommandLine = Read-HostDefault -Prompt '  Uninstall command' -Default ($Defaults.UninstallCommandLine ?? $defaultUninstall)
    }

    #---------------------------------------------------------------------------
    # STEP 5 - Logo
    #---------------------------------------------------------------------------
    Write-WizardStep 5 $totalSteps 'Logo / Icon'

    if ($Defaults.LogoPath -and (Test-Path $Defaults.LogoPath)) {
        $cfg.LogoPath = $Defaults.LogoPath
        Write-Host "  Using logo: $($cfg.LogoPath)" -ForegroundColor Gray
    }
    else {
        $logoAnswer = Read-HostDefault -Prompt '  Browse for logo? (Y/N)' -Default 'Y'
        if ($logoAnswer -match '^[Yy]') {
            $logo = Browse-File -Title 'Select application logo' `
                                -Filter 'Image files (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg|All files (*.*)|*.*'
            $cfg.LogoPath = if ($logo) { $logo } else { '' }
        }
        else {
            $cfg.LogoPath = ''
        }
    }

    #---------------------------------------------------------------------------
    # STEP 6 - Detection method
    #---------------------------------------------------------------------------
    Write-WizardStep 6 $totalSteps 'Detection Method'

    $detectionTypes = @('PowerShell Script', 'Registry Key', 'MSI Product Code', 'File or Folder')
    $detDefault = $Defaults.Detection

    if ($detDefault -and $detDefault.Type) {
        $detTypeMap = @{ 'Script' = 0; 'Registry' = 1; 'MSI' = 2; 'File' = 3 }
        $detIdx = $detTypeMap[$detDefault.Type]
        Write-Host "  Detection type: $($detectionTypes[$detIdx]) [from defaults]" -ForegroundColor Gray
    }
    else {
        $detIdx = Show-Menu -Title 'Detection method type' -Options $detectionTypes
    }

    $detection = @{ Type = @('Script','Registry','MSI','File')[$detIdx] }

    switch ($detIdx) {
        0 {
            # PowerShell Script
            if ($detDefault.ScriptPath -and (Test-Path $detDefault.ScriptPath)) {
                $detection.ScriptPath = $detDefault.ScriptPath
                Write-Host "  Script: $($detection.ScriptPath)" -ForegroundColor Gray
            }
            else {
                Write-Host '  Browse for detection script (browse dialog opening...)' -ForegroundColor Gray
                $sPath = Browse-File -Title 'Select detection PowerShell script' `
                                     -Filter 'PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*'
                $detection.ScriptPath = if ($sPath) { $sPath } else {
                    Read-HostDefault -Prompt '  Detection script path'
                }
            }
            $sigCheck = Read-HostDefault -Prompt '  Enforce signature check? (Y/N)' -Default 'N'
            $run32    = Read-HostDefault -Prompt '  Run as 32-bit? (Y/N)'           -Default 'N'
            $detection.EnforceSignatureCheck = $sigCheck -match '^[Yy]'
            $detection.RunAs32Bit            = $run32    -match '^[Yy]'
        }
        1 {
            # Registry
            $detection.KeyPath = Read-HostDefault -Prompt '  Registry key path (e.g. HKLM:\SOFTWARE\7-Zip)' `
                                                  -Default ($detDefault.KeyPath ?? '')
            $detection.ValueName = Read-HostDefault -Prompt '  Value name (blank = check key exists)' `
                                                    -Default ($detDefault.ValueName ?? '') -AllowEmpty

            $regTypes = @('exists','doesNotExist','string','integer','version','hexadecimal')
            $regIdx   = Show-Menu -Title 'Detection rule type' -Options $regTypes
            $detection.DetectionType = $regTypes[$regIdx]

            if ($regIdx -in 2,3,4,5) {
                $detection.Operator = Read-HostDefault -Prompt '  Operator (equal, notEqual, greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual)' -Default 'equal'
                $detection.Value    = Read-HostDefault -Prompt '  Expected value'
            }
            $chk32 = Read-HostDefault -Prompt '  Check 32-bit registry on 64-bit system? (Y/N)' -Default 'N'
            $detection.Check32BitOn64System = $chk32 -match '^[Yy]'
        }
        2 {
            # MSI
            $detection.ProductCode = Read-HostDefault -Prompt '  MSI Product Code (e.g. {GUID})' `
                                                      -Default ($detDefault.ProductCode ?? '')
            $addVer = Read-HostDefault -Prompt '  Also check product version? (Y/N)' -Default 'N'
            if ($addVer -match '^[Yy]') {
                $detection.ProductVersionOperator = Read-HostDefault -Prompt '  Version operator (equal, greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual)' -Default 'greaterThanOrEqual'
                $detection.ProductVersion         = Read-HostDefault -Prompt '  Product version (e.g. 23.01.0)'
            }
        }
        3 {
            # File or Folder
            $detection.Path           = Read-HostDefault -Prompt '  Folder path (e.g. C:\Program Files\7-Zip)' `
                                                         -Default ($detDefault.Path ?? '')
            $detection.FileOrFolder   = Read-HostDefault -Prompt '  File or folder name (e.g. 7z.exe)'       `
                                                         -Default ($detDefault.FileOrFolder ?? '')
            $fileTypes = @('exists','doesNotExist','modifiedDate','createdDate','version','sizeInMBGreaterThan')
            $fileIdx   = Show-Menu -Title 'Detection rule type' -Options $fileTypes
            $detection.DetectionType  = $fileTypes[$fileIdx]

            if ($fileIdx -in 4,5) {
                $detection.Operator = Read-HostDefault -Prompt '  Operator (equal, notEqual, greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual)' -Default 'greaterThanOrEqual'
                $detection.Value    = Read-HostDefault -Prompt '  Expected value'
            }
            $chk32 = Read-HostDefault -Prompt '  Check 32-bit location on 64-bit system? (Y/N)' -Default 'N'
            $detection.Check32BitOn64System = $chk32 -match '^[Yy]'
        }
    }
    $cfg.Detection = $detection

    #---------------------------------------------------------------------------
    # STEP 7 - Requirements
    #---------------------------------------------------------------------------
    Write-WizardStep 7 $totalSteps 'Requirements'

    $archOptions    = @('x64','x86','arm64','x64x86','AllWithARM64')
    $archDefault    = $Defaults.Requirements?.Architecture ?? ($templateData?.Architecture ?? 'x64')
    $archIdx        = [array]::IndexOf($archOptions, $archDefault)
    if ($archIdx -lt 0) { $archIdx = 0 }
    Write-Host "  Architecture options: $($archOptions -join ', ')" -ForegroundColor Gray
    $archInput = Read-HostDefault -Prompt '  Architecture' -Default $archOptions[$archIdx]
    $cfg.Architecture = if ($archOptions -contains $archInput) { $archInput } else { $archOptions[$archIdx] }

    $osReleases = @(
        'W10_1607','W10_1703','W10_1709','W10_1803','W10_1809',
        'W10_1903','W10_1909','W10_2004','W10_20H2',
        'W10_21H1','W10_21H2','W10_22H2',
        'W11_21H2','W11_22H2','W11_23H2','W11_24H2,W11_25H2'
    )
    $osDefault  = $Defaults.Requirements?.MinimumOS ?? ($templateData?.MinimumSupportedWindowsRelease ?? 'W10_2004')
    Write-Host "  Min Windows: $($osReleases -join ', ')" -ForegroundColor Gray
    $osInput = Read-HostDefault -Prompt '  Minimum Windows release' -Default $osDefault
    $cfg.MinimumSupportedWindowsRelease = if ($osReleases -contains $osInput) { $osInput } else { $osDefault }

    # Optional: requirement script
    $reqScriptAnswer = Read-HostDefault -Prompt '  Add a requirement script? (Y/N)' -Default 'N'
    if ($reqScriptAnswer -match '^[Yy]') {
        $rsPath = Browse-File -Title 'Select requirement PowerShell script' `
                              -Filter 'PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*'
        if ($rsPath) {
            $reqScriptOutput   = Read-HostDefault -Prompt '  Expected output type (string, integer, float, version, dateTime, boolean)' -Default 'string'
            $reqScriptOperator = Read-HostDefault -Prompt '  Operator (equal, notEqual, greaterThan, etc.)'                           -Default 'equal'
            $reqScriptValue    = Read-HostDefault -Prompt '  Expected value'
            $cfg.RequirementScript = @{
                ScriptPath    = $rsPath
                OutputType    = $reqScriptOutput
                Operator      = $reqScriptOperator
                Value         = $reqScriptValue
                RunAs32Bit    = $false
                EnforceSignatureCheck = $false
            }
        }
    }

    #---------------------------------------------------------------------------
    # STEP 8 - Assignment
    #---------------------------------------------------------------------------
    Write-WizardStep 8 $totalSteps 'Assignment'

    $assignTypes = @('All Devices (Required)', 'All Users (Required)', 'Group (specify)', 'No assignment now')
    $asgDefault  = $Defaults.Assignment

    if ($asgDefault -and $asgDefault.Type) {
        $asgTypeMap = @{ 'AllDevices' = 0; 'AllUsers' = 1; 'Group' = 2; 'None' = 3 }
        $asgIdx = $asgTypeMap[$asgDefault.Type]
        Write-Host "  Assignment: $($assignTypes[$asgIdx]) [from defaults]" -ForegroundColor Gray
    }
    elseif ($templateData?.Assignment?.Type) {
        $asgTypeMap = @{ 'AllDevices' = 0; 'AllUsers' = 1; 'Group' = 2; 'None' = 3 }
        $asgIdx     = $asgTypeMap[$templateData.Assignment.Type]
        if ($null -eq $asgIdx) { $asgIdx = 0 }
        Write-Host "  Assignment from template: $($assignTypes[$asgIdx])" -ForegroundColor Gray
        $overrideAsg = Read-HostDefault -Prompt '  Override assignment? (Y/N)' -Default 'N'
        if ($overrideAsg -match '^[Yy]') {
            $asgIdx = Show-Menu -Title 'Assignment type' -Options $assignTypes
        }
    }
    else {
        $asgIdx = Show-Menu -Title 'Assignment type' -Options $assignTypes
    }

    $intentOptions = @('required','available','uninstall')
    $notifOptions  = @('showAll','showReboot','hideAll')

    $assignment = @{ Type = @('AllDevices','AllUsers','Group','None')[$asgIdx] }

    if ($asgIdx -lt 3) {
        $intentIdx = Show-Menu -Title 'Intent' -Options $intentOptions
        $assignment.Intent = $intentOptions[$intentIdx]

        $notifIdx = Show-Menu -Title 'Notification' -Options $notifOptions
        $assignment.Notification = $notifOptions[$notifIdx]
    }

    if ($asgIdx -eq 2) {
        # Group assignment
        Write-Host '  Searching for groups... (you can also type the Group ID directly)' -ForegroundColor Gray
        $groupSearch = Read-HostDefault -Prompt '  Group display name to search (or GUID)'
        # Resolve group name to ID at upload time (passed as GroupName for later resolution)
        $assignment.GroupName = $groupSearch
    }

    $cfg.Assignment = $assignment

    #---------------------------------------------------------------------------
    # STEP 9 - Output path and preview
    #---------------------------------------------------------------------------
    Write-WizardStep 9 $totalSteps 'Output & Confirm'

    $outputDefault = $Defaults.OutputFolder ?? $DefaultOutputPath ?? ''
    if (-not $outputDefault) {
        Write-Host '  Browse for .intunewin output folder...' -ForegroundColor Gray
        $outputPath = Browse-Folder -Description 'Select output folder for .intunewin package'
        if (-not $outputPath) {
            $outputPath = Read-HostDefault -Prompt '  Output folder path'
        }
    }
    else {
        $outputPath = Read-HostDefault -Prompt '  Output folder for .intunewin' -Default $outputDefault
    }
    $cfg.OutputFolder = $outputPath

    # Preview
    Write-Host "`n  ===== SUMMARY =====" -ForegroundColor Cyan
    Write-Host "  Name:        $($cfg.DisplayName)"
    Write-Host "  Version:     $($cfg.Version)"
    Write-Host "  Publisher:   $($cfg.Publisher)"
    Write-Host "  Author:      $($cfg.Author)"
    Write-Host "  Source:      $($cfg.SourceFolder)"
    Write-Host "  Setup file:  $($cfg.SetupFile)"
    Write-Host "  Install:     $($cfg.InstallCommandLine)"
    Write-Host "  Uninstall:   $($cfg.UninstallCommandLine)"
    Write-Host "  Template:    $($cfg.Template)"
    Write-Host "  Detection:   $($cfg.Detection.Type)"
    Write-Host "  Arch:        $($cfg.Architecture)"
    Write-Host "  Min OS:      $($cfg.MinimumSupportedWindowsRelease)"
    Write-Host "  Assignment:  $($cfg.Assignment.Type)"
    Write-Host "  Output:      $($cfg.OutputFolder)"
    Write-Host "  Logo:        $(if ($cfg.LogoPath) { $cfg.LogoPath } else { '(none)' })"
    Write-Host ''

    $confirm = Read-HostDefault -Prompt '  Proceed with packaging and upload? (Y/N)' -Default 'Y'
    if ($confirm -notmatch '^[Yy]') {
        Write-Host '  Cancelled.' -ForegroundColor Yellow
        return $null
    }

    return $cfg
}
