<#
.SYNOPSIS
    Daily infrastructure check: disk space, backups and network, in one HTML report.

.DESCRIPTION
    Meant to run from Task Scheduler every morning. The exit code tells the scheduler
    or a monitoring tool (PRTG, Zabbix) whether to raise an alert:
        0  everything is OK
        1  at least one warning
        2  at least one critical problem

.EXAMPLE
    .\Daily-HealthCheck.ps1 -ConfigPath .\healthcheck.psd1

.EXAMPLE
    # Register as a scheduled task that runs at 07:00 every day
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Daily-HealthCheck.ps1 -ConfigPath C:\Scripts\healthcheck.psd1'
    Register-ScheduledTask -TaskName 'Daily health check' -Action $action `
        -Trigger (New-ScheduledTaskTrigger -Daily -At 07:00) -User 'CONTOSO\svc-healthcheck'
#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ConfigPath = (Join-Path $PSScriptRoot 'healthcheck.example.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ITToolkit/ITToolkit.psd1') -Force

$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$sections = [ordered]@{}

if ($config.Computers) {
    $sections['Disk space'] = @(Get-DiskSpaceReport -ComputerName $config.Computers `
            -WarningPercent $config.DiskWarningPercent -CriticalPercent $config.DiskCriticalPercent)
}
if ($config.BackupFolders) {
    $sections['Backups'] = @(Test-BackupFreshness -Path $config.BackupFolders `
            -MaxAgeHours $config.BackupMaxAgeHours -MinSizeMB $config.BackupMinSizeMB -Filter $config.BackupFilter)
}
if ($config.CriticalHosts) {
    $sections['Critical hosts'] = @(Invoke-PingSweep -Address $config.CriticalHosts -IncludeOffline |
            Select-Object IPAddress, RoundtripMs, @{ Name = 'Status'; Expression = { if ($_.Online) { 'OK' } else { 'Unreachable' } } })
}

$stamp = (Get-Date).ToString('yyyy-MM-dd')
$reportPath = Join-Path $config.ReportFolder "health-$stamp.html"
$report = Export-ToolkitReport -Section $sections -Path $reportPath -Title "Daily health check - $stamp"

$all = @($sections.Values | ForEach-Object { $_ })
$critical = @($all | Where-Object { $_.Status -in 'Critical', 'Unreachable', 'Missing', 'Stale', 'Empty', 'TooSmall' })
$warnings = @($all | Where-Object { $_.Status -eq 'Warning' })

Write-Output "Report: $($report.FullName)"
Write-Output "$($critical.Count) critical, $($warnings.Count) warning(s)"

if ($critical.Count -gt 0) { exit 2 }
if ($warnings.Count -gt 0) { exit 1 }
exit 0
