<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of an application(s).
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

Silent mode is automatically set if it is detected that the process is not user interactive, no users are logged on, the device is in Autopilot mode, or there's specified processes to close that are currently running.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$adtSession = @{
    # App variables.
    AppVendor = 'Notion Labs, Inc'
    AppName = 'Notion'
    AppVersion = 'Latest'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(
        @{ Name = 'Notion'; Description = 'Notion' }
    )
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-09-18'
    AppScriptAuthor = 'Alex Durrant'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = ''
    InstallTitle = ''

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

##================================================
## MARK: Notion helpers
##================================================
## Notion is a per-user application. Every installer in the WinGet manifest for the normal Notion build is
## "Scope: user", it installs into %LocalAppData%\Programs\Notion and registers itself in HKCU. There is no
## machine-wide build of it. (WinGet does have an MSIX for Notion, which "--scope machine" selects, but that is a
## different, packaged build that does not update itself, so this package deliberately uses the normal one.)
##
## This package is deployed as SYSTEM and installs Notion for every user:
## - Users logged on at install time get it straight away, because Install-NotionForUser.ps1 is run in each of
##   their sessions.
## - Everyone else gets it at their next logon, from an HKLM Run value pointing at the same script.
## Notion then keeps itself updated per user.
##
## Intune detection is the machine-wide part of this package (the tag key and the logon script), not Notion
## itself, since Notion lives in each user's profile.

## The WinGet package ID ("Notion.Notion") lives in Install-NotionForUser.ps1, because that is where the install
## actually runs. It is deliberately not repeated here.
$appUserInstallRoot = 'AppData\Local\Programs\Notion'
$appUserScriptName = 'Install-NotionForUser.ps1'
$appUserScriptFolder = "$env:ProgramFiles\PSADTPackages\Notion"
$appUserScriptPath = "$appUserScriptFolder\$appUserScriptName"
$appRunValueName = 'NotionUserInstall'
$appUserMarkerKey = 'HKCU\Software\PSADTPackages\Notion Labs, Inc\Notion'
$appPowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$appUserScriptArguments = @('-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $appUserScriptPath)

## Paths relative to each profile folder, for Remove-ADTFileFromUserProfiles. That function joins them to the
## profile folder and does not look up the real desktop location, so the OneDrive* wildcard covers desktops
## redirected by Known Folder Move.
$appUserFolders = @(
    'AppData\Local\Programs\Notion'
    'AppData\Local\notion-updater'
    'AppData\Roaming\Notion'
)
$appDesktopShortcuts = @(
    'Desktop\Notion.lnk'
    'OneDrive*\Desktop\Notion.lnk'
)
$appStartMenuShortcuts = @('AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Notion.lnk')

function Get-NotionSessionUser
{
    <#
    .SYNOPSIS
    Returns the users logged on right now, with their profile paths.

    .DESCRIPTION
    Covers active and disconnected sessions, so fast user switching and multi-session hosts are handled.
    Autopilot's temporary defaultuser accounts are skipped because they are deleted once setup finishes.
    #>
    [CmdletBinding()]
    param
    (
    )

    $userProfiles = Get-ADTUserProfiles -ExcludeDefaultUser -LoadProfilePaths
    foreach ($sessionUser in (Get-ADTLoggedOnUser | Where-Object { $_.IsValidUserSession -and $_.UserName -notlike 'defaultuser*' } | Sort-Object -Property SID -Unique))
    {
        $userProfile = $userProfiles | Where-Object { $_.SID -eq $sessionUser.SID } | Select-Object -First 1
        if (!$userProfile)
        {
            Write-ADTLogEntry -Message "Could not find a profile for logged on user [$($sessionUser.NTAccount)], skipping them." -Severity 2
            continue
        }
        [PSCustomObject]@{
            NTAccount   = $sessionUser.NTAccount
            SID         = $sessionUser.SID
            ProfilePath = $userProfile.ProfilePath
        }
    }
}

function Invoke-NotionForSessionUser
{
    <#
    .SYNOPSIS
    Runs a Notion per-user command in each logged on user's session.

    .DESCRIPTION
    As SYSTEM (Intune), the command runs as each logged on user with Start-ADTProcessAsUser. When the script is
    run by hand from an elevated prompt, it runs for the current user only, since -Username needs SYSTEM.
    Failures are logged as warnings and never fail the deployment: on install the logon script tries again at
    the user's next logon, and on uninstall the leftovers are cleaned up per profile afterwards.

    .PARAMETER FilePath
    Scriptblock that returns the exe to run, given the user's profile folder as $args[0].

    .PARAMETER ArgumentList
    Arguments for the exe.

    .PARAMETER TimeoutMinutes
    How long to give the command per user.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ScriptBlock]$FilePath,

        [Parameter(Mandatory = $false)]
        [System.String[]]$ArgumentList,

        [Parameter(Mandatory = $false)]
        [System.Int32]$TimeoutMinutes = 20
    )

    if (!$IsLocalSystemAccount)
    {
        $exePath = & $FilePath $envUserProfile
        if (!(Test-Path -LiteralPath $exePath -PathType Leaf))
        {
            Write-ADTLogEntry -Message "[$exePath] not found for [$ProcessNTAccount], nothing to run."
            return
        }
        Write-ADTLogEntry -Message "Not running as SYSTEM, so running [$exePath] for [$ProcessNTAccount] only."
        $result = Start-ADTProcess -FilePath $exePath -ArgumentList $ArgumentList -WindowStyle Hidden -IgnoreExitCodes '*' -PassThru
        Write-ADTLogEntry -Message "Exit code [$($result.ExitCode)] for [$ProcessNTAccount]."
        return
    }

    $sessionUsers = @(Get-NotionSessionUser)
    if ($sessionUsers.Count -eq 0)
    {
        Write-ADTLogEntry -Message 'No users are logged on, so there is nothing to run per user.'
        return
    }

    foreach ($sessionUser in $sessionUsers)
    {
        $exePath = & $FilePath $sessionUser.ProfilePath
        if (!(Test-Path -LiteralPath $exePath -PathType Leaf))
        {
            Write-ADTLogEntry -Message "[$exePath] not found for [$($sessionUser.NTAccount)], nothing to run."
            continue
        }

        try
        {
            Write-ADTLogEntry -Message "Running [$exePath $ArgumentList] as [$($sessionUser.NTAccount)]."
            $saipauParams = @{
                Username        = $sessionUser.NTAccount
                FilePath        = $exePath
                WindowStyle     = 'Hidden'
                Timeout         = New-TimeSpan -Minutes $TimeoutMinutes
                IgnoreExitCodes = '*'
                PassThru        = $true
            }
            if ($ArgumentList)
            {
                $saipauParams.ArgumentList = $ArgumentList
            }
            $result = Start-ADTProcessAsUser @saipauParams
            Write-ADTLogEntry -Message "Exit code [$($result.ExitCode)] for [$($sessionUser.NTAccount)]."
        }
        catch
        {
            Write-ADTLogEntry -Message "Per-user step failed for [$($sessionUser.NTAccount)]; this does not fail the deployment.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)" -Severity 2
        }
    }
}

function Install-NotionMachineComponent
{
    <#
    .SYNOPSIS
    Puts the per-user install script and its logon Run value in place.

    .DESCRIPTION
    The script goes in Program Files, not ProgramData, so standard users cannot replace a script that runs for
    every user. This is also what Intune detects, since Notion itself is per user.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = "This is an internal helper for this package's deployment phases, which are never run with -WhatIf.")]
    [CmdletBinding()]
    param
    (
    )

    New-ADTFolder -LiteralPath $appUserScriptFolder
    Copy-ADTFile -Path "$($adtSession.DirSupportFiles)\$appUserScriptName" -Destination $appUserScriptFolder
    $runCommand = "`"$appPowerShellPath`" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$appUserScriptPath`""
    Set-ADTRegistryKey -Key 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name $appRunValueName -Value $runCommand -Type String
    Write-ADTLogEntry -Message "Users who log on from now on will get Notion from [$appUserScriptPath]."
}

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, close processes if specified, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
    ## Only show the welcome prompt if there are processes that need to be closed.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams = @{
            AllowDefer              = $true
            DeferTimes              = 3
            CheckDiskSpace          = $true
            PersistPrompt           = $true
            CloseProcesses               = $adtSession.AppProcessesToClose
            ForceCloseProcessesCountdown = 900
        }
        Show-ADTInstallationWelcome @saiwParams
    }

    ## Show Progress Message (with the default message).
    if ($adtSession.DeployMode -eq 'Interactive' -and $adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationProgress
    }

    ## <Perform Pre-Installation tasks here>


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI installations.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
        if ($adtSession.DefaultMspFiles)
        {
            $adtSession.DefaultMspFiles | Start-ADTMsiProcess -Action Patch
        }
    }

    ## Ensure WinGet is operational before deploying. Running this as SYSTEM also provisions App Installer
    ## machine-wide, so WinGet is there for each user when the per-user install runs.
    Repair-ADTWinGetPackageManager

    ## Put the per-user install script and its logon Run value in place first, so a user who logs on while this
    ## is running is still covered.
    Install-NotionMachineComponent

    ## Install Notion for the users logged on now, so they don't have to log off and back on. The script runs
    ## "winget install --id Notion.Notion --scope user" in their own session, which is the only scope Notion
    ## publishes for this build.
    Invoke-NotionForSessionUser -FilePath { $appPowerShellPath } -ArgumentList $appUserScriptArguments

    ## Remove the desktop shortcut Notion's installer creates, from every profile that already has Notion: the
    ## users just installed for, plus anyone who had it before. Users who log on later have theirs removed by
    ## the per-user script, which does the same thing straight after installing.
    Remove-ADTFileFromUserProfiles -Path $appDesktopShortcuts -ExcludeDefaultUser


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Adjust the pattern below if the application creates a differently named shortcut on the desktop.
    $appDesktopIconPattern = 'Notion*.lnk'
    Remove-ADTFile -Path "$envCommonDesktop\$appDesktopIconPattern" -ErrorAction SilentlyContinue
    Update-ADTDesktop

    ## Write package tag to registry for auditing and custom detection.
    $adtRegKey = "HKLM:\SOFTWARE\PSADTPackages\$($adtSession.AppVendor)\$($adtSession.AppName)"
    Set-ADTRegistryKey -Key $adtRegKey -Name "Installed"   -Value "True"                         -Type String
    Set-ADTRegistryKey -Key $adtRegKey -Name "Version"     -Value $adtSession.AppVersion          -Type String
    Set-ADTRegistryKey -Key $adtRegKey -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd") -Type String
    Set-ADTRegistryKey -Key $adtRegKey -Name "InstalledBy" -Value "Intune / PSADT"               -Type String


}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## If there are processes to close, show Welcome Message with a 60 second countdown before automatically closing.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 900
    }

    ## Show Progress Message (with the default message).
    if ($adtSession.DeployMode -eq 'Interactive' -and $adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationProgress
    }

    ## <Perform Pre-Uninstallation tasks here>


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI uninstallations.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }

    ## Stop new users getting Notion first: remove the logon Run value and the script behind it.
    Remove-ADTRegistryKey -Key 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name $appRunValueName -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $appUserScriptFolder -PathType Container)
    {
        Remove-ADTFolder -LiteralPath $appUserScriptFolder -ErrorAction SilentlyContinue
    }

    ## Uninstall Notion for the users logged on now, as themselves, using its own uninstaller. Notion is per
    ## user, so there is nothing for Uninstall-ADTApplication to find in HKLM.
    Invoke-NotionForSessionUser -FilePath { "$($args[0])\$appUserInstallRoot\Uninstall Notion.exe" } -ArgumentList '/currentuser', '/S' -TimeoutMinutes 10


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Clean up every profile, including users who are not logged on, since Notion's uninstaller only works for
    ## the user running it. Removing the Roaming folder deletes that user's Notion settings and offline cache.
    ## Profiles without these paths are logged as not found rather than failing.
    Remove-ADTFileFromUserProfiles -Path $appUserFolders -Recurse -ExcludeDefaultUser
    Remove-ADTFileFromUserProfiles -Path ($appDesktopShortcuts + $appStartMenuShortcuts) -ExcludeDefaultUser

    ## Registry for every profile. Invoke-ADTAllUsersRegistryAction loads each user's NTUSER.DAT, so users who
    ## are not logged on are covered too. Notion's uninstall entry is keyed by a GUID rather than its name, so
    ## the entries are matched on DisplayName.
    Invoke-ADTAllUsersRegistryAction -ScriptBlock {
        $userUninstallKey = "Microsoft.PowerShell.Core\Registry::HKEY_USERS\$($_.SID)\Software\Microsoft\Windows\CurrentVersion\Uninstall"
        foreach ($uninstallEntry in (Get-ChildItem -LiteralPath $userUninstallKey -ErrorAction SilentlyContinue))
        {
            if ((Get-ItemProperty -LiteralPath $uninstallEntry.PSPath -ErrorAction SilentlyContinue).DisplayName -like 'Notion*')
            {
                Write-ADTLogEntry -Message "Removing uninstall entry [$($uninstallEntry.PSChildName)] for [$($_.NTAccount)]."
                Remove-Item -LiteralPath $uninstallEntry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        ## Clear the "installed for this user" marker, so a reinstall reaches them again.
        Remove-ADTRegistryKey -Key $appUserMarkerKey -Recurse -SID $_.SID
    }

    ## Refresh the shell so removed shortcuts disappear without a sign out.
    Update-ADTDesktop

    ## Remove package tag from registry.
    Remove-ADTRegistryKey -Key "HKLM:\SOFTWARE\PSADTPackages\$($adtSession.AppVendor)\$($adtSession.AppName)" -Recurse -ErrorAction SilentlyContinue
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## If there are processes to close, show Welcome Message with a 60 second countdown before automatically closing.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 900
    }

    ## Show Progress Message (with the default message).
    if ($adtSession.DeployMode -eq 'Interactive' -and $adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationProgress
    }

    ## <Perform Pre-Repair tasks here>


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI repairs.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }

    ## Repair the machine-wide part, then run the per-user install for anyone logged on who has lost Notion.
    ## Repair-ADTWinGetPackage is not used here: it works on packages in this (SYSTEM) context, and Notion is
    ## installed per user.
    Repair-ADTWinGetPackageManager
    Install-NotionMachineComponent
    Invoke-NotionForSessionUser -FilePath { $appPowerShellPath } -ArgumentList $appUserScriptArguments


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Repair tasks here>
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}











