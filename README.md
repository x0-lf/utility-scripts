# utility-scripts

Windows administration scripts and procedures. Each lives in its own folder with its own README.

| Folder | Contents | What it does | Documentation |
|---|---|---|---|
| [`Hardening/`](Hardening/) | `Harden-Win11-ASD.ps1` | Applies the ASD/ACSC *Hardening Microsoft Windows 11 Workstations* baseline to a standalone Windows 11 workstation, with documented carve-outs for a developer machine. | [Hardening/README.md](Hardening/README.md) |
| [`Firefox/`](Firefox/) | `Remove-FirefoxRemnants.ps1` | Removes leftover Firefox and Firefox Developer Edition files, profiles, tasks, firewall rules and registry entries after uninstalling the browser. | [Firefox/README.md](Firefox/README.md) |
| [`Audit/`](Audit/) | `Export-LockoutEvents.ps1` | Read-only export of account lockout (4740) and failed logon (4625) events from the Security log, with the current lockout and audit policy, to find out why an account keeps locking. | [Audit/README.md](Audit/README.md) |
| [`Recovery/`](Recovery/) | *(procedure, no script)* | Step-by-step recovery of a locked or disabled Windows 10/11 local account via WinRE and the Utility Manager substitution method, with DPAPI data-loss and BitLocker warnings. | [Recovery/README.md](Recovery/README.md) |

All scripts require an elevated PowerShell session.

- **Hardening** and **Firefox** make destructive or system-wide changes. Each has a preview mode — `-DryRun` for the hardening script, `-WhatIf` for the Firefox cleanup — and each README explains what to check before running for real.
- **Audit** changes nothing. It reads the Security log and writes its results to a new folder. Run `-SelfTest` to check it without elevation. The export contains account names and IP addresses; review it before sharing.
- **Recovery** is a manual procedure, not a script, but it changes a security-sensitive system file — follow every step, especially restoring `Utilman.exe`.

**Locked-out account?** Use [`Recovery/`](Recovery/) to get back in, then [`Audit/`](Audit/) to find what caused the lockout so it does not happen again.

Read the folder README (or procedure) before running anything.
