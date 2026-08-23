# Remove Firefox Remnants for Windows

A defensive PowerShell cleanup utility for removing practical remnants of **Mozilla Firefox** and **Firefox Developer Edition** after the browser has already been uninstalled.

The script removes Firefox program directories, user profiles, caches, crash dumps, shortcuts, scheduled tasks, firewall rules, services, application registrations, and known Firefox-related registry entries. An optional deep-clean mode also removes selected Windows execution-history records.

> [!CAUTION]
> This script performs destructive cleanup. Firefox profiles contain bookmarks, saved passwords, cookies, browsing history, sessions, extensions, certificates, and settings. Deleted profile data cannot normally be recovered without a backup.

> [!IMPORTANT]
> Run the script with `-WhatIf` first. Review the proposed operations and the generated log before performing the actual cleanup.

---

## Contents

- [Purpose](#purpose)
- [Supported environment](#supported-environment)
- [Safety features](#safety-features)
- [What the script removes](#what-the-script-removes)
- [What the script intentionally preserves](#what-the-script-intentionally-preserves)
- [What the script does not remove](#what-the-script-does-not-remove)
- [Parameters](#parameters)
- [Usage](#usage)
- [Running on a hardened workstation](#running-on-a-hardened-workstation)
- [Logging and exit codes](#logging-and-exit-codes)
- [Common failures and supported workarounds](#common-failures-and-supported-workarounds)
- [Known limitations](#known-limitations)
- [Post-cleanup verification](#post-cleanup-verification)
- [Security guidance](#security-guidance)
- [References](#references)

---

## Purpose

A normal Firefox uninstall can leave behind user data and Windows integration records. This script is intended for situations such as:

- preparing for a completely clean Firefox reinstall;
- removing Firefox Developer Edition after uninstalling it;
- deleting abandoned Firefox profiles and caches;
- removing obsolete Firefox firewall rules and scheduled tasks;
- clearing stale Firefox application registrations;
- removing selected Firefox execution-history records from Windows.

This is a **post-uninstallation cleanup tool**, not a replacement for the Firefox uninstaller.

The recommended sequence is:

1. Export or back up anything that must be retained.
2. Uninstall every unwanted Firefox edition through Windows.
3. Restart Windows if the uninstaller requests it.
4. Run this script with `-WhatIf`.
5. Review the console output and log.
6. Run the actual cleanup.
7. Restart Windows and perform the read-only verification checks.

---

## Supported environment

| Requirement | Details |
|---|---|
| Operating system | Windows only |
| Architecture | 64-bit PowerShell on a 64-bit Windows installation |
| Windows versions | Designed for current Windows 10 and Windows 11 systems |
| PowerShell | Windows PowerShell 5.1 or PowerShell 7 on Windows |
| Privileges | Administrator elevation is required |
| Script host | A normal interactive administrative PowerShell session is recommended |

The script declares:

```powershell
#requires -Version 5.1
#requires -RunAsAdministrator
```

It stops immediately when run on a non-Windows system or from a 32-bit PowerShell process on 64-bit Windows.

---

## Safety features

### Dry-run support

The script uses PowerShell's `ShouldProcess` model and supports:

```powershell
-WhatIf
-Confirm
```

`-WhatIf` displays and logs the operations that would be attempted without performing the removals.

### Installed-browser detection

Before cleanup, the script checks:

- registered Firefox uninstall entries;
- known `firefox.exe` installation paths;
- the Microsoft Store `Mozilla.Firefox` package.

If Firefox still appears installed, cleanup stops unless `-ForceEvenIfInstalled` is supplied.

### Other Mozilla product detection

The script checks uninstall registrations for other Mozilla products such as Thunderbird or SeaMonkey. When another Mozilla product appears to remain installed, it attempts to preserve shared Mozilla data and the Mozilla Maintenance Service.

This detection is heuristic. Portable, damaged, or unregistered Mozilla installations may not be detected.

### Per-operation error handling

Each removal operation is attempted independently. One failed deletion does not normally stop the remaining cleanup. Failures are counted and recorded in the log.

### Explicit confirmation impact

The script declares a high confirmation impact:

```powershell
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
```

Use `-Confirm:$false` only after reviewing a `-WhatIf` run.

---

## What the script removes

### Running Firefox processes

The script stops the following processes when found:

- `firefox.exe`;
- `private_browsing.exe`;
- `default-browser-agent.exe`.

### Scheduled tasks

It removes scheduled tasks whose task path or task name contains:

- `Firefox`;
- `Default Browser Agent`.

This typically includes Firefox background-update and default-browser-agent tasks.

### Windows Firewall rules

The script examines firewall-rule names, descriptions, and application filters. It removes rules associated with:

- Firefox;
- Firefox Developer Edition;
- `firefox.exe`;
- known Firefox installation directories.

### Mozilla Maintenance Service

When no other registered Mozilla product is detected, the script can:

- stop the `MozillaMaintenance` service;
- delete the service with `sc.exe`;
- remove its service registry key;
- remove the Mozilla Maintenance Service directory.

Use `-KeepMaintenanceService` to preserve it explicitly.

### System-level directories

The script targets known locations including:

```text
%ProgramFiles%\Mozilla Firefox
%ProgramFiles%\Firefox Developer Edition
%ProgramFiles%\Mozilla Maintenance Service
%ProgramFiles(x86)%\Mozilla Firefox
%ProgramFiles(x86)%\Firefox Developer Edition
%ProgramFiles(x86)%\Mozilla Maintenance Service
%ProgramData%\Mozilla
%ProgramData%\Mozilla-1de3e3c7-1234-4177-a864-e594e8d1fb38
```

Shared Mozilla directories may be preserved when another Mozilla product appears installed.

### User profile data

For each selected Windows user profile, the script targets locations including:

```text
AppData\Roaming\Mozilla\Firefox
AppData\Roaming\Mozilla\Extensions\{ec1311f7-c20a-464f-9b0e-13a3a9e97384}
AppData\Local\Mozilla\Firefox
AppData\Local\Mozilla\updates
AppData\LocalLow\Mozilla\Firefox
AppData\Local\Firefox
AppData\Local\Programs\Mozilla Firefox
AppData\Local\Programs\Firefox Developer Edition
Desktop\Old Firefox Data
```

It also removes matching:

- Firefox Microsoft Store package-data directories;
- Firefox crash dumps;
- Default Browser Agent crash dumps;
- Firefox temporary directories;
- Start Menu shortcuts;
- taskbar shortcuts;
- recent-item shortcuts;
- desktop shortcuts.

When no other Mozilla product is detected, additional Mozilla temporary files and selected `plugin-container.exe` crash dumps are also targeted.

### Registry registrations

The script removes known Firefox-related entries from areas including:

- `HKCU\Software\Mozilla` Firefox subkeys;
- `HKLM\Software\Mozilla` Firefox subkeys;
- 32-bit Mozilla registry locations under `WOW6432Node`;
- Firefox `App Paths` registrations;
- Firefox uninstall registrations;
- legacy `Mozilla.org` Firefox registrations;
- Firefox ProgIDs and application classes;
- `Applications\firefox.exe` and `Applications\private_browsing.exe` classes;
- Start Menu Internet client registrations;
- Registered Applications values;
- startup and Run/RunOnce values;
- application-association notification values;
- selected Jump List registration values;
- Firefox `OpenWithList` and `OpenWithProgids` values.

The script also removes Mozilla `NativeMessagingHosts` registry keys from the explicitly listed Mozilla locations. Review the dry run carefully if another Mozilla application or enterprise integration uses native-messaging registrations.

### Firefox enterprise policies

With `-RemovePolicies`, the following Firefox policy keys are targeted:

```text
HKCU\Software\Policies\Mozilla\Firefox
HKLM\Software\Policies\Mozilla\Firefox
HKLM\Software\WOW6432Node\Policies\Mozilla\Firefox
```

The parent Mozilla policy key and policies for unrelated applications are not intentionally removed.

### Deep-clean execution history

With `-DeepClean`, the script additionally targets selected Firefox-related records in:

- Windows Prefetch;
- Application Compatibility Assistant history;
- AppCompat `Layers`;
- MUI cache locations;
- Explorer UserAssist;
- Background Activity Moderator (BAM);
- Desktop Activity Moderator (DAM);
- recent-item shortcuts.

UserAssist names are ROT13-encoded by Windows; the script converts matching names before inspection.

`-DeepClean` is practical cleanup only. It does not provide forensic erasure.

---

## What the script intentionally preserves

The script attempts to preserve:

- Thunderbird profile directories;
- Thunderbird-specific registry keys;
- the Mozilla Maintenance Service when another registered Mozilla product is detected;
- shared Mozilla ProgramData directories when another Mozilla product is detected;
- the shared local Mozilla update directory when another Mozilla product is detected;
- unrelated browser and application registrations.

Use `-KeepMaintenanceService` when the maintenance service must remain regardless of automatic detection.

> [!WARNING]
> Preservation is based mainly on uninstall registrations. A portable or partially removed Mozilla product may not be recognised. Always inspect `-WhatIf` output on a system that still uses Thunderbird or another Mozilla application.

---

## What the script does not remove

The following are outside the script's scope:

- Windows event logs;
- Microsoft Defender, EDR, antivirus, or security-product history;
- filesystem journal records and filesystem metadata;
- Volume Shadow Copies and restore points;
- backups created by other applications;
- Windows Search index records;
- Amcache, SRUM, and every possible compatibility database;
- DNS, router, proxy, firewall-appliance, or network-provider logs;
- cloud-synchronised Firefox data stored on Mozilla's servers;
- Firefox installers saved in Downloads, Desktop, or arbitrary folders;
- arbitrary files whose names do not match the known cleanup patterns;
- Microsoft Store package registration through `Remove-AppxPackage`;
- default-browser reassignment to another application;
- guaranteed cleanup of every per-user registry hive for users who are logged off;
- secure overwrite of free disk space or previously occupied disk sectors.

The script may remove an execution-history reference to a Firefox installer without deleting the installer executable itself.

---

## Parameters

| Parameter | Type | Purpose |
|---|---:|---|
| `-AllUsers` | Switch | Removes Firefox files from all local, non-special user profiles discovered through `Win32_UserProfile`. Without it, only the current profile's files are cleaned. |
| `-RemovePolicies` | Switch | Removes the listed Firefox enterprise-policy keys from HKCU and HKLM. |
| `-DeepClean` | Switch | Removes selected Firefox execution-history traces such as Prefetch, BAM/DAM, UserAssist, MUI cache, AppCompat, and recent-item entries. |
| `-ForceEvenIfInstalled` | Switch | Continues even when Firefox still appears installed. This can destroy a working installation and should normally not be used. |
| `-KeepMaintenanceService` | Switch | Preserves the Mozilla Maintenance Service even if no other Mozilla product is detected. |
| `-LogPath` | String | Overrides the default log-file location. |
| `-WhatIf` | Common parameter | Simulates removal operations without changing the system. |
| `-Confirm` | Common parameter | Controls interactive confirmation. `-Confirm:$false` suppresses operation prompts but does not bypass Windows security controls. |

### Important `-AllUsers` distinction

`-AllUsers` provides broad **filesystem cleanup** for discovered local profiles. It does not load the `NTUSER.DAT` hive of every logged-off user. Therefore, it does not guarantee complete HKCU cleanup for every account.

For comprehensive per-user registry cleanup, run the script in each relevant user's interactive context, or deploy it through an approved management mechanism that runs once for each user.

---

## Usage

Assume the script is named:

```text
Remove-FirefoxRemnants.ps1
```

### 1. Inspect the script and its signature

```powershell
Get-FileHash .\Remove-FirefoxRemnants.ps1 -Algorithm SHA256
Get-AuthenticodeSignature .\Remove-FirefoxRemnants.ps1 | Format-List
```

### 2. Check effective PowerShell execution policy

```powershell
Get-ExecutionPolicy -List
```

On a hardened workstation, follow the signed-script requirements established by the applicable local, Group Policy, MDM, or organisational policy. Do not weaken the policy merely to run a cleanup utility.

### 3. Dry run for the current user

```powershell
.\Remove-FirefoxRemnants.ps1 -RemovePolicies -DeepClean -WhatIf
```

### 4. Actual cleanup for the current user

```powershell
.\Remove-FirefoxRemnants.ps1 `
    -RemovePolicies `
    -DeepClean `
    -Confirm:$false
```

### 5. Dry run for all discovered local user profiles

```powershell
.\Remove-FirefoxRemnants.ps1 `
    -AllUsers `
    -RemovePolicies `
    -DeepClean `
    -WhatIf
```

### 6. Actual cleanup for all discovered local user profiles

```powershell
.\Remove-FirefoxRemnants.ps1 `
    -AllUsers `
    -RemovePolicies `
    -DeepClean `
    -Confirm:$false
```

### 7. Preserve the Mozilla Maintenance Service

```powershell
.\Remove-FirefoxRemnants.ps1 `
    -AllUsers `
    -KeepMaintenanceService `
    -WhatIf
```

### 8. Use a custom log path

```powershell
.\Remove-FirefoxRemnants.ps1 `
    -AllUsers `
    -DeepClean `
    -LogPath 'C:\Logs\Remove-FirefoxRemnants.log' `
    -WhatIf
```

### 9. Force cleanup while Firefox still appears installed

```powershell
.\Remove-FirefoxRemnants.ps1 `
    -ForceEvenIfInstalled `
    -WhatIf
```

> [!DANGER]
> `-ForceEvenIfInstalled` can damage or destroy an active Firefox installation. Prefer uninstalling Firefox correctly and resolving stale installation detection instead.

---

## Running on a hardened workstation

Workstations configured with hardened security controls typically restrict PowerShell script execution and allow only signed scripts, with module logging, script‑block logging, and transcription enabled.

A hardened workstation may therefore:

- reject unsigned `.ps1` files;
- block execution through Windows Defender Application Control or AppLocker;
- require a trusted publisher certificate;
- record the complete script and command activity through PowerShell logging;
- require credential entry on the Secure Desktop for elevation;
- restrict registry modification;
- prevent modification of protected Windows registry areas even from an elevated administrator session.

### Recommended hardened-system workflow

1. Review the script source.
2. Calculate and record its SHA-256 hash.
3. Validate its Authenticode signature.
4. Sign it with an approved code-signing certificate when policy requires this.
5. Run it from an approved location and administrative PowerShell host.
6. Start with `-WhatIf`.
7. Retain the cleanup log and any PowerShell transcript required by policy.
8. Do not disable application control, UAC, registry protections, EDR, or execution-policy Group Policy merely to remove low-value historical metadata.

### Checking a signature

```powershell
Get-AuthenticodeSignature .\Remove-FirefoxRemnants.ps1 |
    Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate
```

### Signing with an existing approved code-signing certificate

```powershell
$certificate = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.HasPrivateKey } |
    Select-Object -First 1

if (-not $certificate) {
    throw 'No usable code-signing certificate was found.'
}

Set-AuthenticodeSignature `
    -FilePath .\Remove-FirefoxRemnants.ps1 `
    -Certificate $certificate
```

Use only a certificate and trust process approved for the workstation. Creating an arbitrary trusted certificate solely to bypass policy defeats the purpose of signed-script enforcement.

---

## Logging and exit codes

### Default log location

Unless `-LogPath` is supplied, the log is created under the current user's temporary directory:

```text
%TEMP%\Remove-FirefoxRemnants-yyyyMMdd-HHmmss.log
```

Each entry contains:

```text
[timestamp] [level] message
```

Possible levels are:

- `INFO`;
- `WARN`;
- `ERROR`;
- `REMOVED`;
- `SKIPPED`.

### Completion summary

A normal completion ends with a summary similar to:

```text
Cleanup completed. Removed=41; Skipped=0; Failed=5; Log=C:\...\Remove-FirefoxRemnants.log
```

The counters represent attempted cleanup operations, not necessarily individual files inside a recursively deleted directory.

### Exit codes

| Exit code | Meaning |
|---:|---|
| `0` | Cleanup completed and no removal operation reported a failure. |
| `1` | Cleanup reached the end but one or more removal operations failed. |
| Non-zero due to a terminating error | A prerequisite or safety check failed, such as non-Windows execution, 32-bit PowerShell, missing elevation, or a detected Firefox installation. |

A non-zero exit code does not automatically mean Firefox remains installed. Protected historical records may produce failures while all program files and profiles have already been removed.

---

## Common failures and supported workarounds

### `Attempted to perform an unauthorized operation` for `UserChoice`

Example:

```text
HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice
HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice
```

**Cause:** Windows protects default-application choices. Current Windows versions use protected and obfuscated registry data for default apps, and applications are expected to direct the user to Windows Settings rather than modify the protected values directly.

**Supported response:** Open Default apps and select the required browser or PDF application:

```powershell
Start-Process 'ms-settings:defaultapps'
```

Review at least:

- `HTTP`;
- `HTTPS`;
- `.htm`;
- `.html`;
- `.pdf`.

**Do not:** take ownership of `UserChoice`, replace its ACL, disable Windows default-app protection, or use unsupported tools that forge the association hash.

This failure does not mean Firefox program data survived. It means Windows refused direct manipulation of a protected user preference.

---

### `Cannot delete a subkey tree because the subkey does not exist`

**Cause:** A race condition between the initial existence check and the deletion. Windows, Explorer, or another cleanup step may have removed or refreshed the key after it was detected.

**Supported response:** Re-check the path. If it no longer exists, no further action is required.

```powershell
Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice'
```

A `False` result confirms that the desired state has already been reached.

---

### `Requested registry access is not allowed` for BAM or DAM

Example:

```text
HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings\...
```

**Cause:** BAM and DAM are Windows-owned activity-history areas. Their ACLs, security software, application control, or hardening policy may prevent modification even from an elevated administrator session.

**Supported response:** Leave the protected entries in place. They are historical execution records, not Firefox executables, profiles, services, scheduled tasks, or startup persistence.

**Do not:**

- take ownership of the BAM or DAM tree;
- grant administrators full control;
- launch Registry Editor as `SYSTEM`;
- disable EDR or security policy;
- use recovery mode solely to circumvent the protection.

The security risk introduced by weakening a protected system area is greater than the value of deleting a stale history value.

---

### `Firefox still appears installed`

**Cause:** The script found both a registered Firefox installation and an existing executable, or found a Microsoft Store Firefox package.

**Supported response:**

1. Check **Settings > Apps > Installed apps**.
2. Uninstall Firefox or Firefox Developer Edition normally.
3. Restart Windows.
4. Confirm that the known executable paths no longer exist.
5. Rerun the dry run.

Useful checks:

```powershell
Get-ItemProperty `
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue |
    Where-Object DisplayName -Match 'Firefox'

Get-AppxPackage -Name Mozilla.Firefox -ErrorAction SilentlyContinue
```

Use `-ForceEvenIfInstalled` only when the detection is understood and destructive cleanup is intentional.

---

### Script is blocked by execution policy

Typical messages mention that scripts are disabled, the file is not digitally signed, or the publisher is not trusted.

**Cause:** The effective `MachinePolicy`, `UserPolicy`, or another execution-policy scope requires signed scripts. Group Policy takes precedence over local process or user settings.

**Supported response:**

```powershell
Get-ExecutionPolicy -List
Get-AuthenticodeSignature .\Remove-FirefoxRemnants.ps1
```

Have the script reviewed and signed with an approved code-signing certificate. Ensure the signer is trusted according to the applicable policy.

**Do not:** use `Set-ExecutionPolicy Bypass`, `-ExecutionPolicy Bypass`, encoded commands, renamed interpreters, or other techniques intended to evade policy on a hardened workstation.

---

### Script is blocked by WDAC, AppLocker, Smart App Control, or EDR

**Cause:** Application-control policy does not allow the script, PowerShell host, script location, hash, or publisher.

**Supported response:** Submit the script for approval and add an appropriately scoped publisher, hash, or managed-installer rule through the authorised policy-management process.

Do not disable application control globally. A narrowly scoped approved rule is preferable.

---

### `Run the script from 64-bit Windows PowerShell or 64-bit PowerShell 7`

**Cause:** A 32-bit PowerShell host is running on 64-bit Windows. Registry redirection would make cleanup incomplete or misleading.

**Supported response:** Start the 64-bit host, normally from:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
```

For PowerShell 7, use the normal 64-bit `pwsh.exe` installation.

Confirm with:

```powershell
[Environment]::Is64BitOperatingSystem
[Environment]::Is64BitProcess
```

Both should return `True` on 64-bit Windows.

---

### Administrator elevation is missing

**Cause:** The script requires administrator rights for system folders, HKLM, services, firewall rules, scheduled tasks, and Prefetch.

**Supported response:** Start PowerShell using **Run as administrator** and complete the configured UAC credential prompt on the Secure Desktop.

Do not disable UAC or change the secure-desktop setting.

---

### A file or directory is in use

**Cause:** A Firefox child process, updater, shell component, security scanner, or another process still holds an open handle.

**Supported response:**

1. Close all Firefox windows.
2. Allow the script to stop its recognised Firefox processes.
3. Restart Windows.
4. Rerun `-WhatIf`, followed by the actual cleanup.

If the item remains locked, identify the owning process with an approved administrative tool. Do not terminate unrelated system or security processes merely to complete cleanup.

---

### Access denied by Controlled Folder Access or security software

**Cause:** Microsoft Defender Controlled Folder Access, EDR, or antivirus policy blocked PowerShell from modifying a protected location.

**Supported response:** Review Windows Security, Defender, EDR, and PowerShell logs. If the operation is genuinely required, approve the exact signed script or administrative workflow through the relevant security policy.

Do not disable protection globally.

---

### Scheduled-task cleanup was skipped

Message:

```text
ScheduledTasks module is unavailable; scheduled-task cleanup was skipped.
```

**Cause:** `Get-ScheduledTask` is unavailable in the current host or Windows image.

**Supported response:** Run the script in the normal 64-bit Windows PowerShell 5.1 environment or a PowerShell 7 session where the Windows compatibility module is available.

Verify with:

```powershell
Get-Command Get-ScheduledTask
```

---

### Firewall cleanup was skipped

Message:

```text
NetSecurity module is unavailable; firewall-rule cleanup was skipped.
```

**Cause:** `Get-NetFirewallRule` is unavailable in the current host or Windows image.

**Supported response:** Use a normal supported Windows administrative PowerShell host and confirm:

```powershell
Get-Command Get-NetFirewallRule
```

Do not disable Windows Firewall because its management module is unavailable.

---

### Firefox policy keys return after deletion

**Cause:** Group Policy, MDM, security configuration management, or another authoritative policy source reapplied the settings.

**Supported response:** Change or remove the policy at its authoritative source only when authorised. Local registry deletion is not a durable workaround for centrally managed policy.

On a hardened workstation, the policy may be intentional and should normally be retained.

---

### Shared Mozilla files or the maintenance service remain

**Cause:** The script detected another registered Mozilla product and intentionally preserved shared components.

**Supported response:** Confirm whether Thunderbird, SeaMonkey, or another Mozilla application remains installed. Use `-KeepMaintenanceService` when preservation is required. Remove shared components manually only after confirming that no remaining Mozilla application depends on them.

---

### Another user's registry entries remain after `-AllUsers`

**Cause:** The script removes files from discovered local profiles but does not mount every logged-off user's registry hive.

**Supported response:** Run the script once in each affected user's context, or use an approved endpoint-management deployment that runs per user.

Avoid manually loading and editing another user's hive unless you have a tested administrative procedure and a backup.

---

## Known limitations

1. **No forensic-erasure guarantee.** The script removes practical remnants, not every trace that could exist on disk, in logs, in backups, or on remote systems.
2. **No uninstall function.** Firefox should be uninstalled before the script is run.
3. **Microsoft Store package registration is not removed.** The script detects Store Firefox and cleans known package-data directories only after the installed-browser safeguard is overridden.
4. **Per-user registry scope is incomplete for logged-off users.** `-AllUsers` primarily extends filesystem cleanup.
5. **Other Mozilla product detection is heuristic.** Unregistered and portable installations can be missed.
6. **Shared native-messaging registrations may be removed.** Review `-WhatIf` when another Mozilla application or enterprise integration remains in use.
7. **Protected Windows values may remain.** UserChoice, BAM, DAM, and other system-managed records can reject deletion by design.
8. **Pattern-based cleanup is conservative.** Installers and unrelated files in arbitrary locations are not deleted merely because Firefox was previously used.
9. **Counts are operation counts.** Removing one directory recursively counts as one removal even if it contains thousands of files.
10. **A failure count can coexist with successful browser removal.** Review what failed rather than treating every non-zero result as evidence that Firefox remains installed.

---

## Post-cleanup verification

Restart Windows before final verification.

### Check common installation and profile paths

```powershell
$firefoxPaths = @(
    "$env:ProgramFiles\Mozilla Firefox",
    "$env:ProgramFiles\Firefox Developer Edition",
    "${env:ProgramFiles(x86)}\Mozilla Firefox",
    "${env:ProgramFiles(x86)}\Firefox Developer Edition",
    "$env:APPDATA\Mozilla\Firefox",
    "$env:LOCALAPPDATA\Mozilla\Firefox"
)

$firefoxPaths | ForEach-Object {
    [pscustomobject]@{
        Path   = $_
        Exists = Test-Path -LiteralPath $_
    }
}
```

Expected result: all unwanted paths report `False`.

### Check running processes

```powershell
Get-Process -Name firefox, private_browsing, default-browser-agent `
    -ErrorAction SilentlyContinue
```

Expected result: no output.

### Check the maintenance service

```powershell
Get-Service -Name MozillaMaintenance -ErrorAction SilentlyContinue
```

Expected result: no output unless the service was intentionally preserved.

### Check scheduled tasks

```powershell
Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object {
        $_.TaskName -match 'Firefox|Mozilla' -or
        $_.TaskPath -match 'Firefox|Mozilla'
    }
```

Review any remaining Mozilla task before deleting it; another Mozilla product may own it.

### Check firewall rules

```powershell
Get-NetFirewallRule -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -match 'Firefox|Mozilla'
    }
```

Review any remaining Mozilla rule before deleting it.

### Check uninstall registrations

```powershell
Get-ItemProperty `
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue |
    Where-Object DisplayName -Match 'Firefox'
```

Expected result: no Firefox uninstall entry.

### Check default applications

```powershell
Start-Process 'ms-settings:defaultapps'
```

Confirm that the desired browser and PDF application are selected.

---

## Security guidance

- Keep `-WhatIf` as the first run on every machine.
- Store the script in a controlled location.
- Verify its hash and Authenticode signature before execution.
- Prefer a publisher-based allow rule for an approved signed script over a broad path or unrestricted PowerShell rule.
- Keep UAC, Secure Desktop, application control, PowerShell logging, Defender, and EDR enabled.
- Treat access-denied results from protected Windows areas as a security boundary, not automatically as a problem to circumvent.
- Retain logs when required for administrative accountability.
- Back up Firefox data before running the script when there is any possibility that it may be needed later.
- Do not use this utility to conceal activity or defeat security monitoring.

---

## References

- Microsoft Learn, **about_Execution_Policies**  
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies

- Microsoft Learn, **about_Signing**  
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_signing

- Microsoft Learn, **Set-AuthenticodeSignature**  
  https://learn.microsoft.com/powershell/module/microsoft.powershell.security/set-authenticodesignature

- Microsoft Learn, **Windows app defaults platform**  
  https://learn.microsoft.com/windows/apps/develop/windows-integration/default-apps-platform

---

## Disclaimer

This script is provided for administrative cleanup. Test it in a disposable virtual machine or representative test environment before broad deployment. Review and adapt it to the workstation's security baseline, installed software, management model, and recovery requirements.

The author and distributor are not responsible for data loss, application damage, policy violations, or operational disruption caused by running the script without appropriate review, backup, testing, and authorisation.
