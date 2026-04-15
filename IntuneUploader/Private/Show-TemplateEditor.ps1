<#
.SYNOPSIS
    WPF Template Editor — create and edit upload templates via a GUI.

.DESCRIPTION
    Templates are JSON files in the Templates folder that pre-fill defaults for
    upload jobs (commands, requirements, assignments, notifications, etc.).
    This editor provides a two-panel UI: a template list on the left and a
    tabbed editor form on the right. Changes are saved as .json files immediately
    when the user clicks Save Template.
#>

function Show-TemplateEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateFolder,

        # Optional: pass live filters from the connected tenant so the user can
        # pick one from a dropdown instead of typing a raw GUID.
        [object[]]$AvailableFilters = @()
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms | Out-Null

    # Valid MinimumSupportedWindowsRelease strings accepted by IntuneWin32App module
    $script:osVersions = @(
        '(Any / Not set)',
        'W10_1607','W10_1703','W10_1709','W10_1803','W10_1809',
        'W10_1903','W10_1909','W10_2004','W10_20H2',
        'W10_21H1','W10_21H2','W10_22H2',
        'W11_21H2','W11_22H2','W11_23H2','W11_24H2'
    )

    # Standard return codes included in every saved template
    $script:defaultReturnCodes = @(
        @{ ReturnCode = 0;    Type = 'success'    }
        @{ ReturnCode = 1707; Type = 'success'    }
        @{ ReturnCode = 3010; Type = 'softReboot' }
        @{ ReturnCode = 1641; Type = 'hardReboot' }
        @{ ReturnCode = 1618; Type = 'retry'      }
    )

    # Working copies of dynamic lists
    $script:tplReturnCodes = @($script:defaultReturnCodes)
    $script:tplGroups      = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

    # ── XAML ──────────────────────────────────────────────────────────────────
    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Template Editor"
    Width="980" Height="700"
    WindowStartupLocation="CenterScreen"
    MinWidth="720" MinHeight="520">

  <Window.Resources>

    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="Padding"         Value="14,5"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}"
                    CornerRadius="3" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.82"/></Trigger>
              <Trigger Property="IsPressed"   Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.65"/></Trigger>
              <Trigger Property="IsEnabled"   Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SecBtn" TargetType="Button">
      <Setter Property="Padding"         Value="10,4"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="BorderBrush"     Value="#CCC"/>
      <Setter Property="BorderThickness" Value="1"/>
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
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.82"/></Trigger>
              <Trigger Property="IsPressed"   Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.65"/></Trigger>
              <Trigger Property="IsEnabled"   Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="FieldLabel" TargetType="TextBlock">
      <Setter Property="FontSize"   Value="11"/>
      <Setter Property="Foreground" Value="#555"/>
      <Setter Property="Margin"     Value="0,10,0,2"/>
    </Style>

    <Style x:Key="FieldBox" TargetType="TextBox">
      <Setter Property="Padding"         Value="7,5"/>
      <Setter Property="BorderBrush"     Value="#CCC"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <Style x:Key="RadioOpt" TargetType="RadioButton">
      <Setter Property="Margin"            Value="0,0,16,0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <Style x:Key="HintText" TargetType="TextBlock">
      <Setter Property="FontSize"     Value="10"/>
      <Setter Property="Foreground"   Value="#999"/>
      <Setter Property="Margin"       Value="0,2,0,0"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <Style x:Key="InfoPanel" TargetType="Border">
      <Setter Property="Background"      Value="#EDF7ED"/>
      <Setter Property="BorderBrush"     Value="#A5D6A7"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius"    Value="4"/>
      <Setter Property="Padding"         Value="10,7"/>
      <Setter Property="Margin"          Value="0,8,0,0"/>
    </Style>

  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="52"/>   <!-- Header -->
      <RowDefinition Height="*"/>    <!-- Main content -->
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
      <Grid Margin="18,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Template Editor" FontSize="18" FontWeight="Light" Foreground="White"/>
          <TextBlock Text="Create and edit upload templates — saved as JSON in the Templates folder"
                     FontSize="11" Foreground="#D4C5F9" Margin="0,1,0,0"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ═══ MAIN CONTENT ═══ -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="220"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- ── LEFT: Template list ── -->
      <Border Grid.Column="0" BorderBrush="#DDD" BorderThickness="0,0,1,0" Background="#FAFAFA">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <Border Grid.Row="0" Background="#F0EBF9" Padding="12,8">
            <TextBlock Text="Templates" FontWeight="SemiBold" FontSize="12" Foreground="#4A2B8F"/>
          </Border>

          <ListBox x:Name="TplList" Grid.Row="1"
                   BorderThickness="0" Background="Transparent"
                   ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                   Padding="4"/>

          <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="8,6,8,8">
            <Button x:Name="BtnNew"       Content="New"       Style="{StaticResource SecBtn}" Margin="0,0,4,0"/>
            <Button x:Name="BtnDuplicate" Content="Duplicate" Style="{StaticResource SecBtn}" Margin="0,0,4,0"/>
            <Button x:Name="BtnDelete"    Content="Delete"    Style="{StaticResource SecBtn}" Foreground="#C62828"/>
          </StackPanel>
        </Grid>
      </Border>

      <!-- ── RIGHT: Editor form ── -->
      <Grid Grid.Column="1">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/> <!-- Name / Description strip -->
          <RowDefinition Height="*"/>    <!-- Tabs -->
        </Grid.RowDefinitions>

        <!-- Name + Description across the top -->
        <Border Grid.Row="0" Padding="16,10,16,12" BorderBrush="#EEE" BorderThickness="0,0,0,1">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="16"/>
              <ColumnDefinition Width="2*"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock Text="Template Name" Style="{StaticResource FieldLabel}" Margin="0,0,0,2"/>
              <TextBox x:Name="TxtTplName" Style="{StaticResource FieldBox}"
                       ToolTip="Filename used to save the template (no special characters)"/>
            </StackPanel>
            <StackPanel Grid.Column="2">
              <TextBlock Text="Description" Style="{StaticResource FieldLabel}" Margin="0,0,0,2"/>
              <TextBox x:Name="TxtTplDescription" Style="{StaticResource FieldBox}"
                       ToolTip="Short description shown in the template list"/>
            </StackPanel>
          </Grid>
        </Border>

        <!-- Tabs -->
        <TabControl Grid.Row="1" BorderThickness="0">

          <!-- ══ Tab 1: General ══ -->
          <TabItem Header="  General  ">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="20,8,20,20">

                <!-- PSADT / Uninstall toggles first so they can control field state -->
                <CheckBox x:Name="ChkIsPSADT" Margin="0,6,0,0"
                          Content="PSADT Package"/>

                <!-- Info panel shown when PSADT is ticked -->
                <Border x:Name="PanelPsadtInfo" Style="{StaticResource InfoPanel}"
                        Visibility="Collapsed">
                  <StackPanel>
                    <TextBlock FontSize="11" FontWeight="SemiBold" Foreground="#2E7D32" Margin="0,0,0,4"
                               Text="PSADT auto-fill is active"/>
                    <TextBlock FontSize="11" Foreground="#388E3C" TextWrapping="Wrap"
                               Text="When this template is used, the following fields are read directly from the PSADT AppDeployToolkit manifest and cannot be overridden here:"/>
                    <TextBlock FontSize="11" Foreground="#388E3C" Margin="8,4,0,0"
                               Text="&#x2022;  Notes / Internal Note  (AppScriptAuthor)&#x0A;&#x2022;  Owner  (AppScriptAuthor)&#x0A;&#x2022;  Display Name, Version, Publisher"/>
                    <TextBlock FontSize="11" Foreground="#388E3C" Margin="0,6,0,0" TextWrapping="Wrap"
                               Text="Install and Uninstall commands are also auto-suggested from the manifest, but you can override them below if needed."/>
                  </StackPanel>
                </Border>

                <TextBlock Text="Notes" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="TxtTplNotes" Style="{StaticResource FieldBox}"
                         AcceptsReturn="True" Height="64" TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"/>
                <TextBlock x:Name="TxtNotesHint" Style="{StaticResource HintText}"
                           Text="Written to the Intune app's Notes field."/>

                <TextBlock Text="Owner" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="TxtTplOwner" Style="{StaticResource FieldBox}"/>
                <TextBlock x:Name="TxtOwnerHint" Style="{StaticResource HintText}"
                           Text="Person or team responsible for this application."/>

                <Separator Margin="0,16,0,6"/>

                <CheckBox x:Name="ChkAllowUninstall" Margin="0,4,0,0"
                          Content="Allow users to uninstall from Company Portal  (AllowAvailableUninstall)"/>

                <TextBlock Text="Maximum Installation Time (minutes)" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="TxtTplTimeout" Style="{StaticResource FieldBox}"
                         Width="80" HorizontalAlignment="Left" Text="60"/>

              </StackPanel>
            </ScrollViewer>
          </TabItem>

          <!-- ══ Tab 2: Commands ══ -->
          <TabItem Header="  Commands  ">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="20,8,20,20">

                <TextBlock Text="Install Command" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="TxtTplInstallCmd" Style="{StaticResource FieldBox}"
                         FontFamily="Consolas" FontSize="12"/>
                <TextBlock x:Name="TxtInstallHint" Style="{StaticResource HintText}"
                           Text="Leave blank to use the default command for the package type."/>

                <TextBlock Text="Uninstall Command" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="TxtTplUninstallCmd" Style="{StaticResource FieldBox}"
                         FontFamily="Consolas" FontSize="12"/>

                <TextBlock Text="Install Context" Style="{StaticResource FieldLabel}"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                  <RadioButton x:Name="RdoCtxSystem" Content="System (recommended)" GroupName="TplCtx"
                               Style="{StaticResource RadioOpt}" IsChecked="True"/>
                  <RadioButton x:Name="RdoCtxUser"   Content="User context"          GroupName="TplCtx"
                               Style="{StaticResource RadioOpt}"/>
                </StackPanel>

                <TextBlock Text="Device Restart Behavior" Style="{StaticResource FieldLabel}"/>
                <StackPanel Margin="0,4,0,0">
                  <RadioButton x:Name="RdoRstSuppress"   Content="No specific action"                           GroupName="TplRst"
                               Style="{StaticResource RadioOpt}" IsChecked="True" Margin="0,0,0,4"/>
                  <RadioButton x:Name="RdoRstAllow"      Content="App install may force a device restart"       GroupName="TplRst"
                               Style="{StaticResource RadioOpt}" Margin="0,0,0,4"/>
                  <RadioButton x:Name="RdoRstReturnCode" Content="Determine behavior based on return codes"     GroupName="TplRst"
                               Style="{StaticResource RadioOpt}" Margin="0,0,0,4"/>
                  <RadioButton x:Name="RdoRstForce"      Content="Intune will force a mandatory device restart" GroupName="TplRst"
                               Style="{StaticResource RadioOpt}"/>
                </StackPanel>

                <Separator Margin="0,16,0,8"/>

                <!-- Return codes -->
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock FontWeight="SemiBold" FontSize="13" Text="Return Codes"/>
                    <TextBlock Style="{StaticResource HintText}" Margin="0,2,0,0"
                               Text="Define how installer exit codes are interpreted by Intune. Defaults match the Intune built-ins."/>
                  </StackPanel>
                  <Button x:Name="BtnReturnCodes" Grid.Column="1" Content="Edit Return Codes..."
                          Padding="10,5" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock x:Name="TxtRCStatus" FontSize="11" Foreground="#666" Margin="0,4,0,0"
                           Text="5 codes (defaults)"/>

              </StackPanel>
            </ScrollViewer>
          </TabItem>

          <!-- ══ Tab 3: Requirements ══ -->
          <TabItem Header="  Requirements  ">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="20,8,20,20">

                <TextBlock Text="Architecture" Style="{StaticResource FieldLabel}"/>
                <TextBlock Style="{StaticResource HintText}" Margin="0,0,0,4"
                           Text="Select all architectures this package supports. Multiple selections are combined."/>
                <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
                  <CheckBox x:Name="ChkArch64"  Content="x64 (64-bit)"  Margin="0,0,20,0" IsChecked="True"/>
                  <CheckBox x:Name="ChkArch32"  Content="x86 (32-bit)"  Margin="0,0,20,0"/>
                  <CheckBox x:Name="ChkArchArm" Content="ARM64"          Margin="0,0,20,0"/>
                </StackPanel>
                <TextBlock Style="{StaticResource HintText}" Margin="0,4,0,0"
                           Text="x64 + ARM64 → deploys to both 64-bit Intel and ARM devices."/>

                <TextBlock Text="Minimum Windows Version" Style="{StaticResource FieldLabel}"/>
                <ComboBox x:Name="CmbMinOS" Width="180" HorizontalAlignment="Left" Margin="0,4,0,0"/>
                <TextBlock Style="{StaticResource HintText}"
                           Text="Corresponds to MinimumSupportedWindowsRelease in the IntuneWin32App module."/>

              </StackPanel>
            </ScrollViewer>
          </TabItem>

          <!-- ══ Tab 4: Assignment ══ -->
          <TabItem Header="  Assignment  ">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="20,8,20,20">

                <!-- Assignment type -->
                <TextBlock Text="Assignment Type" Style="{StaticResource FieldLabel}"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                  <RadioButton x:Name="RdoAsgAllDevices" Content="All Devices" GroupName="TplAsgType"
                               Style="{StaticResource RadioOpt}" IsChecked="True"/>
                  <RadioButton x:Name="RdoAsgAllUsers"   Content="All Users"   GroupName="TplAsgType"
                               Style="{StaticResource RadioOpt}"/>
                  <RadioButton x:Name="RdoAsgGroup"      Content="Group(s)"    GroupName="TplAsgType"
                               Style="{StaticResource RadioOpt}"/>
                  <RadioButton x:Name="RdoAsgNone" Content="None (no assignment)" GroupName="TplAsgType"
                               Style="{StaticResource RadioOpt}"/>
                </StackPanel>

                <!-- Group panel — shown only when Group is selected -->
                <Border x:Name="PanelGroup" Margin="0,8,0,0" Padding="12"
                        Background="#F5F0FF" CornerRadius="4" Visibility="Collapsed">
                  <StackPanel>
                    <Grid Margin="0,0,0,6">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock Grid.Column="0" FontWeight="SemiBold" FontSize="12"
                                 VerticalAlignment="Center" Text="Selected Groups"/>
                      <Button x:Name="BtnSearchGroups" Grid.Column="1"
                              Content="Search / Add Groups..."
                              Padding="10,4"/>
                    </Grid>

                    <ListBox x:Name="LstGroups" MinHeight="80" MaxHeight="160"
                             BorderBrush="#CCC" BorderThickness="1" Background="White"
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

                    <TextBlock FontSize="10" Foreground="#777" Margin="0,4,0,0"
                               Text="Sign in from the main window to search by name. You can also add groups by Object ID via the picker."/>
                    <Button x:Name="BtnRemoveGroup" Content="Remove Selected"
                            HorizontalAlignment="Left" Padding="8,3" Margin="0,6,0,0"/>
                  </StackPanel>
                </Border>

                <!-- Intent -->
                <TextBlock Text="Intent" Style="{StaticResource FieldLabel}"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                  <RadioButton x:Name="RdoIntRequired"  Content="Required"  GroupName="TplIntent"
                               Style="{StaticResource RadioOpt}" IsChecked="True"/>
                  <RadioButton x:Name="RdoIntAvailable" Content="Available" GroupName="TplIntent"
                               Style="{StaticResource RadioOpt}"/>
                  <RadioButton x:Name="RdoIntUninstall" Content="Uninstall" GroupName="TplIntent"
                               Style="{StaticResource RadioOpt}"/>
                </StackPanel>

                <!-- Notification -->
                <TextBlock Text="User Notification" Style="{StaticResource FieldLabel}"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                  <RadioButton x:Name="RdoNotifAll"    Content="Show all notifications"   GroupName="TplNotif"
                               Style="{StaticResource RadioOpt}" IsChecked="True"/>
                  <RadioButton x:Name="RdoNotifReboot" Content="Restart notifications only" GroupName="TplNotif"
                               Style="{StaticResource RadioOpt}"/>
                  <RadioButton x:Name="RdoNotifHide"   Content="Hide all"                 GroupName="TplNotif"
                               Style="{StaticResource RadioOpt}"/>
                </StackPanel>

                <!-- Assignment filter -->
                <Separator Margin="0,18,0,8"/>
                <TextBlock Text="Assignment Filter" FontWeight="SemiBold" FontSize="13"/>
                <TextBlock Style="{StaticResource HintText}" Margin="0,2,0,0"
                           Text="Optional — applies an Intune assignment filter to this template's assignment."/>

                <TextBlock Text="Filter" Style="{StaticResource FieldLabel}"/>
                <ComboBox x:Name="CmbFilter" Margin="0,4,0,0"
                          ToolTip="Populated from connected tenant. Enter the ID manually if not connected."/>

                <TextBlock Text="Filter ID (GUID) — leave blank if no filter" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="TxtFilterID" Style="{StaticResource FieldBox}"
                         FontFamily="Consolas" FontSize="12"/>
                <TextBlock Style="{StaticResource HintText}"
                           Text="Intune → Tenant admin → Filters → select filter → Object ID"/>

                <TextBlock Text="Filter Mode" Style="{StaticResource FieldLabel}"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                  <RadioButton x:Name="RdoFilterInclude" Content="Include" GroupName="TplFilter"
                               Style="{StaticResource RadioOpt}" IsChecked="True"/>
                  <RadioButton x:Name="RdoFilterExclude" Content="Exclude" GroupName="TplFilter"
                               Style="{StaticResource RadioOpt}"/>
                </StackPanel>

              </StackPanel>
            </ScrollViewer>
          </TabItem>

        </TabControl>
      </Grid>
    </Grid>

    <!-- ═══ FOOTER ═══ -->
    <Border Grid.Row="2" Background="#F5F5F5" BorderBrush="#DDD" BorderThickness="0,1,0,0" Padding="16,8">
      <Grid>
        <TextBlock x:Name="TxtTplStatus" VerticalAlignment="Center" FontSize="11" Foreground="#555"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnSaveTpl"  Content="Save Template" Background="#4A2B8F"
                  Style="{StaticResource PrimaryBtn}" Margin="0,0,8,0"/>
          <Button x:Name="BtnCloseTpl" Content="Close"         Background="#888"
                  Style="{StaticResource PrimaryBtn}"/>
        </StackPanel>
      </Grid>
    </Border>

  </Grid>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    function Find { param($n) $window.FindName($n) }

    $tplList          = Find 'TplList'
    $btnNew           = Find 'BtnNew'
    $btnDuplicate     = Find 'BtnDuplicate'
    $btnDelete        = Find 'BtnDelete'
    $txtTplName       = Find 'TxtTplName'
    $txtTplDesc       = Find 'TxtTplDescription'
    $txtTplNotes      = Find 'TxtTplNotes'
    $txtNotesHint     = Find 'TxtNotesHint'
    $txtTplOwner      = Find 'TxtTplOwner'
    $txtOwnerHint     = Find 'TxtOwnerHint'
    $chkIsPSADT       = Find 'ChkIsPSADT'
    $panelPsadtInfo   = Find 'PanelPsadtInfo'
    $chkAllowUninst   = Find 'ChkAllowUninstall'
    $txtTplTimeout    = Find 'TxtTplTimeout'
    $txtTplInstall    = Find 'TxtTplInstallCmd'
    $txtInstallHint   = Find 'TxtInstallHint'
    $txtTplUninstall  = Find 'TxtTplUninstallCmd'
    $rdoCtxSystem     = Find 'RdoCtxSystem'
    $rdoCtxUser       = Find 'RdoCtxUser'
    $rdoRstSuppress   = Find 'RdoRstSuppress'
    $rdoRstReturnCode = Find 'RdoRstReturnCode'
    $rdoRstForce      = Find 'RdoRstForce'
    $rdoRstAllow      = Find 'RdoRstAllow'
    $btnReturnCodes   = Find 'BtnReturnCodes'
    $txtRCStatus      = Find 'TxtRCStatus'
    $chkArch64        = Find 'ChkArch64'
    $chkArch32        = Find 'ChkArch32'
    $chkArchArm       = Find 'ChkArchArm'
    $cmbMinOS         = Find 'CmbMinOS'
    $rdoAsgAllDev     = Find 'RdoAsgAllDevices'
    $rdoAsgAllUsr     = Find 'RdoAsgAllUsers'
    $rdoAsgGroup      = Find 'RdoAsgGroup'
    $rdoAsgNone       = Find 'RdoAsgNone'
    $panelGroup       = Find 'PanelGroup'
    $btnSearchGroups  = Find 'BtnSearchGroups'
    $lstGroups        = Find 'LstGroups'
    $btnRemoveGroup   = Find 'BtnRemoveGroup'
    $rdoIntRequired   = Find 'RdoIntRequired'
    $rdoIntAvailable  = Find 'RdoIntAvailable'
    $rdoIntUninstall  = Find 'RdoIntUninstall'
    $rdoNotifAll      = Find 'RdoNotifAll'
    $rdoNotifReboot   = Find 'RdoNotifReboot'
    $rdoNotifHide     = Find 'RdoNotifHide'
    $cmbFilter        = Find 'CmbFilter'
    $txtFilterID      = Find 'TxtFilterID'
    $rdoFilterInclude = Find 'RdoFilterInclude'
    $rdoFilterExclude = Find 'RdoFilterExclude'
    $txtTplStatus     = Find 'TxtTplStatus'
    $btnSaveTpl       = Find 'BtnSaveTpl'
    $btnCloseTpl      = Find 'BtnCloseTpl'

    # ── Bind groups collection to ListBox ─────────────────────────────────────
    $lstGroups.ItemsSource = $script:tplGroups

    # ── Populate static lists ─────────────────────────────────────────────────
    foreach ($v in $script:osVersions) { $cmbMinOS.Items.Add($v) | Out-Null }
    $cmbMinOS.SelectedIndex = 0

    $cmbFilter.Items.Add('(None)') | Out-Null
    foreach ($f in ($AvailableFilters | Sort-Object { $_.displayName })) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $f.displayName
        $item.Tag     = $f.id
        $cmbFilter.Items.Add($item) | Out-Null
    }
    $cmbFilter.SelectedIndex = 0

    $cmbFilter.Add_SelectionChanged({
        $sel = $cmbFilter.SelectedItem
        if ($sel -is [System.Windows.Controls.ComboBoxItem] -and $sel.Tag) {
            $txtFilterID.Text = $sel.Tag
        } elseif ($cmbFilter.SelectedIndex -eq 0) {
            $txtFilterID.Text = ''
        }
    })

    # ─────────────────────────────────────────────────────────────────────────
    #region Arch helpers (mirrors Show-AppUploadForm pattern)
    # ─────────────────────────────────────────────────────────────────────────

    function Get-ArchValue {
        $x64 = $chkArch64.IsChecked
        $x86 = $chkArch32.IsChecked
        $arm = $chkArchArm.IsChecked
        if ($x64 -and $x86 -and $arm) { return 'AllWithARM64' }
        if ($x64 -and $arm)           { return 'x64arm64'     }
        if ($x64 -and $x86)           { return 'x64x86'       }
        if ($x64)                     { return 'x64'           }
        if ($x86)                     { return 'x86'           }
        if ($arm)                     { return 'arm64'         }
        return 'x64'  # fallback
    }

    function Set-ArchValue {
        param([string]$val)
        $chkArch64.IsChecked  = $val -in @('x64','x64x86','x64arm64','AllWithARM64') -or (-not $val)
        $chkArch32.IsChecked  = $val -in @('x86','x64x86','AllWithARM64')
        $chkArchArm.IsChecked = $val -in @('arm64','x64arm64','AllWithARM64')
    }

    #endregion

    # ─────────────────────────────────────────────────────────────────────────
    #region Return-code status helper
    # ─────────────────────────────────────────────────────────────────────────

    function Update-RCStatus {
        $n = @($script:tplReturnCodes).Count
        $txtRCStatus.Text = "$n return code$(if($n -ne 1){'s'})"
    }

    #endregion

    # ─────────────────────────────────────────────────────────────────────────
    #region PSADT toggle helpers
    # ─────────────────────────────────────────────────────────────────────────

    function Apply-PsadtState {
        param([bool]$IsPSADT)
        if ($IsPSADT) {
            $panelPsadtInfo.Visibility = [System.Windows.Visibility]::Visible
            $txtTplNotes.IsEnabled = $false
            $txtTplOwner.IsEnabled = $false
            $txtNotesHint.Text  = 'Auto-filled from PSADT AppScriptAuthor when the template is used.'
            $txtOwnerHint.Text  = 'Auto-filled from PSADT AppScriptAuthor when the template is used.'
            $txtInstallHint.Text = 'Auto-suggested from PSADT manifest — you can override this if needed.'
        } else {
            $panelPsadtInfo.Visibility = [System.Windows.Visibility]::Collapsed
            $txtTplNotes.IsEnabled = $true
            $txtTplOwner.IsEnabled = $true
            $txtNotesHint.Text  = 'Written to the Intune app Notes field.'
            $txtOwnerHint.Text  = 'Person or team responsible for this application.'
            $txtInstallHint.Text = 'Leave blank to use the default command for the package type.'
        }
    }

    #endregion

    # ─────────────────────────────────────────────────────────────────────────
    #region Helper functions
    # ─────────────────────────────────────────────────────────────────────────

    function Refresh-TplList {
        $selected = $tplList.SelectedItem -as [string]
        $tplList.Items.Clear()
        @(Get-ChildItem -Path $TemplateFolder -Filter '*.json' -ErrorAction SilentlyContinue |
          Sort-Object Name) | ForEach-Object { $tplList.Items.Add($_.BaseName) | Out-Null }
        if ($selected -and $tplList.Items.Contains($selected)) {
            $tplList.SelectedItem = $selected
        }
    }

    function Clear-Form {
        $txtTplName.Text       = ''
        $txtTplDesc.Text       = ''
        $txtTplNotes.Text      = ''
        $txtTplOwner.Text      = ''
        $chkIsPSADT.IsChecked  = $false
        $chkAllowUninst.IsChecked = $false
        $txtTplTimeout.Text    = '60'
        $txtTplInstall.Text    = ''
        $txtTplUninstall.Text  = ''
        $rdoCtxSystem.IsChecked    = $true
        $rdoRstSuppress.IsChecked  = $true
        Set-ArchValue -val 'x64'
        $cmbMinOS.SelectedIndex    = 0
        $rdoAsgAllDev.IsChecked    = $true
        $rdoIntRequired.IsChecked  = $true
        $rdoNotifAll.IsChecked     = $true
        $cmbFilter.SelectedIndex   = 0
        $txtFilterID.Text          = ''
        $rdoFilterInclude.IsChecked = $true
        $panelGroup.Visibility = [System.Windows.Visibility]::Collapsed
        $script:tplGroups.Clear()
        $script:tplReturnCodes = @($script:defaultReturnCodes)
        Update-RCStatus
        Apply-PsadtState -IsPSADT $false
        $txtTplStatus.Text = ''
    }

    function Load-Template {
        param([string]$Name)
        $path = Join-Path $TemplateFolder "$Name.json"
        if (-not (Test-Path $path)) { return }

        try {
            $t = Get-Content $path -Raw | ConvertFrom-Json

            $txtTplName.Text  = $t.TemplateName ?? $Name
            $txtTplDesc.Text  = $t.Description  ?? ''
            $txtTplNotes.Text = if ($t.Notes) { $t.Notes } elseif ($t.InternalNote) { $t.InternalNote } else { '' }
            $txtTplOwner.Text = $t.Owner ?? ''
            $chkIsPSADT.IsChecked     = [bool]$t.IsPSADT
            $chkAllowUninst.IsChecked = [bool]$t.AllowAvailableUninstall
            $txtTplTimeout.Text    = [string]($t.MaximumInstallationTimeInMinutes ?? '60')
            $txtTplInstall.Text    = $t.InstallCommandLine   ?? ''
            $txtTplUninstall.Text  = $t.UninstallCommandLine ?? ''

            # Apply PSADT greying
            Apply-PsadtState -IsPSADT ([bool]$t.IsPSADT)

            # Install context
            $rdoCtxUser.IsChecked   = ($t.InstallExperience -eq 'user')
            $rdoCtxSystem.IsChecked = ($t.InstallExperience -ne 'user')

            # Restart behaviour
            switch ($t.RestartBehavior) {
                'basedOnReturnCode' { $rdoRstReturnCode.IsChecked = $true }
                'force'             { $rdoRstForce.IsChecked      = $true }
                'allow'             { $rdoRstAllow.IsChecked      = $true }
                default             { $rdoRstSuppress.IsChecked   = $true }
            }

            # Architecture — support both old radio style (single string) and new checkbox style
            Set-ArchValue -val ([string]($t.Architecture ?? 'x64'))

            # Minimum OS
            $osVal = $t.MinimumSupportedWindowsRelease ?? ''
            if ($osVal -and $script:osVersions -contains $osVal) {
                $cmbMinOS.SelectedItem = $osVal
            } else {
                $cmbMinOS.SelectedIndex = 0
            }

            # Return codes
            if ($t.ReturnCodes -and @($t.ReturnCodes).Count -gt 0) {
                $script:tplReturnCodes = @($t.ReturnCodes | ForEach-Object {
                    if ($_ -is [PSCustomObject]) {
                        @{ ReturnCode = [int]$_.ReturnCode; Type = [string]$_.Type }
                    } else { $_ }
                })
            } else {
                $script:tplReturnCodes = @($script:defaultReturnCodes)
            }
            Update-RCStatus

            # Assignment
            $asg = $t.Assignment
            if ($asg) {
                switch ($asg.Type) {
                    'AllUsers' { $rdoAsgAllUsr.IsChecked = $true }
                    'Group'    { $rdoAsgGroup.IsChecked  = $true }
                    'None'     { $rdoAsgNone.IsChecked   = $true }
                    default    { $rdoAsgAllDev.IsChecked = $true }
                }
                switch ($asg.Intent) {
                    'available' { $rdoIntAvailable.IsChecked = $true }
                    'uninstall' { $rdoIntUninstall.IsChecked = $true }
                    default     { $rdoIntRequired.IsChecked  = $true }
                }
                switch ($asg.Notification) {
                    'showReboot' { $rdoNotifReboot.IsChecked = $true }
                    'hideAll'    { $rdoNotifHide.IsChecked   = $true }
                    default      { $rdoNotifAll.IsChecked    = $true }
                }

                # Groups — support new Groups array and old GroupName/GroupID scalar
                $script:tplGroups.Clear()
                $groups = @()
                if ($asg.Groups -and @($asg.Groups).Count -gt 0) {
                    $groups = @($asg.Groups)
                } elseif ($asg.GroupID) {
                    $groups = @(@{ GroupName = $asg.GroupName ?? ''; GroupID = $asg.GroupID })
                }
                foreach ($g in $groups) {
                    $gName = if ($g -is [hashtable]) { $g.GroupName ?? $g.DisplayName ?? '' } else { $g.GroupName ?? $g.DisplayName ?? '' }
                    $gID   = if ($g -is [hashtable]) { $g.GroupID   ?? $g.ID ?? '' }           else { $g.GroupID   ?? $g.ID ?? '' }
                    if ($gID) {
                        $script:tplGroups.Add([PSCustomObject]@{ DisplayName = $gName; ID = $gID }) | Out-Null
                    }
                }

                # Filter
                $fid = $asg.FilterID ?? ''
                $txtFilterID.Text = $fid
                if ($fid) {
                    $matched = $false
                    for ($fi = 1; $fi -lt $cmbFilter.Items.Count; $fi++) {
                        $item = $cmbFilter.Items[$fi]
                        if ($item -is [System.Windows.Controls.ComboBoxItem] -and $item.Tag -eq $fid) {
                            $cmbFilter.SelectedIndex = $fi; $matched = $true; break
                        }
                    }
                    if (-not $matched) { $cmbFilter.SelectedIndex = 0 }
                } else {
                    $cmbFilter.SelectedIndex = 0
                }

                if ($asg.FilterIntent -eq 'exclude') { $rdoFilterExclude.IsChecked = $true }
                else                                  { $rdoFilterInclude.IsChecked = $true }

                $panelGroup.Visibility = if ($asg.Type -eq 'Group') {
                    [System.Windows.Visibility]::Visible
                } else {
                    [System.Windows.Visibility]::Collapsed
                }
            } else {
                $rdoAsgAllDev.IsChecked = $true
                $script:tplGroups.Clear()
                $panelGroup.Visibility  = [System.Windows.Visibility]::Collapsed
            }

            $txtTplStatus.Text = "Loaded: $Name"
        }
        catch {
            $txtTplStatus.Text = "Error loading template: $_"
        }
    }

    function Get-FormData {
        $asgType = if     ($rdoAsgAllDev.IsChecked) { 'AllDevices' }
                   elseif ($rdoAsgAllUsr.IsChecked)  { 'AllUsers'   }
                   elseif ($rdoAsgGroup.IsChecked)   { 'Group'      }
                   else                               { 'None'       }

        $intent = if     ($rdoIntAvailable.IsChecked) { 'available' }
                  elseif ($rdoIntUninstall.IsChecked)  { 'uninstall' }
                  else                                  { 'required'  }

        $notification = if     ($rdoNotifReboot.IsChecked) { 'showReboot' }
                        elseif ($rdoNotifHide.IsChecked)    { 'hideAll'    }
                        else                                 { 'showAll'    }

        $context = if ($rdoCtxUser.IsChecked) { 'user' } else { 'system' }

        $restart = if     ($rdoRstReturnCode.IsChecked) { 'basedOnReturnCode' }
                   elseif ($rdoRstForce.IsChecked)       { 'force'             }
                   elseif ($rdoRstAllow.IsChecked)       { 'allow'             }
                   else                                   { 'suppress'          }

        $arch  = Get-ArchValue

        $minOS = $cmbMinOS.SelectedItem -as [string]
        if ($minOS -eq '(Any / Not set)') { $minOS = '' }

        $filterID = $txtFilterID.Text.Trim()
        $filterName = ''
        $selFilter = $cmbFilter.SelectedItem
        if ($selFilter -is [System.Windows.Controls.ComboBoxItem] -and $selFilter.Tag -eq $filterID) {
            $filterName = $selFilter.Content -as [string]
        }
        $filterIntent = if ($filterID -and $rdoFilterExclude.IsChecked) { 'exclude' } elseif ($filterID) { 'include' } else { $null }

        $timeoutVal = 60
        try { $timeoutVal = [int]($txtTplTimeout.Text -replace '\D','') } catch {}
        if ($timeoutVal -le 0) { $timeoutVal = 60 }

        # Build groups array (always array even for single)
        $groupsArr = @($script:tplGroups | ForEach-Object {
            @{ GroupName = $_.DisplayName; GroupID = $_.ID }
        })

        return [ordered]@{
            TemplateName                     = $txtTplName.Text.Trim()
            Description                      = $txtTplDesc.Text.Trim()
            Notes                            = $txtTplNotes.Text.Trim()
            Owner                            = $txtTplOwner.Text.Trim()
            IsPSADT                          = [bool]$chkIsPSADT.IsChecked
            InstallCommandLine               = $txtTplInstall.Text.Trim()
            UninstallCommandLine             = $txtTplUninstall.Text.Trim()
            InstallExperience                = $context
            RestartBehavior                  = $restart
            Architecture                     = $arch
            MinimumSupportedWindowsRelease   = $minOS
            MaximumInstallationTimeInMinutes = $timeoutVal
            AllowAvailableUninstall          = [bool]$chkAllowUninst.IsChecked
            ReturnCodes                      = $script:tplReturnCodes
            Assignment = [ordered]@{
                Type         = $asgType
                Intent       = $intent
                Notification = $notification
                Groups       = if ($asgType -eq 'Group') { $groupsArr } else { @() }
                FilterID     = if ($filterID) { $filterID } else { $null }
                FilterName   = if ($filterID -and $filterName) { $filterName } else { $null }
                FilterIntent = $filterIntent
            }
        }
    }

    function Save-CurrentTemplate {
        $data = Get-FormData
        $name = $data.TemplateName

        if (-not $name) {
            [System.Windows.MessageBox]::Show('Please enter a Template Name.', 'Name Required', 'OK', 'Warning')
            return $false
        }
        if ($name -match '[\\/:*?"<>|]') {
            [System.Windows.MessageBox]::Show(
                "Template Name contains invalid characters.`nAvoid: \ / : * ? `" < > |",
                'Invalid Name', 'OK', 'Warning')
            return $false
        }

        $filePath = Join-Path $TemplateFolder "$name.json"
        try {
            $data | ConvertTo-Json -Depth 10 | Set-Content $filePath -Encoding UTF8
            $txtTplStatus.Text = "Saved: $name.json  ($(Get-Date -Format 'HH:mm:ss'))"
            Refresh-TplList
            $tplList.SelectedItem = $name
            return $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Could not save template:`n$_", 'Save Error', 'OK', 'Error')
            return $false
        }
    }

    #endregion

    # ─────────────────────────────────────────────────────────────────────────
    #region Event handlers
    # ─────────────────────────────────────────────────────────────────────────

    # PSADT toggle
    $chkIsPSADT.Add_Checked({   Apply-PsadtState -IsPSADT $true  })
    $chkIsPSADT.Add_Unchecked({ Apply-PsadtState -IsPSADT $false })

    # Group panel visibility
    $rdoAsgGroup.Add_Checked({   $panelGroup.Visibility = [System.Windows.Visibility]::Visible   })
    $rdoAsgAllDev.Add_Checked({ $panelGroup.Visibility = [System.Windows.Visibility]::Collapsed })
    $rdoAsgAllUsr.Add_Checked({ $panelGroup.Visibility = [System.Windows.Visibility]::Collapsed })
    $rdoAsgNone.Add_Checked({   $panelGroup.Visibility = [System.Windows.Visibility]::Collapsed })

    # Search / Add Groups button
    $btnSearchGroups.Add_Click({
        $already = @($script:tplGroups | ForEach-Object {
            @{ GroupName = $_.DisplayName; GroupID = $_.ID }
        })
        $picked = Show-GroupPicker -AlreadySelected $already
        if ($null -ne $picked) {
            $script:tplGroups.Clear()
            foreach ($g in $picked) {
                $script:tplGroups.Add([PSCustomObject]@{ DisplayName = $g.GroupName; ID = $g.GroupID }) | Out-Null
            }
        }
    })

    # Remove selected group
    $btnRemoveGroup.Add_Click({
        $sel = $lstGroups.SelectedItem
        if (-not $sel) { return }
        $script:tplGroups.Remove($sel) | Out-Null
    })

    # Return Codes button
    $btnReturnCodes.Add_Click({
        $result = Show-ReturnCodeEditor -CurrentCodes $script:tplReturnCodes
        if ($null -ne $result) {
            $script:tplReturnCodes = @($result)
            Update-RCStatus
        }
    })

    # List selection → load template into form
    $tplList.Add_SelectionChanged({
        $sel = $tplList.SelectedItem -as [string]
        if ($sel) { Load-Template -Name $sel }
    })

    # New
    $btnNew.Add_Click({
        $tplList.SelectedIndex = -1
        Clear-Form
        $txtTplName.Focus() | Out-Null
        $txtTplStatus.Text = 'New template — fill in the fields and click Save'
    })

    # Duplicate
    $btnDuplicate.Add_Click({
        $sel = $tplList.SelectedItem -as [string]
        if (-not $sel) {
            [System.Windows.MessageBox]::Show('Select a template to duplicate.', 'Duplicate', 'OK', 'Information')
            return
        }
        $data = Get-FormData
        $newName = "$($data.TemplateName)-Copy"
        $txtTplName.Text = $newName
        $tplList.SelectedIndex = -1
        $txtTplStatus.Text = "Duplicated from '$sel' — edit the name then click Save"
    })

    # Delete
    $btnDelete.Add_Click({
        $sel = $tplList.SelectedItem -as [string]
        if (-not $sel) {
            [System.Windows.MessageBox]::Show('Select a template to delete.', 'Delete', 'OK', 'Information')
            return
        }
        $confirm = [System.Windows.MessageBox]::Show(
            "Permanently delete '$sel'?`n`nThis cannot be undone.",
            'Confirm Delete', 'YesNo', 'Warning')
        if ($confirm -ne 'Yes') { return }

        $path = Join-Path $TemplateFolder "$sel.json"
        try {
            Remove-Item $path -Force
            Clear-Form
            Refresh-TplList
            $txtTplStatus.Text = "Deleted: $sel"
        }
        catch {
            [System.Windows.MessageBox]::Show("Could not delete template:`n$_", 'Error', 'OK', 'Error')
        }
    })

    # Save
    $btnSaveTpl.Add_Click({ Save-CurrentTemplate | Out-Null })

    # Close
    $btnCloseTpl.Add_Click({ $window.Close() })

    #endregion

    # ── Initial load ──────────────────────────────────────────────────────────
    Update-RCStatus
    Refresh-TplList
    if ($tplList.Items.Count -gt 0) {
        $tplList.SelectedIndex = 0
    } else {
        $txtTplStatus.Text = 'No templates found — click New to create one'
    }

    $window.ShowDialog() | Out-Null
}
