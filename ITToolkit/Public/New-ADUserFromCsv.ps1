function New-ADUserFromCsv {
    <#
    .SYNOPSIS
        Creates Active Directory accounts for new staff from an HR spreadsheet (CSV).

    .DESCRIPTION
        For every row the function builds a logon name from the person's name, makes it
        unique, places the account in the OU of its department, adds the department's
        groups and sets a random initial password that must be changed at first logon.

        Nothing is created when -WhatIf is used: each row is reported as "WouldCreate",
        so the HR file can be checked before any change is made.

        Required CSV columns: FirstName, LastName, Department.
        Optional CSV columns: Title, Office.

    .PARAMETER Path
        CSV file exported by HR.

    .PARAMETER UpnSuffix
        Domain part of the user principal name, for example contoso.local.

    .PARAMETER OUMap
        Department name -> OU distinguished name. Departments not listed go to -DefaultOU.

    .PARAMETER GroupMap
        Department name -> one or more groups to add the new account to.

    .EXAMPLE
        $ous = @{ IT = 'OU=IT,OU=Staff,DC=contoso,DC=local'; Sales = 'OU=Sales,OU=Staff,DC=contoso,DC=local' }
        New-ADUserFromCsv -Path .\new-hires.csv -UpnSuffix contoso.local -OUMap $ous `
            -DefaultOU 'OU=Staff,DC=contoso,DC=local' -WhatIf

        Shows what would be created, without touching Active Directory.

    .OUTPUTS
        One object per CSV row: Status is Created, WouldCreate, Skipped or Failed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9.-]+$')]
        [string] $UpnSuffix,

        [Parameter(Mandatory)]
        [string] $DefaultOU,

        [hashtable] $OUMap = @{},

        [hashtable] $GroupMap = @{},

        [ValidateSet('FirstInitialLastName', 'FirstDotLast')]
        [string] $NameFormat = 'FirstInitialLastName',

        [ValidateRange(12, 128)]
        [int] $PasswordLength = 16
    )

    Assert-CommandAvailable -Name 'Get-ADUser', 'New-ADUser', 'Add-ADGroupMember'

    $rows = @(Import-Csv -LiteralPath $Path)
    $taken = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $line = 1

    foreach ($row in $rows) {
        $line++
        $first = Get-CsvValue -Row $row -Column 'FirstName'
        $last = Get-CsvValue -Row $row -Column 'LastName'
        $department = Get-CsvValue -Row $row -Column 'Department'
        $result = [ordered]@{
            Line              = $line
            Name              = ("$first $last").Trim()
            SamAccountName    = $null
            UserPrincipalName = $null
            Department        = $department
            OU                = $null
            Groups            = ''
            InitialPassword   = $null
            Status            = $null
            Message           = ''
        }

        if (-not $first -or -not $last -or -not $department) {
            $result.Status = 'Skipped'
            $result.Message = 'FirstName, LastName and Department are required.'
            [pscustomobject]$result
            continue
        }

        try {
            $base = ConvertTo-SamAccountName -FirstName $first -LastName $last -Format $NameFormat
            $sam = $base
            $suffix = 1
            while ($taken.Contains($sam) -or $null -ne (Get-ADUser -Filter "SamAccountName -eq '$sam'")) {
                $suffix++
                $sam = $base.Substring(0, [Math]::Min($base.Length, 20 - "$suffix".Length)) + $suffix
            }
            [void]$taken.Add($sam)

            $ou = $DefaultOU
            if ($OUMap.ContainsKey($department)) {
                $ou = $OUMap[$department]
            }
            $groups = @()
            if ($GroupMap.ContainsKey($department)) {
                $groups = @($GroupMap[$department])
            }

            $result.SamAccountName = $sam
            $result.UserPrincipalName = "$sam@$UpnSuffix"
            $result.OU = $ou
            $result.Groups = $groups -join '; '

            if (-not $PSCmdlet.ShouldProcess("$($result.Name) ($sam) in $ou", 'Create AD user')) {
                $result.Status = 'WouldCreate'
                [pscustomobject]$result
                continue
            }

            $password = Get-RandomPassword -Length $PasswordLength
            $newUser = @{
                Name                  = $result.Name
                GivenName             = $first
                Surname               = $last
                DisplayName           = $result.Name
                SamAccountName        = $sam
                UserPrincipalName     = $result.UserPrincipalName
                Path                  = $ou
                Department            = $department
                AccountPassword       = (ConvertTo-SecureText -Text $password)
                ChangePasswordAtLogon = $true
                Enabled               = $true
                ErrorAction           = 'Stop'
            }
            $title = Get-CsvValue -Row $row -Column 'Title'
            if ($title) {
                $newUser.Title = $title
            }
            $office = Get-CsvValue -Row $row -Column 'Office'
            if ($office) {
                $newUser.Office = $office
            }
            New-ADUser @newUser

            foreach ($group in $groups) {
                Add-ADGroupMember -Identity $group -Members $sam -ErrorAction Stop
            }

            $result.InitialPassword = $password
            $result.Status = 'Created'
        }
        catch {
            $result.Status = 'Failed'
            $result.Message = $_.Exception.Message
        }
        [pscustomobject]$result
    }
}
