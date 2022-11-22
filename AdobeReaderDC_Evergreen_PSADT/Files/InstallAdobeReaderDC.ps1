## Installs latest version of Adobe Reader DC via Evergreen PowerShell module

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

# Download Latest version of Adobe Reader DC via Evergreen
$AdobeReaderDC = Get-EvergreenApp -Name AdobeAcrobatReaderDC | Where-Object { $_.Architecture -eq "x64"}
$AdobeReaderDCInstaller = $AdobeReaderDC | Save-EvergreenApp -Path "C:\Temp\AdobeReaderDC"

# Install Adobe Reader DC
Start-Process -FilePath "$AdobeReaderDCInstaller" -args "/sAll /msi /norestart /quiet ALLUSERS=1 EULA_ACCEPT=YES" -Wait -Verbose

# Cleanup temp directory
$AdobeReaderDCInstaller | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
