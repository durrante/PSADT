<#
.SYNOPSIS
    Patches the installed IntuneWin32App module for compatibility fixes.

.DESCRIPTION
    Applies two patches to the MSEndpointMgr IntuneWin32App module:

    Patch 1 — New-IntuneWin32AppRequirementRule.ps1
        The shipped ValidateSet only covers OS versions up to W11_22H2
        and architectures up to x64/x86/All.
        Updated to support:
          - OS:   W10_1607 through W11_24H2  (W11_25H2 excluded — not yet accepted by Intune API)
          - Arch: x64, x86, arm64, x64arm64, x64x86, AllWithARM64

    Patch 2 — Add-IntuneWin32App.ps1
        The Begin block subtracts ExpiresOn from the current UTC time.
        On non-US locales (e.g. en-GB), PowerShell may coerce ExpiresOn to a
        culture-formatted string ('13/04/2026 17:08:23'). DateTime.Parse with
        InvariantCulture then fails because the day value (13) is treated as a
        month, which is invalid.
        Fixed by normalising ExpiresOn to a proper UTC DateTime before arithmetic.

    Safe to call multiple times — skips any patch already applied.
    Returns $true if at least one patch was applied, $false if all were already up to date.
#>

function Repair-IntuneWin32AppModule {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $moduleBase = (Get-Module IntuneWin32App -ListAvailable |
                   Sort-Object Version -Descending |
                   Select-Object -First 1).ModuleBase

    if (-not $moduleBase) {
        Write-Warning 'Repair-IntuneWin32AppModule: IntuneWin32App module not found — skipping patches.'
        return $false
    }

    $patched1 = $false
    $patched2 = $false

    # ══════════════════════════════════════════════════════════════════════════
    # Patch 1 — New-IntuneWin32AppRequirementRule.ps1
    #   Adds W11_23H2, W11_24H2 and ARM64/x64arm64/AllWithARM64 support.
    # ══════════════════════════════════════════════════════════════════════════
    $requirementRuleFile = Join-Path $moduleBase 'Public\New-IntuneWin32AppRequirementRule.ps1'

    if (-not (Test-Path $requirementRuleFile)) {
        Write-Warning "Repair-IntuneWin32AppModule: $requirementRuleFile not found — skipping patch 1."
    }
    else {
        $reqContent = Get-Content $requirementRuleFile -Raw
        # Guard: W11_23H2 present AND W11_25H2 absent AND x64arm64 present = already patched
        $alreadyPatched1 = ($reqContent -match 'W11_23H2' -and
                            $reqContent -notmatch 'W11_25H2' -and
                            $reqContent -match 'x64arm64')

        if ($alreadyPatched1) {
            Write-Verbose 'Repair-IntuneWin32AppModule: requirement rule already fully patched.'
        }
        else {
            Write-Verbose "Repair-IntuneWin32AppModule: applying patch 1 — $requirementRuleFile"

            $patchedContent = @'
function New-IntuneWin32AppRequirementRule {
    <#
    .SYNOPSIS
        Construct a new requirement rule as an optional requirement for Add-IntuneWin32App cmdlet.

    .DESCRIPTION
        Construct a new requirement rule as an optional requirement for Add-IntuneWin32App cmdlet.

    .PARAMETER Architecture
        Specify the architecture as a requirement for the Win32 app.
        Supported values: x64, x86, arm64, x64x86, AllWithARM64.

    .PARAMETER MinimumSupportedWindowsRelease
        Specify the minimum supported Windows release version as a requirement for the Win32 app.
        Supported values: W10_1607 through W11_24H2.

    .PARAMETER MinimumFreeDiskSpaceInMB
        Specify the minimum free disk space in MB as a requirement for the Win32 app.

    .PARAMETER MinimumMemoryInMB
        Specify the minimum required memory in MB as a requirement for the Win32 app.

    .PARAMETER MinimumNumberOfProcessors
        Specify the minimum number of required logical processors as a requirement for the Win32 app.

    .PARAMETER MinimumCPUSpeedInMHz
        Specify the minimum CPU speed in Mhz (as an integer) as a requirement for the Win32 app.

    .NOTES
        Author:      Nickolaj Andersen
        Contact:     @NickolajA
        Created:     2020-01-27
        Updated:     2025-12-07 (patched by IntuneUploader for W11_24H2 + ARM64 support)

        Version history:
        1.0.0 - (2020-01-27) Function created
        1.0.7 - (2025-12-07) Added ARM64, x64x86, AllWithARM64; added OS values through W11_24H2;
                              W11_25H2 excluded — Intune API does not accept it yet
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the architecture as a requirement for the Win32 app.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("x64", "x86", "arm64", "x64x86", "x64arm64", "AllWithARM64")]
        [string]$Architecture,

        [parameter(Mandatory = $true, HelpMessage = "Specify the minimum supported Windows release version as a requirement for the Win32 app.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("W10_1607", "W10_1703", "W10_1709", "W10_1803", "W10_1809", "W10_1903", "W10_1909",
                     "W10_2004", "W10_20H2", "W10_21H1", "W10_21H2", "W10_22H2",
                     "W11_21H2", "W11_22H2", "W11_23H2", "W11_24H2")]
        [Alias("MinimumSupportedOperatingSystem")]
        [string]$MinimumSupportedWindowsRelease,

        [parameter(Mandatory = $false, HelpMessage = "Specify the minimum free disk space in MB as a requirement for the Win32 app.")]
        [ValidateNotNullOrEmpty()]
        [int]$MinimumFreeDiskSpaceInMB,

        [parameter(Mandatory = $false, HelpMessage = "Specify the minimum required memory in MB as a requirement for the Win32 app.")]
        [ValidateNotNullOrEmpty()]
        [int]$MinimumMemoryInMB,

        [parameter(Mandatory = $false, HelpMessage = "Specify the minimum number of required logical processors as a requirement for the Win32 app.")]
        [ValidateNotNullOrEmpty()]
        [int]$MinimumNumberOfProcessors,

        [parameter(Mandatory = $false, HelpMessage = "Specify the minimum CPU speed in Mhz (as an integer) as a requirement for the Win32 app.")]
        [ValidateNotNullOrEmpty()]
        [int]$MinimumCPUSpeedInMHz
    )
    Process {
        $ArchitectureTable = @{
            "x64"          = "x64"
            "x86"          = "x86"
            "arm64"        = "arm64"
            "x64x86"       = "x64,x86"
            "x64arm64"     = "x64,arm64"
            "AllWithARM64" = "x64,x86,arm64"
        }

        $OperatingSystemTable = @{
            "W10_1607" = "1607"
            "W10_1703" = "1703"
            "W10_1709" = "1709"
            "W10_1803" = "1803"
            "W10_1809" = "1809"
            "W10_1903" = "1903"
            "W10_1909" = "1909"
            "W10_2004" = "2004"
            "W10_20H2" = "20H2"
            "W10_21H1" = "21H1"
            "W10_21H2" = "Windows10_21H2"
            "W10_22H2" = "Windows10_22H2"
            "W11_21H2" = "Windows11_21H2"
            "W11_22H2" = "Windows11_22H2"
            "W11_23H2" = "Windows11_23H2"
            "W11_24H2" = "Windows11_24H2"
        }

        $RequirementRule = [ordered]@{
            "allowedArchitectures"           = $ArchitectureTable[$Architecture]
            "applicableArchitectures"        = "none"
            "minimumSupportedWindowsRelease" = $OperatingSystemTable[$MinimumSupportedWindowsRelease]
        }

        if ($PSBoundParameters["MinimumFreeDiskSpaceInMB"])  { $RequirementRule.Add("minimumFreeDiskSpaceInMB",  $MinimumFreeDiskSpaceInMB)  }
        if ($PSBoundParameters["MinimumMemoryInMB"])          { $RequirementRule.Add("minimumMemoryInMB",          $MinimumMemoryInMB)          }
        if ($PSBoundParameters["MinimumNumberOfProcessors"]) { $RequirementRule.Add("minimumNumberOfProcessors", $MinimumNumberOfProcessors)  }
        if ($PSBoundParameters["MinimumCPUSpeedInMHz"])       { $RequirementRule.Add("minimumCpuSpeedInMHz",       $MinimumCPUSpeedInMHz)       }

        return $RequirementRule
    }
}
'@

            try {
                Set-Content -Path $requirementRuleFile -Value $patchedContent -Encoding UTF8 -Force
                Write-Verbose 'Repair-IntuneWin32AppModule: patch 1 applied successfully.'
                $patched1 = $true
            }
            catch {
                Write-Warning "Repair-IntuneWin32AppModule: could not write patch 1 — $_"
            }
        }
    }

    # ══════════════════════════════════════════════════════════════════════════
    # Patch 2 — Add-IntuneWin32App.ps1
    #   Normalises ExpiresOn before DateTime arithmetic so en-GB / non-US
    #   locales don't produce an unparseable culture-formatted string.
    # ══════════════════════════════════════════════════════════════════════════
    $addAppFile = Join-Path $moduleBase 'Public\Add-IntuneWin32App.ps1'

    if (-not (Test-Path $addAppFile)) {
        Write-Warning "Repair-IntuneWin32AppModule: $addAppFile not found — skipping patch 2."
    }
    else {
        # Guard: look for our sentinel variable name
        $addLines = Get-Content $addAppFile
        $alreadyPatched2 = $addLines -match '_expiresOn'

        if ($alreadyPatched2) {
            Write-Verbose 'Repair-IntuneWin32AppModule: Add-IntuneWin32App.ps1 already patched.'
        }
        else {
            # Find the target line
            $targetIdx = -1
            for ($ln = 0; $ln -lt $addLines.Count; $ln++) {
                if ($addLines[$ln] -match 'TokenLifeTime\s*=\s*\(\s*\$Global:AuthenticationHeader\.ExpiresOn') {
                    $targetIdx = $ln
                    break
                }
            }

            if ($targetIdx -lt 0) {
                Write-Verbose 'Repair-IntuneWin32AppModule: TokenLifeTime line not found in Add-IntuneWin32App.ps1 — skipping patch 2.'
            }
            else {
                Write-Verbose "Repair-IntuneWin32AppModule: applying patch 2 — $addAppFile (line $($targetIdx + 1))"

                # Detect indentation from the existing line
                $indent = ''
                if ($addLines[$targetIdx] -match '^(\s+)') { $indent = $Matches[1] }

                $replacement = @(
                    "$indent# Patch 2 (IntuneUploader): normalise ExpiresOn so non-US locales (e.g. en-GB) don't"
                    "$indent# produce a culture-formatted string that InvariantCulture DateTime.Parse rejects."
                    "${indent}`$_expiresOn = `$Global:AuthenticationHeader.ExpiresOn"
                    "${indent}if (`$_expiresOn -is [string]) {"
                    "${indent}    try   { `$_expiresOn = [datetime]::Parse(`$_expiresOn, [System.Globalization.CultureInfo]::CurrentCulture) }"
                    "${indent}    catch { `$_expiresOn = [datetime]::UtcNow.AddHours(1) }"
                    "${indent}} elseif (`$_expiresOn -is [System.DateTimeOffset]) {"
                    "${indent}    `$_expiresOn = `$_expiresOn.UtcDateTime"
                    "${indent}}"
                    "${indent}`$TokenLifeTime = (`$_expiresOn - (Get-Date).ToUniversalTime()).Minutes"
                )

                $newLines = [System.Collections.Generic.List[string]]::new()
                for ($ln = 0; $ln -lt $addLines.Count; $ln++) {
                    if ($ln -eq $targetIdx) {
                        $newLines.AddRange([string[]]$replacement)
                    }
                    else {
                        $newLines.Add($addLines[$ln])
                    }
                }

                try {
                    Set-Content -Path $addAppFile -Value $newLines -Encoding UTF8 -Force
                    Write-Verbose 'Repair-IntuneWin32AppModule: patch 2 applied successfully.'
                    $patched2 = $true
                }
                catch {
                    Write-Warning "Repair-IntuneWin32AppModule: could not write patch 2 — $_"
                }
            }
        }
    }

    return $patched1 -or $patched2
}
