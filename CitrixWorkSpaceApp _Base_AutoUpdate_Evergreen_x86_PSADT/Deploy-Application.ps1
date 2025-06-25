﻿<#
.SYNOPSIS

PSApppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION

- The script is provided as a template to perform an install or uninstall of an application(s).
- The script either performs an "Install" deployment type or an "Uninstall" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.

PSApppDeployToolkit is licensed under the GNU LGPLv3 License - (C) 2023 PSAppDeployToolkit Team (Sean Lillis, Dan Cunningham and Muhammad Mashwani).

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the
Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
for more details. You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

.PARAMETER DeploymentType

The type of deployment to perform. Default is: Install.

.PARAMETER DeployMode

Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.

.PARAMETER AllowRebootPassThru

Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode

Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging

Disables logging to file for the script. Default is: $false.

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"

.EXAMPLE

Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"

.INPUTS

None

You cannot pipe objects to this script.

.OUTPUTS

None

This script does not generate any output.

.NOTES

Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
- 69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
- 70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1

.LINK

https://psappdeploytoolkit.com
#>


[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [String]$DeploymentType = 'Install',
    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [String]$DeployMode = 'Interactive',
    [Parameter(Mandatory = $false)]
    [switch]$AllowRebootPassThru = $false,
    [Parameter(Mandatory = $false)]
    [switch]$TerminalServerMode = $false,
    [Parameter(Mandatory = $false)]
    [switch]$DisableLogging = $false
)

Try {
    ## Set the script execution policy for this process
    Try {
        Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop'
    }
    Catch {
    }

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    ## Variables: Application
	[string]$appVendor = 'Citrix'
	[string]$appName = 'Citrix Workspace'
	[string]$appVersion = 'Latest'
	[string]$appArch = 'x86'
	[string]$appLang = 'mui'
	[string]$appRevision = '1.0'
	[string]$appScriptVersion = '1.1.0'
	[string]$appScriptDate = '25/06/2025'
	[string]$appScriptAuthor = 'Alex Durrant'
    ##*===============================================
    ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
    [String]$installName = 'Citrix Workspace'
    [String]$installTitle = 'Citrix Workspace'

    ##* Do not modify section below
    #region DoNotModify

    ## Variables: Exit Code
    [Int32]$mainExitCode = 0

    ## Variables: Script
    [String]$deployAppScriptFriendlyName = 'Deploy Application'
    [Version]$deployAppScriptVersion = [Version]'3.9.3'
    [String]$deployAppScriptDate = '02/05/2023'
    [Hashtable]$deployAppScriptParameters = $PsBoundParameters

    ## Variables: Environment
    If (Test-Path -LiteralPath 'variable:HostInvocation') {
        $InvocationInfo = $HostInvocation
    }
    Else {
        $InvocationInfo = $MyInvocation
    }
    [String]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [String]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) {
            Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]."
        }
        If ($DisableLogging) {
            . $moduleAppDeployToolkitMain -DisableLogging
        }
        Else {
            . $moduleAppDeployToolkitMain
        }
    }
    Catch {
        If ($mainExitCode -eq 0) {
            [Int32]$mainExitCode = 60008
        }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        ## Exit the script, returning the exit code to SCCM
        If (Test-Path -LiteralPath 'variable:HostInvocation') {
            $script:ExitCode = $mainExitCode; Exit
        }
        Else {
            Exit $mainExitCode
        }
    }

	## Global Variables
	[boolean]$configShowBalloonNotifications = $false ## This will overwrite the same variable that's inside AppDeployToolKitMain.ps1
	[boolean]$forceSilentInstallation = $false

	[boolean]$DefaultDetection = $true
	
	[int]$Defertimes = 0
	[int]$CloseAppsCountDownSeconds = 900

    #endregion
    ##* Do not modify section above
    ##*===============================================
    ##* END VARIABLE DECLARATION
    ##*===============================================

    If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        ##*===============================================
        ##* PRE-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Installation'
		
		## Check if PowerPoint is running a presentation, if so, the install will be silently defered until max defer count is reached (default 3)
		Test-PowerPointDefer

		## Show Welcome Message
		if ($forceSilentInstallation) {
			Show-InstallationWelcome -CloseApps 'SelfService,Receiver,AuthManSvr,CtxWebBrowser,concentr,redirector,SelfServicePlugin,wfcrun32,wfica32' -BlockExecution -Silent -PromptToSave
		}
		else {
			# ask to close processes if required, allow up to 3 deferrals
			Show-InstallationWelcome -CloseApps 'SelfService,Receiver,AuthManSvr,CtxWebBrowser,concentr,redirector,SelfServicePlugin,wfcrun32,wfica32' -AllowDeferCloseApps -DeferTimes $Defertimes -ForceCloseAppsCountdown $CloseAppsCountDownSeconds -PromptToSave -MinimizeWindows $true -TopMost $true
		}

        ## Show Progress Message (with the default message)
        

        ## <Perform Pre-Installation tasks here>
		If (Get-Process -Name "TrolleyExpress" -EA 0) { Stop-Process -Name "TrolleyExpress" -Force -EA 0 }
		
		## Check if Microsoft Store app is present
		try {
		  $storeApp = Get-AppxPackage -AllUsers | Where-Object Name -like "*CitrixReceiver*" | Select Name
		  if ($storeApp) {
			  ## Remove for existing users
			  $storeName = $(($storeApp -split "=")[1]).Trim("}")
			  Get-AppxPackage -Name "$storeName" -AllUsers | Remove-AppxPackage -AllUsers
			  ## Remove for new users
			  Get-AppXProvisionedPackage -Online | where DisplayName -EQ "$storeName" | Remove-AppxProvisionedPackage -Online
			  ## Remove shortcuts if present
			  $Profiles = (Get-UserProfiles).ProfilePath 
			  ForEach ($Profile in $Profiles){
				  if (Test-Path "$($Profile)\Desktop\Citrix Workspace.lnk") {
					  Remove-File -Path "$($Profile)\Desktop\Citrix Workspace.lnk"
				  }
			  }
		  }
		} catch {}
		
        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Installation'

        ## Handle Zero-Config MSI Installations
        If ($useDefaultMsi) {
            [Hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) {
                $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile)
            }
            Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) {
                $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ }
            }
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
		$appName = "CitrixWorkspaceApp"
		$appStream = "Current"
		$tempPath = "C:\Temp\$appName"
		
		# Download the latest stable version of the application using the Evergreen module
		$appInfo = Get-EvergreenApp -Name $appName | Where-Object { $_.Stream -eq $appStream} | `
        Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | Select-Object -First 1
		$installerPath = $appInfo | Save-EvergreenApp -Path $tempPath

		# Install Citrix
		Execute-Process -FilePath "$InstallerPath" -Parameters "/AutoUpdateCheck=Auto /AutoUpdateStream=Current /noreboot /silent EnableCEIP=false" -WindowStyle Hidden -IgnoreExitCodes "40008"
		## 40008 means "This version of Citrix Workspace app has already been installed".
		Sleep -Seconds 30
		
        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Installation'

        ## <Perform Post-Installation tasks here>
		## Remove desktop sh
		Sleep -Seconds 5
		Remove-File -Path "$envCommonDesktop\Citrix Workspace.lnk" -EA 0
		
		## Delete Installer Files
		Remove-Item -Path $installerPath -Force

		## Display a message at the end of the install; The balloontip will be invoked by the Exit-Script command
		<##If (-not $useDefaultMsi -and ($false -eq $configShowBalloonNotifications)) { 
			Show-InstallationPrompt -Message 'The application has been installed successfully.' -ButtonRightText 'OK' -Icon Information -NoWait
		}##>
	}
    ElseIf ($deploymentType -ieq 'Uninstall') {
        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps 'SelfService,Receiver,AuthManSvr,CtxWebBrowser,concentr,redirector,SelfServicePlugin,wfcrun32,wfica32' -AllowDeferCloseApps -DeferTimes $MaxDefers -ForceCloseAppsCountdown $CloseAppsCountDownSeconds -PromptToSave -PersistPrompt -MinimizeWindows $false -TopMost $true
		
		
		## Show Progress Message (with the default message)


		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>

		## Uninstall Citrix Workspace
        $AppList = Get-InstalledApplication -Name 'Citrix Workspace'        
        ForEach ($App in $AppList)
        {
        If($App.UninstallString)
        {
        $UninstPath = $App.UninstallString -replace '"', '' -replace ' /uninstall /cleanup', ''       
        If(Test-Path -Path $UninstPath)
        {
        Write-log -Message "Found $($App.DisplayName) ($($App.DisplayVersion)) and a valid uninstall string, now attempting to uninstall."
        Execute-Process -Path $UninstPath -Parameters '/uninstall /cleanup /silent'
        Start-Sleep -Seconds 5
        }
        }
        }


        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Uninstallation'

        ## <Perform Post-Uninstallation tasks here>
		## Delete desktop sh
		Remove-File -Path "$envCommonDesktop\Citrix Workspace.lnk" -EA 0

    }
    ElseIf ($deploymentType -ieq 'Repair') {
        ##*===============================================
        ##* PRE-REPAIR
        ##*===============================================
        [String]$installPhase = 'Pre-Repair'

        ## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
        Show-InstallationWelcome -CloseApps 'iexplore' -CloseAppsCountdown 60

        ## Show Progress Message (with the default message)
        Show-InstallationProgress

        ## <Perform Pre-Repair tasks here>

        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [String]$installPhase = 'Repair'

        ## Handle Zero-Config MSI Repairs
        If ($useDefaultMsi) {
            [Hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) {
                $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile)
            }
            Execute-MSI @ExecuteDefaultMSISplat
        }
        ## <Perform Repair tasks here>

        ##*===============================================
        ##* POST-REPAIR
        ##*===============================================
        [String]$installPhase = 'Post-Repair'

        ## <Perform Post-Repair tasks here>


    }
    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================

    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [Int32]$mainExitCode = 60001
    [String]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}
