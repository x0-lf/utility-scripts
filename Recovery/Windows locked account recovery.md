# Windows 10 / 11 - Locked or Disabled Account Recovery

**Procedure:** Reset a local account password and re-enable a disabled account via the Windows Recovery Environment (WinRE), using the Utility Manager (`Utilman.exe`) substitution method.

**Applies to:** Windows 10 and Windows 11 local accounts.

---

## ⚠️ Before You Begin : Read This First

> **Perform this procedure only on a machine you own or are explicitly authorized to service.** Bypassing authentication on a system you do not control may be unlawful.

### Critical warning: DPAPI data loss

Resetting a password with `net user` is an **administrative reset**, not a user-initiated password change. Because Windows performs the reset *without* the account's original password, it **cannot re-encrypt the user's DPAPI (Data Protection API) master key.**

As a result, the following data protected by DPAPI will become **permanently inaccessible** for that account:

- Saved passwords in browsers that use the Windows credential store (Chrome, Edge, etc.)
- Entries in **Windows Credential Manager**
- Stored **Wi-Fi profile keys**
- **EFS-encrypted** files and folders
- Any application secret tied to the user's DPAPI key

**If you know the current password**, change it from *within* a logged-in Windows session instead - that path preserves DPAPI. Use the procedure below **only** when the password is genuinely lost and this data loss is acceptable.

> **Microsoft accounts:** This method reliably resets *local* accounts only. If the account is a Microsoft account, reset it online at <https://account.microsoft.com/password> instead.

### BitLocker

If the system drive is protected by **BitLocker**, you will be prompted for the **48-digit recovery key** to unlock it inside WinRE. Have that key available before starting, or you will not be able to proceed.

---

## Symptom

At sign-in, Windows displays:

> *"The referenced account is currently locked out and may not be logged on to."*

This indicates the account is locked or disabled. The steps below reset its password and reactivate it.

---

## Part 1 - Enter the Recovery Environment

1. At the Windows sign-in screen, click the **power** icon.
2. **Hold `Shift`**, then click **Restart**. Keep holding `Shift` until the recovery menu appears.
3. Navigate to: **Troubleshoot → Advanced options → Command Prompt.**

---

## Part 2 - Identify the System Drive

Drive letters inside WinRE frequently differ from those in normal Windows (the OS partition is often `D:` here, not `C:`). Confirm before continuing.

Run:

```cmd
bcdedit | find "partition"
```

Look at the `osdevice` line - it names the Windows partition, e.g. `\Device\HarddiskVolumeX`. To be certain, verify which drive letter actually contains Windows:

```cmd
dir C:\Windows
dir D:\Windows
```

The drive that lists the Windows folder is your system drive. **In the commands below, substitute that letter** wherever `C:` appears.

Switch to the system drive and open `System32`:

```cmd
C:
cd \Windows\System32
```

You should now be at `C:\Windows\System32`.

---

## Part 3 - Substitute the Utility Manager

Back up the original `Utilman.exe`, then replace it with the command prompt. This makes the sign-in screen's **Ease of Access** button launch a `SYSTEM`-level command prompt.

```cmd
copy Utilman.exe Utilman.exe.bak
copy cmd.exe Utilman.exe /y
```

Close the command prompt window, then choose **Continue** to exit WinRE and restart into Windows.

> **Remember:** `Utilman.exe` is now `cmd.exe`. This is a temporary, deliberate change - **Part 5 restores it.**

---

## Part 4 - Reset the Password and Re-Enable the Account

1. At the sign-in screen, click the **Ease of Access** button (accessibility icon, lower-right). A command prompt opens with `SYSTEM` privileges.
2. List all local accounts to confirm the exact username:

   ```cmd
   net user
   ```

3. Set a new password (replace `<username>` and `<newpassword>` with your values):

   ```cmd
   net user <username> <newpassword>
   ```

4. Re-enable the account if it is disabled:

   ```cmd
   net user <username> /active:yes
   ```

5. Close the command prompt and sign in with the new password.

> Choose a strong temporary password and change it again from within Windows once you have access.

---

## Part 5 - Restore `Utilman.exe` (Required)

**Do not skip this step.** Until it is done, the sign-in screen's Ease of Access button remains a `SYSTEM`-level command prompt available to *anyone* with physical access - a serious, standing security hole.

Because files in `System32` are owned by **TrustedInstaller**, restoring cleanly from the recovery environment is the reliable method:

1. Reboot into WinRE again: sign-in screen → **power** icon → hold `Shift` → **Restart**.
2. Go to **Troubleshoot → Advanced options → Command Prompt.**
3. Switch to the system drive and open `System32` (verify the drive letter as in Part 2):

   ```cmd
   C:
   cd \Windows\System32
   ```

4. Restore the original file from your backup:

   ```cmd
   copy /y Utilman.exe.bak Utilman.exe
   ```

5. (Optional) Remove the backup:

   ```cmd
   del Utilman.exe.bak
   ```

6. Close the command prompt and choose **Continue** to restart into Windows.

### Verify the restoration

Back at the sign-in screen, click the **Ease of Access** button. It should now open the normal accessibility menu - **not** a command prompt. If a command prompt still appears, repeat Part 5.

---

## Post-Recovery Checklist

- [ ] Account signs in with the new password
- [ ] `Utilman.exe` restored and verified (accessibility button behaves normally)
- [ ] Backup file `Utilman.exe.bak` removed
- [ ] Password changed again from within Windows (recommended)
- [ ] Awareness that DPAPI-protected secrets (saved passwords, Wi-Fi keys, Credential Manager, EFS files) for the reset account are lost and may need to be re-entered

---

## Command Reference

| Purpose | Command |
| --- | --- |
| Show OS partition | `bcdedit \| find "partition"` |
| Verify system drive | `dir C:\Windows` |
| Back up Utility Manager | `copy Utilman.exe Utilman.exe.bak` |
| Substitute with cmd | `copy cmd.exe Utilman.exe /y` |
| List local accounts | `net user` |
| Reset password | `net user <username> <newpassword>` |
| Re-enable account | `net user <username> /active:yes` |
| Restore Utility Manager | `copy /y Utilman.exe.bak Utilman.exe` |
| Delete backup | `del Utilman.exe.bak` |