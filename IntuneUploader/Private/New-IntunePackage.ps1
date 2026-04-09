<#
.SYNOPSIS
    Creates a .intunewin package from a source folder using IntuneWinAppUtil.exe.

.DESCRIPTION
    Wraps either:
      1. The IntuneWin32App module's New-IntuneWin32AppPackage cmdlet (preferred)
      2. IntuneWinAppUtil.exe directly (fallback)

    Returns the full path to the generated .intunewin file.
#>

function New-IntunePackage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$SourceFolder,

        [Parameter(Mandatory)]
        [string]$SetupFile,

        [Parameter(Mandatory)]
        [string]$OutputFolder,

        # Path to IntuneWinAppUtil.exe - read from config if not supplied
        [string]$IntuneWinAppUtilPath = ''
    )

    # Ensure output folder exists
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

    # Resolve the utility path
    if (-not $IntuneWinAppUtilPath -or -not (Test-Path $IntuneWinAppUtilPath)) {
        # Try the module's bundled copy first
        $moduleBase = (Get-Module IntuneWin32App -ListAvailable | Select-Object -First 1).ModuleBase
        $moduleTool = Join-Path $moduleBase 'Bin\IntuneWinAppUtil.exe'
        if (Test-Path $moduleTool) {
            $IntuneWinAppUtilPath = $moduleTool
        }
        else {
            # Try the tool directory alongside this script
            $localTool = Join-Path $PSScriptRoot '..\Tools\IntuneWinAppUtil.exe'
            if (Test-Path $localTool) {
                $IntuneWinAppUtilPath = (Resolve-Path $localTool).Path
            }
        }
    }

    $setupFileFull = Join-Path $SourceFolder $SetupFile
    if (-not (Test-Path $setupFileFull)) {
        throw "Setup file not found: $setupFileFull"
    }

    Write-Host "  [*] Packaging: $SourceFolder" -ForegroundColor Yellow
    Write-Host "      Setup file: $SetupFile" -ForegroundColor Gray
    Write-Host "      Output:     $OutputFolder" -ForegroundColor Gray

    # --- Method 1: Use IntuneWin32App module cmdlet ---
    $intunewinPath = $null

    try {
        if (Get-Command New-IntuneWin32AppPackage -ErrorAction SilentlyContinue) {
            $pkg = New-IntuneWin32AppPackage `
                -SourceFolder $SourceFolder `
                -SetupFile    $SetupFile `
                -OutputFolder $OutputFolder `
                -Verbose:$false

            # The cmdlet returns the output file path in different ways across versions
            if ($pkg -is [string] -and (Test-Path $pkg)) {
                $intunewinPath = $pkg
            }
            elseif ($pkg.Path -and (Test-Path $pkg.Path)) {
                $intunewinPath = $pkg.Path
            }
        }
    }
    catch {
        Write-Verbose "Module cmdlet failed ($_ ), trying direct IntuneWinAppUtil.exe..."
    }

    # --- Method 2: Call IntuneWinAppUtil.exe directly ---
    if (-not $intunewinPath) {
        if (-not $IntuneWinAppUtilPath -or -not (Test-Path $IntuneWinAppUtilPath)) {
            throw "IntuneWinAppUtil.exe not found. Run Setup-IntuneUploader.ps1 to download it, or set the path in Config\config.json."
        }

        $argList = "-c `"$SourceFolder`" -s `"$SetupFile`" -o `"$OutputFolder`" -q"
        $proc = Start-Process -FilePath $IntuneWinAppUtilPath `
                              -ArgumentList $argList `
                              -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            throw "IntuneWinAppUtil.exe exited with code $($proc.ExitCode)"
        }
    }

    # Locate the generated .intunewin file
    if (-not $intunewinPath) {
        $baseSetupName = [System.IO.Path]::GetFileNameWithoutExtension($SetupFile)
        $intunewinPath = Get-ChildItem -Path $OutputFolder -Filter '*.intunewin' |
                         Where-Object { $_.BaseName -eq $baseSetupName } |
                         Sort-Object LastWriteTime -Descending |
                         Select-Object -First 1 -ExpandProperty FullName

        # Fallback: just take the newest .intunewin in the output folder
        if (-not $intunewinPath) {
            $intunewinPath = Get-ChildItem -Path $OutputFolder -Filter '*.intunewin' |
                             Sort-Object LastWriteTime -Descending |
                             Select-Object -First 1 -ExpandProperty FullName
        }
    }

    if (-not $intunewinPath -or -not (Test-Path $intunewinPath)) {
        throw "Package was not created. No .intunewin file found in: $OutputFolder"
    }

    Write-Host "  [OK] Package created: $intunewinPath" -ForegroundColor Green
    return $intunewinPath
}
