# Register-DailyTask.ps1
# Run this once (as Administrator) to schedule the automatic check every 2 hours.
# Right-click PowerShell -> "Run as Administrator", then:
#   cd "C:\Users\TutuFruti\report_ai"
#   .\Register-DailyTask.ps1
#
# If the task already exists (e.g. it was previously scheduled daily at 08:00), this
# script automatically overwrites it with the new 2-hour interval (-Force).

$ScriptPath = Join-Path $PSScriptRoot "Check-SystemSecurity.ps1"
$TaskName = "MonitorizareSecuritatePC"
$StartTime = (Get-Date).Date.AddHours(8)  # anchored at 08:00 today; repeats every 2 hours, non-stop

$Action  = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

$Trigger = New-ScheduledTaskTrigger -Once -At $StartTime `
    -RepetitionInterval (New-TimeSpan -Hours 2) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -AllowStartIfOnBatteries

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
    -Settings $Settings -Description "Collects Windows Update, Defender, app, and startup state every 2 hours." `
    -RunLevel Highest -Force

Write-Host "Task '$TaskName' scheduled to run every 2 hours (non-stop, with -StartWhenAvailable)."
Write-Host "Check it in Task Scheduler (taskschd.msc), or run it now manually with:"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
