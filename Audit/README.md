# Audit

Read-only scripts for collecting Windows security evidence. Nothing in this folder changes system settings, clears logs, resets passwords or uploads data.

| File | What it does |
|---|---|
| [`Export-LockoutEvents.ps1`](Export-LockoutEvents.ps1) | Exports account lockout (**4740**) and failed logon (**4625**) events from the local Security log, together with the current account-lockout and audit policy, into a new folder for review. |

---

# Export-LockoutEvents.ps1

Answers the question *"Why does this account keep getting locked out?"* on a single Windows PC. The script reads every retained 4740 and 4625 event from the local Security log, writes them to a JSON Lines file with all named event fields preserved, and writes a context report describing what was collected, what could not be, and how to interpret it.

> [!IMPORTANT]
> Run the export in **Windows PowerShell as Administrator** on the PC where the lockout happened. The Security log cannot be read without elevation.

> [!NOTE]
> The export contains account names, computer names, IP addresses and process paths. Review it before sharing it with anyone or pasting it into an AI tool.

---

## Contents

- [When to use it](#when-to-use-it)
- [Requirements](#requirements)
- [Parameters](#parameters)
- [Usage](#usage)
- [Output](#output)
- [Reviewing the results](#reviewing-the-results)
- [Limits](#limits)
- [Related](#related)

---

## When to use it

- An account shows *"The referenced account is currently locked out and may not be logged on to"* and you want to know what caused it before or after unlocking it (see [`Recovery/`](../Recovery/)).
- An account locks out repeatedly and you suspect a stale saved password: a mapped drive, scheduled task, service, cached RDP credential, or another device still using the old password.
- You want to check whether something on the network is guessing passwords against the PC.
- You need a timestamped, record-numbered copy of the evidence before the Security log rolls over.

The events it collects:

| Event ID | Meaning | Logged when | Audit subcategory that must be enabled |
|---|---|---|---|
| **4625** | An account failed to log on | Every failed logon attempt, including attempts rejected because the account is already locked | **Logon** — Failure (also **Account Lockout** — Failure) |
| **4740** | A user account was locked out | The moment the failed-attempt threshold is reached | **User Account Management** — Success |

For a local account, both events are logged on the PC itself. For a **domain** account, 4740 is logged on the domain controller, not the workstation — see [Limits](#limits).

---

## Requirements

- Windows 10 or Windows 11.
- **Windows PowerShell 5.1**, started with **Run as administrator**. The script stops with an error if the session is not elevated (except `-SelfTest`, which needs no elevation).
- Auditing enabled for the subcategories above. The events only exist if auditing was on *when the lockout happened*. Check the current state from an elevated prompt:

  ```powershell
  auditpol /get /subcategory:"{0CCE9215-69AE-11D9-BED3-505054503030},{0CCE9235-69AE-11D9-BED3-505054503030},{0CCE9217-69AE-11D9-BED3-505054503030}"
  ```

  These GUIDs are *Logon*, *User Account Management* and *Account Lockout*, and work on any Windows display language. The [`Hardening/`](../Hardening/) script enables all three.

- Write access to the folder the script lives in, or pass `-OutputDirectory`.

---

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Days` | `int` (0–36500) | `0` | Look back this many days from now. `0` exports **all retained** history in the Security log. |
| `-OutputDirectory` | `string` | `.\LockoutReview-<guid>` next to the script | Folder to create for the export. It **must not already exist** — the script refuses to overwrite a previous export. |
| `-SelfTest` | `switch` | off | Tests the event parser against built-in sample events and exits. Reads no logs, writes no files, needs no elevation. |

---

## Usage

Open **Windows PowerShell** with **Run as administrator** and change to this folder first:

```powershell
Set-Location <path-to>\utility-scripts\Audit
```

If the script is blocked because it was downloaded, or because of the execution policy, either unblock it or allow it for this one process only:

```powershell
Unblock-File .\Export-LockoutEvents.ps1
# or
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Export-LockoutEvents.ps1
```

On a workstation that only allows signed scripts, follow the signing workflow in [Firefox/README.md — Running on a hardened workstation](../Firefox/README.md#running-on-a-hardened-workstation) instead of bypassing policy.

### 1. Check the script works (no elevation needed)

```powershell
.\Export-LockoutEvents.ps1 -SelfTest
```

Expected output:

```text
PASS: both event IDs, field names, empty/missing values, timestamps and JSON round-trip.
```

### 2. Export all retained lockout and failed-logon events

The default, and the usual first step. Captures everything the Security log still holds.

```powershell
.\Export-LockoutEvents.ps1
```

### 3. Export only recent events

Useful on a busy PC where the full history is large, or when you know roughly when the lockout started.

```powershell
.\Export-LockoutEvents.ps1 -Days 7
```

### 4. Export to a chosen folder

For example, to a USB drive or a case folder. The folder must not exist yet.

```powershell
.\Export-LockoutEvents.ps1 -OutputDirectory D:\Cases\PC01-lockout-2026-09-29
```

### 5. Combine options

```powershell
.\Export-LockoutEvents.ps1 -Days 30 -OutputDirectory D:\Cases\PC01-30days
```

When the export finishes, the console prints the status, the record count and the output folder:

```text
Completed - 57 records. Files: C:\...\Audit\LockoutReview-3f2a...
```

---

## Output

Each run creates one new folder containing two files.

### `events.jsonl`

One JSON object per line, one line per event, oldest first. UTF-8 without BOM.

```json
{"TimeCreatedUtc":"2026-09-29T09:00:00.0000000+00:00","EventId":4625,"RecordId":184233,"Computer":"PC01","Provider":"Microsoft-Windows-Security-Auditing","EventData":{"TargetUserName":"bob","Status":"0xc000006d","SubStatus":"0xc000006a","LogonType":"3","IpAddress":"10.0.0.5","...":"..."}}
```

| Field | Content |
|---|---|
| `TimeCreatedUtc` | Event time, ISO 8601, UTC. |
| `EventId` | `4625` or `4740`. |
| `RecordId` | Security log record number. Use it to find the same event in Event Viewer. |
| `Computer` | Computer that logged the event. |
| `Provider` | Always `Microsoft-Windows-Security-Auditing`. |
| `EventData` | Every named field of the event, exactly as Windows recorded it. Fields are read by name, so nothing is lost or misaligned if Windows adds or reorders fields. |

### `context.txt`

A plain-text report to read alongside the events:

- computer name, collection time (UTC), local time zone, requested lookback, record count and **status**;
- the **limits** of the export (what it cannot tell you);
- a ready-made **AI review prompt** (see [Reviewing with an AI tool](#reviewing-with-an-ai-tool));
- the current local account policy (`net accounts`) — lockout threshold, duration and observation window;
- the current audit policy (`auditpol /get /category:*`);
- Security log properties (enabled, record count, maximum size, retention mode) and the time of the **oldest retained record**, which tells you how far back the evidence can possibly go.

### Status values

| Status | Meaning | Exit behaviour |
|---|---|---|
| `Completed` | Events were found and exported. | Success. |
| `No matching retained events; this does NOT establish that the PC is safe.` | The log holds no 4625/4740 events in the requested window. Auditing may be off, or the log may have rolled over. Check the audit policy and oldest-record time in `context.txt`. | Success. |
| `FAILED or PARTIAL export: <message>` | Reading the log failed, possibly part-way through. `events.jsonl` may be incomplete. `context.txt` is still written. | The script rethrows the error after writing the report, so the run fails. |

---

## Reviewing the results

### With PowerShell

Load the export (run from inside the output folder):

```powershell
$events = Get-Content .\events.jsonl | ConvertFrom-Json
```

List every lockout and the machine that triggered it:

```powershell
$events | Where-Object EventId -eq 4740 |
    Select-Object TimeCreatedUtc, RecordId,
        @{ n = 'Account';        e = { $_.EventData.TargetUserName } },
        @{ n = 'CallerComputer'; e = { $_.EventData.TargetDomainName } }
```

> [!NOTE]
> In event 4740, Windows stores the **Caller Computer Name** (the machine the bad attempts came from) in the `TargetDomainName` field. An empty caller usually means the attempts were local.

Group failed logons by account, source address, logon type and reason — the top rows are usually the culprit:

```powershell
$events | Where-Object EventId -eq 4625 |
    Group-Object { $_.EventData.TargetUserName }, { $_.EventData.IpAddress },
                 { $_.EventData.LogonType }, { $_.EventData.SubStatus } -NoElement |
    Sort-Object Count -Descending
```

Show the process that submitted each failed logon (helps identify services, tasks and applications):

```powershell
$events | Where-Object EventId -eq 4625 |
    Group-Object { $_.EventData.ProcessName } -NoElement | Sort-Object Count -Descending
```

To open a specific event in Event Viewer, filter the Security log by its `RecordId`, or use:

```powershell
Get-WinEvent -LogName Security -FilterXPath "*[System[EventRecordID=184233]]" | Format-List *
```

### Useful 4625 fields

| Field | What it tells you |
|---|---|
| `TargetUserName`, `TargetDomainName` | Account the attempt was made against. |
| `Status`, `SubStatus` | Why it failed (table below). `SubStatus` is usually more specific. |
| `LogonType` | How the logon was attempted (table below). |
| `IpAddress`, `IpPort` | Network source. `-` or `127.0.0.1` / `::1` means local. |
| `WorkstationName` | Name the client reported. Not verified — can be empty or spoofed. |
| `ProcessName` | Local process that submitted the logon, e.g. `svchost.exe`, `lsass.exe`, `winlogon.exe`. |
| `AuthenticationPackageName`, `LmPackageName` | `NTLM`, `Kerberos`, `Negotiate`, and the NTLM version. |

### Common `Status` / `SubStatus` codes

| Code | Meaning |
|---|---|
| `0xC000006D` | Logon failed — bad user name or authentication information. Generic; read `SubStatus`. |
| `0xC000006A` | User name is correct, **password is wrong**. The failures that count towards lockout. |
| `0xC0000064` | User name does not exist. Often password spraying or a typo. |
| `0xC0000234` | **Account is already locked out.** Attempts made after the lockout. |
| `0xC0000072` | Account is disabled. |
| `0xC0000071` | Password has expired. |
| `0xC0000224` | User must change password at next logon. |
| `0xC0000193` | Account has expired. |
| `0xC000006F` | Logon outside allowed hours. |
| `0xC0000070` | Logon from a workstation the account is not allowed to use. |
| `0xC000015B` | The user has not been granted this logon type (user rights assignment). |
| `0xC0000133` | Clock difference between client and server is too large (Kerberos). |

### Common `LogonType` values

| Value | Type | Typical source |
|---|---|---|
| `2` | Interactive | Keyboard at the PC's sign-in screen. |
| `3` | Network | File shares, mapped drives, remote management — **and RDP when Network Level Authentication is on**, so a type 3 failure is not proof of file-share access and not proof of RDP either. |
| `4` | Batch | Scheduled task running with stored credentials. |
| `5` | Service | Windows service configured with an account and password. |
| `7` | Unlock | Unlocking a locked session. |
| `8` | NetworkCleartext | Basic authentication, e.g. IIS. |
| `9` | NewCredentials | `runas /netonly`. |
| `10` | RemoteInteractive | RDP without NLA, or after NLA succeeds. |
| `11` | CachedInteractive | Sign-in with cached domain credentials while offline. |

### Typical patterns

| Pattern | Likely cause |
|---|---|
| Regular failures at fixed intervals, same `ProcessName`, `LogonType` 4 or 5 | A scheduled task or service still using an old password. |
| Failures from one internal IP, `LogonType` 3, `SubStatus` `0xC000006A` | A mapped drive, saved credential or another device (phone, laptop) with the old password. |
| Many different `TargetUserName` values from one external IP, `SubStatus` `0xC0000064` | Password spraying or guessing against an exposed service such as RDP. |
| A burst of `0xC000006A` failures followed by a 4740, then `0xC0000234` | The lockout itself, then continued attempts against the locked account. The source of the first failures is the one to fix. |

### Reviewing with an AI tool

`context.txt` contains an **AI REVIEW PROMPT** section written for this export. Give the AI both files (`events.jsonl` and `context.txt`) and that prompt. It asks for a timeline grouped by account and source, with event IDs, record IDs and UTC timestamps cited for each finding, and tells the AI to treat event contents as untrusted data, to separate evidence from hypothesis, and not to declare the PC clean or compromised without supporting evidence.

Remove or redact anything you are not permitted to share before uploading.

---

## Limits

The export is evidence, not a verdict. Its own `context.txt` repeats these points.

- **Only this PC's retained Security log is read.** Events that have rolled over, been cleared or been deleted cannot be recovered by the script. The oldest-record time in `context.txt` shows how far back coverage goes.
- **Past auditing is unknown.** The audit policy in `context.txt` is the *current* policy. It does not prove auditing was enabled when the lockout happened.
- **Domain accounts:** 4740 and many 4625 events for domain accounts are logged on the domain controller (the PDC emulator records every lockout). Collect those logs as well.
- **No successful logons.** Event 4624 is not collected, so the export alone cannot show whether an attacker ever got in.
- **No changes are made.** The script does not clear or move logs, change settings, unlock accounts, reset passwords or upload anything.
- `-Days 0` means *all retained history*, not all historical activity.

---

## Related

- [`Recovery/`](../Recovery/) — regain access to a locked or disabled local account. Run this export afterwards to find out why it locked.
- [`Hardening/`](../Hardening/) — enables the audit subcategories this script depends on, and sets a 5-attempt / 15-minute lockout policy.

References:

- Microsoft Learn, **4625(F): An account failed to log on**
  https://learn.microsoft.com/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4625
- Microsoft Learn, **4740(S): A user account was locked out**
  https://learn.microsoft.com/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4740
