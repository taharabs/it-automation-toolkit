BeforeAll {
    . (Join-Path $PSScriptRoot 'Stubs.ps1')
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ITToolkit/ITToolkit.psd1') -Force
}

Describe 'Module' {
    It 'exports exactly the public commands' {
        $exported = @((Get-Module ITToolkit).ExportedFunctions.Keys | Sort-Object)
        $exported | Should -Be @(
            'Disable-DepartedADUser', 'Export-ToolkitReport', 'Get-DiskSpaceReport',
            'Get-StaleADAccount', 'Invoke-PingSweep', 'New-ADUserFromCsv', 'Test-BackupFreshness'
        )
    }

    It 'has comment-based help with an example for every command' {
        foreach ($name in (Get-Module ITToolkit).ExportedFunctions.Keys) {
            $help = Get-Help $name
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$name needs a synopsis"
            @($help.Examples.Example).Count | Should -BeGreaterThan 0 -Because "$name needs an example"
        }
    }
}

Describe 'ConvertTo-SamAccountName' {
    It 'builds <Expected> from <First> <Last> (<Format>)' -ForEach @(
        @{ First = 'Yacine'; Last = 'Haddad'; Format = 'FirstInitialLastName'; Expected = 'yhaddad' }
        @{ First = 'Yacine'; Last = 'Haddad'; Format = 'FirstDotLast'; Expected = 'yacine.haddad' }
        @{ First = 'Leila'; Last = 'Ait-Ouali'; Format = 'FirstInitialLastName'; Expected = 'laitouali' }
        @{ First = 'Sean'; Last = "O'Neil"; Format = 'FirstInitialLastName'; Expected = 'soneil' }
        @{ First = 'Mohamed Tahar'; Last = 'Ababsa'; Format = 'FirstDotLast'; Expected = 'mohamedtahar.ababsa' }
    ) {
        InModuleScope ITToolkit -Parameters $_ {
            ConvertTo-SamAccountName -FirstName $First -LastName $Last -Format $Format | Should -Be $Expected
        }
    }

    It 'removes accents' {
        InModuleScope ITToolkit {
            # "Hélène Bénali", written with escapes so the file stays ASCII
            $first = "H$([char]0x00E9)l$([char]0x00E8)ne"
            $last = "B$([char]0x00E9)nali"
            ConvertTo-SamAccountName -FirstName $first -LastName $last | Should -Be 'hbenali'
        }
    }

    It 'never exceeds 20 characters' {
        InModuleScope ITToolkit {
            $name = ConvertTo-SamAccountName -FirstName 'Abdelkaderabdelkader' -LastName 'Benabdelmoumene' -Format FirstDotLast
            $name.Length | Should -BeLessOrEqual 20
            $name | Should -Not -Match '\.$'
        }
    }

    It 'refuses names with no usable letters' {
        InModuleScope ITToolkit {
            { ConvertTo-SamAccountName -FirstName '123' -LastName 'Haddad' } | Should -Throw
        }
    }
}

Describe 'Get-RandomPassword' {
    It 'has the requested length and every character class' {
        InModuleScope ITToolkit {
            foreach ($i in 1..50) {
                $password = Get-RandomPassword -Length 14
                $password.Length | Should -Be 14
                $password | Should -MatchExactly '[A-Z]'
                $password | Should -MatchExactly '[a-z]'
                $password | Should -Match '[0-9]'
                $password | Should -Match '[^A-Za-z0-9]'
                $password | Should -Not -MatchExactly '[0O1lI]'
            }
        }
    }

    It 'does not repeat itself' {
        InModuleScope ITToolkit {
            $set = @(1..200 | ForEach-Object { Get-RandomPassword }) | Sort-Object -Unique
            @($set).Count | Should -Be 200
        }
    }

    It 'refuses short passwords' {
        InModuleScope ITToolkit {
            { Get-RandomPassword -Length 8 } | Should -Throw
        }
    }
}

Describe 'Get-IPv4Range' {
    It 'expands <Cidr> to <Count> hosts from <First> to <Last>' -ForEach @(
        @{ Cidr = '192.168.1.0/24'; Count = 254; First = '192.168.1.1'; Last = '192.168.1.254' }
        @{ Cidr = '10.0.0.77/24'; Count = 254; First = '10.0.0.1'; Last = '10.0.0.254' }
        @{ Cidr = '172.16.5.8/30'; Count = 2; First = '172.16.5.9'; Last = '172.16.5.10' }
        @{ Cidr = '10.1.2.3/32'; Count = 1; First = '10.1.2.3'; Last = '10.1.2.3' }
        @{ Cidr = '10.1.2.2/31'; Count = 2; First = '10.1.2.2'; Last = '10.1.2.3' }
        @{ Cidr = '10.20.0.0/16'; Count = 65534; First = '10.20.0.1'; Last = '10.20.255.254' }
    ) {
        InModuleScope ITToolkit -Parameters $_ {
            $range = @(Get-IPv4Range -Cidr $Cidr)
            $range.Count | Should -Be $Count
            $range[0] | Should -Be $First
            $range[-1] | Should -Be $Last
        }
    }

    It 'rejects <Cidr>' -ForEach @(
        @{ Cidr = '10.0.0.0/8' }
        @{ Cidr = '10.0.0.0' }
        @{ Cidr = '300.1.1.1/24' }
        @{ Cidr = 'server/24' }
    ) {
        InModuleScope ITToolkit -Parameters $_ {
            { Get-IPv4Range -Cidr $Cidr } | Should -Throw
        }
    }
}
