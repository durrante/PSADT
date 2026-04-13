<#
.SYNOPSIS
    Patches the installed IntuneWin32App module to support modern Windows releases and ARM64.

.DESCRIPTION
    The MSEndpointMgr IntuneWin32App module ships with a ValidateSet in
    New-IntuneWin32AppRequirementRule that only covers OS versions up to W11_22H2
    and architectures up to x64/x86/All.

    This function overwrites that file with an updated version supporting:
      - OS:   W10_1607 through W11_24H2  (W11_25H2 excluded — not yet accepted by Intune API)
      - Arch: x64, x86, arm64, x64x86, AllWithARM64

    Safe to call multiple times — skips if already patched at the correct version.
    Returns $true if the patch was applied, $false if already up to date.
#>

function Repair-IntuneWin32AppModule {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $moduleBase = (Get-Module IntuneWin32App -ListAvailable |
                   Sort-Object Version -Descending |
                   Select-Object -First 1).ModuleBase

    if (-not $moduleBase) {
        Write-Warning 'Repair-IntuneWin32AppModule: IntuneWin32App module not found — skipping patch.'
        return $false
    }

    $requirementRuleFile = Join-Path $moduleBase 'Public\New-IntuneWin32AppRequirementRule.ps1'
    if (-not (Test-Path $requirementRuleFile)) {
        Write-Warning "Repair-IntuneWin32AppModule: $requirementRuleFile not found — skipping patch."
        return $false
    }

    # Already patched at the correct version?
    # W11_23H2 present = our patch has been applied.
    # W11_25H2 absent  = Intune API doesn't support it yet; older patch revisions included it.
    # If both conditions hold we are up to date. If W11_25H2 is still present we need to re-patch.
    $content = Get-Content $requirementRuleFile -Raw
    if ($content -match 'W11_23H2' -and $content -notmatch 'W11_25H2' -and $content -match 'x64arm64') {
        Write-Verbose 'Repair-IntuneWin32AppModule: module already fully patched.'
        return $false
    }

    Write-Verbose "Repair-IntuneWin32AppModule: applying patch for W11_23H2, W11_24H2 and ARM64 — $requirementRuleFile"

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
        Write-Verbose "Repair-IntuneWin32AppModule: patch applied successfully."
        return $true
    }
    catch {
        Write-Warning "Repair-IntuneWin32AppModule: could not write patch — $_"
        return $false
    }
}
