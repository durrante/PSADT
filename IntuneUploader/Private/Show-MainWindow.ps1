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
    Width="820" Height="620"
    WindowStartupLocation="CenterScreen"
    MinWidth="600" MinHeight="460">

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
    <Border Background="#0078D4" Grid.Row="0">
      <Grid Margin="20,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Intune Win32 App Uploader" FontSize="20" FontWeight="Light" Foreground="White"/>
          <TextBlock Text="Microsoft Intune application packaging and deployment" FontSize="11"
                     Foreground="#B3D9F7" Margin="0,1,0,0"/>
        </StackPanel>
        <Button x:Name="BtnSignOut" Content="Sign Out" HorizontalAlignment="Right"
                VerticalAlignment="Center" Padding="10,4" Background="#005A9E"
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
        <Button x:Name="BtnConnect" Content="Connect to Intune" HorizontalAlignment="Right"
                Padding="10,4" FontSize="12" Background="#0078D4" Foreground="White" BorderThickness="0"
                Cursor="Hand"/>
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
              Background="#0078D4" Foreground="White" Style="{StaticResource TileBtn}">
        <StackPanel>
          <TextBlock Text="&#xE898;" FontFamily="Segoe MDL2 Assets" FontSize="22" HorizontalAlignment="Center" Margin="0,0,0,4"/>
          <TextBlock Text="Upload App" FontSize="12"/>
        </StackPanel>
      </Button>

      <Button x:Name="BtnBulkUpload" Grid.Column="2" Height="72"
              Background="#107C10" Foreground="White" Style="{StaticResource TileBtn}">
        <StackPanel>
          <TextBlock Text="&#xE838;" FontFamily="Segoe MDL2 Assets" FontSize="22" HorizontalAlignment="Center" Margin="0,0,0,4"/>
          <TextBlock Text="Bulk Upload" FontSize="12"/>
        </StackPanel>
      </Button>

      <Button x:Name="BtnTemplates" Grid.Column="4" Height="72"
              Background="#5C2D91" Foreground="White" Style="{StaticResource TileBtn}">
        <StackPanel>
          <TextBlock Text="&#xE70B;" FontFamily="Segoe MDL2 Assets" FontSize="22" HorizontalAlignment="Center" Margin="0,0,0,4"/>
          <TextBlock Text="Templates" FontSize="12"/>
        </StackPanel>
      </Button>

      <Button x:Name="BtnSettings" Grid.Column="6" Height="72"
              Background="#767676" Foreground="White" Style="{StaticResource TileBtn}">
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
        $connDot.Fill     = [System.Windows.Media.Brushes]::Green
        $txtStatus.Text   = if ($UserDisplay) { "Connected as $UserDisplay" } else { 'Connected' }
        $txtFooter.Text   = 'Connected to Intune'
        $script:connected = $true
    }

    function Set-Disconnected {
        $connDot.Fill     = [System.Windows.Media.Brushes]::Red
        $txtStatus.Text   = 'Not connected'
        $txtFooter.Text   = 'Not connected — click Connect to sign in'
        $script:connected = $false
    }

    #endregion

    #region Connect / Disconnect

    $btnConnect.Add_Click({
        $txtFooter.Text = 'Connecting...'
        try {
            Import-Module IntuneWin32App -Force -ErrorAction Stop
            Connect-MSIntuneGraph -TenantID $Config.TenantID -ClientID $Config.ClientID -Interactive -ErrorAction Stop

            # Signed-in user
            $userLabel = ''
            try {
                $me = Invoke-TenantGraphRequest -Url 'https://graph.microsoft.com/v1.0/me?$select=displayName,userPrincipalName' `
                                               -ClientID $Config.ClientID -TenantID $Config.TenantID
                $userLabel = "$($me.displayName) ($($me.userPrincipalName))"
            } catch {}

            Set-Connected -UserDisplay $userLabel
            Write-Log "Connected to Intune tenant: $($Config.TenantID)" 'OK'

            # Fetch categories
            try {
                $catResp = Get-TenantGraphCollection `
                    -Url 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileAppCategories?$select=id,displayName' `
                    -ClientID $Config.ClientID -TenantID $Config.TenantID
                $script:availableCategories = @($catResp | ForEach-Object { $_.displayName } | Sort-Object)
                Write-Log "Loaded $($script:availableCategories.Count) app categories" 'OK'
            } catch {
                Write-Log "Could not load categories: $_" 'Warn'
            }

            # Fetch assignment filters
            try {
                $filterResp = Get-TenantGraphCollection `
                    -Url 'https://graph.microsoft.com/v1.0/deviceManagement/assignmentFilters?$select=id,displayName' `
                    -ClientID $Config.ClientID -TenantID $Config.TenantID
                $script:availableFilters = @($filterResp | ForEach-Object { @{ id = $_.id; displayName = $_.displayName } })
                Write-Log "Loaded $($script:availableFilters.Count) assignment filters" 'OK'
            } catch {
                Write-Log "Could not load filters: $_" 'Warn'
            }
        }
        catch {
            Set-Disconnected
            Write-Log "Connection failed: $_" 'Fail'
            [System.Windows.MessageBox]::Show(
                "Could not connect to Intune:`n`n$_`n`nCheck your Tenant ID, Client ID, and app registration settings.",
                'Connection Failed', 'OK', 'Error')
        }
    })

    $btnSignOut.Add_Click({
        try { Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue } catch {}
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

        Write-Log "Starting: $($appConfig.DisplayName) $($appConfig.Version)" 'Info'
        $txtFooter.Text = "Processing: $($appConfig.DisplayName)..."

        try {
            $result = Invoke-ProcessApp -AppConfig $appConfig -Config $Config -TemplateFolder $TemplateFolder

            if ($result.Success) {
                Write-Log "$($appConfig.DisplayName) — uploaded successfully (ID: $($result.App.id))" 'OK'
                Write-Log "  Documentation: $($result.DocPath)" 'Info'
                $txtFooter.Text = "Done: $($appConfig.DisplayName)"
                [System.Windows.MessageBox]::Show(
                    "Successfully uploaded:`n$($appConfig.DisplayName) $($appConfig.Version)`n`nApp ID: $($result.App.id)`nDoc: $($result.DocPath)",
                    'Upload Complete', 'OK', 'Information')
            }
            else {
                Write-Log "$($appConfig.DisplayName) — FAILED: $($result.Error)" 'Fail'
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

        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = 'Select bulk upload JSON file'
        $dlg.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'

        if ($dlg.ShowDialog() -ne 'OK') { return }

        try {
            $apps = Get-Content $dlg.FileName -Raw | ConvertFrom-Json
        }
        catch {
            [System.Windows.MessageBox]::Show("Could not read JSON file:`n$_", 'Error', 'OK', 'Error')
            return
        }

        if ($apps -isnot [array]) { $apps = @($apps) }

        $confirmed = [System.Windows.MessageBox]::Show(
            "Found $($apps.Count) application(s) in the bulk file.`n`nProceed with packaging and uploading all?",
            'Bulk Upload', 'YesNo', 'Question')

        if ($confirmed -ne 'Yes') { return }

        Write-Log "=== Bulk upload started: $($apps.Count) apps ===" 'Info'
        $ok = 0; $fail = 0; $idx = 0

        foreach ($appJson in $apps) {
            $idx++
            $appConfig = ConvertFrom-AppJson -AppJson $appJson

            if (-not $appConfig) {
                Write-Log "[$idx/$($apps.Count)] SKIP — missing required fields" 'Warn'
                $fail++
                continue
            }

            $txtFooter.Text = "[$idx/$($apps.Count)] $($appConfig.DisplayName)..."
            Write-Log "[$idx/$($apps.Count)] $($appConfig.DisplayName) $($appConfig.Version)" 'Info'

            $result = Invoke-ProcessApp -AppConfig $appConfig -Config $Config -TemplateFolder $TemplateFolder

            if ($result.Success) {
                Write-Log "  OK — $($appConfig.DisplayName) (ID: $($result.App.id))" 'OK'
                $ok++
            }
            else {
                Write-Log "  FAILED — $($result.Error)" 'Fail'
                $fail++
            }
        }

        $summary = "Bulk upload complete: $ok succeeded, $fail failed"
        Write-Log "=== $summary ===" 'Info'
        $txtFooter.Text = $summary
        [System.Windows.MessageBox]::Show($summary, 'Bulk Upload Complete', 'OK', 'Information')
    })

    #endregion

    #region Templates

    $btnTemplates.Add_Click({
        $tplFiles = Get-ChildItem -Path $TemplateFolder -Filter '*.json' -ErrorAction SilentlyContinue
        if (-not $tplFiles) {
            [System.Windows.MessageBox]::Show("No templates found in:`n$TemplateFolder", 'Templates', 'OK', 'Information')
            return
        }

        $list = $tplFiles | ForEach-Object {
            try {
                $d = Get-Content $_.FullName -Raw | ConvertFrom-Json
                "$($_.BaseName.PadRight(25))  $($d.Description ?? '(no description)')"
            }
            catch { "$($_.BaseName.PadRight(25))  (invalid JSON)" }
        }

        $msg = "Available templates in:`n$TemplateFolder`n`n" + ($list -join "`n") + `
               "`n`nTo create a new template: copy an existing .json file and edit it.`n" + `
               "To use a template: select it in the Upload form's Packaging section."

        [System.Windows.MessageBox]::Show($msg, 'Templates', 'OK', 'Information')
    })

    #endregion

    #region Settings

    $btnSettings.Add_Click({
        $configPath = Join-Path $ToolRoot 'Config\config.json'
        $msg = "Current configuration:`n`n" +
               "Tenant ID:         $($Config.TenantID)`n" +
               "Client ID:         $($Config.ClientID)`n" +
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
