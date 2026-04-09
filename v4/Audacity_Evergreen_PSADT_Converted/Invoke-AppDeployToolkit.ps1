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
    AppVendor = 'Audacity Team'
    AppName = 'Audacity'
    AppVersion = 'Latest'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = 'Audacity'  # Example: @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-04-09'
    AppScriptAuthor = 'Alex Durrant'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = ''
    InstallTitle = 'Audacity'

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
		
		## Show Welcome Message, close Audacity if required after 10 minute countdown, verify there is enough disk space to complete the install, and persist the prompt
		Show-ADTInstallationWelcome -CloseProcesses 'Audacity' -CheckDiskSpace -PersistPrompt -CloseProcessesCountdown 600

		## Show Progress Message (with the default message)
		## Show-InstallationProgress

		## <Perform Pre-Installation tasks here>
		## Microsoft Intune Win32 App Workaround - Check If Running 32-bit Powershell on 64-bit OS, Restart as 64-bit Process
        If (!([Environment]::Is64BitProcess)){
        If([Environment]::Is64BitOperatingSystem){
        Write-ADTLogEntry -Message "Running 32-bit Powershell on 64-bit OS, Restarting as 64-bit Process..." -Severity 2
        $Arguments = "-NoProfile -ExecutionPolicy ByPass -WindowStyle Hidden -File `"" + $myinvocation.mycommand.definition + "`""
        $Path = (Join-Path $Env:SystemRoot -ChildPath "\sysnative\WindowsPowerShell\v1.0\powershell.exe")
        Start-Process $Path -ArgumentList $Arguments -Wait
        Write-ADTLogEntry -Message "Finished Running x64 version of PowerShell"
        Exit
        }Else{
        Write-ADTLogEntry -Message "Running 32-bit Powershell on 32-bit OS"
        }
        }
		
        ## Remove Any Existing Version of Audacity
        $AppList = Get-ADTApplication -Name 'Audacity'        
        ForEach ($App in $AppList)
        {
        If($App.UninstallString)
        {
        $UninstPath = $App.UninstallString -replace '"', ''       
        If(Test-Path -Path $UninstPath)
        {
        Write-ADTLogEntry -Message "Found $($App.DisplayName) ($($App.DisplayVersion)) and a valid uninstall string, now attempting to uninstall."
        Start-ADTProcess -FilePath $UninstPath -ArgumentList '/VERYSILENT /NORESTART'
        Start-Sleep -Seconds 5
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
		If ((Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" })) {
		    # Install NuGet package provider, which is required to trust the PowerShell Gallery
		    Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
		    # Trust the PowerShell Gallery
		    Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
		}
		
		# Install or update Evergreen module
		$InstalledEvergreen = Get-Module -Name "Evergreen" -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
		$PublishedEvergreen = Find-Module -Name "Evergreen"
		
		If ($null -eq $InstalledEvergreen) {
		    # Evergreen module is not installed, so install it
		    Install-Module -Name "Evergreen"
		}
		ElseIf ($PublishedEvergreen.Version -gt $InstalledEvergreen.Version) {
		    # A newer version of the Evergreen module is available, so update it
		    Update-Module -Name "Evergreen"
		}
		
		# Application-specific variables
		$adtSession.AppName = "Audacity"
		$appType = "exe"
		$adtSession.AppArch = "x64"
		$tempPath = "C:\Temp\$($adtSession.AppName)"
		
		# Download the latest stable version of the application using the Evergreen module
		$appInfo = Get-EvergreenApp -Name $adtSession.AppName | Where-Object { $_.Architecture -eq $adtSession.AppArch -and $_.Type -eq $appType}  | `
		Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | Select-Object -First 1		
		$installerPath = $appInfo | Save-EvergreenApp -Path $tempPath

		# Install cmd
		Start-ADTProcess -FilePath "$installerPath" -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=!desktopicon" -WindowStyle Hidden -WaitForMsiExec

		# Sleep 5 seconds
		Start-Sleep 5
		
		
        ## Suppress Audacity App Update Checking & Welcome to Audacity! Pop-Ups and Disable Check for Updates
		# Locate the Audacity configuration file
		$Config = Get-ChildItem -Path "$($adtSession.DirSupportFiles)" -Include 'audacity.cfg' -File -Recurse -ErrorAction SilentlyContinue

		if ($Config) {
			Write-ADTLogEntry -Message "Copying audacity.cfg to user profiles (Suppress Audacity update checks and pop-ups)" -Source $adtSession.DeployAppScriptFriendlyName

			# Get all user profile paths using the Get-UserProfiles cmdlet
			[string[]]$UserProfiles = Get-ADTUserProfiles | Select-Object -ExpandProperty 'ProfilePath'

			foreach ($Profile in $UserProfiles) {
				$audacityPath = Join-Path -Path $Profile -ChildPath 'AppData\Roaming\audacity'

				# Ensure target folder exists
				New-Item -Path $audacityPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

				# Copy the config file
				Copy-Item -Path $Config.FullName -Destination $audacityPath -Force -ErrorAction SilentlyContinue
			}
		}
		else {
			Write-ADTLogEntry -Message "audacity.cfg not found in support files path" -Severity 1 -Source $adtSession.DeployAppScriptFriendlyName
		}
	

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		$adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

		## <Perform Post-Installation tasks here>
		Remove-ADTFolder -Path "$env:SYSTEMDRIVE\temp" -ErrorAction SilentlyContinue 

		## Display a message at the end of the install
		##If (-not $useDefaultMsi) { Show-InstallationPrompt -Message 'You can customize text to appear at the end of an install or remove it completely for unattended installations.' -ButtonRightText 'OK' -Icon Information -NoWait }
	}

function Uninstall-ADTDeployment
{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		$adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

		## Show Welcome Message, close Audacity with a 600 second countdown before automatically closing
		Show-ADTInstallationWelcome -CloseProcesses 'Audacity' -CloseProcessesCountdown 600

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
        ## Uninstall Any Existing Version of Audacity
        $AppList = Get-ADTApplication -Name 'Audacity'        
        ForEach ($App in $AppList)
        {
        If($App.UninstallString)
        {
        $UninstPath = $App.UninstallString -replace '"', ''       
        If(Test-Path -Path $UninstPath)
        {
        Write-ADTLogEntry -Message "Found $($App.DisplayName) ($($App.DisplayVersion)) and a valid uninstall string, now attempting to uninstall."
        Start-ADTProcess -FilePath $UninstPath -ArgumentList '/VERYSILENT /NORESTART'
        Start-Sleep -Seconds 5
        }
        }
        }

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		$adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

		## <Perform Post-Uninstallation tasks here>
		Write-ADTLogEntry -Message "Removing audacity folder from all user profiles" -Source $adtSession.DeployAppScriptFriendlyName

		# Get all user profile paths using the Get-UserProfiles cmdlet
		[string[]]$UserProfiles = Get-ADTUserProfiles | Select-Object -ExpandProperty 'ProfilePath'
		
		foreach ($Profile in $UserProfiles) {
			$audacityPath = Join-Path -Path $Profile -ChildPath 'AppData\Roaming\audacity'
		
			if (Test-Path -Path $audacityPath) {
				try {
					Remove-Item -Path $audacityPath -Recurse -Force -ErrorAction SilentlyContinue
					Write-ADTLogEntry -Message "Removed: $audacityPath" -Source $adtSession.DeployAppScriptFriendlyName
				}
				catch {
					Write-ADTLogEntry -Message "Failed to remove: $audacityPath. $_" -Severity 2 -Source $adtSession.DeployAppScriptFriendlyName
				}
			}
		}

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
