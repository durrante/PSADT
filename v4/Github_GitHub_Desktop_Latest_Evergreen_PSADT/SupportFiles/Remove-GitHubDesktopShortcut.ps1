#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the GitHub Desktop shortcut that the per-user install puts on the user's desktop.

.DESCRIPTION
    Runs as the user at logon, from an HKLM Run value added by the PSADT package, alongside the MSI's own
    "GitHubDesktopDeployment" Run value that does the per-user install. Profiles that already have GitHub
    Desktop when the package installs are cleaned by the package itself.

    It removes the shortcut once per user, then writes a marker to HKCU so it never runs again for them. If a
    user puts the shortcut back themselves, it stays.

    Both Run values start at the same time, so the script waits for the install to finish. GitHub Desktop
    creates its shortcuts first and writes its HKCU uninstall entry last, so once that entry has existed for
    30 seconds with no shortcut, there is nothing to remove.
#>

$markerKey = 'HKCU:\Software\PSADTPackages\Github\GitHub Desktop'
$markerName = 'DesktopShortcutRemoved'
$installFolder = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'GitHubDesktop'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\GitHubDesktop'

function Set-Marker
{
    New-Item -Path $markerKey -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $markerKey -Name $markerName -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
}

try
{
    ## Already done for this user.
    if ((Get-ItemProperty -LiteralPath $markerKey -Name $markerName -ErrorAction SilentlyContinue).$markerName -eq 1)
    {
        exit 0
    }

    ## The user uninstalled GitHub Desktop themselves, so the deployment tool will not reinstall it.
    if (Test-Path -LiteralPath (Join-Path -Path $installFolder -ChildPath '.dead'))
    {
        exit 0
    }

    $shell = New-Object -ComObject WScript.Shell
    $deadline = (Get-Date).AddMinutes(10)
    $installedSince = $null

    do
    {
        ## Check the desktop path again on every pass, because OneDrive Known Folder Move can redirect it
        ## during a user's first logon.
        $desktopFolders = @([Environment]::GetFolderPath('Desktop'), (Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop')) |
            Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } |
            Select-Object -Unique

        $shortcuts = foreach ($desktopFolder in $desktopFolders)
        {
            Get-ChildItem -LiteralPath $desktopFolder -Filter '*.lnk' -ErrorAction SilentlyContinue |
                Where-Object { $shell.CreateShortcut($_.FullName).TargetPath -like "$installFolder\*" }
        }

        if ($shortcuts)
        {
            ## Give the installer a moment to finish writing the other shortcuts before touching the desktop.
            Start-Sleep -Seconds 5
            $shortcuts | Remove-Item -Force -ErrorAction SilentlyContinue
            Set-Marker
            exit 0
        }

        if (Test-Path -LiteralPath $uninstallKey)
        {
            if (!$installedSince)
            {
                $installedSince = Get-Date
            }
            elseif ((Get-Date) -gt $installedSince.AddSeconds(30))
            {
                ## Installed, and no shortcut on the desktop.
                Set-Marker
                exit 0
            }
        }

        Start-Sleep -Seconds 5
    }
    while ((Get-Date) -lt $deadline)

    ## Nothing installed within 10 minutes. No marker, so this runs again at the next logon.
    exit 0
}
catch
{
    exit 1
}
