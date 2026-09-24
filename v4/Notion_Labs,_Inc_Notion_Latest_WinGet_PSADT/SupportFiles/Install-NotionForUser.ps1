#Requires -Version 5.1
<#
.SYNOPSIS
    Installs Notion for the current user with WinGet.

.DESCRIPTION
    Notion only ships a per-user installer, so it has to be installed in each user's own context. The PSADT
    package runs this script as every user who is logged on at install time, and again at each logon from an
    HKLM Run value, which is how users who log on later get Notion.

    It does nothing when Notion is already installed. After a successful install it writes a marker to HKCU, so
    a user who then uninstalls Notion themselves does not get it put back at their next logon.

    It also removes the desktop shortcut that Notion's installer creates, once per user, and records that in
    HKCU as well. If a user puts the shortcut back themselves, it stays.

    Exit codes: 0 = installed, or nothing to do. 1 = the install was attempted and failed.

.NOTES
    Logs to %TEMP%\PSADT-Notion-UserInstall.log.
#>

$appWinGetId = 'Notion.Notion'
$appInstallRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\Notion'
$appExePath = Join-Path -Path $appInstallRoot -ChildPath 'Notion.exe'
$markerKey = 'HKCU:\Software\PSADTPackages\Notion Labs, Inc\Notion'
$markerName = 'Installed'
$shortcutMarkerName = 'DesktopShortcutRemoved'
$logPath = Join-Path -Path $env:TEMP -ChildPath 'PSADT-Notion-UserInstall.log'

function Write-Log
{
    param ([System.String]$Message)

    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Write-Output $line
    Add-Content -LiteralPath $logPath -Value $line -ErrorAction SilentlyContinue
}

function Set-Marker
{
    param ([System.String]$Name)

    New-Item -Path $markerKey -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $markerKey -Name $Name -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
}

function Test-Marker
{
    param ([System.String]$Name)

    (Get-ItemProperty -LiteralPath $markerKey -Name $Name -ErrorAction SilentlyContinue).$Name -eq 1
}

function Remove-DesktopShortcut
{
    <#
    .SYNOPSIS
    Removes the Notion desktop shortcut for this user, once.

    .DESCRIPTION
    Only shortcuts pointing into this user's Notion install are removed, so an unrelated file of the same name
    is left alone. The desktop location is looked up rather than assumed, so a desktop redirected into OneDrive
    by Known Folder Move is covered.
    #>
    if (Test-Marker -Name $shortcutMarkerName)
    {
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    $desktopFolders = @([Environment]::GetFolderPath('Desktop'), (Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop')) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } |
        Select-Object -Unique

    foreach ($desktopFolder in $desktopFolders)
    {
        foreach ($shortcut in (Get-ChildItem -LiteralPath $desktopFolder -Filter '*.lnk' -ErrorAction SilentlyContinue))
        {
            if ($shell.CreateShortcut($shortcut.FullName).TargetPath -like "$appInstallRoot\*")
            {
                Write-Log "Removing desktop shortcut [$($shortcut.FullName)]."
                Remove-Item -LiteralPath $shortcut.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Set-Marker -Name $shortcutMarkerName
}

function Get-WinGetPath
{
    <#
    .SYNOPSIS
    Finds winget.exe for the current user.

    .DESCRIPTION
    The App Installer alias in WindowsApps is the normal route, but it is registered per user and can be missing
    for a few moments at a first logon, so the package folder is used as a fallback.
    #>
    $wingetCommand = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wingetCommand)
    {
        return $wingetCommand.Source
    }

    $aliasPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $aliasPath -PathType Leaf)
    {
        return $aliasPath
    }

    Get-ChildItem -Path (Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe') -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName |
        Select-Object -Last 1 -ExpandProperty FullName
}

try
{
    if (Test-Path -LiteralPath $appExePath -PathType Leaf)
    {
        Write-Log "Notion is already installed at [$appInstallRoot], nothing to install."
        Remove-DesktopShortcut
        exit 0
    }

    if (Test-Marker -Name $markerName)
    {
        Write-Log 'Notion was installed for this user before and has since been removed by them, so it will not be reinstalled.'
        exit 0
    }

    ## WinGet and the network are not always ready the moment a user logs on, so try a few times.
    $attempt = 0
    $maxAttempts = 3
    while ($attempt -lt $maxAttempts)
    {
        $attempt++

        $wingetPath = Get-WinGetPath
        if (!$wingetPath)
        {
            Write-Log "Attempt $attempt of $maxAttempts`: winget.exe not found."
        }
        else
        {
            Write-Log "Attempt $attempt of $maxAttempts`: installing [$appWinGetId] with [$wingetPath]."
            $wingetOutput = & $wingetPath install --exact --id $appWinGetId --scope user --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
            Write-Log "winget exit code [$LASTEXITCODE]: $($wingetOutput -join ' ')"

            if (Test-Path -LiteralPath $appExePath -PathType Leaf)
            {
                Set-Marker -Name $markerName
                Write-Log 'Notion installed.'
                Remove-DesktopShortcut
                exit 0
            }
        }

        if ($attempt -lt $maxAttempts)
        {
            Start-Sleep -Seconds 60
        }
    }

    Write-Log 'Notion could not be installed. It will be tried again at the next logon.'
    exit 1
}
catch
{
    Write-Log "Unhandled error: $($_.Exception.Message)"
    exit 1
}
