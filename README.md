# PC Security Monitoring — how it works

This folder contains the monitoring system: a local script that reads your PC's real state, plus a Cowork scheduled task that analyzes the results with AI and keeps a live dashboard updated.

## What the local script does (`Check-SystemSecurity.ps1`)

Runs on your PC (not in the cloud) and only **reads** state, never changes anything:

- uninstalled Windows updates (including security ones)
- Windows Defender status (real-time protection, how old the signatures are, last scan)
- installed apps that have a newer version available (via winget)
- programs that auto-start with Windows
- running services that aren't from Microsoft (a signal, not proof, of risk)
- list of active processes

The result is saved to `latest.json` (always overwritten) plus a historical copy in the `history/` folder.

## One-time setup — scheduling it every 2 hours

1. Open **PowerShell as Administrator** (right-click the PowerShell icon → "Run as Administrator").
2. Run:
   ```powershell
   cd "C:\Users\TutuFruti\report_ai"
   .\Register-DailyTask.ps1
   ```
   (the filename is left over from the first version, but it now schedules the run every 2 hours, non-stop — running it again automatically overwrites the old schedule.)
3. Done — the script now runs automatically every 2 hours and writes `latest.json`.

To test it immediately:
```powershell
.\Check-SystemSecurity.ps1
```

## The AI part (Cowork)

A scheduled task runs every 2 hours, reads `latest.json`, compares it with the previous run (from `history/`), and actively decides — not just a mechanical version diff — whether anything looks risky. The analysis becomes a full HTML dashboard with an **AI Recommendations** section written by the agent, published in two places:

- A live dashboard in Cowork ("security-dashboard" artifact) with a **Run Now** button — click it to trigger an immediate re-analysis of the current local data, with a live progress checklist. Note: it can't remotely start a new Windows scan (browsers can't execute local scripts) — it only re-reads whatever `Check-SystemSecurity.ps1` last wrote.
- A static file at `C:\Users\TutuFruti\report_ai\security-report.html` — open it anytime (double-click, opens in a browser) to see the last analysis; it's overwritten on every run, so it always shows the current state.

You'll also get a short chat message in Cowork, but **only if the agent finds a real risk** — not on every 2-hour run.

## Important limitations (so you know what to expect)

- This isn't an antivirus — it doesn't block or remove anything, only flags things.
- The AI analysis is based on what it sees in `latest.json`; if the Windows task isn't running (PC off, task disabled), there's no new data to analyze.
- "Unusual process" detection is based on simple heuristics + AI judgment, not a malware database — for real malware protection, keep Windows Defender or another antivirus active.
