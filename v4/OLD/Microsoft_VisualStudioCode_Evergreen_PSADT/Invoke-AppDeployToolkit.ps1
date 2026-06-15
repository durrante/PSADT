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
    AppVendor = 'Microsoft'
    AppName = 'Visual Studio Code'
    AppVersion = 'Latest'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = 'Latest'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = 'code'  # Example: @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-04-09'
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
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		$adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

		## Show Welcome Message, close VSCode if required after 10 minute countdown, verify there is enough disk space to complete the install, and persist the prompt
		Show-ADTInstallationWelcome -CloseProcesses 'code' -CheckDiskSpace -PersistPrompt -CloseProcessesCountdown 600

		## Show Progress Message (with the default message)
		## Show-InstallationProgress

		## <Perform Pre-Installation tasks here>
		## Remove Microsoft Visual Studio Code (User Installer)
		$Users = Get-ChildItem C:\Users
		ForEach ($user in $Users){
		$VSCodeLocal = "$($user.fullname)\AppData\Local\Programs\Microsoft VS Code"
		If (Test-Path $VSCodeLocal) {
		$UninstPath = Get-ChildItem -Path "$VSCodeLocal\*" -Include unins000.exe -Recurse -ErrorAction SilentlyContinue
		If($UninstPath.Exists)
		{
		Write-ADTLogEntry -Message "Found $($UninstPath.FullName), now attempting to uninstall the $($adtSession.InstallTitle)."
		Start-ADTProcessAsUser -Path "$UninstPath" -Parameters "/VERYSILENT /NORESTART"
		Start-Sleep -Seconds 5

		## Cleanup User Profile Registry
		[scriptblock]$HKCURegistrySettings = {
		Remove-ADTRegistryKey -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{D628A17A-9713-46BF-8D57-E671B46A741E}_is1' -SID $_.SID
		Remove-ADTRegistryKey -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{771FD6B0-FA20-440A-A002-3B3BAC16DC50}_is1' -SID $_.SID
		}
		Invoke-ADTAllUsersRegistryAction -ScriptBlock $HKCURegistrySettings -ErrorAction SilentlyContinue

		## Cleanup Microsoft Visual Studio Code (Local User Profile) Directory
		If (Test-Path $VSCodeLocal) {
		Write-ADTLogEntry -Message "Cleanup ($VSCodeLocal) Directory."
		Remove-Item -Path "$VSCodeLocal" -Force -Recurse -ErrorAction SilentlyContinue 
		}
		}
		}
		}
		$Users = Get-ChildItem C:\Users
		ForEach ($user in $Users){

		## Cleanup Microsoft Visual Studio Code (Roaming User Profile) Directory

		$VSCodeRoaming = "$($user.fullname)\AppData\Roaming\Code"
		If (Test-Path $VSCodeRoaming) {
		Write-ADTLogEntry -Message "Cleanup ($VSCodeRoaming) Directory."
		Remove-Item -Path "$VSCodeRoaming" -Force -Recurse -ErrorAction SilentlyContinue
		Start-Sleep -Seconds 5
		}

		## Remove Microsoft Visual Studio Code Start Menu Shortcut From User Profiles (If Present)

		$StartMenuSC = "$($user.fullname)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Visual Studio Code"
		If (Test-Path $StartMenuSC) {
		Write-ADTLogEntry -Message "Removing Microsoft Visual Studio Code Start Menu Shortcut From User Profile."
		Remove-Item $StartMenuSC -Recurse -Force -ErrorAction SilentlyContinue
		}

		## Remove Microsoft Visual Studio Code Desktop Shortcut From User Profiles (If Present)

		$DesktopSC = "$($user.fullname)\Desktop\Visual Studio Code.lnk"
		If (Test-Path $DesktopSC) {
		Write-ADTLogEntry -Message "Removing Microsoft Visual Studio Code Desktop Shortcut From User Profile."
		Remove-Item $DesktopSC -Recurse -Force -ErrorAction SilentlyContinue
		}
		}

		## Remove Microsoft Visual Studio Code (System Installer)
		
		$AppList = Get-ADTApplication -Name 'Microsoft Visual Studio Code'        
		ForEach ($App in $AppList)
		{
		If($App.UninstallString)
		{
		$UninstPath = $App.UninstallString -replace '"', ''       
		If(Test-Path -Path $UninstPath)
		{
		Write-ADTLogEntry -Message "Found $($App.DisplayName) ($($App.DisplayVersion)) and a valid uninstall string, now attempting to uninstall."
		Start-ADTProcess -FilePath $UninstPath -ArgumentList '/VERYSILENT /NORESTART'
		Sleep -Seconds 5
		}
		}
		}

		##*===============================================
		##* INSTALLATION
		##*===============================================
		$adtSession.InstallPhase = $adtSession.DeploymentType

		## Handle Zero-Config MSI Installations
		If ($adtSession.UseDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $adtSession.DefaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Start-ADTMsiProcess; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Start-ADTMsiProcess -Action 'Patch' -FilePath $_ } }
		}

		## <Perform Installation tasks here>
		# Trust PowerShell Gallery
		if (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
			Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
			Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
		}

		#Install or update Evergreen module
		$Installed = Get-Module -Name "Evergreen" -ListAvailable | `
			Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | `
			Select-Object -First 1
		$Published = Find-Module -Name "Evergreen"
		if ($Null -eq $Installed) {
			Install-Module -Name "Evergreen"
		}
		elseif ([System.Version]$Published.Version -gt [System.Version]$Installed.Version) {
			Update-Module -Name "Evergreen"
		}
		
		## Download latest manifest
		Update-Evergreen -force
		
		# Application-specific variables
		$appname = "MicrosoftVisualStudioCode"
		$appArchitecture = "x64"
		$appChannel = "Stable"
		$appPlatform = "win32-x64"
		$tempPath = "C:\Temp\$($appname)"
		
		# Download the latest stable version of the application using the Evergreen module
		$appInfo = Get-EvergreenApp -Name $appname | Where-Object { $_.Architecture -eq $appArchitecture -and $_.Channel -eq $appChannel -and $_.Platform -eq $appPlatform } | `
		Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | Select-Object -First 1		
		$installerPath = $appInfo | Save-EvergreenApp -Path $tempPath
		
		# Install cmd
        Start-ADTProcess -FilePath "$installerPath" -ArgumentList "/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /MERGETASKS=!runcode" -WindowStyle Hidden -WaitForMsiExec
		
		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		$adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

		## <Perform Post-Installation tasks here>
		Remove-ADTFolder -Path "$env:SYSTEMDRIVE\temp" -ErrorAction SilentlyContinue 
		

		## Display a message at the end of the install
		## If (-not $useDefaultMsi) { Show-InstallationPrompt -Message 'You can customize text to appear at the end of an install or remove it completely for unattended installations.' -ButtonRightText 'OK' -Icon Information -NoWait }
	}

function Uninstall-ADTDeployment
{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		$adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

		## Show Welcome Message, close VSCode with a 600 second countdown before automatically closing
		Show-ADTInstallationWelcome -CloseProcesses 'Code' -CloseProcessesCountdown 600

		## Show Progress Message (with the default message)
		## Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		$adtSession.InstallPhase = $adtSession.DeploymentType

		## Handle Zero-Config MSI Uninstallations
		If ($adtSession.UseDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $adtSession.DefaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Start-ADTMsiProcess
		}

		# <Perform Uninstallation tasks here>
		Uninstall-ADTApplication `
			-Name 'Microsoft Visual Studio Code' `
			-FilterScript { $_.Publisher -match 'Microsoft' } `
			-ArgumentList '/VERYSILENT /NORESTART'
			

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		$adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

		## <Perform Post-Uninstallation tasks here>
		

	}

function Repair-ADTDeployment
{
		##*===============================================
		##* PRE-REPAIR
		##*===============================================
		$adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

		## Show Progress Message (with the default message)
		Show-ADTInstallationProgress

		## <Perform Pre-Repair tasks here>

		##*===============================================
		##* REPAIR
		##*===============================================
		$adtSession.InstallPhase = $adtSession.DeploymentType

		## Handle Zero-Config MSI Repairs
		If ($adtSession.UseDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $adtSession.DefaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Start-ADTMsiProcess
		}
		# <Perform Repair tasks here>

		##*===============================================
		##* POST-REPAIR
		##*===============================================
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
