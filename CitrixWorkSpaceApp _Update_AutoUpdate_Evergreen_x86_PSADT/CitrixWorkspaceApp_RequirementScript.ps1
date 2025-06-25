<#
.SYNOPSIS
    Checks if specific application is installed.
.DESCRIPTION
    Retrieves information about installed application by searching specified DisplayName under Uninstall registry keys.
    Specify application name or names separated by comma (* wildcard is allowed).
    Returns TRUE if application is found under Uninstall keys.
    Returns FALSE if true conditions not met.
    Additionaly checks inventory registry keys for applications with extended support releases. If inventory registry key for the application with opposite support release type exists returns FALSE.
.PARAMETER RequirementRule
    The name of the application to check for (* wildcard is allowed). You can specify several variants of the application name separated by comma.
.PARAMETER AppVendor
    The name of the application vendor on the portal.
.PARAMETER AppName
    The name of the application on the portal.
.EXAMPLE
    .\requirement_script.ps1 -RequirementRule "Chrome"
    Checks if Chrome is installed.
.EXAMPLE
    .\requirement_script.ps1 -RequirementRule "Adobe*Acrobat Reader*"
    Checks if Adobe Reader is installed. Using wildcards allows to detect earlier version as well.
.EXAMPLE
    .\requirement_script.ps1 -RequirementRule "*Foxit Editor*,*FoxitPhantomPDF*" -Verbose
    Checks if Foxit is installed by checking two different names.
.EXAMPLE
    .\requirement_script.ps1 -RequirementRule "Citrix Workspace*,LTSR" -AppVendor "Citrix" -AppName "Citrix Workspace" -Verbose
    Checks if Foxit is installed by checking two different names.
.NOTES
#>

Param (
    [Parameter(Mandatory = $False)]
    [ValidateNotNullorEmpty()]
    [string]$RequirementRule = "Citrix Workspace*,CR",
    [Parameter(Mandatory = $False)]
    [ValidateNotNullorEmpty()]
    [string]$AppVendor = "Citrix",
    [Parameter(Mandatory = $False)]
    [ValidateNotNullorEmpty()]
    [string]$AppName = "Citrix Workspace"

)

## Support release types
$Releases = @('CR','LTSR')

## Version number to compare
$VersionToCompare = "22.4"

## Function to verify the existence of the inventory registry key for the application with opposite support release type
function Get-InventoryRegKey {   
    ## Inventory registry keys
    [string[]]$InventoryRegKeys = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Scappman", "Registry::HKEY_CURRENT_USER\Software\Scappman"
    ForEach ( $InventoryRegKey in $InventoryRegKeys ) {
        ## If the requirement rule contains LTSR, etc.
        If ( $Names -cmatch ([string]::Join('|', $Releases[1..($Releases.Length - 1)])) ) {
            ## If CR application is found under the inventory registry key
            ForEach ( $Release in $Releases[1..($Releases.Length - 1)] ) {
                If ( Test-Path -LiteralPath "$($InventoryRegKey)\$($AppVendor)\$(($AppName -replace $Release, '').Trim())" -ErrorAction "SilentlyContinue" ) {
                    Write-Verbose "FALSE: Current Release application's inventory registry key exists."
                    Return $True
                }
                Else {
                    ## Verify currently installed version
                    If ( [version]$VersionToCompare -lt [version]$DisplayVersion ) {
                        Write-Verbose "FALSE: The higher version already installed"
                        Return $True
                    }
                }
            }
        }
        ## If the requirement rule contains CR
        If ( $Names -cmatch ([string]::Join('|', $Releases[0])) ) {
            ## If LTSR, etc. application is found under the inventory registry key
            ForEach ( $Release in $Releases[1..($Releases.Length - 1)] ) {
                If ( Test-Path -LiteralPath "$($InventoryRegKey)\$($AppVendor)\$($AppName) $($Release)" -ErrorAction "SilentlyContinue" ) {
                    Write-Verbose "FALSE: Extended support application's inventory registry key exists."
                    Return $True
                }
            }
        }
        Return $False
    }
}

## Uninstall registry keys
[string[]]$UninstallRegKeys = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall", "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall"
Get-ChildItem -LiteralPath "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" | ForEach-Object {
    $UninstallRegKeys += "Registry::HKEY_USERS\$($_.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
}

## Requirement rule is a comma separated names list
$Names = $RequirementRule.Split(',')

ForEach ( $UninstallRegKey in $UninstallRegKeys ) {
    If ( Test-Path -LiteralPath $UninstallRegKey -ErrorAction "SilentlyContinue" ) {
        ## Get applications Uninstall registry keys
        [psobject[]]$AppsUninstallKeys = Get-ChildItem -LiteralPath $UninstallRegKey -ErrorAction "SilentlyContinue"
        ForEach ( $AppUninstallKey in $AppsUninstallKeys ) {
            ## Get DisplayName of the installed application
            $DisplayName = (Get-ItemProperty -LiteralPath $AppUninstallKey.PSPath).DisplayName
            ## Get DisplayVersion of the installed application
            $DisplayVersion = ((Get-ItemProperty -LiteralPath $AppUninstallKey.PSPath).DisplayVersion -split '\s+')[-1]
            ForEach ( $Name in $Names ) {
                If ( $DisplayName -like $Name ) {
                    ## If support release type is specified in the requirement rule
                    If ( $Names -cmatch ([string]::Join('|', $Releases)) ) {
                        If ( Get-InventoryRegKey ) {
                            Return 0
                        }
                    }

                    if ($AppName -match "Adobe") {
                        $Value = Get-ItemProperty -Path "HKLM:\SOFTWARE\Adobe\Adobe Acrobat\DC\Installer" -Name "SCAPackageLevel" -ErrorAction SilentlyContinue
                        ## Get AppName from Portal
                        if ( $AppName -eq "Adobe Acrobat Pro DC" ) {
                            ## Adobe Acrobat is being installed, checking for SCAPackageLevel
                            if (($Value.SCAPackageLevel -ne 1) -and ($null -ne $Value.SCAPackageLevel)) {
                                Write-Verbose "Adobe Acrobat Pro DC"
                                Return 1
                            } else {
                                Return 0
                            }
                        }
                        ## Get AppName from Portal
                        if ( $AppName -eq "Adobe Acrobat Reader DC") {
                            ## Adobe Reader is being installed, checking for SCAPackageLevel
                            if ($Value.SCAPackageLevel -eq 1) {
                                Write-Verbose "Adobe Acrobat Reader DC"
                                Return 1
                            } else {
                                Return 0
                            }
                        }
                    }

                    Write-Verbose "TRUE: Application found under Uninstall registry keys."
                    Return 1
                }
            }
        }
    }
}
Write-Verbose "FALSE: True conditions not met."
Return 0