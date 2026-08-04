# Check-SystemSecurity.ps1
# Collects a "snapshot" of the PC's security state and saves it as JSON.
# Run it manually or on a schedule (Task Scheduler).
# Does not change anything on the system - read-only.

$ErrorActionPreference = "SilentlyContinue"
$OutDir = $PSScriptRoot
$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$LatestPath = Join-Path $OutDir "latest.json"
$HistoryPath = Join-Path $OutDir "history"
if (-not (Test-Path $HistoryPath)) { New-Item -ItemType Directory -Path $HistoryPath | Out-Null }

Write-Host "Collecting data... may take 1-2 minutes (winget is checking for updates)."

# 0. System info
$sysInfo = $null
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bootTime = $os.LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    $sysInfo = [PSCustomObject]@{
        OsName       = $os.Caption
        OsVersion    = $os.Version
        OsBuild      = $os.BuildNumber
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        LastBoot     = $bootTime
        UptimeText   = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    }
} catch {}

# 1. Windows Update - uninstalled updates
$pendingUpdates = @()
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")
    foreach ($u in $searchResult.Updates) {
        $pendingUpdates += [PSCustomObject]@{
            Title      = $u.Title
            Severity   = $u.MsrcSeverity
            KB         = ($u.KBArticleIDs -join ",")
            IsSecurity = ($u.Title -match "Security|Cumulative")
        }
    }
} catch {
    $pendingUpdates = @("ERROR checking Windows Update: $($_.Exception.Message)")
}

# 2. Windows Defender / antivirus
$defender = $null
try {
    $mp = Get-MpComputerStatus
    $defender = [PSCustomObject]@{
        RealTimeProtectionEnabled = $mp.RealTimeProtectionEnabled
        AntivirusEnabled          = $mp.AntivirusEnabled
        AntispywareEnabled        = $mp.AntispywareEnabled
        AntivirusSignatureAge     = $mp.AntivirusSignatureAge
        LastQuickScan             = $mp.QuickScanEndTime
        LastFullScan              = $mp.FullScanEndTime
        NISEnabled                = $mp.NISEnabled
    }
} catch {
    $defender = "Could not read Windows Defender status (another antivirus may be installed, or Defender is disabled)."
}

# 3. Apps with an available update (winget)
$appUpgrades = @()
try {
    $wingetRaw = winget upgrade --include-unknown --accept-source-agreements 2>$null
    $appUpgrades = $wingetRaw
} catch {
    $appUpgrades = @("winget unavailable or errored while running.")
}

# 4. Startup programs
$startupItems = @()
try {
    $startupItems += Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
} catch {}

# 5. Current processes (name + executable path, to detect anything unusual)
$processes = @()
try {
    $processes = Get-Process | Where-Object { $_.Path } | Select-Object Name, Id, Path, Company |
        Sort-Object Name -Unique
} catch {}

# 6. Running services that are NOT Microsoft's (a risk signal, not proof)
$suspiciousServices = @()
try {
    $suspiciousServices = Get-CimInstance Win32_Service | Where-Object {
        $_.State -eq "Running" -and $_.PathName -and $_.PathName -notmatch "Windows|Microsoft"
    } | Select-Object Name, DisplayName, PathName, StartMode
} catch {}

# 7. Windows Firewall status (per profile)
$firewallProfiles = @()
try {
    $firewallProfiles = Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
} catch {}

# 8. BitLocker disk encryption (best effort - usually needs admin/Pro-Enterprise)
$bitlockerVolumes = @()
try {
    $bitlockerVolumes = Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage
} catch {}

# 9. Local user accounts (flag enabled built-in accounts, passwordless accounts)
$localAccounts = @()
try {
    $localAccounts = Get-LocalUser | Select-Object Name, Enabled, PasswordRequired, PasswordLastSet, LastLogon
} catch {}

# 10. Processes with no publisher/company info (not proof of anything, but worth a look)
$unsignedProcesses = @()
try {
    $unsignedProcesses = $processes | Where-Object {
        [string]::IsNullOrWhiteSpace($_.Company) -and $_.Path -notmatch "^C:\\WINDOWS\\"
    }
} catch {}

$report = [PSCustomObject]@{
    Timestamp           = (Get-Date).ToString("o")
    ComputerName        = $env:COMPUTERNAME
    SystemInfo          = $sysInfo
    PendingUpdatesCount = $pendingUpdates.Count
    PendingUpdates      = $pendingUpdates
    Defender            = $defender
    FirewallProfiles    = $firewallProfiles
    BitLockerVolumes    = $bitlockerVolumes
    LocalAccounts       = $localAccounts
    AppUpgrades         = $appUpgrades
    StartupItems        = $startupItems
    SuspiciousServices  = $suspiciousServices
    ProcessCount        = $processes.Count
    Processes           = $processes
    UnsignedProcesses   = $unsignedProcesses
}

$json = $report | ConvertTo-Json -Depth 6
$json | Out-File -FilePath $LatestPath -Encoding utf8
$json | Out-File -FilePath (Join-Path $HistoryPath "report_$Timestamp.json") -Encoding utf8

Write-Host "Done. Report saved to: $LatestPath"
