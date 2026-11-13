function Disable-DepartedADUser {
    <#
    .SYNOPSIS
        Offboards a user who left: disables the account, records and removes group
        memberships, stamps the description and moves it to a "disabled" OU.

    .DESCRIPTION
        The account is disabled, not deleted, so mail and files can still be recovered.
        Before groups are removed, the full list is written to an audit CSV, so access can
        be restored exactly if the departure was a mistake.

        The function asks for confirmation for each account unless -Confirm:$false is given,
        and -WhatIf shows what would happen without changing anything.

    .EXAMPLE
        Disable-DepartedADUser -Identity yhaddad -DisabledOU 'OU=Disabled,DC=contoso,DC=local' `
            -AuditPath .\offboarding-audit.csv -Reason 'Contract ended'

    .EXAMPLE
        Import-Csv .\leavers.csv | Disable-DepartedADUser -DisabledOU 'OU=Disabled,DC=contoso,DC=local' `
            -AuditPath .\audit.csv -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('SamAccountName')]
        [string] $Identity,

        [Parameter(Mandatory)]
        [string] $DisabledOU,

        [Parameter(Mandatory)]
        [string] $AuditPath,

        [string] $Reason = 'Left the company'
    )

    begin {
        Assert-CommandAvailable -Name 'Get-ADUser', 'Disable-ADAccount', 'Set-ADUser', 'Remove-ADGroupMember', 'Move-ADObject'
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $operator = [Environment]::UserName
    }

    process {
        $result = [ordered]@{
            Identity      = $Identity
            Name          = $null
            GroupsRemoved = 0
            MovedTo       = $null
            Status        = $null
            Message       = ''
        }

        try {
            $user = Get-ADUser -Identity $Identity -Properties MemberOf, Description -ErrorAction Stop
            $result.Name = $user.Name
            $groups = @($user.MemberOf)

            if (-not $PSCmdlet.ShouldProcess("$($user.Name) ($Identity)", "Disable, remove from $($groups.Count) group(s), move to $DisabledOU")) {
                $result.Status = 'WouldDisable'
                $result.GroupsRemoved = $groups.Count
                $result.MovedTo = $DisabledOU
                return [pscustomobject]$result
            }

            # Audit first: if anything below fails, the record of what the user had is already saved.
            $audit = @($groups | ForEach-Object {
                    [pscustomobject]@{
                        Date           = $today
                        SamAccountName = $Identity
                        Name           = $user.Name
                        Group          = $_
                        Operator       = $operator
                        Reason         = $Reason
                    }
                })
            if ($audit.Count -gt 0) {
                $audit | Export-Csv -LiteralPath $AuditPath -Append -NoTypeInformation -Encoding UTF8
            }

            Disable-ADAccount -Identity $user.DistinguishedName -Confirm:$false -ErrorAction Stop
            Set-ADUser -Identity $user.DistinguishedName -Description "Disabled $today by ${operator}: $Reason" -Confirm:$false -ErrorAction Stop
            foreach ($group in $groups) {
                Remove-ADGroupMember -Identity $group -Members $user.DistinguishedName -Confirm:$false -ErrorAction Stop
            }
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU -Confirm:$false -ErrorAction Stop

            $result.GroupsRemoved = $groups.Count
            $result.MovedTo = $DisabledOU
            $result.Status = 'Disabled'
        }
        catch {
            $result.Status = 'Failed'
            $result.Message = $_.Exception.Message
        }
        [pscustomobject]$result
    }
}
