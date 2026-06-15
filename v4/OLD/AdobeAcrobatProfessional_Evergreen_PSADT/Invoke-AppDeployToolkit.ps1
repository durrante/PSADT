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
    AppVendor = 'Adobe'
    AppName = 'Acrobat Pro (Unified Installer)'
    AppVersion = 'Latest'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(@{ Name = "AcroRd32"; Description = "Adobe Acrobat" }, @{ Name = "Acrobat"; Description = "Adobe Acrobat" }) # Example: @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })
    AppScriptVersion = '1.2.0'
    AppScriptDate = '2026-04-15'
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
		## Microsoft Intune Win32 App Workaround - Check If Running 32-bit PowerShell on 64-bit OS, Restart as 64-bit Process
		if (!([Environment]::Is64BitProcess)) {
			if([Environment]::Is64BitOperatingSystem) {
				
				Write-ADTLogEntry -Message "Running 32-bit PowerShell on 64-bit OS, Restarting as 64-bit Process..." -Severity 1
				
				$arguments = "-NoProfile -ExecutionPolicy ByPass -WindowStyle Hidden -File `"" + $myinvocation.mycommand.definition + "`""
				$path = (Join-Path $Env:SystemRoot -ChildPath "\sysnative\WindowsPowerShell\v1.0\powershell.exe")
				Start-Process $path -ArgumentList $arguments -Wait
				
				Write-ADTLogEntry -Message "Finished Running x64 version of PowerShell" -Severity 1
				Exit
			}
			else {
				Write-ADTLogEntry -Message "Running 32-bit PowerShell on 32-bit OS" -Severity 1
			}
		}

		## Show Welcome Message, close processes with a 60 second countdown before automatically closing. 
		## Switch to $true to allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
		$saiwParams = @{
			CloseProcessesCountdown = 60
			AllowDefer = $false
			DeferTimes = 3
			CheckDiskSpace = $false
			PersistPrompt = $false
		}
		if ($adtSession.AppProcessesToClose.Count -gt 0)
		{
			$saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
		}
		
		## Show Progress Message (with a message to indicate the application is being uninstalled).
		Show-ADTInstallationProgress -StatusMessage "Removing Any Existing Version of $($adtSession.AppName). Please Wait..."
		## Remove Any Existing Legacy Versions of Adobe Acrobat Reader
		Uninstall-ADTApplication -FilterScript {$_.DisplayName -match '^Adobe (Acrobat )?Reader'} -ApplicationType 'MSI' 
		## Remove Any Existing Version of Adobe Acrobat Reader (64-bit)
		$appName = Get-ADTApplication -Name 'Adobe Acrobat (64-bit)' -FilterScript { $_.Publisher -match 'Adobe' }
		if ($appName.Count -gt 0) {
			## Check if Adobe Acrobat Reader is installed, ignore Adobe Acrobat
			$pkgLevel = Get-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\Adobe\Adobe Acrobat\DC\Installer' -Name 'SCAPackageLevel'
			if ($null -ne $pkgLevel) {
				Write-ADTLogEntry -Message "SCAPackageLevel registry key found and is set to: $pkgLevel" -Severity 1
				if ($pkgLevel -eq 1) {
					Write-ADTLogEntry -Message "SCAPackageLevel is set to 1. Proceeding to uninstall Adobe Acrobat Reader." -Severity 1
					Uninstall-ADTApplication -Name 'Adobe Acrobat (64-bit)' -ApplicationType 'MSI' -FilterScript { $_.Publisher -match 'Adobe' }
				}
				else {
					Write-ADTLogEntry -Message "SCAPackageLevel is not set to 1, indicating this is Adobe Acrobat (not Adobe Acrobat Reader). Skipping uninstall." -Severity 2
				}
			}
			else {
				Write-ADTLogEntry -Message "SCAPackageLevel registry key not found. Cannot determine package level. Skipping uninstall." -Severity 2
			}
		}
		else {
			Write-ADTLogEntry -Message "$($adtSession.AppName) (64-bit) application is not currently installed." -Severity 1
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
		$appname = "AdobeAcrobatProStdDC"
		$AppArch = "x64"
		$appSku = "Pro"
		$appType = "zip"
		$tempPath = "C:\Temp\$($appname)"
		
		# Download the latest stable version of the application using the Evergreen module
		$appInfo = Get-EvergreenApp -Name $appname | Where-Object { $_.Architecture -eq $appArch -and $_.Type -eq $appType -and $_.Sku -eq $appSku} | `
		Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | Select-Object -First 1		
		$installerPath = $appInfo | Save-EvergreenApp -Path $tempPath

		# Unzip file
		# If it's a ZIP file, extract and update the installer path
		if ($installerPath -like "*.zip") {
			$extractPath = Join-Path -Path $tempPath -ChildPath "extracted"
			Expand-Archive -Path $installerPath -DestinationPath $extractPath -Force

			# Manually set the installer path to the exact EXE within the extracted files
			# Example below assumes you know the subfolder and filename 
			$installerPath = Join-Path -Path $extractPath -ChildPath "Adobe Acrobat\setup.exe" # Change me (if needed)
			
			if (-Not (Test-Path -Path $installerPath)) {
				Write-Error "Specified installer file not found: $installerPath"
				Exit 1
			}
		}

		# Install cmd
        Start-ADTProcess -FilePath "$installerPath" -ArgumentList "/sAll /msi /norestart /quiet ALLUSERS=1 DISABLEDESKTOPSHORTCUT=1 EULA_ACCEPT=YES" -WindowStyle Hidden -WaitForMsiExec

		# Sleep 15 seconds
		Start-Sleep 15

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		$adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

		## <Perform Post-Installation tasks here>
		Remove-ADTFolder -Path "$tempPath" -ErrorAction SilentlyContinue 
		Remove-ADTFile -Path "$envCommonDesktop\Adobe*.lnk" -ErrorAction SilentlyContinue
		Update-ADTDesktop

		## Configure settings for Adobe Acrobat
		$SoftwareRegKey = "HKLM:\SOFTWARE"

		#Disable EULA
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Adobe\Adobe Acrobat\DC\AdobeViewer" -Name "EULA" -Value "1" -Type "DWord"
		#Dsable the prompt "Make Adobe Acrobat my default PDF application."
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Adobe\Adobe Acrobat\DC\AVAlert\cCheckbox" -Name "iAppDoNotTakePDFOwnershipAtLaunch" -Value "1" -Type "DWord"
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Adobe\Adobe Acrobat\DC\AVAlert\cCheckbox" -Name "iAppDoNotTakePDFOwnershipAtLaunchWin10" -Value "1" -Type "DWord"
		#Disable the Help > Repair Installation menu
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Adobe\Adobe Acrobat\DC\Installer" -Name "DisableMaintenance" -Value "1" -Type "DWord"
		#Disable messages which encourage the user to upgrade the product
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown" -Name "bAcroSuppressUpsell" -Value "1" -Type "DWord"
		#Disable the First Time Experience (FTE) feature (Welcome tour/page)
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown" -Name "bToggleFTE" -Value "1" -Type "DWord"
		#Disable user participation in the feedback program
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown" -Name "bUsageMeasurement" -Value "0" -Type "DWord"
		# Set multi user licence mode (This key allows Acrobat to function as either Adobe Reader or Adobe Acrobat, depending on the user license. If you only want to use it as Adobe Reader, you don’t need to sign in.)
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown" -Name "bIsSCReducedModeEnforcedEx" -Value "1" -Type "DWord"
		Set-ADTRegistryKey -LiteralPath "$($SoftwareRegKey)\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown\cIPM" -Name "bDontShowMsgWhenViewingDoc" -Value "0" -Type "DWord"
		
		## Display a message at the end of the install
		##If (-not $useDefaultMsi) { Show-InstallationPrompt -Message 'You can customize text to appear at the end of an install or remove it completely for unattended installations.' -ButtonRightText 'OK' -Icon Information -NoWait }
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
			Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60
		}
		## Show Progress Message (with a message to indicate the application is being uninstalled).
		Show-ADTInstallationProgress -StatusMessage "Uninstalling Any Existing Version of $($adtSession.AppName). Please Wait..."
		##================================================
		## MARK: Uninstall
		##================================================
		$adtSession.InstallPhase = $adtSession.DeploymentType
		## Uninstall Any Existing Legacy Versions of Adobe Acrobat Reader
		Uninstall-ADTApplication -FilterScript {$_.DisplayName -match '^Adobe (Acrobat )?Reader'} -ApplicationType 'MSI' 
		## Uninstall Any Existing Version of Adobe Acrobat Reader (64-bit)
		$appName = Get-ADTApplication -Name 'Adobe Acrobat (64-bit)' -FilterScript { $_.Publisher -match 'Adobe' }
		if ($appName.Count -gt 0) {
			## Check if Adobe Acrobat Reader is installed, ignore Adobe Acrobat
			$pkgLevel = Get-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\Adobe\Adobe Acrobat\DC\Installer' -Name 'SCAPackageLevel'
			if ($null -ne $pkgLevel) {
				Write-ADTLogEntry -Message "SCAPackageLevel registry key found and is set to: $pkgLevel" -Severity 1
				if ($pkgLevel -eq 1) {
					Write-ADTLogEntry -Message "SCAPackageLevel is set to 1. Proceeding to uninstall Adobe Acrobat Reader." -Severity 1
					Uninstall-ADTApplication -Name 'Adobe Acrobat (64-bit)' -ApplicationType 'MSI' -FilterScript { $_.Publisher -match 'Adobe' }
				}
				else {
					Write-ADTLogEntry -Message "SCAPackageLevel is not set to 1, indicating this is Adobe Acrobat (not Adobe Acrobat Reader). Skipping uninstall." -Severity 2
				}
			}
			else {
				Write-ADTLogEntry -Message "SCAPackageLevel registry key not found. Cannot determine package level. Skipping uninstall." -Severity 2
			}
		}
		else {
			Write-ADTLogEntry -Message "$($adtSession.AppName) (64-bit) application is not currently installed." -Severity 1
		}
		##================================================
		## MARK: Post-Uninstallation
		##================================================
		$adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
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
