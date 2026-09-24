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
    AppVendor = 'Fortinet'
    AppName = 'FortiClient VPN'
    AppVersion = '7.4.3.4726'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(
        @{ Name = 'FortiClient'; Description = 'FortiClient' }
        @{ Name = 'FortiClientConsole'; Description = 'FortiClient Console' }
        @{ Name = 'FortiClientSecurity'; Description = 'FortiClient Security' }
        @{ Name = 'FortiElevate'; Description = 'FortiClient Elevate' }
        @{ Name = 'FortiScand'; Description = 'FortiClient Scan Daemon' }
        @{ Name = 'FortiSettings'; Description = 'FortiClient Settings' }
        @{ Name = 'FortiSSLVPNdaemon'; Description = 'FortiClient SSL VPN Daemon' }
        @{ Name = 'FortiSSLVPNsys'; Description = 'FortiClient SSL VPN System' }
        @{ Name = 'FortiVPNSt'; Description = 'FortiClient VPN Status' }
        @{ Name = 'FSSOMA'; Description = 'FortiClient SSO Mobility Agent' }
        @{ Name = 'FortiESNAC'; Description = 'FortiClient ESNAC' }
        @{ Name = 'FortiProxy'; Description = 'FortiClient Proxy' }
        @{ Name = 'FortiTray'; Description = 'FortiClient Tray' }
        @{ Name = 'FortiWF'; Description = 'FortiClient Web Filter' }
        @{ Name = 'fcappdb'; Description = 'FortiClient Application Database' }
        @{ Name = 'FCDBLog'; Description = 'FortiClient Database Logger' }
        @{ Name = 'fmon'; Description = 'FortiClient Monitor' }
        @{ Name = 'scheduler'; Description = 'FortiClient Scheduler' }
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

    ## Disable the FortiClient scheduler service so it does not relaunch FortiClient processes while they are being closed.
    if (Test-ADTServiceExists -Name 'FA_Scheduler')
    {
        Set-ADTServiceStartMode -Service 'FA_Scheduler' -StartMode 'Disabled'
    }

    ## Show Welcome Message, close FortiClient processes with a 90 minute countdown before they are force closed.
    ## NOTE: no deferrals (the PSADT 3.x package used DeferTimes 0). -BlockExecution is intentionally not used on install,
    ## the 3.x package unblocked immediately after the welcome prompt so the installer can relaunch FortiTray.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams = @{
            CloseProcesses               = $adtSession.AppProcessesToClose
            ForceCloseProcessesCountdown = 5400
            PromptToSave                 = $true
            MinimizeWindows              = $true
            CheckDiskSpace               = $true
        }
        Show-ADTInstallationWelcome @saiwParams
    }

    ## Show Progress Message (with the default message).
    if ($adtSession.DeployMode -eq 'Interactive' -and $adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationProgress
    }

    ## Install Visual C++ Redistributable prerequisites.

    ## VC++ v14 x64 (VS 2017-2026) - supports apps built with Visual Studio 2015 through 2026.
    ## The v14 runtime is binary-compatible with VS 2015 apps (14.0.x) - no separate 2015 entry is needed.
    ## Downloaded from the official Microsoft permalink (always the latest v14 build).
    ## Exit code 1638 means a newer version is already installed and is ignored.
    ## All other non-zero exit codes are treated as genuine failures.
    Write-ADTLogEntry -Message 'Downloading and installing VC++ v14 x64 (VS 2017-2026).'
    $vcRedistVCv14x64VS20172026Path = Join-Path -Path $envTemp -ChildPath 'vc_redist.x64.exe'
    Invoke-WebRequest -Uri 'https://aka.ms/vc14/vc_redist.x64.exe' -OutFile $vcRedistVCv14x64VS20172026Path -UseBasicParsing
    Start-ADTProcess -FilePath $vcRedistVCv14x64VS20172026Path -ArgumentList @('/install', '/quiet', '/norestart') -IgnoreExitCodes '1638' -WindowStyle Hidden

    ## VC++ v14 x86 (VS 2017-2026) - supports apps built with Visual Studio 2015 through 2026.
    ## The v14 runtime is binary-compatible with VS 2015 apps (14.0.x) - no separate 2015 entry is needed.
    ## Downloaded from the official Microsoft permalink (always the latest v14 build).
    ## Exit code 1638 means a newer version is already installed and is ignored.
    ## All other non-zero exit codes are treated as genuine failures.
    Write-ADTLogEntry -Message 'Downloading and installing VC++ v14 x86 (VS 2017-2026).'
    $vcRedistVCv14x86VS20172026Path = Join-Path -Path $envTemp -ChildPath 'vc_redist.x86.exe'
    Invoke-WebRequest -Uri 'https://aka.ms/vc14/vc_redist.x86.exe' -OutFile $vcRedistVCv14x86VS20172026Path -UseBasicParsing
    Start-ADTProcess -FilePath $vcRedistVCv14x86VS20172026Path -ArgumentList @('/install', '/quiet', '/norestart') -IgnoreExitCodes '1638' -WindowStyle Hidden

    ## Back up existing VPN tunnel configurations. Removing the previous version deletes them.
    $vpnTunnelsKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels'
    $vpnBackupFolder = "$envProgramData\TempDeployment\cache"
    $vpnBackupFile = "$vpnBackupFolder\vpnbackup.reg"
    Write-ADTLogEntry -Message "Checking for existing VPN configurations at registry path: $vpnTunnelsKey"
    if (Get-ChildItem -LiteralPath "Registry::$vpnTunnelsKey" -ErrorAction SilentlyContinue)
    {
        Write-ADTLogEntry -Message "VPN configurations found. Exporting to: $vpnBackupFile"
        New-ADTFolder -LiteralPath $vpnBackupFolder
        Start-ADTProcess -FilePath "$envSystem32Directory\reg.exe" -ArgumentList 'export', $vpnTunnelsKey, $vpnBackupFile, '/y' -CreateNoWindow
    }
    else
    {
        Write-ADTLogEntry -Message 'No existing VPN configurations found to back up.' -Severity 2
    }

    ## Remove any other version of FortiClient VPN.
    ## NOTE: FortiClient VPN builds all share ProductCode {15C7B361-A0B2-4E79-93E0-868B5000BA3F} and build numbers are not
    ## sequential (7.4.3.4726 is newer than 7.4.3.8758), so every version other than this one must be removed first, otherwise
    ## the MSI install is skipped as "already installed".
    $previousVersions = Get-ADTApplication -Name 'FortiClient VPN' -ApplicationType MSI -FilterScript { $_.DisplayVersion -ne $adtSession.AppVersion }
    if ($previousVersions)
    {
        Write-ADTLogEntry -Message "Previous FortiClient VPN version(s) detected [$($previousVersions.DisplayVersion -join ', ')]. A reboot will be requested after the upgrade." -Severity 2
        $script:upgradePerformed = $true
        Uninstall-ADTApplication -Name 'FortiClient VPN' -ApplicationType MSI -FilterScript { $_.DisplayVersion -ne $adtSession.AppVersion } -AdditionalArgumentList 'MSIRESTARTMANAGERCONTROL=Disable', 'MSIRMSHUTDOWN=2'
    }


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

    ## Install FortiClient VPN 64-bit.
    $appMsiInstallArgumentList = @(
        # These args REPLACE all PSADT defaults. Include /qn or equivalent silent flags.
        'REBOOT=ReallySuppress'
        'DONT_PROMPT_REBOOT=1'
        '/qn'
    )
    Start-ADTMsiProcess -Action Install -FilePath "$($adtSession.DirFiles)\FortiClientVPN.msi" -ArgumentList $appMsiInstallArgumentList


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Disable auto updates.
    Set-ADTRegistryKey -LiteralPath 'HKLM:\SOFTWARE\Fortinet\FortiClient\FA_UPDATE' -Name 'enabled' -Value 0 -Type DWord
    Set-ADTRegistryKey -LiteralPath 'HKLM:\SOFTWARE\Fortinet\FortiClient\FA_UPDATE' -Name 'softwareupdateenabled' -Value 0 -Type DWord

    ## Remove the public desktop shortcut. Wait briefly as the installer creates it asynchronously.
    Start-Sleep -Seconds 5
    Remove-ADTFile -LiteralPath "$($envCommonDesktop)\FortiClient VPN.lnk" -ErrorAction SilentlyContinue
    Update-ADTDesktop

    ## Suppress the EULA / first-run prompt for all users (including the Default User profile for new users).
    Invoke-ADTAllUsersRegistryAction -ScriptBlock {
        Set-ADTRegistryKey -SID $_.SID -LiteralPath "HKCU\SOFTWARE\Fortinet\FortiClient\FA_UI\VPN-$($adtSession.AppVersion)" -Name 'installed' -Value 1773907410 -Type DWord
    }

    ## Restore VPN configurations (if applicable).
    Write-ADTLogEntry -Message "Checking for VPN configuration backup at: $vpnBackupFile"
    if (Test-Path -LiteralPath $vpnBackupFile -PathType Leaf)
    {
        Write-ADTLogEntry -Message 'VPN configuration backup found. Importing registry settings.'
        Start-ADTProcess -FilePath "$envSystem32Directory\reg.exe" -ArgumentList 'import', $vpnBackupFile -CreateNoWindow
        Remove-ADTFile -LiteralPath $vpnBackupFile
        Write-ADTLogEntry -Message 'VPN configuration backup file removed.'
    }
    else
    {
        Write-ADTLogEntry -Message 'No VPN configuration backup found to restore.' -Severity 2
    }

    ## Set the FortiClient scheduler service back to Automatic.
    if (Test-ADTServiceExists -Name 'FA_Scheduler')
    {
        Set-ADTServiceStartMode -Service 'FA_Scheduler' -StartMode 'Automatic' -ErrorAction SilentlyContinue
    }

    ## Write package tag to registry for auditing and custom detection.
    $adtRegKey = "HKLM:\SOFTWARE\PSADTPackages\$($adtSession.AppVendor)\$($adtSession.AppName)"
    Set-ADTRegistryKey -LiteralPath $adtRegKey -Name 'Installed'   -Value 'True'                         -Type String
    Set-ADTRegistryKey -LiteralPath $adtRegKey -Name 'Version'     -Value $adtSession.AppVersion          -Type String
    Set-ADTRegistryKey -LiteralPath $adtRegKey -Name 'InstallDate' -Value (Get-Date -Format 'yyyy-MM-dd') -Type String
    Set-ADTRegistryKey -LiteralPath $adtRegKey -Name 'InstalledBy' -Value 'Intune / PSADT'               -Type String

    ## Request a soft reboot when an upgrade from a previous version was performed.
    if ($script:upgradePerformed)
    {
        Write-ADTLogEntry -Message 'Upgrade was performed. Setting exit code to 3010 to request a soft reboot.' -Severity 2
        $adtSession.SetExitCode(3010)
    }
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

    ## If there are processes to close, show Welcome Message with a 90 minute countdown before force closing, and block them from relaunching.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams = @{
            CloseProcesses               = $adtSession.AppProcessesToClose
            ForceCloseProcessesCountdown = 5400
            BlockExecution               = $true
            PromptToSave                 = $true
            PersistPrompt                = $true
            MinimizeWindows              = $true
        }
        Show-ADTInstallationWelcome @saiwParams
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

    ## Uninstall FortiClient VPN 64-bit.
    Uninstall-ADTApplication -Name 'FortiClient VPN' -ApplicationType MSI -AdditionalArgumentList 'MSIRESTARTMANAGERCONTROL=Disable', 'MSIRMSHUTDOWN=2'


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Delete the public desktop shortcut if it remains.
    Remove-ADTFile -LiteralPath "$($envCommonDesktop)\FortiClient VPN.lnk" -ErrorAction SilentlyContinue
    Update-ADTDesktop

    ## Remove package tag from registry.
    Remove-ADTRegistryKey -LiteralPath "HKLM:\SOFTWARE\PSADTPackages\$($adtSession.AppVendor)\$($adtSession.AppName)" -Recurse -ErrorAction SilentlyContinue
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

    ## If there are processes to close, show Welcome Message with a 90 minute countdown before force closing.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -ForceCloseProcessesCountdown 5400 -PromptToSave
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

    ## Repair FortiClient VPN from the packaged MSI.
    Start-ADTMsiProcess -Action Repair -FilePath "$($adtSession.DirFiles)\FortiClientVPN.msi" -RepairFromSource


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Re-apply auto update settings.
    Set-ADTRegistryKey -LiteralPath 'HKLM:\SOFTWARE\Fortinet\FortiClient\FA_UPDATE' -Name 'enabled' -Value 0 -Type DWord
    Set-ADTRegistryKey -LiteralPath 'HKLM:\SOFTWARE\Fortinet\FortiClient\FA_UPDATE' -Name 'softwareupdateenabled' -Value 0 -Type DWord
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Tracks whether a previous FortiClient VPN version was removed, so a soft reboot (3010) can be requested.
$upgradePerformed = $false

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
