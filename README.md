# utility-scripts

Windows administration scripts. Each script lives in its own folder with its own README.

| Folder | Script | What it does | Documentation |
|---|---|---|---|
| [`Hardening/`](Hardening/) | `Harden-Win11-ASD.ps1` | Applies the ASD/ACSC *Hardening Microsoft Windows 11 Workstations* baseline to a standalone Windows 11 workstation, with documented carve-outs for a developer machine. | [Hardening/README.md](Hardening/README.md) |
| [`Firefox/`](Firefox/) | `Remove-FirefoxRemnants.ps1` | Removes leftover Firefox and Firefox Developer Edition files, profiles, tasks, firewall rules and registry entries after uninstalling the browser. | [Firefox/README.md](Firefox/README.md) |
| [`Recovery/`](Recovery/) | *(procedure, no script)* | Step-by-step recovery of a locked or disabled Windows 10/11 local account via WinRE and the Utility Manager substitution method, with DPAPI data-loss and BitLocker warnings. | [Recovery/Windows locked account recovery.md](Recovery/Windows%20locked%20account%20recovery.md) |

Both scripts require an elevated PowerShell session and both make destructive or system-wide changes. Each has a preview mode — `-DryRun` for the hardening script, `-WhatIf` for the Firefox cleanup — and each README explains what to check before running for real. The Recovery entry is a manual procedure, not a script, but it changes a security-sensitive system file — follow every step, especially restoring `Utilman.exe`.

Read the folder README (or procedure) before running anything.
