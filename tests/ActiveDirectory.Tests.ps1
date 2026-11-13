BeforeAll {
    . (Join-Path $PSScriptRoot 'Stubs.ps1')
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ITToolkit/ITToolkit.psd1') -Force

    function New-HrCsv {
        param([string] $Path, [object[]] $Rows)
        $Rows | ForEach-Object { [pscustomobject]$_ } | Export-Csv -LiteralPath $Path -NoTypeInformation
        $Path
    }

    $defaultOU = 'OU=Staff,DC=contoso,DC=local'
    $ouMap = @{
        IT    = 'OU=IT,OU=Staff,DC=contoso,DC=local'
        Sales = 'OU=Sales,OU=Staff,DC=contoso,DC=local'
    }
    $groupMap = @{ IT = @('GG-IT', 'GG-VPN') }
}

Describe 'New-ADUserFromCsv' {
    BeforeEach {
        Mock -ModuleName ITToolkit Get-ADUser { $null }
        Mock -ModuleName ITToolkit New-ADUser { }
        Mock -ModuleName ITToolkit Add-ADGroupMember { }
    }

    It 'creates accounts in the right OU, with groups and a temporary password' {
        $csv = New-HrCsv -Path (Join-Path $TestDrive 'hires.csv') -Rows @(
            @{ FirstName = 'Yacine'; LastName = 'Haddad'; Department = 'IT'; Title = 'Technician' }
            @{ FirstName = 'Amina'; LastName = 'Belkacem'; Department = 'Sales'; Title = '' }
        )

        $result = @(New-ADUserFromCsv -Path $csv -UpnSuffix contoso.local -DefaultOU $defaultOU -OUMap $ouMap -GroupMap $groupMap)

        $result.Status | Should -Be @('Created', 'Created')
        $result[0].SamAccountName | Should -Be 'yhaddad'
        $result[0].UserPrincipalName | Should -Be 'yhaddad@contoso.local'
        $result[0].OU | Should -Be $ouMap.IT
        $result[0].InitialPassword.Length | Should -Be 16
        $result[1].OU | Should -Be $ouMap.Sales

        Should -Invoke -ModuleName ITToolkit New-ADUser -Times 1 -Exactly -ParameterFilter {
            $SamAccountName -eq 'yhaddad' -and $Path -eq 'OU=IT,OU=Staff,DC=contoso,DC=local' -and
            $Title -eq 'Technician' -and $ChangePasswordAtLogon -eq $true -and $Enabled -eq $true -and
            $AccountPassword -is [securestring]
        }
        Should -Invoke -ModuleName ITToolkit Add-ADGroupMember -Times 2 -Exactly
        Should -Invoke -ModuleName ITToolkit Add-ADGroupMember -Times 1 -Exactly -ParameterFilter {
            $Identity -eq 'GG-VPN' -and $Members -eq 'yhaddad'
        }
    }

    It 'uses the default OU for an unknown department' {
        $csv = New-HrCsv -Path (Join-Path $TestDrive 'hires.csv') -Rows @(
            @{ FirstName = 'Sarah'; LastName = 'Boudiaf'; Department = 'Logistics' }
        )
        $result = New-ADUserFromCsv -Path $csv -UpnSuffix contoso.local -DefaultOU $defaultOU -OUMap $ouMap
        $result.OU | Should -Be $defaultOU
    }

    It 'adds a number when the logon name is already taken, in AD or earlier in the file' {
        Mock -ModuleName ITToolkit Get-ADUser { [pscustomobject]@{ SamAccountName = 'yhaddad' } } -ParameterFilter {
            $Filter -eq "SamAccountName -eq 'yhaddad'"
        }
        $csv = New-HrCsv -Path (Join-Path $TestDrive 'hires.csv') -Rows @(
            @{ FirstName = 'Yacine'; LastName = 'Haddad'; Department = 'IT' }
            @{ FirstName = 'Youcef'; LastName = 'Haddad'; Department = 'IT' }
        )
        $result = @(New-ADUserFromCsv -Path $csv -UpnSuffix contoso.local -DefaultOU $defaultOU)
        $result.SamAccountName | Should -Be @('yhaddad2', 'yhaddad3')
    }

    It 'skips incomplete rows and keeps going' {
        $csv = New-HrCsv -Path (Join-Path $TestDrive 'hires.csv') -Rows @(
            @{ FirstName = ''; LastName = 'Haddad'; Department = 'IT' }
            @{ FirstName = 'Amina'; LastName = 'Belkacem'; Department = 'Sales' }
        )
        $result = @(New-ADUserFromCsv -Path $csv -UpnSuffix contoso.local -DefaultOU $defaultOU)
        $result.Status | Should -Be @('Skipped', 'Created')
        $result[0].Line | Should -Be 2
    }

    It 'reports a failure without stopping the batch' {
        Mock -ModuleName ITToolkit New-ADUser { throw 'The specified account already exists' } -ParameterFilter {
            $SamAccountName -eq 'abelkacem'
        }
        $csv = New-HrCsv -Path (Join-Path $TestDrive 'hires.csv') -Rows @(
            @{ FirstName = 'Amina'; LastName = 'Belkacem'; Department = 'Sales' }
            @{ FirstName = 'Sarah'; LastName = 'Boudiaf'; Department = 'Sales' }
        )
        $result = @(New-ADUserFromCsv -Path $csv -UpnSuffix contoso.local -DefaultOU $defaultOU)
        $result.Status | Should -Be @('Failed', 'Created')
        $result[0].Message | Should -Match 'already exists'
        $result[0].InitialPassword | Should -BeNullOrEmpty
    }

    It 'changes nothing with -WhatIf' {
        $csv = New-HrCsv -Path (Join-Path $TestDrive 'hires.csv') -Rows @(
            @{ FirstName = 'Yacine'; LastName = 'Haddad'; Department = 'IT' }
        )
        $result = New-ADUserFromCsv -Path $csv -UpnSuffix contoso.local -DefaultOU $defaultOU -GroupMap $groupMap -WhatIf
        $result.Status | Should -Be 'WouldCreate'
        $result.Groups | Should -Be 'GG-IT; GG-VPN'
        $result.InitialPassword | Should -BeNullOrEmpty
        Should -Invoke -ModuleName ITToolkit New-ADUser -Times 0
        Should -Invoke -ModuleName ITToolkit Add-ADGroupMember -Times 0
    }
}

Describe 'Disable-DepartedADUser' {
    BeforeEach {
        $dn = 'CN=Yacine Haddad,OU=IT,OU=Staff,DC=contoso,DC=local'
        Mock -ModuleName ITToolkit Get-ADUser {
            [pscustomobject]@{
                Name              = 'Yacine Haddad'
                SamAccountName    = 'yhaddad'
                DistinguishedName = 'CN=Yacine Haddad,OU=IT,OU=Staff,DC=contoso,DC=local'
                Description       = ''
                MemberOf          = @('CN=GG-IT,OU=Groups,DC=contoso,DC=local', 'CN=GG-VPN,OU=Groups,DC=contoso,DC=local')
            }
        }
        Mock -ModuleName ITToolkit Disable-ADAccount { }
        Mock -ModuleName ITToolkit Set-ADUser { }
        Mock -ModuleName ITToolkit Remove-ADGroupMember { }
        Mock -ModuleName ITToolkit Move-ADObject { }
        $audit = Join-Path $TestDrive "audit-$([guid]::NewGuid().ToString('N')).csv"
        $disabledOU = 'OU=Disabled,DC=contoso,DC=local'
    }

    It 'disables, records groups, removes them and moves the account' {
        $result = Disable-DepartedADUser -Identity yhaddad -DisabledOU $disabledOU -AuditPath $audit -Reason 'Contract ended' -Confirm:$false

        $result.Status | Should -Be 'Disabled'
        $result.GroupsRemoved | Should -Be 2
        Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 1 -Exactly -ParameterFilter { $Identity -eq $dn }
        Should -Invoke -ModuleName ITToolkit Set-ADUser -Times 1 -Exactly -ParameterFilter { $Description -match '^Disabled \d{4}-\d{2}-\d{2} by .+: Contract ended$' }
        Should -Invoke -ModuleName ITToolkit Remove-ADGroupMember -Times 2 -Exactly
        Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 1 -Exactly -ParameterFilter { $TargetPath -eq $disabledOU }

        $rows = @(Import-Csv -LiteralPath $audit)
        $rows.Count | Should -Be 2
        $rows[0].SamAccountName | Should -Be 'yhaddad'
        $rows.Group | Should -Contain 'CN=GG-VPN,OU=Groups,DC=contoso,DC=local'
    }

    It 'appends to an existing audit file' {
        Disable-DepartedADUser -Identity yhaddad -DisabledOU $disabledOU -AuditPath $audit -Confirm:$false | Out-Null
        Disable-DepartedADUser -Identity yhaddad -DisabledOU $disabledOU -AuditPath $audit -Confirm:$false | Out-Null
        @(Import-Csv -LiteralPath $audit).Count | Should -Be 4
    }

    It 'accepts accounts from the pipeline' {
        $result = @(
            [pscustomobject]@{ SamAccountName = 'yhaddad' },
            [pscustomobject]@{ SamAccountName = 'abelkacem' }
        ) | Disable-DepartedADUser -DisabledOU $disabledOU -AuditPath $audit -Confirm:$false
        @($result).Count | Should -Be 2
        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter { $Identity -eq 'abelkacem' }
    }

    It 'changes nothing with -WhatIf' {
        $result = Disable-DepartedADUser -Identity yhaddad -DisabledOU $disabledOU -AuditPath $audit -WhatIf
        $result.Status | Should -Be 'WouldDisable'
        Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 0
        Should -Invoke -ModuleName ITToolkit Remove-ADGroupMember -Times 0
        Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 0
        Test-Path -LiteralPath $audit | Should -BeFalse
    }

    It 'reports an unknown account as Failed' {
        Mock -ModuleName ITToolkit Get-ADUser { throw 'Cannot find an object with identity: nobody' }
        $result = Disable-DepartedADUser -Identity nobody -DisabledOU $disabledOU -AuditPath $audit -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'Cannot find'
        Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 0
    }
}

Describe 'Get-StaleADAccount' {
    BeforeEach {
        $now = Get-Date
        Mock -ModuleName ITToolkit Get-ADUser {
            @(
                [pscustomobject]@{ Name = 'Active'; SamAccountName = 'active'; LastLogonDate = $now.AddDays(-3); whenCreated = $now.AddYears(-2); DistinguishedName = 'CN=Active' }
                [pscustomobject]@{ Name = 'Gone'; SamAccountName = 'gone'; LastLogonDate = $now.AddDays(-200); whenCreated = $now.AddYears(-3); DistinguishedName = 'CN=Gone' }
                [pscustomobject]@{ Name = 'Never old'; SamAccountName = 'neverold'; LastLogonDate = $null; whenCreated = $now.AddDays(-120); DistinguishedName = 'CN=NeverOld' }
                [pscustomobject]@{ Name = 'Never new'; SamAccountName = 'nevernew'; LastLogonDate = $null; whenCreated = $now.AddDays(-5); DistinguishedName = 'CN=NeverNew' }
            )
        }
        Mock -ModuleName ITToolkit Get-ADComputer {
            [pscustomobject]@{ Name = 'PC-OLD'; SamAccountName = 'PC-OLD$'; LastLogonDate = $now.AddDays(-400); whenCreated = $now.AddYears(-5); DistinguishedName = 'CN=PC-OLD' }
        }
    }

    It 'returns inactive and never-used accounts, not recent ones' {
        $stale = @(Get-StaleADAccount -Days 90)
        $stale.SamAccountName | Should -Be @('gone', 'neverold')
        $stale[0].Status | Should -Be 'Stale'
        $stale[0].DaysInactive | Should -BeGreaterOrEqual 199
        $stale[1].Status | Should -Be 'NeverLoggedOn'
    }

    It 'queries enabled accounts only, in the given OU' {
        Get-StaleADAccount -Days 30 -SearchBase 'OU=Staff,DC=contoso,DC=local' | Out-Null
        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter {
            $Filter -eq "Enabled -eq 'True'" -and $SearchBase -eq 'OU=Staff,DC=contoso,DC=local'
        }
    }

    It 'works for computers' {
        $stale = Get-StaleADAccount -Type Computer -Days 90
        $stale.Name | Should -Be 'PC-OLD'
        $stale.Type | Should -Be 'Computer'
    }
}
