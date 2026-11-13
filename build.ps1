<#
.SYNOPSIS
    Installs Pester 5 if needed and runs the test suite. Works in Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string] $Output = 'Detailed'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.5.0' } | Select-Object -First 1
if (-not $pester) {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    Install-Module -Name Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck -Scope CurrentUser
}
Import-Module Pester -MinimumVersion 5.5.0

Write-Output "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)), Pester $((Get-Module Pester).Version)"

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $PSScriptRoot 'tests'
$config.Run.Exit = $true
$config.Output.Verbosity = $Output
Invoke-Pester -Configuration $config
