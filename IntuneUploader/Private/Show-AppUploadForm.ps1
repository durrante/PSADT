<#
.SYNOPSIS
    WPF form for configuring and uploading a single Win32 application to Intune.

.DESCRIPTION
    Tabbed GUI:
      1. Application  - Name, version, publisher, owner, description, notes, internal note,
                        information URL, privacy URL, categories (multi-select from Intune)
      2. Commands     - Install/uninstall (auto-locked for PSADT), experience, restart
      3. Detection    - Script / Registry / MSI / File with dynamic sub-panels
      4. Requirements - Architecture (checkboxes), minimum OS, multiple additional rules
                        (script, registry, or file — any number)
      5. Assignment   - All Devices / All Users / Group / None, intent, notification,
                        include/exclude filter from Intune

    Returns a fully populated AppConfig hashtable on OK, $null on cancel.
#>

function Show-AppUploadForm {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$TemplateFolder  = '',
        [string]$DefaultOutput   = '',
        [string]$DefaultTemplate = 'PSADT-Default',
        [PSCustomObject]$Config  = $null,

        # Pre-loaded from Intune by Show-MainWindow (can be empty arrays)
        [string[]]$AvailableCategories = @(),
        [object[]]$AvailableFilters    = @(),

        # When opening from the Bulk Manager to edit an existing row, pass the AppConfig
        # hashtable here and the form will pre-fill all fields.
        [hashtable]$PrePopulate        = @{},

        # Label for the primary action button (changes context: "Package and Upload" vs "Add to Queue")
        [string]$SubmitLabel           = 'Package and Upload'
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms | Out-Null

    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Upload Application to Intune"
    Width="780" Height="820"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanMinimize">

  <Window.Resources>
    <Style TargetType="Label">
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Padding" Value="0,0,6,0"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Padding" Value="4,3"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Padding" Value="4,3"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="12,5"/>
      <Setter Property="MinWidth" Value="80"/>
    </Style>
    <Style x:Key="BrowseBtn" TargetType="Button">
      <Setter Property="Padding" Value="8,3"/>
      <Setter Property="MinWidth" Value="0"/>
      <Setter Property="Content" Value="Browse..."/>
    </Style>
    <Style x:Key="SectionHeader" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#4A2B8F"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Margin" Value="0,10,0,4"/>
    </Style>
    <Style x:Key="FieldRow" TargetType="Grid">
      <Setter Property="Margin" Value="0,3"/>
    </Style>
    <Style x:Key="RulePanel" TargetType="Border">
      <Setter Property="BorderBrush" Value="#4A2B8F"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background" Value="#F0EBF9"/>
      <Setter Property="CornerRadius" Value="3"/>
      <Setter Property="Padding" Value="10"/>
      <Setter Property="Margin" Value="0,6,0,4"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="52"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- HEADER -->
    <Border Grid.Row="0">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
          <GradientStop Color="#0693E3" Offset="0"/>
          <GradientStop Color="#9B51E0" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0">
        <TextBlock Text="Upload Application" FontSize="18" FontWeight="Light" Foreground="White" VerticalAlignment="Center"/>
      </StackPanel>
    </Border>

    <!-- SOURCE FOLDER -->
    <GroupBox Header="Source Folder" Grid.Row="1" Margin="10,8,10,0" Padding="8,6">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name="TxtSource" Grid.Column="0" IsReadOnly="True" Background="#F9F9F9"/>
        <Button x:Name="BtnBrowseSource" Grid.Column="1" Margin="6,0,0,0" Style="{StaticResource BrowseBtn}"/>
        <Button x:Name="BtnClearSource"  Grid.Column="2" Margin="4,0,0,0" Content="Clear" Padding="8,3" MinWidth="0"/>
      </Grid>
    </GroupBox>

    <!-- PSADT BANNER -->
    <Border x:Name="PsadtBanner" Grid.Row="2" Margin="10,6,10,0"
            Background="#EDE7F6" BorderBrush="#4A2B8F" BorderThickness="1"
            CornerRadius="3" Padding="10,7" Visibility="Collapsed">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="&#x2714;" Foreground="#4A2B8F" FontSize="14" Margin="0,0,8,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="TxtPsadtInfo" FontWeight="SemiBold" Foreground="#4A2B8F" VerticalAlignment="Center"
                   Text="PSADT v4 detected — metadata auto-filled."/>
      </StackPanel>
    </Border>

    <!-- TABS -->
    <TabControl Grid.Row="3" Margin="10,8,10,0">

      <!-- ═══ TAB 1: APPLICATION ═══ -->
      <TabItem Header="Application">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8">
          <StackPanel>
            <TextBlock Style="{StaticResource SectionHeader}" Text="Application Details"/>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Display Name *" Grid.Column="0"/>
              <TextBox x:Name="TxtDisplayName" Grid.Column="1"/>
            </Grid>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="90"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Version" Grid.Column="0"/>
              <TextBox x:Name="TxtVersion" Grid.Column="1"/>
              <Label Content="Publisher" Grid.Column="2" Padding="12,0,6,0"/>
              <TextBox x:Name="TxtPublisher" Grid.Column="3"/>
            </Grid>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Owner" Grid.Column="0" ToolTip="Maps to the Owner field in Intune. Auto-filled from PSADT script author."/>
              <TextBox x:Name="TxtOwner" Grid.Column="1"/>
            </Grid>

            <TextBlock Style="{StaticResource SectionHeader}" Text="Notes"/>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Description" Grid.Column="0" VerticalAlignment="Top" Padding="0,4,6,0"/>
              <TextBox x:Name="TxtDescription" Grid.Column="1" Height="50"
                       TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"
                       ToolTip="Shown to end users in Company Portal"/>
            </Grid>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Notes" Grid.Column="0" VerticalAlignment="Top" Padding="0,4,6,0"/>
              <TextBox x:Name="TxtNotes" Grid.Column="1" Height="50"
                       TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"
                       ToolTip="Admin-facing notes in Intune portal"/>
            </Grid>

            <TextBlock Style="{StaticResource SectionHeader}" Text="URLs"/>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Information URL" Grid.Column="0"/>
              <TextBox x:Name="TxtInfoURL" Grid.Column="1" ToolTip="e.g. https://docs.vendor.com/product"/>
            </Grid>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Privacy URL" Grid.Column="0"/>
              <TextBox x:Name="TxtPrivacyURL" Grid.Column="1" ToolTip="e.g. https://vendor.com/privacy"/>
            </Grid>

            <TextBlock Style="{StaticResource SectionHeader}" Text="Categories"/>
            <TextBlock Text="Select one or more categories (populated from your Intune tenant)."
                       Foreground="#666" FontSize="11" Margin="0,0,0,4"/>
            <Border BorderBrush="#CCC" BorderThickness="1" CornerRadius="2" Height="90">
              <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="PanelCategories" Margin="6,4">
                  <TextBlock x:Name="TxtCategoryPlaceholder"
                             Text="(No categories available — connect to Intune first)"
                             Foreground="Gray" FontSize="11"/>
                </StackPanel>
              </ScrollViewer>
            </Border>

          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ═══ TAB 2: COMMANDS ═══ -->
      <TabItem Header="Commands">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8">
          <StackPanel>
            <TextBlock Style="{StaticResource SectionHeader}" Text="Install / Uninstall Commands"/>

            <Border x:Name="PsadtCmdNote" Background="#FFF8E1" BorderBrush="#FFA000"
                    BorderThickness="1" CornerRadius="3" Padding="8,6" Margin="0,0,0,8"
                    Visibility="Collapsed">
              <TextBlock TextWrapping="Wrap" Foreground="#6D4C00">
                <Run FontWeight="Bold">PSADT package:</Run>
                <Run> Commands are pre-set from the template and cannot be changed here.</Run>
              </TextBlock>
            </Border>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Install *" Grid.Column="0"/>
              <TextBox x:Name="TxtInstallCmd" Grid.Column="1"/>
            </Grid>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Uninstall *" Grid.Column="0"/>
              <TextBox x:Name="TxtUninstallCmd" Grid.Column="1"/>
            </Grid>

            <TextBlock Style="{StaticResource SectionHeader}" Text="Install Experience" Margin="0,14,0,4"/>
            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="160"/>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="180"/>
              </Grid.ColumnDefinitions>
              <Label Content="Context" Grid.Column="0"/>
              <ComboBox x:Name="CmbInstallExp" Grid.Column="1" SelectedIndex="0">
                <ComboBoxItem Content="system"/>
                <ComboBoxItem Content="user"/>
              </ComboBox>
              <Label Content="Restart" Grid.Column="2" Padding="12,0,6,0"/>
              <ComboBox x:Name="CmbRestart" Grid.Column="3" SelectedIndex="0">
                <ComboBoxItem Content="No specific action"                          Tag="suppress"/>
                <ComboBoxItem Content="App install may force a device restart"      Tag="allow"/>
                <ComboBoxItem Content="Determine behavior based on return codes"    Tag="basedOnReturnCode"/>
                <ComboBoxItem Content="Intune will force a mandatory device restart" Tag="force"/>
              </ComboBox>
            </Grid>

            <Separator Margin="0,14,0,10"/>
            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Style="{StaticResource SectionHeader}" Margin="0,0,0,2" Text="Return Codes"/>
                <TextBlock x:Name="TxtRCStatus" Foreground="#666" FontSize="11"
                           Text="5 codes (defaults)"/>
              </StackPanel>
              <Button x:Name="BtnReturnCodes" Grid.Column="1" Content="Edit Return Codes..."
                      Padding="10,5" VerticalAlignment="Center"/>
            </Grid>

          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ═══ TAB 3: DETECTION ═══ -->
      <TabItem Header="Detection">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8">
          <StackPanel>
            <TextBlock Style="{StaticResource SectionHeader}" Text="Detection Method"/>

            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
              <RadioButton x:Name="RdoDetectScript"   Content="PowerShell Script"  Margin="0,0,16,0" IsChecked="True"/>
              <RadioButton x:Name="RdoDetectRegistry" Content="Registry Key"       Margin="0,0,16,0"/>
              <RadioButton x:Name="RdoDetectMSI"      Content="MSI Product Code"   Margin="0,0,16,0"/>
              <RadioButton x:Name="RdoDetectFile"     Content="File / Folder"/>
            </StackPanel>

            <!-- Script Panel -->
            <StackPanel x:Name="PanelDetectScript">
              <Grid Style="{StaticResource FieldRow}">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Label Content="Script file *" Grid.Column="0"/>
                <TextBox x:Name="TxtDetectScript" Grid.Column="1" IsReadOnly="True" Background="#F9F9F9"/>
                <Button x:Name="BtnBrowseDetectScript" Grid.Column="2" Margin="6,0,0,0" Style="{StaticResource BrowseBtn}"/>
              </Grid>
              <StackPanel Orientation="Horizontal" Margin="130,6,0,0">
                <CheckBox x:Name="ChkDetectSignature" Content="Enforce signature check" Margin="0,0,20,0"/>
                <CheckBox x:Name="ChkDetect32Bit"     Content="Run as 32-bit"/>
              </StackPanel>
            </StackPanel>

            <!-- Registry Panel -->
            <StackPanel x:Name="PanelDetectRegistry" Visibility="Collapsed">
              <Grid Style="{StaticResource FieldRow}">
                <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Label Content="Registry key *" Grid.Column="0"/>
                <TextBox x:Name="TxtRegKey" Grid.Column="1" ToolTip="e.g. HKLM:\SOFTWARE\7-Zip"/>
              </Grid>
              <Grid Style="{StaticResource FieldRow}">
                <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Label Content="Value name" Grid.Column="0"/>
                <TextBox x:Name="TxtRegValue" Grid.Column="1" ToolTip="Leave blank to check key exists"/>
              </Grid>
              <Grid Style="{StaticResource FieldRow}">
                <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="160"/></Grid.ColumnDefinitions>
                <Label Content="Detection type" Grid.Column="0"/>
                <ComboBox x:Name="CmbRegType" Grid.Column="1" SelectedIndex="0">
                  <ComboBoxItem Content="exists"/>
                  <ComboBoxItem Content="doesNotExist"/>
                  <ComboBoxItem Content="string"/>
                  <ComboBoxItem Content="integer"/>
                  <ComboBoxItem Content="version"/>
                  <ComboBoxItem Content="hexadecimal"/>
                </ComboBox>
              </Grid>
              <Grid x:Name="PanelRegComparison" Style="{StaticResource FieldRow}" Visibility="Collapsed">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/>
                  <ColumnDefinition Width="160"/>
                  <ColumnDefinition Width="80"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Label Content="Operator" Grid.Column="0"/>
                <ComboBox x:Name="CmbRegOperator" Grid.Column="1" SelectedIndex="0">
                  <ComboBoxItem Content="equal"/>
                  <ComboBoxItem Content="notEqual"/>
                  <ComboBoxItem Content="greaterThan"/>
                  <ComboBoxItem Content="greaterThanOrEqual"/>
                  <ComboBoxItem Content="lessThan"/>
                  <ComboBoxItem Content="lessThanOrEqual"/>
                </ComboBox>
                <Label Content="Value" Grid.Column="2" Padding="12,0,6,0"/>
                <TextBox x:Name="TxtRegCompValue" Grid.Column="3"/>
              </Grid>
              <CheckBox x:Name="ChkReg32Bit" Content="Check 32-bit registry on 64-bit system" Margin="130,6,0,0"/>
            </StackPanel>

            <!-- MSI Panel -->
            <StackPanel x:Name="PanelDetectMSI" Visibility="Collapsed">
              <Grid Style="{StaticResource FieldRow}">
                <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Label Content="Product code *" Grid.Column="0"/>
                <TextBox x:Name="TxtMsiCode" Grid.Column="1" ToolTip="e.g. {12345678-1234-1234-1234-123456789ABC}"/>
              </Grid>
              <CheckBox x:Name="ChkMsiVersion" Content="Also check product version" Margin="130,6,0,6"/>
              <Grid x:Name="PanelMsiVersion" Style="{StaticResource FieldRow}" Visibility="Collapsed">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/>
                  <ColumnDefinition Width="160"/>
                  <ColumnDefinition Width="80"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Label Content="Operator" Grid.Column="0"/>
                <ComboBox x:Name="CmbMsiOperator" Grid.Column="1" SelectedIndex="2">
                  <ComboBoxItem Content="equal"/>
                  <ComboBoxItem Content="notEqual"/>
                  <ComboBoxItem Content="greaterThan"/>
                  <ComboBoxItem Content="greaterThanOrEqual"/>
                  <ComboBoxItem Content="lessThan"/>
                  <ComboBoxItem Content="lessThanOrEqual"/>
                </ComboBox>
                <Label Content="Version" Grid.Column="2" Padding="12,0,6,0"/>
                <TextBox x:Name="TxtMsiVersion" Grid.Column="3"/>
              </Grid>
            </StackPanel>

            <!-- File Panel -->
            <StackPanel x:Name="PanelDetectFile" Visibility="Collapsed">
              <Grid Style="{StaticResource FieldRow}">
                <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Label Content="Folder path *" Grid.Column="0"/>
                <TextBox x:Name="TxtFilePath" Grid.Column="1" ToolTip="e.g. C:\Program Files\7-Zip"/>
              </Grid>
              <Grid Style="{StaticResource FieldRow}">
                <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Label Content="File / folder name *" Grid.Column="0"/>
                <TextBox x:Name="TxtFileName" Grid.Column="1" ToolTip="e.g. 7z.exe"/>
              </Grid>
              <Grid Style="{StaticResource FieldRow}">
                <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="160"/></Grid.ColumnDefinitions>
                <Label Content="Detection type" Grid.Column="0"/>
                <ComboBox x:Name="CmbFileType" Grid.Column="1" SelectedIndex="0">
                  <ComboBoxItem Content="exists"/>
                  <ComboBoxItem Content="doesNotExist"/>
                  <ComboBoxItem Content="modifiedDate"/>
                  <ComboBoxItem Content="createdDate"/>
                  <ComboBoxItem Content="version"/>
                  <ComboBoxItem Content="sizeInMBGreaterThan"/>
                </ComboBox>
              </Grid>
              <Grid x:Name="PanelFileComparison" Style="{StaticResource FieldRow}" Visibility="Collapsed">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/>
                  <ColumnDefinition Width="160"/>
                  <ColumnDefinition Width="80"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Label Content="Operator" Grid.Column="0"/>
                <ComboBox x:Name="CmbFileOperator" Grid.Column="1" SelectedIndex="2">
                  <ComboBoxItem Content="equal"/>
                  <ComboBoxItem Content="notEqual"/>
                  <ComboBoxItem Content="greaterThan"/>
                  <ComboBoxItem Content="greaterThanOrEqual"/>
                  <ComboBoxItem Content="lessThan"/>
                  <ComboBoxItem Content="lessThanOrEqual"/>
                </ComboBox>
                <Label Content="Value" Grid.Column="2" Padding="12,0,6,0"/>
                <TextBox x:Name="TxtFileValue" Grid.Column="3"/>
              </Grid>
              <CheckBox x:Name="ChkFile32Bit" Content="Check 32-bit location on 64-bit system" Margin="130,6,0,0"/>
            </StackPanel>

          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ═══ TAB 4: REQUIREMENTS ═══ -->
      <TabItem Header="Requirements">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8">
          <StackPanel>

            <TextBlock Style="{StaticResource SectionHeader}" Text="Operating System"/>

            <!-- Architecture checkboxes -->
            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="130"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Architecture" Grid.Column="0"/>
              <CheckBox x:Name="ChkArchX64"   Content="x64"   Grid.Column="1" Margin="0,0,16,0" IsChecked="True"/>
              <CheckBox x:Name="ChkArchX86"   Content="x86"   Grid.Column="2" Margin="0,0,16,0"/>
              <CheckBox x:Name="ChkArchArm64" Content="arm64" Grid.Column="3" Margin="0,0,16,0"/>
              <TextBlock x:Name="TxtArchResult" Grid.Column="4"
                         Text="→ x64" Foreground="#666" FontSize="11" VerticalAlignment="Center"/>
            </Grid>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="130"/>
                <ColumnDefinition Width="200"/>
              </Grid.ColumnDefinitions>
              <Label Content="Minimum Windows" Grid.Column="0"/>
              <ComboBox x:Name="CmbMinOS" Grid.Column="1" SelectedIndex="7">
                <ComboBoxItem Content="W10_1607"/>
                <ComboBoxItem Content="W10_1703"/>
                <ComboBoxItem Content="W10_1709"/>
                <ComboBoxItem Content="W10_1803"/>
                <ComboBoxItem Content="W10_1809"/>
                <ComboBoxItem Content="W10_1903"/>
                <ComboBoxItem Content="W10_1909"/>
                <ComboBoxItem Content="W10_2004"/>
                <ComboBoxItem Content="W10_20H2"/>
                <ComboBoxItem Content="W10_21H1"/>
                <ComboBoxItem Content="W10_21H2"/>
                <ComboBoxItem Content="W10_22H2"/>
                <ComboBoxItem Content="W11_21H2"/>
                <ComboBoxItem Content="W11_22H2"/>
                <ComboBoxItem Content="W11_23H2"/>
                <ComboBoxItem Content="W11_24H2"/>
              </ComboBox>
            </Grid>

            <!-- Additional Requirement Rules -->
            <TextBlock Style="{StaticResource SectionHeader}" Text="Additional Requirement Rules"/>
            <TextBlock Text="Rules are evaluated in addition to the OS requirement above. All rules must pass."
                       Foreground="#666" FontSize="11" Margin="0,0,0,6"/>

            <ListBox x:Name="LstReqRules" Height="110" Margin="0,0,0,6"
                     HorizontalContentAlignment="Stretch"
                     ScrollViewer.HorizontalScrollBarVisibility="Auto"
                     FontFamily="Consolas" FontSize="11"/>

            <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
              <Button x:Name="BtnAddReqRule"    Content="+ Add Rule"       Padding="10,4" Margin="0,0,8,0" MinWidth="0"/>
              <Button x:Name="BtnRemoveReqRule" Content="Remove Selected"  Padding="10,4" MinWidth="0"/>
            </StackPanel>

            <!-- === ADD RULE PANEL === -->
            <Border x:Name="PanelAddReqRule" Style="{StaticResource RulePanel}" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="Configure Additional Requirement Rule"
                           FontWeight="SemiBold" Margin="0,0,0,8"/>

                <!-- Rule type selection -->
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                  <Label Content="Rule type" Width="110" Padding="0,0,6,0"/>
                  <RadioButton x:Name="RdoReqTypeScript"   Content="PowerShell Script" IsChecked="True" Margin="0,0,16,0"/>
                  <RadioButton x:Name="RdoReqTypeRegistry" Content="Registry"          Margin="0,0,16,0"/>
                  <RadioButton x:Name="RdoReqTypeFile"     Content="File"              Margin="0,0,16,0"/>
                </StackPanel>

                <!-- Script sub-panel -->
                <StackPanel x:Name="PanelAddReqScript">
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="130"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Label Content="Script file *" Grid.Column="0"/>
                    <TextBox x:Name="TxtAddReqScript" Grid.Column="1" IsReadOnly="True" Background="#F9F9F9"/>
                    <Button x:Name="BtnAddReqScriptBrowse" Grid.Column="2" Margin="6,0,0,0" Style="{StaticResource BrowseBtn}"/>
                  </Grid>
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="130"/>
                      <ColumnDefinition Width="160"/>
                      <ColumnDefinition Width="110"/>
                      <ColumnDefinition Width="160"/>
                    </Grid.ColumnDefinitions>
                    <Label Content="Output data type" Grid.Column="0"/>
                    <ComboBox x:Name="CmbAddReqOutputType" Grid.Column="1" SelectedIndex="0">
                      <ComboBoxItem Content="string"/>
                      <ComboBoxItem Content="integer"/>
                      <ComboBoxItem Content="float"/>
                      <ComboBoxItem Content="version"/>
                      <ComboBoxItem Content="dateTime"/>
                      <ComboBoxItem Content="boolean"/>
                    </ComboBox>
                    <Label Content="Operator" Grid.Column="2" Padding="12,0,6,0"/>
                    <ComboBox x:Name="CmbAddReqScriptOp" Grid.Column="3" SelectedIndex="0">
                      <ComboBoxItem Content="equal"/>
                      <ComboBoxItem Content="notEqual"/>
                      <ComboBoxItem Content="greaterThan"/>
                      <ComboBoxItem Content="greaterThanOrEqual"/>
                      <ComboBoxItem Content="lessThan"/>
                      <ComboBoxItem Content="lessThanOrEqual"/>
                    </ComboBox>
                  </Grid>
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="130"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Label Content="Expected value" Grid.Column="0"/>
                    <TextBox x:Name="TxtAddReqScriptValue" Grid.Column="1"/>
                  </Grid>
                  <StackPanel Orientation="Horizontal" Margin="130,4,0,0">
                    <CheckBox x:Name="ChkAddReqSignature" Content="Enforce signature check" Margin="0,0,16,0"/>
                    <CheckBox x:Name="ChkAddReq32Bit"     Content="Run as 32-bit"/>
                  </StackPanel>
                </StackPanel>

                <!-- Registry sub-panel -->
                <StackPanel x:Name="PanelAddReqRegistry" Visibility="Collapsed">
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Label Content="Registry key *" Grid.Column="0"/>
                    <TextBox x:Name="TxtAddReqRegKey" Grid.Column="1" ToolTip="e.g. HKLM:\SOFTWARE\App"/>
                  </Grid>
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Label Content="Value name" Grid.Column="0"/>
                    <TextBox x:Name="TxtAddReqRegValName" Grid.Column="1" ToolTip="Leave blank to check key exists"/>
                  </Grid>
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="130"/>
                      <ColumnDefinition Width="160"/>
                      <ColumnDefinition Width="110"/>
                      <ColumnDefinition Width="160"/>
                    </Grid.ColumnDefinitions>
                    <Label Content="Detection type" Grid.Column="0"/>
                    <ComboBox x:Name="CmbAddReqRegType" Grid.Column="1" SelectedIndex="0">
                      <ComboBoxItem Content="exists"/>
                      <ComboBoxItem Content="doesNotExist"/>
                      <ComboBoxItem Content="string"/>
                      <ComboBoxItem Content="integer"/>
                      <ComboBoxItem Content="version"/>
                    </ComboBox>
                    <Label Content="Operator" Grid.Column="2" Padding="12,0,6,0"/>
                    <ComboBox x:Name="CmbAddReqRegOp" Grid.Column="3" SelectedIndex="0">
                      <ComboBoxItem Content="equal"/>
                      <ComboBoxItem Content="notEqual"/>
                      <ComboBoxItem Content="greaterThan"/>
                      <ComboBoxItem Content="greaterThanOrEqual"/>
                      <ComboBoxItem Content="lessThan"/>
                      <ComboBoxItem Content="lessThanOrEqual"/>
                    </ComboBox>
                  </Grid>
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Label Content="Expected value" Grid.Column="0"/>
                    <TextBox x:Name="TxtAddReqRegValue" Grid.Column="1"/>
                  </Grid>
                  <CheckBox x:Name="ChkAddReqReg32Bit" Content="Check 32-bit registry on 64-bit system" Margin="130,4,0,0"/>
                </StackPanel>

                <!-- File sub-panel -->
                <StackPanel x:Name="PanelAddReqFile" Visibility="Collapsed">
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Label Content="Folder path *" Grid.Column="0"/>
                    <TextBox x:Name="TxtAddReqFilePath" Grid.Column="1" ToolTip="e.g. C:\Program Files\App"/>
                  </Grid>
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Label Content="File / folder name *" Grid.Column="0"/>
                    <TextBox x:Name="TxtAddReqFileName" Grid.Column="1" ToolTip="e.g. app.exe"/>
                  </Grid>
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="130"/>
                      <ColumnDefinition Width="160"/>
                      <ColumnDefinition Width="110"/>
                      <ColumnDefinition Width="160"/>
                    </Grid.ColumnDefinitions>
                    <Label Content="Detection type" Grid.Column="0"/>
                    <ComboBox x:Name="CmbAddReqFileType" Grid.Column="1" SelectedIndex="0">
                      <ComboBoxItem Content="exists"/>
                      <ComboBoxItem Content="doesNotExist"/>
                      <ComboBoxItem Content="version"/>
                      <ComboBoxItem Content="sizeInMBGreaterThan"/>
                    </ComboBox>
                    <Label Content="Operator" Grid.Column="2" Padding="12,0,6,0"/>
                    <ComboBox x:Name="CmbAddReqFileOp" Grid.Column="3" SelectedIndex="2">
                      <ComboBoxItem Content="equal"/>
                      <ComboBoxItem Content="notEqual"/>
                      <ComboBoxItem Content="greaterThan"/>
                      <ComboBoxItem Content="greaterThanOrEqual"/>
                      <ComboBoxItem Content="lessThan"/>
                      <ComboBoxItem Content="lessThanOrEqual"/>
                    </ComboBox>
                  </Grid>
                  <Grid Style="{StaticResource FieldRow}">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Label Content="Expected value" Grid.Column="0"/>
                    <TextBox x:Name="TxtAddReqFileValue" Grid.Column="1"/>
                  </Grid>
                  <CheckBox x:Name="ChkAddReqFile32Bit" Content="Check 32-bit location on 64-bit system" Margin="130,4,0,0"/>
                </StackPanel>

                <!-- Confirm / Cancel -->
                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                  <Button x:Name="BtnReqAddConfirm" Content="Add to List"
                          Background="#4A2B8F" Foreground="White"
                          Padding="12,5" Margin="0,0,8,0" MinWidth="0"/>
                  <Button x:Name="BtnReqAddCancel" Content="Cancel" Padding="12,5" MinWidth="0"/>
                </StackPanel>
              </StackPanel>
            </Border>

          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ═══ TAB 5: ASSIGNMENT ═══ -->
      <TabItem Header="Assignment">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8">
          <StackPanel>
            <TextBlock Style="{StaticResource SectionHeader}" Text="Assignment Target"/>

            <StackPanel Margin="0,0,0,10">
              <RadioButton x:Name="RdoAsgAllDevices" Content="All Devices"  Margin="0,0,0,6" IsChecked="True"/>
              <RadioButton x:Name="RdoAsgAllUsers"   Content="All Users"    Margin="0,0,0,6"/>
              <RadioButton x:Name="RdoAsgGroup"      Content="Specific Group" Margin="0,0,0,6"/>
              <RadioButton x:Name="RdoAsgNone"       Content="No assignment now (configure manually in Intune)"/>
            </StackPanel>

            <!-- Multi-group panel — shown only when Group is selected -->
            <Border x:Name="PanelGroupSearch" Visibility="Collapsed"
                    Background="#F5F0FF" BorderBrush="#CCC" BorderThickness="1"
                    CornerRadius="3" Padding="10" Margin="0,4,0,8">
              <StackPanel>
                <Grid Margin="0,0,0,6">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" FontWeight="SemiBold" FontSize="12"
                             VerticalAlignment="Center" Text="Selected Groups"/>
                  <Button x:Name="BtnSearchGroup" Grid.Column="1"
                          Content="Search / Add Groups..." Padding="10,4" MinWidth="0"/>
                </Grid>
                <ListBox x:Name="LstFormGroups" MinHeight="60" MaxHeight="140"
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
                <Button x:Name="BtnRemoveFormGroup" Content="Remove Selected"
                        HorizontalAlignment="Left" Padding="8,3" Margin="0,6,0,0" MinWidth="0"/>
              </StackPanel>
            </Border>

            <TextBlock Style="{StaticResource SectionHeader}" Text="Options" Margin="0,8,0,4"/>
            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="130"/>
                <ColumnDefinition Width="160"/>
                <ColumnDefinition Width="130"/>
                <ColumnDefinition Width="160"/>
              </Grid.ColumnDefinitions>
              <Label Content="Intent" Grid.Column="0"/>
              <ComboBox x:Name="CmbIntent" Grid.Column="1" SelectedIndex="0">
                <ComboBoxItem Content="required"/>
                <ComboBoxItem Content="available"/>
                <ComboBoxItem Content="uninstall"/>
              </ComboBox>
              <Label Content="Notification" Grid.Column="2" Padding="12,0,6,0"/>
              <ComboBox x:Name="CmbNotification" Grid.Column="3" SelectedIndex="0">
                <ComboBoxItem Content="showAll"/>
                <ComboBoxItem Content="showReboot"/>
                <ComboBoxItem Content="hideAll"/>
              </ComboBox>
            </Grid>

            <TextBlock Style="{StaticResource SectionHeader}" Text="Filters" Margin="0,12,0,4"/>
            <TextBlock TextWrapping="Wrap" Foreground="#666" FontSize="11" Margin="0,0,0,8">
              <Run>Filters limit which devices this assignment applies to.</Run>
              <Run Foreground="#999">Populated from your Intune tenant when connected.</Run>
            </TextBlock>

            <Grid Style="{StaticResource FieldRow}">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="130"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="130"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label Content="Filter" Grid.Column="0"/>
              <ComboBox x:Name="CmbAssignFilter" Grid.Column="1" SelectedIndex="0">
                <ComboBoxItem Content="(none)" Tag=""/>
              </ComboBox>
              <Label Content="Filter intent" Grid.Column="2" Padding="12,0,6,0"/>
              <ComboBox x:Name="CmbFilterIntent" Grid.Column="3" SelectedIndex="0" IsEnabled="False">
                <ComboBoxItem Content="include"/>
                <ComboBoxItem Content="exclude"/>
              </ComboBox>
            </Grid>
            <TextBlock x:Name="TxtFilterStatus" Foreground="#999" FontSize="11" Margin="130,4,0,0"
                       Text="(No filters loaded — connect to Intune to populate)"/>

          </StackPanel>
        </ScrollViewer>
      </TabItem>

    </TabControl>

    <!-- PACKAGING ROW -->
    <GroupBox Header="Packaging" Grid.Row="4" Margin="10,8,10,0" Padding="8,6">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="75"/>
          <ColumnDefinition Width="155"/>
          <ColumnDefinition Width="55"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="60"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Label Content="Template" Grid.Column="0"/>
        <ComboBox x:Name="CmbTemplate" Grid.Column="1"/>
        <Label Content="Logo" Grid.Column="2" Padding="10,0,6,0"/>
        <TextBox x:Name="TxtLogo" Grid.Column="3" IsReadOnly="True" Background="#F9F9F9"/>
        <Button x:Name="BtnBrowseLogo" Grid.Column="4" Margin="4,0,0,0" Style="{StaticResource BrowseBtn}"/>
        <Label Content="Output" Grid.Column="5" Padding="10,0,6,0"/>
        <TextBox x:Name="TxtOutput" Grid.Column="6" IsReadOnly="True" Background="#F9F9F9"/>
        <Button x:Name="BtnBrowseOutput" Grid.Column="7" Margin="4,0,0,0" Style="{StaticResource BrowseBtn}"/>
      </Grid>
    </GroupBox>

    <!-- BUTTONS -->
    <Border Grid.Row="5" Background="#F5F5F5" BorderBrush="#DDD" BorderThickness="0,1,0,0" Padding="10,8">
      <Grid>
        <TextBlock x:Name="TxtValidation" Foreground="Red" VerticalAlignment="Center" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnUpload" Content="Package and Upload" Foreground="White"
                  FontWeight="SemiBold" Padding="16,6" MinWidth="0" Margin="0,0,8,0">
            <Button.Background>
              <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
                <GradientStop Color="#0693E3" Offset="0"/>
                <GradientStop Color="#9B51E0" Offset="1"/>
              </LinearGradientBrush>
            </Button.Background>
          </Button>
          <Button x:Name="BtnCancel" Content="Cancel"/>
        </StackPanel>
      </Grid>
    </Border>

  </Grid>
</Window>
'@

    #region Build window
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    function Find { param($n) $window.FindName($n) }

    # --- All controls ---
    $txtSource           = Find 'TxtSource'
    $btnBrowseSource     = Find 'BtnBrowseSource'
    $btnClearSource      = Find 'BtnClearSource'
    $psadtBanner         = Find 'PsadtBanner'
    $txtPsadtInfo        = Find 'TxtPsadtInfo'

    $txtDisplayName      = Find 'TxtDisplayName'
    $txtVersion          = Find 'TxtVersion'
    $txtPublisher        = Find 'TxtPublisher'
    $txtOwner            = Find 'TxtOwner'
    $txtDescription      = Find 'TxtDescription'
    $txtNotes            = Find 'TxtNotes'
    $txtInfoURL          = Find 'TxtInfoURL'
    $txtPrivacyURL       = Find 'TxtPrivacyURL'
    $panelCategories     = Find 'PanelCategories'
    $txtCategoryPH       = Find 'TxtCategoryPlaceholder'

    $txtInstallCmd       = Find 'TxtInstallCmd'
    $txtUninstallCmd     = Find 'TxtUninstallCmd'
    $cmbInstallExp       = Find 'CmbInstallExp'
    $cmbRestart          = Find 'CmbRestart'
    $psadtCmdNote        = Find 'PsadtCmdNote'

    $rdoDetectScript     = Find 'RdoDetectScript'
    $rdoDetectRegistry   = Find 'RdoDetectRegistry'
    $rdoDetectMSI        = Find 'RdoDetectMSI'
    $rdoDetectFile       = Find 'RdoDetectFile'
    $panelDetectScript   = Find 'PanelDetectScript'
    $panelDetectRegistry = Find 'PanelDetectRegistry'
    $panelDetectMSI      = Find 'PanelDetectMSI'
    $panelDetectFile     = Find 'PanelDetectFile'
    $txtDetectScript     = Find 'TxtDetectScript'
    $btnBrowseDetect     = Find 'BtnBrowseDetectScript'
    $chkDetectSignature  = Find 'ChkDetectSignature'
    $chkDetect32Bit      = Find 'ChkDetect32Bit'
    $txtRegKey           = Find 'TxtRegKey'
    $txtRegValue         = Find 'TxtRegValue'
    $cmbRegType          = Find 'CmbRegType'
    $panelRegComparison  = Find 'PanelRegComparison'
    $cmbRegOperator      = Find 'CmbRegOperator'
    $txtRegCompValue     = Find 'TxtRegCompValue'
    $chkReg32Bit         = Find 'ChkReg32Bit'
    $txtMsiCode          = Find 'TxtMsiCode'
    $chkMsiVersion       = Find 'ChkMsiVersion'
    $panelMsiVersion     = Find 'PanelMsiVersion'
    $cmbMsiOperator      = Find 'CmbMsiOperator'
    $txtMsiVersion       = Find 'TxtMsiVersion'
    $txtFilePath         = Find 'TxtFilePath'
    $txtFileName         = Find 'TxtFileName'
    $cmbFileType         = Find 'CmbFileType'
    $panelFileComparison = Find 'PanelFileComparison'
    $cmbFileOperator     = Find 'CmbFileOperator'
    $txtFileValue        = Find 'TxtFileValue'
    $chkFile32Bit        = Find 'ChkFile32Bit'

    # Requirements
    $chkArchX64          = Find 'ChkArchX64'
    $chkArchX86          = Find 'ChkArchX86'
    $chkArchArm64        = Find 'ChkArchArm64'
    $txtArchResult       = Find 'TxtArchResult'
    $cmbMinOS            = Find 'CmbMinOS'
    $lstReqRules         = Find 'LstReqRules'
    $btnAddReqRule       = Find 'BtnAddReqRule'
    $btnRemoveReqRule    = Find 'BtnRemoveReqRule'
    $panelAddReqRule     = Find 'PanelAddReqRule'
    $rdoReqTypeScript    = Find 'RdoReqTypeScript'
    $rdoReqTypeRegistry  = Find 'RdoReqTypeRegistry'
    $rdoReqTypeFile      = Find 'RdoReqTypeFile'
    $panelAddReqScript   = Find 'PanelAddReqScript'
    $panelAddReqRegistry = Find 'PanelAddReqRegistry'
    $panelAddReqFile     = Find 'PanelAddReqFile'
    $txtAddReqScript     = Find 'TxtAddReqScript'
    $btnAddReqScriptBrowse = Find 'BtnAddReqScriptBrowse'
    $cmbAddReqOutputType = Find 'CmbAddReqOutputType'
    $cmbAddReqScriptOp   = Find 'CmbAddReqScriptOp'
    $txtAddReqScriptValue = Find 'TxtAddReqScriptValue'
    $chkAddReqSignature  = Find 'ChkAddReqSignature'
    $chkAddReq32Bit      = Find 'ChkAddReq32Bit'
    $txtAddReqRegKey     = Find 'TxtAddReqRegKey'
    $txtAddReqRegValName = Find 'TxtAddReqRegValName'
    $cmbAddReqRegType    = Find 'CmbAddReqRegType'
    $cmbAddReqRegOp      = Find 'CmbAddReqRegOp'
    $txtAddReqRegValue   = Find 'TxtAddReqRegValue'
    $chkAddReqReg32Bit   = Find 'ChkAddReqReg32Bit'
    $txtAddReqFilePath   = Find 'TxtAddReqFilePath'
    $txtAddReqFileName   = Find 'TxtAddReqFileName'
    $cmbAddReqFileType   = Find 'CmbAddReqFileType'
    $cmbAddReqFileOp     = Find 'CmbAddReqFileOp'
    $txtAddReqFileValue  = Find 'TxtAddReqFileValue'
    $chkAddReqFile32Bit  = Find 'ChkAddReqFile32Bit'
    $btnReqAddConfirm    = Find 'BtnReqAddConfirm'
    $btnReqAddCancel     = Find 'BtnReqAddCancel'

    # Assignment
    $rdoAsgAllDevices    = Find 'RdoAsgAllDevices'
    $rdoAsgAllUsers      = Find 'RdoAsgAllUsers'
    $rdoAsgGroup         = Find 'RdoAsgGroup'
    $rdoAsgNone          = Find 'RdoAsgNone'
    $panelGroupSearch    = Find 'PanelGroupSearch'
    $lstFormGroups       = Find 'LstFormGroups'
    $btnSearchGroup      = Find 'BtnSearchGroup'
    $btnRemoveFormGroup  = Find 'BtnRemoveFormGroup'
    $btnReturnCodes      = Find 'BtnReturnCodes'
    $txtRCStatus         = Find 'TxtRCStatus'
    $cmbIntent           = Find 'CmbIntent'
    $cmbNotification     = Find 'CmbNotification'
    $cmbAssignFilter     = Find 'CmbAssignFilter'
    $cmbFilterIntent     = Find 'CmbFilterIntent'
    $txtFilterStatus     = Find 'TxtFilterStatus'

    # Packaging row
    $cmbTemplate         = Find 'CmbTemplate'
    $txtLogo             = Find 'TxtLogo'
    $btnBrowseLogo       = Find 'BtnBrowseLogo'
    $txtOutput           = Find 'TxtOutput'
    $btnBrowseOutput     = Find 'BtnBrowseOutput'

    $txtValidation       = Find 'TxtValidation'
    $btnUpload           = Find 'BtnUpload'
    $btnCancel           = Find 'BtnCancel'
    #endregion

    #region Script-level state
    $script:isPSADT          = $false
    $script:psadtMeta        = $null
    $script:requirementRules = [System.Collections.Generic.List[hashtable]]::new()
    $script:formGroups       = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $script:formReturnCodes  = @(
        @{ ReturnCode = 0;    Type = 'success'    }
        @{ ReturnCode = 1707; Type = 'success'    }
        @{ ReturnCode = 3010; Type = 'softReboot' }
        @{ ReturnCode = 1641; Type = 'hardReboot' }
        @{ ReturnCode = 1618; Type = 'retry'      }
    )
    $lstFormGroups.ItemsSource = $script:formGroups
    #endregion

    #region Populate static data
    # Templates
    if ($TemplateFolder -and (Test-Path $TemplateFolder)) {
        $tpls = Get-ChildItem -Path $TemplateFolder -Filter '*.json' | Select-Object -ExpandProperty BaseName
        foreach ($t in $tpls) { $cmbTemplate.Items.Add($t) | Out-Null }
        $idx = $cmbTemplate.Items.IndexOf($DefaultTemplate)
        $cmbTemplate.SelectedIndex = [Math]::Max(0, $idx)
    }
    if ($DefaultOutput) { $txtOutput.Text = $DefaultOutput }

    # Categories
    if ($AvailableCategories -and $AvailableCategories.Count -gt 0) {
        $panelCategories.Children.Remove($txtCategoryPH)
        foreach ($cat in ($AvailableCategories | Sort-Object)) {
            $cb = [System.Windows.Controls.CheckBox]::new()
            $cb.Content = $cat
            $cb.Margin  = [System.Windows.Thickness]::new(0, 2, 0, 2)
            $panelCategories.Children.Add($cb) | Out-Null
        }
    }

    # Filters
    if ($AvailableFilters -and $AvailableFilters.Count -gt 0) {
        foreach ($f in $AvailableFilters) {
            $item     = [System.Windows.Controls.ComboBoxItem]::new()
            $item.Content = $f.displayName
            $item.Tag     = $f.id
            $cmbAssignFilter.Items.Add($item) | Out-Null
        }
        $txtFilterStatus.Text = "$($AvailableFilters.Count) filter(s) available"
    }
    #endregion

    #region Helper functions

    function Show-FolderDialog {
        param([string]$Desc = 'Select folder')
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $Desc; $dlg.ShowNewFolderButton = $true
        if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
        return $null
    }

    function Show-FileDialog {
        param([string]$Title, [string]$Filter = 'All files (*.*)|*.*')
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = $Title; $dlg.Filter = $Filter
        if ($dlg.ShowDialog() -eq 'OK') { return $dlg.FileName }
        return $null
    }

    function Get-ArchValue {
        $x64  = [bool]$chkArchX64.IsChecked
        $x86  = [bool]$chkArchX86.IsChecked
        $arm  = [bool]$chkArchArm64.IsChecked
        if ($x64 -and $x86 -and $arm) { return 'AllWithARM64' }
        if ($x64 -and $arm)            { return 'x64arm64' }
        if ($x86 -and $arm)            { return 'AllWithARM64' }  # no x86+arm64 only option
        if ($arm)                      { return 'arm64' }
        if ($x64 -and $x86)            { return 'x64x86' }
        if ($x64)                      { return 'x64' }
        if ($x86)                      { return 'x86' }
        return 'x64'
    }

    function Update-ArchLabel {
        $txtArchResult.Text = "→ $(Get-ArchValue)"
    }

    function Update-ReqRulesListBox {
        $lstReqRules.Items.Clear()
        foreach ($r in $script:requirementRules) {
            $summary = switch ($r.Type) {
                'Script'   {
                    $fn = [System.IO.Path]::GetFileName($r.ScriptPath)
                    "[Script]    $fn  →  $($r.OutputDataType)  $($r.Operator)  '$($r.Value)'"
                }
                'Registry' {
                    $vn = if ($r.ValueName) { "\$($r.ValueName)" } else { '' }
                    "[Registry]  $($r.KeyPath)$vn  →  $($r.DetectionType)"
                }
                'File'     {
                    "[File]      $($r.Path)\$($r.FileOrFolder)  →  $($r.DetectionType)"
                }
            }
            $lstReqRules.Items.Add($summary) | Out-Null
        }
    }

    function Switch-AddReqPanel {
        $panelAddReqScript.Visibility   = 'Collapsed'
        $panelAddReqRegistry.Visibility = 'Collapsed'
        $panelAddReqFile.Visibility     = 'Collapsed'
        if ($rdoReqTypeScript.IsChecked)   { $panelAddReqScript.Visibility   = 'Visible' }
        if ($rdoReqTypeRegistry.IsChecked) { $panelAddReqRegistry.Visibility = 'Visible' }
        if ($rdoReqTypeFile.IsChecked)     { $panelAddReqFile.Visibility     = 'Visible' }
    }
    #endregion

    #region PSADT auto-detect
    function Update-PSADTState {
        param([string]$Folder)
        $meta = if ($Folder -and (Test-Path $Folder)) { Get-PSADTMetadata -SourceFolder $Folder } else { $null }

        if ($meta) {
            $script:isPSADT = $true; $script:psadtMeta = $meta

            if (-not $txtDisplayName.Text) { $txtDisplayName.Text = $meta.AppName }
            if (-not $txtVersion.Text)     { $txtVersion.Text     = $meta.AppVersion }
            if (-not $txtPublisher.Text)   { $txtPublisher.Text   = $meta.AppVendor }
            if (-not $txtOwner.Text)       { $txtOwner.Text       = $meta.AppOwner }
            if (-not $txtNotes.Text)       { $txtNotes.Text       = "PSADT v4 package ($($meta.AppName))" }

            $txtInstallCmd.Text     = $meta.InstallCommandLine
            $txtUninstallCmd.Text   = $meta.UninstallCommandLine
            $txtInstallCmd.IsReadOnly   = $true
            $txtInstallCmd.Background   = [System.Windows.Media.Brushes]::WhiteSmoke
            $txtUninstallCmd.IsReadOnly = $true
            $txtUninstallCmd.Background = [System.Windows.Media.Brushes]::WhiteSmoke

            $psadtBanner.Visibility  = 'Visible'
            $psadtCmdNote.Visibility = 'Visible'
            $txtPsadtInfo.Text = "PSADT v4 — $($meta.AppVendor) $($meta.AppName) $($meta.AppVersion). Commands locked from template."

            $idx = $cmbTemplate.Items.IndexOf('PSADT-Default')
            if ($idx -ge 0) { $cmbTemplate.SelectedIndex = $idx }
        }
        else {
            $script:isPSADT = $false; $script:psadtMeta = $null
            $psadtBanner.Visibility  = 'Collapsed'
            $psadtCmdNote.Visibility = 'Collapsed'
            $txtInstallCmd.IsReadOnly   = $false
            $txtInstallCmd.Background   = [System.Windows.Media.Brushes]::White
            $txtUninstallCmd.IsReadOnly = $false
            $txtUninstallCmd.Background = [System.Windows.Media.Brushes]::White
        }
    }
    #endregion

    #region Event handlers

    $btnBrowseSource.Add_Click({
        $f = Show-FolderDialog -Desc 'Select application source folder'
        if ($f) { $txtSource.Text = $f; Update-PSADTState -Folder $f }
    })

    $btnClearSource.Add_Click({
        $txtSource.Text = ''
        Update-PSADTState -Folder ''
        $txtDisplayName.Text = $txtVersion.Text = $txtPublisher.Text = $txtOwner.Text = ''
        $txtInstallCmd.Text  = $txtUninstallCmd.Text = ''
    })

    # Detection panel switches
    $rdoDetectScript.Add_Checked({
        $panelDetectScript.Visibility   = 'Visible'
        $panelDetectRegistry.Visibility = 'Collapsed'
        $panelDetectMSI.Visibility      = 'Collapsed'
        $panelDetectFile.Visibility     = 'Collapsed'
    })
    $rdoDetectRegistry.Add_Checked({
        $panelDetectScript.Visibility   = 'Collapsed'
        $panelDetectRegistry.Visibility = 'Visible'
        $panelDetectMSI.Visibility      = 'Collapsed'
        $panelDetectFile.Visibility     = 'Collapsed'
    })
    $rdoDetectMSI.Add_Checked({
        $panelDetectScript.Visibility   = 'Collapsed'
        $panelDetectRegistry.Visibility = 'Collapsed'
        $panelDetectMSI.Visibility      = 'Visible'
        $panelDetectFile.Visibility     = 'Collapsed'
    })
    $rdoDetectFile.Add_Checked({
        $panelDetectScript.Visibility   = 'Collapsed'
        $panelDetectRegistry.Visibility = 'Collapsed'
        $panelDetectMSI.Visibility      = 'Collapsed'
        $panelDetectFile.Visibility     = 'Visible'
    })

    $cmbRegType.Add_SelectionChanged({
        $needsVal = $cmbRegType.SelectedItem.Content -notin @('exists','doesNotExist')
        $panelRegComparison.Visibility = if ($needsVal) { 'Visible' } else { 'Collapsed' }
    })
    $chkMsiVersion.Add_Checked({   $panelMsiVersion.Visibility = 'Visible' })
    $chkMsiVersion.Add_Unchecked({ $panelMsiVersion.Visibility = 'Collapsed' })
    $cmbFileType.Add_SelectionChanged({
        $needsVal = $cmbFileType.SelectedItem.Content -notin @('exists','doesNotExist','modifiedDate','createdDate')
        $panelFileComparison.Visibility = if ($needsVal) { 'Visible' } else { 'Collapsed' }
    })

    $btnBrowseDetect.Add_Click({
        $f = Show-FileDialog -Title 'Select detection script' -Filter 'PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*'
        if ($f) { $txtDetectScript.Text = $f }
    })

    # Architecture checkboxes
    $chkArchX64.Add_Checked(   { Update-ArchLabel })
    $chkArchX64.Add_Unchecked( { Update-ArchLabel })
    $chkArchX86.Add_Checked(   { Update-ArchLabel })
    $chkArchX86.Add_Unchecked( { Update-ArchLabel })
    $chkArchArm64.Add_Checked( { Update-ArchLabel })
    $chkArchArm64.Add_Unchecked({ Update-ArchLabel })

    # Additional requirement rules
    $btnAddReqRule.Add_Click({
        $panelAddReqRule.Visibility = 'Visible'
        Switch-AddReqPanel
    })
    $btnRemoveReqRule.Add_Click({
        $idx = $lstReqRules.SelectedIndex
        if ($idx -ge 0) {
            $script:requirementRules.RemoveAt($idx)
            Update-ReqRulesListBox
        }
    })

    $rdoReqTypeScript.Add_Checked(   { Switch-AddReqPanel })
    $rdoReqTypeRegistry.Add_Checked( { Switch-AddReqPanel })
    $rdoReqTypeFile.Add_Checked(     { Switch-AddReqPanel })

    $btnAddReqScriptBrowse.Add_Click({
        $f = Show-FileDialog -Title 'Select requirement script' -Filter 'PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*'
        if ($f) { $txtAddReqScript.Text = $f }
    })

    $btnReqAddConfirm.Add_Click({
        $rule = $null
        if ($rdoReqTypeScript.IsChecked) {
            if (-not $txtAddReqScript.Text) {
                [System.Windows.MessageBox]::Show('Please select a script file.', 'Validation', 'OK', 'Warning')
                return
            }
            $rule = @{
                Type                 = 'Script'
                ScriptPath           = $txtAddReqScript.Text
                OutputDataType       = $cmbAddReqOutputType.SelectedItem.Content
                Operator             = $cmbAddReqScriptOp.SelectedItem.Content
                Value                = $txtAddReqScriptValue.Text
                EnforceSignatureCheck = [bool]$chkAddReqSignature.IsChecked
                RunAs32Bit           = [bool]$chkAddReq32Bit.IsChecked
            }
        }
        elseif ($rdoReqTypeRegistry.IsChecked) {
            if (-not $txtAddReqRegKey.Text) {
                [System.Windows.MessageBox]::Show('Please enter a registry key path.', 'Validation', 'OK', 'Warning')
                return
            }
            $rule = @{
                Type                 = 'Registry'
                KeyPath              = $txtAddReqRegKey.Text
                ValueName            = $txtAddReqRegValName.Text
                DetectionType        = $cmbAddReqRegType.SelectedItem.Content
                Operator             = $cmbAddReqRegOp.SelectedItem.Content
                Value                = $txtAddReqRegValue.Text
                Check32BitOn64System = [bool]$chkAddReqReg32Bit.IsChecked
            }
        }
        elseif ($rdoReqTypeFile.IsChecked) {
            if (-not $txtAddReqFilePath.Text -or -not $txtAddReqFileName.Text) {
                [System.Windows.MessageBox]::Show('Please enter folder path and file/folder name.', 'Validation', 'OK', 'Warning')
                return
            }
            $rule = @{
                Type                 = 'File'
                Path                 = $txtAddReqFilePath.Text
                FileOrFolder         = $txtAddReqFileName.Text
                DetectionType        = $cmbAddReqFileType.SelectedItem.Content
                Operator             = $cmbAddReqFileOp.SelectedItem.Content
                Value                = $txtAddReqFileValue.Text
                Check32BitOn64System = [bool]$chkAddReqFile32Bit.IsChecked
            }
        }

        if ($rule) {
            $script:requirementRules.Add($rule)
            Update-ReqRulesListBox

            # Reset add-rule fields
            $txtAddReqScript.Text = ''; $txtAddReqScriptValue.Text = ''
            $txtAddReqRegKey.Text = ''; $txtAddReqRegValName.Text = ''; $txtAddReqRegValue.Text = ''
            $txtAddReqFilePath.Text = ''; $txtAddReqFileName.Text = ''; $txtAddReqFileValue.Text = ''
            $panelAddReqRule.Visibility = 'Collapsed'
        }
    })

    $btnReqAddCancel.Add_Click({ $panelAddReqRule.Visibility = 'Collapsed' })

    # Assignment — show/hide groups panel
    $rdoAsgGroup.Add_Checked({ $panelGroupSearch.Visibility = 'Visible' })
    $rdoAsgAllDevices.Add_Checked({ $panelGroupSearch.Visibility = 'Collapsed' })
    $rdoAsgAllUsers.Add_Checked({   $panelGroupSearch.Visibility = 'Collapsed' })
    $rdoAsgNone.Add_Checked({       $panelGroupSearch.Visibility = 'Collapsed' })

    # Enable filter intent when a filter is selected
    $cmbAssignFilter.Add_SelectionChanged({
        $selected = $cmbAssignFilter.SelectedItem
        $hasFilter = ($selected -and $selected.Tag -ne '')
        $cmbFilterIntent.IsEnabled = $hasFilter
    })

    # Group picker — open Show-GroupPicker with current selection pre-loaded
    $btnSearchGroup.Add_Click({
        $already = @($script:formGroups | ForEach-Object { @{ GroupName = $_.DisplayName; GroupID = $_.ID } })
        $picked = Show-GroupPicker -AlreadySelected $already
        if ($null -ne $picked) {
            $script:formGroups.Clear()
            foreach ($g in $picked) {
                $script:formGroups.Add([PSCustomObject]@{ DisplayName = $g.GroupName; ID = $g.GroupID }) | Out-Null
            }
        }
    })

    # Remove selected group from list
    $btnRemoveFormGroup.Add_Click({
        $sel = $lstFormGroups.SelectedItem
        if ($sel) { $script:formGroups.Remove($sel) | Out-Null }
    })

    # Return codes editor
    $btnReturnCodes.Add_Click({
        $result = Show-ReturnCodeEditor -CurrentCodes $script:formReturnCodes
        if ($null -ne $result) {
            $script:formReturnCodes = @($result)
            $n = $script:formReturnCodes.Count
            $txtRCStatus.Text = "$n return code$(if($n -ne 1){'s'})"
        }
    })

    $btnBrowseLogo.Add_Click({
        $f = Show-FileDialog -Title 'Select logo' -Filter 'Images (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg|All files (*.*)|*.*'
        if ($f) { $txtLogo.Text = $f }
    })
    $btnBrowseOutput.Add_Click({
        $f = Show-FolderDialog -Desc 'Select output folder for .intunewin'
        if ($f) { $txtOutput.Text = $f }
    })
    #endregion

    #region Upload / Cancel
    $script:result = $null

    $btnUpload.Add_Click({
        $errors = [System.Collections.Generic.List[string]]::new()
        if (-not $txtSource.Text)       { $errors.Add('Source folder is required') }
        if (-not $txtDisplayName.Text)  { $errors.Add('Display Name is required') }
        if (-not $txtInstallCmd.Text)   { $errors.Add('Install command is required') }
        if (-not $txtUninstallCmd.Text) { $errors.Add('Uninstall command is required') }
        if (-not $txtOutput.Text)       { $errors.Add('Output folder is required') }
        if ($rdoDetectScript.IsChecked   -and -not $txtDetectScript.Text)   { $errors.Add('Detection script required') }
        if ($rdoDetectRegistry.IsChecked -and -not $txtRegKey.Text)         { $errors.Add('Detection registry key required') }
        if ($rdoDetectMSI.IsChecked      -and -not $txtMsiCode.Text)        { $errors.Add('Detection MSI product code required') }
        if ($rdoDetectFile.IsChecked     -and (-not $txtFilePath.Text -or -not $txtFileName.Text)) {
            $errors.Add('Detection file path and name required')
        }

        if ($errors.Count -gt 0) {
            $txtValidation.Text = $errors -join '  •  '
            return
        }
        $txtValidation.Text = ''

        # Architecture
        $archValue = Get-ArchValue

        # Detection
        $detection = if ($rdoDetectScript.IsChecked) {
            @{ Type='Script'; ScriptPath=$txtDetectScript.Text
               EnforceSignatureCheck=[bool]$chkDetectSignature.IsChecked
               RunAs32Bit=[bool]$chkDetect32Bit.IsChecked }
        }
        elseif ($rdoDetectRegistry.IsChecked) {
            @{ Type='Registry'; KeyPath=$txtRegKey.Text; ValueName=$txtRegValue.Text
               DetectionType=$cmbRegType.SelectedItem.Content
               Operator=$cmbRegOperator.SelectedItem.Content; Value=$txtRegCompValue.Text
               Check32BitOn64System=[bool]$chkReg32Bit.IsChecked }
        }
        elseif ($rdoDetectMSI.IsChecked) {
            @{ Type='MSI'; ProductCode=$txtMsiCode.Text
               ProductVersionOperator=if($chkMsiVersion.IsChecked){$cmbMsiOperator.SelectedItem.Content}else{$null}
               ProductVersion=if($chkMsiVersion.IsChecked){$txtMsiVersion.Text}else{$null} }
        }
        else {
            @{ Type='File'; Path=$txtFilePath.Text; FileOrFolder=$txtFileName.Text
               DetectionType=$cmbFileType.SelectedItem.Content
               Operator=$cmbFileOperator.SelectedItem.Content; Value=$txtFileValue.Text
               Check32BitOn64System=[bool]$chkFile32Bit.IsChecked }
        }

        # Selected categories
        $selectedCategories = @()
        foreach ($child in $panelCategories.Children) {
            if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked) {
                $selectedCategories += $child.Content
            }
        }

        # Assignment
        $asgType = if ($rdoAsgAllDevices.IsChecked) { 'AllDevices' }
                   elseif ($rdoAsgAllUsers.IsChecked) { 'AllUsers' }
                   elseif ($rdoAsgGroup.IsChecked)    { 'Group' }
                   else                                { 'None' }
        $groupsArr = @($script:formGroups | ForEach-Object { @{ GroupName = $_.DisplayName; GroupID = $_.ID } })
        $assignment = @{
            Type         = $asgType
            Intent       = $cmbIntent.SelectedItem.Content
            Notification = $cmbNotification.SelectedItem.Content
            Groups       = if ($asgType -eq 'Group') { $groupsArr } else { @() }
        }

        # Filter
        $filterItem = $cmbAssignFilter.SelectedItem
        if ($filterItem -and $filterItem.Tag) {
            $assignment.FilterID     = $filterItem.Tag
            $assignment.FilterIntent = $cmbFilterIntent.SelectedItem.Content
        }

        # Setup file
        $setupFile = if ($script:psadtMeta) { $script:psadtMeta.SetupFile } else { '' }

        $script:result = @{
            SourceFolder             = $txtSource.Text
            SetupFile                = $setupFile
            IsPSADT                  = $script:isPSADT
            DisplayName              = $txtDisplayName.Text
            Version                  = $txtVersion.Text
            Publisher                = $txtPublisher.Text
            Owner                    = $txtOwner.Text
            Description              = $txtDescription.Text
            Notes                    = $txtNotes.Text
            InformationURL           = $txtInfoURL.Text
            PrivacyURL               = $txtPrivacyURL.Text
            Categories               = $selectedCategories
            InstallCommandLine       = $txtInstallCmd.Text
            UninstallCommandLine     = $txtUninstallCmd.Text
            InstallExperience        = $cmbInstallExp.SelectedItem.Content
            RestartBehavior          = $cmbRestart.SelectedItem.Tag ?? $cmbRestart.SelectedItem.Content
            Template                 = $cmbTemplate.SelectedItem
            LogoPath                 = $txtLogo.Text
            OutputFolder             = $txtOutput.Text
            Detection                = $detection
            Architecture             = $archValue
            MinimumSupportedWindowsRelease = $cmbMinOS.SelectedItem.Content
            AdditionalRequirementRules = ($script:requirementRules | ForEach-Object { $_ })
            ReturnCodes              = $script:formReturnCodes
            Assignment               = $assignment
        }

        $window.DialogResult = $true
        $window.Close()
    })

    $btnCancel.Add_Click({ $window.DialogResult = $false; $window.Close() })
    #endregion

    #region Pre-populate (edit / bulk-manager mode)
    # Runs AFTER all event handlers are registered so that setting radio buttons and
    # checkboxes correctly fires the panel-switch handlers.
    if ($PrePopulate -and $PrePopulate.Count -gt 0) {
        $p = $PrePopulate

        # Button label + window title
        $btnUpload.Content = $SubmitLabel
        if ($p.DisplayName) { $window.Title = "Edit Application — $($p.DisplayName)" }

        # ── Simple text fields (set before source folder so PSADT won't overwrite them) ──
        if ($p.DisplayName)    { $txtDisplayName.Text   = $p.DisplayName    }
        if ($p.Version)        { $txtVersion.Text       = $p.Version        }
        if ($p.Publisher)      { $txtPublisher.Text     = $p.Publisher      }
        if ($p.Owner)          { $txtOwner.Text         = $p.Owner          }
        if ($p.Description)    { $txtDescription.Text   = $p.Description    }
        if ($p.Notes)          { $txtNotes.Text         = $p.Notes          }
        if ($p.InformationURL) { $txtInfoURL.Text       = $p.InformationURL }
        if ($p.PrivacyURL)     { $txtPrivacyURL.Text    = $p.PrivacyURL     }

        # ── Source folder (triggers PSADT detection + locks commands if applicable) ──
        if ($p.SourceFolder -and (Test-Path $p.SourceFolder)) {
            $txtSource.Text = $p.SourceFolder
            Update-PSADTState -Folder $p.SourceFolder
        }

        # ── Commands (only if not locked by PSADT) ──
        if (-not $script:isPSADT) {
            if ($p.InstallCommandLine)   { $txtInstallCmd.Text   = $p.InstallCommandLine   }
            if ($p.UninstallCommandLine) { $txtUninstallCmd.Text = $p.UninstallCommandLine }
        }
        $expMap  = @{ system=0; user=1 }
        $rstMap  = @{ suppress=0; allow=1; basedOnReturnCode=2; force=3 }
        if ($p.InstallExperience -and $expMap.ContainsKey($p.InstallExperience)) { $cmbInstallExp.SelectedIndex = $expMap[$p.InstallExperience] }
        if ($p.RestartBehavior   -and $rstMap.ContainsKey($p.RestartBehavior))   { $cmbRestart.SelectedIndex   = $rstMap[$p.RestartBehavior]   }

        # ── Template / Logo / Output ──
        if ($p.Template) {
            $tIdx = $cmbTemplate.Items.IndexOf($p.Template)
            if ($tIdx -ge 0) { $cmbTemplate.SelectedIndex = $tIdx }
        }
        if ($p.LogoPath)     { $txtLogo.Text   = $p.LogoPath     }
        if ($p.OutputFolder) { $txtOutput.Text = $p.OutputFolder }

        # ── Detection ──
        if ($p.Detection) {
            $d       = $p.Detection
            $opMap   = @{ equal=0; notEqual=1; greaterThan=2; greaterThanOrEqual=3; lessThan=4; lessThanOrEqual=5 }
            switch ($d.Type) {
                'Script' {
                    $rdoDetectScript.IsChecked    = $true
                    if ($d.ScriptPath) { $txtDetectScript.Text = $d.ScriptPath }
                    $chkDetectSignature.IsChecked = [bool]$d.EnforceSignatureCheck
                    $chkDetect32Bit.IsChecked     = [bool]$d.RunAs32Bit
                }
                'Registry' {
                    $rdoDetectRegistry.IsChecked = $true
                    $txtRegKey.Text              = $d.KeyPath
                    $txtRegValue.Text            = $d.ValueName
                    $rTypeMap = @{ exists=0; doesNotExist=1; string=2; integer=3; version=4; hexadecimal=5 }
                    if ($d.DetectionType -and $rTypeMap.ContainsKey($d.DetectionType)) { $cmbRegType.SelectedIndex     = $rTypeMap[$d.DetectionType] }
                    if ($d.Operator      -and $opMap.ContainsKey($d.Operator))         { $cmbRegOperator.SelectedIndex = $opMap[$d.Operator]          }
                    if ($d.Value)        { $txtRegCompValue.Text = $d.Value }
                    $chkReg32Bit.IsChecked = [bool]$d.Check32BitOn64System
                }
                'MSI' {
                    $rdoDetectMSI.IsChecked = $true
                    $txtMsiCode.Text        = $d.ProductCode
                    if ($d.ProductVersionOperator) {
                        $chkMsiVersion.IsChecked = $true
                        if ($opMap.ContainsKey($d.ProductVersionOperator)) { $cmbMsiOperator.SelectedIndex = $opMap[$d.ProductVersionOperator] }
                        $txtMsiVersion.Text = $d.ProductVersion
                    }
                }
                'File' {
                    $rdoDetectFile.IsChecked = $true
                    $txtFilePath.Text        = $d.Path
                    $txtFileName.Text        = $d.FileOrFolder
                    $fTypeMap = @{ exists=0; doesNotExist=1; modifiedDate=2; createdDate=3; version=4; sizeInMBGreaterThan=5 }
                    if ($d.DetectionType -and $fTypeMap.ContainsKey($d.DetectionType)) { $cmbFileType.SelectedIndex     = $fTypeMap[$d.DetectionType] }
                    if ($d.Operator      -and $opMap.ContainsKey($d.Operator))         { $cmbFileOperator.SelectedIndex = $opMap[$d.Operator]          }
                    if ($d.Value) { $txtFileValue.Text = $d.Value }
                    $chkFile32Bit.IsChecked = [bool]$d.Check32BitOn64System
                }
            }
        }

        # ── Architecture ──
        if ($p.Architecture) {
            $a = $p.Architecture
            $chkArchX64.IsChecked   = $a -in @('x64',  'x64x86', 'x64arm64', 'AllWithARM64')
            $chkArchX86.IsChecked   = $a -in @('x86',  'x64x86', 'AllWithARM64')
            $chkArchArm64.IsChecked = $a -in @('arm64','x64arm64','AllWithARM64')
            Update-ArchLabel
        }

        # ── Minimum OS ──
        if ($p.MinimumSupportedWindowsRelease) {
            $osOrder = @('W10_1607','W10_1703','W10_1709','W10_1803','W10_1809','W10_1903','W10_1909',
                         'W10_2004','W10_20H2','W10_21H1','W10_21H2','W10_22H2',
                         'W11_21H2','W11_22H2','W11_23H2','W11_24H2')
            $oIdx = $osOrder.IndexOf($p.MinimumSupportedWindowsRelease)
            if ($oIdx -ge 0) { $cmbMinOS.SelectedIndex = $oIdx }
        }

        # ── Additional requirement rules ──
        if ($p.AdditionalRequirementRules) {
            foreach ($rule in $p.AdditionalRequirementRules) { $script:requirementRules.Add($rule) }
            Update-ReqRulesListBox
        }

        # ── Assignment ──
        if ($p.Assignment) {
            $a = $p.Assignment
            switch ($a.Type) {
                'AllDevices' { $rdoAsgAllDevices.IsChecked = $true }
                'AllUsers'   { $rdoAsgAllUsers.IsChecked   = $true }
                'Group' {
                    $rdoAsgGroup.IsChecked = $true
                    # Load groups — support new Groups array and old GroupName/GroupID scalar
                    $script:formGroups.Clear()
                    $grpsToLoad = @()
                    if ($a.Groups -and @($a.Groups).Count -gt 0) {
                        $grpsToLoad = @($a.Groups)
                    } elseif ($a.GroupID) {
                        $grpsToLoad = @(@{ GroupName = $a.GroupName ?? ''; GroupID = $a.GroupID })
                    }
                    foreach ($g in $grpsToLoad) {
                        $gName = if ($g -is [hashtable]) { $g.GroupName ?? $g.DisplayName ?? '' } else { $g.GroupName ?? $g.DisplayName ?? '' }
                        $gID   = if ($g -is [hashtable]) { $g.GroupID   ?? $g.ID ?? '' }           else { $g.GroupID   ?? $g.ID ?? '' }
                        if ($gID) { $script:formGroups.Add([PSCustomObject]@{ DisplayName = $gName; ID = $gID }) | Out-Null }
                    }
                }
                'None' { $rdoAsgNone.IsChecked = $true }
            }
            $intentMap = @{ required=0; available=1; uninstall=2 }
            $notifMap  = @{ showAll=0; showReboot=1; hideAll=2 }
            if ($a.Intent       -and $intentMap.ContainsKey($a.Intent))       { $cmbIntent.SelectedIndex       = $intentMap[$a.Intent]       }
            if ($a.Notification -and $notifMap.ContainsKey($a.Notification))  { $cmbNotification.SelectedIndex = $notifMap[$a.Notification]  }
            if ($a.FilterID) {
                foreach ($item in $cmbAssignFilter.Items) {
                    if ($item -is [System.Windows.Controls.ComboBoxItem] -and $item.Tag -eq $a.FilterID) {
                        $cmbAssignFilter.SelectedItem = $item; break
                    }
                }
                $fMap = @{ include=0; exclude=1 }
                if ($a.FilterIntent -and $fMap.ContainsKey($a.FilterIntent)) { $cmbFilterIntent.SelectedIndex = $fMap[$a.FilterIntent] }
            }
        }

        # ── Return codes ──
        if ($p.ReturnCodes -and @($p.ReturnCodes).Count -gt 0) {
            $script:formReturnCodes = @($p.ReturnCodes | ForEach-Object {
                if ($_ -is [PSCustomObject]) { @{ ReturnCode = [int]$_.ReturnCode; Type = [string]$_.Type } } else { $_ }
            })
            $n = $script:formReturnCodes.Count
            $txtRCStatus.Text = "$n return code$(if($n -ne 1){'s'})"
        }

        # ── Categories ──
        # Accept either a Categories array (from Full Setup result) or a Category string (from bulk grid)
        $preCategories = if ($p.Categories -and @($p.Categories).Count -gt 0) {
            @($p.Categories)
        } elseif ($p.Category -and $p.Category -ne '') {
            @($p.Category)
        } else { @() }

        if ($preCategories.Count -gt 0) {
            foreach ($child in $panelCategories.Children) {
                if ($child -is [System.Windows.Controls.CheckBox]) {
                    $child.IsChecked = ($preCategories -contains $child.Content)
                }
            }
        }
    }
    #endregion

    $window.ShowDialog() | Out-Null
    return $script:result
}
