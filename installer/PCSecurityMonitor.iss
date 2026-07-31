; PC Security Monitoring -- installer script (Inno Setup)
; Compile with the Inno Setup Compiler (ISCC.exe / Inno Setup IDE) on Windows to
; produce a single install .exe. See installer/README.md for build instructions.
;
; What it installs:
;   - Check-SystemSecurity.ps1  (read-only local data collector)
;   - Register-DailyTask.ps1    (creates the "MonitorizareSecuritatePC" scheduled task)
;   - README.md / CITESTE-MA.md (documentation)
; and, by default, registers the Windows Scheduled Task that runs the collector
; every 2 hours. Uninstalling removes the scheduled task and the installed
; scripts, but leaves any data the scripts generated (latest.json, history\,
; security-report.html) untouched.

#define MyAppName "PC Security Monitoring"
#define MyAppVersion "1.0"
#define MyAppPublisher "Dan Popa"
#define MyTaskName "MonitorizareSecuritatePC"

[Setup]
AppId={{B6E1B6B0-6C8B-4B9E-9C7B-9B7E9C6B2A11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Registering a scheduled task that runs elevated (RunLevel Highest) requires
; the installer itself to run elevated.
PrivilegesRequired=admin
DefaultDirName={%USERPROFILE}\report_ai
DefaultGroupName=PC Security Monitoring
DisableProgramGroupPage=yes
OutputBaseFilename=PCSecurityMonitor-Setup
OutputDir=Output
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Check-SystemSecurity.ps1
DisableWelcomePage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "registertask"; Description: "Register the scheduled task (runs the check automatically every 2 hours)"; Flags: checkedonce
Name: "runnow"; Description: "Run an initial security scan right after installing"; Flags: unchecked

[Files]
Source: "..\Check-SystemSecurity.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Register-DailyTask.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CITESTE-MA.md"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{app}\history"

[Icons]
Name: "{group}\Run security scan now"; Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Check-SystemSecurity.ps1"""; \
    WorkingDir: "{app}"
Name: "{group}\Open latest report"; Filename: "{app}\security-report.html"; \
    Comment: "Opens once the AI has generated a report"
Name: "{group}\Open install folder"; Filename: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
; Register the scheduled task (elevated, since the installer itself runs elevated).
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Register-DailyTask.ps1"""; \
    WorkingDir: "{app}"; Tasks: registertask; \
    StatusMsg: "Registering the 2-hour scheduled task..."; Flags: runhidden waituntilterminated

; Optional immediate first scan.
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Check-SystemSecurity.ps1"""; \
    WorkingDir: "{app}"; Tasks: runnow; \
    StatusMsg: "Running initial security scan (this can take 1-2 minutes)..."; Flags: runhidden waituntilterminated

Filename: "{app}\README.md"; Description: "View the README"; Flags: postinstall shellexec skipifsilent unchecked

[UninstallRun]
; Best-effort removal of the scheduled task. Errors are ignored (task may
; already be gone, or may never have been registered).
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Unregister-ScheduledTask -TaskName '{#MyTaskName}' -Confirm:$false -ErrorAction SilentlyContinue"""; \
    RunOnceId: "RemoveScheduledTask"; Flags: runhidden waituntilterminated
