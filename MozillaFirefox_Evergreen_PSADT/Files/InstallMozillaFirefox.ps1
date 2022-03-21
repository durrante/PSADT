## Installs latest version of Firefox via Evergreen PowerShell module

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

# Download Latest version of Firefox via Evergreen
$Firefox = Get-EvergreenApp -Name MozillaFirefox | Where-Object { $_.Architecture -eq "x64" -and $_.Channel -eq "LATEST_FIREFOX_VERSION" -and $_.Type -eq "msi"}
$FirefoxInstaller = $Firefox | Save-EvergreenApp -Path "C:\Temp\Firefox"

# Install Firefox
Start-Process -FilePath msiexec.exe -Args "/I ""$FirefoxInstaller"" /quiet" -Wait -Verbose

# Cleanup temp directory
$FirefoxInstaller | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue