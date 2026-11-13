<#
.SYNOPSIS
    Example: create the accounts listed in the HR file, after a dry run.

.DESCRIPTION
    Run once with -DryRun, review the output, then run again without it.
    Initial passwords are written to the screen only; hand each one over in person
    and never store the list. Users must change their password at first logon.
#>
[CmdletBinding()]
param(
    [string] $CsvPath = (Join-Path $PSScriptRoot 'new-hires.example.csv'),

    [switch] $DryRun
)

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ITToolkit/ITToolkit.psd1') -Force

$staff = 'OU=Staff,DC=contoso,DC=local'
$ouMap = @{
    IT        = "OU=IT,$staff"
    Sales     = "OU=Sales,$staff"
    Finance   = "OU=Finance,$staff"
    Logistics = "OU=Logistics,$staff"
}
$groupMap = @{
    IT        = @('GG-IT', 'GG-VPN')
    Sales     = @('GG-Sales', 'GG-CRM')
    Finance   = @('GG-Finance')
    Logistics = @('GG-Logistics', 'GG-ERP-Depot')
}

$results = New-ADUserFromCsv -Path $CsvPath -UpnSuffix 'contoso.local' -DefaultOU $staff `
    -OUMap $ouMap -GroupMap $groupMap -WhatIf:$DryRun

$results | Format-Table Line, Name, SamAccountName, OU, Groups, Status, Message -AutoSize
