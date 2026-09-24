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
    AppVendor = 'Github'
    AppName = 'GitHub Desktop'
    AppVersion = 'Latest'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(
        @{ Name = 'GitHubDesktop'; Description = 'GitHub Desktop' }
    )
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-09-17'
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
## MARK: GitHub Desktop helpers
##================================================
## How GitHub Desktop deploys (worked out from the 3.6.6 x64 MSI tables):
## - The MSI ("GitHub Desktop Deployment Tool") installs only
##   "%ProgramFiles(x86)%\GitHub Desktop Deployment\GitHubDesktopDeploymentTool.exe", plus the HKLM Run value
##   "GitHubDesktopDeployment" = "<that exe>" --checkInstall (32-bit component, so under WOW6432Node).
## - At each logon, --checkInstall installs GitHub Desktop into %LocalAppData%\GitHubDesktop for that user,
##   unless it is already there (a "packages" folder) or the user uninstalled it (a ".dead" file).
## - Each per-user copy then updates itself, like the old Teams machine-wide installer.
## Users already logged on would not get it until they log off and on again, so Install-ADTDeployment runs
## --checkInstall in their sessions straight away. Anyone who logs on later is covered by the Run value.

$appDeploymentToolName = 'GitHub Desktop Deployment Tool'
$appDeploymentToolPath = "${env:ProgramFiles(x86)}\GitHub Desktop Deployment\GitHubDesktopDeploymentTool.exe"
$appUserFolderName = 'GitHubDesktop'
$appUserDataFolderName = 'GitHub Desktop'
$appProtocols = @('x-github-client', 'x-github-desktop-auth', 'github-windows')

## The per-user install always puts a shortcut on the user's desktop. Remove-GitHubDesktopShortcut.ps1 removes it
## once per user. It runs from its own HKLM Run value at logon, next to the MSI's, for users who get GitHub Desktop
## at a later logon. Profiles that already have it are cleaned during the install by Remove-ADTFileFromUserProfiles.
## It goes in Program Files, not ProgramData, so standard users cannot replace a script that runs for every user.
$appShortcutScriptName = 'Remove-GitHubDesktopShortcut.ps1'
$appShortcutScriptFolder = "$env:ProgramFiles\PSADTPackages\GitHub Desktop"
$appShortcutScriptPath = "$appShortcutScriptFolder\$appShortcutScriptName"
$appShortcutRunValueName = 'GitHubDesktopRemoveDesktopShortcut'
$appShortcutMarkerKey = 'HKCU\Software\PSADTPackages\Github\GitHub Desktop'
$appPowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

## Shortcut paths relative to each profile folder, for Remove-ADTFileFromUserProfiles. That function joins them to
## the profile folder and does not look up the real desktop location, so the OneDrive* wildcard covers desktops
## redirected by Known Folder Move.
$appDesktopShortcutPaths = @('Desktop\GitHub Desktop.lnk', 'OneDrive*\Desktop\GitHub Desktop.lnk')
$appStartMenuShortcutPaths = @(
    'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\GitHub Desktop.lnk'
    'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\*\GitHub Desktop.lnk'
)

function Get-GitHubDesktopSessionUser
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
            NTAccount        = $sessionUser.NTAccount
            SID              = $sessionUser.SID
            LocalAppDataPath = $(if ($userProfile.LocalAppDataPath) { $userProfile.LocalAppDataPath } else { "$($userProfile.ProfilePath)\AppData\Local" })
        }
    }
}

function Invoke-GitHubDesktopForSessionUser
{
    <#
    .SYNOPSIS
    Runs a GitHub Desktop per-user command in each logged on user's session.

    .DESCRIPTION
    As SYSTEM (Intune), the command runs as each logged on user with Start-ADTProcessAsUser. When the script
    is run by hand from an elevated prompt, it runs for the current user only, since -Username needs SYSTEM.
    Failures are logged as warnings and never fail the deployment: the machine part is already done, and the
    Run value retries the install at the user's next logon.

    .PARAMETER FilePath
    Scriptblock that returns the exe to run, given the user's LocalAppData path as $args[0].

    .PARAMETER ArgumentList
    Arguments for the exe.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ScriptBlock]$FilePath,

        [Parameter(Mandatory = $true)]
        [System.String[]]$ArgumentList
    )

    if (!$IsLocalSystemAccount)
    {
        $exePath = & $FilePath $envLocalAppData
        if (!(Test-Path -LiteralPath $exePath -PathType Leaf))
        {
            Write-ADTLogEntry -Message "[$exePath] not found for [$ProcessNTAccount], nothing to run."
            return
        }
        Write-ADTLogEntry -Message "Not running as SYSTEM, so running [$exePath $ArgumentList] for [$ProcessNTAccount] only."
        $result = Start-ADTProcess -FilePath $exePath -ArgumentList $ArgumentList -WindowStyle Hidden -IgnoreExitCodes '*' -PassThru
        Write-ADTLogEntry -Message "Exit code [$($result.ExitCode)] for [$ProcessNTAccount]."
        return
    }

    $sessionUsers = @(Get-GitHubDesktopSessionUser)
    if ($sessionUsers.Count -eq 0)
    {
        Write-ADTLogEntry -Message 'No users are logged on, so there is nothing to run per user.'
        return
    }

    foreach ($sessionUser in $sessionUsers)
    {
        $exePath = & $FilePath $sessionUser.LocalAppDataPath
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
                ArgumentList    = $ArgumentList
                WindowStyle     = 'Hidden'
                Timeout         = New-TimeSpan -Minutes 10
                IgnoreExitCodes = '*'
                PassThru        = $true
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

    ## No close-apps prompt on install. The MSI only drops the deployment tool into Program Files (x86), and
    ## --checkInstall skips users who already have GitHub Desktop, so a running copy is never touched.
    ## Existing per-user installs are left alone: they update themselves.



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

    ## Evergreen download and install.
    # Update the variables below to suit the application package you selected.
    # For MSI installs, leave $appMsiInstallArgumentList empty to use the built-in PSADT MSI settings
    # from Config\config.psd1 such as MSI.InstallParams / MSI.SilentParams.
    # For EXE installs, add one argument per line to $appExeInstallArgumentList.
    # For ZIP installs: $appZipInstallerFilename is the filename searched for after extraction.
    # Set $appZipInstallerPath to a relative path to skip the search and use an exact location instead.

    $appEvergreenName = 'GitHubDesktop'
    $appArchitecture = 'x64'
    $appType = 'msi'
    $tempPath = Join-Path -Path $envTemp -ChildPath $appEvergreenName
    $appMsiInstallArgumentList = @(
        # Add one MSI argument per line only if you need to override PSADT defaults.
        # Examples:
        # /qn
        # REBOOT=ReallySuppress
        # ALLUSERS=1
    )
    $appExeInstallArgumentList = @(
        # Add one EXE argument per line.
        # Examples:
        # /S
        # /quiet
        # /norestart
    )
    $appZipInstallerFilename = 'setup.exe'  # TODO: verify this matches the installer filename inside the ZIP
    $appZipInstallerPath     = ''              # override: set to a relative path to skip auto-search (e.g. 'Subfolder\setup.exe')

    if (Get-PSRepository | Where-Object { $_.Name -eq 'PSGallery' -and $_.InstallationPolicy -ne 'Trusted' })
    {
        Install-PackageProvider -Name 'NuGet' -MinimumVersion '2.8.5.208' -Force
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted'
    }

    $installedEvergreen = Get-Module -Name 'Evergreen' -ListAvailable |
        Sort-Object -Property @{ Expression = { [version]$_.Version }; Descending = $true } |
        Select-Object -First 1
    $publishedEvergreen = Find-Module -Name 'Evergreen'
    if ($null -eq $installedEvergreen)
    {
        Install-Module -Name 'Evergreen' -Force
    }
    elseif ([version]$publishedEvergreen.Version -gt [version]$installedEvergreen.Version)
    {
        Update-Module -Name 'Evergreen' -Force
    }

    Import-Module -Name 'Evergreen' -Force
    Update-Evergreen -Force | Out-Null

    $appInfo = Get-EvergreenApp -Name $appEvergreenName | Where-Object { $_.Architecture -eq $appArchitecture -and $_.Type -eq $appType } |
        Sort-Object -Property @{
            # Vendor version strings are not always castable to [version] (QGIS publishes
            # '4.2.1-1', for example), so build the sort key from the numeric parts instead.
            Expression = {
                $versionParts = @([regex]::Matches([string]$_.Version, '\d+') | Select-Object -First 4 | ForEach-Object { [int][System.Math]::Min([double]$_.Value, [int]::MaxValue) })
                while ($versionParts.Count -lt 4) { $versionParts += 0 }
                [version]($versionParts -join '.')
            }
            Descending = $true
        } |
        Select-Object -First 1
    if ($null -eq $appInfo)
    {
        throw "No Evergreen package matched the configured filters for [$appEvergreenName]."
    }

    $installerPath = $appInfo | Save-EvergreenApp -Path $tempPath | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$installerPath))
    {
        throw "Save-EvergreenApp did not return a downloadable installer path for [$appEvergreenName]."
    }

    $installerExtension = [System.IO.Path]::GetExtension([string]$installerPath).ToLowerInvariant()
    switch ($installerExtension)
    {
        '.msi'
        {
            if ($appMsiInstallArgumentList.Count -gt 0)
            {
                Start-ADTMsiProcess -Action Install -FilePath $installerPath -ArgumentList $appMsiInstallArgumentList
            }
            else
            {
                Start-ADTMsiProcess -Action Install -FilePath $installerPath
            }
        }
        '.exe'
        {
            $exeProcessSplat = @{
                FilePath       = $installerPath
                WindowStyle    = 'Hidden'
                WaitForMsiExec = $true
            }
            if ($appExeInstallArgumentList.Count -gt 0)
            {
                $exeProcessSplat.ArgumentList = $appExeInstallArgumentList
            }
            Start-ADTProcess @exeProcessSplat
        }
        '.zip'
        {
            $extractPath = Join-Path -Path $tempPath -ChildPath 'Extracted'
            Expand-Archive -Path $installerPath -DestinationPath $extractPath -Force

            if (-not [string]::IsNullOrWhiteSpace($appZipInstallerPath))
            {
                $expandedInstallerPath = Join-Path -Path $extractPath -ChildPath $appZipInstallerPath
            }
            else
            {
                $expandedInstallerPath = Get-ChildItem -Path $extractPath -Filter $appZipInstallerFilename -Recurse -ErrorAction SilentlyContinue |
                    Select-Object -First 1 -ExpandProperty FullName
                if ([string]::IsNullOrWhiteSpace([string]$expandedInstallerPath))
                {
                    throw "Could not find '$appZipInstallerFilename' inside the extracted ZIP. Set $appZipInstallerPath to the relative path manually."
                }
            }
            if (-not (Test-Path -LiteralPath $expandedInstallerPath))
            {
                throw "Installer path not found inside the extracted ZIP: [$expandedInstallerPath]."
            }

            switch ([System.IO.Path]::GetExtension([string]$expandedInstallerPath).ToLowerInvariant())
            {
                '.msi'
                {
                    if ($appMsiInstallArgumentList.Count -gt 0)
                    {
                        Start-ADTMsiProcess -Action Install -FilePath $expandedInstallerPath -ArgumentList $appMsiInstallArgumentList
                    }
                    else
                    {
                        Start-ADTMsiProcess -Action Install -FilePath $expandedInstallerPath
                    }
                }
                '.exe'
                {
                    $zipExeProcessSplat = @{
                        FilePath       = $expandedInstallerPath
                        WindowStyle    = 'Hidden'
                        WaitForMsiExec = $true
                    }
                    if ($appExeInstallArgumentList.Count -gt 0)
                    {
                        $zipExeProcessSplat.ArgumentList = $appExeInstallArgumentList
                    }
                    Start-ADTProcess @zipExeProcessSplat
                }
                default
                {
                    throw "Unsupported installer type inside ZIP: [$expandedInstallerPath]."
                }
            }
        }
        default
        {
            throw "Unsupported Evergreen download type: [$installerExtension]."
        }
    }


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Make sure the machine part landed before relying on it.
    if (!(Test-Path -LiteralPath $appDeploymentToolPath -PathType Leaf))
    {
        throw "The MSI finished but [$appDeploymentToolPath] is missing."
    }

    ## Install GitHub Desktop for the users logged on now, so they don't have to log off and back on.
    ## Everyone else gets it at their next logon from the HKLM Run value.
    ## Set up the desktop shortcut removal before any per-user install runs, so every user is covered.
    New-ADTFolder -LiteralPath $appShortcutScriptFolder
    Copy-ADTFile -Path "$($adtSession.DirSupportFiles)\$appShortcutScriptName" -Destination $appShortcutScriptFolder
    $appShortcutRunCommand = "`"$appPowerShellPath`" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$appShortcutScriptPath`""
    Set-ADTRegistryKey -Key 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name $appShortcutRunValueName -Value $appShortcutRunCommand -Type String

    Invoke-GitHubDesktopForSessionUser -FilePath { $appDeploymentToolPath } -ArgumentList '--checkInstall'

    ## Remove the desktop shortcut from every profile that already has GitHub Desktop: the users just installed
    ## for, plus anyone who had it before. Users who log on later are handled by the logon script.
    Remove-ADTFileFromUserProfiles -Path $appDesktopShortcutPaths -ExcludeDefaultUser

    ## Adjust the pattern below if the application creates a differently named shortcut on the desktop.
    $appDesktopIconPattern = 'GitHub*.lnk'
    Remove-ADTFolder -Path "$tempPath" -ErrorAction SilentlyContinue
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

    ## Remove the machine-wide MSI first. This also removes the HKLM Run value, so nobody gets GitHub Desktop
    ## reinstalled at their next logon.
    Uninstall-ADTApplication -Name $appDeploymentToolName -NameMatch Exact -ApplicationType MSI

    ## Remove the shortcut removal Run value and its script.
    Remove-ADTRegistryKey -Key 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name $appShortcutRunValueName -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $appShortcutScriptFolder -PathType Container)
    {
        Remove-ADTFolder -LiteralPath $appShortcutScriptFolder -ErrorAction SilentlyContinue
    }

    ## Uninstall the per-user copy for users logged on now, as themselves. Squirrel's uninstaller removes
    ## their shortcuts, HKCU uninstall entry and protocol handlers properly.
    Invoke-GitHubDesktopForSessionUser -FilePath { "$($args[0])\$appUserFolderName\Update.exe" } -ArgumentList '--uninstall', '-s'


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Clean up every profile, including users who are not logged on, since Update.exe --uninstall only works
    ## for the user running it. This also clears the ".dead" marker Squirrel leaves behind, so a later
    ## reinstall reaches these users again. Removing the Roaming folder deletes GitHub Desktop settings too.
    ## Profiles without these paths are logged as not found rather than failing.
    Remove-ADTFileFromUserProfiles -Path "AppData\Local\$appUserFolderName", "AppData\Roaming\$appUserDataFolderName" -Recurse -ExcludeDefaultUser
    Remove-ADTFileFromUserProfiles -Path ($appDesktopShortcutPaths + $appStartMenuShortcutPaths) -ExcludeDefaultUser

    ## Registry for every profile. Invoke-ADTAllUsersRegistryAction loads each user's NTUSER.DAT, which holds the
    ## uninstall entry. Protocol handlers are in Software\Classes, which is only mapped for users logged on, so
    ## they are cleaned where visible and only when they point at GitHub Desktop.
    Invoke-ADTAllUsersRegistryAction -ScriptBlock {
        Remove-ADTRegistryKey -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\$appUserFolderName" -Recurse -SID $_.SID

        ## Clear the "shortcut already removed" marker, so a reinstall removes the shortcut again.
        Remove-ADTRegistryKey -Key $appShortcutMarkerKey -Recurse -SID $_.SID

        foreach ($protocol in $appProtocols)
        {
            $protocolKey = "Microsoft.PowerShell.Core\Registry::HKEY_USERS\$($_.SID)\Software\Classes\$protocol"
            $protocolCommand = (Get-ItemProperty -LiteralPath "$protocolKey\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
            if ($protocolCommand -like "*\$appUserFolderName\*")
            {
                Write-ADTLogEntry -Message "Removing [$protocol] protocol handler for [$($_.NTAccount)]."
                Remove-Item -LiteralPath $protocolKey -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
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

    ## <Perform Repair tasks here>


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










