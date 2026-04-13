<#
.SYNOPSIS
    Microsoft Graph API helper with layered auth fallback — never prompts interactively.

.DESCRIPTION
    Attempts Graph calls in order, stopping at the first that succeeds:

      1. Invoke-MSGraphRequest (if exported by IntuneWin32App)
      2. $Global:AuthenticationHeader set by Connect-MSIntuneGraph + Invoke-RestMethod
         (most IntuneWin32App versions store the bearer token in global scope)
      3. $script:AuthenticationHeader via module scope invocation
         (older versions that store it as script-scope)
      4. Get-MsalToken -Silent with login hint + Invoke-RestMethod

    If all fail, throws with the actual last error. Never opens a browser.
#>

function Invoke-TenantGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [ValidateSet('GET','POST','PATCH','DELETE')]
        [string]$Method = 'GET',

        [object]$Body = $null,

        [string]$ClientID = '',
        [string]$TenantID = ''
    )

    $bodyJson  = if ($Body) { $Body | ConvertTo-Json -Depth 10 -Compress } else { $null }
    $lastError = $null

    # Resolve ClientID/TenantID from globals if not passed
    if (-not $ClientID -and $global:IntuneUploaderClientID) { $ClientID = $global:IntuneUploaderClientID }
    if (-not $TenantID -and $global:IntuneUploaderTenantID) { $TenantID = $global:IntuneUploaderTenantID }

    # Helper: make a REST call with a given header hashtable
    function Invoke-WithHeader {
        param([hashtable]$Headers)
        $h = @{ 'Content-Type' = 'application/json' }
        foreach ($kv in $Headers.GetEnumerator()) {
            if ($kv.Key -ne 'ExpiresOn') { $h[$kv.Key] = $kv.Value }
        }
        $p = @{ Uri = $Url; Method = $Method; Headers = $h }
        if ($bodyJson) { $p.Body = $bodyJson }
        Invoke-RestMethod @p
    }

    # ── Method 1 ── Invoke-MSGraphRequest directly (if exported by this module version)
    if (Get-Command 'Invoke-MSGraphRequest' -ErrorAction SilentlyContinue) {
        try {
            $p = @{ HttpMethod = $Method; Url = $Url }
            if ($bodyJson) { $p.Body = $bodyJson }
            return Invoke-MSGraphRequest @p
        }
        catch { $lastError = $_; Write-Verbose "Method 1 (Invoke-MSGraphRequest): $_" }
    }

    # ── Method 2 ── $Global:AuthenticationHeader (most IntuneWin32App versions)
    # Connect-MSIntuneGraph stores the bearer token in global scope as $Global:AuthenticationHeader.
    if ($Global:AuthenticationHeader -and $Global:AuthenticationHeader['Authorization']) {
        try { return Invoke-WithHeader -Headers $Global:AuthenticationHeader }
        catch {
            $lastError = $_
            # 4xx errors are permission/resource problems — a different auth method won't fix them
            if ($_ -match '40[13467]|Forbidden|Unauthorized|Bad Request|Not Found') { throw }
            Write-Verbose "Method 2 (Global:AuthenticationHeader): $_"
        }
    }

    # ── Method 3 ── $script:AuthenticationHeader via module scope (some older versions)
    $intuneModule = Get-Module 'IntuneWin32App' -ErrorAction SilentlyContinue
    if ($intuneModule) {
        try {
            $scriptHeader = & $intuneModule { $script:AuthenticationHeader }
            if ($scriptHeader -and $scriptHeader['Authorization']) {
                return Invoke-WithHeader -Headers $scriptHeader
            }
        }
        catch {
            $lastError = $_
            if ($_ -match '40[13467]|Forbidden|Unauthorized|Bad Request|Not Found') { throw }
            Write-Verbose "Method 3 (script:AuthenticationHeader): $_"
        }
    }

    # ── Method 4 ── MSAL.PS silent token with login hint
    if ($ClientID -and $TenantID) {
        try {
            Import-Module MSAL.PS -ErrorAction Stop
            $msalParams = @{
                ClientId = $ClientID
                TenantId = $TenantID
                Scopes   = 'https://graph.microsoft.com/.default'
                Silent   = $true
            }
            if ($global:IntuneUploaderLoginHint) { $msalParams.LoginHint = $global:IntuneUploaderLoginHint }
            $token     = Get-MsalToken @msalParams -ErrorAction Stop
            $headers   = @{ Authorization = "Bearer $($token.AccessToken)"; 'Content-Type' = 'application/json' }
            $irmParams = @{ Uri = $Url; Method = $Method; Headers = $headers }
            if ($bodyJson) { $irmParams.Body = $bodyJson }
            return Invoke-RestMethod @irmParams
        }
        catch { $lastError = $_; Write-Verbose "Method 4 (MSAL silent): $_" }
    }

    throw "Graph API call failed. $lastError"
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
