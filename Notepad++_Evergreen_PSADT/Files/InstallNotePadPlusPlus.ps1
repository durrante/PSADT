## Installs latest version of Notepad++ via Evergreen PowerShell module

# Trust PowerShell Gallery
if (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
	Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
	Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
}

#Install or update Evergreen module
$Installed = Get-Module -Name "Evergreen" -ListAvailable | `
	Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | `
	Select-Object -First 1
$Published = Find-Module -Name "Evergreen"
if ($Null -eq $Installed) {
	Install-Module -Name "Evergreen"
}
elseif ([System.Version]$Published.Version -gt [System.Version]$Installed.Version) {
	Update-Module -Name "Evergreen"
}

## Download latest manifest
Update-Evergreen -force

# Download Latest version of Notepad++ via Evergreen
$Notepadpp = Get-EvergreenApp -Name NotepadPlusPlus | Where-Object { $_.Architecture -eq "x64" -and $_.Type -eq "exe"}
$NotepadppInstaller = $Notepadpp | Save-EvergreenApp -Path "C:\Temp\notepadpp"

# Install NotePad++
Start-Process -FilePath "$NotepadppInstaller" -args "/S" -Wait -Verbose

# Cleanup temp directory
$NotepadppInstaller | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
