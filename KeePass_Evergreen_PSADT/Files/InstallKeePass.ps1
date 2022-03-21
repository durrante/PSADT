## Installs latest version of KeePass via Evergreen PowerShell module

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

# Download Latest version of KeePass via Evergreen
$KeePass = Get-EvergreenApp -Name KeePass | Where-Object { $_.Architecture -eq "x86" -and $_.Type -eq "msi"}
$KeePassInstaller = $KeePass | Save-EvergreenApp -Path "C:\Temp\KeePass"

# Install KeePass
Start-Process -FilePath msiexec.exe -Args "/I ""$KeePassInstaller"" /qn" -Wait -Verbose

# Cleanup temp directory
$KeePassInstaller | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue