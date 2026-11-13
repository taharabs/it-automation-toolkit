function Test-BackupFreshness {
    <#
    .SYNOPSIS
        Checks that each backup folder received a recent, non-empty backup file.

    .DESCRIPTION
        For every folder, finds the newest file and reports:
          OK       newest file is recent enough and big enough
          Stale    newest file is older than -MaxAgeHours
          TooSmall newest file is smaller than -MinSizeMB (a backup that silently failed)
          Empty    no file matches -Filter
          Missing  the folder does not exist or cannot be read

    .EXAMPLE
        Test-BackupFreshness -Path '\\NAS01\backup\sql', '\\NAS01\backup\files' -Filter '*.bak' -MaxAgeHours 26 -MinSizeMB 50
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path,

        [ValidateRange(1, 8760)]
        [int] $MaxAgeHours = 26,

        [string] $Filter = '*',

        [ValidateRange(0, 10485760)]
        [double] $MinSizeMB = 0,

        [switch] $Recurse
    )

    process {
        foreach ($folder in $Path) {
            $result = [ordered]@{
                Path          = $folder
                LatestFile    = $null
                LastWriteTime = $null
                AgeHours      = $null
                SizeMB        = $null
                Status        = $null
            }

            if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                $result.Status = 'Missing'
                [pscustomobject]$result
                continue
            }

            $newest = Get-ChildItem -LiteralPath $folder -Filter $Filter -File -Recurse:$Recurse -ErrorAction SilentlyContinue |
                Sort-Object -Property LastWriteTime -Descending |
                Select-Object -First 1

            if ($null -eq $newest) {
                $result.Status = 'Empty'
                [pscustomobject]$result
                continue
            }

            $age = ((Get-Date) - $newest.LastWriteTime).TotalHours
            $sizeMB = $newest.Length / 1MB
            $result.LatestFile = $newest.Name
            $result.LastWriteTime = $newest.LastWriteTime
            $result.AgeHours = [math]::Round($age, 1)
            $result.SizeMB = [math]::Round($sizeMB, 2)

            if ($age -gt $MaxAgeHours) {
                $result.Status = 'Stale'
            }
            elseif ($sizeMB -lt $MinSizeMB) {
                $result.Status = 'TooSmall'
            }
            else {
                $result.Status = 'OK'
            }
            [pscustomobject]$result
        }
    }
}
