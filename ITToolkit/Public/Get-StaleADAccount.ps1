function Get-StaleADAccount {
    <#
    .SYNOPSIS
        Lists enabled user or computer accounts that have not logged on for a number of days.

    .DESCRIPTION
        Uses LastLogonDate (lastLogonTimestamp), which Active Directory replicates with a delay
        of up to 14 days, so use thresholds of 30 days or more. Accounts that never logged on
        are reported once they are older than the threshold.

    .EXAMPLE
        Get-StaleADAccount -Type Computer -Days 90 | Export-ToolkitReport -Path .\stale.html -Title 'Stale computers'
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('User', 'Computer')]
        [string] $Type = 'User',

        [ValidateRange(1, 3650)]
        [int] $Days = 90,

        [string] $SearchBase
    )

    $command = "Get-AD$Type"
    Assert-CommandAvailable -Name $command

    $cutoff = (Get-Date).AddDays(-$Days)
    $query = @{
        Filter      = "Enabled -eq 'True'"
        Properties  = @('LastLogonDate', 'whenCreated')
        ErrorAction = 'Stop'
    }
    if ($SearchBase) {
        $query.SearchBase = $SearchBase
    }

    $accounts = if ($Type -eq 'User') { Get-ADUser @query } else { Get-ADComputer @query }

    foreach ($account in @($accounts)) {
        $lastLogon = $account.LastLogonDate
        $reference = if ($lastLogon) { $lastLogon } else { $account.whenCreated }
        if ($reference -ge $cutoff) {
            continue
        }
        $inactive = $null
        if ($lastLogon) {
            $inactive = [int]((Get-Date) - $lastLogon).TotalDays
        }
        [pscustomobject]@{
            Type              = $Type
            Name              = $account.Name
            SamAccountName    = $account.SamAccountName
            LastLogonDate     = $lastLogon
            DaysInactive      = $inactive
            Created           = $account.whenCreated
            Status            = if ($lastLogon) { 'Stale' } else { 'NeverLoggedOn' }
            DistinguishedName = $account.DistinguishedName
        }
    }
}
