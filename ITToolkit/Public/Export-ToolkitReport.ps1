function Export-ToolkitReport {
    <#
    .SYNOPSIS
        Writes the output of any toolkit command to a self-contained HTML page, with problems highlighted.

    .DESCRIPTION
        Rows whose Status is Critical, Failed, Missing, Stale, Unreachable, Empty or TooSmall are shown
        in red; Warning and similar states in amber. The page has no external dependencies, so it
        can be attached to an e-mail or opened from a file share.

    .EXAMPLE
        Get-DiskSpaceReport -ComputerName SRV-FILE01 | Export-ToolkitReport -Path .\disks.html -Title 'Disk space'

    .EXAMPLE
        $sections = [ordered]@{ 'Disks' = Get-DiskSpaceReport; 'Backups' = Test-BackupFreshness -Path D:\Backup }
        Export-ToolkitReport -Section $sections -Path .\daily.html -Title 'Daily health check'
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [AllowNull()]
        [psobject] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Section')]
        [System.Collections.IDictionary] $Section,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'IT report'
    )

    begin {
        $collected = New-Object System.Collections.Generic.List[psobject]

        function ConvertTo-Fragment {
            param([object[]] $Rows)
            $bad = 'Critical|Failed|Missing|Stale|Unreachable|Empty|TooSmall'
            $warn = 'Warning|WouldCreate|WouldDisable|NeverLoggedOn|Skipped'
            if (@($Rows).Count -eq 0) {
                return '<p class="none">Nothing to report.</p>'
            }
            $html = ($Rows | ConvertTo-Html -Fragment) -join "`n"
            $html = [regex]::Replace($html, "<td>($bad)</td>", '<td class="bad">$1</td>')
            $html = [regex]::Replace($html, "<td>($warn)</td>", '<td class="warn">$1</td>')
            $html = [regex]::Replace($html, '<td>(OK|Created|Disabled|True)</td>', '<td class="ok">$1</td>')
            return $html
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline' -and $null -ne $InputObject) {
            $collected.Add($InputObject)
        }
    }

    end {
        $encode = { param($Text) [System.Net.WebUtility]::HtmlEncode([string]$Text) }
        $body = New-Object System.Text.StringBuilder
        if ($PSCmdlet.ParameterSetName -eq 'Section') {
            foreach ($name in $Section.Keys) {
                $rows = @($Section[$name])
                [void]$body.AppendLine("<h2>$(& $encode $name)</h2>")
                [void]$body.AppendLine((ConvertTo-Fragment -Rows $rows))
            }
        }
        else {
            [void]$body.AppendLine((ConvertTo-Fragment -Rows $collected.ToArray()))
        }

        $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        $page = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$(& $encode $Title)</title>
<style>
  body { font: 14px/1.45 "Segoe UI", system-ui, sans-serif; color: #1f2328; margin: 24px; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  h2 { font-size: 15px; margin: 24px 0 8px; }
  .meta { color: #656d76; margin-bottom: 16px; }
  table { border-collapse: collapse; width: 100%; }
  th { text-align: left; background: #f6f8fa; font-weight: 600; }
  th, td { border: 1px solid #d0d7de; padding: 6px 10px; vertical-align: top; }
  td.bad { background: #ffebe9; color: #a40e26; font-weight: 600; }
  td.warn { background: #fff8c5; color: #7d4e00; font-weight: 600; }
  td.ok { color: #1a7f37; }
  .none { color: #656d76; }
</style>
</head>
<body>
<h1>$(& $encode $Title)</h1>
<div class="meta">Generated $generated on $(& $encode $env:COMPUTERNAME)</div>
$($body.ToString())
</body>
</html>
"@
        # Resolve against the PowerShell location, not the process working directory.
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $directory = [System.IO.Path]::GetDirectoryName($fullPath)
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($fullPath, $page, (New-Object System.Text.UTF8Encoding $false))
        Get-Item -LiteralPath $fullPath
    }
}
