function Get-DiskSpaceReport {
    <#
    .SYNOPSIS
        Free space on every fixed disk of one or more Windows machines, with an OK / Warning / Critical status.

    .DESCRIPTION
        Queries Win32_LogicalDisk over CIM (WinRM). A machine that cannot be reached is reported
        with the status Unreachable instead of stopping the whole report.

    .EXAMPLE
        Get-DiskSpaceReport -ComputerName SRV-FILE01, SRV-SQL01 -WarningPercent 20 -CriticalPercent 10

    .EXAMPLE
        Get-DiskSpaceReport | Where-Object Status -ne 'OK'
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'DNSHostName')]
        [string[]] $ComputerName = @($env:COMPUTERNAME),

        [ValidateRange(1, 99)]
        [int] $WarningPercent = 20,

        [ValidateRange(1, 99)]
        [int] $CriticalPercent = 10
    )

    begin {
        if ($CriticalPercent -ge $WarningPercent) {
            throw 'CriticalPercent must be lower than WarningPercent.'
        }
        $localNames = @('localhost', '.', '127.0.0.1', $env:COMPUTERNAME) | Where-Object { $_ }
    }

    process {
        foreach ($computer in $ComputerName) {
            $query = @{
                ClassName   = 'Win32_LogicalDisk'
                Filter      = 'DriveType=3'
                ErrorAction = 'Stop'
            }
            if ($localNames -notcontains $computer) {
                $query.ComputerName = $computer
            }

            try {
                $disks = @(Get-CimInstance @query)
            }
            catch {
                [pscustomobject]@{
                    ComputerName = $computer
                    Drive        = $null
                    SizeGB       = $null
                    FreeGB       = $null
                    FreePercent  = $null
                    Status       = 'Unreachable'
                    Message      = $_.Exception.Message
                }
                continue
            }

            foreach ($disk in $disks) {
                $size = [double]$disk.Size
                $free = [double]$disk.FreeSpace
                $percent = 0
                if ($size -gt 0) {
                    $percent = [math]::Round(100 * $free / $size, 1)
                }
                $status = 'OK'
                if ($percent -lt $CriticalPercent) {
                    $status = 'Critical'
                }
                elseif ($percent -lt $WarningPercent) {
                    $status = 'Warning'
                }
                [pscustomobject]@{
                    ComputerName = $computer
                    Drive        = $disk.DeviceID
                    SizeGB       = [math]::Round($size / 1GB, 1)
                    FreeGB       = [math]::Round($free / 1GB, 1)
                    FreePercent  = $percent
                    Status       = $status
                    Message      = ''
                }
            }
        }
    }
}
