<#
.SYNOPSIS
PSAppDeployToolkit.MSStore - provisions Microsoft Store apps for all users.

.DESCRIPTION
Resolves the latest version of a Microsoft Store app and its framework dependencies directly from
Microsoft's own endpoints, then provisions it with Add-AppxProvisionedPackage so every user gets it:

    1. displaycatalog.mp.microsoft.com  Store product ID -> package family name + WuCategoryId
    2. fe3.delivery.mp.microsoft.com    WuCategoryId -> every package version and dependency (SyncUpdates)
    3. fe3.delivery.mp.microsoft.com    package -> signed download URL (GetExtendedUpdateInfo2)
    4. Download, verify the SHA256 that FE3 publishes, then provision.

No third-party site, Store sign-in or WinGet is needed, and it runs as SYSTEM (Intune, Azure Image Builder).
The FE3 endpoints are the ones the Store client itself uses. They are not a documented public API, so if
Microsoft changes them this module needs updating.

Only MSIX/AppX Store apps can be provisioned. Win32 apps listed in the Store (IDs usually starting with XP)
have no WuCategoryId. Use the PSAppDeployToolkit.WinGet extension with -Source msstore for those.

Exported functions:
    Get-ADTMSStoreApp        Resolves the latest package + dependencies (no download).
    Save-ADTMSStoreApp       Downloads and hash-verifies what Get-ADTMSStoreApp resolved.
    Install-ADTMSStoreApp    Resolves, downloads and provisions for all users (skips if already current).
    Uninstall-ADTMSStoreApp  Deprovisions and removes the app for all users.
#>

$Script:MSStoreConfig = @{
    CatalogUri = 'https://displaycatalog.mp.microsoft.com/v7.0/products/{0}?market={1}&languages=en-US,en,neutral'
    Fe3Uri     = 'https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx'
    ServiceNs  = 'http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService'

    # Update IDs the Store client reports as already installed. SyncUpdates needs these to return app packages.
    NonLeafUpdateIds = @(
        1, 2, 3, 11, 19, 544, 549, 2359974, 2359977, 5169044, 8788830, 23110993, 23110994, 54341900, 54343656,
        59830006, 59830007, 59830008, 60484010, 62450018, 62450019, 62450020, 66027979, 66053150, 97657898,
        98822896, 98959022, 98959023, 98959024, 98959025, 98959026, 104433538, 104900364, 105489019, 117765322,
        129905029, 130040031, 132387090, 132393049, 133399034, 138537048, 140377312, 143747671, 158941041,
        158941042, 158941043, 158941044, 159123858, 159130928, 164836897, 164847386, 164848327, 164852241,
        164852246, 164852252, 164852253
    )
}


##================================================
## MARK: Private helpers
##================================================

function Initialize-ADTMSStoreTls
{
    # Windows PowerShell 5.1 can default to TLS 1.0/1.1. Microsoft's Store endpoints require TLS 1.2.
    $current = [System.Net.ServicePointManager]::SecurityProtocol
    if (($current -band [System.Net.SecurityProtocolType]::Tls12) -eq 0)
    {
        [System.Net.ServicePointManager]::SecurityProtocol = $current -bor [System.Net.SecurityProtocolType]::Tls12
    }
}

function Get-ADTMSStoreDeviceArchitecture
{
    # PROCESSOR_ARCHITEW6432 is set when running in a 32-bit process on a 64-bit OS.
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch)
    {
        'ARM64' { return 'arm64' }
        'x86' { return 'x86' }
        default { return 'x64' }
    }
}

function Get-ADTMSStoreDeviceAttributes
{
    # The device description FE3 uses to decide which packages apply. Built from the real OS so the
    # Store service only offers versions this device can run.
    param ([Parameter(Mandatory = $true)][System.String]$Architecture)

    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $osVersion = '10.0.{0}.{1}' -f $cv.CurrentBuildNumber, $cv.UBR
    $osArch = @{ x64 = 'AMD64'; arm64 = 'ARM64'; x86 = 'X86' }[$Architecture]
    $skuId = try { (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).OperatingSystemSKU } catch { 48 }

    $attributes = @(
        'E:BranchReadinessLevel=CB'
        'CurrentBranch=rs_prerelease'
        'FlightRing=Retail'
        'AttrDataVer=331'
        'InstallLanguage=en-US'
        'OSUILocale=en-US'
        'InstallationType=Client'
        'FlightingBranchName='
        "OSSkuId=$skuId"
        'App=WU_STORE'
        'AppVer=1407.2503.28012.0'
        "OSArchitecture=$osArch"
        'IsFlightingEnabled=0'
        'TelemetryLevel=1'
        'DefaultUserRegion=244'
        "WuClientVer=$osVersion"
        "OSVersion=$osVersion"
        'DeviceFamily=Windows.Desktop'
    ) -join '&'

    return [System.Security.SecurityElement]::Escape($attributes)
}

function Invoke-ADTMSStoreWithRetry
{
    # Runs a script block, retrying transient network/service failures with a growing back-off.
    param
    (
        [Parameter(Mandatory = $true)][System.String]$Description,
        [Parameter(Mandatory = $true)][System.Management.Automation.ScriptBlock]$ScriptBlock,
        [System.Int32]$MaxAttempts = 3
    )

    for ($attempt = 1; ; $attempt++)
    {
        try
        {
            return (& $ScriptBlock)
        }
        catch
        {
            # Don't retry client errors (404 etc.): they won't succeed on a second try. Timeouts/throttling are retried.
            $statusCode = 0
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $statusCode = [System.Int32]$_.Exception.Response.StatusCode }
            $isClientError = $statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -notin 408, 429

            if ($attempt -ge $MaxAttempts -or $isClientError)
            {
                throw "$Description failed after $MaxAttempts attempt(s): $($_.Exception.Message)"
            }
            Write-ADTLogEntry -Message "$Description failed (attempt $attempt of $MaxAttempts): $($_.Exception.Message) Retrying in $($attempt * 10) seconds." -Severity 2
            Start-Sleep -Seconds ($attempt * 10)
        }
    }
}

function Invoke-ADTMSStoreSoapRequest
{
    # Sends one SOAP request to the Store delivery service (FE3) and returns the response as XML.
    param
    (
        [Parameter(Mandatory = $true)][System.String]$Action,
        [Parameter(Mandatory = $true)][System.String]$Body,
        [System.Management.Automation.SwitchParameter]$Secured
    )

    $uri = if ($Secured) { "$($Script:MSStoreConfig.Fe3Uri)/secured" } else { $Script:MSStoreConfig.Fe3Uri }
    $now = [System.DateTime]::UtcNow
    $envelope = @"
<s:Envelope xmlns:a="http://www.w3.org/2005/08/addressing" xmlns:s="http://www.w3.org/2003/05/soap-envelope">
<s:Header>
<a:Action s:mustUnderstand="1">http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService/$Action</a:Action>
<a:MessageID>urn:uuid:$([System.Guid]::NewGuid())</a:MessageID>
<a:To s:mustUnderstand="1">$uri</a:To>
<o:Security s:mustUnderstand="1" xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
<Timestamp xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"><Created>$($now.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))</Created><Expires>$($now.AddMinutes(5).ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))</Expires></Timestamp>
<wuws:WindowsUpdateTicketsToken wsu:id="ClientMSA" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wuws="http://schemas.microsoft.com/msus/2014/10/WindowsUpdateAuthorization">
<TicketType Name="MSA" Version="1.0" Policy="MBI_SSL"><User/></TicketType>
<TicketType Name="AAD" Version="1.0" Policy="MBI_SSL"></TicketType>
</wuws:WindowsUpdateTicketsToken>
</o:Security>
</s:Header>
<s:Body>$Body</s:Body>
</s:Envelope>
"@

    $response = Invoke-ADTMSStoreWithRetry -Description "Microsoft Store delivery service request [$Action]" -ScriptBlock {
        Invoke-WebRequest -Uri $uri -Method Post -Body $envelope -ContentType 'application/soap+xml; charset=utf-8' -UseBasicParsing
    }
    return [System.Xml.XmlDocument]$response.Content
}

function Get-ADTMSStoreXmlChild
{
    # Namespace-agnostic child lookup for FE3 responses.
    param ([System.Xml.XmlNode]$Node, [System.String]$Name)
    return $Node.SelectSingleNode("*[local-name()='$Name']")
}

function Test-ADTMSStoreFileDigest
{
    # Verifies a downloaded file against the digest FE3 published for it (SHA256 when available).
    param
    (
        [Parameter(Mandatory = $true)][System.String]$LiteralPath,
        [Parameter(Mandatory = $true)][System.Object]$Package
    )

    if ($Package.Sha256Digest) { $algorithm = 'SHA256'; $expected = $Package.Sha256Digest }
    else { $algorithm = 'SHA1'; $expected = $Package.Sha1Digest }

    $expectedHex = [System.BitConverter]::ToString([System.Convert]::FromBase64String($expected)) -replace '-'
    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm $algorithm).Hash -eq $expectedHex
}

function Get-ADTMSStorePackageUrl
{
    # Asks FE3 for the signed download URL of one package. URLs are short-lived, so call this just before downloading.
    param
    (
        [Parameter(Mandatory = $true)][System.Object]$Package,
        [Parameter(Mandatory = $true)][System.String]$DeviceAttributes
    )

    $ns = $Script:MSStoreConfig.ServiceNs
    $body = "<GetExtendedUpdateInfo2 xmlns=`"$ns`"><updateIDs><UpdateIdentity><UpdateID>$($Package.UpdateId)</UpdateID><RevisionNumber>$($Package.RevisionNumber)</RevisionNumber></UpdateIdentity></updateIDs><infoTypes><XmlUpdateFragmentType>FileUrl</XmlUpdateFragmentType><XmlUpdateFragmentType>FileDecryption</XmlUpdateFragmentType></infoTypes><deviceAttributes>$DeviceAttributes</deviceAttributes></GetExtendedUpdateInfo2>"
    $response = Invoke-ADTMSStoreSoapRequest -Action 'GetExtendedUpdateInfo2' -Body $body -Secured

    # The response also contains the package's blockmap URL. Match on the file digest to get the package itself.
    foreach ($location in $response.SelectNodes("//*[local-name()='FileLocation']"))
    {
        if ((Get-ADTMSStoreXmlChild -Node $location -Name 'FileDigest').InnerText -eq $Package.Sha1Digest)
        {
            return (Get-ADTMSStoreXmlChild -Node $location -Name 'Url').InnerText
        }
    }
    throw "The Microsoft Store delivery service did not return a download URL for [$($Package.PackageFullName)]."
}

function Get-ADTMSStoreProvisionedPackage
{
    # Highest provisioned version of a package identity name, or $null.
    param ([Parameter(Mandatory = $true)][System.String]$Name)

    return Get-AppxProvisionedPackage -Online |
        Where-Object { $_.DisplayName -eq $Name } |
        Sort-Object -Property { [System.Version]$_.Version } -Descending |
        Select-Object -First 1
}

function Register-ADTMSStoreAppForLoggedOnUsers
{
    # Provisioned apps reach new users at first sign-in. This registers the app for users who are
    # already signed in so they don't have to sign out. A failure is only a warning.
    param ([Parameter(Mandatory = $true)][System.String]$PackageFamilyName)

    $users = @(Get-ADTLoggedOnUser)
    if ($users.Count -eq 0)
    {
        Write-ADTLogEntry -Message 'No users are signed in. Windows registers the app for each user when they sign in.'
        return
    }

    $command = "`$ProgressPreference = 'SilentlyContinue'; try { Add-AppxPackage -RegisterByFamilyName -MainPackage '$PackageFamilyName' -ErrorAction Stop; exit 0 } catch { exit 1 }"
    $encodedCommand = Out-ADTPowerShellEncodedCommand -Command $command
    $powershellExe = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

    foreach ($user in $users)
    {
        try
        {
            Write-ADTLogEntry -Message "Registering [$PackageFamilyName] for signed-in user [$($user.NTAccount)] (session $($user.SessionId))."
            $result = Start-ADTProcessAsUser -Username $user.NTAccount -FilePath $powershellExe -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand -CreateNoWindow -IgnoreExitCodes '*' -Timeout ([System.TimeSpan]::FromMinutes(5)) -PassThru
            if ($result.ExitCode -ne 0)
            {
                Write-ADTLogEntry -Message "Registration for [$($user.NTAccount)] returned exit code $($result.ExitCode). The app appears for them at next sign-in." -Severity 2
            }
        }
        catch
        {
            Write-ADTLogEntry -Message "Unable to register the app for [$($user.NTAccount)]: $($_.Exception.Message) The app appears for them at next sign-in." -Severity 2
        }
    }
}


##================================================
## MARK: Public functions
##================================================

function Get-ADTMSStoreApp
{
    <#
    .SYNOPSIS
    Resolves the latest package of a Microsoft Store app and its dependencies for this device. Nothing is downloaded.

    .PARAMETER ProductId
    The Store product ID, e.g. 9MVC8P1Q3B29 (the ID in the apps.microsoft.com URL or `winget search --source msstore`).

    .PARAMETER Architecture
    Target architecture. Defaults to this device's.

    .PARAMETER Market
    Two-letter Store market used for the catalog lookup. Defaults to US.

    .EXAMPLE
    Get-ADTMSStoreApp -ProductId 9MVC8P1Q3B29
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z0-9]{12,14}$')]
        [System.String]$ProductId,

        [ValidateSet('x64', 'x86', 'arm64')]
        [System.String]$Architecture = (Get-ADTMSStoreDeviceArchitecture),

        [ValidatePattern('^[A-Za-z]{2}$')]
        [System.String]$Market = 'US'
    )

    Initialize-ADTMSStoreTls
    $ProductId = $ProductId.ToUpperInvariant()
    $ns = $Script:MSStoreConfig.ServiceNs

    # 1. Store catalog: product ID -> package family name and the WU category that holds its packages.
    Write-ADTLogEntry -Message "Looking up Microsoft Store product [$ProductId] (market $Market, $Architecture)."
    $catalogUri = $Script:MSStoreConfig.CatalogUri -f $ProductId, $Market
    $notFound = "Microsoft Store product [$ProductId] was not found in the MSIX/AppX catalog (market $Market). Check the ID. Win32 Store apps (IDs usually starting with XP) aren't in this catalog and must be installed with WinGet (-Source msstore)."
    try
    {
        $catalog = Invoke-ADTMSStoreWithRetry -Description 'Microsoft Store catalog lookup' -ScriptBlock {
            Invoke-RestMethod -Uri $catalogUri -UseBasicParsing
        }
    }
    catch
    {
        if ($_.Exception.Message -match '\(404\)') { throw $notFound }
        throw
    }
    if (-not $catalog.Product)
    {
        throw $notFound
    }

    $title = @($catalog.Product.LocalizedProperties)[0].ProductTitle
    $fulfillment = $null
    foreach ($availability in @($catalog.Product.DisplaySkuAvailabilities))
    {
        $data = $availability.Sku.Properties.FulfillmentData
        if ($data -is [System.String]) { $data = $data | ConvertFrom-Json }
        if ($data -and $data.WuCategoryId) { $fulfillment = $data; break }
    }
    if (-not $fulfillment)
    {
        throw "[$title] ($ProductId) is not an MSIX/AppX Store app, so it can't be provisioned. Win32 apps in the Store must be installed with WinGet (-Source msstore)."
    }

    $packageFamilyName = $fulfillment.PackageFamilyName
    $identityName = $packageFamilyName.Split('_')[0]
    Write-ADTLogEntry -Message "Found [$title], package family [$packageFamilyName]."

    # 2. FE3 session cookie.
    $cookieXml = Invoke-ADTMSStoreSoapRequest -Action 'GetCookie' -Body "<GetCookie xmlns=`"$ns`"><oldCookie></oldCookie><lastChange>2015-10-21T17:01:07.1472913Z</lastChange><currentTime>$([System.DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))</currentTime><protocolVersion>1.40</protocolVersion></GetCookie>"
    $cookie = $cookieXml.SelectSingleNode("//*[local-name()='EncryptedData']")
    if (-not $cookie)
    {
        throw 'The Microsoft Store delivery service did not return a session cookie.'
    }

    # 3. SyncUpdates: every version of the app plus the framework packages it depends on.
    $deviceAttributes = Get-ADTMSStoreDeviceAttributes -Architecture $Architecture
    $installedIds = ($Script:MSStoreConfig.NonLeafUpdateIds | ForEach-Object { "<int>$_</int>" }) -join ''
    $syncBody = "<SyncUpdates xmlns=`"$ns`"><cookie><Expiration>2045-03-11T02:02:48Z</Expiration><EncryptedData>$($cookie.InnerText)</EncryptedData></cookie><parameters><ExpressQuery>false</ExpressQuery><InstalledNonLeafUpdateIDs>$installedIds</InstalledNonLeafUpdateIDs><OtherCachedUpdateIDs></OtherCachedUpdateIDs><SkipSoftwareSync>false</SkipSoftwareSync><NeedTwoGroupOutOfScopeUpdates>true</NeedTwoGroupOutOfScopeUpdates><FilterAppCategoryIds><CategoryIdentifier><Id>$($fulfillment.WuCategoryId)</Id></CategoryIdentifier></FilterAppCategoryIds><TreatAppCategoryIdsAsInstalled>true</TreatAppCategoryIdsAsInstalled><AlsoPerformRegularSync>false</AlsoPerformRegularSync><ComputerSpec/><ExtendedUpdateInfoParameters><XmlUpdateFragmentTypes><XmlUpdateFragmentType>Extended</XmlUpdateFragmentType><XmlUpdateFragmentType>LocalizedProperties</XmlUpdateFragmentType><XmlUpdateFragmentType>Eula</XmlUpdateFragmentType></XmlUpdateFragmentTypes><Locales><string>en-US</string><string>en</string></Locales></ExtendedUpdateInfoParameters><ClientPreferredLanguages><string>en-US</string></ClientPreferredLanguages><ProductsParameters><SyncCurrentVersionOnly>false</SyncCurrentVersionOnly><DeviceAttributes>$deviceAttributes</DeviceAttributes><CallerAttributes>Interactive=1;IsSeeker=0;</CallerAttributes><Products/></ProductsParameters></parameters></SyncUpdates>"
    $sync = Invoke-ADTMSStoreSoapRequest -Action 'SyncUpdates' -Body $syncBody

    # File details (name, size, digests) live under ExtendedUpdateInfo; update identities under NewUpdates. Join on ID.
    $fileById = @{}
    foreach ($update in $sync.SelectNodes("//*[local-name()='ExtendedUpdateInfo']/*[local-name()='Updates']/*[local-name()='Update']"))
    {
        $inner = [System.Xml.XmlDocument]"<r>$((Get-ADTMSStoreXmlChild -Node $update -Name 'Xml').InnerText)</r>"
        $file = $inner.SelectSingleNode('/r/Files/File[@InstallerSpecificIdentifier]')
        if ($file) { $fileById[(Get-ADTMSStoreXmlChild -Node $update -Name 'ID').InnerText] = $file }
    }

    $candidates = foreach ($info in $sync.SelectNodes("//*[local-name()='NewUpdates']/*[local-name()='UpdateInfo']"))
    {
        $file = $fileById[(Get-ADTMSStoreXmlChild -Node $info -Name 'ID').InnerText]
        if (-not $file) { continue }
        $inner = [System.Xml.XmlDocument]"<r>$((Get-ADTMSStoreXmlChild -Node $info -Name 'Xml').InnerText)</r>"
        $identity = $inner.SelectSingleNode('/r/UpdateIdentity')
        $moniker = $file.GetAttribute('InstallerSpecificIdentifier')
        $parts = $moniker.Split('_')
        if (-not $identity -or $parts.Count -lt 5) { continue }

        $extension = [System.IO.Path]::GetExtension($file.GetAttribute('FileName')).ToLowerInvariant()
        $sha256 = $file.SelectSingleNode("AdditionalDigest[@Algorithm='SHA256']")
        [pscustomobject]@{
            PackageFullName = $moniker
            Name            = $parts[0]
            Version         = [System.Version]$parts[1]
            Architecture    = $parts[2].ToLowerInvariant()
            Extension       = $extension
            IsBundle        = $extension -match 'bundle$'
            FileName        = "$moniker$extension"
            Size            = [System.Int64]$file.GetAttribute('Size')
            UpdateId        = $identity.GetAttribute('UpdateID')
            RevisionNumber  = $identity.GetAttribute('RevisionNumber')
            Sha1Digest      = $file.GetAttribute('Digest')
            Sha256Digest    = if ($sha256) { $sha256.InnerText } else { $null }
        }
    }

    # 4. Latest main package: bundles are neutral; a single-arch package must match this device.
    $archFilter = @($Architecture, 'neutral')
    $main = $candidates |
        Where-Object { $_.Name -eq $identityName -and ($_.IsBundle -or $_.Architecture -in $archFilter) } |
        Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, @{ Expression = { -not $_.IsBundle } } |
        Select-Object -First 1
    if (-not $main)
    {
        throw "The Microsoft Store delivery service returned no installable package of [$packageFamilyName] for $Architecture."
    }

    # Latest version of each dependency for this architecture. Frameworks install side by side, so this is safe
    # even when an older or newer version is already on the device.
    $dependencies = @(
        $candidates |
            Where-Object { $_.Name -ne $identityName -and $_.Architecture -in $archFilter } |
            Group-Object -Property Name |
            ForEach-Object { $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1 } |
            Sort-Object -Property Name
    )

    Write-ADTLogEntry -Message "Latest version: [$($main.PackageFullName)] ($([System.Math]::Round($main.Size / 1MB, 1)) MB)."
    foreach ($dependency in $dependencies)
    {
        Write-ADTLogEntry -Message "Dependency: [$($dependency.PackageFullName)] ($([System.Math]::Round($dependency.Size / 1MB, 1)) MB)."
    }

    return [pscustomobject]@{
        ProductId         = $ProductId
        Title             = $title
        PackageFamilyName = $packageFamilyName
        Name              = $identityName
        Version           = $main.Version
        Architecture      = $Architecture
        MainPackage       = $main
        Dependencies      = $dependencies
    }
}

function Save-ADTMSStoreApp
{
    <#
    .SYNOPSIS
    Downloads the packages resolved by Get-ADTMSStoreApp and verifies each against the SHA256 published by the Store.

    .PARAMETER InputObject
    The output of Get-ADTMSStoreApp.

    .PARAMETER Path
    Folder to download into. Files that are already there and pass the hash check are reused.

    .OUTPUTS
    An object with MainPackagePath and DependencyPaths.

    .EXAMPLE
    Get-ADTMSStoreApp -ProductId 9MVC8P1Q3B29 | Save-ADTMSStoreApp -Path C:\Temp\PowerApps
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Object]$InputObject,

        [Parameter(Mandatory = $true)]
        [System.String]$Path
    )

    process
    {
        Initialize-ADTMSStoreTls
        if (-not (Test-Path -LiteralPath $Path -PathType Container))
        {
            $null = New-Item -Path $Path -ItemType Directory -Force
        }
        $deviceAttributes = Get-ADTMSStoreDeviceAttributes -Architecture $InputObject.Architecture

        $paths = foreach ($package in (@($InputObject.MainPackage) + @($InputObject.Dependencies)))
        {
            $target = Join-Path -Path $Path -ChildPath $package.FileName
            if ((Test-Path -LiteralPath $target -PathType Leaf) -and (Test-ADTMSStoreFileDigest -LiteralPath $target -Package $package))
            {
                Write-ADTLogEntry -Message "[$($package.FileName)] is already downloaded and verified."
                $target
                continue
            }

            Write-ADTLogEntry -Message "Downloading [$($package.FileName)] ($([System.Math]::Round($package.Size / 1MB, 1)) MB)."
            Invoke-ADTMSStoreWithRetry -Description "Download of [$($package.FileName)]" -ScriptBlock {
                # Resolve the URL on every attempt: the signed URLs expire.
                $url = Get-ADTMSStorePackageUrl -Package $package -DeviceAttributes $deviceAttributes
                Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing
                if (-not (Test-ADTMSStoreFileDigest -LiteralPath $target -Package $package))
                {
                    Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                    throw "The downloaded file failed its hash check."
                }
            }
            Write-ADTLogEntry -Message "Downloaded and verified [$($package.FileName)]."
            $target
        }

        [pscustomobject]@{
            MainPackagePath = @($paths)[0]
            DependencyPaths = @(@($paths) | Select-Object -Skip 1)
        }
    }
}

function Install-ADTMSStoreApp
{
    <#
    .SYNOPSIS
    Provisions the latest version of a Microsoft Store app for all users, straight from the Microsoft Store.

    .DESCRIPTION
    Resolves the latest package, skips the download if that version (or newer) is already provisioned,
    otherwise downloads and hash-verifies it and its dependencies and runs Add-AppxProvisionedPackage.
    Downloads are deleted afterwards. Must run elevated (SYSTEM or admin).

    .PARAMETER ProductId
    The Store product ID, e.g. 9MVC8P1Q3B29.

    .PARAMETER RegisterForLoggedOnUsers
    Also register the app for users who are already signed in, so it appears without signing out.

    .PARAMETER Force
    Download and provision even if the latest version is already provisioned.

    .PARAMETER DownloadPath
    Working folder for the downloads. Defaults to C:\Windows\Temp\PSAppDeployToolkit.MSStore\<ProductId>.

    .PARAMETER KeepDownloads
    Keep the downloaded files instead of deleting them.

    .OUTPUTS
    An object with ProductId, Title, PackageFamilyName, Version and RestartNeeded.

    .EXAMPLE
    Install-ADTMSStoreApp -ProductId 9MVC8P1Q3B29 -RegisterForLoggedOnUsers
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z0-9]{12,14}$')]
        [System.String]$ProductId,

        [ValidateSet('x64', 'x86', 'arm64')]
        [System.String]$Architecture = (Get-ADTMSStoreDeviceArchitecture),

        [ValidatePattern('^[A-Za-z]{2}$')]
        [System.String]$Market = 'US',

        [System.String]$DownloadPath,

        [System.Management.Automation.SwitchParameter]$RegisterForLoggedOnUsers,

        [System.Management.Automation.SwitchParameter]$Force,

        [System.Management.Automation.SwitchParameter]$KeepDownloads
    )

    if (-not $DownloadPath)
    {
        $DownloadPath = Join-Path -Path $env:SystemRoot -ChildPath "Temp\PSAppDeployToolkit.MSStore\$($ProductId.ToUpperInvariant())"
    }

    $app = Get-ADTMSStoreApp -ProductId $ProductId -Architecture $Architecture -Market $Market
    $restartNeeded = $false
    $provisioned = Get-ADTMSStoreProvisionedPackage -Name $app.Name

    if ($provisioned -and ([System.Version]$provisioned.Version -ge $app.Version) -and -not $Force)
    {
        Write-ADTLogEntry -Message "[$($app.Title)] $($provisioned.Version) is already provisioned (latest in the Store is $($app.Version)). Nothing to download."
    }
    else
    {
        if ($provisioned)
        {
            Write-ADTLogEntry -Message "[$($app.Title)] $($provisioned.Version) is provisioned. Updating to $($app.Version)."
        }

        try
        {
            $files = Save-ADTMSStoreApp -InputObject $app -Path $DownloadPath

            $provisionParams = @{
                Online      = $true
                PackagePath = $files.MainPackagePath
                SkipLicense = $true
                Regions     = 'all'
                ErrorAction = 'Stop'
            }
            if ($files.DependencyPaths.Count -gt 0)
            {
                $provisionParams.DependencyPackagePath = [System.String[]]$files.DependencyPaths
            }

            Write-ADTLogEntry -Message "Provisioning [$($app.MainPackage.PackageFullName)] for all users."
            $result = Add-AppxProvisionedPackage @provisionParams
            $restartNeeded = [System.Boolean]$result.RestartNeeded
        }
        finally
        {
            if (-not $KeepDownloads)
            {
                Remove-Item -LiteralPath $DownloadPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $provisioned = Get-ADTMSStoreProvisionedPackage -Name $app.Name
        if (-not $provisioned)
        {
            throw "Add-AppxProvisionedPackage finished, but [$($app.Name)] is not listed as a provisioned package."
        }
        Write-ADTLogEntry -Message "Provisioned [$($app.Title)] $($provisioned.Version) for all users.$(if ($restartNeeded) { ' A restart is required.' })"
    }

    if ($RegisterForLoggedOnUsers)
    {
        Register-ADTMSStoreAppForLoggedOnUsers -PackageFamilyName $app.PackageFamilyName
    }

    return [pscustomobject]@{
        ProductId         = $app.ProductId
        Title             = $app.Title
        PackageFamilyName = $app.PackageFamilyName
        Version           = $provisioned.Version
        RestartNeeded     = $restartNeeded
    }
}

function Uninstall-ADTMSStoreApp
{
    <#
    .SYNOPSIS
    Deprovisions a Store app and removes it for every user. Shared framework dependencies are left in place.

    .PARAMETER PackageFamilyName
    e.g. MicrosoftCorporationII.PowerAppsforWindows10_8wekyb3d8bbwe. Works offline: no Store lookup is made.

    .EXAMPLE
    Uninstall-ADTMSStoreApp -PackageFamilyName 'MicrosoftCorporationII.PowerAppsforWindows10_8wekyb3d8bbwe'
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[^_\s]+_[a-z0-9]{13}$')]
        [System.String]$PackageFamilyName
    )

    $name = $PackageFamilyName.Split('_')[0]
    $removed = $false

    # Deprovision first so Windows doesn't re-register it for users at their next sign-in.
    foreach ($package in @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $name }))
    {
        Write-ADTLogEntry -Message "Deprovisioning [$($package.PackageName)]."
        $null = Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop
        $removed = $true
    }

    foreach ($package in @(Get-AppxPackage -AllUsers -Name $name | Where-Object { $_.PackageFamilyName -eq $PackageFamilyName }))
    {
        Write-ADTLogEntry -Message "Removing [$($package.PackageFullName)] for all users."
        Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
        $removed = $true
    }

    if (-not $removed)
    {
        Write-ADTLogEntry -Message "[$PackageFamilyName] is not provisioned or installed for any user. Nothing to remove."
    }
}
