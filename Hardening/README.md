# Harden Windows 11 (ASD/ACSC baseline)

A PowerShell script that applies the ASD/ACSC publication **Hardening Microsoft Windows 11 Workstations** (January 2026) to a standalone, non-domain Windows 11 workstation, with deliberate carve-outs for a developer machine.

The script writes Group Policy registry values, audit policy, account policy, user rights, firewall state and power configuration. Every deviation from the ASD guide is intentional and is printed in the summary at the end of each run.

> [!CAUTION]
> This script changes system-wide security policy. Some settings can prevent applications from starting, prevent drivers from loading, or change how you sign in. Read [Things that will surprise you](#things-that-will-surprise-you) before the first run.

> [!IMPORTANT]
> Run the script with `-DryRun` first. Review the proposed changes and the log, then run it for real.

---

## Contents

- [Purpose](#purpose)
- [Supported environment](#supported-environment)
- [Safety features](#safety-features)
- [Parameters](#parameters)
- [Usage](#usage)
- [Sections](#sections)
- [Things that will surprise you](#things-that-will-surprise-you)
- [Deliberate deviations from ASD](#deliberate-deviations-from-asd)
- [Not automated](#not-automated)
- [Logging](#logging)
- [Backups and rollback](#backups-and-rollback)
- [Verification](#verification)
- [Known limitations](#known-limitations)
- [Security guidance](#security-guidance)
- [References](#references)
- [Disclaimer](#disclaimer)

---

## Purpose

The ASD guidance is written for a managed domain fleet. This script is the standalone-workstation subset of it: everything that can be applied to a single machine without Active Directory, LAPS, WSUS or centralised log forwarding.

It is intended to be run once on a freshly installed Windows 11 machine, from an elevated PowerShell session, signed in as the account you will actually use day to day. Re-running it is safe: values that already match are counted and left alone.

The recommended sequence is:

1. Install Windows 11 and complete first sign-in as your everyday account.
2. Install your antivirus and confirm real-time protection is on.
3. Run the script with `-DryRun` and read the output.
4. Run the script for real.
5. Restart Windows.
6. Re-run with `-Verify` to confirm nothing was reverted.

---

## Supported environment

| Requirement | Details |
|---|---|
| Operating system | Windows 11 (Windows 10 accepts most, but not all, values) |
| Architecture | 64-bit Windows; the script warns on a 32-bit OS |
| PowerShell | Windows PowerShell 5.1 or PowerShell 7 on Windows |
| Privileges | Administrator elevation is required and is checked at startup |
| Domain membership | Designed for a standalone, non-domain machine |
| Hardware | Virtualization Based Security, HVCI and Secure Launch need a compatible CPU, UEFI and Secure Boot |

The script throws immediately when it is not running elevated:

```
Run this script from an elevated PowerShell session (Run as administrator).
```

---

## Safety features

### Three modes

| Mode | Effect |
|---|---|
| `-DryRun` | Prints every change it would make. Writes nothing. |
| `-Verify` | Re-reads every policy value and reports drift. Writes nothing. |
| default | Applies the configuration. |

### Automatic backup

The `Backup` section runs first and writes to `C:\HardeningBackup-<timestamp>\`:

- `secpol-before.inf` - the current local security policy (`secedit /export`);
- `auditpol-before.csv` - the current audit policy (`auditpol /backup`);
- `HKLM-Policies.reg` and `HKCU-Policies.reg` - the current policy registry hives;
- a System Restore point, unless `-NoRestorePoint` is supplied.

### Per-setting error handling

Each policy value and each action is applied independently. A failure is counted and logged; the remaining settings still run. The summary reports `changed`, `already correct` and `failed` counts.

### Opt-in sections

`FIPS` and `StrongKeyProtection` are off unless named in `-Enable`. Both routinely break developer tooling.

### Skippable sections

Any section can be excluded with `-Skip`. Use this when a setting conflicts with hardware or software you depend on.

### Language-independent

Audit subcategories are set by GUID and user rights by well-known SID, so the script behaves identically on any Windows display language.

---

## Parameters

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `-Skip` | `string[]` | empty | Section names to skip. |
| `-Enable` | `string[]` | empty | Opt-in sections to apply: `FIPS`, `StrongKeyProtection`. |
| `-DryRun` | `switch` | off | Print every change without making it. |
| `-Verify` | `switch` | off | Make no changes; re-read values and report drift. |
| `-NtpServer` | `string` | `time.windows.com` | NTP source, so log timestamps line up. Ignored on a domain-joined machine. |
| `-TranscriptDir` | `string` | `C:\ProgramData\PSTranscripts` | PowerShell transcript output directory. |
| `-LogPath` | `string` | `C:\Harden-Win11-ASD.log` | Run log. |
| `-NoRestorePoint` | `switch` | off | Skip creating a System Restore point during backup. |

---

## Usage

### 1. Preview every change

```powershell
.\Harden-Win11-ASD.ps1 -DryRun
```

This also prints the full list of section names for use with `-Skip`.

### 2. Apply the configuration

```powershell
.\Harden-Win11-ASD.ps1
```

### 3. Apply, keeping the legacy Run list and sleep

```powershell
.\Harden-Win11-ASD.ps1 -Skip RunLists,Power
```

### 4. Apply, keeping a Thunderbolt dock working

```powershell
.\Harden-Win11-ASD.ps1 -Skip DMA
```

### 5. Apply with the opt-in sections

```powershell
.\Harden-Win11-ASD.ps1 -Enable FIPS,StrongKeyProtection
```

### 6. Check for drift after a reboot

```powershell
.\Harden-Win11-ASD.ps1 -Verify
```

### 7. Use a custom log path

```powershell
.\Harden-Win11-ASD.ps1 -LogPath 'D:\Logs\harden.log'
```

---

## Sections

| Section | What it does | ASD pages |
|---|---|---|
| `Backup` | Exports security policy, audit policy and policy hives; creates a restore point. | - |
| `AntivirusCheck` | Reports registered antivirus and real-time state. Read-only. | 3–4, 6, 16–18 |
| `ExploitProtection` | System-wide DEP, bottom-up and high-entropy ASLR, SEHOP, CFG; blocks user override. | 9 |
| `CredentialProtection` | Cached logons = 1, WDigest off, LSA protected process, no custom SSPs. | 5–6 |
| `VBS` | Virtualization Based Security, HVCI, Credential Guard, Secure Launch, kernel shadow stacks. | 6 |
| `UAC` | Admin Approval Mode, credential prompt on the secure desktop, installer detection. | 8–9 |
| `Logon` | No network selection or user enumeration at the lock screen, CTRL+ALT+DEL required, Early Launch Antimalware, Safe Mode blocked for non-admins. | 7–8, 41 |
| `RunLists` | Ignores the legacy `HKLM` Run list. | 31 |
| `Audit` | 20 audit subcategories, command line in process creation, event log sizes, NTP client. | 19–21 |
| `Autoplay` | Autoplay and AutoRun off on all drives. | 21 |
| `AttachmentManager` | Zone information preserved, Unblock button hidden. Per-user. | 18 |
| `Network` | Anonymous access, NTLMv2-only, Kerberos AES, secure channel, MSS settings, LLMNR off, network bridging off, hardened UNC paths, RPC restrictions, WPAD blocked, NetBIOS over TCP/IP off. | 15, 22, 30, 32–34, 40, 42–43, 48 |
| `SMB` | SMB signing required both ways, SMBv1 client driver and feature removed, in-place sharing off. | 29, 43 |
| `Firewall` | All three profiles on, default-block inbound, block logging on. | 45 |
| `RDP` | Remote Desktop and Remote Assistance disabled outright; hardened settings written anyway; firewall rule groups disabled. | 39 |
| `WinRM` | Basic and Digest auth off, unencrypted traffic off, remote shell access off. | 36 |
| `PowerShellLogging` | Module logging, script block logging and transcription on; transcript directory ACLed to Administrators and SYSTEM. | 36–37 |
| `Printers` | Driver installation restricted to administrators, Redirection Guard, RPC over TCP with packet privacy, no web driver download. | 37–38 |
| `Power` | Password on wake; sleep and hibernation disabled. | 35 |
| `SessionLock` | 15-minute inactivity lock, secure screen saver, no lock-screen camera, slideshow, notifications or voice activation. | 44–45 |
| `Privacy` | Telemetry off, location off, web search and Cortana off, Copilot and Widgets off, Game DVR off, SmartScreen set to Block, Windows Installer elevation off, file extensions shown. | 30–31, 34, 40–42, 49–52 |
| `Update` | Automatic download and daily install at 03:00, including other Microsoft products; "Pause updates" removed. | 12–13 |
| `DriveEncryptionCheck` | Reports BitLocker volume status. Read-only. | 24–28 |
| `DMA` | Kernel DMA Protection set to block all; FireWire, Thunderbolt and SBP-2 blocked at device install. | 24 |
| `FIPS` | Opt-in. FIPS algorithm policy on. | - |
| `StrongKeyProtection` | Opt-in. Password prompt on every private key use. | - |
| `AccountPolicy` | 15-character minimum password, 24-password history, 5-attempt lockout, guest account off, user rights assignment, applied via `secedit`. | 15, 34, 46–48 |
| `HardwareCheck` | Reports Secure Boot, TPM and running Device Guard services. Read-only. | 21, 47 |

---

## Things that will surprise you

The script prints these at the end of every run. They are the settings most likely to change how the machine behaves day to day.

| Change | Consequence | How to undo it |
|---|---|---|
| UAC asks for your password | Every elevation prompts for credentials on the secure desktop, not Yes/No. | Set `ConsentPromptBehaviorAdmin` to `2` under `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`. |
| Legacy `HKLM` Run list ignored | Third-party updaters and tray applications started from there stop launching. | `-Skip RunLists`, or delete `DisableLocalMachineRun`. |
| Sleep and hibernation off | No fast resume; higher battery drain on a laptop. | `-Skip Power`, or `powercfg /hibernate on` and reset the timeouts. |
| FireWire, Thunderbolt and SBP-2 blocked | A Thunderbolt dock or eGPU stops working. | `-Skip DMA`. |
| HVCI and Credential Guard on | Unsigned or old drivers and some third-party hypervisors can stop loading. | `-Skip VBS`, or clear the values under `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard`. All are set **without** UEFI lock so they can be turned off from Windows. |
| Inbound network logon restricted | Other machines can no longer reach shares on this PC; local accounts are denied network logon. | Adjust `SeNetworkLogonRight` and `SeDenyNetworkLogonRight` in `secpol.msc`. |
| 15-character minimum password | Existing shorter passwords keep working; the next change must meet the new length. | Adjust in `secpol.msc`. |
| Per-user settings | `AttachmentManager` and the screen saver lock are written to `HKCU` and apply only to the account that ran the script. | Re-run as each additional account. |
| 15-minute inactivity lock | The console locks after 15 minutes of no input. | Adjust `InactivityTimeoutSecs`. |

---

## Deliberate deviations from ASD

### My Own requirement

| Not applied | Reason |
|---|---|
| Prevent access to the command prompt, and to registry editing tools | This is a developer workstation. |
| PowerShell "Allow only signed scripts" | Same. The logging half of the PowerShell guidance **is** applied. |
| All Removable Storage deny rules | Removable media stays usable. |
| Microsoft Defender Antivirus configuration | Third-party engine is the real-time engine. |
| Attack Surface Reduction rules | Only function with Defender as the primary real-time scanner. |
| Controlled Folder Access | Same dependency on Defender. |
| All BitLocker policy | Drive encryption is not in use. |
| Microsoft account, Store, MSIX and OneDrive blocks | Visual Studio and Store-delivered tooling depend on them. |
| Remote Desktop "allow users to connect remotely", securely configured | RDP is disabled outright instead. |

> [!WARNING]
> Two of these have consequences worth stating plainly. Without Defender as the primary scanner, Attack Surface Reduction and Controlled Folder Access cannot be configured at all - turn on the Third-party equivalents (Exploit Protection, Ransomware Protection, Web Protection, and scanning of archives and removable drives) yourself. Without drive encryption, anyone with physical access can boot other media, read every file on the disk, and take the SAM database offline to crack password hashes; nothing this script applies prevents that, because these settings only apply while Windows is running.

### Because the ASD value would lock you out, or only makes sense on a domain

| ASD setting | What the script does instead |
|---|---|
| `Administrator account status = Enabled` (page 10) | Left disabled. The ASD value is only correct with LAPS managing the password. |
| `Deny log on locally = Administrators` (page 48) | Not applied - it would lock you out at the console. |
| `Allow log on locally = Users` only (page 47) | Granted to Users **and** Administrators, for the same reason. |
| `Deny log on as a batch job = Administrators` (page 48) | Not applied - it breaks your own scheduled tasks. |
| Account lockout duration `0` (page 15) | 15 minutes. On a single-admin standalone machine, `0` plus "Allow Administrator account lockout" can lock you out permanently. |
| Mandatory (force-relocate) ASLR | Not enabled - it breaks a large amount of software. Enable per-application after testing. |
| UEFI lock on Credential Guard, HVCI and LSA protection | Enabled **unlocked** (`LsaCfgFlags=2`, `RunAsPPL=2`) so a bad driver can be recovered from without physical presence at boot. |

---

## Not automated

These cannot be scripted and must be done by hand:

- Set a UEFI/BIOS supervisor password and restrict the boot order to the internal disk (ASD pages 21, 47).
- Turn on the Malwarebytes equivalents of ASR and Controlled Folder Access.
- Build a WDAC or AppLocker application control ruleset (page 2).
- LAPS, WSUS, AD recovery-key escrow and centralised log forwarding - all need a domain (pages 10, 13, 23).
- Harden Microsoft Edge and Office with the Microsoft Security Baselines (pages 2, 11).
- Stand up a corporate Windows Error Reporting server (page 41).
- CLFS log file authentication (page 19) - no documented standalone registry equivalent.

The `HardwareCheck` section reports Secure Boot, TPM and Device Guard state so you know what is left to do in firmware.

---

## Logging

### Console

Colour-coded by level:

| Level | Meaning |
|---|---|
| `SET` | The value was written. |
| `WOULD` | `-DryRun`: the value would be written. |
| `SKIP` | Section skipped, or the setting is intentionally not applied. |
| `WARN` | Something needs your attention. |
| `FAIL` | The operation failed; the message is included. |
| `DRIFT` | `-Verify`: the value does not match. |

### Log file

Every line is also appended to `C:\Harden-Win11-ASD.log`, or to `-LogPath`.

### PowerShell transcripts

After the `PowerShellLogging` section runs, every PowerShell session on the machine is transcribed to `C:\ProgramData\PSTranscripts` (or `-TranscriptDir`). The directory is ACLed so that only Administrators and SYSTEM can read it, while Users can append.

### Summary

Each run ends with the counts, the full section list, the surprises, the three "not applied" lists, and a reboot reminder.

---

## Backups and rollback

To restore the pre-hardening state from the backup folder:

```powershell
# security policy and user rights
secedit /configure /db "$env:TEMP\rollback.sdb" /cfg 'C:\HardeningBackup-<timestamp>\secpol-before.inf' /areas SECURITYPOLICY USER_RIGHTS

# audit policy
auditpol /restore /file:'C:\HardeningBackup-<timestamp>\auditpol-before.csv'

# policy registry hives
reg import 'C:\HardeningBackup-<timestamp>\HKLM-Policies.reg'
reg import 'C:\HardeningBackup-<timestamp>\HKCU-Policies.reg'
```

> [!NOTE]
> A `.reg` import restores the values that existed at backup time. It does **not** delete values the script added under keys that did not exist before. For a full revert, use the System Restore point, or delete the added values individually.

Settings written outside the policy hives - `HKLM:\SYSTEM\CurrentControlSet\...`, the hosts file entry, `powercfg`, firewall profiles and the SMB1 feature - are not covered by the `.reg` exports and must be reverted by hand or by restore point.

---

## Verification

After the reboot:

```powershell
.\Harden-Win11-ASD.ps1 -Verify
```

`No drift. Every checked value matches the intended configuration.` means every registry value the script sets is still in place.

Values applied through `secedit` (account policy and user rights) are **not** re-read by `-Verify`. Check those with:

```powershell
secedit /export /cfg "$env:TEMP\secpol-now.inf"
notepad "$env:TEMP\secpol-now.inf"
```

Check audit policy, Device Guard and firewall state directly:

```powershell
auditpol /get /category:*

Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard |
    Select-Object SecurityServicesRunning, VirtualizationBasedSecurityStatus

Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction
```

---

## Known limitations

- A reboot is required before Credential Guard, HVCI, Secure Launch, SMBv1 removal and the audit policy take effect.
- `-Verify` covers registry values only, not `secedit`, `auditpol`, `powercfg` or firewall state.
- Per-user (`HKCU`) settings apply only to the account that ran the script.
- On a domain-joined machine, Group Policy overwrites much of this at the next refresh. The script is written for standalone use; only the NTP section detects domain membership and stands down.
- Section names passed to `-Skip` and `-Enable` are matched exactly as listed in the section table.
- The hosts-file WPAD entry is appended once; no rollback step here removes it.
- Hardware-dependent sections fail on machines without the required CPU, UEFI or TPM support. Read the `FAIL` lines.

---

## Security guidance

- Run `-DryRun` first on every machine.
- Read the summary. The deviations are the point of this script, not a footnote.
- Reboot and re-run with `-Verify` before trusting the configuration.
- Keep the backup folder until the machine has been in normal use long enough to expose breakage.
- Encrypt the drive if the machine ever leaves a trusted location. Nothing here substitutes for that.
- Set the UEFI supervisor password. It is the one control that protects the machine while Windows is not running.
- Review each deviation against your own threat model before reusing this script elsewhere. The carve-outs are tuned to one developer workstation.

---

## References

- Australian Signals Directorate, **Hardening Microsoft Windows 11 Workstations**  
  https://www.cyber.gov.au/resources-business-and-government/maintaining-devices-and-systems/system-hardening-and-administration/system-hardening/hardening-microsoft-windows-workstations

- Australian Signals Directorate, **Essential Eight Maturity Model**  
  https://www.cyber.gov.au/resources-business-and-government/essential-cyber-security/essential-eight/essential-eight-maturity-model

- Microsoft Learn, **Virtualization-based Security (VBS) and HVCI**  
  https://learn.microsoft.com/windows-hardware/design/device-experiences/oem-vbs

- Microsoft Learn, **Configuring Additional LSA Protection**  
  https://learn.microsoft.com/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection

- Microsoft Learn, **Advanced security audit policy settings**  
  https://learn.microsoft.com/windows/security/threat-protection/auditing/advanced-security-audit-policy-settings

- Microsoft Learn, **secedit**  
  https://learn.microsoft.com/windows-server/administration/windows-commands/secedit

- Microsoft Learn, **About Logging Windows (PowerShell)**  
  https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_logging_windows

- Microsoft Learn, **Microsoft Security Compliance Toolkit and baselines**  
  https://learn.microsoft.com/windows/security/operating-system-security/device-management/windows-security-configuration-framework/security-compliance-toolkit-10

---

## Disclaimer

This script applies a security baseline adapted for one specific standalone developer workstation. Test it in a disposable virtual machine before running it on a machine you depend on. Review and adapt every section to your own hardware, installed software, management model and recovery requirements.

The author and distributor are not responsible for data loss, application or driver failure, lockout, policy violations, or operational disruption caused by running the script without appropriate review, backup, testing and authorisation.
