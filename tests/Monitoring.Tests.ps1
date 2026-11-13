BeforeAll {
    . (Join-Path $PSScriptRoot 'Stubs.ps1')
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ITToolkit/ITToolkit.psd1') -Force

    function New-Disk {
        param([string] $Id, [double] $SizeGB, [double] $FreeGB)
        [pscustomobject]@{ DeviceID = $Id; Size = $SizeGB * 1GB; FreeSpace = $FreeGB * 1GB }
    }
}

Describe 'Get-DiskSpaceReport' {
    BeforeEach {
        Mock -ModuleName ITToolkit Get-CimInstance {
            New-Disk -Id 'C:' -SizeGB 100 -FreeGB 50
            New-Disk -Id 'D:' -SizeGB 500 -FreeGB 75
            New-Disk -Id 'E:' -SizeGB 200 -FreeGB 10
        }
        Mock -ModuleName ITToolkit Get-CimInstance { throw 'The RPC server is unavailable.' } -ParameterFilter {
            $ComputerName -eq 'SRV-DOWN'
        }
    }

    It 'classifies each fixed disk' {
        $report = @(Get-DiskSpaceReport -ComputerName SRV-FILE01 -WarningPercent 20 -CriticalPercent 10)
        $report.Drive | Should -Be @('C:', 'D:', 'E:')
        $report.FreePercent | Should -Be @(50, 15, 5)
        $report.Status | Should -Be @('OK', 'Warning', 'Critical')
        $report[1].SizeGB | Should -Be 500
        $report[1].FreeGB | Should -Be 75
    }

    It 'asks only for local fixed disks on the remote machine' {
        Get-DiskSpaceReport -ComputerName SRV-FILE01 | Out-Null
        Should -Invoke -ModuleName ITToolkit Get-CimInstance -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_LogicalDisk' -and $Filter -eq 'DriveType=3' -and $ComputerName -eq 'SRV-FILE01'
        }
    }

    It 'queries the local machine without a remote connection' {
        Get-DiskSpaceReport -ComputerName localhost | Out-Null
        Should -Invoke -ModuleName ITToolkit Get-CimInstance -Times 1 -Exactly -ParameterFilter { $null -eq $ComputerName }
    }

    It 'reports an unreachable machine and continues with the next one' {
        $report = @(Get-DiskSpaceReport -ComputerName SRV-DOWN, SRV-FILE01)
        $report.Count | Should -Be 4
        $report[0].Status | Should -Be 'Unreachable'
        $report[0].Message | Should -Match 'RPC'
        $report[1].ComputerName | Should -Be 'SRV-FILE01'
    }

    It 'accepts computer names from the pipeline' {
        $report = @([pscustomobject]@{ Name = 'SRV-A' }, [pscustomobject]@{ Name = 'SRV-B' } | Get-DiskSpaceReport)
        ($report.ComputerName | Sort-Object -Unique) | Should -Be @('SRV-A', 'SRV-B')
    }

    It 'rejects thresholds in the wrong order' {
        { Get-DiskSpaceReport -ComputerName SRV-FILE01 -WarningPercent 10 -CriticalPercent 20 } | Should -Throw
    }
}

Describe 'Test-BackupFreshness' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $sql = New-Item -ItemType Directory -Path (Join-Path $root 'sql')
        $files = New-Item -ItemType Directory -Path (Join-Path $root 'files')
        $empty = New-Item -ItemType Directory -Path (Join-Path $root 'empty')

        $old = New-Item -ItemType File -Path (Join-Path $sql 'erp_old.bak')
        [System.IO.File]::WriteAllBytes($old.FullName, (New-Object byte[] 2048))
        $old.LastWriteTime = (Get-Date).AddHours(-50)

        $fresh = New-Item -ItemType File -Path (Join-Path $sql 'erp_new.bak')
        [System.IO.File]::WriteAllBytes($fresh.FullName, (New-Object byte[] 4096))
        $fresh.LastWriteTime = (Get-Date).AddHours(-2)

        $stale = New-Item -ItemType File -Path (Join-Path $files 'files.zip')
        [System.IO.File]::WriteAllBytes($stale.FullName, (New-Object byte[] 1024))
        $stale.LastWriteTime = (Get-Date).AddHours(-30)
    }

    It 'judges each folder by its newest file' {
        $result = @(Test-BackupFreshness -Path $sql.FullName, $files.FullName, $empty.FullName, (Join-Path $root 'nope') -MaxAgeHours 26)
        $result.Status | Should -Be @('OK', 'Stale', 'Empty', 'Missing')
        $result[0].LatestFile | Should -Be 'erp_new.bak'
        $result[0].AgeHours | Should -BeLessThan 3
        $result[1].AgeHours | Should -BeGreaterThan 29
    }

    It 'flags a backup that is suspiciously small' {
        $result = Test-BackupFreshness -Path $sql.FullName -MinSizeMB 1
        $result.Status | Should -Be 'TooSmall'
    }

    It 'only looks at files matching the filter' {
        $result = Test-BackupFreshness -Path $files.FullName -Filter '*.bak'
        $result.Status | Should -Be 'Empty'
    }

    It 'can search sub-folders' {
        $nested = New-Item -ItemType Directory -Path (Join-Path $empty.FullName 'daily')
        $file = New-Item -ItemType File -Path (Join-Path $nested 'today.bak')
        [System.IO.File]::WriteAllBytes($file.FullName, (New-Object byte[] 10))
        (Test-BackupFreshness -Path $empty.FullName).Status | Should -Be 'Empty'
        (Test-BackupFreshness -Path $empty.FullName -Recurse).Status | Should -Be 'OK'
    }
}

Describe 'Invoke-PingSweep' {
    BeforeEach {
        Mock -ModuleName ITToolkit Invoke-PingBatch {
            foreach ($ip in $Address) {
                $online = $ip -in @('10.0.0.1', '10.0.0.5')
                [pscustomobject]@{ IPAddress = $ip; Online = $online; RoundtripMs = $(if ($online) { 3 } else { $null }) }
            }
        }
        Mock -ModuleName ITToolkit Resolve-HostName { "host-$($IPAddress.Split('.')[-1]).contoso.local" }
    }

    It 'returns only the hosts that answered' {
        $result = @(Invoke-PingSweep -Cidr 10.0.0.0/28)
        $result.IPAddress | Should -Be @('10.0.0.1', '10.0.0.5')
        @($result | Where-Object { $_.HostName }).Count | Should -Be 0
        Should -Invoke -ModuleName ITToolkit Resolve-HostName -Times 0
    }

    It 'splits the subnet into batches' {
        Invoke-PingSweep -Cidr 10.0.0.0/28 -BatchSize 5 | Out-Null
        Should -Invoke -ModuleName ITToolkit Invoke-PingBatch -Times 3 -Exactly
    }

    It 'can include offline hosts and resolve names' {
        $result = @(Invoke-PingSweep -Cidr 10.0.0.0/29 -IncludeOffline -ResolveNames)
        $result.Count | Should -Be 6
        ($result | Where-Object Online).HostName | Should -Be @('host-1.contoso.local', 'host-5.contoso.local')
        Should -Invoke -ModuleName ITToolkit Resolve-HostName -Times 2 -Exactly
    }

    It 'accepts a list of addresses or names' {
        $result = @(Invoke-PingSweep -Address '10.0.0.1', 'SRV-X' -IncludeOffline)
        $result.IPAddress | Should -Be @('10.0.0.1', 'SRV-X')
    }
}

Describe 'Invoke-PingBatch (real network)' {
    It 'gets an answer from the loopback address' {
        InModuleScope ITToolkit {
            $reply = Invoke-PingBatch -Address '127.0.0.1' -TimeoutMs 2000
            $reply.Online | Should -BeTrue
            $reply.RoundtripMs | Should -BeOfType [int]
        }
    }
}

Describe 'Export-ToolkitReport' {
    It 'writes a page with problems highlighted' {
        $path = Join-Path $TestDrive 'out/report.html'
        $rows = @(
            [pscustomobject]@{ ComputerName = 'SRV-A'; Drive = 'C:'; Status = 'OK' }
            [pscustomobject]@{ ComputerName = 'SRV-A'; Drive = 'D:'; Status = 'Critical' }
            [pscustomobject]@{ ComputerName = 'SRV-B'; Drive = 'C:'; Status = 'Warning' }
        )
        $file = $rows | Export-ToolkitReport -Path $path -Title 'Disk <space>'

        $file.FullName | Should -Exist
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -Match '<title>Disk &lt;space&gt;</title>'
        $html | Should -Match '<td class="bad">Critical</td>'
        $html | Should -Match '<td class="warn">Warning</td>'
        $html | Should -Match '<td class="ok">OK</td>'
    }

    It 'builds one section per command' {
        $path = Join-Path $TestDrive 'daily.html'
        $sections = [ordered]@{
            'Disks'   = @([pscustomobject]@{ Drive = 'C:'; Status = 'OK' })
            'Backups' = @()
        }
        Export-ToolkitReport -Section $sections -Path $path -Title 'Daily' | Out-Null
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -Match '<h2>Disks</h2>'
        $html | Should -Match '<h2>Backups</h2>\s*<p class="none">Nothing to report.</p>'
    }
}
