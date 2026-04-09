<#
.SYNOPSIS
    Robust Microsoft Graph API helper that works regardless of IntuneWin32App module version.

.DESCRIPTION
    Tries Invoke-MSGraphRequest (IntuneWin32App) first, then falls back to MSAL.PS
    for a silent token + Invoke-RestMethod.

    Returns the parsed response object, or throws on failure.
#>

function Invoke-TenantGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [ValidateSet('GET','POST','PATCH','DELETE')]
        [string]$Method = 'GET',

        [object]$Body = $null,

        # Required for MSAL fallback
        [string]$ClientID = '',
        [string]$TenantID = ''
    )

    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Depth 10 -Compress } else { $null }

    # Method 1 — IntuneWin32App module's Invoke-MSGraphRequest
    $fn = Get-Command 'Invoke-MSGraphRequest' -ErrorAction SilentlyContinue
    if ($fn) {
        try {
            $params = @{ HttpMethod = $Method; Url = $Url }
            if ($bodyJson) { $params.Body = $bodyJson }
            return Invoke-MSGraphRequest @params
        }
        catch {
            Write-Verbose "Invoke-MSGraphRequest failed: $_ — trying MSAL fallback"
        }
    }

    # Method 2 — MSAL.PS silent token + Invoke-RestMethod
    if (-not $ClientID -or -not $TenantID) {
        throw "Graph request failed: Invoke-MSGraphRequest not available and no ClientID/TenantID supplied for MSAL fallback."
    }

    try {
        Import-Module MSAL.PS -ErrorAction Stop
        $tokenParams = @{
            ClientId = $ClientID
            TenantId = $TenantID
            Scopes   = 'https://graph.microsoft.com/.default'
            Silent   = $true
        }
        $token   = Get-MsalToken @tokenParams -ErrorAction Stop
        $headers = @{
            Authorization  = "Bearer $($token.AccessToken)"
            'Content-Type' = 'application/json'
        }

        $irmParams = @{ Uri = $Url; Method = $Method; Headers = $headers }
        if ($bodyJson) { $irmParams.Body = $bodyJson }
        return Invoke-RestMethod @irmParams
    }
    catch {
        # MSAL silent failed — try interactive as last resort
        try {
            $token   = Get-MsalToken -ClientId $ClientID -TenantId $TenantID `
                                     -Scopes 'https://graph.microsoft.com/.default' -Interactive -ErrorAction Stop
            $headers = @{
                Authorization  = "Bearer $($token.AccessToken)"
                'Content-Type' = 'application/json'
            }
            $irmParams = @{ Uri = $Url; Method = $Method; Headers = $headers }
            if ($bodyJson) { $irmParams.Body = $bodyJson }
            return Invoke-RestMethod @irmParams
        }
        catch {
            throw "Graph API call failed after all attempts: $_"
        }
    }
}

# Convenience wrapper for GET calls that auto-pages through @odata.nextLink
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
