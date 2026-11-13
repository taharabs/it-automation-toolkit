function ConvertTo-UInt64Address {
    [CmdletBinding()]
    [OutputType([uint64])]
    param([Parameter(Mandatory)] [System.Net.IPAddress] $Address)

    $bytes = $Address.GetAddressBytes()
    [Array]::Reverse($bytes)
    return [uint64][BitConverter]::ToUInt32($bytes, 0)
}

function ConvertFrom-UInt64Address {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [uint64] $Value)

    $bytes = [BitConverter]::GetBytes([uint32]$Value)
    [Array]::Reverse($bytes)
    return (New-Object System.Net.IPAddress (, $bytes)).ToString()
}

function Get-IPv4Range {
    <#
    .SYNOPSIS
        Expands a CIDR block into its usable host addresses.
    .DESCRIPTION
        192.168.1.0/24 -> 192.168.1.1 .. 192.168.1.254 (network and broadcast excluded).
        /31 and /32 return every address. Blocks larger than /16 are refused.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Cidr
    )

    if ($Cidr -notmatch '^\s*(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})\s*$') {
        throw "'$Cidr' is not a CIDR block such as 192.168.1.0/24."
    }
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Matches[1], [ref]$address) -or
        $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "'$($Matches[1])' is not a valid IPv4 address."
    }
    $prefix = [int]$Matches[2]
    if ($prefix -lt 16 -or $prefix -gt 32) {
        throw "Prefix /$prefix is out of range: use /16 to /32 (at most 65,534 hosts)."
    }

    $size = [uint64][math]::Pow(2, 32 - $prefix)
    $network = (ConvertTo-UInt64Address -Address $address) - ((ConvertTo-UInt64Address -Address $address) % $size)

    if ($prefix -ge 31) {
        $first = $network
        $last = $network + $size - 1
    }
    else {
        $first = $network + 1
        $last = $network + $size - 2
    }

    $result = New-Object System.Collections.Generic.List[string]
    for ($value = $first; $value -le $last; $value++) {
        $result.Add((ConvertFrom-UInt64Address -Value $value))
    }
    return $result.ToArray()
}

function Invoke-PingBatch {
    <#
    .SYNOPSIS
        Pings a batch of addresses at the same time and waits for all answers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Address,

        [int] $TimeoutMs = 500
    )

    $pings = New-Object System.Collections.Generic.List[System.Net.NetworkInformation.Ping]
    $tasks = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task]
    try {
        foreach ($ip in $Address) {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $pings.Add($ping)
            $tasks.Add($ping.SendPingAsync($ip, $TimeoutMs))
        }
        try {
            [System.Threading.Tasks.Task]::WaitAll($tasks.ToArray())
        }
        catch {
            Write-Verbose "Some pings failed: $($_.Exception.Message)"
        }

        for ($i = 0; $i -lt $Address.Count; $i++) {
            $task = $tasks[$i]
            $online = (-not $task.IsFaulted) -and ($task.Result.Status -eq 'Success')
            $roundtrip = $null
            if ($online) {
                $roundtrip = [int]$task.Result.RoundtripTime
            }
            [pscustomobject]@{
                IPAddress   = $Address[$i]
                Online      = $online
                RoundtripMs = $roundtrip
            }
        }
    }
    finally {
        foreach ($ping in $pings) {
            $ping.Dispose()
        }
    }
}

function Resolve-HostName {
    <#
    .SYNOPSIS
        Reverse DNS lookup that returns $null instead of failing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $IPAddress)

    try {
        return [System.Net.Dns]::GetHostEntry($IPAddress).HostName
    }
    catch {
        return $null
    }
}
