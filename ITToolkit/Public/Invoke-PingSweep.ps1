function Invoke-PingSweep {
    <#
    .SYNOPSIS
        Finds the hosts that answer on a subnet, fast: addresses are pinged in parallel batches.

    .EXAMPLE
        Invoke-PingSweep -Cidr 192.168.10.0/24 -ResolveNames

    .EXAMPLE
        Invoke-PingSweep -Address SRV-FILE01, SRV-SQL01, 192.168.10.1 -IncludeOffline
    #>
    [CmdletBinding(DefaultParameterSetName = 'Cidr')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Cidr', Position = 0)]
        [string[]] $Cidr,

        [Parameter(Mandatory, ParameterSetName = 'Address')]
        [string[]] $Address,

        [ValidateRange(50, 10000)]
        [int] $TimeoutMs = 500,

        [ValidateRange(1, 1024)]
        [int] $BatchSize = 128,

        [switch] $ResolveNames,

        [switch] $IncludeOffline
    )

    if ($PSCmdlet.ParameterSetName -eq 'Cidr') {
        $targets = @($Cidr | ForEach-Object { Get-IPv4Range -Cidr $_ })
    }
    else {
        $targets = @($Address)
    }

    for ($start = 0; $start -lt $targets.Count; $start += $BatchSize) {
        $end = [Math]::Min($start + $BatchSize, $targets.Count) - 1
        $batch = @($targets[$start..$end])
        Write-Progress -Activity 'Ping sweep' -Status "$($end + 1) of $($targets.Count)" -PercentComplete (100 * ($end + 1) / $targets.Count)

        foreach ($reply in @(Invoke-PingBatch -Address $batch -TimeoutMs $TimeoutMs)) {
            if (-not $reply.Online -and -not $IncludeOffline) {
                continue
            }
            $hostName = $null
            if ($ResolveNames -and $reply.Online) {
                $hostName = Resolve-HostName -IPAddress $reply.IPAddress
            }
            [pscustomobject]@{
                IPAddress   = $reply.IPAddress
                Online      = $reply.Online
                RoundtripMs = $reply.RoundtripMs
                HostName    = $hostName
            }
        }
    }
    Write-Progress -Activity 'Ping sweep' -Completed
}
