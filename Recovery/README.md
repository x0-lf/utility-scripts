# Recovery

Manual procedures for regaining access to a Windows machine. This folder contains documentation only — there are no scripts to run.

| File | What it covers |
|---|---|
| [`Windows locked account recovery.md`](Windows%20locked%20account%20recovery.md) | Reset the password of a locked or disabled Windows 10/11 **local** account and re-enable it from the Windows Recovery Environment (WinRE), using the Utility Manager (`Utilman.exe`) substitution method. |

## Windows locked account recovery

Use it when sign-in shows *"The referenced account is currently locked out and may not be logged on to"*, the password is lost, and no other administrator account is available.

The procedure walks through:

1. booting into WinRE and opening a Command Prompt;
2. finding the real system drive letter (often not `C:` inside WinRE);
3. backing up `Utilman.exe` and temporarily replacing it with `cmd.exe`;
4. resetting the password and re-enabling the account with `net user` from the sign-in screen;
5. restoring the original `Utilman.exe` and verifying the restore.

> [!CAUTION]
> - Use it only on a machine you own or are authorised to service.
> - An administrative password reset makes the account's **DPAPI-protected data permanently unreadable**: saved browser passwords, Credential Manager entries, Wi-Fi keys and EFS-encrypted files.
> - If the system drive is protected by **BitLocker**, you need the 48-digit recovery key.
> - Until `Utilman.exe` is restored (Part 5), anyone at the sign-in screen can open a `SYSTEM` command prompt. Do not skip the restore.

Microsoft accounts are not covered — reset those at <https://account.microsoft.com/password>.

## After recovery

Recovering the account does not explain *why* it locked. Once signed in, run [`Audit/Export-LockoutEvents.ps1`](../Audit/) to export the failed logon (4625) and lockout (4740) events and find the source — a stale saved password, a scheduled task or service, another device, or password guessing. Otherwise the account may simply lock again.
