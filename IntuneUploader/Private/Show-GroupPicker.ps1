<#
.SYNOPSIS
    WPF modal dialog for searching Entra ID groups and building a multi-group assignment list.

.DESCRIPTION
    Opens a search box that queries Graph with a substring match (ConsistencyLevel: eventual).
    Results are displayed in a list — the user selects one or more and adds them to the
    "Selected Groups" list on the right. Supports manual GUID entry as a fallback.
    Returns an array of @{ GroupName='...'; GroupID='...' } hashtables, or $null on cancel.
#>

function Show-GroupPicker {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        # Groups already assigned (pre-populate the selected list)
        [object[]]$AlreadySelected = @()
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase | Out-Null

    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Search and Select Groups"
    Width="660" Height="540"
    WindowStartupLocation="CenterOwner"
    ResizeMode="CanResize">

  <Window.Resources>
    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="Background"      Value="#4A2B8F"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="14,5"/>
      <Setter Property="Cursor"          Value="Hand"/>
    </Style>
  </Window.Resources>

  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>  <!-- Header -->
      <RowDefinition Height="*"/>     <!-- Two-panel search + selected -->
      <RowDefinition Height="Auto"/>  <!-- Manual ID entry -->
      <RowDefinition Height="Auto"/>  <!-- Footer buttons -->
    </Grid.RowDefinitions>

    <!-- Header strip -->
    <TextBlock Grid.Row="0" Margin="0,0,0,10"
               Text="Search for groups by name. Partial matches are supported — type a keyword and click Search."
               TextWrapping="Wrap" FontSize="11" Foreground="#444"/>

    <!-- Two-panel main area -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>    <!-- Search / results -->
        <ColumnDefinition Width="10"/>
        <ColumnDefinition Width="*"/>    <!-- Selected groups -->
      </Grid.ColumnDefinitions>

      <!-- LEFT: Search + results -->
      <Grid Grid.Column="0">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="Search" FontWeight="SemiBold" Margin="0,0,0,4"/>
        <Grid Grid.Row="1" Margin="0,0,0,4">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="TxtSearch" Grid.Column="0" Padding="6,4" Margin="0,0,4,0"
                   ToolTip="Type part of the group name, then click Search"/>
          <Button  x:Name="BtnSearch" Grid.Column="1" Content="Search" Padding="12,4"/>
        </Grid>

        <ListBox x:Name="LstResults" Grid.Row="2"
                 SelectionMode="Extended"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled">
          <ListBox.ItemTemplate>
            <DataTemplate>
              <StackPanel Margin="2">
                <TextBlock Text="{Binding DisplayName}" FontWeight="SemiBold" FontSize="12"/>
                <TextBlock Text="{Binding ID}" FontSize="10" Foreground="#888" FontFamily="Consolas"/>
              </StackPanel>
            </DataTemplate>
          </ListBox.ItemTemplate>
        </ListBox>

        <StackPanel Grid.Row="3" Margin="0,4,0,0">
          <TextBlock x:Name="TxtSearchStatus" FontSize="10" Foreground="#666" Margin="0,0,0,4"/>
          <Button x:Name="BtnAddSelected" Content="Add Selected  →" HorizontalAlignment="Left"
                  Padding="10,4"/>
        </StackPanel>
      </Grid>

      <!-- RIGHT: Selected groups -->
      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="Selected Groups" FontWeight="SemiBold" Margin="0,0,0,4"/>

        <ListBox x:Name="LstSelected" Grid.Row="1"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled">
          <ListBox.ItemTemplate>
            <DataTemplate>
              <StackPanel Margin="2">
                <TextBlock Text="{Binding DisplayName}" FontWeight="SemiBold" FontSize="12"/>
                <TextBlock Text="{Binding ID}" FontSize="10" Foreground="#888" FontFamily="Consolas"/>
              </StackPanel>
            </DataTemplate>
          </ListBox.ItemTemplate>
        </ListBox>

        <Button x:Name="BtnRemoveSelected" Grid.Row="2" Content="Remove Selected"
                HorizontalAlignment="Left" Padding="10,4" Margin="0,4,0,0"/>
      </Grid>
    </Grid>

    <!-- Manual GUID entry -->
    <Border Grid.Row="2" BorderBrush="#DDD" BorderThickness="0,1,0,0" Padding="0,8,0,4" Margin="0,8,0,0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" FontSize="11" Foreground="#555" Margin="0,0,0,4"
                   Text="Or add a group manually by Object ID (useful if not connected or group isn't returned by search):"/>
        <Grid Grid.Row="1">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="8"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="TxtManualName" Grid.Column="0" Padding="6,4"
                   ToolTip="Display name (for your reference)"/>
          <TextBox x:Name="TxtManualID" Grid.Column="2" Padding="6,4"
                   FontFamily="Consolas" FontSize="11"
                   ToolTip="Group Object ID — found in Entra ID (Azure AD) → Groups → Properties → Object ID"/>
          <Button  x:Name="BtnAddManual" Grid.Column="3" Content="Add" Padding="12,4" Margin="8,0,0,0"/>
        </Grid>
        <TextBlock x:Name="TxtManualHint" Margin="0,6,0,0" FontSize="10" Foreground="#999"
                   Text="Name column is for reference only · Object ID is the GUID used during upload"/>
      </Grid>
    </Border>

    <!-- Footer -->
    <Grid Grid.Row="3" Margin="0,8,0,0">
      <TextBlock x:Name="TxtSelectedCount" VerticalAlignment="Center" FontSize="11" Foreground="#555"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnOK"     Content="OK"     Style="{StaticResource PrimaryBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnCancel" Content="Cancel" Padding="12,5" IsCancel="True"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    function Find { param($n) $window.FindName($n) }

    $txtSearch       = Find 'TxtSearch'
    $btnSearch       = Find 'BtnSearch'
    $lstResults      = Find 'LstResults'
    $txtSearchStatus = Find 'TxtSearchStatus'
    $btnAddSelected  = Find 'BtnAddSelected'
    $lstSelected     = Find 'LstSelected'
    $btnRemoveSelected = Find 'BtnRemoveSelected'
    $txtManualName   = Find 'TxtManualName'
    $txtManualID     = Find 'TxtManualID'
    $btnAddManual    = Find 'BtnAddManual'
    $txtSelectedCount = Find 'TxtSelectedCount'
    $btnOK           = Find 'BtnOK'
    $btnCancel       = Find 'BtnCancel'

    # ── Internal state ────────────────────────────────────────────────────────
    # Each item: PSCustomObject with DisplayName, ID
    $script:pickerSelected = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

    # Pre-populate from AlreadySelected
    foreach ($grp in $AlreadySelected) {
        $name = if ($grp -is [hashtable]) { $grp.GroupName ?? $grp.DisplayName ?? '' } else { $grp.GroupName ?? '' }
        $id   = if ($grp -is [hashtable]) { $grp.GroupID   ?? $grp.ID ?? '' }           else { $grp.GroupID   ?? '' }
        if ($id) {
            $script:pickerSelected.Add([PSCustomObject]@{ DisplayName = $name; ID = $id }) | Out-Null
        }
    }

    $lstSelected.ItemsSource = $script:pickerSelected

    function Update-Count {
        $n = $script:pickerSelected.Count
        $txtSelectedCount.Text = "$n group$(if($n -ne 1){'s'}) selected"
    }

    function Add-ToSelected {
        param([string]$Name, [string]$Id)
        if (-not $Id) { return }
        # Deduplicate by ID
        if ($script:pickerSelected | Where-Object { $_.ID -eq $Id }) { return }
        $script:pickerSelected.Add([PSCustomObject]@{ DisplayName = $Name; ID = $Id }) | Out-Null
        Update-Count
    }

    # ── Group search ─────────────────────────────────────────────────────────
    function Invoke-GroupSearch {
        param([string]$Term)

        # Prefer $Global:AuthenticationHeader (set by Connect-MSIntuneGraph)
        $authHeader = $Global:AuthenticationHeader
        if (-not $authHeader -or -not $authHeader['Authorization']) {
            throw "Not connected to Intune. Please connect from the main window first."
        }

        $headers = @{
            'Authorization'    = $authHeader['Authorization']
            'Content-Type'     = 'application/json'
            'ConsistencyLevel' = 'eventual'
        }

        # Use $search for substring match — requires ConsistencyLevel: eventual
        # The search term must be double-quoted in the query string (%22 = ")
        $escapedTerm = [System.Uri]::EscapeDataString($Term)
        $url = "https://graph.microsoft.com/v1.0/groups?`$search=%22displayName:$escapedTerm%22&`$count=true&`$select=id,displayName&`$top=50&`$orderby=displayName asc"

        try {
            $resp = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
            return @($resp.value | Sort-Object displayName)
        }
        catch {
            # Fall back to startsWith filter (no ConsistencyLevel needed)
            $headers2 = @{
                'Authorization' = $authHeader['Authorization']
                'Content-Type'  = 'application/json'
            }
            $url2 = "https://graph.microsoft.com/v1.0/groups?`$filter=startsWith(displayName,'$([System.Uri]::EscapeDataString($Term))')&`$select=id,displayName&`$top=50"
            $resp2 = Invoke-RestMethod -Uri $url2 -Method GET -Headers $headers2
            return @($resp2.value | Sort-Object displayName)
        }
    }

    # ── Event handlers ────────────────────────────────────────────────────────

    $doSearch = {
        $term = $txtSearch.Text.Trim()
        if ($term.Length -lt 2) {
            $txtSearchStatus.Text = 'Enter at least 2 characters to search.'
            return
        }
        $txtSearchStatus.Text = 'Searching...'
        $lstResults.ItemsSource = $null

        try {
            $results = @(Invoke-GroupSearch -Term $term)
            $items = $results | ForEach-Object {
                [PSCustomObject]@{ DisplayName = $_.displayName; ID = $_.id }
            }
            $lstResults.ItemsSource = $items
            $txtSearchStatus.Text = if ($items.Count -eq 0) {
                'No groups found.'
            } elseif ($items.Count -eq 50) {
                "Showing first 50 results — refine your search for more specific results."
            } else {
                "$($items.Count) group$(if($items.Count -ne 1){'s'}) found."
            }
        }
        catch {
            $txtSearchStatus.Text = "Search failed: $_"
        }
    }

    $btnSearch.Add_Click($doSearch)
    $txtSearch.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) { & $doSearch }
    })

    $btnAddSelected.Add_Click({
        $sel = @($lstResults.SelectedItems)
        if (-not $sel) {
            [System.Windows.MessageBox]::Show('Select one or more groups from the results list first.', 'None Selected', 'OK', 'Information')
            return
        }
        foreach ($item in $sel) {
            Add-ToSelected -Name $item.DisplayName -Id $item.ID
        }
    })

    $btnRemoveSelected.Add_Click({
        $sel = @($lstSelected.SelectedItems)
        if (-not $sel) { return }
        foreach ($item in $sel) {
            $script:pickerSelected.Remove($item) | Out-Null
        }
        Update-Count
    })

    $btnAddManual.Add_Click({
        $id   = $txtManualID.Text.Trim()
        $name = $txtManualName.Text.Trim()
        if (-not $id) {
            [System.Windows.MessageBox]::Show('Enter a Group Object ID (GUID) to add manually.', 'ID Required', 'OK', 'Warning')
            return
        }
        Add-ToSelected -Name ($name ?? $id) -Id $id
        $txtManualID.Text   = ''
        $txtManualName.Text = ''
    })

    $btnOK.Add_Click({
        $window.DialogResult = $true
        $window.Close()
    })
    $btnCancel.Add_Click({ $window.DialogResult = $false; $window.Close() })

    # ── Initial state ─────────────────────────────────────────────────────────
    Update-Count

    $ok = $window.ShowDialog()
    if (-not $ok) { return $null }

    return @($script:pickerSelected | ForEach-Object {
        @{ GroupName = $_.DisplayName; GroupID = $_.ID }
    })
}
