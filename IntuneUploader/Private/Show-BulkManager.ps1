<#
.SYNOPSIS
    WPF Bulk Upload Manager — inline spreadsheet-style queue.

.DESCRIPTION
    Each row is a Win32 app config.  Users edit cells directly:
      - Type/paste a source folder path → PSADT metadata is auto-scanned
      - Pick a template from the dropdown → defaults are applied
      - Edit Name / Version / Publisher inline
      - "Browse Source..." opens a folder picker for the selected row
      - "Full Setup..." opens Show-AppUploadForm for detection / assignment
      - Double-click a row for the same Full Setup experience
      - Import / Export JSON, Upload Selected / All
#>

function Show-BulkManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [string]$TemplateFolder,
        [string]$ToolRoot,

        [string[]]$AvailableCategories = @(),
        [object[]]$AvailableFilters    = @()
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms | Out-Null

    # ── Template list ─────────────────────────────────────────────────────────
    $script:templateNames = @('PSADT-Default','Generic-Default')
    if ($TemplateFolder -and (Test-Path $TemplateFolder)) {
        $loaded = @(
            Get-ChildItem -Path $TemplateFolder -Filter '*.json' |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
            Sort-Object
        )
        if ($loaded.Count) { $script:templateNames = $loaded }
    }

    # ── XAML ──────────────────────────────────────────────────────────────────
    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Bulk Upload Manager"
    Width="1200" Height="700"
    WindowStartupLocation="CenterScreen"
    MinWidth="820" MinHeight="480">

  <Window.Resources>

    <Style x:Key="ToolBtn" TargetType="Button">
      <Setter Property="Padding"         Value="10,4"/>
      <Setter Property="Margin"          Value="0,0,5,0"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="BorderBrush"     Value="#CCC"/>
      <Setter Property="Background"      Value="White"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="3" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.82"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.65"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PrimaryBtn" TargetType="Button" BasedOn="{StaticResource ToolBtn}">
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>

    <!-- Hint text style for empty cells -->
    <Style x:Key="HintCell" TargetType="TextBlock">
      <Setter Property="Foreground"   Value="#BBB"/>
      <Setter Property="FontStyle"    Value="Italic"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Padding"      Value="4,0"/>
    </Style>

  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="56"/>   <!-- Header gradient -->
      <RowDefinition Height="Auto"/> <!-- Toolbar -->
      <RowDefinition Height="*"/>    <!-- DataGrid -->
      <RowDefinition Height="Auto"/> <!-- Status bar -->
    </Grid.RowDefinitions>

    <!-- ═══ HEADER ═══ -->
    <Border Grid.Row="0">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
          <GradientStop Color="#0693E3" Offset="0"/>
          <GradientStop Color="#9B51E0" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Grid Margin="18,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Bulk Upload Manager" FontSize="20" FontWeight="Light" Foreground="White"/>
          <TextBlock Text="Add rows, edit inline — Source Folder auto-scans PSADT metadata. Full Setup for detection/assignment."
                     FontSize="11" Foreground="#D4C5F9" Margin="0,1,0,0"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ═══ TOOLBAR ═══ -->
    <Border Grid.Row="1" Background="#F8F8F8" BorderBrush="#E0E0E0" BorderThickness="0,0,0,1" Padding="10,7">
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">

        <Button x:Name="BtnAddRow"   Content="+ Add Row"        Style="{StaticResource PrimaryBtn}" Background="#4A2B8F"/>
        <Button x:Name="BtnBrowse"   Content="Browse Source..."  Style="{StaticResource ToolBtn}"/>
        <Button x:Name="BtnFullSetup" Content="Full Setup..."    Style="{StaticResource ToolBtn}"/>

        <Separator Width="1" Background="#DDD" Margin="4,2,10,2"/>

        <Button x:Name="BtnRemove"   Content="Remove Selected"  Style="{StaticResource ToolBtn}"/>
        <Button x:Name="BtnClear"    Content="Clear All"        Style="{StaticResource ToolBtn}"/>

        <Separator Width="1" Background="#DDD" Margin="4,2,10,2"/>

        <Button x:Name="BtnImport"   Content="Import JSON"      Style="{StaticResource ToolBtn}"/>
        <Button x:Name="BtnExport"   Content="Export JSON"      Style="{StaticResource ToolBtn}" IsEnabled="False"/>

        <Separator Width="1" Background="#DDD" Margin="4,2,10,2"/>

        <Button x:Name="BtnUploadSel" Content="Upload Selected"
                Style="{StaticResource PrimaryBtn}" Background="#5BA3E8" IsEnabled="False"/>
        <Button x:Name="BtnUploadAll" Content="Upload All"
                Style="{StaticResource PrimaryBtn}" IsEnabled="False">
          <Button.Background>
            <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
              <GradientStop Color="#0693E3" Offset="0"/>
              <GradientStop Color="#9B51E0" Offset="1"/>
            </LinearGradientBrush>
          </Button.Background>
        </Button>

      </StackPanel>
    </Border>

    <!-- ═══ DATA GRID ═══ -->
    <DataGrid x:Name="BulkGrid" Grid.Row="2"
              AutoGenerateColumns="False"
              CanUserAddRows="False"
              CanUserDeleteRows="False"
              SelectionMode="Extended"
              SelectionUnit="FullRow"
              IsReadOnly="False"
              GridLinesVisibility="Horizontal"
              HeadersVisibility="Column"
              AlternatingRowBackground="#FAFAFA"
              RowBackground="White"
              BorderThickness="0"
              ColumnHeaderHeight="30"
              RowHeight="28">

      <DataGrid.ColumnHeaderStyle>
        <Style TargetType="DataGridColumnHeader">
          <Setter Property="Background"      Value="#F0EBF9"/>
          <Setter Property="Foreground"      Value="#4A2B8F"/>
          <Setter Property="FontWeight"      Value="SemiBold"/>
          <Setter Property="FontSize"        Value="12"/>
          <Setter Property="Padding"         Value="8,0"/>
          <Setter Property="BorderBrush"     Value="#DDD"/>
          <Setter Property="BorderThickness" Value="0,0,1,1"/>
        </Style>
      </DataGrid.ColumnHeaderStyle>

      <DataGrid.CellStyle>
        <Style TargetType="DataGridCell">
          <Setter Property="Padding"         Value="0"/>
          <Setter Property="BorderThickness" Value="0"/>
          <Style.Triggers>
            <Trigger Property="IsSelected" Value="True">
              <Setter Property="Background" Value="#E8DEFF"/>
              <Setter Property="Foreground" Value="#2D1B69"/>
            </Trigger>
          </Style.Triggers>
        </Style>
      </DataGrid.CellStyle>

      <DataGrid.Columns>

        <!-- 0 — Source Folder: display=leaf, edit=full path -->
        <DataGridTemplateColumn Header="Source Folder" Width="175" MinWidth="100" SortMemberPath="SourceLeaf">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock VerticalAlignment="Center" Padding="6,0"
                         TextTrimming="CharacterEllipsis"
                         ToolTip="{Binding [SourceFolder]}">
                <TextBlock.Style>
                  <Style TargetType="TextBlock">
                    <Setter Property="Text" Value="{Binding [SourceLeaf]}"/>
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding [SourceLeaf]}" Value="">
                        <Setter Property="Text"       Value="Click to set path…"/>
                        <Setter Property="Foreground"  Value="#BBB"/>
                        <Setter Property="FontStyle"   Value="Italic"/>
                      </DataTrigger>
                    </Style.Triggers>
                  </Style>
                </TextBlock.Style>
              </TextBlock>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
          <DataGridTemplateColumn.CellEditingTemplate>
            <DataTemplate>
              <TextBox x:Name="TbSourceFolder"
                       Text="{Binding [SourceFolder], UpdateSourceTrigger=LostFocus}"
                       VerticalAlignment="Center" Padding="5,0"
                       BorderThickness="0" Background="Transparent"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellEditingTemplate>
        </DataGridTemplateColumn>

        <!-- 1 — Display Name -->
        <DataGridTemplateColumn Header="Display Name" Width="165" MinWidth="80" SortMemberPath="DisplayName">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock VerticalAlignment="Center" Padding="6,0" TextTrimming="CharacterEllipsis">
                <TextBlock.Style>
                  <Style TargetType="TextBlock">
                    <Setter Property="Text" Value="{Binding [DisplayName]}"/>
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding [DisplayName]}" Value="">
                        <Setter Property="Text"      Value="auto-filled…"/>
                        <Setter Property="Foreground" Value="#BBB"/>
                        <Setter Property="FontStyle"  Value="Italic"/>
                      </DataTrigger>
                    </Style.Triggers>
                  </Style>
                </TextBlock.Style>
              </TextBlock>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
          <DataGridTemplateColumn.CellEditingTemplate>
            <DataTemplate>
              <TextBox Text="{Binding [DisplayName], UpdateSourceTrigger=LostFocus}"
                       VerticalAlignment="Center" Padding="5,0"
                       BorderThickness="0" Background="Transparent"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellEditingTemplate>
        </DataGridTemplateColumn>

        <!-- 2 — Version -->
        <DataGridTemplateColumn Header="Version" Width="80" SortMemberPath="Version">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock Text="{Binding [Version]}" VerticalAlignment="Center" Padding="6,0"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
          <DataGridTemplateColumn.CellEditingTemplate>
            <DataTemplate>
              <TextBox Text="{Binding [Version], UpdateSourceTrigger=LostFocus}"
                       VerticalAlignment="Center" Padding="5,0"
                       BorderThickness="0" Background="Transparent"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellEditingTemplate>
        </DataGridTemplateColumn>

        <!-- 3 — Publisher -->
        <DataGridTemplateColumn Header="Publisher" Width="115" SortMemberPath="Publisher">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock Text="{Binding [Publisher]}" VerticalAlignment="Center" Padding="6,0"
                         TextTrimming="CharacterEllipsis"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
          <DataGridTemplateColumn.CellEditingTemplate>
            <DataTemplate>
              <TextBox Text="{Binding [Publisher], UpdateSourceTrigger=LostFocus}"
                       VerticalAlignment="Center" Padding="5,0"
                       BorderThickness="0" Background="Transparent"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellEditingTemplate>
        </DataGridTemplateColumn>

        <!-- 4 — Template (ComboBox) -->
        <DataGridTemplateColumn Header="Template" Width="130" MinWidth="80" SortMemberPath="Template">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock Text="{Binding [Template]}" VerticalAlignment="Center" Padding="6,0"
                         TextTrimming="CharacterEllipsis"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
          <DataGridTemplateColumn.CellEditingTemplate>
            <DataTemplate>
              <ComboBox x:Name="CmbTemplate"
                        SelectedItem="{Binding [Template], Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                        VerticalAlignment="Center" BorderThickness="0" Padding="4,0"
                        Background="Transparent"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellEditingTemplate>
        </DataGridTemplateColumn>

        <!-- 5 — Detection (read-only summary) -->
        <DataGridTemplateColumn Header="Detection" Width="105" IsReadOnly="True" SortMemberPath="Detection">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock VerticalAlignment="Center" Padding="6,0" TextTrimming="CharacterEllipsis">
                <TextBlock.Style>
                  <Style TargetType="TextBlock">
                    <Setter Property="Text"     Value="{Binding [Detection]}"/>
                    <Setter Property="Foreground" Value="#444"/>
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding [Detection]}" Value="—">
                        <Setter Property="Foreground" Value="#F59E0B"/>
                      </DataTrigger>
                      <DataTrigger Binding="{Binding [Detection]}" Value="">
                        <Setter Property="Foreground" Value="#F59E0B"/>
                        <Setter Property="Text"       Value="Not set"/>
                        <Setter Property="FontStyle"  Value="Italic"/>
                      </DataTrigger>
                    </Style.Triggers>
                  </Style>
                </TextBlock.Style>
              </TextBlock>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
        </DataGridTemplateColumn>

        <!-- 6 — Assignment (read-only summary) -->
        <DataGridTemplateColumn Header="Assignment" Width="*" MinWidth="120" IsReadOnly="True" SortMemberPath="Assignment">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock Text="{Binding [Assignment]}" VerticalAlignment="Center" Padding="6,0"
                         TextTrimming="CharacterEllipsis" Foreground="#444"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
        </DataGridTemplateColumn>

        <!-- 7 — Status (read-only, colour-coded) -->
        <DataGridTemplateColumn Header="Status" Width="85" IsReadOnly="True" SortMemberPath="Status">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock Text="{Binding [Status]}" FontWeight="SemiBold"
                         VerticalAlignment="Center" Padding="6,0">
                <TextBlock.Style>
                  <Style TargetType="TextBlock">
                    <Setter Property="Foreground" Value="#888"/>
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding [Status]}" Value="Done">
                        <Setter Property="Foreground" Value="#2E7D32"/>
                      </DataTrigger>
                      <DataTrigger Binding="{Binding [Status]}" Value="Failed">
                        <Setter Property="Foreground" Value="#C62828"/>
                      </DataTrigger>
                      <DataTrigger Binding="{Binding [Status]}" Value="Uploading...">
                        <Setter Property="Foreground" Value="#1565C0"/>
                      </DataTrigger>
                    </Style.Triggers>
                  </Style>
                </TextBlock.Style>
              </TextBlock>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
        </DataGridTemplateColumn>

      </DataGrid.Columns>
    </DataGrid>

    <!-- ═══ STATUS BAR ═══ -->
    <Border Grid.Row="3" Background="#F5F5F5" BorderBrush="#DDD" BorderThickness="0,1,0,0" Padding="14,5">
      <Grid>
        <TextBlock x:Name="TxtStatus" FontSize="11" Foreground="#555" VerticalAlignment="Center"
                   Text="0 apps in queue  •  Click + Add Row to begin  •  Double-click a row for full configuration"/>
        <TextBlock x:Name="TxtUploadResult" HorizontalAlignment="Right"
                   FontSize="11" FontWeight="SemiBold" Foreground="#4A2B8F" VerticalAlignment="Center"/>
      </Grid>
    </Border>

  </Grid>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    function Find { param($n) $window.FindName($n) }

    $bulkGrid        = Find 'BulkGrid'
    $btnAddRow       = Find 'BtnAddRow'
    $btnBrowse       = Find 'BtnBrowse'
    $btnFullSetup    = Find 'BtnFullSetup'
    $btnRemove       = Find 'BtnRemove'
    $btnClear        = Find 'BtnClear'
    $btnImport       = Find 'BtnImport'
    $btnExport       = Find 'BtnExport'
    $btnUploadSel    = Find 'BtnUploadSel'
    $btnUploadAll    = Find 'BtnUploadAll'
    $txtStatus       = Find 'TxtStatus'
    $txtUploadResult = Find 'TxtUploadResult'

    # ── Data structures ───────────────────────────────────────────────────────
    # $script:bmRows  — List of hashtables; full AppConfig + _id + _status
    # $script:bmTable — DataTable; parallel display data; never rebuilt (updated in-place)
    $script:bmRows  = [System.Collections.Generic.List[hashtable]]::new()
    $script:bmTable = New-Object System.Data.DataTable

    foreach ($col in @('_Id','SourceFolder','SourceLeaf','DisplayName','Version',
                        'Publisher','Template','Detection','Assignment','Status')) {
        $script:bmTable.Columns.Add($col, [string]) | Out-Null
    }
    $bulkGrid.ItemsSource = $script:bmTable.DefaultView

    # ─────────────────────────────────────────────────────────────────────────
    #region Helper functions
    # ─────────────────────────────────────────────────────────────────────────

    function Get-DetectionSummary {
        param($Det)
        if (-not $Det) { return '—' }
        $d = if ($Det -is [hashtable]) { $Det } else {
            $h = @{}; $Det.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }; $h
        }
        switch ($d.Type) {
            'Script'   { 'Script' }
            'Registry' { "Reg: $(Split-Path ($d.KeyPath ?? '') -Leaf)" }
            'MSI'      { "MSI: $($d.ProductCode -replace '^\{|\}$','')" }
            'File'     { "File: $($d.FileOrFolder)" }
            default    { $d.Type ?? '—' }
        }
    }

    function Get-AssignmentSummary {
        param($Asg)
        if (-not $Asg) { return '—' }
        $a = if ($Asg -is [hashtable]) { $Asg } else {
            $h = @{}; $Asg.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }; $h
        }
        $intent = if ($a.Intent) { " / $($a.Intent)" } else { '' }
        switch ($a.Type) {
            'AllDevices' { "All Devices$intent" }
            'AllUsers'   { "All Users$intent" }
            'Group'      { "Group: $($a.GroupName)$intent" }
            'None'       { 'None' }
            default      { $a.Type ?? '—' }
        }
    }

    function Find-RowById {
        param([string]$Id)
        for ($i = 0; $i -lt $script:bmRows.Count; $i++) {
            if ($script:bmRows[$i]._id -eq $Id) { return $i }
        }
        return -1
    }

    function Find-DataRow {
        param([string]$Id)
        foreach ($dr in $script:bmTable.Rows) {
            if ($dr['_Id'] -eq $Id) { return $dr }
        }
        return $null
    }

    function Refresh-StatusBar {
        $total  = $script:bmRows.Count
        $done   = @($script:bmRows | Where-Object { $_._status -eq 'Done'   }).Count
        $failed = @($script:bmRows | Where-Object { $_._status -eq 'Failed' }).Count
        $plural = if ($total -ne 1) { 's' } else { '' }

        $parts = @("$total app$plural in queue")
        if ($done)   { $parts += "$done done" }
        if ($failed) { $parts += "$failed failed" }
        $parts += 'Double-click a row for full configuration'
        $txtStatus.Text = $parts -join '  •  '

        $hasRows = $total -gt 0
        $btnExport.IsEnabled   = $hasRows
        $btnUploadAll.IsEnabled = $hasRows
        $btnUploadSel.IsEnabled = $hasRows
    }

    function Update-RowStatus {
        param([string]$Id, [string]$Status)
        $idx = Find-RowById -Id $Id
        if ($idx -ge 0) { $script:bmRows[$idx]._status = $Status }
        $dr = Find-DataRow -Id $Id
        if ($dr) { $dr['Status'] = $Status }
    }

    # Called after a source folder is set — scans PSADT metadata and updates the row in-place
    function Invoke-SourceScan {
        param([string]$Id, [string]$Path)

        $idx = Find-RowById -Id $Id
        if ($idx -lt 0) { return }

        $dr = Find-DataRow -Id $Id
        $row = $script:bmRows[$idx]

        # Always update the leaf display regardless of metadata
        $leaf = if ($Path) { Split-Path $Path -Leaf } else { '' }
        if ($dr) {
            $dr['SourceFolder'] = $Path
            $dr['SourceLeaf']   = $leaf
        }
        $row.SourceFolder = $Path

        if (-not $Path -or -not (Test-Path $Path -PathType Container)) {
            Refresh-StatusBar
            return
        }

        # Try PSADT scan
        $meta = $null
        try { $meta = Get-PSADTMetadata -SourceFolder $Path } catch {}

        if ($meta) {
            $row.IsPSADT  = $true
            $row.SetupFile = $meta.SetupFile

            if (-not $row.DisplayName)          { $row.DisplayName          = $meta.AppName }
            if (-not $row.Version)              { $row.Version              = $meta.AppVersion }
            if (-not $row.Publisher)            { $row.Publisher            = $meta.AppVendor }
            if (-not $row.InstallCommandLine)   { $row.InstallCommandLine   = $meta.InstallCommandLine }
            if (-not $row.UninstallCommandLine) { $row.UninstallCommandLine = $meta.UninstallCommandLine }
            if (-not $row.Author)               { $row.Author               = $meta.AppScriptAuthor }

            # Switch to PSADT template if still on generic
            if (-not $row.Template -or $row.Template -eq 'Generic-Default') {
                $row.Template = 'PSADT-Default'
            }
        }

        if ($dr) {
            $dr['DisplayName'] = $row.DisplayName  ?? ''
            $dr['Version']     = $row.Version      ?? ''
            $dr['Publisher']   = $row.Publisher    ?? ''
            $dr['Template']    = $row.Template     ?? ''
        }

        Refresh-StatusBar
    }

    # Apply template defaults to a row's bmRows entry (does not overwrite user edits)
    function Apply-TemplateToRow {
        param([string]$Id, [string]$TemplateName)

        $idx = Find-RowById -Id $Id
        if ($idx -lt 0 -or -not $TemplateName) { return }

        $tplPath = Join-Path $TemplateFolder "$TemplateName.json"
        if (-not (Test-Path $tplPath)) { return }

        try {
            $tpl = Get-Content $tplPath -Raw | ConvertFrom-Json
            $row = $script:bmRows[$idx]

            if ($tpl.Architecture)                    { $row.Architecture = $tpl.Architecture }
            if ($tpl.MinimumSupportedWindowsRelease)  { $row.MinimumSupportedWindowsRelease = $tpl.MinimumSupportedWindowsRelease }

            # Command lines — apply only if not already user-set
            if ($tpl.InstallCommandLine   -and -not $row.InstallCommandLine)   { $row.InstallCommandLine   = $tpl.InstallCommandLine }
            if ($tpl.UninstallCommandLine -and -not $row.UninstallCommandLine) { $row.UninstallCommandLine = $tpl.UninstallCommandLine }

            # Assignment — apply if not yet configured
            if ($tpl.Assignment -and -not $row.Assignment) {
                if ($tpl.Assignment -is [PSCustomObject]) {
                    $h = @{}
                    $tpl.Assignment.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
                    $row.Assignment = $h
                } else { $row.Assignment = $tpl.Assignment }

                $dr = Find-DataRow -Id $Id
                if ($dr) {
                    $dr['Assignment'] = Get-AssignmentSummary -Asg $row.Assignment
                }
            }

            if ($tpl.InternalNote -and -not $row.InternalNote) { $row.InternalNote = $tpl.InternalNote }
        }
        catch { }
    }

    # Add a new row to both DataTable and bmRows
    function Add-BmRow {
        param([hashtable]$Config = @{})

        $id      = [guid]::NewGuid().ToString()
        $defTpl  = $Config.DefaultTemplate ?? 'PSADT-Default'

        $newRow = $Config.Clone()
        if (-not $newRow._id)     { $newRow._id     = $id }
        if (-not $newRow._status) { $newRow._status = 'Pending' }
        if (-not $newRow.Template){ $newRow.Template = $defTpl }
        $script:bmRows.Add($newRow)

        $dr = $script:bmTable.NewRow()
        $dr['_Id']        = $newRow._id
        $dr['SourceFolder'] = $newRow.SourceFolder ?? ''
        $dr['SourceLeaf']   = if ($newRow.SourceFolder) { Split-Path $newRow.SourceFolder -Leaf } else { '' }
        $dr['DisplayName']  = $newRow.DisplayName  ?? ''
        $dr['Version']      = $newRow.Version      ?? ''
        $dr['Publisher']    = $newRow.Publisher    ?? ''
        $dr['Template']     = $newRow.Template     ?? ''
        $dr['Detection']    = Get-DetectionSummary  -Det $newRow.Detection
        $dr['Assignment']   = Get-AssignmentSummary -Asg $newRow.Assignment
        $dr['Status']       = $newRow._status
        $script:bmTable.Rows.Add($dr)

        Refresh-StatusBar
        return $newRow._id
    }

    #endregion

    # ─────────────────────────────────────────────────────────────────────────
    #region Grid events
    # ─────────────────────────────────────────────────────────────────────────

    # Set ComboBox ItemsSource when Template column enters edit mode
    $bulkGrid.Add_PreparingCellForEdit({
        param($s, $e)
        if (($e.Column.Header -as [string]) -eq 'Template') {
            $cmb = $e.EditingElement
            if ($cmb -is [System.Windows.Controls.ComboBox]) {
                $cmb.ItemsSource = $script:templateNames
            }
        }
    })

    # Sync bmRows when a cell is committed
    $bulkGrid.Add_CellEditEnding({
        param($s, $e)
        if ($e.EditAction.ToString() -ne 'Commit') { return }

        $header  = $e.Column.Header -as [string]
        $rowView = $e.Row.Item
        if (-not $rowView) { return }

        $id  = $rowView['_Id'] -as [string]
        $idx = Find-RowById -Id $id
        if ($idx -lt 0) { return }

        switch ($header) {
            'Source Folder' {
                $tb = $e.EditingElement -as [System.Windows.Controls.TextBox]
                if ($tb) {
                    $newPath = $tb.Text.Trim()
                    if ($newPath -ne ($script:bmRows[$idx].SourceFolder ?? '')) {
                        Invoke-SourceScan -Id $id -Path $newPath
                    }
                }
            }
            'Display Name' {
                $tb = $e.EditingElement -as [System.Windows.Controls.TextBox]
                if ($tb) { $script:bmRows[$idx].DisplayName = $tb.Text.Trim() }
            }
            'Version' {
                $tb = $e.EditingElement -as [System.Windows.Controls.TextBox]
                if ($tb) { $script:bmRows[$idx].Version = $tb.Text.Trim() }
            }
            'Publisher' {
                $tb = $e.EditingElement -as [System.Windows.Controls.TextBox]
                if ($tb) { $script:bmRows[$idx].Publisher = $tb.Text.Trim() }
            }
            'Template' {
                $cmb = $e.EditingElement -as [System.Windows.Controls.ComboBox]
                if ($cmb -and $cmb.SelectedItem) {
                    $newTpl = $cmb.SelectedItem -as [string]
                    $script:bmRows[$idx].Template = $newTpl
                    Apply-TemplateToRow -Id $id -TemplateName $newTpl
                }
            }
        }
    })

    #endregion

    # ─────────────────────────────────────────────────────────────────────────
    #region Button handlers
    # ─────────────────────────────────────────────────────────────────────────

    # ── + Add Row ─────────────────────────────────────────────────────────────
    $btnAddRow.Add_Click({
        $defTpl = $Config.DefaultTemplate ?? 'PSADT-Default'
        Add-BmRow -Config @{ Template = $defTpl } | Out-Null

        # Force layout pass so Items reflects the new row, then select it
        $bulkGrid.UpdateLayout()
        $newIdx = $script:bmTable.Rows.Count - 1
        if ($newIdx -ge 0 -and $newIdx -lt $bulkGrid.Items.Count) {
            $bulkGrid.SelectedIndex = $newIdx
            $bulkGrid.ScrollIntoView($bulkGrid.Items[$newIdx])
            # Put the Source Folder cell into edit mode (user can also press F2)
            try {
                $bulkGrid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo(
                    $bulkGrid.Items[$newIdx], $bulkGrid.Columns[0])
                $bulkGrid.BeginEdit()
            } catch { }
        }
    })

    # ── Browse Source (folder picker for selected row) ────────────────────────
    $btnBrowse.Add_Click({
        $sel = $bulkGrid.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show(
                'Select a row first, then click Browse Source.',
                'Browse', 'OK', 'Information')
            return
        }

        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select the application source folder'
        $currentPath = $sel['SourceFolder'] -as [string]
        if ($currentPath -and (Test-Path $currentPath)) { $dlg.SelectedPath = $currentPath }

        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $newPath = $dlg.SelectedPath
        $id      = $sel['_Id'] -as [string]

        Invoke-SourceScan -Id $id -Path $newPath
    })

    # ── Full Setup (opens Show-AppUploadForm pre-populated) ───────────────────
    function Open-FullSetup {
        param([string]$Id)
        $idx = Find-RowById -Id $Id
        if ($idx -lt 0) { return }

        $existing = $script:bmRows[$idx]

        $updated = Show-AppUploadForm `
            -TemplateFolder      $TemplateFolder `
            -DefaultOutput       $Config.DefaultOutputPath `
            -DefaultTemplate     ($Config.DefaultTemplate ?? 'PSADT-Default') `
            -Config              $Config `
            -AvailableCategories $AvailableCategories `
            -AvailableFilters    $AvailableFilters `
            -PrePopulate         $existing `
            -SubmitLabel         'Save to Queue'

        if ($updated) {
            $updated._id     = $existing._id
            $updated._status = $existing._status
            $script:bmRows[$idx] = $updated

            $dr = Find-DataRow -Id $Id
            if ($dr) {
                $dr['SourceFolder'] = $updated.SourceFolder ?? ''
                $dr['SourceLeaf']   = if ($updated.SourceFolder) { Split-Path $updated.SourceFolder -Leaf } else { '' }
                $dr['DisplayName']  = $updated.DisplayName  ?? ''
                $dr['Version']      = $updated.Version      ?? ''
                $dr['Publisher']    = $updated.Publisher    ?? ''
                $dr['Template']     = $updated.Template     ?? ''
                $dr['Detection']    = Get-DetectionSummary  -Det $updated.Detection
                $dr['Assignment']   = Get-AssignmentSummary -Asg $updated.Assignment
            }

            Refresh-StatusBar
        }
    }

    $btnFullSetup.Add_Click({
        $sel = $bulkGrid.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show(
                'Select a row to configure.',
                'Full Setup', 'OK', 'Information')
            return
        }
        Open-FullSetup -Id ($sel['_Id'] -as [string])
    })

    # Double-click opens Full Setup
    $bulkGrid.Add_MouseDoubleClick({
        $sel = $bulkGrid.SelectedItem
        if ($sel) {
            $bulkGrid.CommitEdit()
            Open-FullSetup -Id ($sel['_Id'] -as [string])
        }
    })

    # ── Remove Selected ───────────────────────────────────────────────────────
    $btnRemove.Add_Click({
        $selIds = @($bulkGrid.SelectedItems | ForEach-Object { $_['_Id'] -as [string] })
        if (-not $selIds) {
            [System.Windows.MessageBox]::Show(
                'Select one or more rows to remove.', 'Remove', 'OK', 'Information')
            return
        }

        $script:bmRows.RemoveAll([Predicate[hashtable]]{ param($r) $selIds -contains $r._id }) | Out-Null

        $toRemove = @($script:bmTable.Rows | Where-Object { $selIds -contains $_['_Id'] })
        foreach ($dr in $toRemove) { $script:bmTable.Rows.Remove($dr) }

        Refresh-StatusBar
    })

    # ── Clear All ─────────────────────────────────────────────────────────────
    $btnClear.Add_Click({
        if ($script:bmRows.Count -eq 0) { return }
        $confirm = [System.Windows.MessageBox]::Show(
            "Remove all $($script:bmRows.Count) app(s) from the queue?",
            'Clear Queue', 'YesNo', 'Question')
        if ($confirm -ne 'Yes') { return }

        $script:bmRows.Clear()
        $script:bmTable.Rows.Clear()
        Refresh-StatusBar
    })

    # ── Import JSON ───────────────────────────────────────────────────────────
    $btnImport.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = 'Import bulk upload JSON'
        $dlg.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        try {
            $apps = Get-Content $dlg.FileName -Raw | ConvertFrom-Json
            if ($apps -isnot [array]) { $apps = @($apps) }

            $added = 0
            foreach ($appJson in $apps) {
                $cfg = ConvertFrom-AppJson -AppJson $appJson
                if ($cfg) {
                    Add-BmRow -Config $cfg | Out-Null
                    $added++
                }
            }

            [System.Windows.MessageBox]::Show(
                "Imported $added of $($apps.Count) app(s) from:`n$($dlg.FileName)",
                'Import Complete', 'OK', 'Information')
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Import failed:`n$_", 'Import Error', 'OK', 'Error')
        }
    })

    # ── Export JSON ───────────────────────────────────────────────────────────
    $btnExport.Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title    = 'Export queue to JSON'
        $dlg.Filter   = 'JSON files (*.json)|*.json'
        $dlg.FileName = 'BulkUpload.json'
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $export = $script:bmRows | ForEach-Object {
            $h = @{}
            foreach ($key in $_.Keys) {
                if ($key -notmatch '^_') { $h[$key] = $_[$key] }
            }
            $h
        }

        $export | ConvertTo-Json -Depth 10 | Set-Content $dlg.FileName -Encoding UTF8
        [System.Windows.MessageBox]::Show(
            "Exported $($script:bmRows.Count) app(s) to:`n$($dlg.FileName)",
            'Export Complete', 'OK', 'Information')
    })

    # ── Upload ────────────────────────────────────────────────────────────────
    function Start-BulkUpload {
        param([bool]$SelectedOnly = $false)

        $toProcess = if ($SelectedOnly) {
            $selIds = @($bulkGrid.SelectedItems | ForEach-Object { $_['_Id'] -as [string] })
            @($script:bmRows | Where-Object { $selIds -contains $_._id })
        } else {
            @($script:bmRows)
        }

        if ($toProcess.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                'No apps to upload.', 'Upload', 'OK', 'Warning')
            return
        }

        $plural  = if ($toProcess.Count -ne 1) { 's' } else { '' }
        $confirm = [System.Windows.MessageBox]::Show(
            "Upload $($toProcess.Count) app$plural to Intune?`nThis may take several minutes.",
            'Confirm Upload', 'YesNo', 'Question')
        if ($confirm -ne 'Yes') { return }

        # Disable toolbar during upload
        foreach ($btn in @($btnAddRow,$btnBrowse,$btnFullSetup,$btnRemove,$btnClear,
                           $btnImport,$btnExport,$btnUploadSel,$btnUploadAll)) {
            $btn.IsEnabled = $false
        }
        $txtUploadResult.Text = ''

        $ok = 0; $fail = 0; $i = 0
        foreach ($row in $toProcess) {
            $i++
            Update-RowStatus -Id $row._id -Status 'Uploading...'
            $txtStatus.Text = "Uploading $i of $($toProcess.Count): $($row.DisplayName)…"
            $window.Dispatcher.Invoke([action]{}, 'Background')

            $appConfig = @{}
            foreach ($key in $row.Keys) {
                if ($key -notmatch '^_') { $appConfig[$key] = $row[$key] }
            }

            try {
                $result = Invoke-ProcessApp `
                    -AppConfig      $appConfig `
                    -Config         $Config `
                    -TemplateFolder $TemplateFolder

                if ($result.Success) {
                    Update-RowStatus -Id $row._id -Status 'Done'; $ok++
                } else {
                    Update-RowStatus -Id $row._id -Status 'Failed'; $fail++
                }
            }
            catch {
                Update-RowStatus -Id $row._id -Status 'Failed'; $fail++
            }
        }

        Refresh-StatusBar
        $summary = "$ok succeeded"
        if ($fail) { $summary += ", $fail failed" }
        $txtUploadResult.Text = $summary

        # Re-enable toolbar
        foreach ($btn in @($btnAddRow,$btnBrowse,$btnFullSetup,$btnRemove,$btnClear,$btnImport)) {
            $btn.IsEnabled = $true
        }
        Refresh-StatusBar  # re-enables export/upload buttons based on row count

        [System.Windows.MessageBox]::Show(
            "Bulk upload complete:`n  Succeeded: $ok`n  Failed:    $fail",
            'Upload Complete', 'OK',
            $(if ($fail -gt 0) { 'Warning' } else { 'Information' }))
    }

    $btnUploadAll.Add_Click({ Start-BulkUpload -SelectedOnly $false })
    $btnUploadSel.Add_Click({ Start-BulkUpload -SelectedOnly $true  })

    #endregion

    Refresh-StatusBar
    $window.ShowDialog() | Out-Null
}
