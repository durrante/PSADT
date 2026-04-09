<#
.SYNOPSIS
    Uploads a Win32 application to Intune and configures assignments.

.DESCRIPTION
    Handles all Intune upload concerns:
      - Detection rule (Script / MSI / Registry / File)
      - Base requirement rule (architecture + min OS)
      - Additional requirement rules (Script / Registry / File — multiple)
      - Logo base64 encoding
      - App upload via Add-IntuneWin32App
      - Assignment (AllDevices / AllUsers / Group) with optional filter
      - Category assignment

    AppConfig fields used:
        DisplayName, Version, Publisher, Owner, Description, Notes,
        InformationURL, PrivacyURL, Categories (string[]),
        InstallCommandLine, UninstallCommandLine, InstallExperience, RestartBehavior,
        Detection, Architecture, MinimumSupportedWindowsRelease,
        AdditionalRequirementRules (hashtable[]),
        LogoPath, Assignment { Type, Intent, Notification, GroupName, GroupID,
                               FilterID, FilterIntent }
#>

function Add-IntuneApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AppConfig,

        [Parameter(Mandatory)]
        [string]$IntunewinPath,

        [string]$TemplatePath = '',

        # Needed for Graph calls (group resolution, filter assignment)
        [string]$ClientID = '',
        [string]$TenantID = ''
    )

    #region Template helper
    $template = $null
    if ($TemplatePath -and (Test-Path $TemplatePath)) {
        $template = Get-Content $TemplatePath -Raw | ConvertFrom-Json
    }
    function Get-TplVal {
        param([string]$Key, $Fallback)
        if ($template -and $null -ne $template.$Key -and $template.$Key -ne '') { return $template.$Key }
        return $Fallback
    }
    #endregion

    #region Detection Rule
    Write-Host '  [*] Building detection rule...' -ForegroundColor Yellow
    $det = $AppConfig.Detection
    $detectionRule = switch ($det.Type) {
        'Script' {
            if (-not (Test-Path $det.ScriptPath)) { throw "Detection script not found: $($det.ScriptPath)" }
            New-IntuneWin32AppDetectionRuleScript `
                -ScriptFile            $det.ScriptPath `
                -EnforceSignatureCheck ([bool]$det.EnforceSignatureCheck) `
                -RunAs32Bit            ([bool]$det.RunAs32Bit)
        }
        'MSI' {
            $p = @{ ProductCode = $det.ProductCode }
            if ($det.ProductVersion) {
                $p.ProductVersionOperator = $det.ProductVersionOperator ?? 'greaterThanOrEqual'
                $p.ProductVersion         = $det.ProductVersion
            }
            New-IntuneWin32AppDetectionRuleMSI @p
        }
        'Registry' {
            $p = @{
                KeyPath              = $det.KeyPath
                DetectionType        = $det.DetectionType
                Check32BitOn64System = ([bool]$det.Check32BitOn64System)
            }
            if ($det.ValueName)  { $p.ValueName = $det.ValueName }
            if ($det.DetectionType -eq 'string') {
                $p.StringComparisonOperator = $det.Operator ?? 'equal'
                $p.StringValue              = $det.Value
            }
            elseif ($det.DetectionType -eq 'integer') {
                $p.IntegerComparisonOperator = $det.Operator ?? 'equal'
                $p.IntegerValue              = [int]$det.Value
            }
            elseif ($det.DetectionType -eq 'version') {
                $p.VersionComparisonOperator = $det.Operator ?? 'greaterThanOrEqual'
                $p.VersionValue              = $det.Value
            }
            New-IntuneWin32AppDetectionRuleRegistry @p
        }
        'File' {
            $p = @{
                Path                 = $det.Path
                FileOrFolder         = $det.FileOrFolder
                DetectionType        = $det.DetectionType
                Check32BitOn64System = ([bool]$det.Check32BitOn64System)
            }
            if ($det.DetectionType -notin 'exists','doesNotExist') {
                $p.Operator = $det.Operator ?? 'greaterThanOrEqual'
                $p.Value    = $det.Value
            }
            New-IntuneWin32AppDetectionRuleFile @p
        }
        default { throw "Unknown detection type: $($det.Type)" }
    }
    #endregion

    #region Requirement Rules
    Write-Host '  [*] Building requirement rules...' -ForegroundColor Yellow

    $arch  = $AppConfig.Architecture                       ?? (Get-TplVal 'Architecture' 'x64')
    $minOS = $AppConfig.MinimumSupportedWindowsRelease     ?? (Get-TplVal 'MinimumSupportedWindowsRelease' 'W10_2004')

    $requirementRule = New-IntuneWin32AppRequirementRule `
        -Architecture                   $arch `
        -MinimumSupportedWindowsRelease $minOS

    # Additional requirement rules (script, registry, file)
    $additionalRequirements = [System.Collections.Generic.List[object]]::new()

    $extraRules = $AppConfig.AdditionalRequirementRules
    if ($extraRules) {
        foreach ($rule in $extraRules) {
            try {
                $reqRule = switch ($rule.Type) {
                    'Script' {
                        if (-not (Test-Path $rule.ScriptPath)) {
                            Write-Warning "Requirement script not found, skipping: $($rule.ScriptPath)"
                            continue
                        }
                        New-IntuneWin32AppRequirementRuleScript `
                            -ScriptFile            $rule.ScriptPath `
                            -OutputDataType        $rule.OutputDataType `
                            -Operator              $rule.Operator `
                            -Value                 $rule.Value `
                            -RunAs32Bit            ([bool]$rule.RunAs32Bit) `
                            -EnforceSignatureCheck ([bool]$rule.EnforceSignatureCheck) `
                            -RunAsAccount          'system'
                    }
                    'Registry' {
                        $p = @{
                            KeyPath              = $rule.KeyPath
                            DetectionType        = $rule.DetectionType
                            Check32BitOn64System = ([bool]$rule.Check32BitOn64System)
                        }
                        if ($rule.ValueName) { $p.ValueName = $rule.ValueName }
                        if ($rule.DetectionType -eq 'string') {
                            $p.StringComparisonOperator = $rule.Operator ?? 'equal'
                            $p.StringValue              = $rule.Value
                        }
                        elseif ($rule.DetectionType -eq 'integer') {
                            $p.IntegerComparisonOperator = $rule.Operator ?? 'equal'
                            $p.IntegerValue              = [int]$rule.Value
                        }
                        elseif ($rule.DetectionType -eq 'version') {
                            $p.VersionComparisonOperator = $rule.Operator ?? 'greaterThanOrEqual'
                            $p.VersionValue              = $rule.Value
                        }
                        New-IntuneWin32AppRequirementRuleRegistry @p
                    }
                    'File' {
                        $p = @{
                            Path                 = $rule.Path
                            FileOrFolder         = $rule.FileOrFolder
                            DetectionType        = $rule.DetectionType
                            Check32BitOn64System = ([bool]$rule.Check32BitOn64System)
                        }
                        if ($rule.DetectionType -notin 'exists','doesNotExist') {
                            $p.Operator = $rule.Operator ?? 'greaterThanOrEqual'
                            $p.Value    = $rule.Value
                        }
                        New-IntuneWin32AppRequirementRuleFile @p
                    }
                    default { Write-Warning "Unknown requirement rule type: $($rule.Type)"; $null }
                }
                if ($reqRule) { $additionalRequirements.Add($reqRule) }
            }
            catch {
                Write-Warning "Could not build requirement rule ($($rule.Type)): $_"
            }
        }
    }
    #endregion

    #region Icon
    $iconBase64 = $null
    if ($AppConfig.LogoPath -and (Test-Path $AppConfig.LogoPath)) {
        Write-Host '  [*] Converting logo...' -ForegroundColor Yellow
        try {
            if (Get-Command New-IntuneWin32AppIcon -ErrorAction SilentlyContinue) {
                $iconBase64 = New-IntuneWin32AppIcon -FilePath $AppConfig.LogoPath
            }
            else {
                $iconBase64 = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($AppConfig.LogoPath))
            }
        }
        catch { Write-Warning "Could not convert logo: $_" }
    }
    #endregion

    #region Return Codes
    $returnCodes = @()
    $tplRC = Get-TplVal 'ReturnCodes' $null
    if ($tplRC) {
        foreach ($rc in $tplRC) {
            $returnCodes += New-IntuneWin32AppReturnCode -ReturnCode $rc.ReturnCode -Type $rc.Type
        }
    }
    else {
        $returnCodes += New-IntuneWin32AppReturnCode -ReturnCode 0    -Type success
        $returnCodes += New-IntuneWin32AppReturnCode -ReturnCode 1707 -Type success
        $returnCodes += New-IntuneWin32AppReturnCode -ReturnCode 3010 -Type softReboot
        $returnCodes += New-IntuneWin32AppReturnCode -ReturnCode 1641 -Type hardReboot
        $returnCodes += New-IntuneWin32AppReturnCode -ReturnCode 1618 -Type retry
    }
    #endregion

    #region Upload
    Write-Host '  [*] Uploading to Intune...' -ForegroundColor Yellow

    $installExp  = $AppConfig.InstallExperience ?? (Get-TplVal 'InstallExperience' 'system')
    $restartBeh  = $AppConfig.RestartBehavior   ?? (Get-TplVal 'RestartBehavior'   'suppress')
    $maxTime     = Get-TplVal 'MaximumInstallationTimeInMinutes' 60

    $appParams = @{
        FilePath                          = $IntunewinPath
        DisplayName                       = $AppConfig.DisplayName
        Description                       = if ($AppConfig.Description) { $AppConfig.Description } else { $AppConfig.DisplayName }
        Publisher                         = $AppConfig.Publisher         ?? ''
        AppVersion                        = $AppConfig.Version           ?? ''
        Owner                             = $AppConfig.Owner             ?? ''
        Notes                             = $AppConfig.Notes             ?? ''
        InstallCommandLine                = $AppConfig.InstallCommandLine
        UninstallCommandLine              = $AppConfig.UninstallCommandLine
        InstallExperience                 = $installExp
        RestartBehavior                   = $restartBeh
        MaximumInstallationTimeInMinutes  = [int]$maxTime
        DetectionRule                     = $detectionRule
        RequirementRule                   = $requirementRule
        ReturnCode                        = $returnCodes
    }

    if ($additionalRequirements.Count -gt 0) {
        $appParams.AdditionalRequirementRule = $additionalRequirements.ToArray()
    }
    if ($iconBase64)                    { $appParams.Icon = $iconBase64 }
    if ($AppConfig.InformationURL)      { $appParams.InformationURL = $AppConfig.InformationURL }
    if ($AppConfig.PrivacyURL)          { $appParams.PrivacyURL     = $AppConfig.PrivacyURL }
    if ((Get-TplVal 'AllowAvailableUninstall' $false)) { $appParams.AllowAvailableUninstall = $true }

    # Categories
    $cats = $AppConfig.Categories
    if ($cats -and $cats.Count -gt 0) {
        $appParams.CategoryName = [string[]]$cats
    }

    $intuneApp = Add-IntuneWin32App @appParams

    if (-not $intuneApp -or -not $intuneApp.id) {
        throw "Upload failed — no App ID returned from Intune"
    }
    Write-Host "  [OK] App uploaded: $($intuneApp.displayName)  (ID: $($intuneApp.id))" -ForegroundColor Green
    #endregion

    #region Assignment
    $asg = $AppConfig.Assignment
    if ($asg -and $asg.Type -ne 'None') {
        Write-Host "  [*] Configuring assignment: $($asg.Type)..." -ForegroundColor Yellow

        $intent  = $asg.Intent       ?? 'required'
        $notif   = $asg.Notification ?? 'showAll'

        # Build optional filter params (supported in IntuneWin32App 1.4+)
        $filterParams = @{}
        if ($asg.FilterID) {
            $filterParams.FilterID     = $asg.FilterID
            $filterParams.FilterIntent = $asg.FilterIntent ?? 'include'
        }

        switch ($asg.Type) {
            'AllDevices' {
                Add-IntuneWin32AppAssignmentAllDevices `
                    -ID           $intuneApp.id `
                    -Intent       $intent `
                    -Notification $notif `
                    @filterParams
            }
            'AllUsers' {
                Add-IntuneWin32AppAssignmentAllUsers `
                    -ID           $intuneApp.id `
                    -Intent       $intent `
                    -Notification $notif `
                    @filterParams
            }
            'Group' {
                $groupId = $asg.GroupID
                if (-not $groupId -and $asg.GroupName) {
                    Write-Host "    Resolving group: '$($asg.GroupName)'..." -ForegroundColor Gray
                    try {
                        $res = Invoke-TenantGraphRequest `
                            -Url "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$($asg.GroupName)'&`$select=id,displayName" `
                            -ClientID $ClientID -TenantID $TenantID
                        if ($res.value.Count -eq 1) {
                            $groupId = $res.value[0].id
                            Write-Host "    Resolved: $($res.value[0].displayName) ($groupId)" -ForegroundColor Gray
                        }
                        else {
                            Write-Warning "Could not uniquely resolve group '$($asg.GroupName)' — skipping assignment."
                        }
                    }
                    catch { Write-Warning "Group lookup failed: $_" }
                }

                if ($groupId) {
                    Add-IntuneWin32AppAssignmentGroup `
                        -ID           $intuneApp.id `
                        -Target       'Group' `
                        -GroupID      $groupId `
                        -Intent       $intent `
                        -Notification $notif `
                        @filterParams
                }
                else {
                    Write-Warning "No group ID — assignment skipped. Assign manually in Intune."
                }
            }
        }
        Write-Host "  [OK] Assignment configured." -ForegroundColor Green
    }
    #endregion

    return $intuneApp
}
