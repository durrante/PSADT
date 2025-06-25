<#
.SYNOPSIS
    Customised Win32App Detection Script
.DESCRIPTION
    This script identifies if a specific software, defined by its display name, is installed on the system.
    It checks the uninstall keys in the registry and reports back.
.EXAMPLE
    $TargetSoftware = 'Google Chrome'  # Searches for an uninstall key with the display name 'Google Chrome'
#>

# Define the name of the software to search for
$TargetSoftware = 'Mozilla Firefox'

# Function to fetch uninstall keys from the registry
function Fetch-UninstallKeys {
    [CmdletBinding()]
    param (
        [string]$TargetName
    )

    # Continue on error
    $ErrorActionPreference = 'Continue'

    # Define uninstall registry paths
    $registryPaths = @(
        "registry::HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "registry::HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    # Initialize software list
    $softwareList = @()

    # Loop through each registry path to find software
    foreach ($path in $registryPaths) {
        $softwareList += Get-ChildItem $path | Get-ItemProperty | Where-Object { $_.DisplayName } | Sort-Object DisplayName
    }

    # Filter software list based on target name
    if ($TargetName) {
        $softwareList | Where-Object { $_.DisplayName -like "*$TargetName*" }
    } else {
        $softwareList | Sort-Object DisplayName -Unique
    }
}


# Fetch the list of detected software
$DetectedSoftware = Fetch-UninstallKeys -TargetName $TargetSoftware

# Check if the target software is installed
if ($DetectedSoftware) {
    ("$TargetSoftware is installed.")
    return $true
} else {
    ("$TargetSoftware is NOT installed.")
    return $false
}