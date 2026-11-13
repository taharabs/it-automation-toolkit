# Settings for Daily-HealthCheck.ps1. Names below are placeholders (contoso.local).
@{
    Computers           = @('SRV-DC01', 'SRV-FILE01', 'SRV-SQL01')
    DiskWarningPercent  = 20
    DiskCriticalPercent = 10

    BackupFolders       = @('\\NAS01\backup\sql', '\\NAS01\backup\files')
    BackupFilter        = '*'
    BackupMaxAgeHours   = 26
    BackupMinSizeMB     = 10

    CriticalHosts       = @('SRV-DC01', 'SRV-FILE01', '192.168.10.1')

    ReportFolder        = 'C:\Reports\HealthCheck'
}
