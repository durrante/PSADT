<#

.SYNOPSIS
PSAppDeployToolkit.WinGet - This module script a basic scaffold to use with PSAppDeployToolkit modules destined for the PowerShell Gallery.

.DESCRIPTION
This module can be directly imported from the command line via Import-Module, but it is usually imported by the Invoke-AppDeployToolkit.ps1 script.

PSAppDeployToolkit is licensed under the BSD 3-Clause License - Copyright (C) 2024 Mitch Richters. All rights reserved.

.NOTES
BSD 3-Clause License

Copyright (c) 2024, Mitch Richters

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1.  Redistributions of source code must retain the above copyright notice, this
    list of conditions and the following disclaimer.

2.  Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

3.  Neither the name of the copyright holder nor the names of its
    contributors may be used to endorse or promote products derived from
    this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#>

#-----------------------------------------------------------------------------
#
# MARK: Module Initialization Code
#
#-----------------------------------------------------------------------------

# Throw if we're running in the ISE, it can't support different character encoding.
if ($Host.Name.Equals('Windows PowerShell ISE Host'))
{
    throw [System.Management.Automation.ErrorRecord]::new(
        [System.NotSupportedException]::new("This module does not support Windows PowerShell ISE as it's not possible to set the output character encoding correctly."),
        'WindowsPowerShellIseNotSupported',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $Host
    )
}

# Throw if this psm1 file isn't being imported via our manifest.
if (!([System.Environment]::StackTrace.Split("`n") -like '*Microsoft.PowerShell.Commands.ModuleCmdletBase.LoadModuleManifest(*'))
{
    throw [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new("This module must be imported via its .psd1 file, which is recommended for all modules that supply a .psd1 file."),
        'ModuleImportError',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $MyInvocation.MyCommand.ScriptBlock.Module
    )
}

# Rethrowing caught exceptions makes the error output from Import-Module look better.
try
{
    # Set up lookup table for all cmdlets used within module, using PSAppDeployToolkit's as a basis.
    $CommandTable = [System.Collections.Generic.Dictionary[System.String, System.Management.Automation.CommandInfo]](& (& 'Microsoft.PowerShell.Core\Get-Command' -Name Get-ADTCommandTable -FullyQualifiedModule @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.0.6' }))

    # Expand command lookup table with cmdlets used through this module.
    & {
        # Set up list of modules this module depends upon.
        $RequiredModules = [System.Collections.Generic.List[Microsoft.PowerShell.Commands.ModuleSpecification]][Microsoft.PowerShell.Commands.ModuleSpecification[]]$(
            @{ ModuleName = "$PSScriptRoot\Submodules\psyml"; Guid = 'a88e2e67-a937-4d98-a4d3-0b03d3ade169'; ModuleVersion = '1.0.0' }
        )

        # Handle the Appx module differently due to PowerShell 7 shenanighans. https://github.com/PowerShell/PowerShell/issues/13138
        if ($PSEdition.Equals('Core'))
        {
            try
            {
                (& $Script:CommandTable.'Import-Module' -FullyQualifiedName @{ ModuleName = 'Appx'; Guid = 'aeef2bef-eba9-4a1d-a3d2-d0b52df76deb'; ModuleVersion = '1.0' } -Global -UseWindowsPowerShell -Force -PassThru -WarningAction Ignore -ErrorAction Stop).ExportedCommands.Values | & { process { $CommandTable.Add($_.Name, $_) } }
            }
            catch
            {
                (& $Script:CommandTable.'Import-Module' -FullyQualifiedName @{ ModuleName = 'Appx'; Guid = 'aeef2bef-eba9-4a1d-a3d2-d0b52df76deb'; ModuleVersion = '1.0' } -Global -UseWindowsPowerShell -Force -PassThru -WarningAction Ignore -ErrorAction Stop).ExportedCommands.Values | & { process { $CommandTable.Add($_.Name, $_) } }
            }
        }
        else
        {
            $RequiredModules.Add(@{ ModuleName = 'Appx'; Guid = 'aeef2bef-eba9-4a1d-a3d2-d0b52df76deb'; ModuleVersion = '1.0' })
        }

        # Import required modules and add their commands to the command table.
        (& $Script:CommandTable.'Import-Module' -FullyQualifiedName $RequiredModules -Global -Force -PassThru -ErrorAction Stop).ExportedCommands.Values | & { process { $CommandTable.Add($_.Name, $_) } }
    }

    # Set required variables to ensure module functionality.
    & $Script:CommandTable.'New-Variable' -Name ErrorActionPreference -Value ([System.Management.Automation.ActionPreference]::Stop) -Option Constant -Force
    & $Script:CommandTable.'New-Variable' -Name InformationPreference -Value ([System.Management.Automation.ActionPreference]::Continue) -Option Constant -Force
    & $Script:CommandTable.'New-Variable' -Name ProgressPreference -Value ([System.Management.Automation.ActionPreference]::SilentlyContinue) -Option Constant -Force

    # Ensure module operates under the strictest of conditions.
    & $Script:CommandTable.'Set-StrictMode' -Version 3

    # Store build information pertaining to this module's state.
    & $Script:CommandTable.'New-Variable' -Name Module -Option Constant -Force -Value ([ordered]@{
            Manifest = & $Script:CommandTable.'Import-LocalizedData' -BaseDirectory $PSScriptRoot -FileName 'PSAppDeployToolkit.WinGet.psd1'
            Compiled = $MyInvocation.MyCommand.Name.Equals('PSAppDeployToolkit.WinGet.psm1')
        }).AsReadOnly()

    # Remove any previous functions that may have been defined.
    if ($Module.Compiled)
    {
        & $Script:CommandTable.'New-Variable' -Name FunctionPaths -Option Constant -Value ($MyInvocation.MyCommand.ScriptBlock.Ast.EndBlock.Statements | & { process { if ($_ -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return "Microsoft.PowerShell.Core\Function::$($_.Name)" } } })
        & $Script:CommandTable.'Remove-Item' -LiteralPath $FunctionPaths -Force -ErrorAction Ignore
    }

    # Define enum for all known WinGet exit codes.
    enum ADTWinGetExitCode
    {
        INTERNAL_ERROR = -1978335231
        INVALID_CL_ARGUMENTS = -1978335230
        COMMAND_FAILED = -1978335229
        MANIFEST_FAILED = -1978335228
        CTRL_SIGNAL_RECEIVED = -1978335227
        SHELLEXEC_INSTALL_FAILED = -1978335226
        UNSUPPORTED_MANIFESTVERSION = -1978335225
        DOWNLOAD_FAILED = -1978335224
        CANNOT_WRITE_TO_UPLEVEL_INDEX = -1978335223
        INDEX_INTEGRITY_COMPROMISED = -1978335222
        SOURCES_INVALID = -1978335221
        SOURCE_NAME_ALREADY_EXISTS = -1978335220
        INVALID_SOURCE_TYPE = -1978335219
        PACKAGE_IS_BUNDLE = -1978335218
        SOURCE_DATA_MISSING = -1978335217
        NO_APPLICABLE_INSTALLER = -1978335216
        INSTALLER_HASH_MISMATCH = -1978335215
        SOURCE_NAME_DOES_NOT_EXIST = -1978335214
        SOURCE_ARG_ALREADY_EXISTS = -1978335213
        NO_APPLICATIONS_FOUND = -1978335212
        NO_SOURCES_DEFINED = -1978335211
        MULTIPLE_APPLICATIONS_FOUND = -1978335210
        NO_MANIFEST_FOUND = -1978335209
        EXTENSION_PUBLIC_FAILED = -1978335208
        COMMAND_REQUIRES_ADMIN = -1978335207
        SOURCE_NOT_SECURE = -1978335206
        MSSTORE_BLOCKED_BY_POLICY = -1978335205
        MSSTORE_APP_BLOCKED_BY_POLICY = -1978335204
        EXPERIMENTAL_FEATURE_DISABLED = -1978335203
        MSSTORE_INSTALL_FAILED = -1978335202
        COMPLETE_INPUT_BAD = -1978335201
        YAML_INIT_FAILED = -1978335200
        YAML_INVALID_MAPPING_KEY = -1978335199
        YAML_DUPLICATE_MAPPING_KEY = -1978335198
        YAML_INVALID_OPERATION = -1978335197
        YAML_DOC_BUILD_FAILED = -1978335196
        YAML_INVALID_EMITTER_STATE = -1978335195
        YAML_INVALID_DATA = -1978335194
        LIBYAML_ERROR = -1978335193
        MANIFEST_VALIDATION_WARNING = -1978335192
        MANIFEST_VALIDATION_FAILURE = -1978335191
        INVALID_MANIFEST = -1978335190
        UPDATE_NOT_APPLICABLE = -1978335189
        UPDATE_ALL_HAS_FAILURE = -1978335188
        INSTALLER_SECURITY_CHECK_FAILED = -1978335187
        DOWNLOAD_SIZE_MISMATCH = -1978335186
        NO_UNINSTALL_INFO_FOUND = -1978335185
        EXEC_UNINSTALL_COMMAND_FAILED = -1978335184
        ICU_BREAK_ITERATOR_ERROR = -1978335183
        ICU_CASEMAP_ERROR = -1978335182
        ICU_REGEX_ERROR = -1978335181
        IMPORT_INSTALL_FAILED = -1978335180
        NOT_ALL_PACKAGES_FOUND = -1978335179
        JSON_INVALID_FILE = -1978335178
        SOURCE_NOT_REMOTE = -1978335177
        UNSUPPORTED_RESTSOURCE = -1978335176
        RESTSOURCE_INVALID_DATA = -1978335175
        BLOCKED_BY_POLICY = -1978335174
        RESTAPI_INTERNAL_ERROR = -1978335173
        RESTSOURCE_INVALID_URL = -1978335172
        RESTAPI_UNSUPPORTED_MIME_TYPE = -1978335171
        RESTSOURCE_INVALID_VERSION = -1978335170
        SOURCE_DATA_INTEGRITY_FAILURE = -1978335169
        STREAM_READ_FAILURE = -1978335168
        PACKAGE_AGREEMENTS_NOT_ACCEPTED = -1978335167
        PROMPT_INPUT_ERROR = -1978335166
        UNSUPPORTED_SOURCE_REQUEST = -1978335165
        RESTAPI_ENDPOINT_NOT_FOUND = -1978335164
        SOURCE_OPEN_FAILED = -1978335163
        SOURCE_AGREEMENTS_NOT_ACCEPTED = -1978335162
        CUSTOMHEADER_EXCEEDS_MAXLENGTH = -1978335161
        MISSING_RESOURCE_FILE = -1978335160
        MSI_INSTALL_FAILED = -1978335159
        INVALID_MSIEXEC_ARGUMENT = -1978335158
        FAILED_TO_OPEN_ALL_SOURCES = -1978335157
        DEPENDENCIES_VALIDATION_FAILED = -1978335156
        MISSING_PACKAGE = -1978335155
        INVALID_TABLE_COLUMN = -1978335154
        UPGRADE_VERSION_NOT_NEWER = -1978335153
        UPGRADE_VERSION_UNKNOWN = -1978335152
        ICU_CONVERSION_ERROR = -1978335151
        PORTABLE_INSTALL_FAILED = -1978335150
        PORTABLE_REPARSE_POINT_NOT_SUPPORTED = -1978335149
        PORTABLE_PACKAGE_ALREADY_EXISTS = -1978335148
        PORTABLE_SYMLINK_PATH_IS_DIRECTORY = -1978335147
        INSTALLER_PROHIBITS_ELEVATION = -1978335146
        PORTABLE_UNINSTALL_FAILED = -1978335145
        ARP_VERSION_VALIDATION_FAILED = -1978335144
        UNSUPPORTED_ARGUMENT = -1978335143
        BIND_WITH_EMBEDDED_NULL = -1978335142
        NESTEDINSTALLER_NOT_FOUND = -1978335141
        EXTRACT_ARCHIVE_FAILED = -1978335140
        NESTEDINSTALLER_INVALID_PATH = -1978335139
        PINNED_CERTIFICATE_MISMATCH = -1978335138
        INSTALL_LOCATION_REQUIRED = -1978335137
        ARCHIVE_SCAN_FAILED = -1978335136
        PACKAGE_ALREADY_INSTALLED = -1978335135
        PIN_ALREADY_EXISTS = -1978335134
        PIN_DOES_NOT_EXIST = -1978335133
        CANNOT_OPEN_PINNING_INDEX = -1978335132
        MULTIPLE_INSTALL_FAILED = -1978335131
        MULTIPLE_UNINSTALL_FAILED = -1978335130
        NOT_ALL_QUERIES_FOUND_SINGLE = -1978335129
        PACKAGE_IS_PINNED = -1978335128
        PACKAGE_IS_STUB = -1978335127
        APPTERMINATION_RECEIVED = -1978335126
        DOWNLOAD_DEPENDENCIES = -1978335125
        DOWNLOAD_COMMAND_PROHIBITED = -1978335124
        SERVICE_UNAVAILABLE = -1978335123
        RESUME_ID_NOT_FOUND = -1978335122
        CLIENT_VERSION_MISMATCH = -1978335121
        INVALID_RESUME_STATE = -1978335120
        CANNOT_OPEN_CHECKPOINT_INDEX = -1978335119
        RESUME_LIMIT_EXCEEDED = -1978335118
        INVALID_AUTHENTICATION_INFO = -1978335117
        AUTHENTICATION_TYPE_NOT_SUPPORTED = -1978335116
        AUTHENTICATION_FAILED = -1978335115
        AUTHENTICATION_INTERACTIVE_REQUIRED = -1978335114
        AUTHENTICATION_CANCELLED_BY_USER = -1978335113
        AUTHENTICATION_INCORRECT_ACCOUNT = -1978335112
        NO_REPAIR_INFO_FOUND = -1978335111
        REPAIR_NOT_APPLICABLE = -1978335110
        EXEC_REPAIR_FAILED = -1978335109
        REPAIR_NOT_SUPPORTED = -1978335108
        ADMIN_CONTEXT_REPAIR_PROHIBITED = -1978335107
        SQLITE_CONNECTION_TERMINATED = -1978335106
        DISPLAYCATALOG_API_FAILED = -1978335105
        NO_APPLICABLE_DISPLAYCATALOG_PACKAGE = -1978335104
        SFSCLIENT_API_FAILED = -1978335103
        NO_APPLICABLE_SFSCLIENT_PACKAGE = -1978335102
        LICENSING_API_FAILED = -1978335101
        INSTALL_PACKAGE_IN_USE = -1978334975
        INSTALL_INSTALL_IN_PROGRESS = -1978334974
        INSTALL_FILE_IN_USE = -1978334973
        INSTALL_MISSING_DEPENDENCY = -1978334972
        INSTALL_DISK_FULL = -1978334971
        INSTALL_INSUFFICIENT_MEMORY = -1978334970
        INSTALL_NO_NETWORK = -1978334969
        INSTALL_CONTACT_SUPPORT = -1978334968
        INSTALL_REBOOT_REQUIRED_TO_FINISH = -1978334967
        INSTALL_REBOOT_REQUIRED_FOR_INSTALL = -1978334966
        INSTALL_REBOOT_INITIATED = -1978334965
        INSTALL_CANCELLED_BY_USER = -1978334964
        INSTALL_ALREADY_INSTALLED = -1978334963
        INSTALL_DOWNGRADE = -1978334962
        INSTALL_BLOCKED_BY_POLICY = -1978334961
        INSTALL_DEPENDENCIES = -1978334960
        INSTALL_PACKAGE_IN_USE_BY_APPLICATION = -1978334959
        INSTALL_INVALID_PARAMETER = -1978334958
        INSTALL_SYSTEM_NOT_SUPPORTED = -1978334957
        INSTALL_UPGRADE_NOT_SUPPORTED = -1978334956
        INVALID_CONFIGURATION_FILE = -1978286079
        INVALID_YAML = -1978286078
        INVALID_FIELD_TYPE = -1978286077
        UNKNOWN_CONFIGURATION_FILE_VERSION = -1978286076
        SET_APPLY_FAILED = -1978286075
        DUPLICATE_IDENTIFIER = -1978286074
        MISSING_DEPENDENCY = -1978286073
        DEPENDENCY_UNSATISFIED = -1978286072
        ASSERTION_FAILED = -1978286071
        MANUALLY_SKIPPED = -1978286070
        WARNING_NOT_ACCEPTED = -1978286069
        SET_DEPENDENCY_CYCLE = -1978286068
        INVALID_FIELD_VALUE = -1978286067
        MISSING_FIELD = -1978286066
        TEST_FAILED = -1978286065
        TEST_NOT_RUN = -1978286064
        GET_FAILED = -1978286063
        UNIT_NOT_INSTALLED = -1978285823
        UNIT_NOT_FOUND_REPOSITORY = -1978285822
        UNIT_MULTIPLE_MATCHES = -1978285821
        UNIT_INVOKE_GET = -1978285820
        UNIT_INVOKE_TEST = -1978285819
        UNIT_INVOKE_SET = -1978285818
        UNIT_MODULE_CONFLICT = -1978285817
        UNIT_IMPORT_MODULE = -1978285816
        UNIT_INVOKE_INVALID_RESULT = -1978285815
        UNIT_SETTING_CONFIG_ROOT = -1978285808
        UNIT_IMPORT_MODULE_ADMIN = -1978285807
        NOT_SUPPORTED_BY_PROCESSOR = -1978285806
    }
}
catch
{
    throw
}


#-----------------------------------------------------------------------------
#
# MARK: Convert-ADTArrayToRegexCaptureGroup
#
#-----------------------------------------------------------------------------

function Convert-ADTArrayToRegexCaptureGroup
{
    <#
    .SYNOPSIS
        Accepts one or more strings and converts the results into a regex capture group.

    .DESCRIPTION
        This function accepts one or more strings and converts the results into a regex capture group.

    .PARAMETER InputObject
        One or more string objects to parse and return as a regex capture group.

    .INPUTS
        System.String. Convert-ADTArrayToRegexCaptureGroup accepts accepts one or more string objects for returning as a regex capture group.

    .OUTPUTS
        System.String. Convert-ADTArrayToRegexCaptureGroup returns a string object of the concatenated input as a regex capture group.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [System.String[]]$InputObject
    )

    begin
    {
        # Open collector to hold escaped and parsed values.
        $items = [System.Collections.Specialized.StringCollection]::new()
    }

    process
    {
        # Process incoming data and store in the collector.
        $null = $InputObject | & {
            process
            {
                if (![System.String]::IsNullOrWhiteSpace($_))
                {
                    $items.Add([System.Text.RegularExpressions.Regex]::Escape($_))
                }
            }
        }
    }

    end
    {
        # Return collected strings as a regex capture group.
        if ($items.Count) { return "($($items -join '|'))" }
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Convert-ADTFunctionParamsToArgArray
#
#-----------------------------------------------------------------------------

function Convert-ADTFunctionParamsToArgArray
{
    <#
    .SYNOPSIS
        Converts the provided parameter metadata into an argument array for applications, with presets for MSI, Dell Command | Update, and WinGet.

    .DESCRIPTION
        This function accepts parameter metadata and with this, the parameter set name and a help message tag, converts the parameters into an array of arguments for applications.

        There are presets available for MSI, Dell Command | Update, WinGet, and PnpUtil, or a completely custom arrangement can be accomodated.

    .PARAMETER BoundParameters
        A hashtable of parameters to process.

    .PARAMETER Invocation
        The script or function's InvocationInfo ($MyInvocation) to process.

    .PARAMETER ParameterSetName
        The ParameterSetName to use as a filter against the Invocation's parameters.

    .PARAMETER HelpMessage
        The HelpMessage field to use as a filter against the Invocation's parameters.

    .PARAMETER Exclude
        One or more parameter names to exclude from the results.

    .PARAMETER Ordered
        Instructs that the returned parameters are in the exact order they're read from the BoundParameters or Invocation.

    .PARAMETER Preset
        The preset of which to use when generating an argument array. Current presets are MSI, Dell Command | Update, WinGet, PnpUtil, and PowerShell.

    .PARAMETER ArgValSeparator
        For non-preset modes, the separator between an argument's name and value.

    .PARAMETER ArgPrefix
        For non-preset modes, the prefix to apply to an argument's name.

    .PARAMETER ValueWrapper
        For non-preset modes, what, if anything, to use as characters to wrap around the value (e.g. --ArgName="Value").

    .PARAMETER MultiValDelimiter
        For non-preset modes, how to handle parameters where their value is an array of data.

    .INPUTS
        System.Collections.IDictionary. Convert-ADTFunctionParamsToArgArray can accept one or more IDictionary objects for processing.
        System.Management.Automation.InvocationInfo. Convert-ADTFunctionParamsToArgArray can accept one or more InvocationInfo objects for processing.

    .OUTPUTS
        System.String[]. Convert-ADTFunctionParamsToArgArray returns one or more string objects representing the converted parameters.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ParameterSetName', Justification = "This parameter is used within delegates that PSScriptAnalyzer has no visibility of. See https://github.com/PowerShell/PSScriptAnalyzer/issues/1472 for more details.")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'HelpMessage', Justification = "This parameter is used within delegates that PSScriptAnalyzer has no visibility of. See https://github.com/PowerShell/PSScriptAnalyzer/issues/1472 for more details.")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Ordered', Justification = "This parameter is used within delegates that PSScriptAnalyzer has no visibility of. See https://github.com/PowerShell/PSScriptAnalyzer/issues/1472 for more details.")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MultiValDelimiter', Justification = "This parameter is used within delegates that PSScriptAnalyzer has no visibility of. See https://github.com/PowerShell/PSScriptAnalyzer/issues/1472 for more details.")]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'BoundParametersPreset', ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = 'BoundParametersCustom', ValueFromPipeline = $true)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]$BoundParameters,

        [Parameter(Mandatory = $true, ParameterSetName = 'InvocationPreset', HelpMessage = 'Primary parameter', ValueFromPipeline = $true)]
        [Parameter(Mandatory = $true, ParameterSetName = 'InvocationCustom', HelpMessage = 'Primary parameter', ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.InvocationInfo]$Invocation,

        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationPreset', HelpMessage = 'Primary parameter')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationCustom', HelpMessage = 'Primary parameter')]
        [ValidateNotNullOrEmpty()]
        [System.String]$ParameterSetName,

        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationPreset', HelpMessage = 'Primary parameter')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationCustom', HelpMessage = 'Primary parameter')]
        [ValidateNotNullOrEmpty()]
        [System.String]$HelpMessage,

        [Parameter(Mandatory = $false, ParameterSetName = 'BoundParametersPreset', HelpMessage = 'Primary parameter')]
        [Parameter(Mandatory = $false, ParameterSetName = 'BoundParametersCustom', HelpMessage = 'Primary parameter')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationPreset', HelpMessage = 'Primary parameter')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationCustom', HelpMessage = 'Primary parameter')]
        [ValidateNotNullOrEmpty()]
        [System.String[]]$Exclude,

        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationPreset', HelpMessage = 'Primary parameter')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationCustom', HelpMessage = 'Primary parameter')]
        [System.Management.Automation.SwitchParameter]$Ordered,

        [Parameter(Mandatory = $true, ParameterSetName = 'BoundParametersPreset')]
        [Parameter(Mandatory = $true, ParameterSetName = 'InvocationPreset')]
        [ValidateSet('MSI', 'WinGet', 'DellCommandUpdate', 'PnpUtil', 'PowerShell')]
        [System.String]$Preset,

        [Parameter(Mandatory = $true, ParameterSetName = 'BoundParametersCustom')]
        [Parameter(Mandatory = $true, ParameterSetName = 'InvocationCustom')]
        [ValidateSet(' ', '=', "`n")]
        [System.String]$ArgValSeparator,

        [Parameter(Mandatory = $false, ParameterSetName = 'BoundParametersCustom')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationCustom')]
        [ValidateSet('-', '--', '/')]
        [System.String]$ArgPrefix,

        [Parameter(Mandatory = $false, ParameterSetName = 'BoundParametersCustom')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationCustom')]
        [ValidateSet("'", '"')]
        [System.String]$ValueWrapper,

        [Parameter(Mandatory = $false, ParameterSetName = 'BoundParametersPreset')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationPreset')]
        [Parameter(Mandatory = $false, ParameterSetName = 'BoundParametersCustom')]
        [Parameter(Mandatory = $false, ParameterSetName = 'InvocationCustom')]
        [ValidateSet(',', '|')]
        [System.String]$MultiValDelimiter = ','
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        # Set up regex for properly trimming lines. Yes, reflection == long lines.
        $invalidends = "$($MyInvocation.MyCommand.Parameters.Values.GetEnumerator().Where({$_.Name.Equals('ArgValSeparator')}).Attributes.Where({$_ -is [System.Management.Automation.ValidateSetAttribute]}).ValidValues | & $Script:CommandTable.'Convert-ADTArrayToRegexCaptureGroup')+$"
        $nullvalues = "\s$($MyInvocation.MyCommand.Parameters.Values.GetEnumerator().Where({$_.Name.Equals('ValueWrapper')}).Attributes.Where({$_ -is [System.Management.Automation.ValidateSetAttribute]}).ValidValues | & $Script:CommandTable.'Convert-ADTArrayToRegexCaptureGroup'){2}$"

        # Set up the string for formatting.
        $string = switch ($Preset)
        {
            MSI { "{0}=`"{1}`""; break }
            WinGet { "--{0}`n{1}"; break }
            DellCommandUpdate { "-{0}={1}"; break }
            PnpUtil { "/{0}`n{1}"; break }
            PowerShell { "-{0}`n`"{1}`""; break }
            default { "$($ArgPrefix){0}$($ArgValSeparator)$($ValueWrapper){1}$($ValueWrapper)"; break }
        }

        # Persistent scriptblocks stored in RAM for Convert-ADTFunctionParamsToArgArray.
        $script = if ($Preset -eq 'MSI')
        {
            {
                # For switches, we want to convert the $true/$false into 1/0 respectively.
                if ($_.Value -isnot [System.Management.Automation.SwitchParameter])
                {
                    [System.String]::Format($string, $_.Key.ToUpper(), $_.Value -join $MultiValDelimiter).Split("`n").Trim()
                }
                else
                {
                    [System.String]::Format($string, $_.Key.ToUpper(), [System.UInt32][System.Boolean]$_.Value).Split("`n").Trim()
                }
            }
        }
        else
        {
            {
                # For switches, we only want true switches, and we drop the $true value entirely.
                $notswitch = $_.Value -isnot [System.Management.Automation.SwitchParameter]
                if ($notswitch -or $_.Value)
                {
                    $name = if ($Preset -eq 'PowerShell') { $_.Key } else { $_.Key.ToLower() }
                    $value = if ($notswitch) { $_.Value -join $MultiValDelimiter }
                    [System.String]::Format($string, $name, $value).Split("`n").Trim() -replace $nullvalues
                }
            }
        }

        # Amend exclusions with default parameter values.
        $Exclude = $(
            $Exclude
            [System.Management.Automation.PSCmdlet]::CommonParameters
            [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        )
    }

    process
    {
        try
        {
            try
            {
                # If we're processing an invocation, get its bound parameters as required.
                if ($Invocation)
                {
                    $bpdvParams = & $Script:CommandTable.'Get-ADTBoundParametersAndDefaultValues' -Invocation $MyInvocation -HelpMessage 'Primary parameter'
                    $BoundParameters = & $Script:CommandTable.'Get-ADTBoundParametersAndDefaultValues' @bpdvParams
                }

                # Process the parameters into an argument array and return to the caller.
                return $BoundParameters.GetEnumerator().Where({ $Exclude -notcontains $_.Key }).ForEach($script) -replace $invalidends | & $Script:CommandTable.'Where-Object' { ![System.String]::IsNullOrWhiteSpace($_) }
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to convert the provided input to an argument array."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Convert-ADTWinGetQueryOutput
#
#-----------------------------------------------------------------------------

function Convert-ADTWinGetQueryOutput
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]$WinGetOutput
    )

    # Test whether the provided output is convertable.
    $wingetDivider = $($WinGetOutput -match '^-+$'); if (!$wingetDivider)
    {
        $naerParams = @{
            Exception = [System.IO.InvalidDataException]::new("The provided WinGet output is not valid query output. Provided WinGet output was:`n$([System.String]::Join("`n", $WinGetOutput))")
            Category = [System.Management.Automation.ErrorCategory]::InvalidData
            ErrorId = 'WinGetQueryOutputInvalid'
            TargetObject = $WinGetOutput
            RecommendedAction = "Please review the WinGet output, then try again."
        }
        $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
    }

    # Process each collected line into an object.
    try
    {
        $WinGetOutput[($WinGetOutput.IndexOf($wingetDivider) - 1)..($WinGetOutput.Count - 1)].Trim() | & {
            begin
            {
                # Define variables for heading data that'll be the first line via the pipe.
                $listHeading = $headIndices = $null
            }

            process
            {
                if ($_ -notmatch '^\w+')
                {
                    return
                }

                # Use our first valid line to set up the keys for each property.
                if (!$listHeading)
                {
                    # Get all headings and the indices from the output.
                    $listHeading = $_ -split '\s+'
                    $headIndices = $($listHeading | & { process { $args[0].IndexOf($_) } } $_; 10000)
                    return
                }

                # Establish hashtable to hold contents we're converting.
                $obj = [ordered]@{}

                # Begin conversion and return object to the pipeline.
                for ($i = 0; $i -lt $listHeading.Length; $i++)
                {
                    $thisi = [System.Math]::Min($headIndices[$i], $_.Length)
                    $nexti = [System.Math]::Min($headIndices[$i + 1], $_.Length)
                    $value = $_.Substring($thisi, $nexti - $thisi).Trim()
                    $obj.Add($listHeading[$i], $(if (![System.String]::IsNullOrWhiteSpace($value)) { $value }))
                }
                return [pscustomobject]$obj
            }
        }
    }
    catch
    {
        $naerParams = @{
            Exception = [System.IO.InvalidDataException]::new("Failed to parse provided WinGet output. Provided WinGet output was:`n$([System.String]::Join("`n", $WinGetOutput))", $_.Exception)
            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
            ErrorId = 'WinGetQueryOutputParseFailure'
            TargetObject = $WinGetOutput
            RecommendedAction = "Please review the WinGet output, then try again."
        }
        $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTGitHubReleaseAssetUri
#
#-----------------------------------------------------------------------------

function Get-ADTGitHubReleaseAssetUri
{
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'FilePattern', Justification = "This parameter is used within delegates that PSScriptAnalyzer has no visibility of. See https://github.com/PowerShell/PSScriptAnalyzer/issues/1472 for more details.")]
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [OutputType([System.Uri])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Account,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Repository,

        [Parameter(Mandatory = $true, ParameterSetName = 'FilePattern')]
        [ValidateNotNullOrEmpty()]
        [System.String]$FilePattern,

        [Parameter(Mandatory = $false, ParameterSetName = 'FilePattern')]
        [System.Management.Automation.SwitchParameter]$Regex
    )

    # Get the list of URLs from GitHub's API.
    $links = (& $Script:CommandTable.'Invoke-RestMethod' -UseBasicParsing -Uri "https://api.github.com/repos/$Account/$Repository/releases/latest" -Verbose:$false).assets.browser_download_url

    # Find the one that matches the pattern and confirm we have a singular result.
    if ($PSCmdlet.ParameterSetName.Equals('FilePattern'))
    {
        if (!(($link = $links | & $Script:CommandTable.'Where-Object' { $_.Split('/').Where($(if ($Regex) { { $_ -match $FilePattern } } else { { $_ -like $FilePattern } })) }) | & $Script:CommandTable.'Measure-Object').Count.Equals(1))
        {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new("The match against the provided file pattern returned an invalid result."),
                    'UriPatternMatchInvalidResult',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $link
                ))
        }
        return [System.Uri]$link
    }
    return $links
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTRedirectedUri
#
#-----------------------------------------------------------------------------

function Get-ADTRedirectedUri
{
    <#
    .SYNOPSIS
        Returns the resolved URI from the provided permalink.

    .DESCRIPTION
        This function gets the resolved/redirected URI from the provided input and returns it to the caller.

    .PARAMETER Uri
        The URL that requires redirection resolution.

    .PARAMETER Headers
        Any headers that need to be provided for URI redirection resolution.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        System.Uri

        Get-ADTRedirectedUri returns a Uri of the resolved/redirected URI.

    .EXAMPLE
        Get-ADTRedirectedUri -Uri https://aka.ms/getwinget

        Returns the absolute URI for the specified short link, e.g. https://github.com/microsoft/winget-cli/releases/download/v1.8.1911/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    [OutputType([System.Uri])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (![System.Uri]::IsWellFormedUriString($_.AbsoluteUri, [System.UriKind]::Absolute))
                {
                    $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTValidateScriptErrorRecord' -ParameterName Uri -ProvidedValue $_ -ExceptionMessage 'The specified input is not a valid Uri.'))
                }
                return !!$_
            })]
        [System.Uri]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.IDictionary]$Headers = @{ Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' }
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                # Create web request.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Retrieving the redirected URI for [$Uri]."
                $webReq = [System.Net.WebRequest]::Create($Uri)
                $webReq.AllowAutoRedirect = $false
                $Headers.GetEnumerator() | & { process { $webReq.($_.Key) = $_.Value } }

                # Get a response and close it out.
                $reqRes = $webReq.GetResponse()
                $resLoc = $reqRes.GetResponseHeader('Location')
                $reqRes.Close()

                # If $resLoc is empty, return the provided URI so something is returned to the caller.
                if (![System.String]::IsNullOrWhiteSpace($resLoc))
                {
                    $Uri = $resLoc
                }

                # Return the redirected URI to the caller.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Retrieved redirected URI [$Uri] from the provided input."
                return $Uri
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to determine the redirected URI for [$Uri]."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTUriFileName
#
#-----------------------------------------------------------------------------

function Get-ADTUriFileName
{
    <#
    .SYNOPSIS
        Returns the filename of the provided URI.

    .DESCRIPTION
        This function gets the filename of the provided URI from the provided input and returns it to the caller.

    .PARAMETER Uri
        The URL that to retrieve the filename from.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        System.String

        Get-ADTUriFileName returns a string value of the URI's filename.

    .EXAMPLE
        Get-ADTUriFileName -Uri https://aka.ms/getwinget

        Returns the filename for the specified URI, redirected or otherwise. e.g. Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (![System.Uri]::IsWellFormedUriString($_.AbsoluteUri, [System.UriKind]::Absolute))
                {
                    $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTValidateScriptErrorRecord' -ParameterName Uri -ProvidedValue $_ -ExceptionMessage 'The specified input is not a valid Uri.'))
                }
                return !!$_
            })]
        [System.Uri]$Uri
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                # Re-write the URI to factor in any redirections.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Retrieving the file name for URI [$Uri]."
                $Uri = & $Script:CommandTable.'Get-ADTRedirectedUri' -Uri $Uri

                # Create web request.
                $webReq = [System.Net.WebRequest]::Create($Uri)
                $webReq.AllowAutoRedirect = $false
                $webReq.Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'

                # Get a response and close it out.
                $reqRes = $webReq.GetResponse()
                $resCnt = $reqRes.GetResponseHeader('Content-Disposition')
                $reqRes.Close()

                # If $resCnt is empty, the provided URI likely has the filename in it.
                $filename = if (!$resCnt.Contains('filename'))
                {
                    & $Script:CommandTable.'Remove-ADTInvalidFileNameChars' -Name $Uri.ToString().Split('/')[-1]
                }
                else
                {
                    & $Script:CommandTable.'Remove-ADTInvalidFileNameChars' -Name $resCnt.Split(';').Trim().Where({ $_.StartsWith('filename=') }).Split('=')[-1]
                }

                # Return the determined filename to the caller.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Resolved filename [$filename] from the provided URI."
                return $filename
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to determine the filename for URI [$Uri]."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetHashMismatchArgumentList
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetHashMismatchArgumentList
{
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = "This function is appropriately named and we don't need PSScriptAnalyzer telling us otherwise.")]
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject]$Manifest,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject]$Installer,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$FilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$LogFile
    )

    # Internal filter to process manifest install switches.
    filter Get-ADTWinGetManifestInstallSwitches
    {
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = "This function is appropriately named and we don't need PSScriptAnalyzer telling us otherwise.")]
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [ValidateNotNullOrEmpty()]
            [pscustomobject]$InputObject,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [System.String]$Type
        )

        # Test whether the piped object has InstallerSwitches and it's not null.
        if (($InputObject.PSObject.Properties.Name -notcontains 'InstallerSwitches') -or ($null -eq $InputObject.InstallerSwitches))
        {
            return
        }

        # Return the requested type. This will be null if its not available.
        return $InputObject.InstallerSwitches.PSObject.Properties | & $Script:CommandTable.'Where-Object' { $_.Name -eq $Type } | & $Script:CommandTable.'Select-Object' -ExpandProperty Value
    }

    # Internal function to return default install switches based on type.
    function Get-ADTDefaultKnownSwitches
    {
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = "This function is appropriately named and we don't need PSScriptAnalyzer telling us otherwise.")]
        [CmdletBinding()]
        [OutputType([System.String])]
        param
        (
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [System.String]$InstallerType
        )

        # Switch on the installer type and return an array of strings for the args.
        switch -Regex ($InstallerType)
        {
            '^(Burn|Wix|Msi)$'
            {
                "/quiet"
                "/norestart"
                "/log `"$LogFile`""
                break
            }
            '^Nullsoft$'
            {
                "/S"
                break
            }
            '^Inno$'
            {
                "/VERYSILENT"
                "/NORESTART"
                "/LOG=`"$LogFile`""
                break
            }
            default
            {
                $naerParams = @{
                    Exception = [System.InvalidOperationException]::new("The installer type '$_' is unsupported.")
                    Category = [System.Management.Automation.ErrorCategory]::InvalidData
                    ErrorId = 'WinGetInstallerTypeUnknown'
                    TargetObject = $_
                    RecommendedAction = "Please report the installer type to the project's maintainer for further review."
                }
                $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
            }
        }
    }

    # Add standard msiexec.exe args.
    if ($FilePath.EndsWith('msi'))
    {
        "/i `"$FilePath`""
    }

    # If we're not overriding, get silent switches from manifest and $Custom if we can.
    if (!$Override)
    {
        # Try to get switches from the installer, then the manifest, then by what the installer is, either from the installer or the manifest.
        if ($switches = $Installer | Get-ADTWinGetManifestInstallSwitches -Type Silent)
        {
            # First check the installer array for a silent switch.
            $switches
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Using Silent switches from the manifest's installer data."
        }
        elseif ($switches = $Manifest | Get-ADTWinGetManifestInstallSwitches -Type Silent)
        {
            # Fall back to the manifest itself.
            $switches
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Using Silent switches from the manifest's top level."
        }
        elseif ($instType = $Installer | & $Script:CommandTable.'Get-ADTWinGetHashMismatchInstallerType')
        {
            # We have no defined switches, try to determine switches from the installer's defined type.
            Get-ADTDefaultKnownSwitches -InstallerType $instType
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Using default switches for the manifest installer's installer type ($instType)."
        }
        elseif ($instType = $Manifest | & $Script:CommandTable.'Get-ADTWinGetHashMismatchInstallerType')
        {
            # The installer array doesn't define a type, see if the manifest itself does.
            Get-ADTDefaultKnownSwitches -InstallerType $instType
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Using default switches for the manifest's installer type ($instType)."
        }
        elseif ($switches = $Installer | Get-ADTWinGetManifestInstallSwitches -Type SilentWithProgress)
        {
            # We're shit out of luck... circle back and see if we have _anything_ we can use.
            $switches
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Using SilentWithProgress switches from the manifest's installer data."
        }
        elseif ($switches = $Manifest | Get-ADTWinGetManifestInstallSwitches -Type SilentWithProgress)
        {
            # Last-ditch effort. It's this or bust.
            $switches
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Using SilentWithProgress switches from the manifest's top level."
        }
        else
        {
            $naerParams = @{
                Exception = [System.InvalidOperationException]::new("Unable to determine how to silently install the application.")
                Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                ErrorId = 'WinGetInstallerTypeUnknown'
                TargetObject = $PSBoundParameters
                RecommendedAction = "Please report this issue to the project's maintainer for further review."
            }
            $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
        }

        # Append any custom switches the caller has provided.
        if ($Custom)
        {
            $Custom
        }
    }
    else
    {
        # Override replaces anything the manifest provides.
        $Override
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetHashMismatchDownload
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetHashMismatchDownload
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject]$Installer
    )

    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Downloading [$($Installer.InstallerUrl)], please wait..."
    try
    {
        # Download WinGet app and store path to binary.
        $wgFilePath = "$([System.IO.Directory]::CreateDirectory("$([System.IO.Path]::GetTempPath())$(& $Script:CommandTable.'Get-Random')").FullName)\$(& $Script:CommandTable.'Get-ADTUriFileName' -Uri $Installer.InstallerUrl)"
        & $Script:CommandTable.'Invoke-ADTWebDownload' -Uri $Installer.InstallerUrl -OutFile $wgFilePath

        # If downloaded file is a zip, we need to expand it and modify our file path before returning.
        if ($wgFilePath -match 'zip$')
        {
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Downloaded installer is a zip file, expanding its contents."
            & $Script:CommandTable.'Expand-Archive' -LiteralPath $wgFilePath -DestinationPath ([System.IO.Path]::GetTempPath()) -Force
            $wgFilePath = "$([System.IO.Path]::GetTempPath())$($Installer.NestedInstallerFiles.RelativeFilePath)"
        }
        return $wgFilePath
    }
    catch
    {
        $naerParams = @{
            Exception = [System.InvalidOperationException]::new("Failed to download [$($Installer.InstallerUrl)].", $_.Exception)
            Category = [System.Management.Automation.ErrorCategory]::InvalidOperation
            ErrorId = 'WinGetInstallerDownloadFailure'
            RecommendedAction = "Please verify the installer's URI is valid, then try again."
        }
        $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetHashMismatchExitCodes
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetHashMismatchExitCodes
{
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = "This function is appropriately named and we don't need PSScriptAnalyzer telling us otherwise.")]
    [CmdletBinding()]
    [OutputType([System.Int32])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject]$Manifest,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject]$Installer,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$FilePath
    )

    # Try to get switches from the installer, then the manifest, then by whatever known defaults we have.
    if ($Installer.PSObject.Properties.Name.Contains('InstallerSuccessCodes'))
    {
        return $Installer.InstallerSuccessCodes
    }
    elseif ($Manifest.PSObject.Properties.Name.Contains('InstallerSuccessCodes'))
    {
        return $Manifest.InstallerSuccessCodes
    }
    else
    {
        # Zero is valid for everything.
        0

        # Factor in two msiexec.exe-specific exit codes.
        if ($FilePath.EndsWith('msi'))
        {
            1641  # Machine needs immediate reboot.
            3010  # Reboot should be rebooted.
        }
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetHashMismatchInstaller
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetHashMismatchInstaller
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject]$Manifest,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Scope,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Architecture,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$InstallerType
    )

    # Get correct installation data from the manifest based on scope and system architecture.
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Processing installer metadata from the package manifest."
    $nativeArch = $Manifest.Installers.Architecture -contains $Script:ADT.SystemArchitecture
    $cultureName = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    $wgInstaller = $Manifest.Installers | & $Script:CommandTable.'Where-Object' {
        (!$_.PSObject.Properties.Name.Contains('Scope') -or ($_.Scope -eq $Scope)) -and
        (!$_.PSObject.Properties.Name.Contains('InstallerLocale') -or ($_.InstallerLocale -eq $cultureName)) -and
        (!$InstallerType -or (($instType = $_ | & $Script:CommandTable.'Get-ADTWinGetHashMismatchInstallerType') -and ($instType -eq $InstallerType))) -and
        ($_.Architecture.Equals($Architecture) -or ($haveArch = $_.Architecture -eq $Script:ADT.SystemArchitecture) -or (!$haveArch -and !$nativeArch))
    }

    # Validate the output. The yoda notation is to keep PSScriptAnalyzer happy.
    if ($null -eq $wgInstaller)
    {
        # We found nothing and therefore can't continue.
        $naerParams = @{
            Exception = [System.InvalidOperationException]::new("Error occurred while processing installer metadata from the package's manifest.")
            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
            ErrorId = 'WinGetManifestInstallerResultNull'
            TargetObject = $wgInstaller
            RecommendedAction = "Please review the package's installer metadata within the manifest, then try again."
        }
        $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
    }
    elseif ($wgInstaller -is [System.Collections.IEnumerable])
    {
        # We got multiple values. Get all unique installer types from the metadata and check for uniqueness.
        if (!$wgInstaller.Count.Equals((($wgInstTypes = $wgInstaller | & $Script:CommandTable.'Get-ADTWinGetHashMismatchInstallerType' | & $Script:CommandTable.'Select-Object' -Unique) | & $Script:CommandTable.'Measure-Object').Count))
        {
            # Something's gone wrong as we've got duplicate installer types.
            $naerParams = @{
                Exception = [System.InvalidOperationException]::new("Error determining correct installer metadata from the package's manifest.")
                Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                ErrorId = 'WinGetManifestInstallerResultInconclusive'
                TargetObject = $wgInstaller
                RecommendedAction = "Please review the package's installer metadata within the manifest, then try again."
            }
            $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
        }

        # Installer types were unique, just return the first one and hope for the best.
        & $Script:CommandTable.'Write-ADTLogEntry' -Message "Found installer types ['$([System.String]::Join("', '", $wgInstTypes))']; using [$($wgInstTypes[0])] metadata."
        $wgInstaller = $wgInstaller | & $Script:CommandTable.'Where-Object' { ($_ | & $Script:CommandTable.'Get-ADTWinGetHashMismatchInstallerType').Equals($wgInstTypes[0]) }
    }

    # Return installer metadata to the caller.
    return $wgInstaller
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetHashMismatchInstallerType
#
#-----------------------------------------------------------------------------

filter Get-ADTWinGetHashMismatchInstallerType
{
    if ($_.PSObject.Properties.Name.Contains('NestedInstallerType'))
    {
        return $_.NestedInstallerType
    }
    elseif ($_.PSObject.Properties.Name.Contains('InstallerType'))
    {
        return $_.InstallerType
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetHashMismatchManifest
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetHashMismatchManifest
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Version
    )

    # Set up vars and get package manifest.
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Downloading and parsing the package manifest from GitHub."
    try
    {
        $wgUriBase = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/{0}/{1}/{2}/{3}.installer.yaml"
        $wgPkgsUri = [System.String]::Format($wgUriBase, $Id.Substring(0, 1).ToLower(), $Id.Replace('.', '/'), $Version, $Id)
        $wgPkgYaml = & $Script:CommandTable.'Invoke-RestMethod' -UseBasicParsing -Uri $wgPkgsUri -Verbose:$false
        $wgManifest = $wgPkgYaml | & $Script:CommandTable.'ConvertFrom-Yaml'
        return $wgManifest
    }
    catch
    {
        $naerParams = @{
            Exception = [System.IO.InvalidDataException]::new("Failed to download or parse the package manifest from GitHub.", $_.Exception)
            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
            ErrorId = 'WinGetManifestParseFailure'
            RecommendedAction = "Please review the package's manifest, then try again."
        }
        $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetPath
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetPath
{
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param
    (
    )

    # For the system user, get the path from Program Files directly. For some systems, we can't rely on the
    # output of Get-AppxPackage as it'll update, but Get-AppxPackage won't reflect the new path fast enough.
    $wingetPath = if ($Script:ADT.RunningAsSystem)
    {
        & $Script:CommandTable.'Get-ChildItem' -Path "$([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFiles))\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe" | & $Script:CommandTable.'Sort-Object' -Descending | & $Script:CommandTable.'Select-Object' -First 1
    }
    elseif (($wingetCommand = & $Script:CommandTable.'Get-Command' -Name winget.exe -ErrorAction Ignore))
    {
        $wingetCommand.Source
    }
    elseif ([System.IO.File]::Exists(($appxPath = "$(& $Script:CommandTable.'Get-AppxPackage' -Name Microsoft.DesktopAppInstaller -AllUsers:$Script:ADT.RunningAsSystem | & $Script:CommandTable.'Sort-Object' -Property Version -Descending | & $Script:CommandTable.'Select-Object' -ExpandProperty InstallLocation -First 1)\winget.exe")))
    {
        $appxPath
    }

    # Throw if we didn't find a WinGet path.
    if (!$wingetPath)
    {
        $naerParams = @{
            Exception = [System.IO.FileNotFoundException]::new("Failed to find a valid path to winget.exe on this system.")
            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
            ErrorId = 'MicrosoftDesktopAppInstallerVersionError'
            RecommendedAction = "Please invoke [Repair-ADTWinGetPackageManager], then try again."
        }
        $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
    }

    # Return the found path to the caller.
    return [System.IO.FileInfo]$wingetPath
}


#-----------------------------------------------------------------------------
#
# MARK: Invoke-ADTWebDownload
#
#-----------------------------------------------------------------------------

function Invoke-ADTWebDownload
{
    <#
    .SYNOPSIS
        Wraps around Invoke-WebRequest to provide logging and retry support.

    .DESCRIPTION
        This function allows callers to download files as part of a deployment with logging and retry support.

    .PARAMETER Uri
        The URL that to retrieve the file from.

    .PARAMETER OutFile
        The path of where to save the file to.

    .PARAMETER Headers
        Any headers that need to be provided for file transfer.

    .PARAMETER Sha256Hash
        An optional SHA256 reference file hash for download verification.

    .PARAMETER PassThru
        Returns the WebResponseObject object from Invoke-WebRequest.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        Microsoft.PowerShell.Commands.WebResponseObject

        Invoke-ADTWebDownload returns the results from Invoke-WebRequest if PassThru is specified.

    .EXAMPLE
        Invoke-ADTWebDownload -Uri https://aka.ms/getwinget -OutFile "$($adtSession.DirSupportFiles)\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"

        Downloads the latest WinGet installer to the SupportFiles directory.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.WebResponseObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if (![System.Uri]::IsWellFormedUriString($_.AbsoluteUri, [System.UriKind]::Absolute))
                {
                    $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTValidateScriptErrorRecord' -ParameterName Uri -ProvidedValue $_ -ExceptionMessage 'The specified input is not a valid Uri.'))
                }
                return !!$_
            })]
        [System.Uri]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$OutFile,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.IDictionary]$Headers = @{ Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' },

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Sha256Hash,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$PassThru
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                # Commence download and return the result if passing through.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Downloading $Uri."
                $iwrParams = & $Script:CommandTable.'Get-ADTBoundParametersAndDefaultValues' -Invocation $MyInvocation -Exclude Sha256Hash
                $iwrResult = & $Script:CommandTable.'Invoke-ADTCommandWithRetries' -Command $Script:CommandTable.'Invoke-WebRequest' -UseBasicParsing @iwrParams -Verbose:$false

                # Validate the hash if one was provided.
                if ($PSBoundParameters.ContainsKey('Sha256Hash') -and (($fileHash = & $Script:CommandTable.'Get-FileHash' -LiteralPath $OutFile).Hash -ne $Sha256Hash))
                {
                    $naerParams = @{
                        Exception = [System.BadImageFormatException]::new("The downloaded file has an invalid file hash of [$($fileHash.Hash)].", $OutFile)
                        Category = [System.Management.Automation.ErrorCategory]::InvalidData
                        ErrorId = 'DownloadedFileInvalid'
                        TargetObject = $fileHash
                        RecommendedAction = "Please compare the downloaded file's hash against the provided value and try again."
                    }
                    throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                }

                # Return any results from Invoke-WebRequest if we have any and we're passing through.
                if ($PassThru -and $iwrResult)
                {
                    return $iwrResult
                }
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Object ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Error downloading setup file(s) from the provided URL of [$Uri]."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Invoke-ADTWinGetDeploymentOperation
#
#-----------------------------------------------------------------------------

function Invoke-ADTWinGetDeploymentOperation
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'repair', 'uninstall', 'upgrade')]
        [System.String]$Action,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Equals', 'EqualsCaseInsensitive')]
        [System.String]$MatchOption,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Query,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Log,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Silent', 'Interactive')]
        [System.String]$Mode,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Moniker,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
                try
                {
                    return (& $Script:CommandTable.'Get-ADTWinGetSource' -Name $_ -InformationAction SilentlyContinue)
                }
                catch
                {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
            })]
        [System.String]$Source,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Version
    )

    dynamicparam
    {
        # Define parameter dictionary for returning at the end.
        $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

        # Add in parameters for specific modes.
        if ($Action -match '^(install|upgrade)$')
        {
            if ($Action -eq 'upgrade')
            {
                $paramDictionary.Add('Include-Unknown', [System.Management.Automation.RuntimeDefinedParameter]::new(
                        'Include-Unknown', [System.Management.Automation.SwitchParameter], $(
                            [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                            [System.Management.Automation.AliasAttribute]::new('IncludeUnknown')
                        )
                    ))
            }
            $paramDictionary.Add('Ignore-Security-Hash', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Ignore-Security-Hash', [System.Management.Automation.SwitchParameter], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.AliasAttribute]::new('AllowHashMismatch')
                    )
                ))
            $paramDictionary.Add('DebugHashMismatch', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'DebugHashMismatch', [System.Management.Automation.SwitchParameter], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                    )
                ))
            $paramDictionary.Add('Architecture', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Architecture', [System.String], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.ValidateSetAttribute]::new('x86', 'x64', 'arm64')
                    )
                ))
            $paramDictionary.Add('Custom', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Custom', [System.String], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.ValidateNotNullOrEmptyAttribute]::new()
                    )
                ))
            $paramDictionary.Add('Header', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Header', [System.String], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.ValidateNotNullOrEmptyAttribute]::new()
                    )
                ))
            $paramDictionary.Add('Installer-Type', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Installer-Type', [System.String], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.ValidateSetAttribute]::new('Inno', 'Wix', 'Msi', 'Nullsoft', 'Zip', 'Msix', 'Exe', 'Burn', 'MSStore', 'Portable')
                        [System.Management.Automation.AliasAttribute]::new('InstallerType')
                    )
                ))
            $paramDictionary.Add('Locale', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Locale', [System.String], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.ValidateNotNullOrEmptyAttribute]::new()
                    )
                ))
            $paramDictionary.Add('Location', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Location', [System.String], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.ValidateNotNullOrEmptyAttribute]::new()
                    )
                ))
            $paramDictionary.Add('Override', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Override', [System.String], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.ValidateNotNullOrEmptyAttribute]::new()
                    )
                ))
            $paramDictionary.Add('Skip-Dependencies', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Skip-Dependencies', [System.Management.Automation.SwitchParameter], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.AliasAttribute]::new('SkipDependencies')
                    )
                ))
        }
        if ($Action -ne 'repair')
        {
            $paramDictionary.Add('Scope', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Scope', [System.String], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                        [System.Management.Automation.ValidateSetAttribute]::new('Any', 'User', 'System', 'UserOrUnknown', 'SystemOrUnknown')
                    )
                ))
            $paramDictionary.Add('Force', [System.Management.Automation.RuntimeDefinedParameter]::new(
                    'Force', [System.Management.Automation.SwitchParameter], $(
                        [System.Management.Automation.ParameterAttribute]@{ Mandatory = $false }
                    )
                ))
        }

        # Return the populated dictionary.
        if ($paramDictionary.Count)
        {
            return $paramDictionary
        }
    }

    begin
    {
        # Internal function to generate arguments array for WinGet.
        function Out-ADTWinGetDeploymentArgumentList
        {
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [System.Collections.Generic.Dictionary[System.String, System.Object]]$BoundParameters,

                [Parameter(Mandatory = $false)]
                [ValidateNotNullOrEmpty()]
                [System.String[]]$Exclude
            )

            # Ensure the action is also excluded.
            $PSBoundParameters.Exclude = $('Action'; 'MatchOption'; 'Mode'; 'Ignore-Security-Hash'; 'DebugHashMismatch'; $(if ($Exclude) { $Exclude } ))

            # Output each item for the caller to collect.
            return $(
                $Action
                & $Script:CommandTable.'Convert-ADTFunctionParamsToArgArray' @PSBoundParameters -Preset WinGet
                if ($MatchOption -eq 'Equals')
                {
                    '--exact'
                }
                if (($Mode -eq 'Silent') -or ($adtSession -and ($adtSession.DeployMode -eq 'Silent')))
                {
                    '--silent'
                }
                '--accept-source-agreements'
                if ($Action -ne 'Uninstall')
                {
                    '--accept-package-agreements'
                }
            )
        }

        # Define internal scriptblock for invoking WinGet. This is a
        # scriptblock so Write-ADTLogEntry uses this function's source.
        $wingetInvoker = {
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [System.String[]]$ArgumentList
            )

            # This scriptblock must always return the output as a string array, even for singular lines.
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Executing [$wingetPath $ArgumentList]."
            return , [System.String[]](& $wingetPath $ArgumentList 2>&1 | & {
                    begin
                    {
                        $waleParams = @{ PassThru = $true }
                    }

                    process
                    {
                        if ($_ -match '^\w+')
                        {
                            $waleParams.Severity = if ($_ -match 'exit code: \d+') { 3 } else { 1 }
                            & $Script:CommandTable.'Write-ADTLogEntry' @waleParams -Message ($_.Trim() -replace '((?<![.:])|:)$', '.')
                        }
                    }
                })
        }

        # Throw if an id, name, or moniker hasn't been provided. This is done like this
        # and not via parameter sets because this is what Install-WinGetPackage does.
        if (!$PSBoundParameters.ContainsKey('Id') -and !$PSBoundParameters.ContainsKey('Name') -and !$PSBoundParameters.ContainsKey('Moniker'))
        {
            $naerParams = @{
                Exception = [System.ArgumentException]::new("Please specify a package by Id, Name, or Moniker.")
                Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
                ErrorId = "WinGet$([System.Globalization.CultureInfo]::CurrentUICulture.TextInfo.ToTitleCase($Action))FilterError"
                TargetObject = $PSBoundParameters
                RecommendedAction = "Please specify a package by Id, Name, or Moniker; then try again."
            }
            $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
        }

        # If we're deploying using an id, enforce exact matching.
        if ($PSBoundParameters.ContainsKey('Id'))
        {
            $MatchOption = 'Equals'
        }

        # Perform initial setup.
        try
        {
            # Ensure WinGet is good to go.
            if (!$PSBoundParameters.ContainsKey('Source'))
            {
                & $Script:CommandTable.'Assert-ADTWinGetPackageManager'
            }
            $wingetPath = & $Script:CommandTable.'Get-ADTWinGetPath'

            # Attempt to find the package to install.
            $fawgpParams = @{}; if ($PSBoundParameters.ContainsKey('Id'))
            {
                $fawgpParams.Add('Id', $PSBoundParameters.Id)
            }
            if ($PSBoundParameters.ContainsKey('Name'))
            {
                $fawgpParams.Add('Name', $PSBoundParameters.Name)
            }
            if ($PSBoundParameters.ContainsKey('Moniker'))
            {
                $fawgpParams.Add('Moniker', $PSBoundParameters.Moniker)
            }
            if ($PSBoundParameters.ContainsKey('Source'))
            {
                $fawgpParams.Add('Source', $PSBoundParameters.Source)
            }
            if (![System.String]::IsNullOrWhiteSpace($MatchOption))
            {
                $fawgpParams.Add('MatchOption', $MatchOption)
            }
            $wgPackage = & $Script:CommandTable.'Find-ADTWinGetPackage' @fawgpParams -InformationAction SilentlyContinue
        }
        catch
        {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        # Get the active ADT session object if one's in play.
        $adtSession = if (& $Script:CommandTable.'Test-ADTSessionActive')
        {
            & $Script:CommandTable.'Get-ADTSession'
        }

        # Add in a default log file if the caller hasn't specified one.
        if (!$PSBoundParameters.ContainsKey('Log'))
        {
            $PSBoundParameters.Log = if ($adtSession)
            {
                "$((& $Script:CommandTable.'Get-ADTConfig').Toolkit.LogPath)\$($adtSession.InstallName)_WinGet.log"
            }
            else
            {
                "$([System.IO.Path]::GetTempPath())Invoke-ADTWinGetOperation_$([System.DateTime]::Now.ToString('O').Split('.')[0].Replace(':', $null))_WinGet.log"
            }
        }

        # Translate the provided scope argument, otherwise fefault the scope to "Machine" for the safety of users.
        # It's super easy to install user-scoped apps into the SYSTEM user's account, and it's painful to diagnose/clean up.
        if (($callerScope = if ($PSBoundParameters.ContainsKey('Scope')) { $PSBoundParameters.Scope }))
        {
            switch -regex ($callerScope)
            {
                '^System'
                {
                    $PSBoundParameters.Scope = 'Machine'
                }
                '^User'
                {
                    $PSBoundParameters.Scope = 'User'
                }
                default
                {
                    # If we're here, the caller's specified "Any".
                    # As such, remove entirely so WinGet can determine.
                    $null = $PSBoundParameters.Remove('Scope')
                }
            }
        }
        elseif (($wgPackage.PSObject.Properties.Name.Contains('Source') -and !$wgPackage.Source.Equals('msstore')) -or ($PSBoundParameters.ContainsKey('Source') -and ($PSBoundParameters.Source -ne 'msstore')))
        {
            $PSBoundParameters.Add('Scope', 'Machine')
        }

        # Generate action lookup table for verbage.
        $actionTranslator = @{
            Install = 'Installer'
            Repair = 'Repair'
            Uninstall = 'Uninstaller'
            Upgrade = 'Installer'
        }
    }

    end
    {
        # Test whether we're debugging the AllowHashMismatch feature.
        if (($Action -notmatch '^(install|upgrade)$') -or !$PSBoundParameters.ContainsKey('DebugHashMismatch') -or !$PSBoundParameters.DebugHashMismatch)
        {
            # Invoke WinGet and print each non-null line.
            $wingetOutput = & $wingetInvoker -ArgumentList (Out-ADTWinGetDeploymentArgumentList -BoundParameters $PSBoundParameters)

            # If package isn't found, rerun again without --Scope argument.
            if (($Global:LASTEXITCODE -eq [ADTWinGetExitCode]::NO_APPLICABLE_INSTALLER) -and (!$callerScope -or $callerScope.EndsWith('Unknown')))
            {
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Attempting to execute WinGet again without '--scope' argument."
                $wingetOutput = & $wingetInvoker -ArgumentList (Out-ADTWinGetDeploymentArgumentList -BoundParameters $PSBoundParameters -Exclude Scope)
            }
        }
        else
        {
            # Going into bypass mode. Simulate WinGet output for the purpose of getting the app's version later on.
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Bypassing WinGet as `-DebugHashMismatch` has been passed. This switch should only be used for debugging purposes."
            $Global:LASTEXITCODE = [ADTWinGetExitCode]::INSTALLER_HASH_MISMATCH.value__
            $PSBoundParameters.'Ignore-Security-Hash' = $true
        }

        # If we're bypassing a hash failure, process the WinGet manifest ourselves.
        if (($Global:LASTEXITCODE -eq [ADTWinGetExitCode]::INSTALLER_HASH_MISMATCH) -and $PSBoundParameters.ContainsKey('Ignore-Security-Hash') -and $PSBoundParameters.'Ignore-Security-Hash')
        {
            # The hash failed, however we're forcing an override. Set up default parameters for Get-ADTWinGetHashMismatchInstaller and get started.
            & $Script:CommandTable.'Write-ADTLogEntry' -Message "Installation failed due to mismatched hash, attempting to override as `-IgnoreHashFailure` has been passed."
            $gawgaiParams = @{}; if ($PSBoundParameters.ContainsKey('Scope'))
            {
                $gawgaiParams.Add('Scope', $PSBoundParameters.Scope)
            }
            if ($PSBoundParameters.ContainsKey('Architecture'))
            {
                $gawgaiParams.Add('Architecture', $PSBoundParameters.Architecture)
            }
            if ($PSBoundParameters.ContainsKey('Installer-Type'))
            {
                $gawgaiParams.Add('InstallerType', $PSBoundParameters.'Installer-Type')
            }

            # Grab the manifest so we can parse out the installation info as required.
            $wgAppInfo = [ordered]@{ Manifest = & $Script:CommandTable.'Get-ADTWinGetHashMismatchManifest' -Id $wgPackage.Id -Version $wgPackage.Version }
            $wgAppInfo.Add('Installer', (& $Script:CommandTable.'Get-ADTWinGetHashMismatchInstaller' @gawgaiParams -Manifest $wgAppInfo.Manifest))
            $wgAppInfo.Add('FilePath', (& $Script:CommandTable.'Get-ADTWinGetHashMismatchDownload' -Installer $wgAppInfo.Installer))

            # Set up arguments to pass to Start-Process.
            $spParams = @{
                WorkingDirectory = $ExecutionContext.SessionState.Path.CurrentLocation.Path
                ArgumentList = & $Script:CommandTable.'Get-ADTWinGetHashMismatchArgumentList' @wgAppInfo -LogFile $PSBoundParameters.Log
                FilePath = $(if ($wgAppInfo.FilePath.EndsWith('msi')) { 'msiexec.exe' } else { $wgAppInfo.FilePath })
                PassThru = $true
                Wait = $true
            }

            # Commence installation and test the resulting exit code for success.
            $wingetOutput = $(
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Starting package install..." -PassThru
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Executing [$($spParams.FilePath) $($spParams.ArgumentList)]" -PassThru
                if ((& $Script:CommandTable.'Get-ADTWinGetHashMismatchExitCodes' @wgAppInfo) -notcontains ($Global:LASTEXITCODE = (& $Script:CommandTable.'Start-Process' @spParams).ExitCode))
                {
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Uninstall failed with exit code: $Global:LASTEXITCODE." -PassThru
                }
                else
                {
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Successfully installed." -PassThru
                }
            )
        }

        # Generate an exception if we received any failure.
        $wingetException = if (($wingetErrLine = $($wingetOutput -match 'exit code: \d+')))
        {
            [System.Runtime.InteropServices.ExternalException]::new($wingetErrLine, [System.Int32]($wingetErrLine -replace '^.+:\s((0x\d{8})|\d+)(.+)?$', '$1'))
        }
        elseif ($Global:LASTEXITCODE)
        {
            # All this bullshit is to change crap like '0x800704c7 : unknown error.' to 'Unknown error.'...
            $wgErrorDef = if ([System.Enum]::IsDefined([ADTWinGetExitCode], $Global:LASTEXITCODE)) { [ADTWinGetExitCode]$Global:LASTEXITCODE }
            $wgErrorMsg = [System.Text.RegularExpressions.Regex]::Replace($wingetOutput[-1], '^0x\w{8}\s:\s(\w)', { $args[0].Groups[1].Value.ToUpper() })
            [System.Runtime.InteropServices.ExternalException]::new("WinGet operation finished with exit code [0x$($Global:LASTEXITCODE.ToString('X'))]$(if ($wgErrorDef) {" ($wgErrorDef)"}): $($wgErrorMsg.TrimEnd('.')).", $Global:LASTEXITCODE)
        }

        # Calculate the exit code of the deployment operation.
        $wingetExitCode = if ($wingetException)
        {
            $wingetException.ErrorCode
        }
        else
        {
            $Global:LASTEXITCODE
        }

        # Update the session's exit code if one's in play.
        if ($adtSession)
        {
            $adtSession.SetExitCode($wingetExitCode)
        }

        # Generate the WinGet result. We do this here so we can add it to the ErrorRecord's TargetObject if we're going to throw.
        $wingetResult = [pscustomobject]@{
            Id = $wgPackage.Id
            Name = $wgPackage.Name
            Source = if ($PSBoundParameters.ContainsKey('Source')) { $Source } else { $wgPackage | & $Script:CommandTable.'Select-Object' -ExpandProperty Source -ErrorAction Ignore }
            CorrelationData = [System.String]::Empty
            ExtendedErrorCode = $null
            RebootRequired = $Global:LASTEXITCODE.Equals(1641) -or ($Global:LASTEXITCODE.Equals(3010))
            Status = if ($wingetException) { "$($Action)Error" } else { 'Ok' }
            "$($actionTranslator.$Action)ErrorCode" = $wingetExitCode
        }

        # Extend the result with an ErrorRecord for the caller to throw.
        if ($wingetException)
        {
            $naerParams = @{
                Exception = $wingetException
                Activity = (& $Script:CommandTable.'Get-PSCallStack')[1].Command
                Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                ErrorId = "WinGetPackage$([System.Globalization.CultureInfo]::CurrentUICulture.TextInfo.ToTitleCase($Action))Failure"
                TargetObject = [pscustomobject]@{ Result = $wingetResult; Output = $wingetOutput }
                RecommendedAction = "Please review the exit code, then try again."
            }
            $wingetResult.ExtendedErrorCode = & $Script:CommandTable.'New-ADTErrorRecord' @naerParams
        }

        # Return the result if we've succeeded.
        return $wingetResult
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Invoke-ADTWinGetQueryOperation
#
#-----------------------------------------------------------------------------

function Invoke-ADTWinGetQueryOperation
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('list', 'search')]
        [System.String]$Action,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Query,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Equals', 'EqualsCaseInsensitive')]
        [System.String]$MatchOption,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Command,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.UInt32]$Count,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Moniker,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
                try
                {
                    return (& $Script:CommandTable.'Get-ADTWinGetSource' -Name $_ -InformationAction SilentlyContinue)
                }
                catch
                {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
            })]
        [System.String]$Source,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Tag
    )

    # Confirm WinGet is good to go.
    if (!$PSBoundParameters.ContainsKey('Source'))
    {
        try
        {
            & $Script:CommandTable.'Assert-ADTWinGetPackageManager'
        }
        catch
        {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    # Force exact matching when using an Id.
    if ($PSBoundParameters.ContainsKey('Id'))
    {
        $MatchOption = 'Equals'
    }

    # Set up arguments array for WinGet.
    $wingetArgs = $(
        $Action
        $PSBoundParameters | & $Script:CommandTable.'Convert-ADTFunctionParamsToArgArray' -Preset WinGet -Exclude Action, MatchOption
        if ($MatchOption -eq 'Equals') { '--exact' }
        '--accept-source-agreements'
    )

    # Invoke WinGet, handling the required change in console output encoding.
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Finding packages matching input criteria, please wait..."
    $origEncoding = [System.Console]::OutputEncoding; [System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $wingetOutput = & (& $Script:CommandTable.'Get-ADTWinGetPath') $wingetArgs 2>&1 | & { process { if ($_ -match '^(\w+|-+$)') { return $_.Trim() } } }
    [System.Console]::OutputEncoding = $origEncoding

    # Return early if we couldn't find a package.
    if ($WinGetOutput -match '^No.+package found matching input criteria\.$')
    {
        # Throw if we're searching.
        if ($Action -eq 'search')
        {
            $naerParams = @{
                Exception = [System.IO.InvalidDataException]::new("No package found matching input criteria.")
                Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                ErrorId = "WinGetPackageNotFoundError"
                TargetObject = $PSBoundParameters
                RecommendedAction = "Please review the specified input, then try again."
            }
            $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
        }
        & $Script:CommandTable.'Write-ADTLogEntry' -Message "No package found matching input criteria."
        return
    }

    # Convert the cached output to proper PowerShell objects.
    $wingetObjects = & $Script:CommandTable.'Convert-ADTWinGetQueryOutput' -WinGetOutput $wingetOutput
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Found $(($wingetObjCount = ($wingetObjects | & $Script:CommandTable.'Measure-Object').Count)) package$(if (!$wingetObjCount.Equals(1)) { 's' }) matching input criteria."
    return $wingetObjects
}


#-----------------------------------------------------------------------------
#
# MARK: Repair-ADTWinGetDesktopAppInstaller
#
#-----------------------------------------------------------------------------

function Repair-ADTWinGetDesktopAppInstaller
{
    # Update WinGet to the latest version. Don't rely in 3rd party store API services for this.
    # https://learn.microsoft.com/en-us/windows/package-manager/winget/#install-winget-on-windows-sandbox
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Installing/updating $(($pkgName = "Microsoft.DesktopAppInstaller")) dependency, please wait..."
    [System.Uri[]]$links = & $Script:CommandTable.'Get-ADTGitHubReleaseAssetUri' -Account microsoft -Repository winget-cli

    # Define installation file info.
    $packages = @(
        @{
            Name = 'latest WinGet dependencies'
            Uri = ($uri = $links | & { process { if ($_.AbsoluteUri.EndsWith('DesktopAppInstaller_Dependencies.zip')) { return $_ } } } | & $Script:CommandTable.'Select-Object' -First 1)
            FilePath = "$([System.IO.Path]::GetTempPath())$($uri.Segments[-1])"
        }
        @{
            Name = 'latest WinGet msixbundle'
            Uri = ($uri = $links | & { process { if ($_.AbsoluteUri.EndsWith('Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle')) { return $_ } } } | & $Script:CommandTable.'Select-Object' -First 1)
            FilePath = "$([System.IO.Path]::GetTempPath())$($uri.Segments[-1])"
        }
    )

    # Download all packages.
    foreach ($package in $packages)
    {
        & $Script:CommandTable.'Write-ADTLogEntry' -Message "Downloading [$($package.Name)], please wait..."
        & $Script:CommandTable.'Invoke-ADTWebDownload' -Uri $package.Uri -OutFile $package.FilePath
    }

    # Set the log file path.
    $logFile = if (& $Script:CommandTable.'Test-ADTSessionActive')
    {
        "$((& $Script:CommandTable.'Get-ADTConfig').Toolkit.LogPath)\$((& $Script:CommandTable.'Get-ADTSession').InstallName)_Dism.log"
    }
    else
    {
        "$([System.IO.Path]::GetFileNameWithoutExtension($packages[(-1)].FilePath)).log"
    }

    # Extract dependencies so they can be used with Add-AppxProvisionedPackage.
    & $Script:CommandTable.'Expand-Archive' -LiteralPath $packages[0].FilePath -DestinationPath ($depsPath = [System.IO.Path]::GetFileNameWithoutExtension($packages[0].FilePath)) -Force

    # Pre-provision package in the system.
    $aappParams = @{
        Online = $true
        SkipLicense = $true
        PackagePath = $packages[-1].FilePath
        DependencyPackagePath = [System.IO.Directory]::GetFiles([System.IO.Path]::Combine($depsPath, $Script:ADT.SystemArchitecture))
        LogPath = $logFile
    }
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Pre-provisioning [$pkgName] $($packages[-1].Uri.Segments[-2].Trim('/')), please wait..."
    $null = & $Script:CommandTable.'Add-AppxProvisionedPackage' @aappParams -Verbose:$false

    # Register the package again if we're not running as SYSTEM.
    if (!$Script:ADT.RunningAsSystem)
    {
        & $Script:CommandTable.'Write-ADTLogEntry' -Message "Registering [$pkgName] $($packages[-1].Uri.Segments[-2].Trim('/')), please wait..."
        & $Script:CommandTable.'Add-AppxPackage' -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Repair-ADTWinGetVisualStudioRuntime
#
#-----------------------------------------------------------------------------

function Repair-ADTWinGetVisualStudioRuntime
{
    # Set required variables for install operation.
    $pkgArch = @('x86', 'x64')[[System.Environment]::Is64BitProcess]
    $pkgName = "Microsoft Visual C++ 2015-2022 Redistributable ($pkgArch)"
    $uriPath = "https://aka.ms/vs/17/release/vc_redist.$pkgArch.exe"
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Preparing $pkgName dependency, please wait..."

    # Get the active ADT session object for log naming, if available.
    $adtSession = if (& $Script:CommandTable.'Test-ADTSessionActive')
    {
        & $Script:CommandTable.'Get-ADTSession'
    }

    # Set up the filename for the download.
    $fileName = & $Script:CommandTable.'Get-Random'

    # Set the log filename.
    $logFile = if ($adtSession)
    {
        "$((& $Script:CommandTable.'Get-ADTConfig').Toolkit.LogPath)\$($adtSession.InstallName)_MSVCRT.log"
    }
    else
    {
        "$([System.IO.Path]::GetTempPath())$fileName.log"
    }

    # Define arguments for installation.
    $spParams = @{
        FilePath = "$([System.IO.Path]::GetTempPath())$fileName.exe"
        ArgumentList = "/install", "/quiet", "/norestart", "/log `"$logFile`""
    }

    # Download and extract installer.
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Downloading [$pkgName], please wait..."
    & $Script:CommandTable.'Invoke-ADTWebDownload' -Uri $uriPath -OutFile $spParams.FilePath

    # Invoke installer and throw if we failed.
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Installing [$pkgName], please wait..."
    if (($exitCode = (& $Script:CommandTable.'Start-Process' @spParams -Wait -PassThru).ExitCode))
    {
        if ($adtSession)
        {
            $adtSession.SetExitCode($exitCode)
        }
        $naerParams = @{
            Exception = [System.Runtime.InteropServices.ExternalException]::new("The installation of [$pkgName] failed with exit code [$exitCode].", $exitCode)
            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
            ErrorId = 'VcRedistInstallFailure'
            TargetObject = $exitCode
            RecommendedAction = "Please review the exit code, then try again."
        }
        throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Assert-ADTWinGetPackageManager
#
#-----------------------------------------------------------------------------

function Assert-ADTWinGetPackageManager
{
    <#
    .SYNOPSIS
        Verifies that WinGet is installed properly.

    .DESCRIPTION
        Verifies that WinGet is installed properly.

        Note: The cmdlet doesn't ensure that the latest version of WinGet is installed. It just verifies that the installed version of Winget is supported by installed version of this module.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Assert-ADTWinGetPackageManager

        If the current version of WinGet is installed correctly, the command returns without error.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
    )

    # Try to get the path to WinGet before proceeding.
    try
    {
        $wingetPath = & $Script:CommandTable.'Get-ADTWinGetPath'
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Try to get the WinGet version.
    try
    {
        [System.Version]$wingetVer = (& $Script:CommandTable.'Get-ADTWinGetVersion' -InformationAction SilentlyContinue).Trim('v')
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Test that the retrieved version is greater than or equal to our minimum.
    if ($wingetVer -lt $Script:ADT.WinGetMinVersion)
    {
        $naerParams = @{
            Exception = [System.Activities.VersionMismatchException]::new("The installed WinGet version of [$wingetVer] is less than the required [$($Script:ADT.WinGetMinVersion)].", [System.Activities.WorkflowIdentity]::new('winget.exe', $Script:ADT.WinGetMinVersion, $wingetPath.FullName), [System.Activities.WorkflowIdentity]::new('winget.exe', $wingetVer, $wingetPath.FullName))
            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
            ErrorId = 'WinGetMinimumVersionError'
            RecommendedAction = "Please run [Repair-ADTWinGetPackageManager] as an admin, then try again."
        }
        $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Find-ADTWinGetPackage
#
#-----------------------------------------------------------------------------

function Find-ADTWinGetPackage
{
    <#
    .SYNOPSIS
        Searches for packages from configured sources.

    .DESCRIPTION
        Searches for packages from configured sources.

    .PARAMETER Query
        Specify one or more strings to search for. By default, the command searches all configured sources.

    .PARAMETER MatchOption
        Specify matching logic used for search.

    .PARAMETER Command
        Specify the name of the command defined in the package manifest.

    .PARAMETER Count
        Limits the number of items returned by the command.

    .PARAMETER Id
        Specify the package identifier for the package you want to list.

    .PARAMETER Moniker
        Specify the moniker of the package you want to list.

    .PARAMETER Name
        Specify the name of the package to list.

    .PARAMETER Source
        Specify the name of the WinGet source to search. The most common sources are `msstore` and `winget`.

    .PARAMETER Tag
        Specify a package tag to search for.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Find-ADTWinGetPackage -Id Microsoft.PowerShell

        This example shows how to search for packages by package identifier. By default, the command searches all configured sources. The command performs a case-insensitive substring match against the PackageIdentifier property of the packages.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Query,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Equals', 'EqualsCaseInsensitive')]
        [System.String]$MatchOption,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Command,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.UInt32]$Count,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Moniker,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Source,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Tag
    )

    begin
    {
        # Throw if at least one filtration method isn't provided.
        if (!($PSBoundParameters.Keys -match '^(Query|Command|Id|Moniker|Name|Tag)$'))
        {
            $naerParams = @{
                Exception = [System.ArgumentException]::new("At least one search parameter must be provided to this function.")
                Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
                ErrorId = "WinGetPackageSearchError"
                TargetObject = $PSBoundParameters
                RecommendedAction = "Please review the specified parameters, then try again."
            }
            $PSCmdlet.ThrowTerminatingError((& $Script:CommandTable.'New-ADTErrorRecord' @naerParams))
        }

        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                # Send this to the backend common function.
                return (& $Script:CommandTable.'Invoke-ADTWinGetQueryOperation' -Action Search @PSBoundParameters)
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to find the specified WinGet package."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetPackage
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetPackage
{
    <#
    .SYNOPSIS
        Lists installed packages.

    .DESCRIPTION
        This command lists all of the packages installed on your system. The output includes packages installed from WinGet sources and packages installed by other methods. Packages that have package identifiers starting with `MSIX` or `ARP` could not be correlated to a WinGet source.

    .PARAMETER Query
        Specify one or more strings to search for. By default, the command searches all configured sources.

    .PARAMETER MatchOption
        Specify matching logic used for search.

    .PARAMETER Command
        Specify the name of the command defined in the package manifest.

    .PARAMETER Count
        Limits the number of items returned by the command.

    .PARAMETER Id
        Specify the package identifier for the package you want to list.

    .PARAMETER Moniker
        Specify the moniker of the package you want to list.

    .PARAMETER Name
        Specify the name of the package to list.

    .PARAMETER Source
        Specify the name of the WinGet source of the package.

    .PARAMETER Tag
        Specify a package tag to search for.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Get-ADTWinGetPackage

        This example shows how to list all packages installed on your system.

    .EXAMPLE
        Get-ADTWinGetPackage -Id "Microsoft.PowerShell"

        This example shows how to get an installed package by its package identifier.

    .EXAMPLE
        Get-ADTWinGetPackage -Name "PowerShell"

        This example shows how to get installed packages that match a name value. The command does a substring comparison of the provided name with installed package names.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Query,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Equals', 'EqualsCaseInsensitive')]
        [System.String]$MatchOption,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Command,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.UInt32]$Count,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Moniker,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Source,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Tag
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                # Send this to the backend common function.
                return (& $Script:CommandTable.'Invoke-ADTWinGetQueryOperation' -Action List @PSBoundParameters)
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to get the specified WinGet package."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetSource
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetSource
{
    <#
    .SYNOPSIS
        Lists configured WinGet sources.

    .DESCRIPTION
        Lists the configured WinGet sources.

    .PARAMETER Name
        Lists the configured WinGet sources.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        PSObject

        This function returns one or more objects for each WinGet source.

    .EXAMPLE
        Get-ADTWinGetSource

        Lists all configured WinGet sources.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name
    )

    begin
    {
        # Confirm WinGet is good to go.
        try
        {
            & $Script:CommandTable.'Assert-ADTWinGetPackageManager'
        }
        catch
        {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                # Get all sources, returning early if there's none (1:1 API with `Get-WinGetSource`).
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Getting list of WinGet sources, please wait..."
                if (($wgSrcRes = & (& $Script:CommandTable.'Get-ADTWinGetPath') source list 2>&1).Equals('There are no sources configured.'))
                {
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "There are no WinGet sources configured on this system."
                    return
                }

                # Convert the results into proper PowerShell data.
                $wgSrcObjs = & $Script:CommandTable.'Convert-ADTWinGetQueryOutput' -WinGetOutput $wgSrcRes

                # Filter by the name if specified.
                if ($PSBoundParameters.ContainsKey('Name'))
                {
                    if (!($wgSrcObj = $wgSrcObjs | & { process { if ($_.Name -eq $Name) { return $_ } } } | & $Script:CommandTable.'Select-Object' -First 1))
                    {
                        $naerParams = @{
                            Exception = [System.ArgumentException]::new("No source found matching the given value [$Name].")
                            Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
                            ErrorId = 'WinGetSourceNotFoundFailure'
                            TargetObject = $wgSrcObjs
                            RecommendedAction = "Please review the configured sources, then try again."
                        }
                        throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                    }
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Found WinGet source [$Name]."
                    return $wgSrcObj
                }
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Found $(($wgSrcObjCount = ($wgSrcObjs | & $Script:CommandTable.'Measure-Object').Count)) WinGet source$(if (!$wgSrcObjCount.Equals(1)) { 's' }): ['$([System.String]::Join("', '", $wgSrcObjs.Name))']."
                return $wgSrcObjs
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to get the specified WinGet source(s)."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Get-ADTWinGetVersion
#
#-----------------------------------------------------------------------------

function Get-ADTWinGetVersion
{
    <#
    .SYNOPSIS
        Gets the installed version of WinGet.

    .DESCRIPTION
        Gets the installed version of WinGet.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        System.String

        This function returns the installed WinGet's version number as a string.

    .EXAMPLE
        Get-ADTWinGetVersion -All

        Gets the installed version of WinGet.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        # Try to get the path to WinGet before proceeding.
        try
        {
            $wingetPath = & $Script:CommandTable.'Get-ADTWinGetPath'
        }
        catch
        {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    process
    {
        try
        {
            try
            {
                # Get the WinGet version and return it to the caller. The API here 1:1 matches WinGet's PowerShell module, rightly or wrongly.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Running [$wingetPath] with [--version] parameter."
                $wingetVer = & $wingetPath --version

                # If we've got a null string, we're probably missing the Visual Studio Runtime or something.
                if ([System.String]::IsNullOrWhiteSpace($wingetVer))
                {
                    $naerParams = @{
                        Exception = [System.InvalidOperationException]::new("The installed version of WinGet was unable to run.")
                        Category = [System.Management.Automation.ErrorCategory]::PermissionDenied
                        ErrorId = 'WinGetNullOutputError'
                        TargetObject = $wingetVer
                        RecommendedAction = "Please run [Repair-ADTWinGetPackageManager] as an admin, then try again."
                    }
                    throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                }
                if ($wingetVer -isnot [System.String])
                {
                    $naerParams = @{
                        Exception = [System.InvalidOperationException]::new("The output from [winget.exe --version] is invalid.")
                        Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                        ErrorId = 'WinGetInvalidOutputError'
                        TargetObject = $wingetVer
                        RecommendedAction = "Please report this error at [https://github.com/mjr4077au/PSAppDeployToolkit.WinGet/issues], then try again."
                    }
                    throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                }
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Installed WinGet version is [$($wingetVer)]."
                return $wingetVer.Replace('-preview', $null)
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to get the WinGet version."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Install-ADTWinGetPackage
#
#-----------------------------------------------------------------------------

function Install-ADTWinGetPackage
{
    <#
    .SYNOPSIS
        Installs a WinGet Package.

    .DESCRIPTION
        This command installs a WinGet package from a configured source. The command includes parameters to specify values used to search for packages in the configured sources. By default, the command searches the winget source. All string-based searches are case-insensitive substring searches. Wildcards are not supported.

    .PARAMETER Query
        Specify one or more strings to search for. By default, the command searches all configured sources.

    .PARAMETER MatchOption
        Specify matching logic used for search.

    .PARAMETER AllowHashMismatch
        Allows you to download package even when the SHA256 hash for an installer or a dependency does not match the SHA256 hash in the WinGet package manifest.

    .PARAMETER Architecture
        Specify the processor architecture for the WinGet package installer.

    .PARAMETER Custom
        Use this parameter to pass additional arguments to the installer. The parameter takes a single string value. To add multiple arguments, include the arguments in the string. The arguments must be provided in the format expected by the installer. If the string contains spaces, it must be enclosed in quotes. This string is added to the arguments defined in the package manifest.

    .PARAMETER Force
        Force the installer to run even when other checks WinGet would perform would prevent this action.

    .PARAMETER Header
        Custom value to be passed via HTTP header to WinGet REST sources.

    .PARAMETER Id
        Specify the package identifier to search for. The command does a case-insensitive full text match, rather than a substring match.

    .PARAMETER InstallerType
        A package may contain multiple installer types.

    .PARAMETER Locale
        Specify the locale of the installer package. The locale must provided in the BCP 47 format, such as `en-US`. For more information, see Standard locale names (/globalization/locale/standard-locale-names).

    .PARAMETER Location
        Specify the file path where you want the packed to be installed. The installer must be able to support alternate install locations.

    .PARAMETER Log
        Specify the location for the installer log. The value can be a fully-qualified or relative path and must include the file name. For example: `$env:TEMP\package.log`.

    .PARAMETER Mode
        Specify the output mode for the installer.

    .PARAMETER Moniker
        Specify the moniker of the WinGet package to install. For example, the moniker for the Microsoft.PowerShell package is `pwsh`.

    .PARAMETER Name
        Specify the name of the package to be installed.

    .PARAMETER Override
        Use this parameter to override the existing arguments passed to the installer. The parameter takes a single string value. To add multiple arguments, include the arguments in the string. The arguments must be provided in the format expected by the installer. If the string contains spaces, it must be enclosed in quotes. This string overrides the arguments specified in the package manifest.

    .PARAMETER Scope
        Specify WinGet package installer scope.

    .PARAMETER SkipDependencies
        Specifies that the command shouldn't install the WinGet package dependencies.

    .PARAMETER Source
        Specify the name of the WinGet source from which the package should be installed.

    .PARAMETER Version
        Specify the version of the package.

    .PARAMETER DebugHashMismatch
        Forces the AllowHashMismatch for debugging purposes.

    .PARAMETER PassThru
        Returns an object detailing the operation, just as Microsoft's module does by default.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        PSObject

        This function returns a PSObject containing the outcome of the operation.

    .EXAMPLE
        Install-ADTWinGetPackage -Id Microsoft.PowerShell

        This example shows how to install a package by the specifying the package identifier. If the package identifier is available from more than one source, you must provide additional search criteria to select a specific instance of the package. If more than one source is configured with the same package identifier, the user must disambiguate.

    .EXAMPLE
        Install-ADTWinGetPackage -Name "PowerToys (Preview)"

        This example shows how to install a package by specifying the package name.

    .EXAMPLE
        Install-ADTWinGetPackage Microsoft.PowerShell -Version 7.4.4.0

        This example shows how to install a specific version of a package using a query. The command does a query search for packages matching `Microsoft.PowerShell`. The results of the search a limited to matches with the version of `7.4.4.0`.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Query,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Equals', 'EqualsCaseInsensitive')]
        [System.String]$MatchOption,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$AllowHashMismatch,

        [Parameter(Mandatory = $false)]
        [ValidateSet('x86', 'x64', 'arm64')]
        [System.String]$Architecture,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Custom,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$Force,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Header,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Inno', 'Wix', 'Msi', 'Nullsoft', 'Zip', 'Msix', 'Exe', 'Burn', 'MSStore', 'Portable')]
        [System.String]$InstallerType,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Locale,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Location,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Log,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Silent', 'Interactive')]
        [System.String]$Mode,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Moniker,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Override,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Any', 'User', 'System', 'UserOrUnknown', 'SystemOrUnknown')]
        [System.String]$Scope,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$SkipDependencies,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Source,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Version,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$DebugHashMismatch,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$PassThru
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        $null = $PSBoundParameters.Remove('PassThru')
    }

    process
    {
        # Initialise variables before proceeding.
        $wingetResult = $null
        try
        {
            try
            {
                # Perform the required operation.
                $wingetResult = & $Script:CommandTable.'Invoke-ADTWinGetDeploymentOperation' -Action Install @PSBoundParameters
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }

            # Throw if the result has an ErrorRecord.
            if ($wingetResult.ExtendedErrorCode)
            {
                & $Script:CommandTable.'Write-Error' -ErrorRecord $wingetResult.ExtendedErrorCode
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to install the specified WinGet package." -DisableErrorResolving:($null -ne $wingetResult)
        }

        # If we have a result and are passing through, return it.
        if ($wingetResult -and $PassThru)
        {
            return $wingetResult
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Invoke-ADTWinGetOperation
#
#-----------------------------------------------------------------------------

function Invoke-ADTWinGetOperation
{
    <#
    .SYNOPSIS
        This function performs the end-to-end installation or uninstallation of a WinGet application using PSAppDeployToolkit.

    .DESCRIPTION
        This function performs the end-to-end installation or uninstallation of a WinGet application using PSAppDeployToolkit.

        - The function is provided as a basic implementation to perform an install, uninstall, or repair of a WinGet application.
        - The function either performs an "Install", "Uninstall", or "Repair" deployment type.
        - The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

        This function is not intended to be called from an existing `Invoke-AppDeployToolkit.ps1` script. For usage within your own script, please use the individual WinGet functions, such as `Install-ADTWinGetPackage`, etc.

    .PARAMETER Id
        The WinGet package identifier for the deployment.

    .PARAMETER DeploymentType
        The type of deployment to perform.

    .PARAMETER DeployMode
        Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode.

    .PARAMETER AllowRebootPassThru
        Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

    .EXAMPLE
        powershell.exe -File Invoke-AppDeployToolkit.ps1 -Id Microsoft.VSTOR

    .EXAMPLE
        powershell.exe -File Invoke-AppDeployToolkit.ps1 -Id Microsoft.VSTOR -DeployMode Silent

    .EXAMPLE
        powershell.exe -File Invoke-AppDeployToolkit.ps1 -Id Microsoft.VSTOR -AllowRebootPassThru

    .EXAMPLE
        powershell.exe -File Invoke-AppDeployToolkit.ps1 -Id Microsoft.VSTOR -DeploymentType Uninstall

    .EXAMPLE
        Invoke-AppDeployToolkit.exe -Id Microsoft.VSTOR -DeploymentType Install -DeployMode Silent

    .INPUTS
        None. You cannot pipe objects to this function.

    .OUTPUTS
        None. This function does not generate any output.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Install', 'Uninstall', 'Repair')]
        [PSDefaultValue(Help = 'Install', Value = 'Install')]
        [System.String]$DeploymentType,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
        [PSDefaultValue(Help = 'Interactive', Value = 'Interactive')]
        [System.String]$DeployMode,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$AllowRebootPassThru
    )

    # Set strict error handling across entire operation.
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
    & $Script:CommandTable.'Set-StrictMode' -Version 3
    $mainError = $null

    # Perform initial setup and establish new DeploymentSession.
    try
    {
        try
        {
            & $Script:CommandTable.'Assert-ADTWinGetPackageManager'
        }
        catch
        {
            & $Script:CommandTable.'Invoke-ADTWinGetRepair'
            & $Script:CommandTable.'Assert-ADTWinGetPackageManager'
        }
        $adtSession = @{
            AppName = (($wgPackage = & $Script:CommandTable.'Find-ADTWinGetPackage' -Id $Id -MatchOption Equals).Name -replace ([regex]::Escape($wgPackage.Version))).Trim()
            AppVersion = $wgPackage.Version
            DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
            DeployAppScriptVersion = $MyInvocation.MyCommand.Module.Version
            DeployAppScriptParameters = $PSBoundParameters
        }
        $adtSession = & $Script:CommandTable.'Open-ADTSession' -SessionState $ExecutionContext.SessionState @adtSession @PSBoundParameters -PassThru
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Main invocation once session is open.
    try
    {
        # Show Welcome Message.
        $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
        $saiwParams = if ($adtSession.DeploymentType -eq 'Install')
        {
            @{ AllowDefer = $true; DeferTimes = 3; CheckDiskSpace = $true; PersistPrompt = $true; NoMinimizeWindows = $true }
        }
        else
        {
            @{ CloseProcessesCountdown = 60; NoMinimizeWindows = $true }
        }
        & $Script:CommandTable.'Show-ADTInstallationWelcome' @saiwParams
        & $Script:CommandTable.'Show-ADTInstallationProgress'

        # Perform our WinGet action and close out
        $adtSession.InstallPhase = $adtSession.DeploymentType
        $null = & "$($adtSession.DeploymentType)-ADTWinGetPackage" -Id $Id
        & $Script:CommandTable.'Close-ADTSession'
    }
    catch
    {
        & $Script:CommandTable.'Write-ADTLogEntry' -Message ($mainErrorMessage = & $Script:CommandTable.'Resolve-ADTErrorRecord' -ErrorRecord ($mainError = $_)) -Severity 3
        & $Script:CommandTable.'Show-ADTDialogBox' -Text $mainErrorMessage -Icon Stop | & $Script:CommandTable.'Out-Null'
        & $Script:CommandTable.'Close-ADTSession' -ExitCode 60001
    }
    finally
    {
        if ($mainError -and !([System.Environment]::GetCommandLineArgs() -eq '-NonInteractive'))
        {
            $PSCmdlet.ThrowTerminatingError($mainError)
        }
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Invoke-ADTWinGetRepair
#
#-----------------------------------------------------------------------------

function Invoke-ADTWinGetRepair
{
    <#
    .SYNOPSIS
        PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

    .DESCRIPTION
        - The script is provided as a template to perform an install, uninstall, or repair of an application(s).
        - The script either performs an "Install", "Uninstall", or "Repair" deployment type.
        - The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

        The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

    .PARAMETER AllowRebootPassThru
        Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

    .EXAMPLE
        powershell.exe -File Invoke-AppDeployToolkit.ps1 -AllowRebootPassThru

    .INPUTS
        None. You cannot pipe objects to this script.

    .OUTPUTS
        None. This script does not generate any output.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$AllowRebootPassThru
    )


    ##================================================
    ## MARK: Variables
    ##================================================

    $adtSession = @{
        # App variables.
        AppName = "$($MyInvocation.MyCommand.Module.Name) Repair Operation"

        # Script variables.
        DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
        DeployAppScriptVersion = $MyInvocation.MyCommand.Module.Version
        DeployAppScriptParameters = $PSBoundParameters

        # Script parameters.
        DeploymentType = 'Repair'
        DeployMode = 'Silent'
    }


    ##================================================
    ## MARK: Initialization
    ##================================================

    # Set strict error handling across entire operation.
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
    & $Script:CommandTable.'Set-StrictMode' -Version 3
    $mainError = $null

    # Import the module and instantiate a new session.
    try
    {
        $adtSession = & $Script:CommandTable.'Open-ADTSession' -SessionState $ExecutionContext.SessionState @adtSession @PSBoundParameters -PassThru
        $adtSession.InstallPhase = $adtSession.DeploymentType
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($_)
    }


    ##================================================
    ## MARK: Invocation
    ##================================================

    try
    {
        & $Script:CommandTable.'Repair-ADTWinGetPackageManager'
        & $Script:CommandTable.'Close-ADTSession'
    }
    catch
    {
        & $Script:CommandTable.'Write-ADTLogEntry' -Message (& $Script:CommandTable.'Resolve-ADTErrorRecord' -ErrorRecord ($mainError = $_)) -Severity 3
        & $Script:CommandTable.'Close-ADTSession' -ExitCode 60001 -Force:(!(& $Script:CommandTable.'Get-PSCallStack').Command.Equals('Invoke-ADTWinGetOperation'))
    }
    finally
    {
        if ($mainError -and !([System.Environment]::GetCommandLineArgs() -eq '-NonInteractive'))
        {
            $PSCmdlet.ThrowTerminatingError($mainError)
        }
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Repair-ADTWinGetPackage
#
#-----------------------------------------------------------------------------

function Repair-ADTWinGetPackage
{
    <#
    .SYNOPSIS
        Repairs a WinGet Package.

    .DESCRIPTION
        This command repairs a WinGet package from your computer, provided the package includes repair support. The command includes parameters to specify values used to search for installed packages. By default, all string-based searches are case-insensitive substring searches. Wildcards are not supported.

        Note: Not all packages support repair.

    .PARAMETER Query
        Specify one or more strings to search for. By default, the command searches all configured sources.

    .PARAMETER MatchOption
        Specify matching logic used for search.

    .PARAMETER Id
        Specify the package identifier to search for. The command does a case-insensitive full text match, rather than a substring match.

    .PARAMETER Log
        Specify the location for the installer log. The value can be a fully-qualified or relative path and must include the file name. For example: `$env:TEMP\package.log`.

    .PARAMETER Mode
        Specify the output mode for the installer.

    .PARAMETER Moniker
        Specify the moniker of the WinGet package to install. For example, the moniker for the Microsoft.PowerShell package is `pwsh`.

    .PARAMETER Name
        Specify the name of the package to be installed.

    .PARAMETER Source
        Specify the name of the WinGet source from which the package should be installed.

    .PARAMETER Version
        Specify the version of the package.

    .PARAMETER PassThru
        Returns an object detailing the operation, just as Microsoft's module does by default.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        PSObject

        This function returns a PSObject containing the outcome of the operation.

    .EXAMPLE
        Repair-ADTWinGetPackage -Id "Microsoft.GDK.2406"

        This example shows how to repair a package by specifying the package identifier. If the package identifier is available from more than one source, you must provide additional search criteria to select a specific instance of the package.

    .EXAMPLE
        Repair-ADTWinGetPackage -Name "Microsoft Game Development Kit - 240602 (June 2024 Update 2)"

        This example shows how to repair a package using the package name. Please note that the examples mentioned above are mainly reference examples for the repair cmdlet and may not be operational as is, since many installers don't support repair as a standard functionality. For the Microsoft.GDK.2406 example, the assumption is that Microsoft.GDK.2406 supports repair capability and the author of the installer has provided the necessary repair context/switches in the Package Manifest in the Package Source referenced by the WinGet Client.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Query,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Equals', 'EqualsCaseInsensitive')]
        [System.String]$MatchOption,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Log,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Silent', 'Interactive')]
        [System.String]$Mode,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Moniker,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Source,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Version,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$PassThru
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        $null = $PSBoundParameters.Remove('PassThru')
    }

    process
    {
        # Initialise variables before proceeding.
        $wingetResult = $null
        try
        {
            try
            {
                # Perform the required operation.
                $wingetResult = & $Script:CommandTable.'Invoke-ADTWinGetDeploymentOperation' -Action Repair @PSBoundParameters
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }

            # Throw if the result has an ErrorRecord.
            if ($wingetResult.ExtendedErrorCode)
            {
                & $Script:CommandTable.'Write-Error' -ErrorRecord $wingetResult.ExtendedErrorCode
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to repair the specified WinGet package." -DisableErrorResolving:($null -ne $wingetResult)
        }

        # If we have a result and are passing through, return it.
        if ($wingetResult -and $PassThru)
        {
            return $wingetResult
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Repair-ADTWinGetPackageManager
#
#-----------------------------------------------------------------------------

function Repair-ADTWinGetPackageManager
{
    <#
    .SYNOPSIS
        Repairs the installation of the WinGet client on your computer.

    .DESCRIPTION
        This command repairs the installation of the WinGet client on your computer by installing the specified version or the latest version of the client. This command can also install the WinGet client if it is not already installed on your machine. It ensures that the client is installed in a working state.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Repair-ADTWinGetPackageManager

        This example shows how to repair they WinGet client by installing the latest version and ensuring it functions properly.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                # Test whether WinGet is installed and available at all.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Confirming whether [Microsoft.DesktopAppInstaller] is installed, please wait..."
                if (!($wingetPath = & $Script:CommandTable.'Get-ADTWinGetPath') -or !$wingetPath.Exists)
                {
                    # Throw if we're not admin.
                    if (!$Script:ADT.RunningAsAdmin)
                    {
                        $naerParams = @{
                            Exception = [System.UnauthorizedAccessException]::new("WinGet is not installed. Please install [Microsoft.DesktopAppInstaller] and try again.")
                            Category = [System.Management.Automation.ErrorCategory]::PermissionDenied
                            ErrorId = 'MicrosoftDesktopAppInstallerCannotInstallFailure'
                            RecommendedAction = "Please install [Microsoft.DesktopAppInstaller] as an admin, then try again."
                        }
                        throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                    }

                    # Install Microsoft.DesktopAppInstaller.
                    & $Script:CommandTable.'Repair-ADTWinGetDesktopAppInstaller'

                    # Throw if the installation was successful but we still don't have WinGet.
                    if (!($wingetPath = & $Script:CommandTable.'Get-ADTWinGetPath') -or !$wingetPath.Exists)
                    {
                        $naerParams = @{
                            Exception = [System.InvalidOperationException]::new("Failed to get a valid WinGet path after successfully pre-provisioning the app. Please report this issue for further analysis.")
                            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                            ErrorId = 'MicrosoftDesktopAppInstallerMissingFailure'
                            RecommendedAction = "Please report this issue to the project's maintainer for further analysis."
                        }
                        throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                    }
                }
                else
                {
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Successfully confirmed that [Microsoft.DesktopAppInstaller] is installed on system."
                }

                # Test whether we have any output from winget.exe. If this is null, it typically means the appropriate MSVC++ runtime is not installed.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Testing whether [Microsoft Visual C++ 2015-2022 Runtime] is installed, please wait..."
                if (!(& $wingetPath))
                {
                    # Throw if we're not admin.
                    if (!$Script:ADT.RunningAsAdmin)
                    {
                        $naerParams = @{
                            Exception = [System.InvalidOperationException]::new("The installed version of WinGet was unable to run. Please ensure the latest [Microsoft Visual C++ 2015-2022 Runtime] is installed and try again.")
                            Category = [System.Management.Automation.ErrorCategory]::PermissionDenied
                            ErrorId = 'VcRedistCannotInstallFailure'
                            RecommendedAction = "Please install the latest [Microsoft Visual C++ 2015-2022 Runtime] as an admin, then try again."
                        }
                        throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                    }

                    # Install MSVCRT onto device.
                    & $Script:CommandTable.'Repair-ADTWinGetVisualStudioRuntime'

                    # Throw if we're still not able to run WinGet.
                    if (!(& $wingetPath))
                    {
                        $naerParams = @{
                            Exception = [System.InvalidOperationException]::new("The installed version of WinGet was unable to run. This is possibly related to a missing [Microsoft Visual C++ 2015-2022 Runtime] library.")
                            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                            ErrorId = 'MicrosoftDesktopAppInstallerExecutionFailure'
                            RecommendedAction = "Please verify that WinGet.exe can run on this system, then try again."
                        }
                        throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                    }
                }
                else
                {
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Successfully confirmed that [Microsoft Visual C++ 2015-2022 Runtime] is installed on system."
                }

                # Ensure winget.exe is above the minimum version.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Testing whether the installed WinGet is version [$($Script:ADT.WinGetMinVersion)] or higher, please wait..."
                if (([System.Version]$wingetVer = (& $Script:CommandTable.'Get-ADTWinGetVersion' -InformationAction SilentlyContinue).Trim('v')) -lt $Script:ADT.WinGetMinVersion)
                {
                    # Throw if we're not admin.
                    if (!$Script:ADT.RunningAsAdmin)
                    {
                        $naerParams = @{
                            Exception = [System.Activities.VersionMismatchException]::new("The installed WinGet version of [$wingetVer] is less than [$($Script:ADT.WinGetMinVersion)]. Please update [Microsoft.DesktopAppInstaller] and try again.", [System.Activities.WorkflowIdentity]::new('winget.exe', $wingetVer, $wingetPath.FullName), [System.Activities.WorkflowIdentity]::new('winget.exe', $Script:ADT.WinGetMinVersion, $wingetPath.FullName))
                            Category = [System.Management.Automation.ErrorCategory]::PermissionDenied
                            ErrorId = 'VcRedistCannotInstallFailure'
                            RecommendedAction = "Please update [Microsoft.DesktopAppInstaller] as an admin, then try again."
                        }
                        throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                    }

                    # Install the missing dependency and reset variables.
                    & $Script:CommandTable.'Repair-ADTWinGetDesktopAppInstaller'
                    $wingetPath = & $Script:CommandTable.'Get-ADTWinGetPath'

                    # Ensure winget.exe is above the minimum version.
                    & $Script:CommandTable.'Assert-ADTWinGetPackageManager'

                    # Reset WinGet sources after updating. Helps with a corner-case issue discovered.
                    & $Script:CommandTable.'Reset-ADTWinGetSource' -All
                }
                else
                {
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Successfully confirmed WinGet version [$wingetVer] is installed on system."
                }
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to repair the WinGet package manager."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Reset-ADTWinGetSource
#
#-----------------------------------------------------------------------------

function Reset-ADTWinGetSource
{
    <#
    .SYNOPSIS
        Resets WinGet sources.

    .DESCRIPTION
        Resets a named WinGet source by removing the source configuration. You can reset all configured sources and add the default source configurations using the All switch parameter. This command must be executed with administrator permissions.

    .PARAMETER Name
        The name of the source.

    .PARAMETER All
        Reset all sources and add the default sources.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Reset-ADTWinGetSource -Name msstore

        This example resets the configured source named 'msstore' by removing it.

    .EXAMPLE
        Reset-ADTWinGetSource -All

        This example resets all configured sources and adds the default sources.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [System.Management.Automation.SwitchParameter]$All
    )

    begin
    {
        # Confirm WinGet is good to go.
        try
        {
            & $Script:CommandTable.'Assert-ADTWinGetPackageManager'
        }
        catch
        {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                # Reset all sources if specified.
                if ($All)
                {
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Resetting all WinGet sources, please wait..."
                    if (!($wgSrcRes = & (& $Script:CommandTable.'Get-ADTWinGetPath') source reset --force 2>&1).Equals('Resetting all sources...Done'))
                    {
                        $naerParams = @{
                            Exception = [System.Runtime.InteropServices.ExternalException]::new("Failed to reset all WinGet sources. $($wgSrcRes.TrimEnd('.')).", $Global:LASTEXITCODE)
                            Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                            ErrorId = 'WinGetSourceAllResetFailure'
                            TargetObject = $wgSrcRes
                            RecommendedAction = "Please review the result in this error's TargetObject property and try again."
                        }
                        throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                    }
                    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Successfully reset all WinGet sources."
                    return
                }

                # Reset the specified source.
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Resetting WinGet source [$Name], please wait..."
                if (!($wgSrcRes = & (& $Script:CommandTable.'Get-ADTWinGetPath') source reset $Name 2>&1).Equals("Resetting source: $Name...Done"))
                {
                    $naerParams = @{
                        Exception = [System.Runtime.InteropServices.ExternalException]::new("Failed to WinGet source [$Name]. $($wgSrcRes.TrimEnd('.')).", $Global:LASTEXITCODE)
                        Category = [System.Management.Automation.ErrorCategory]::InvalidResult
                        ErrorId = "WinGetNamedSourceResetFailure"
                        TargetObject = $wgSrcRes
                        RecommendedAction = "Please review the result in this error's TargetObject property and try again."
                    }
                    throw (& $Script:CommandTable.'New-ADTErrorRecord' @naerParams)
                }
                & $Script:CommandTable.'Write-ADTLogEntry' -Message "Successfully WinGet source [$Name]."
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to repair the specified WinGet source(s)."
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Uninstall-ADTWinGetPackage
#
#-----------------------------------------------------------------------------

function Uninstall-ADTWinGetPackage
{
    <#
    .SYNOPSIS
        Uninstalls a WinGet Package.

    .DESCRIPTION
        This command uninstalls a WinGet package from your computer. The command includes parameters to specify values used to search for installed packages. By default, all string-based searches are case-insensitive substring searches. Wildcards are not supported.

    .PARAMETER Query
        Specify one or more strings to search for. By default, the command searches all configured sources.

    .PARAMETER MatchOption
        Specify matching logic used for search.

    .PARAMETER Force
        Force the installer to run even when other checks WinGet would perform would prevent this action.

    .PARAMETER Id
        Specify the package identifier to search for. The command does a case-insensitive full text match, rather than a substring match.

    .PARAMETER Log
        Specify the location for the installer log. The value can be a fully-qualified or relative path and must include the file name. For example: `$env:TEMP\package.log`.

    .PARAMETER Mode
        Specify the output mode for the installer.

    .PARAMETER Moniker
        Specify the moniker of the WinGet package to install. For example, the moniker for the Microsoft.PowerShell package is `pwsh`.

    .PARAMETER Name
        Specify the name of the package to be installed.

    .PARAMETER Scope
        Specify WinGet package installer scope.

    .PARAMETER Source
        Specify the name of the WinGet source from which the package should be installed.

    .PARAMETER Version
        Specify the version of the package.

    .PARAMETER PassThru
        Returns an object detailing the operation, just as Microsoft's module does by default.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        PSObject

        This function returns a PSObject containing the outcome of the operation.

    .EXAMPLE
        Uninstall-ADTWinGetPackage -Id Microsoft.PowerShell

        This example shows how to uninstall a package by the specifying the package identifier. If the package identifier is available from more than one source, you must provide additional search criteria to select a specific instance of the package.

    .EXAMPLE
        Uninstall-ADTWinGetPackage -Name "PowerToys (Preview)"

        This sample uninstalls the PowerToys package by the specifying the package name.

    .EXAMPLE
        Uninstall-ADTWinGetPackage Microsoft.PowerShell -Version 7.4.4.0

        This example shows how to uninstall a specific version of a package using a query. The command does a query search for packages matching `Microsoft.PowerShell`. The results of the search a limited to matches with the version of `7.4.4.0`.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Query,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Equals', 'EqualsCaseInsensitive')]
        [System.String]$MatchOption,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$Force,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Log,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Silent', 'Interactive')]
        [System.String]$Mode,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Moniker,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Any', 'User', 'System', 'UserOrUnknown', 'SystemOrUnknown')]
        [System.String]$Scope,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Source,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Version,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$PassThru
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        $null = $PSBoundParameters.Remove('PassThru')
    }

    process
    {
        # Initialise variables before proceeding.
        $wingetResult = $null
        try
        {
            try
            {
                # Perform the required operation.
                $wingetResult = & $Script:CommandTable.'Invoke-ADTWinGetDeploymentOperation' -Action Uninstall @PSBoundParameters
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }

            # Throw if the result has an ErrorRecord.
            if ($wingetResult.ExtendedErrorCode)
            {
                & $Script:CommandTable.'Write-Error' -ErrorRecord $wingetResult.ExtendedErrorCode
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to uninstall the specified WinGet package." -DisableErrorResolving:($null -ne $wingetResult)
        }

        # If we have a result and are passing through, return it.
        if ($wingetResult -and $PassThru)
        {
            return $wingetResult
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Update-ADTWinGetPackage
#
#-----------------------------------------------------------------------------

function Update-ADTWinGetPackage
{
    <#
    .SYNOPSIS
        Installs a newer version of a previously installed WinGet package.

    .DESCRIPTION
        This command searches the packages installed on your system and installs a newer version of the matching WinGet package. The command includes parameters to specify values used to search for packages in the configured sources. By default, the command searches the winget source. All string-based searches are case-insensitive substring searches. Wildcards are not supported.

    .PARAMETER Query
        Specify one or more strings to search for. By default, the command searches all configured sources.

    .PARAMETER MatchOption
        Specify matching logic used for search.

    .PARAMETER AllowHashMismatch
        Allows you to download package even when the SHA256 hash for an installer or a dependency does not match the SHA256 hash in the WinGet package manifest.

    .PARAMETER Architecture
        Specify the processor architecture for the WinGet package installer.

    .PARAMETER Custom
        Use this parameter to pass additional arguments to the installer. The parameter takes a single string value. To add multiple arguments, include the arguments in the string. The arguments must be provided in the format expected by the installer. If the string contains spaces, it must be enclosed in quotes. This string is added to the arguments defined in the package manifest.

    .PARAMETER Force
        Force the installer to run even when other checks WinGet would perform would prevent this action.

    .PARAMETER Header
        Custom value to be passed via HTTP header to WinGet REST sources.

    .PARAMETER Id
        Specify the package identifier to search for. The command does a case-insensitive full text match, rather than a substring match.

    .PARAMETER IncludeUnknown
        Use this parameter to upgrade the package when the installed version is not specified in the registry.

    .PARAMETER InstallerType
        A package may contain multiple installer types.

    .PARAMETER Locale
        Specify the locale of the installer package. The locale must provided in the BCP 47 format, such as `en-US`. For more information, see Standard locale names (/globalization/locale/standard-locale-names).

    .PARAMETER Location
        Specify the file path where you want the packed to be installed. The installer must be able to support alternate install locations.

    .PARAMETER Log
        Specify the location for the installer log. The value can be a fully-qualified or relative path and must include the file name. For example: `$env:TEMP\package.log`.

    .PARAMETER Mode
        Specify the output mode for the installer.

    .PARAMETER Moniker
        Specify the moniker of the WinGet package to install. For example, the moniker for the Microsoft.PowerShell package is `pwsh`.

    .PARAMETER Name
        Specify the name of the package to be installed.

    .PARAMETER Override
        Use this parameter to override the existing arguments passed to the installer. The parameter takes a single string value. To add multiple arguments, include the arguments in the string. The arguments must be provided in the format expected by the installer. If the string contains spaces, it must be enclosed in quotes. This string overrides the arguments specified in the package manifest.

    .PARAMETER Scope
        Specify WinGet package installer scope.

    .PARAMETER SkipDependencies
        Specifies that the command shouldn't install the WinGet package dependencies.

    .PARAMETER Source
        Specify the name of the WinGet source from which the package should be installed.

    .PARAMETER Version
        Specify the version of the package.

    .PARAMETER DebugHashMismatch
        Forces the AllowHashMismatch for debugging purposes.

    .PARAMETER PassThru
        Returns an object detailing the operation, just as Microsoft's module does by default.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        PSObject

        This function returns a PSObject containing the outcome of the operation.

    .EXAMPLE
        Update-ADTWinGetPackage -Id Microsoft.PowerShell

        This example shows how to update a package by the specifying the package identifier. If the package identifier is available from more than one source, you must provide additional search criteria to select a specific instance of the package.

    .EXAMPLE
        Update-ADTWinGetPackage -Name "PowerToys (Preview)"

        This sample updates the PowerToys package by the specifying the package name.

    .EXAMPLE
        Update-ADTWinGetPackage Microsoft.PowerShell -Version 7.4.4.0

        This example shows how to update a specific version of a package using a query. The command does a query search for packages matching `Microsoft.PowerShell`. The results of the search a limited to matches with the version of `7.4.4.0`.

    .LINK
        https://github.com/mjr4077au/PSAppDeployToolkit.WinGet
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Query,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Equals', 'EqualsCaseInsensitive')]
        [System.String]$MatchOption,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$AllowHashMismatch,

        [Parameter(Mandatory = $false)]
        [ValidateSet('x86', 'x64', 'arm64')]
        [System.String]$Architecture,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Custom,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$Force,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Header,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Id,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$IncludeUnknown,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Inno', 'Wix', 'Msi', 'Nullsoft', 'Zip', 'Msix', 'Exe', 'Burn', 'MSStore', 'Portable')]
        [System.String]$InstallerType,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Locale,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Location,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Log,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Silent', 'Interactive')]
        [System.String]$Mode,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Moniker,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Override,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Any', 'User', 'System', 'UserOrUnknown', 'SystemOrUnknown')]
        [System.String]$Scope,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$SkipDependencies,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Source,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Version,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$DebugHashMismatch,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$PassThru
    )

    begin
    {
        # Initialize function.
        & $Script:CommandTable.'Initialize-ADTFunction' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        $null = $PSBoundParameters.Remove('PassThru')
    }

    process
    {
        # Initialise variables before proceeding.
        $wingetResult = $null
        try
        {
            try
            {
                # Perform the required operation.
                $wingetResult = & $Script:CommandTable.'Invoke-ADTWinGetDeploymentOperation' -Action Upgrade @PSBoundParameters
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                & $Script:CommandTable.'Write-Error' -ErrorRecord $_
            }

            # Throw if the result has an ErrorRecord.
            if ($wingetResult.ExtendedErrorCode)
            {
                & $Script:CommandTable.'Write-Error' -ErrorRecord $wingetResult.ExtendedErrorCode
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            & $Script:CommandTable.'Invoke-ADTFunctionErrorHandler' -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to update the specified WinGet package." -DisableErrorResolving:($null -ne $wingetResult)
        }

        # If we have a result and are passing through, return it.
        if ($wingetResult -and $PassThru)
        {
            return $wingetResult
        }
    }

    end
    {
        # Finalize function.
        & $Script:CommandTable.'Complete-ADTFunction' -Cmdlet $PSCmdlet
    }
}


#-----------------------------------------------------------------------------
#
# MARK: Module Constants and Function Exports
#
#-----------------------------------------------------------------------------

# Rethrowing caught exceptions makes the error output from Import-Module look better.
try
{
    # Set all functions as read-only, export all public definitions and finalise the CommandTable.
    & $Script:CommandTable.'Set-Item' -LiteralPath $FunctionPaths -Options ReadOnly
    & $Script:CommandTable.'Get-Item' -LiteralPath $FunctionPaths | & { process { $CommandTable.Add($_.Name, $_) } }
    & $Script:CommandTable.'New-Variable' -Name CommandTable -Value ([System.Collections.ObjectModel.ReadOnlyDictionary[System.String, System.Management.Automation.CommandInfo]]::new($CommandTable)) -Option Constant -Force -Confirm:$false
    & $Script:CommandTable.'Export-ModuleMember' -Function $Module.Manifest.FunctionsToExport

    # Store module globals needed for the lifetime of the module.
    $currentWindowsIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try
    {
        & $Script:CommandTable.'New-Variable' -Name ADT -Option Constant -Value ([pscustomobject]@{
                WinGetMinVersion = [System.Version]::new(1, 10, 390)
                RunningAsSystem = $currentWindowsIdentity.User.IsWellKnown([System.Security.Principal.WellKnownSidType]::LocalSystemSid)
                RunningAsAdmin = & $Script:CommandTable.'Test-ADTCallerIsAdmin'
                SystemArchitecture = [System.Runtime.InteropServices.RuntimeInformation, mscorlib, Version = 4.0.0.0, Culture = neutral, PublicKeyToken = b77a5c561934e089]::OSArchitecture.ToString().ToLower()
            })
    }
    finally
    {
        $currentWindowsIdentity.Dispose()
        & $Script:CommandTable.'Remove-Variable' -Name currentWindowsIdentity -Force -Confirm:$false
    }

    # Announce successful importation of module.
    & $Script:CommandTable.'Write-ADTLogEntry' -Message "Module [PSAppDeployToolkit.WinGet] imported successfully." -ScriptSection Initialization -Source 'PSAppDeployToolkit.WinGet.psm1'
}
catch
{
    throw
}


