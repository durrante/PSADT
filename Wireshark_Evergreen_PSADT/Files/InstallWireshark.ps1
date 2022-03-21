## Installs latest version of WireShark via Evergreen PowerShell module

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

# Download Latest version of WireShark via Evergreen
$Wireshark = Get-EvergreenApp -Name WireShark | Where-Object { $_.Architecture -eq "x64" -and $_.Type -eq "msi"}
$WiresharkInstaller = $Wireshark | Save-EvergreenApp -Path "C:\Temp\Wireshark"

# Install WireShark
Start-Process -FilePath msiexec.exe -Args "/I ""$WiresharkInstaller"" /qn" -Wait -Verbose

# Cleanup temp directory
$Wireshark | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue