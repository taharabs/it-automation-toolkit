function Assert-CommandAvailable {
    <#
    .SYNOPSIS
        Fails early with a clear message when a required command (for example from RSAT) is missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Name,

        [string] $Hint = 'Install the RSAT Active Directory tools (ActiveDirectory module).'
    )

    $missing = @($Name | Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) })
    if ($missing.Count -gt 0) {
        throw "Required command(s) not found: $($missing -join ', '). $Hint"
    }
}

function Get-CsvValue {
    <#
    .SYNOPSIS
        Reads a column from a CSV row, returning an empty string when the column is absent.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Row,

        [Parameter(Mandatory)]
        [string] $Column
    )

    $property = $Row.PSObject.Properties[$Column]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }
    return ([string]$property.Value).Trim()
}

function ConvertTo-PlainAscii {
    <#
    .SYNOPSIS
        Removes accents and keeps lower-case letters only: "Ait-Ouali O'Neil" -> "aitoualioneil".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $decomposed = $Text.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $decomposed.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }
    return ($builder.ToString().ToLowerInvariant() -replace '[^a-z]', '')
}

function ConvertTo-SamAccountName {
    <#
    .SYNOPSIS
        Builds a logon name from a first and last name, following a naming convention.
    .DESCRIPTION
        FirstInitialLastName: Yacine Haddad -> yhaddad
        FirstDotLast        : Yacine Haddad -> yacine.haddad
        The result is at most 20 characters, the limit for sAMAccountName.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $FirstName,

        [Parameter(Mandatory)]
        [string] $LastName,

        [ValidateSet('FirstInitialLastName', 'FirstDotLast')]
        [string] $Format = 'FirstInitialLastName'
    )

    $first = ConvertTo-PlainAscii -Text $FirstName
    $last = ConvertTo-PlainAscii -Text $LastName
    if (-not $first -or -not $last) {
        throw "Cannot build a logon name from '$FirstName' '$LastName'."
    }

    if ($Format -eq 'FirstDotLast') {
        $name = "$first.$last"
    }
    else {
        $name = $first.Substring(0, 1) + $last
    }

    if ($name.Length -gt 20) {
        $name = $name.Substring(0, 20).TrimEnd('.')
    }
    return $name
}

function Get-RandomPassword {
    <#
    .SYNOPSIS
        Generates a random password with upper, lower, digit and symbol characters,
        using a cryptographic random number generator. Ambiguous characters (0/O, 1/l/I) are excluded.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateRange(12, 128)]
        [int] $Length = 16
    )

    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnpqrstuvwxyz',
        '23456789',
        '!@#$%*-_=+?'
    )
    $all = -join $sets
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $pick = {
            param([string] $From)
            $bytes = New-Object byte[] 4
            $rng.GetBytes($bytes)
            $From[[int]([BitConverter]::ToUInt32($bytes, 0) % [uint32]$From.Length)]
        }

        $chars = New-Object System.Collections.Generic.List[char]
        foreach ($set in $sets) {
            $chars.Add((& $pick $set))
        }
        while ($chars.Count -lt $Length) {
            $chars.Add((& $pick $all))
        }

        # Fisher-Yates shuffle so the guaranteed characters are not always first.
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $bytes = New-Object byte[] 4
            $rng.GetBytes($bytes)
            $j = [int]([BitConverter]::ToUInt32($bytes, 0) % [uint32]($i + 1))
            $tmp = $chars[$i]
            $chars[$i] = $chars[$j]
            $chars[$j] = $tmp
        }
        return (-join $chars)
    }
    finally {
        $rng.Dispose()
    }
}

function ConvertTo-SecureText {
    <#
    .SYNOPSIS
        Builds a SecureString one character at a time.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    $secure = New-Object System.Security.SecureString
    foreach ($char in $Text.ToCharArray()) {
        $secure.AppendChar($char)
    }
    $secure.MakeReadOnly()
    return $secure
}
