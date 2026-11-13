<#
.SYNOPSIS
    Builds docs/sample-report.html, the example shown in the README.

.DESCRIPTION
    Backup and network results are real: they come from temporary folders and real pings
    (127.0.0.1 answers; 192.0.2.1 is a reserved documentation address that never does).
    Disk rows are sample data, because disk queries need Windows machines.
#>
[CmdletBinding()]
param(
    [string] $Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/sample-report.html')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ITToolkit/ITToolkit.psd1') -Force

$root = Join-Path ([System.IO.Path]::GetTempPath()) "toolkit-sample-$([guid]::NewGuid().ToString('N'))"
$folders = @{}
foreach ($name in 'sql', 'files', 'erp') {
    $folders[$name] = (New-Item -ItemType Directory -Path (Join-Path $root $name)).FullName
}
$samples = @(
    @{ Folder = 'sql'; File = 'erp_full.bak'; Bytes = 3MB; AgeHours = 5 }
    @{ Folder = 'files'; File = 'fileshare.zip'; Bytes = 2MB; AgeHours = 49 }
    @{ Folder = 'erp'; File = 'export.dmp'; Bytes = 2KB; AgeHours = 3 }
)
foreach ($sample in $samples) {
    $file = Join-Path $folders[$sample.Folder] $sample.File
    [System.IO.File]::WriteAllBytes($file, (New-Object byte[] $sample.Bytes))
    (Get-Item -LiteralPath $file).LastWriteTime = (Get-Date).AddHours(-$sample.AgeHours)
}

$disks = @(
    [pscustomobject]@{ ComputerName = 'SRV-DC01'; Drive = 'C:'; SizeGB = 120; FreeGB = 61.4; FreePercent = 51.2; Status = 'OK'; Message = '' }
    [pscustomobject]@{ ComputerName = 'SRV-FILE01'; Drive = 'C:'; SizeGB = 100; FreeGB = 38.2; FreePercent = 38.2; Status = 'OK'; Message = '' }
    [pscustomobject]@{ ComputerName = 'SRV-FILE01'; Drive = 'D:'; SizeGB = 2000; FreeGB = 290.5; FreePercent = 14.5; Status = 'Warning'; Message = '' }
    [pscustomobject]@{ ComputerName = 'SRV-SQL01'; Drive = 'E:'; SizeGB = 500; FreeGB = 31; FreePercent = 6.2; Status = 'Critical'; Message = '' }
)

$sections = [ordered]@{
    'Disk space (sample data)' = $disks
    'Backups'                  = @(Test-BackupFreshness -Path $folders.sql, $folders.files, $folders.erp -MaxAgeHours 26 -MinSizeMB 1 |
            Select-Object @{ Name = 'Folder'; Expression = { Split-Path -Leaf $_.Path } }, LatestFile, AgeHours, SizeMB, Status)
    'Critical hosts'           = @(Invoke-PingSweep -Address '127.0.0.1', '192.0.2.1' -IncludeOffline -TimeoutMs 1000 |
            Select-Object IPAddress, RoundtripMs, @{ Name = 'Status'; Expression = { if ($_.Online) { 'OK' } else { 'Unreachable' } } })
}

Export-ToolkitReport -Section $sections -Path $Path -Title 'Daily health check (sample)'
Remove-Item -LiteralPath $root -Recurse -Force
