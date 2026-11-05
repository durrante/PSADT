@{
    RootModule        = 'PSAppDeployToolkit.MSStore.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '3f6d2a8e-5b1c-4e7a-9d42-8c1f0b7e6a53'
    Author            = 'Alex Durrant'
    Description       = 'Provisions Microsoft Store (MSIX/AppX) apps for all users, downloading the latest version directly from the Microsoft Store delivery service.'
    PowerShellVersion = '5.1.14393.0'
    CLRVersion        = '4.0.30319.42000'
    RequiredModules   = @(
        @{ ModuleName = 'PSAppDeployToolkit'; GUID = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.0' }
    )
    FunctionsToExport = @(
        'Get-ADTMSStoreApp'
        'Save-ADTMSStoreApp'
        'Install-ADTMSStoreApp'
        'Uninstall-ADTMSStoreApp'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{} }
}
