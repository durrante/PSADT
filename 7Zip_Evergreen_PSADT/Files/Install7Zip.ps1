## Installs latest version of 7-Zip via Evergreen PowerShell module

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

# Download Latest version of 7-Zip via Evergreen
$7Zip = Get-EvergreenApp -Name 7Zip | Where-Object { $_.Architecture -eq "x64" -and $_.Type -eq "msi"}
$7ZipInstaller = $7Zip | Save-EvergreenApp -Path "C:\Temp\7Zip"

# Install 7-Zip
Start-Process -FilePath msiexec.exe -Args "/I ""$7ZipInstaller"" /qn" -Wait -Verbose

# Cleanup temp directory
$7ZipInstaller | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue