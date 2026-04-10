<#
.SYNOPSIS
    Microsoft Graph API helper that uses the IntuneWin32App module's stored auth token.

.DESCRIPTION
    Tries Invoke-MSGraphRequest (IntuneWin32App module) first — this uses the token
    cached by Connect-MSIntuneGraph with no additional prompts.

    Falls back to MSAL.PS silent token only if the module call fails. NEVER prompts
    interactively — if unauthenticated, throws a clear "not connected" error.

    Call Connect-MSIntuneGraph once (in the main window) before using this function.
#>

function Invoke-TenantGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [ValidateSet('GET','POST','PATCH','DELETE')]
        [string]$Method = 'GET',

        [object]$Body = $null,

        # Used for MSAL silent fallback only (never for interactive login)
        [string]$ClientID = '',
        [string]$TenantID = ''
    )

    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Depth 10 -Compress } else { $null }

    # Resolve ClientID/TenantID from globals if not passed
    if (-not $ClientID -and $global:IntuneUploaderClientID) { $ClientID = $global:IntuneUploaderClientID }
    if (-not $TenantID -and $global:IntuneUploaderTenantID) { $TenantID = $global:IntuneUploaderTenantID }

    # Method 1 — IntuneWin32App module's Invoke-MSGraphRequest
    # Uses the token stored by Connect-MSIntuneGraph — no browser, no prompt
    $fn = Get-Command 'Invoke-MSGraphRequest' -ErrorAction SilentlyContinue
    if ($fn) {
        try {
            $params = @{ HttpMethod = $Method; Url = $Url }
            if ($bodyJson) { $params.Body = $bodyJson }
            return Invoke-MSGraphRequest @params
        }
        catch {
            Write-Verbose "Invoke-MSGraphRequest failed: $_ — trying MSAL silent fallback"
        }
    }

    # Method 2 — MSAL.PS silent token (uses cached refresh token, no browser)
    if ($ClientID -and $TenantID) {
        try {
            Import-Module MSAL.PS -ErrorAction Stop
            $token = Get-MsalToken -ClientId $ClientID -TenantId $TenantID `
                                   -Scopes 'https://graph.microsoft.com/.default' `
                                   -Silent -ErrorAction Stop
            $headers = @{
                Authorization  = "Bearer $($token.AccessToken)"
                'Content-Type' = 'application/json'
            }
            $irmParams = @{ Uri = $Url; Method = $Method; Headers = $headers }
            if ($bodyJson) { $irmParams.Body = $bodyJson }
            return Invoke-RestMethod @irmParams
        }
        catch {
            Write-Verbose "MSAL silent token failed: $_"
        }
    }

    # Both methods failed — never prompt interactively
    throw "Not connected to Intune. Click 'Connect to Intune' in the main window and sign in first."
}

# Convenience wrapper: GET calls that auto-page through @odata.nextLink
function Get-TenantGraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [string]$ClientID = '',
        [string]$TenantID = ''
    )

    $allItems = [System.Collections.Generic.List[object]]::new()
    $nextUrl  = $Url

    do {
        $resp = Invoke-TenantGraphRequest -Url $nextUrl -ClientID $ClientID -TenantID $TenantID
        if ($resp.value) { $allItems.AddRange([object[]]$resp.value) }
        $nextUrl = $resp.'@odata.nextLink'
    } while ($nextUrl)

    return $allItems
}
