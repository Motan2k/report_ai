# Check-SystemSecurity-Standalone.ps1
#
# Fully self-contained version: collects system security data AND builds a detailed
# HTML report itself, using rule-based checks instead of AI analysis. No Cowork,
# no scheduled task, no cloud agent needed.
#
# Use this on any other Windows PC that doesn't have the Cowork agent installed:
#   1. Copy this single file anywhere on that PC.
#   2. Run it in PowerShell (no admin required, but run as Administrator for the
#      most complete results - BitLocker and some Defender fields need it):
#        .\Check-SystemSecurity-Standalone.ps1
#   3. Open the generated security-report.html (same folder) in a browser.
#
# Read-only - does not change anything on the system.

$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Web
$OutDir = $PSScriptRoot
$HtmlPath = Join-Path $OutDir "security-report.html"
$Now = Get-Date

function Html([string]$s) {
    if ($null -eq $s) { return "" }
    return [System.Web.HttpUtility]::HtmlEncode($s)
}

Write-Host "Collecting data... may take 1-2 minutes (winget is checking for updates)."

# ---------------------------------------------------------------------------
# 1. System info
# ---------------------------------------------------------------------------
$sysInfo = $null
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bootTime = $os.LastBootUpTime
    $uptime = $Now - $bootTime
    $sysInfo = [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        OsName       = $os.Caption
        OsVersion    = $os.Version
        OsBuild      = $os.BuildNumber
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        LastBoot     = $bootTime
        UptimeText   = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    }
} catch {}

# ---------------------------------------------------------------------------
# 2. Windows Update - uninstalled updates (full detail)
# ---------------------------------------------------------------------------
$pendingUpdates = @()
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")
    foreach ($u in $searchResult.Updates) {
        $pendingUpdates += [PSCustomObject]@{
            Title      = $u.Title
            Severity   = $(if ($u.MsrcSeverity) { $u.MsrcSeverity } else { "Unspecified" })
            KB         = ($u.KBArticleIDs -join ", ")
            SizeMB     = [math]::Round($u.MaxDownloadSize / 1MB, 1)
        }
    }
} catch {
    $pendingUpdates = @()
}
$criticalUpdates = $pendingUpdates | Where-Object { $_.Severity -in @("Critical","Important") }

# ---------------------------------------------------------------------------
# 3. Windows Defender / antivirus (full detail)
# ---------------------------------------------------------------------------
$defenderOk = $true
$defenderNotes = @()
$defender = $null
try {
    $mp = Get-MpComputerStatus
    $defender = [PSCustomObject]@{
        RealTimeProtectionEnabled = $mp.RealTimeProtectionEnabled
        AntivirusEnabled          = $mp.AntivirusEnabled
        AntispywareEnabled       = $mp.AntispywareEnabled
        BehaviorMonitorEnabled    = $mp.BehaviorMonitorEnabled
        IoavProtectionEnabled     = $mp.IoavProtectionEnabled
        NISEnabled                = $mp.NISEnabled
        OnAccessProtectionEnabled = $mp.OnAccessProtectionEnabled
        IsTamperProtected         = $mp.IsTamperProtected
        AntivirusSignatureAge     = $mp.AntivirusSignatureAge
        AntivirusSignatureVersion = $mp.AntivirusSignatureVersion
        LastQuickScan             = $mp.QuickScanEndTime
        LastFullScan              = $mp.FullScanEndTime
        ComputerState             = $mp.ComputerState
    }
    if (-not $mp.RealTimeProtectionEnabled) { $defenderOk = $false; $defenderNotes += "Real-time protection is OFF." }
    if (-not $mp.AntivirusEnabled) { $defenderOk = $false; $defenderNotes += "Antivirus engine is OFF." }
    if (-not $mp.AntispywareEnabled) { $defenderOk = $false; $defenderNotes += "Antispyware engine is OFF." }
    if ($mp.IsTamperProtected -eq $false) { $defenderNotes += "Tamper Protection is OFF - Defender settings could be changed by malware or another user without a prompt." }
    if ($mp.AntivirusSignatureAge -gt 7) { $defenderNotes += "Signatures are $($mp.AntivirusSignatureAge) days old." }
    if (-not $mp.FullScanEndTime) { $defenderNotes += "A full scan has never been run (reminder, not critical)." }
    if ($defenderNotes.Count -eq 0) { $defenderNotes += "No issues found." }
} catch {
    $defenderOk = $false
    $defenderNotes += "Could not read Windows Defender status (another antivirus may be installed, or Defender is disabled, or this requires elevation)."
}

# ---------------------------------------------------------------------------
# 4. Firewall status
# ---------------------------------------------------------------------------
$firewallProfiles = @()
$firewallOk = $true
try {
    $firewallProfiles = Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
    foreach ($fp in $firewallProfiles) {
        if (-not $fp.Enabled) { $firewallOk = $false }
    }
} catch {}

# ---------------------------------------------------------------------------
# 5. BitLocker (best effort - usually needs admin)
# ---------------------------------------------------------------------------
$bitlockerVolumes = @()
try {
    $bitlockerVolumes = Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage
} catch {}

# ---------------------------------------------------------------------------
# 6. Local user accounts (flag enabled built-in accounts)
# ---------------------------------------------------------------------------
$localAccounts = @()
$accountNotes = @()
try {
    $localAccounts = Get-LocalUser | Select-Object Name, Enabled, PasswordRequired, PasswordLastSet, LastLogon
    $guest = $localAccounts | Where-Object { $_.Name -eq "Guest" -and $_.Enabled }
    $builtinAdmin = $localAccounts | Where-Object { $_.Name -eq "Administrator" -and $_.Enabled }
    if ($guest) { $accountNotes += "The built-in Guest account is ENABLED - this is a common hardening gap, consider disabling it." }
    if ($builtinAdmin) { $accountNotes += "The built-in Administrator account is ENABLED - fine if intentional, but confirm it has a strong password if so." }
    $noPassword = $localAccounts | Where-Object { $_.Enabled -and -not $_.PasswordRequired }
    foreach ($u in $noPassword) { $accountNotes += "Account '$($u.Name)' is enabled and does not require a password." }
} catch {}

# ---------------------------------------------------------------------------
# 7. Apps with an available update (winget) - parsed into a table where possible
# ---------------------------------------------------------------------------
$appUpgradeRaw = @()
$appUpgradeParsed = @()
try {
    $appUpgradeRaw = winget upgrade --include-unknown --accept-source-agreements 2>$null
    $dividerIndex = ($appUpgradeRaw | Select-String -Pattern "^-{5,}").LineNumber
    if ($dividerIndex) {
        for ($i = $dividerIndex; $i -lt $appUpgradeRaw.Count; $i++) {
            $line = $appUpgradeRaw[$i]
            if ($line -match "^\d+ upgrades? available" -or [string]::IsNullOrWhiteSpace($line)) { continue }
            $cols = $line -split '\s{2,}' | Where-Object { $_ -ne "" }
            if ($cols.Count -ge 4) {
                $appUpgradeParsed += [PSCustomObject]@{
                    Name      = $cols[0]
                    Id        = $cols[1]
                    Version   = $cols[2]
                    Available = $cols[3]
                }
            }
        }
    }
} catch {
    $appUpgradeRaw = @()
}

# ---------------------------------------------------------------------------
# 8. Startup programs (full detail)
# ---------------------------------------------------------------------------
$startupItems = @()
try {
    $startupItems = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
} catch {}

# ---------------------------------------------------------------------------
# 9. Running services that are NOT Microsoft's (a risk signal, not proof)
# ---------------------------------------------------------------------------
$suspiciousServices = @()
try {
    $suspiciousServices = Get-CimInstance Win32_Service | Where-Object {
        $_.State -eq "Running" -and $_.PathName -and $_.PathName -notmatch "Windows|Microsoft"
    } | Select-Object Name, DisplayName, PathName, StartMode, StartName
} catch {}

# ---------------------------------------------------------------------------
# 10. Processes with no publisher info (Company is blank/null) - worth a look
# ---------------------------------------------------------------------------
$allProcesses = @()
$unsignedProcesses = @()
try {
    $allProcesses = Get-Process | Where-Object { $_.Path } | Select-Object Name, Id, Path, Company | Sort-Object Name -Unique
    $unsignedProcesses = $allProcesses | Where-Object { [string]::IsNullOrWhiteSpace($_.Company) -and $_.Path -notmatch "^C:\\WINDOWS\\" }
} catch {}
$processCount = $allProcesses.Count

# ---------------------------------------------------------------------------
# Build overall status
# ---------------------------------------------------------------------------
$statusLevel = "ok"     # ok | warn | risk
$statusText  = "OK - nothing that needs immediate action"

if (-not $defenderOk) {
    $statusLevel = "risk"
    $statusText = "Risk detected - Windows Defender protection is off"
} elseif (-not $firewallOk) {
    $statusLevel = "risk"
    $statusText = "Risk detected - a Windows Firewall profile is disabled"
} elseif ($criticalUpdates.Count -gt 0) {
    $statusLevel = "warn"
    $statusText = "Needs attention - $($criticalUpdates.Count) Critical/Important update(s) pending"
} elseif ($accountNotes.Count -gt 0 -or $suspiciousServices.Count -gt 0 -or ($defenderNotes -notcontains "No issues found.") -or $unsignedProcesses.Count -gt 0) {
    $statusLevel = "warn"
    $statusText = "Needs attention - see notes below"
}

$colors = @{
    ok   = @{ fg = "#1a7f37"; bg = "#dafbe1" }
    warn = @{ fg = "#9a6700"; bg = "#fff8c5" }
    risk = @{ fg = "#cf222e"; bg = "#ffebe9" }
}
$c = $colors[$statusLevel]

function Badge([string]$level, [string]$text) {
    $bc = $colors[$level]
    return "<span style='display:inline-block;font-size:11px;font-weight:600;padding:2px 9px;border-radius:999px;text-transform:uppercase;letter-spacing:.3px;background:$($bc.bg);color:$($bc.fg);'>$text</span>"
}

# ---------------------------------------------------------------------------
# Recommendations (rule-based, not AI)
# ---------------------------------------------------------------------------
$recommendations = @()
if (-not $defenderOk) {
    $recommendations += "Re-enable Windows Defender real-time/antivirus/antispyware protection immediately, or confirm another antivirus is active in its place."
}
if (-not $firewallOk) {
    $recommendations += "Re-enable the Windows Firewall profile(s) currently disabled - see the Firewall card below for which one(s)."
}
if ($defender -and $defender.IsTamperProtected -eq $false) {
    $recommendations += "Turn Tamper Protection back on in Windows Security > Virus & threat protection settings."
}
if ($criticalUpdates.Count -gt 0) {
    $recommendations += "Install the $($criticalUpdates.Count) pending Critical/Important Windows update(s) listed below as soon as possible."
}
if ($defender -and -not $defender.LastFullScan) {
    $recommendations += "Run a full Windows Defender scan - none has ever been recorded."
}
foreach ($n in $accountNotes) { $recommendations += $n }
if ($suspiciousServices.Count -gt 0) {
    $recommendations += "Review the $($suspiciousServices.Count) non-Microsoft running service(s) listed below - confirm you recognize each one (most OEM/utility services are legitimate, but check anything unfamiliar)."
}
if ($unsignedProcesses.Count -gt 0) {
    $recommendations += "Review the $($unsignedProcesses.Count) running process(es) with no publisher/company information listed below - not necessarily malicious, but worth confirming what they are."
}
if ($appUpgradeParsed.Count -gt 2 -or $appUpgradeRaw.Count -gt 2) {
    $recommendations += "Update outdated applications, prioritizing anything internet-facing or remote-access (browsers, AnyDesk/TeamViewer, PDF readers)."
}
if ($bitlockerVolumes.Count -gt 0) {
    $unprotected = $bitlockerVolumes | Where-Object { $_.ProtectionStatus -eq "Off" }
    if ($unprotected) {
        $recommendations += "Consider turning on BitLocker encryption for drive(s): $(($unprotected | ForEach-Object { $_.MountPoint }) -join ', ') - especially important on a laptop."
    }
}
if ($recommendations.Count -eq 0) {
    $recommendations += "Nothing to do right now."
}

# ---------------------------------------------------------------------------
# Render HTML
# ---------------------------------------------------------------------------
$updateRows = ""
foreach ($u in $pendingUpdates) {
    $sevBadge = if ($u.Severity -in @("Critical","Important")) { Badge "warn" $u.Severity } else { Badge "ok" $u.Severity }
    $updateRows += "<tr><td>$(Html $u.Title)</td><td>$sevBadge</td><td>$(Html $u.KB)</td><td>$($u.SizeMB) MB</td></tr>`n"
}
if (-not $updateRows) { $updateRows = "<tr><td colspan='4'>No pending updates found.</td></tr>" }

$firewallRows = ""
foreach ($fp in $firewallProfiles) {
    $state = if ($fp.Enabled) { Badge "ok" "Enabled" } else { Badge "risk" "Disabled" }
    $firewallRows += "<tr><td>$($fp.Name)</td><td>$state</td><td>$($fp.DefaultInboundAction)</td><td>$($fp.DefaultOutboundAction)</td></tr>`n"
}
if (-not $firewallRows) { $firewallRows = "<tr><td colspan='4'>Could not read firewall profiles.</td></tr>" }

$accountRows = ""
foreach ($a in $localAccounts) {
    $state = if ($a.Enabled) { Badge "warn" "Enabled" } else { Badge "ok" "Disabled" }
    $accountRows += "<tr><td>$(Html $a.Name)</td><td>$state</td><td>$($a.PasswordRequired)</td><td>$($a.LastLogon)</td></tr>`n"
}
if (-not $accountRows) { $accountRows = "<tr><td colspan='4'>Could not read local accounts (may need elevation).</td></tr>" }

$appRows = ""
if ($appUpgradeParsed.Count -gt 0) {
    foreach ($a in $appUpgradeParsed) {
        $appRows += "<tr><td>$(Html $a.Name)</td><td>$(Html $a.Version)</td><td>$(Html $a.Available)</td></tr>`n"
    }
} else {
    foreach ($line in $appUpgradeRaw) {
        $appRows += "<div>$(Html $line)</div>`n"
    }
}

$startupRows = ""
foreach ($item in $startupItems) {
    $startupRows += "<tr><td>$(Html $item.Name)</td><td>$(Html $item.Command)</td><td>$(Html $item.User)</td></tr>`n"
}
if (-not $startupRows) { $startupRows = "<tr><td colspan='3'>No startup items found.</td></tr>" }

$serviceRows = ""
foreach ($svc in $suspiciousServices) {
    $serviceRows += "<tr><td>$(Html $svc.Name)</td><td>$(Html $svc.DisplayName)</td><td>$(Html $svc.PathName)</td><td>$($svc.StartMode)</td></tr>`n"
}
if (-not $serviceRows) { $serviceRows = "<tr><td colspan='4'>No non-Microsoft running services found.</td></tr>" }

$unsignedRows = ""
foreach ($p in $unsignedProcesses) {
    $unsignedRows += "<tr><td>$(Html $p.Name)</td><td>$($p.Id)</td><td>$(Html $p.Path)</td></tr>`n"
}
if (-not $unsignedRows) { $unsignedRows = "<tr><td colspan='3'>All running processes have publisher information.</td></tr>" }

$bitlockerRows = ""
foreach ($v in $bitlockerVolumes) {
    $state = if ($v.ProtectionStatus -eq "On") { Badge "ok" "On" } else { Badge "warn" "Off" }
    $bitlockerRows += "<tr><td>$($v.MountPoint)</td><td>$($v.VolumeStatus)</td><td>$state</td><td>$($v.EncryptionPercentage)%</td></tr>`n"
}

$recRows = ""
foreach ($r in $recommendations) { $recRows += "<li>$r</li>`n" }

$appUpdateCount = $appUpgradeParsed.Count
if ($appUpdateCount -eq 0 -and $appUpgradeRaw) {
    $summaryLine = $appUpgradeRaw | Where-Object { $_ -match '^\d+ upgrades? available' } | Select-Object -First 1
    if ($summaryLine -match '^(\d+)') { $appUpdateCount = [int]$matches[1] }
}

$sysInfoRows = ""
if ($sysInfo) {
    $sysInfoRows = @"
    <div class="row"><span>Computer name</span><span>$(Html $sysInfo.ComputerName)</span></div>
    <div class="row"><span>OS</span><span>$(Html $sysInfo.OsName) (build $($sysInfo.OsBuild))</span></div>
    <div class="row"><span>Make / model</span><span>$(Html $sysInfo.Manufacturer) $(Html $sysInfo.Model)</span></div>
    <div class="row"><span>Last boot</span><span>$($sysInfo.LastBoot)</span></div>
    <div class="row"><span>Uptime</span><span>$($sysInfo.UptimeText)</span></div>
"@
}

$defenderNoteText = $defenderNotes -join " "

$bitlockerCard = ""
if ($bitlockerRows) {
    $bitlockerCard = @"
  <div class="card">
    <h2>BitLocker disk encryption</h2>
    <table>
      <tr><th>Drive</th><th>Status</th><th>Protection</th><th>Encrypted</th></tr>
      $bitlockerRows
    </table>
  </div>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Security Report - $(Html $env:COMPUTERNAME)</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, Arial, sans-serif; background: #f6f8fa; color: #1f2328; margin: 0; padding: 32px; }
  .wrap { max-width: 920px; margin: 0 auto; }
  header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 16px; flex-wrap: wrap; gap: 8px; }
  h1 { font-size: 20px; margin: 0; }
  .meta { color: #57606a; font-size: 13px; }
  .status-banner { background: $($c.bg); color: $($c.fg); border: 1px solid $($c.fg); border-radius: 8px; padding: 14px 18px; font-weight: 600; margin-bottom: 24px; }
  .card { background: #fff; border: 1px solid #d0d7de; border-radius: 10px; padding: 18px 20px; margin-bottom: 16px; }
  .card h2 { font-size: 15px; margin: 0 0 12px 0; display: flex; align-items: center; gap: 8px; }
  .row { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #eef1f4; font-size: 13.5px; }
  .row:last-child { border-bottom: none; }
  .row span:first-child { color: #57606a; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid #eef1f4; vertical-align: top; }
  th { color: #57606a; font-weight: 600; font-size: 11.5px; text-transform: uppercase; }
  ol { font-size: 13.5px; padding-left: 20px; }
  ol li { padding: 4px 0; }
  details summary { cursor: pointer; color: #57606a; font-size: 13px; margin: 4px 0; font-weight: 600; }
  .note { font-size: 12.5px; color: #57606a; margin-top: 8px; }
  footer { font-size: 12px; color: #57606a; text-align: center; margin-top: 28px; }
  pre { font-size: 11.5px; white-space: pre-wrap; word-break: break-word; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>PC Security Report</h1>
    <span class="meta">$(Html $env:COMPUTERNAME) &middot; $($Now.ToString("MMM d, yyyy, HH:mm"))</span>
  </header>

  <div class="status-banner">$statusText</div>

  <div class="card">
    <h2>System info</h2>
    $sysInfoRows
  </div>

  <div class="card">
    <h2>Windows Update $(if ($criticalUpdates.Count -gt 0) { Badge "warn" "$($criticalUpdates.Count) critical/important" } else { Badge "ok" "up to date" })</h2>
    <div class="row"><span>Pending updates</span><span>$($pendingUpdates.Count)</span></div>
    <div class="row"><span>Critical/Important pending</span><span>$($criticalUpdates.Count)</span></div>
    <details open>
      <summary>Pending update details</summary>
      <table>
        <tr><th>Title</th><th>Severity</th><th>KB</th><th>Size</th></tr>
        $updateRows
      </table>
    </details>
  </div>

  <div class="card">
    <h2>Windows Defender $(if (-not $defenderOk) { Badge "risk" "issue" } elseif ($defenderNoteText -ne "No issues found.") { Badge "warn" "review" } else { Badge "ok" "ok" })</h2>
    <div class="row"><span>Real-time protection</span><span>$($defender.RealTimeProtectionEnabled)</span></div>
    <div class="row"><span>Antivirus / Antispyware engine</span><span>$($defender.AntivirusEnabled) / $($defender.AntispywareEnabled)</span></div>
    <div class="row"><span>Behavior monitoring / IOAV / on-access</span><span>$($defender.BehaviorMonitorEnabled) / $($defender.IoavProtectionEnabled) / $($defender.OnAccessProtectionEnabled)</span></div>
    <div class="row"><span>Network Inspection System (NIS)</span><span>$($defender.NISEnabled)</span></div>
    <div class="row"><span>Tamper Protection</span><span>$($defender.IsTamperProtected)</span></div>
    <div class="row"><span>Signature version / age</span><span>$($defender.AntivirusSignatureVersion) ($($defender.AntivirusSignatureAge) days)</span></div>
    <div class="row"><span>Last quick scan</span><span>$($defender.LastQuickScan)</span></div>
    <div class="row"><span>Last full scan</span><span>$(if ($defender.LastFullScan) { $defender.LastFullScan } else { "Never run" })</span></div>
    <div class="note">$defenderNoteText</div>
  </div>

  <div class="card">
    <h2>Windows Firewall $(if (-not $firewallOk) { Badge "risk" "disabled profile" } else { Badge "ok" "ok" })</h2>
    <table>
      <tr><th>Profile</th><th>State</th><th>Inbound default</th><th>Outbound default</th></tr>
      $firewallRows
    </table>
  </div>

  $bitlockerCard

  <div class="card">
    <h2>Local user accounts</h2>
    <table>
      <tr><th>Account</th><th>State</th><th>Password required</th><th>Last logon</th></tr>
      $accountRows
    </table>
  </div>

  <div class="card">
    <h2>Services &amp; processes $(if ($suspiciousServices.Count -gt 0 -or $unsignedProcesses.Count -gt 0) { Badge "warn" "review" } else { Badge "ok" "ok" })</h2>
    <div class="row"><span>Running processes</span><span>$processCount</span></div>
    <div class="row"><span>Non-Microsoft services flagged for review</span><span>$($suspiciousServices.Count)</span></div>
    <div class="row"><span>Processes with no publisher info</span><span>$($unsignedProcesses.Count)</span></div>
    <details>
      <summary>Non-Microsoft running services</summary>
      <table>
        <tr><th>Service</th><th>Display name</th><th>Path</th><th>Start mode</th></tr>
        $serviceRows
      </table>
    </details>
    <details>
      <summary>Processes with no publisher info</summary>
      <table>
        <tr><th>Name</th><th>PID</th><th>Path</th></tr>
        $unsignedRows
      </table>
    </details>
    <div class="note">Most OEM/utility services and unsigned tools are legitimate - review anything you don't recognize.</div>
  </div>

  <div class="card">
    <h2>Startup programs</h2>
    <table>
      <tr><th>Name</th><th>Command</th><th>User</th></tr>
      $startupRows
    </table>
  </div>

  <div class="card">
    <h2>Available app updates <span>($appUpdateCount)</span></h2>
    <details>
      <summary>See full list</summary>
      $(if ($appUpgradeParsed.Count -gt 0) { "<table><tr><th>App</th><th>Current</th><th>Available</th></tr>$appRows</table>" } else { "<pre>$appRows</pre>" })
    </details>
  </div>

  <div class="card">
    <h2>Recommendations</h2>
    <ol>
      $recRows
    </ol>
    <div class="note">These are simple rule-based checks (no AI judgment) - use your own judgment for anything ambiguous. Run this script again after making changes to confirm they took effect.</div>
  </div>

  <footer>Generated locally by Check-SystemSecurity-Standalone.ps1 - no cloud agent involved</footer>
</div>
</body>
</html>
"@

$html | Out-File -FilePath $HtmlPath -Encoding utf8

Write-Host "Done. Report saved to: $HtmlPath"
Write-Host "Open it by double-clicking the file, or run: Start-Process `"$HtmlPath`""
