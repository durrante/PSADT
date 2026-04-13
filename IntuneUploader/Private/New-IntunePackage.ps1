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

    # Call IntuneWinAppUtil.exe directly.
    # We skip the New-IntuneWin32AppPackage cmdlet — it wraps the same exe but without
    # output redirection, which can cause the process to block when run from a WPF host.
    $intunewinPath = $null

    if (-not $IntuneWinAppUtilPath -or -not (Test-Path $IntuneWinAppUtilPath)) {
        throw "IntuneWinAppUtil.exe not found. Run Setup-IntuneUploader.ps1 to download it, or set the path in Config\config.json."
    }

    # Use ProcessStartInfo with redirected stdout/stderr to prevent output-buffer freeze
    $psi                       = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName              = $IntuneWinAppUtilPath
    $psi.Arguments             = "-c `"$SourceFolder`" -s `"$SetupFile`" -o `"$OutputFolder`" -q"
    $psi.UseShellExecute       = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow        = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    # Read output asynchronously to prevent deadlock if buffer fills
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdoutTask.Wait(); $stderrTask.Wait()

    if ($proc.ExitCode -ne 0) {
        $errText = $stderrTask.Result.Trim()
        if (-not $errText) { $errText = $stdoutTask.Result.Trim() }
        throw "IntuneWinAppUtil.exe failed (exit $($proc.ExitCode))$(if ($errText) {": $errText"})"
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

<#
.SYNOPSIS
    Updates the inner content filename and Detection.xml FileName element inside a .intunewin ZIP.

.DESCRIPTION
    IntuneWinAppUtil.exe always names the encrypted inner payload "IntunePackage.intunewin"
    regardless of the source or output filename. The IntuneWin32App module reads that name from
    Detection.xml and uses it as the filename that appears in the Intune portal.

    This function rewrites the .intunewin ZIP to:
      - Rename IntuneWinPackage/Contents/IntunePackage.intunewin → IntuneWinPackage/Contents/<DesiredName>
      - Update <FileName> in IntuneWinPackage/Metadata/Detection.xml to match

    Call this after renaming the outer .intunewin file so that Intune shows the correct name.

.PARAMETER IntunewinPath
    Full path to the .intunewin file to patch (modified in place).

.PARAMETER DesiredName
    The filename to set inside the ZIP, e.g. "MyApp_1.0_PSADT.intunewin".
    Usually the leaf name of the renamed outer file.
#>
function Update-IntunewinPackageName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IntunewinPath,

        [Parameter(Mandatory)]
        [string]$DesiredName
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $tempPath = $IntunewinPath + '.patching'

    $srcStream = $null
    $srcZip    = $null
    $dstStream = $null
    $dstZip    = $null

    try {
        $srcStream = [System.IO.File]::OpenRead($IntunewinPath)
        $srcZip    = [System.IO.Compression.ZipArchive]::new($srcStream, [System.IO.Compression.ZipArchiveMode]::Read)
        $dstStream = [System.IO.File]::Create($tempPath)
        $dstZip    = [System.IO.Compression.ZipArchive]::new($dstStream, [System.IO.Compression.ZipArchiveMode]::Create)

        foreach ($srcEntry in $srcZip.Entries) {
            # Map the source entry name to the destination entry name
            $dstName = $srcEntry.FullName
            if ($dstName -eq 'IntuneWinPackage/Contents/IntunePackage.intunewin') {
                $dstName = "IntuneWinPackage/Contents/$DesiredName"
            }

            $dstEntry = $dstZip.CreateEntry($dstName, [System.IO.Compression.CompressionLevel]::NoCompression)
            $dstEntry.LastWriteTime = $srcEntry.LastWriteTime

            $inStream  = $srcEntry.Open()
            $outStream = $dstEntry.Open()

            if ($srcEntry.FullName -eq 'IntuneWinPackage/Metadata/Detection.xml') {
                # Patch the FileName element so the Intune portal shows the correct name
                $reader  = [System.IO.StreamReader]::new($inStream, [System.Text.Encoding]::UTF8)
                $xml     = $reader.ReadToEnd()
                $xml     = $xml -replace '<FileName>[^<]*</FileName>', "<FileName>$DesiredName</FileName>"
                $bytes   = [System.Text.Encoding]::UTF8.GetBytes($xml)
                $outStream.Write($bytes, 0, $bytes.Length)
            }
            else {
                $inStream.CopyTo($outStream)
            }

            $outStream.Dispose()
            $inStream.Dispose()
        }

        $dstZip.Dispose();    $dstZip    = $null
        $dstStream.Dispose(); $dstStream = $null
        $srcZip.Dispose();    $srcZip    = $null
        $srcStream.Dispose(); $srcStream = $null

        Remove-Item $IntunewinPath -Force
        Move-Item   $tempPath      $IntunewinPath

        Write-Verbose "Update-IntunewinPackageName: inner filename updated to '$DesiredName'."
    }
    catch {
        if ($dstZip)    { try { $dstZip.Dispose()    } catch {} }
        if ($dstStream) { try { $dstStream.Dispose() } catch {} }
        if ($srcZip)    { try { $srcZip.Dispose()    } catch {} }
        if ($srcStream) { try { $srcStream.Dispose() } catch {} }
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        throw "Update-IntunewinPackageName: failed to patch '$IntunewinPath' — $_"
    }
}
