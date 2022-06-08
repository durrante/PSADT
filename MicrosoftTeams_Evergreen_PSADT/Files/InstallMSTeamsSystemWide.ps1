## Installs latest version of MS Teams via Evergreen PowerShell module

# Trust PowerShell Gallery
If (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
    Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
    Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
}

#Install or update Evergreen module
$Installed = Get-Module -Name "Evergreen" -ListAvailable | `
    Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | `
    Select-Object -First 1
$Published = Find-Module -Name "Evergreen"
If ($Null -eq $Installed) {
    Install-Module -Name "Evergreen"
}
ElseIf ([System.Version]$Published.Version -gt [System.Version]$Installed.Version) {
    Update-Module -Name "Evergreen"
}

# Download Latest version of Teams via Evergreen
$Teams = Get-EvergreenApp -Name MicrosoftTeams | Where-Object { $_.Architecture -eq "x64" -and $_.Ring -eq "General" -and $_.Type -eq "MSI"}
$TeamsInstaller = $Teams | Save-EvergreenApp -Path "C:\Temp\Teams"

# Install Teams
Start-Process -FilePath msiexec.exe -Args "/I ""$TeamsInstaller"" OPTIONS=noAutoStart=true ALLUSERS=1 /qn" -Wait -Verbose

# Cleanup temp directory
$TeamsInstaller | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue