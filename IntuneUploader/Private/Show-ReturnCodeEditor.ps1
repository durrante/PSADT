<#
.SYNOPSIS
    WPF modal dialog for viewing and editing Intune Win32 app return codes.

.DESCRIPTION
    Displays a DataGrid pre-populated with the supplied return codes (or defaults).
    The user can add rows, remove selected rows, edit values inline, and reset to
    the Intune-default set.

    Returns an array of @{ ReturnCode = <int>; Type = '<string>' } hashtables,
    or $null if the user cancels.

.PARAMETER CurrentCodes
    Existing return codes to display. If omitted, the Intune defaults are loaded.
#>

function Show-ReturnCodeEditor {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [object[]]$CurrentCodes = @()
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase | Out-Null

    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Return Codes"
    Width="520" Height="440"
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
    <Style x:Key="DangerBtn" TargetType="Button">
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="Background"      Value="#B00020"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="10,4"/>
      <Setter Property="Cursor"          Value="Hand"/>
    </Style>
  </Window.Resources>

  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>  <!-- Description -->
      <RowDefinition Height="*"/>     <!-- DataGrid -->
      <RowDefinition Height="Auto"/>  <!-- Row action buttons -->
      <RowDefinition Height="Auto"/>  <!-- Footer -->
    </Grid.RowDefinitions>

    <!-- Description -->
    <TextBlock Grid.Row="0" Margin="0,0,0,10" TextWrapping="Wrap" FontSize="11" Foreground="#444"
               Text="Define how the app installer's exit codes are interpreted by Intune. Click a cell to edit it inline."/>

    <!-- DataGrid -->
    <DataGrid x:Name="DgCodes" Grid.Row="1"
              AutoGenerateColumns="False"
              CanUserAddRows="False"
              CanUserDeleteRows="False"
              CanUserReorderColumns="False"
              CanUserResizeRows="False"
              SelectionMode="Single"
              SelectionUnit="FullRow"
              HeadersVisibility="Column"
              GridLinesVisibility="Horizontal"
              BorderBrush="#DDD" BorderThickness="1"
              RowBackground="White" AlternatingRowBackground="#F8F8FF"
              FontSize="12">
      <DataGrid.Columns>

        <!-- Return Code — plain text column -->
        <DataGridTextColumn Header="Return Code" Width="140"
                            Binding="{Binding ReturnCode, UpdateSourceTrigger=PropertyChanged}"
                            SortMemberPath="ReturnCode">
          <DataGridTextColumn.ElementStyle>
            <Style TargetType="TextBlock">
              <Setter Property="Padding"           Value="6,4"/>
              <Setter Property="FontFamily"        Value="Consolas"/>
              <Setter Property="VerticalAlignment" Value="Center"/>
            </Style>
          </DataGridTextColumn.ElementStyle>
          <DataGridTextColumn.EditingElementStyle>
            <Style TargetType="TextBox">
              <Setter Property="Padding"    Value="4,2"/>
              <Setter Property="FontFamily" Value="Consolas"/>
            </Style>
          </DataGridTextColumn.EditingElementStyle>
        </DataGridTextColumn>

        <!-- Type — template column with ComboBox in edit mode, TextBlock in display mode -->
        <DataGridTemplateColumn Header="Type" Width="*" SortMemberPath="Type">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock Text="{Binding Type}" VerticalAlignment="Center" Padding="6,4"/>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
          <DataGridTemplateColumn.CellEditingTemplate>
            <DataTemplate>
              <ComboBox SelectedValue="{Binding Type, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                        SelectedValuePath="Content"
                        VerticalAlignment="Center" Padding="4,2" BorderThickness="0">
                <ComboBoxItem Content="success"/>
                <ComboBoxItem Content="softReboot"/>
                <ComboBoxItem Content="hardReboot"/>
                <ComboBoxItem Content="retry"/>
                <ComboBoxItem Content="failed"/>
              </ComboBox>
            </DataTemplate>
          </DataGridTemplateColumn.CellEditingTemplate>
        </DataGridTemplateColumn>

      </DataGrid.Columns>
    </DataGrid>

    <!-- Row-level actions -->
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,8,0,0">
      <Button x:Name="BtnAddRow"    Content="Add Row"           Padding="10,4" Margin="0,0,6,0"/>
      <Button x:Name="BtnRemoveRow" Content="Remove Selected"   Style="{StaticResource DangerBtn}" Margin="0,0,6,0"/>
      <Button x:Name="BtnReset"     Content="Reset to Defaults" Padding="10,4"/>
    </StackPanel>

    <!-- Footer -->
    <Grid Grid.Row="3" Margin="0,12,0,0">
      <TextBlock x:Name="TxtStatus" VerticalAlignment="Center" FontSize="11" Foreground="#555"/>
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

    $dgCodes      = Find 'DgCodes'
    $btnAddRow    = Find 'BtnAddRow'
    $btnRemoveRow = Find 'BtnRemoveRow'
    $btnReset     = Find 'BtnReset'
    $txtStatus    = Find 'TxtStatus'
    $btnOK        = Find 'BtnOK'
    $btnCancel    = Find 'BtnCancel'

    # ── Default return codes (Intune built-in) ────────────────────────────────
    $script:defaultCodes = @(
        [PSCustomObject]@{ ReturnCode = 0;    Type = 'success'    }
        [PSCustomObject]@{ ReturnCode = 1707; Type = 'success'    }
        [PSCustomObject]@{ ReturnCode = 3010; Type = 'softReboot' }
        [PSCustomObject]@{ ReturnCode = 1641; Type = 'hardReboot' }
        [PSCustomObject]@{ ReturnCode = 1618; Type = 'retry'      }
    )

    # ── Observable collection bound to the grid ───────────────────────────────
    $script:codeList = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

    function Import-Codes {
        param([object[]]$Codes)
        $script:codeList.Clear()
        foreach ($rc in $Codes) {
            $code = if ($rc -is [hashtable]) { $rc.ReturnCode ?? $rc.returnCode }
                    else                     { $rc.ReturnCode ?? $rc.returnCode }
            $type = if ($rc -is [hashtable]) { $rc.Type ?? $rc.type ?? 'success' }
                    else                     { $rc.Type ?? $rc.type ?? 'success' }
            $script:codeList.Add([PSCustomObject]@{ ReturnCode = [int]$code; Type = [string]$type }) | Out-Null
        }
        Update-Status
    }

    function Update-Status {
        $n = $script:codeList.Count
        $txtStatus.Text = "$n return code$(if($n -ne 1){'s'})"
    }

    $dgCodes.ItemsSource = $script:codeList

    # Populate — use supplied codes if any, else defaults
    if ($CurrentCodes -and @($CurrentCodes).Count -gt 0) {
        Import-Codes -Codes $CurrentCodes
    } else {
        Import-Codes -Codes $script:defaultCodes
    }

    # ── Event handlers ────────────────────────────────────────────────────────

    $btnAddRow.Add_Click({
        $script:codeList.Add([PSCustomObject]@{ ReturnCode = 0; Type = 'success' }) | Out-Null
        $dgCodes.SelectedIndex = $script:codeList.Count - 1
        $dgCodes.ScrollIntoView($dgCodes.SelectedItem)
        Update-Status
    })

    $btnRemoveRow.Add_Click({
        $sel = $dgCodes.SelectedItem
        if (-not $sel) { return }
        # Commit any pending edit first
        $dgCodes.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
        $script:codeList.Remove($sel) | Out-Null
        Update-Status
    })

    $btnReset.Add_Click({
        $ans = [System.Windows.MessageBox]::Show(
            "Reset all return codes to the Intune defaults?`nThis will discard any changes.",
            'Reset Codes', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        Import-Codes -Codes $script:defaultCodes
    })

    $btnOK.Add_Click({
        # Commit any in-progress cell edit
        $dgCodes.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
        $window.DialogResult = $true
        $window.Close()
    })

    $btnCancel.Add_Click({ $window.DialogResult = $false; $window.Close() })

    # ── Show dialog ───────────────────────────────────────────────────────────
    $ok = $window.ShowDialog()
    if (-not $ok) { return $null }

    return @($script:codeList | ForEach-Object {
        @{ ReturnCode = [int]$_.ReturnCode; Type = [string]$_.Type }
    })
}
