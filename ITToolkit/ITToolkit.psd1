@{
    RootModule           = 'ITToolkit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '55ded6db-f3fb-4d37-a6a4-99602566dcbb'
    Author               = 'Mohamed Tahar Ababsa'
    Copyright            = '(c) 2026 Mohamed Tahar Ababsa. MIT License.'
    Description          = 'Everyday IT administration as safe, testable PowerShell: Active Directory onboarding and offboarding, stale accounts, disk space, backup freshness and network sweeps, with HTML reports.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'New-ADUserFromCsv'
        'Disable-DepartedADUser'
        'Get-StaleADAccount'
        'Get-DiskSpaceReport'
        'Test-BackupFreshness'
        'Invoke-PingSweep'
        'Export-ToolkitReport'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'SysAdmin', 'Automation', 'Monitoring', 'Backup', 'Windows')
            LicenseUri = 'https://github.com/taharabs/it-automation-toolkit/blob/main/LICENSE'
            ProjectUri = 'https://github.com/taharabs/it-automation-toolkit'
        }
    }
}
