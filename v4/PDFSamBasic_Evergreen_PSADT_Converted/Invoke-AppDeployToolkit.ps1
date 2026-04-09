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
    AppVendor = 'Sober Lemur S.r.l.'
    AppName = 'PDFSam Basic'
    AppVersion = 'Latest'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = 'javaw', 'pdfsam'  # Example: @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-04-09'
    AppScriptAuthor = 'Alex Durrant'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = ''
    InstallTitle = 'PDFSam Basic'

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

		## Show Welcome Message, Close PDFsam Basic With a 600 Second Countdown Before Automatically Closing
		Show-ADTInstallationWelcome -CloseProcesses 'javaw', 'pdfsam' -CloseProcessesCountdown 600

        ## Show Progress Message (with the default message)
        #Show-InstallationProgress

        ## <Perform Pre-Installation tasks here>
        ## Remove Any Existing Version of PDFsam Basic
        Uninstall-ADTApplication -Name "PDFsam Basic" -ApplicationType MSI

        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        $adtSession.InstallPhase = $adtSession.DeploymentType

        ## Handle Zero-Config MSI Installations
        If ($adtSession.UseDefaultMsi) {
            [Hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Install'; Path = $adtSession.DefaultMsiFile }; If ($defaultMstFile) {
                $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile)
            }
            Start-ADTMsiProcess; If ($defaultMspFiles) {
                $defaultMspFiles | ForEach-Object { Start-ADTMsiProcess -Action 'Patch' -FilePath $_ }
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
		$adtSession.AppName = "SoberLemurPDFSamBasic"
		$appType = "msi"
		$tempPath = "C:\Temp\$($adtSession.AppName)"
		
		# Download the latest stable version of the application using the Evergreen module
		$appInfo = Get-EvergreenApp -Name $adtSession.AppName | Where-Object { $_.type -eq $apptype}
		$installerPath = $appInfo | Save-EvergreenApp -Path $tempPath
		
		# Install the application
		Start-Process -FilePath msiexec.exe -ArgumentList "/I `"$installerPath`" /quiet /norestart SKIPTHANKSPAGE=Yes CHECK_FOR_UPDATES=false CHECK_FOR_NEWS=false DONATE_NOTIFICATION=false PREMIUM_MODULES=false PLAY_SOUNDS=false" -Wait -Verbose -WindowStyle Hidden
		Sleep -Seconds 10

        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

        ## <Perform Post-Installation tasks here>
		## Delete desktop shortcut
		Remove-ADTFile -Path "$envCommonDesktop\PDFsam Basic.lnk"
		
		## Delete Installer Files
		Remove-Item -Path $installerPath -Force

		## Remove uninstall shortcut
		Remove-ADTFile -Path "$envCommonStartMenuPrograms\PDFsam Basic\Uninstall.lnk"
		
        ## Display a message at the end of the install
        <#If (-not $useDefaultMsi) {
            Show-InstallationPrompt -Message 'You can customize text to appear at the end of an install or remove it completely for unattended installations.' -ButtonRightText 'OK' -Icon Information -NoWait
        }#>
    }

function Uninstall-ADTDeployment
{
        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

		## Show Welcome Message, Close PDFsam Basic With a 60 Second Countdown Before Automatically Closing
		Show-ADTInstallationWelcome -CloseProcesses 'javaw', 'pdfsam' -CloseProcessesCountdown 60

        ## Show Progress Message (With a Message to Indicate the Application is Being Uninstalled)
        Show-ADTInstallationProgress -StatusMessage "Uninstalling the $($adtSession.InstallTitle) Application. Please Wait..."

        ## <Perform Pre-Uninstallation tasks here>


        ##*===============================================
        ##* UNINSTALLATION
        ##*===============================================
        $adtSession.InstallPhase = $adtSession.DeploymentType

        ## Handle Zero-Config MSI Uninstallations
        If ($adtSession.UseDefaultMsi) {
            [Hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Uninstall'; Path = $adtSession.DefaultMsiFile }; If ($defaultMstFile) {
                $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile)
            }
            Start-ADTMsiProcess
        }

        ## <Perform Uninstallation tasks here>
        ## Uninstall Any Existing Version of PDFsam Basic
        Uninstall-ADTApplication -Name "PDFsam Basic" -ApplicationType MSI

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

        ## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
        Show-ADTInstallationWelcome -CloseProcesses 'iexplore' -CloseProcessesCountdown 60

        ## Show Progress Message (with the default message)
        Show-ADTInstallationProgress

        ## <Perform Pre-Repair tasks here>

        ##*===============================================
        ##* REPAIR
        ##*===============================================
        $adtSession.InstallPhase = $adtSession.DeploymentType

        ## Handle Zero-Config MSI Repairs
        If ($adtSession.UseDefaultMsi) {
            [Hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Repair'; Path = $adtSession.DefaultMsiFile; }; If ($defaultMstFile) {
                $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile)
            }
            Start-ADTMsiProcess
        }
        ## <Perform Repair tasks here>

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
