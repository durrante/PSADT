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
    AppVendor = 'Martin Prikryl'
    AppName = 'WinSCP'
    AppVersion = 'Latest'
    AppArch = 'x86'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @('WinSCP')
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-06-08'
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
    if ($adtSession.DeployMode -eq 'Interactive')
    {
        Show-ADTInstallationProgress
    }

    ## Remove any existing WinSCP installation before upgrading.
    $existingWinSCP = @(Get-ADTApplication -Name 'WinSCP' -NameMatch Contains -ErrorAction SilentlyContinue)
    if ($existingWinSCP.Count -gt 0)
    {
        Write-ADTLogEntry -Message "Found $($existingWinSCP.Count) existing WinSCP installation(s) - removing before upgrade."
        $preUninstallSplat = @{
            Name            = 'WinSCP'
            NameMatch       = 'Contains'
            ApplicationType = 'EXE'
            ArgumentList    = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' 
        }
        Uninstall-ADTApplication @preUninstallSplat
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

    ## Evergreen download and install.
    # Update the variables below to suit the application package you selected.
    # For MSI installs, leave $appMsiInstallArgumentList empty to use the built-in PSADT MSI settings
    # from Config\config.psd1 such as MSI.InstallParams / MSI.SilentParams.
    # For EXE installs, add one argument per line to $appExeInstallArgumentList.
    # For ZIP installs: $appZipInstallerFilename is the filename searched for after extraction.
    # Set $appZipInstallerPath to a relative path to skip the search and use an exact location instead.

    $appEvergreenName = 'WinSCP'
    $appArchitecture = 'x86'
    $appType = 'msi'
    $tempPath = Join-Path -Path $envTemp -ChildPath $appEvergreenName
    $appMsiInstallArgumentList = @(
        # Add one MSI argument per line only if you need to override PSADT defaults.
        # Examples:
        # /qn
        # REBOOT=ReallySuppress
        # ALLUSERS=1
        '/qn'
        'REBOOT=ReallySuppress'
        'ALLUSERS=1'
        'DESKTOPSHORTCUT=0'
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
        Sort-Object -Property @{ Expression = { [version]$_.Version }; Descending = $true } |
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

    ## Disable Anonymous Usage Statistics, Automatic Check for Updates, and Beta Versions
    Invoke-ADTAllUsersRegistryAction {
        Set-ADTRegistryKey -Key 'HKCU\Software\Martin Prikryl\WinSCP 2\Configuration\Interface' -Name 'CollectUsage' -Value 0 -Type DWord -SID $_.SID
        Set-ADTRegistryKey -Key 'HKCU\Software\Martin Prikryl\WinSCP 2\Configuration\Interface\Updates' -Name 'Period' -Value 0 -Type DWord -SID $_.SID
        Set-ADTRegistryKey -Key 'HKCU\Software\Martin Prikryl\WinSCP 2\Configuration\Interface\Updates' -Name 'BetaVersions' -Value 1 -Type DWord -SID $_.SID
        Set-ADTRegistryKey -Key 'HKCU\Software\Martin Prikryl\WinSCP 2\Configuration\Interface\Updates' -Name 'ShowOnStartup' -Value 0 -Type DWord -SID $_.SID
    }

    ## Adjust the pattern below if the application creates a differently named shortcut on the desktop.
    $appDesktopIconPattern = 'WinSCP*.lnk'
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
    if ($adtSession.DeployMode -eq 'Interactive')
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

    ## Uninstall all application components.
    $uninstallSplat1 = @{
        Name            = 'WinSCP'
        NameMatch       = 'Contains'
        ApplicationType = 'MSI'
    }
    Uninstall-ADTApplication @uninstallSplat1

    $uninstallSplat2 = @{
        Name            = 'WinSCP'
        NameMatch       = 'Contains'
        ApplicationType = 'EXE'
        ArgumentList    = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' 
    }
    Uninstall-ADTApplication @uninstallSplat2


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

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
    if ($adtSession.DeployMode -eq 'Interactive')
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











