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
            # Module uses parameter-set switches, not a DetectionType string
            $chk = ([bool]$det.Check32BitOn64System)
            switch ($det.DetectionType) {
                { $_ -in 'exists','doesNotExist' } {
                    $p = @{ Existence = $true; KeyPath = $det.KeyPath; DetectionType = $det.DetectionType; Check32BitOn64System = $chk }
                    if ($det.ValueName) { $p.ValueName = $det.ValueName }
                    New-IntuneWin32AppDetectionRuleRegistry @p
                }
                'string' {
                    $p = @{ StringComparison = $true; KeyPath = $det.KeyPath; StringComparisonOperator = ($det.Operator ?? 'equal'); StringComparisonValue = $det.Value; Check32BitOn64System = $chk }
                    if ($det.ValueName) { $p.ValueName = $det.ValueName }
                    New-IntuneWin32AppDetectionRuleRegistry @p
                }
                'integer' {
                    $p = @{ IntegerComparison = $true; KeyPath = $det.KeyPath; IntegerComparisonOperator = ($det.Operator ?? 'equal'); IntegerComparisonValue = [string][int]$det.Value; Check32BitOn64System = $chk }
                    if ($det.ValueName) { $p.ValueName = $det.ValueName }
                    New-IntuneWin32AppDetectionRuleRegistry @p
                }
                'version' {
                    $p = @{ VersionComparison = $true; KeyPath = $det.KeyPath; VersionComparisonOperator = ($det.Operator ?? 'greaterThanOrEqual'); VersionComparisonValue = $det.Value; Check32BitOn64System = $chk }
                    if ($det.ValueName) { $p.ValueName = $det.ValueName }
                    New-IntuneWin32AppDetectionRuleRegistry @p
                }
                default { throw "Unknown registry detection type: $($det.DetectionType)" }
            }
        }
        'File' {
            # Module uses parameter-set switches, not a DetectionType string
            $chk = ([bool]$det.Check32BitOn64System)
            switch ($det.DetectionType) {
                { $_ -in 'exists','doesNotExist' } {
                    New-IntuneWin32AppDetectionRuleFile -Existence -Path $det.Path -FileOrFolder $det.FileOrFolder -DetectionType $det.DetectionType -Check32BitOn64System $chk
                }
                'version' {
                    New-IntuneWin32AppDetectionRuleFile -Version -Path $det.Path -FileOrFolder $det.FileOrFolder -Operator ($det.Operator ?? 'greaterThanOrEqual') -VersionValue $det.Value -Check32BitOn64System $chk
                }
                'size' {
                    New-IntuneWin32AppDetectionRuleFile -Size -Path $det.Path -FileOrFolder $det.FileOrFolder -Operator ($det.Operator ?? 'greaterThanOrEqual') -SizeInMBValue ([string][int]$det.Value) -Check32BitOn64System $chk
                }
                'dateModified' {
                    New-IntuneWin32AppDetectionRuleFile -DateModified -Path $det.Path -FileOrFolder $det.FileOrFolder -Operator ($det.Operator ?? 'greaterThanOrEqual') -DateTimeValue ([datetime]$det.Value) -Check32BitOn64System $chk
                }
                'dateCreated' {
                    New-IntuneWin32AppDetectionRuleFile -DateCreated -Path $det.Path -FileOrFolder $det.FileOrFolder -Operator ($det.Operator ?? 'greaterThanOrEqual') -DateTimeValue ([datetime]$det.Value) -Check32BitOn64System $chk
                }
                default { throw "Unknown file detection type: $($det.DetectionType)" }
            }
        }
        default { throw "Unknown detection type: $($det.Type)" }
    }
    #endregion

    #region Requirement Rules
    Write-Host '  [*] Building requirement rules...' -ForegroundColor Yellow

    $arch  = $AppConfig.Architecture                   ?? (Get-TplVal 'Architecture' 'x64')
    $minOS = $AppConfig.MinimumSupportedWindowsRelease ?? (Get-TplVal 'MinimumSupportedWindowsRelease' 'W10_2004')

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
                        # Module uses parameter-set switches, not a DetectionType string
                        $chk = ([bool]$rule.Check32BitOn64System)
                        switch ($rule.DetectionType) {
                            { $_ -in 'exists','doesNotExist' } {
                                $p = @{ Existence = $true; KeyPath = $rule.KeyPath; DetectionType = $rule.DetectionType; Check32BitOn64System = $chk }
                                if ($rule.ValueName) { $p.ValueName = $rule.ValueName }
                                New-IntuneWin32AppRequirementRuleRegistry @p
                            }
                            'string' {
                                $p = @{ StringComparison = $true; KeyPath = $rule.KeyPath; StringComparisonOperator = ($rule.Operator ?? 'equal'); StringComparisonValue = $rule.Value; Check32BitOn64System = $chk }
                                if ($rule.ValueName) { $p.ValueName = $rule.ValueName }
                                New-IntuneWin32AppRequirementRuleRegistry @p
                            }
                            'integer' {
                                $p = @{ IntegerComparison = $true; KeyPath = $rule.KeyPath; IntegerComparisonOperator = ($rule.Operator ?? 'equal'); IntegerComparisonValue = [string][int]$rule.Value; Check32BitOn64System = $chk }
                                if ($rule.ValueName) { $p.ValueName = $rule.ValueName }
                                New-IntuneWin32AppRequirementRuleRegistry @p
                            }
                            'version' {
                                $p = @{ VersionComparison = $true; KeyPath = $rule.KeyPath; VersionComparisonOperator = ($rule.Operator ?? 'greaterThanOrEqual'); VersionComparisonValue = $rule.Value; Check32BitOn64System = $chk }
                                if ($rule.ValueName) { $p.ValueName = $rule.ValueName }
                                New-IntuneWin32AppRequirementRuleRegistry @p
                            }
                            default { Write-Warning "Unknown registry requirement type: $($rule.DetectionType)"; $null }
                        }
                    }
                    'File' {
                        # Module uses parameter-set switches, not a DetectionType string
                        $chk = ([bool]$rule.Check32BitOn64System)
                        switch ($rule.DetectionType) {
                            { $_ -in 'exists','doesNotExist' } {
                                New-IntuneWin32AppRequirementRuleFile -Existence -Path $rule.Path -FileOrFolder $rule.FileOrFolder -DetectionType $rule.DetectionType -Check32BitOn64System $chk
                            }
                            'version' {
                                New-IntuneWin32AppRequirementRuleFile -Version -Path $rule.Path -FileOrFolder $rule.FileOrFolder -Operator ($rule.Operator ?? 'greaterThanOrEqual') -VersionValue $rule.Value -Check32BitOn64System $chk
                            }
                            'size' {
                                New-IntuneWin32AppRequirementRuleFile -Size -Path $rule.Path -FileOrFolder $rule.FileOrFolder -Operator ($rule.Operator ?? 'greaterThanOrEqual') -SizeInMBValue ([string][int]$rule.Value) -Check32BitOn64System $chk
                            }
                            default { Write-Warning "Unknown file requirement type: $($rule.DetectionType)"; $null }
                        }
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

    # The IntuneWin32App module performs date arithmetic on $Global:AuthenticationHeader.ExpiresOn
    # using DateTime.Parse(string, InvariantCulture). On non-US locales (e.g. en-GB) the value
    # may have been coerced to a locale-format string ('13/04/2026 16:25:40') which InvariantCulture
    # cannot parse (month=13 invalid). Ensure it is always a proper UTC DateTime before the call.
    if ($Global:AuthenticationHeader) {
        $eo = $Global:AuthenticationHeader.ExpiresOn
        if ($eo -is [string]) {
            try   { $Global:AuthenticationHeader.ExpiresOn = [datetime]::Parse($eo, [System.Globalization.CultureInfo]::CurrentCulture) }
            catch { $Global:AuthenticationHeader.ExpiresOn = [datetime]::UtcNow.AddHours(1) }
        } elseif ($eo -is [System.DateTimeOffset]) {
            $Global:AuthenticationHeader.ExpiresOn = $eo.UtcDateTime
        }
    }

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
    # Assignments are made directly via the Graph API rather than through the module's
    # assignment cmdlets, because those cmdlets hardcode filter fields to null/"none"
    # and offer no way to pass FilterID/FilterIntent regardless of module version.
    $asg = $AppConfig.Assignment
    if ($asg -and $asg.Type -ne 'None') {
        Write-Host "  [*] Configuring assignment: $($asg.Type)..." -ForegroundColor Yellow

        $intent  = $asg.Intent       ?? 'required'
        $notif   = $asg.Notification ?? 'showAll'

        # Resolve group ID if only a name was given
        $groupId = $asg.GroupID
        if ($asg.Type -eq 'Group' -and -not $groupId -and $asg.GroupName) {
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

        if ($asg.Type -eq 'Group' -and -not $groupId) {
            Write-Warning "No group ID — assignment skipped. Assign manually in Intune."
        }
        else {
            # Build the assignment target
            $targetOdata = switch ($asg.Type) {
                'AllDevices' { '#microsoft.graph.allDevicesAssignmentTarget' }
                'AllUsers'   { '#microsoft.graph.allLicensedUsersAssignmentTarget' }
                'Group'      { '#microsoft.graph.groupAssignmentTarget' }
            }
            $target = [ordered]@{
                '@odata.type'                                    = $targetOdata
                'deviceAndAppManagementAssignmentFilterId'       = if ($asg.FilterID)     { $asg.FilterID }                    else { $null }
                'deviceAndAppManagementAssignmentFilterType'     = if ($asg.FilterID)     { $asg.FilterIntent ?? 'include' }   else { 'none' }
            }
            if ($asg.Type -eq 'Group') { $target['groupId'] = $groupId }

            $assignBody = [ordered]@{
                '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                'intent'      = $intent
                'source'      = 'direct'
                'target'      = $target
                'settings'    = [ordered]@{
                    '@odata.type'                  = '#microsoft.graph.win32LobAppAssignmentSettings'
                    'notifications'                = $notif
                    'installTimeSettings'          = $null
                    'restartSettings'              = $null
                    'deliveryOptimizationPriority' = 'notConfigured'
                }
            }

            Invoke-TenantGraphRequest `
                -Url    "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$($intuneApp.id)/assignments" `
                -Method POST `
                -Body   $assignBody `
                -ClientID $ClientID -TenantID $TenantID | Out-Null

            Write-Host "  [OK] Assignment configured." -ForegroundColor Green
        }
    }
    #endregion

    return $intuneApp
}
