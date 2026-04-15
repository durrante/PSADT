<#
.SYNOPSIS
    WPF main dashboard window for the Intune Win32 App Uploader.

.DESCRIPTION
    Shows the main application window with:
      - Connection status (tenant + user)
      - Action buttons: Upload App, Bulk Upload, Templates, Settings
      - Activity log showing results of uploads
      - Recent uploads list

    Calls Show-AppUploadForm for single-app uploads,
    and Invoke-ProcessApp to run the actual package/upload/document pipeline.
#>

function Show-MainWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [string]$TemplateFolder,
        [string]$ToolRoot
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms | Out-Null

    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Intune Win32 App Uploader"
    Width="1000" Height="720"
    WindowStartupLocation="CenterScreen"
    MinWidth="700" MinHeight="520">

  <Window.Resources>
    <Style x:Key="TileBtn" TargetType="Button">
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="border" Background="{TemplateBinding Background}"
                    CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="border" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="border" Property="Opacity" Value="0.7"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="border" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="64"/>   <!-- Header -->
      <RowDefinition Height="Auto"/> <!-- Status bar -->
      <RowDefinition Height="Auto"/> <!-- Action buttons -->
      <RowDefinition Height="*"/>    <!-- Log area -->
      <RowDefinition Height="Auto"/> <!-- Footer -->
    </Grid.RowDefinitions>

    <!-- ═══ HEADER ═══ -->
    <Border Grid.Row="0">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
          <GradientStop Color="#0693E3" Offset="0"/>
          <GradientStop Color="#9B51E0" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Grid Margin="20,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Intune Win32 App Uploader" FontSize="20" FontWeight="Light" Foreground="White"/>
          <TextBlock Text="Modern Workspace Hub — Intune application packaging and deployment" FontSize="11"
                     Foreground="#D4C5F9" Margin="0,1,0,0"/>
        </StackPanel>
        <Button x:Name="BtnSignOut" Content="Sign Out" HorizontalAlignment="Right"
                VerticalAlignment="Center" Padding="10,4" Background="#2D1B69"
                Foreground="White" BorderThickness="0" Cursor="Hand"/>
      </Grid>
    </Border>

    <!-- ═══ CONNECTION STATUS ═══ -->
    <Border Grid.Row="1" Background="#F0F0F0" BorderBrush="#DDD" BorderThickness="0,0,0,1" Padding="20,7">
      <Grid>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse x:Name="ConnDot" Width="10" Height="10" Fill="#D32F2F" Margin="0,0,8,0"/>
          <TextBlock x:Name="TxtStatus" Text="Not connected" VerticalAlignment="Center" FontSize="12"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnRefresh" Content="Refresh Data" Visibility="Collapsed"
                  Padding="10,4" FontSize="12" Background="#5BA3E8" Foreground="White" BorderThickness="0"
                  Cursor="Hand" Margin="0,0,8,0"/>
          <Button x:Name="BtnConnect" Content="Connect to Intune"
                  Padding="10,4" FontSize="12" Background="#4A2B8F" Foreground="White" BorderThickness="0"
                  Cursor="Hand"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ═══ ACTION BUTTONS ═══ -->
    <Grid Grid.Row="2" Margin="16,14,16,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="8"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="8"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="8"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Button x:Name="BtnUploadSingle" Grid.Column="0" Height="72"
              Background="#5BA3E8" Foreground="White" Style="{StaticResource TileBtn}">
        <StackPanel>
          <TextBlock Text="&#xE898;" FontFamily="Segoe MDL2 Assets" FontSize="22" HorizontalAlignment="Center" Margin="0,0,0,4"/>
          <TextBlock Text="Upload App" FontSize="12"/>
        </StackPanel>
      </Button>

      <Button x:Name="BtnBulkUpload" Grid.Column="2" Height="72"
              Background="#3A2673" Foreground="White" Style="{StaticResource TileBtn}">
        <StackPanel>
          <TextBlock Text="&#xE838;" FontFamily="Segoe MDL2 Assets" FontSize="22" HorizontalAlignment="Center" Margin="0,0,0,4"/>
          <TextBlock Text="Bulk Upload" FontSize="12"/>
        </StackPanel>
      </Button>

      <Button x:Name="BtnTemplates" Grid.Column="4" Height="72"
              Background="#4A2B8F" Foreground="White" Style="{StaticResource TileBtn}">
        <StackPanel>
          <TextBlock Text="&#xE70B;" FontFamily="Segoe MDL2 Assets" FontSize="22" HorizontalAlignment="Center" Margin="0,0,0,4"/>
          <TextBlock Text="Templates" FontSize="12"/>
        </StackPanel>
      </Button>

      <Button x:Name="BtnSettings" Grid.Column="6" Height="72"
              Background="#2D1B69" Foreground="White" Style="{StaticResource TileBtn}">
        <StackPanel>
          <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="22" HorizontalAlignment="Center" Margin="0,0,0,4"/>
          <TextBlock Text="Settings" FontSize="12"/>
        </StackPanel>
      </Button>
    </Grid>

    <!-- ═══ LOG AREA ═══ -->
    <Grid Grid.Row="3" Margin="16,12,16,0">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0" Margin="0,0,0,6">
        <TextBlock Text="Activity Log" FontWeight="SemiBold" FontSize="13" VerticalAlignment="Center"/>
        <Button x:Name="BtnClearLog" Content="Clear" HorizontalAlignment="Right"
                Padding="8,2" FontSize="11" Background="Transparent" BorderBrush="#CCC"
                Cursor="Hand"/>
      </Grid>

      <Border Grid.Row="1" BorderBrush="#CCC" BorderThickness="1" CornerRadius="3">
        <ScrollViewer x:Name="LogScroller" VerticalScrollBarVisibility="Auto">
          <TextBox x:Name="TxtLog"
                   IsReadOnly="True"
                   TextWrapping="Wrap"
                   AcceptsReturn="True"
                   BorderThickness="0"
                   Padding="8"
                   FontFamily="Consolas"
                   FontSize="12"
                   Background="Transparent"
                   VerticalAlignment="Top"/>
        </ScrollViewer>
      </Border>
    </Grid>

    <!-- ═══ FOOTER ═══ -->
    <Border Grid.Row="4" Background="#F5F5F5" BorderBrush="#DDD" BorderThickness="0,1,0,0" Padding="16,5">
      <Grid>
        <TextBlock x:Name="TxtFooter" Text="Ready" FontSize="11" Foreground="#666" VerticalAlignment="Center"/>
        <TextBlock Text="IntuneWin32App module by MSEndpointMgr" FontSize="10" Foreground="#AAA"
                   HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </Grid>
    </Border>

  </Grid>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    function Find { param($n) $window.FindName($n) }

    $connDot        = Find 'ConnDot'
    $txtStatus      = Find 'TxtStatus'
    $btnConnect     = Find 'BtnConnect'
    $btnRefresh     = Find 'BtnRefresh'
    $btnSignOut     = Find 'BtnSignOut'
    $btnUploadSingle = Find 'BtnUploadSingle'
    $btnBulkUpload  = Find 'BtnBulkUpload'
    $btnTemplates   = Find 'BtnTemplates'
    $btnSettings    = Find 'BtnSettings'
    $txtLog         = Find 'TxtLog'
    $logScroller    = Find 'LogScroller'
    $btnClearLog    = Find 'BtnClearLog'
    $txtFooter      = Find 'TxtFooter'

    $script:connected          = $false
    $script:availableCategories = @()
    $script:availableFilters    = @()

    #region Helpers

    function Write-Log {
        param([string]$Text, [string]$Level = 'Info')
        $prefix = switch ($Level) {
            'OK'   { '[OK]   ' }
            'Warn' { '[WARN] ' }
            'Fail' { '[FAIL] ' }
            default{ '[INFO] ' }
        }
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $line = "$timestamp  $prefix $Text`n"
        $txtLog.Dispatcher.Invoke([action]{
            $txtLog.AppendText($line)
            $logScroller.ScrollToEnd()
        })
    }

    function Set-Connected {
        param([string]$UserDisplay = '')
        $connDot.Fill              = [System.Windows.Media.Brushes]::Green
        $txtStatus.Text            = if ($UserDisplay) { "Connected as $UserDisplay" } else { 'Connected' }
        $txtFooter.Text            = 'Connected to Intune'
        $script:connected          = $true
        $btnRefresh.Visibility     = [System.Windows.Visibility]::Visible
    }

    function Set-Disconnected {
        $connDot.Fill              = [System.Windows.Media.Brushes]::Red
        $txtStatus.Text            = 'Not connected'
        $txtFooter.Text            = 'Not connected — click Connect to sign in'
        $script:connected          = $false
        $btnRefresh.Visibility     = [System.Windows.Visibility]::Collapsed
    }

    # Fetch categories and filters — shared by connect and the Refresh button
    function Invoke-RefreshTenantData {
        try {
            $catResp = Get-TenantGraphCollection -Url 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileAppCategories?$select=id,displayName'
            $script:availableCategories = @($catResp | ForEach-Object { $_.displayName } | Sort-Object)
            Write-Log "Loaded $($script:availableCategories.Count) app categories" 'OK'
        } catch {
            Write-Log "Could not load categories: $_" 'Warn'
        }

        try {
            # Assignment filters are beta-only — v1.0 returns 'segment not found'.
            # Fetch platform and assignmentFilterManagementType so we can restrict to
            # Windows 10 and later / Managed Devices only (matching what Intune shows
            # when assigning Win32 apps to device groups).
            $filterUrl  = 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' +
                          '?$select=id,displayName,platform,assignmentFilterManagementType'
            $filterResp = Get-TenantGraphCollection -Url $filterUrl

            $script:availableFilters = @(
                $filterResp |
                Where-Object {
                    $_.platform                       -eq 'windows10AndLater' -and
                    $_.assignmentFilterManagementType -eq 'devices'
                } |
                ForEach-Object { @{ id = $_.id; displayName = $_.displayName } }
            )

            $total    = @($filterResp).Count
            $count    = $script:availableFilters.Count
            $skipped  = $total - $count
            $skipNote = if ($skipped -gt 0) { " ($skipped non-Windows/managed-apps filters hidden)" } else { '' }
            Write-Log "Loaded $count Managed Device / Windows 10+ filter$(if ($count -ne 1) {'s'})$skipNote" 'OK'
        } catch {
            if ($_ -match '403|Forbidden') {
                Write-Log "Assignment filters not loaded — missing DeviceManagementConfiguration.Read.All permission." 'Warn'
            } else {
                Write-Log "Could not load filters: $_" 'Warn'
            }
        }
    }

    #endregion

    #region Connect / Disconnect

    $btnConnect.Add_Click({
        $txtFooter.Text = 'Connecting...'
        try {
            Import-Module IntuneWin32App -Force -ErrorAction Stop
            Import-Module MSAL.PS        -Force -ErrorAction Stop

            # Determine effective ClientID
            $effectiveClientID = if ($Config.AuthMethod -eq 'MicrosoftGraphCLI' -or -not $Config.ClientID) {
                '14d82eec-204b-4c2f-b7e8-296a70dab67e'   # Microsoft Graph Command Line Tools
            } else {
                $Config.ClientID
            }

            # Use the module's own Connect-MSIntuneGraph so that $Global:AuthenticationHeader
            # is set in exactly the format Add-IntuneWin32App expects (ExpiresOn as UTCDateTime,
            # Authorization via CreateAuthorizationHeader()).  Bypassing it via Get-MsalToken
            # produces a subtly wrong ExpiresOn type that makes the module's token-lifetime
            # check always treat the token as expired, silently aborting the upload.
            Connect-MSIntuneGraph -TenantID $Config.TenantID -ClientID $effectiveClientID `
                                  -Interactive -ErrorAction Stop | Out-Null

            # Store for Invoke-TenantGraphRequest fallback methods
            $global:IntuneUploaderClientID  = $effectiveClientID
            $global:IntuneUploaderTenantID  = $Config.TenantID
            $global:IntuneUploaderLoginHint = ''

            # Signed-in user display name
            $userLabel = ''
            try {
                $me = Invoke-TenantGraphRequest -Url 'https://graph.microsoft.com/v1.0/me?$select=displayName,userPrincipalName'
                $userLabel = "$($me.displayName) ($($me.userPrincipalName))"
                $global:IntuneUploaderLoginHint = $me.userPrincipalName
            } catch {}

            Set-Connected -UserDisplay $userLabel
            Write-Log "Connected to Intune tenant: $($Config.TenantID)" 'OK'

            Invoke-RefreshTenantData
        }
        catch {
            Set-Disconnected
            Write-Log "Connection failed: $_" 'Fail'
            [System.Windows.MessageBox]::Show(
                "Could not connect to Intune:`n`n$_`n`nCheck your Tenant ID and permissions.`n`nRun Setup-IntuneUploader.ps1 if you haven't already.",
                'Connection Failed', 'OK', 'Error')
        }
    })

    $btnRefresh.Add_Click({
        $txtFooter.Text = 'Refreshing...'
        Write-Log 'Refreshing categories and filters...' 'Info'
        Invoke-RefreshTenantData
        $txtFooter.Text = 'Connected to Intune'
    })

    $btnSignOut.Add_Click({
        $Global:AuthenticationHeader    = $null
        $global:IntuneUploaderClientID  = $null
        $global:IntuneUploaderTenantID  = $null
        $global:IntuneUploaderLoginHint = $null
        try { Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue } catch {}
        $script:availableCategories = @()
        $script:availableFilters    = @()
        Set-Disconnected
        Write-Log 'Signed out.' 'Info'
    })

    #endregion

    #region Upload Single App

    $btnUploadSingle.Add_Click({
        if (-not $script:connected) {
            [System.Windows.MessageBox]::Show('Please connect to Intune first.', 'Not Connected', 'OK', 'Warning')
            return
        }

        $appConfig = Show-AppUploadForm `
            -TemplateFolder      $TemplateFolder `
            -DefaultOutput       $Config.DefaultOutputPath `
            -DefaultTemplate     $Config.DefaultTemplate `
            -Config              $Config `
            -AvailableCategories $script:availableCategories `
            -AvailableFilters    $script:availableFilters

        if (-not $appConfig) {
            Write-Log 'Upload cancelled by user.' 'Info'
            return
        }

        # Log everything the user selected so they can see what's about to happen
        $asgDesc = switch ($appConfig.Assignment.Type) {
            'AllDevices' { 'All Devices' }
            'AllUsers'   { 'All Users'   }
            'Group'      { "Group: $($appConfig.Assignment.GroupName)" }
            default      { 'None (manual)' }
        }
        $catDesc = if ($appConfig.Categories -and $appConfig.Categories.Count) {
            $appConfig.Categories -join ', '
        } else { 'None' }
        $filterDesc = if ($appConfig.Assignment.FilterID) { $appConfig.Assignment.FilterIntent } else { 'None' }

        Write-Log "─── Upload: $($appConfig.DisplayName) $($appConfig.Version) ───" 'Info'
        Write-Log "  Source:     $($appConfig.SourceFolder)" 'Info'
        Write-Log "  Detection:  $($appConfig.Detection.Type)" 'Info'
        Write-Log "  Assignment: $asgDesc" 'Info'
        Write-Log "  Filter:     $filterDesc" 'Info'
        Write-Log "  Categories: $catDesc" 'Info'
        Write-Log "  Template:   $($appConfig.Template)" 'Info'

        $txtFooter.Text = "Packaging: $($appConfig.DisplayName)..."
        Write-Log "Packaging .intunewin..." 'Info'

        try {
            $result = Invoke-ProcessApp -AppConfig $appConfig -Config $Config -TemplateFolder $TemplateFolder

            if ($result.Success) {
                Write-Log "Uploading to Intune... done." 'OK'
                Write-Log "$($appConfig.DisplayName) — complete  (ID: $($result.App.id))" 'OK'
                Write-Log "  Documentation: $($result.DocPath)" 'Info'
                $txtFooter.Text = "Done: $($appConfig.DisplayName)"
                [System.Windows.MessageBox]::Show(
                    "Successfully uploaded:`n$($appConfig.DisplayName) $($appConfig.Version)`n`nApp ID: $($result.App.id)`nDoc: $($result.DocPath)",
                    'Upload Complete', 'OK', 'Information')
            }
            else {
                Write-Log "FAILED: $($result.Error)" 'Fail'
                $txtFooter.Text = "Failed: $($appConfig.DisplayName)"
                [System.Windows.MessageBox]::Show(
                    "Upload failed for: $($appConfig.DisplayName)`n`n$($result.Error)",
                    'Upload Failed', 'OK', 'Error')
            }
        }
        catch {
            Write-Log "Unexpected error: $_" 'Fail'
            $txtFooter.Text = 'Error'
        }
    })

    #endregion

    #region Bulk Upload

    $btnBulkUpload.Add_Click({
        if (-not $script:connected) {
            [System.Windows.MessageBox]::Show('Please connect to Intune first.', 'Not Connected', 'OK', 'Warning')
            return
        }

        Write-Log 'Opening Bulk Upload Manager...' 'Info'
        $txtFooter.Text = 'Bulk Upload Manager open'

        # Capture UI controls so the logger closure can write to them after
        # Show-BulkManager takes over the message loop.
        $capturedLog      = $txtLog
        $capturedScroller = $logScroller
        $bulkLogger = {
            param([string]$Text, [string]$Level)
            $prefix = switch ($Level) {
                'OK'   { '[OK]   ' }
                'Warn' { '[WARN] ' }
                'Fail' { '[FAIL] ' }
                default{ '[INFO] ' }
            }
            $line = "$(Get-Date -Format 'HH:mm:ss')  $prefix $Text`n"
            $capturedLog.AppendText($line)
            $capturedScroller.ScrollToEnd()
        }.GetNewClosure()

        Show-BulkManager `
            -Config              $Config `
            -TemplateFolder      $TemplateFolder `
            -ToolRoot            $ToolRoot `
            -AvailableCategories $script:availableCategories `
            -AvailableFilters    $script:availableFilters `
            -Logger              $bulkLogger

        $txtFooter.Text = 'Ready'
        Write-Log 'Bulk Upload Manager closed.' 'Info'
    })

    #endregion

    #region Templates

    $btnTemplates.Add_Click({
        Write-Log 'Opening Template Editor...' 'Info'
        Show-TemplateEditor `
            -TemplateFolder   $TemplateFolder `
            -AvailableFilters $script:availableFilters
        Write-Log 'Template Editor closed.' 'Info'
    })

    #endregion

    #region Settings

    $btnSettings.Add_Click({
        $configPath  = Join-Path $ToolRoot 'Config\config.json'
        $authDisplay = if ($Config.AuthMethod -eq 'MicrosoftGraphCLI' -or -not $Config.ClientID) {
            'Microsoft Graph Command Line Tools (no app registration)'
        } else {
            "Custom App Registration ($($Config.ClientID))"
        }
        $msg = "Current configuration:`n`n" +
               "Auth method:       $authDisplay`n" +
               "Tenant ID:         $($Config.TenantID)`n" +
               "Output path:       $($Config.DefaultOutputPath)`n" +
               "Docs path:         $($Config.DocumentationPath)`n" +
               "Default template:  $($Config.DefaultTemplate)`n" +
               "IntuneWinAppUtil:  $($Config.IntuneWinAppUtilPath)`n`n" +
               "Config file: $configPath`n`n" +
               "To change settings, run Setup-IntuneUploader.ps1 or edit config.json directly."

        [System.Windows.MessageBox]::Show($msg, 'Settings', 'OK', 'Information')
    })

    #endregion

    $btnClearLog.Add_Click({ $txtLog.Clear() })

    # Initial log entry
    Write-Log 'Intune Win32 App Uploader started. Click Connect to sign in.' 'Info'
    Write-Log "Tool root: $ToolRoot" 'Info'

    $window.ShowDialog() | Out-Null
}
