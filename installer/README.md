# Building the installer

This folder contains `PCSecurityMonitor.iss`, an [Inno Setup](https://jrsoftware.org/isinfo.php)
script that packages the local part of the project (the two PowerShell
scripts) into a single `PCSecurityMonitor-Setup.exe`. Running that installer:

1. Copies `Check-SystemSecurity.ps1`, `Register-DailyTask.ps1`, `README.md`
   and `CITESTE-MA.md` into an install folder (default: `%USERPROFILE%\report_ai`,
   same as the manual setup this project started with).
2. Registers the `MonitorizareSecuritatePC` scheduled task automatically
   (equivalent to running `Register-DailyTask.ps1` by hand), unless the user
   unchecks that option on the tasks page.
3. Optionally runs one scan immediately, if the user checks that box.
4. Adds Start Menu shortcuts: "Run security scan now", "Open latest report",
   "Open install folder", and an uninstaller entry.

Uninstalling removes the scheduled task and the installed scripts, but
**does not** delete `latest.json`, `history\`, or `security-report.html` —
those are your generated data, left in place.

## Why Inno Setup instead of a real `.msi`

Inno Setup produces a `.exe` installer, not a `.msi`. It was chosen because:

- The install itself is simple (copy a couple of scripts + register one
  scheduled task) — no Windows Installer features (rollback transactions,
  Group Policy deployment, WiX's XML component model) are actually needed.
- The `.iss` script above is ~60 lines and easy to read/modify; the
  equivalent WiX `.wxs` for a scheduled-task-registering installer is
  considerably more verbose.
- End users experience the same "double-click, click through a wizard,
  done" flow either way.

If you specifically need a `.msi` (e.g. for deployment via Intune/Group
Policy in an organization), the same steps can be re-expressed with the
[WiX Toolset](https://wixtoolset.org/), using a `ScheduledTask` custom
action or a `[Setup Type=Immediate]` `Exec` element to call
`Register-DailyTask.ps1`.

## How to build it

This has to be done on Windows (Inno Setup itself is a Windows tool).

1. Install [Inno Setup](https://jrsoftware.org/isdl.php) (free).
2. Open `installer/PCSecurityMonitor.iss` in the Inno Setup Compiler (or
   run `ISCC.exe installer\PCSecurityMonitor.iss` from a command prompt).
3. The compiled installer is written to `installer/Output/PCSecurityMonitor-Setup.exe`.

## Notes / things to double check before distributing

- The installer requests admin privileges (`PrivilegesRequired=admin`),
  because `Register-DailyTask.ps1` registers the task with `-RunLevel
  Highest`, which the SOP documents as required for reading Windows
  Defender status and enumerating all services.
- `security-report.html` and the AI-analysis side of the project are
  produced by the Cowork/Claude scheduled task, not by this installer —
  installing this package only sets up the local, read-only data
  collection half described in `README.md`.
- If you rename the install folder away from the SOP-documented
  `C:\Users\<you>\report_ai` path, update
  `PC-Security-Monitoring-SOP.docx` accordingly, since it references that
  path directly.
