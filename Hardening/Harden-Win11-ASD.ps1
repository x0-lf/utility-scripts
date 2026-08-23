<#
.SYNOPSIS
    Applies the ASD/ACSC "Hardening Microsoft Windows 11 Workstations" guidance
    (January 2026) to a standalone, non-domain Windows 11 workstation, with
    deliberate carve-outs for a developer machine.

.DESCRIPTION
    Run once on a freshly installed Windows 11 machine, from an elevated PowerShell
    session, signed in as the account you will actually use day to day.

    Deviations from the ASD guide are deliberate and are printed in the final summary.
    Four come from the operator's stated requirements:

      1. Script execution stays allowed. "Prevent access to the command prompt",
         "Prevent access to registry editing tools" and the PowerShell
         "Allow only signed scripts" execution policy are NOT applied. PowerShell
         module logging, script block logging and transcription ARE applied - that
         is the half that provides visibility without blocking work.
      2. Removable media stays usable. "All Removable Storage classes: Deny all
         access", the per-class deny-write rules, and the BitLocker
         "deny write access to unprotected removable drives" rule are NOT applied.
      3. Microsoft services stay usable. The policies that block Microsoft accounts,
         the Microsoft Store, MSIX/non-admin package install and OneDrive are NOT
         applied, because Visual Studio and Store-delivered tooling depend on them.
      4. Remote Desktop is DISABLED outright rather than "securely configured".
         Remote Assistance, WinRM and Windows Remote Shell are disabled too.
      5. No Microsoft Defender Antivirus policy is written - Malwarebytes Premium is
         the real-time engine. That necessarily drops Attack Surface Reduction and
         Controlled Folder Access, which only work with Defender as primary scanner.
      6. No BitLocker policy is written - drive encryption is not in use.

    The remaining deviations are settings that would lock the operator out of their
    own machine, or that only make sense on a domain. Every one is listed at the end.

.PARAMETER Skip
    Section names to skip. Run with -DryRun to see the full section list.

.PARAMETER Enable
    Opt-in sections, OFF by default because they routinely break developer tooling:
    FIPS, StrongKeyProtection.

.PARAMETER DryRun
    Print every change without making it.

.PARAMETER Verify
    Make no changes. Re-read every value and report drift. Useful after a reboot.

.EXAMPLE
    .\Harden-Win11-ASD.ps1 -DryRun

.EXAMPLE
    .\Harden-Win11-ASD.ps1

.EXAMPLE
    .\Harden-Win11-ASD.ps1 -Skip Power,RunLists

.EXAMPLE
    .\Harden-Win11-ASD.ps1 -Verify
#>

[CmdletBinding()]
param(
    [string[]]$Skip = @(),
    [string[]]$Enable = @(),
    [switch]$DryRun,
    [switch]$Verify,
    [string]$NtpServer = 'time.windows.com',
    [string]$TranscriptDir = 'C:\ProgramData\PSTranscripts',
    [string]$LogPath = 'C:\Harden-Win11-ASD.log',
    [switch]$NoRestorePoint
)

$ErrorActionPreference = 'Stop'

# Sections that stay OFF unless named in -Enable.
$OptInSections = @('FIPS', 'StrongKeyProtection')

$script:Changed  = 0
$script:Same     = 0
$script:Failed   = 0
$script:Drift    = New-Object System.Collections.Generic.List[string]
$script:Notes    = New-Object System.Collections.Generic.List[string]
$script:Sections = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------- helpers --

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'SET'   { Write-Host $line -ForegroundColor Green }
        'WOULD' { Write-Host $line -ForegroundColor Cyan }
        'SKIP'  { Write-Host $line -ForegroundColor DarkGray }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'FAIL'  { Write-Host $line -ForegroundColor Red }
        'HEAD'  { Write-Host ''; Write-Host $line -ForegroundColor Black -BackgroundColor Gray }
        'DRIFT' { Write-Host $line -ForegroundColor Magenta }
        default { Write-Host $line }
    }
    try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 } catch { }
}

function Test-ValueMatch {
    param($Current, $Desired)
    if ($null -eq $Current) { return $false }
    if (($Desired -is [array]) -or ($Current -is [array])) {
        return (@($Current) -join '|') -eq (@($Desired) -join '|')
    }
    return "$Current" -eq "$Desired"
}

# The single abstraction: set one policy value, honouring -DryRun / -Verify.
function Set-Pol {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString')]
        [string]$Type = 'DWord'
    )
    $current = $null
    try { $current = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { }
    $isMatch = Test-ValueMatch -Current $current -Desired $Value

    if ($Verify) {
        if (-not $isMatch) {
            $shown = if ($null -eq $current) { '<missing>' } else { (@($current) -join ',') }
            $script:Drift.Add("$Path\$Name is $shown, expected $(@($Value) -join ',')")
        }
        return
    }
    if ($isMatch) { $script:Same++; return }
    if ($DryRun) { Write-Log "$Path\$Name = $(@($Value) -join ',')" 'WOULD'; return }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        $script:Changed++
        Write-Log "$Path\$Name = $(@($Value) -join ',')" 'SET'
    } catch {
        $script:Failed++
        Write-Log "$Path\$Name -> $($_.Exception.Message)" 'FAIL'
    }
}

# Run an action, honouring -DryRun / -Verify.
function Invoke-Step {
    param([string]$Description, [scriptblock]$Action)
    if ($Verify) { return }
    if ($DryRun) { Write-Log $Description 'WOULD'; return }
    try {
        & $Action | Out-Null
        $script:Changed++
        Write-Log $Description 'SET'
    } catch {
        $script:Failed++
        Write-Log "$Description -> $($_.Exception.Message)" 'FAIL'
    }
}

function Section {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Body)
    $script:Sections.Add($Name)
    if ($Skip -contains $Name) { Write-Log "section '$Name' skipped by -Skip" 'SKIP'; return }
    if (($OptInSections -contains $Name) -and ($Enable -notcontains $Name)) {
        Write-Log "section '$Name' not applied (opt-in: add -Enable $Name)" 'SKIP'
        return
    }
    Write-Log "SECTION $Name" 'HEAD'
    try { & $Body } catch { $script:Failed++; Write-Log "section '$Name' -> $($_.Exception.Message)" 'FAIL' }
}

function Note { param([string]$Text) $script:Notes.Add($Text) }

# Well-known SIDs, used so the script works on any Windows display language.
$SID = @{
    Administrators       = '*S-1-5-32-544'
    Users                = '*S-1-5-32-545'
    RemoteDesktopUsers   = '*S-1-5-32-555'
    LocalService         = '*S-1-5-19'
    NetworkService       = '*S-1-5-20'
    Service              = '*S-1-5-6'
    LocalAccount         = '*S-1-5-113'
}

# -------------------------------------------------------------- preflight --

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session (Run as administrator).'
}

$mode = if ($Verify) { 'VERIFY (read-only)' } elseif ($DryRun) { 'DRY RUN (no changes)' } else { 'APPLY' }
Write-Log "Harden-Win11-ASD starting. Mode: $mode"
Write-Log ("OS: {0}  Build: {1}" -f (Get-CimInstance Win32_OperatingSystem).Caption, [Environment]::OSVersion.Version)
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Log 'This is a 32-bit OS. ASD requires x64 - reinstall as x64.' 'WARN'
}

# ---------------------------------------------------------------- backups --

Section 'Backup' {
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $folder = "C:\HardeningBackup-$stamp"
    Invoke-Step "create backup folder $folder" { New-Item -ItemType Directory -Path $folder -Force }
    Invoke-Step 'export current local security policy' {
        secedit /export /cfg "$folder\secpol-before.inf" /quiet
    }
    Invoke-Step 'export current audit policy' {
        auditpol /backup /file:"$folder\auditpol-before.csv"
    }
    Invoke-Step 'export current registry policy hives' {
        reg export 'HKLM\SOFTWARE\Policies' "$folder\HKLM-Policies.reg" /y
        reg export 'HKCU\Software\Policies' "$folder\HKCU-Policies.reg" /y
    }
    if (-not $NoRestorePoint) {
        Invoke-Step 'create a system restore point' {
            Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description 'Before ASD hardening' -RestorePointType 'MODIFY_SETTINGS'
        }
    }
    Note "Backups written to $folder (secpol-before.inf, auditpol-before.csv, *.reg)."
}

# -------------------------------------------------------- Antivirus (none) --
# ASD pages 3-4 (Attack Surface Reduction), 6 (Controlled Folder Access) and
# 16-18 (Microsoft Defender Antivirus) are NOT implemented: this machine uses
# Malwarebytes Premium as its real-time engine. ASR and Controlled Folder Access
# only function when Microsoft Defender Antivirus is the primary real-time
# scanner, so configuring them here would write policy that never takes effect.
# ASD's own wording covers this - "use third-party antivirus solutions that
# offer similar functionality to those provided by ASR" (page 4).

Section 'AntivirusCheck' {
    $av = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
    if ($av.Count -eq 0) {
        Write-Log 'No antivirus product is registered with Windows Security Center.' 'WARN'
    } else {
        foreach ($p in $av) {
            # productState bit 0x1000 in the second byte means real-time protection is on.
            $rt = ([int]$p.productState -band 0x1000) -ne 0
            Write-Log ("Registered AV: {0}  real-time={1}" -f $p.displayName, $rt)
        }
    }
    if (($av.displayName -join ' ') -notmatch 'Malwarebytes') {
        Write-Log 'Malwarebytes is not registered yet. Install it before relying on this machine.' 'WARN'
    }
    Note ('No Microsoft Defender Antivirus policy is written, per your requirement. That ' +
          'also removes Attack Surface Reduction and Controlled Folder Access, which only ' +
          'work when Defender is the primary real-time engine. Turn on the Malwarebytes ' +
          'equivalents yourself: Exploit Protection, Ransomware Protection, Web Protection, ' +
          'and scanning of archives and removable drives.')
}

# ------------------------------------------------------- Exploit protection --
# ASD page 9. System-wide mitigations. Mandatory ASLR (ForceRelocateImages) is
# left off - it breaks a large amount of software and ASD itself recommends a
# staged, tested rollout for application-specific mitigations.

Section 'ExploitProtection' {
    Invoke-Step 'enable system-wide DEP, bottom-up ASLR, high-entropy ASLR, SEHOP, CFG' {
        Set-ProcessMitigation -System -Enable DEP, EmulateAtlThunks, BottomUp, HighEntropy, SEHOP, CFG
    }
    # Force SEHOP on regardless of the per-image opt-out (MS Security Guide).
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DisableExceptionChainValidation' 0
    # Do not let users weaken this from the Windows Security app.
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\App and Browser protection' 'DisallowExploitProtectionOverride' 1
    # DEP must stay on for File Explorer.
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'NoDataExecutionPrevention' 0
    Set-Pol 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoHeapTerminationOnCorruption' 0
    Set-Pol 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'PreXPSP2ShellProtocolBehavior' 0
    Note 'Mandatory (force-relocate) ASLR is intentionally NOT enabled - it breaks many applications. Enable per-application after testing.'
}

# ------------------------------------------------------ Credential protection --
# ASD pages 5-6.

Section 'CredentialProtection' {
    Set-Pol 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'CachedLogonsCount' '1' 'String'
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'DisableDomainCreds' 1
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential' 0
    # LSA as a protected process. 2 = enabled WITHOUT UEFI lock, so it can be turned
    # off again from Windows. ASD specifies the UEFI-locked variant (1); on a machine
    # you own alone, the locked variant can only be cleared with physical presence.
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL' 2
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCustomSSPsAPs' 0
    Note 'LSA protected process is enabled WITHOUT the UEFI lock (RunAsPPL=2). ASD specifies the locked variant (1); set it to 1 if you want that and accept that clearing it needs physical presence at boot.'
}

# ------------------------------------------- Virtualization Based Security --
# ASD page 6. HVCI can block unsigned or old drivers and some third-party
# hypervisors - if a driver stops loading after reboot, this is the cause.

Section 'VBS' {
    $dg = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
    Set-Pol $dg 'EnableVirtualizationBasedSecurity' 1
    Set-Pol $dg 'RequirePlatformSecurityFeatures' 3          # Secure Boot and DMA protection
    Set-Pol $dg 'HypervisorEnforcedCodeIntegrity' 1          # 1 = enabled, unlocked
    Set-Pol $dg 'HVCIMATRequired' 1                          # require UEFI Memory Attributes Table
    Set-Pol $dg 'LsaCfgFlags' 2                              # Credential Guard, no UEFI lock
    Set-Pol $dg 'ConfigureSystemGuardLaunch' 1               # Secure Launch
    Set-Pol $dg 'ConfigureKernelShadowStacksLaunch' 1        # kernel-mode HW stack protection
    Note 'Virtualization Based Security, HVCI, Credential Guard and Secure Launch are enabled WITHOUT UEFI lock, so you can turn them back off if a driver or hypervisor breaks. ASD specifies UEFI lock (LsaCfgFlags=1, HVCI Locked). Requires a reboot and compatible hardware.'
}

# -------------------------------------------------------- Elevating privileges --
# ASD pages 8-9.

Section 'UAC' {
    $sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-Pol $sys 'FilterAdministratorToken' 1        # Admin Approval Mode for built-in Administrator
    Set-Pol $sys 'ConsentPromptBehaviorAdmin' 1      # prompt for credentials on the secure desktop
    Set-Pol $sys 'ConsentPromptBehaviorUser' 0       # standard users: automatically deny
    Set-Pol $sys 'EnableInstallerDetection' 1
    Set-Pol $sys 'EnableSecureUIAPaths' 1
    Set-Pol $sys 'EnableLUA' 1
    Set-Pol $sys 'EnableVirtualization' 1
    Set-Pol $sys 'PromptOnSecureDesktop' 1
    Set-Pol $sys 'LocalAccountTokenFilterPolicy' 0   # UAC restrictions on network logons
    Note 'UAC now asks for your PASSWORD on the secure desktop for every elevation, not just Yes/No. That is the ASD setting. To go back to consent-only, set ConsentPromptBehaviorAdmin to 2 under HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System.'
}

# ------------------------------------------- Credential entry and logon UI --
# ASD page 7, plus Early Launch Antimalware (page 8) and Safe Mode (page 41).

Section 'Logon' {
    $polSys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-Pol $polSys 'DontDisplayNetworkSelectionUI' 1
    Set-Pol $polSys 'EnumerateLocalUsers' 0
    Set-Pol $polSys 'DisableLockScreenAppNotifications' 1

    $credui = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredUI'
    Set-Pol $credui 'DisablePasswordReveal' 1
    Set-Pol $credui 'EnumerateAdministrators' 0
    Set-Pol $credui 'EnableSecureCredentialPrompting' 1      # require trusted path

    $sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-Pol $sys 'SoftwareSASGeneration' 0                   # no software-generated SAS
    Set-Pol $sys 'EnableMPR' 0                               # no MPR notifications
    Set-Pol $sys 'DisableAutomaticRestartSignOn' 1           # do not auto sign-in after restart
    Set-Pol $sys 'DisableCAD' 0                              # require CTRL+ALT+DEL
    Set-Pol $sys 'SafeModeBlockNonAdmins' 1                  # ASD page 41

    # Early Launch Antimalware: good, unknown and bad-but-critical drivers only.
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Policies\EarlyLaunch' 'DriverLoadPolicy' 3

    # Legacy and run-once lists (ASD page 31).
    Set-Pol 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'DisableLocalMachineRunOnce' 1
}

# Split out because it is the single most likely setting to surprise you.
Section 'RunLists' {
    Set-Pol 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'DisableLocalMachineRun' 1
    Note 'The legacy HKLM Run list is now ignored (DisableLocalMachineRun=1), per ASD. Some third-party updaters and tray applications start from there and will stop launching. Re-run with -Skip RunLists, or delete that value, if something you need no longer starts.'
}

# ----------------------------------------------------------- Audit policy --
# ASD pages 19-21. Subcategory GUIDs are used so this works on any UI language.

Section 'Audit' {
    Set-Pol 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' 'ProcessCreationIncludeCmdLine_Enabled' 1
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'SCENoApplyLegacyAuditPolicy' 1

    $audit = @(
        @{ Name = 'Computer Account Management';    Guid = '{0CCE9236-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Other Account Management Events';Guid = '{0CCE923A-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Security Group Management';      Guid = '{0CCE9237-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'User Account Management';        Guid = '{0CCE9235-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Process Creation';               Guid = '{0CCE922B-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'disable' }
        @{ Name = 'Process Termination';            Guid = '{0CCE922C-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'disable' }
        @{ Name = 'Account Lockout';                Guid = '{0CCE9217-69AE-11D9-BED3-505054503030}'; S = 'disable'; F = 'enable' }
        @{ Name = 'Group Membership';               Guid = '{0CCE9249-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'disable' }
        @{ Name = 'Logoff';                         Guid = '{0CCE9216-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'disable' }
        @{ Name = 'Logon';                          Guid = '{0CCE9215-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Other Logon/Logoff Events';      Guid = '{0CCE921C-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Special Logon';                  Guid = '{0CCE921B-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'File Share';                     Guid = '{0CCE9224-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'File System';                    Guid = '{0CCE921D-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Kernel Object';                  Guid = '{0CCE921F-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Other Object Access Events';     Guid = '{0CCE9227-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Registry';                       Guid = '{0CCE921E-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Audit Policy Change';            Guid = '{0CCE922F-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'Other Policy Change Events';     Guid = '{0CCE9234-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
        @{ Name = 'System Integrity';               Guid = '{0CCE9212-69AE-11D9-BED3-505054503030}'; S = 'enable'; F = 'enable' }
    )
    foreach ($a in $audit) {
        # Invoke-Step runs the block immediately, so $a is the current item - no closure needed.
        Invoke-Step "auditpol: $($a.Name) success=$($a.S) failure=$($a.F)" {
            $out = auditpol /set /subcategory:"$($a.Guid)" /success:$($a.S) /failure:$($a.F) 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($out | Out-String).Trim() }
        }
    }

    # Event log sizes (ASD page 19).
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\Application' 'MaxSize' 65536
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\Security'    'MaxSize' 2097152
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\System'      'MaxSize' 65536

    # NTP client so timestamps across logs line up. Left alone on a domain-joined
    # machine, where the domain hierarchy is the correct time source.
    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        Write-Log 'domain-joined: leaving W32Time on the domain hierarchy' 'SKIP'
    } else {
        $w32 = 'HKLM:\SOFTWARE\Policies\Microsoft\W32Time\Parameters'
        Set-Pol $w32 'NtpServer' "$NtpServer,0x9" 'String'
        Set-Pol $w32 'Type' 'NTP' 'String'
        Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\W32Time\TimeProviders\NtpClient' 'Enabled' 1
    }
}

# ------------------------------------------------------- Autoplay / AutoRun --
# ASD page 21. Note this does NOT stop you reading or writing removable media.

Section 'Autoplay' {
    $exp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    Set-Pol $exp 'NoAutoplayfornonVolume' 1
    Set-Pol $exp 'NoAutorun' 1
    Set-Pol $exp 'NoDriveTypeAutoRun' 255            # turn off Autoplay on all drives
}

# --------------------------------------------------------- Attachment Manager --
# ASD page 18. Per-user policy - applies to the account running this script.

Section 'AttachmentManager' {
    $att = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments'
    Set-Pol $att 'SaveZoneInformation' 2             # always preserve zone info
    Set-Pol $att 'HideZoneInfoOnProperties' 1        # hide the Unblock button
    Note 'Attachment Manager and screen saver settings are per-user (HKCU) and apply to the account that ran this script. Re-run as any other account you create.'
}

# ------------------------------------------------------------- Networking --
# ASD pages 15, 22, 32-34, 42-43.

Section 'Network' {
    # Anonymous connections.
    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    Set-Pol $lsa 'RestrictAnonymous' 1
    Set-Pol $lsa 'RestrictAnonymousSAM' 1
    Set-Pol $lsa 'EveryoneIncludesAnonymous' 0
    Set-Pol $lsa 'restrictremotesam' 'O:BAG:BAD:(A;;RC;;;BA)' 'String'
    Set-Pol $lsa 'LimitBlankPasswordUse' 1
    Set-Pol "$lsa\MSV1_0" 'allownullsessionfallback' 0
    Set-Pol "$lsa\pku2u" 'AllowOnlineID' 0
    Set-Pol "$lsa\LDAP" 'LDAPClientIntegrity' 1
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'RestrictNullSessAccess' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation' 'AllowInsecureGuestAuth' 0

    # Network authentication: NTLMv2 only, 128-bit, AES Kerberos.
    Set-Pol $lsa 'LmCompatibilityLevel' 5
    Set-Pol $lsa 'NoLMHash' 1
    Set-Pol "$lsa\MSV1_0" 'NTLMMinClientSec' 537395200      # 0x20080000
    Set-Pol "$lsa\MSV1_0" 'NTLMMinServerSec' 537395200
    Set-Pol 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters' 'SupportedEncryptionTypes' 24
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NTLM' 'NTLMEnhancedLogging' 1
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' 'AuditNTLMInDomain' 7

    # Secure channel (harmless on a standalone machine, correct if you ever join a domain).
    $nl = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    Set-Pol $nl 'RequireSignOrSeal' 1
    Set-Pol $nl 'SealSecureChannel' 1
    Set-Pol $nl 'SignSecureChannel' 1
    Set-Pol $nl 'RequireStrongKey' 1
    Set-Pol $nl 'DisablePasswordChange' 0
    Set-Pol $nl 'MaximumPasswordAge' 30

    # MSS settings (ASD pages 32-33).
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'  'DisableIPSourceRouting' 2
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' 'DisableIPSourceRouting' 2
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'  'EnableICMPRedirect' 0

    # Multicast name resolution (LLMNR) off.
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0

    # Bridging networks and simultaneous connections (ASD page 22).
    $nc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections'
    Set-Pol $nc 'NC_AllowNetBridge_NLA' 0
    Set-Pol $nc 'NC_ShowSharedAccessUI' 0
    $wcm = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy'
    Set-Pol $wcm 'fMinimizeConnections' 3                    # prevent Wi-Fi while on Ethernet
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\wifinetworkmanager\config' 'AutoConnectAllowedOEM' 0

    # Hardened UNC paths (ASD page 30).
    $unc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkProvider\HardenedPaths'
    Set-Pol $unc '\\*\SYSVOL'   'RequireMutualAuthentication=1, RequireIntegrity=1' 'String'
    Set-Pol $unc '\\*\NETLOGON' 'RequireMutualAuthentication=1, RequireIntegrity=1' 'String'

    # Restrict unauthenticated RPC clients (ASD page 40).
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\RPC' 'RestrictRemoteClients' 1

    # Web Proxy Auto Discovery (ASD page 48).
    Invoke-Step 'add "255.255.255.255 wpad" to the hosts file' {
        $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
        if (-not (Select-String -LiteralPath $hosts -Pattern '^\s*255\.255\.255\.255\s+wpad\s*$' -Quiet)) {
            Add-Content -LiteralPath $hosts -Value "`r`n255.255.255.255 wpad" -Encoding ASCII
        }
    }

    # NetBIOS over TCP/IP off on every interface (ASD page 33).
    Invoke-Step 'disable NetBIOS over TCP/IP on all interfaces' {
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' |
            ForEach-Object { New-ItemProperty -LiteralPath $_.PSPath -Name 'NetbiosOptions' -Value 2 -PropertyType DWord -Force | Out-Null }
    }
}

# ------------------------------------------------------------------- SMB --
# ASD page 43.

Section 'SMB' {
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' 'RequireSecuritySignature' 1
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' 'EnablePlainTextPassword' 0
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'RequireSecuritySignature' 1
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1' 0
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10' 'Start' 4          # SMBv1 client driver disabled
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanServer' 'AuditClientDoesNotSupportEncryption' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanServer' 'AuditClientDoesNotSupportSigning' 1
    Invoke-Step 'remove the SMB1Protocol Windows feature' {
        $f = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
        if ($f.State -eq 'Enabled') { Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop }
    }

    # Do not let users share folders out of their own profile (ASD page 29).
    Set-Pol 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoInplaceSharing' 1
}

# -------------------------------------------------------------- Firewall --
# ASD page 45.

Section 'Firewall' {
    Invoke-Step 'enable Windows Firewall on all profiles, default-block inbound' {
        Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True `
            -DefaultInboundAction Block -DefaultOutboundAction Allow `
            -NotifyOnListen True -LogBlocked True -LogMaxSizeKilobytes 16384
    }
}

# ------------------------------------- Remote Desktop / Assistance / WinRM --
# Operator requirement: remote access is not used, so it is turned off outright.

Section 'RDP' {
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1
    $ts = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    Set-Pol $ts 'fDenyTSConnections' 1
    Set-Pol $ts 'fAllowToGetHelp' 0                # solicited Remote Assistance off
    Set-Pol $ts 'fAllowUnsolicited' 0              # offer Remote Assistance off
    # Belt and braces on the settings that matter if RDP is ever turned back on.
    Set-Pol $ts 'DisablePasswordSaving' 1
    Set-Pol $ts 'fPromptForPassword' 1
    Set-Pol $ts 'fEncryptRPCTraffic' 1
    Set-Pol $ts 'SecurityLayer' 2                  # SSL/TLS
    Set-Pol $ts 'UserAuthentication' 1             # Network Level Authentication
    Set-Pol $ts 'MinEncryptionLevel' 3             # High
    Set-Pol $ts 'fDisableClip' 1                   # no clipboard redirection
    Set-Pol $ts 'fDisableCdm' 1                    # no drive redirection
    Set-Pol $ts 'AuthenticationLevel' 2            # do not connect if server auth fails

    $cd = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
    Set-Pol $cd 'AllowEncryptionOracle' 0          # force updated clients
    Set-Pol $cd 'AllowProtectedCreds' 1

    Invoke-Step 'disable the Remote Desktop firewall rule group' {
        Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue |
            Disable-NetFirewallRule
    }
    Invoke-Step 'disable the Remote Assistance firewall rule group' {
        Get-NetFirewallRule -Group '@FirewallAPI.dll,-33752' -ErrorAction SilentlyContinue |
            Disable-NetFirewallRule
    }
}

Section 'WinRM' {
    $c = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client'
    Set-Pol $c 'AllowBasic' 0
    Set-Pol $c 'AllowUnencryptedTraffic' 0
    Set-Pol $c 'AllowDigest' 0
    $s = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
    Set-Pol $s 'AllowBasic' 0
    Set-Pol $s 'AllowUnencryptedTraffic' 0
    Set-Pol $s 'DisableRunAs' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS' 'AllowRemoteShellAccess' 0
}

# -------------------------------------------------------- PowerShell logging --
# ASD pages 36-37, minus the signed-scripts-only execution policy.

Section 'PowerShellLogging' {
    $ps = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'
    Set-Pol "$ps\ModuleLogging" 'EnableModuleLogging' 1
    Set-Pol "$ps\ModuleLogging\ModuleNames" '*' '*' 'String'
    Set-Pol "$ps\ScriptBlockLogging" 'EnableScriptBlockLogging' 1
    Set-Pol "$ps\Transcription" 'EnableTranscripting' 1
    Set-Pol "$ps\Transcription" 'EnableInvocationHeader' 1
    Set-Pol "$ps\Transcription" 'OutputDirectory' $TranscriptDir 'String'
    Invoke-Step "create the transcript directory $TranscriptDir (Administrators + SYSTEM only)" {
        New-Item -ItemType Directory -Path $TranscriptDir -Force | Out-Null
        icacls $TranscriptDir /inheritance:r /grant 'BUILTIN\Administrators:(OI)(CI)F' 'NT AUTHORITY\SYSTEM:(OI)(CI)F' 'BUILTIN\Users:(OI)(CI)(WD,AD,WEA,WA)' | Out-Null
    }
    Note ('PowerShell script execution is NOT restricted, per your requirement. Module logging, ' +
          "script block logging and transcription ARE on, so everything that runs is recorded to $TranscriptDir.")
}

# -------------------------------------------------------------- Printers --
# ASD pages 37-38.

Section 'Printers' {
    $pnp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
    Set-Pol $pnp 'RestrictDriverInstallationToAdministrators' 1
    $pr = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers'
    Set-Pol $pr 'RedirectionguardPolicy' 1
    Set-Pol $pr 'CopyFilesPolicy' 1                  # queue-specific files: colour profiles only
    Set-Pol $pr 'DisableWebPnPDownload' 1            # no print driver download over HTTP
    Set-Pol $pr 'RpcUseNamedPipeProtocol' 0          # RPC over TCP
    Set-Pol $pr 'RpcAuthentication' 0                # outgoing: default
    Set-Pol $pr 'RpcTcpPort' 0
    Set-Pol $pr 'RpcProtocols' 5
    Set-Pol $pr 'ForceKerberosForRpc' 0
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'DriverInstallationPolicy' 1
}

# ------------------------------------------------------ Power management --
# ASD page 35. Sleep and hibernation are disabled so encryption keys are never
# left in memory or written to hiberfil.sys.

Section 'Power' {
    $pw = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51'
    Set-Pol $pw 'ACSettingIndex' 1                   # require a password on wake
    Set-Pol $pw 'DCSettingIndex' 1
    $exp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    Set-Pol $exp 'ShowSleepOption' 0
    Set-Pol $exp 'ShowHibernateOption' 0
    Invoke-Step 'disable hibernation and all sleep/standby timeouts' {
        powercfg /hibernate off
        powercfg /change standby-timeout-ac 0
        powercfg /change standby-timeout-dc 0
        powercfg /change hibernate-timeout-ac 0
        powercfg /change hibernate-timeout-dc 0
    }
    Note 'Sleep and hibernation are OFF (ASD page 35). On a laptop this costs battery and removes fast resume. Re-run with -Skip Power, or run "powercfg /hibernate on" and reset the timeouts, if you want them back.'
}

# ---------------------------------------------------------- Session locking --
# ASD pages 44-45.

Section 'SessionLock' {
    Set-Pol 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'InactivityTimeoutSecs' 900
    $per = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
    Set-Pol $per 'NoLockScreenCamera' 1
    Set-Pol $per 'NoLockScreenSlideshow' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsActivateWithVoiceAboveLock' 2
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace' 'AllowWindowsInkWorkspace' 1

    # Per-user screen saver lock.
    $desk = 'HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
    Set-Pol $desk 'ScreenSaveActive'   '1'   'String'
    Set-Pol $desk 'ScreenSaverIsSecure' '1'  'String'
    Set-Pol $desk 'ScreenSaveTimeOut'  '900' 'String'
    Set-Pol 'HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' 'NoToastApplicationNotificationOnLockScreen' 1
    Set-Pol 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1
}

# --------------------------------------------------- Telemetry and features --
# ASD pages 34, 40-42, 49-52. Microsoft account / Store / OneDrive blocks are
# deliberately absent - Visual Studio and Store tooling need them.

Section 'Privacy' {
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1

    # Location services.
    $loc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
    Set-Pol $loc 'DisableLocation' 1
    Set-Pol $loc 'DisableLocationScripting' 1
    Set-Pol $loc 'DisableWindowsLocationProvider' 1

    # Search: no web results, no indexing of encrypted files.
    $srch = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-Pol $srch 'AllowIndexingEncryptedStoresOrItems' 0
    Set-Pol $srch 'DisableWebSearch' 1
    Set-Pol $srch 'ConnectedSearchUseWeb' 0
    Set-Pol $srch 'AllowCortana' 0

    # Copilot, Widgets, Game DVR, Sound Recorder, RSS enclosures.
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsOnLockScreen' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\SoundRecorder' 'Soundrecorder' 0
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Feeds' 'DisableEnclosureDownload' 1

    # SmartScreen: warn and prevent bypass (ASD page 30).
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' 1
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'ShellSmartScreenLevel' 'Block' 'String'

    # Windows Installer (ASD page 31).
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer' 'EnableUserControl' 0
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer' 'AlwaysInstallElevated' 0
    Set-Pol 'HKCU:\Software\Policies\Microsoft\Windows\Installer' 'AlwaysInstallElevated' 0

    # Show file extensions (ASD page 51).
    Set-Pol 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0

    # Group Policy processing (ASD page 30) and system object hardening (page 43).
    $gp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Group Policy'
    foreach ($ext in '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}', '{827D319E-6EAC-11D2-A4EA-00C04F79F83A}') {
        Set-Pol "$gp\$ext" 'NoBackgroundPolicy' 0
        Set-Pol "$gp\$ext" 'NoGPOListChanges' 0
    }
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'ProtectionMode' 1
}

# --------------------------------------------------------- Windows Update --
# ASD pages 12-13. Auto download and install daily, including other MS products.

Section 'Update' {
    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    Set-Pol "$wu\AU" 'NoAutoUpdate' 0
    Set-Pol "$wu\AU" 'AUOptions' 4                   # auto download and schedule install
    Set-Pol "$wu\AU" 'ScheduledInstallDay' 0         # every day
    Set-Pol "$wu\AU" 'ScheduledInstallTime' 3        # 03:00
    Set-Pol "$wu\AU" 'AllowMUUpdateService' 1        # other Microsoft products
    Set-Pol $wu 'SetDisablePauseUXAccess' 1          # remove "Pause updates"
    Set-Pol $wu 'SetDisableUXWUAccess' 0             # keep the rest of the Update UI
}

# ------------------------------------------------ Drive encryption (none) --
# ASD pages 24-28 are NOT implemented: BitLocker is not in use on this machine.
# Nothing is written under HKLM:\SOFTWARE\Policies\Microsoft\FVE.

Section 'DriveEncryptionCheck' {
    $vols = @(Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object { $_.ProtectionStatus -eq 'On' })
    Write-Log ("BitLocker-protected volumes: {0}" -f $(if ($vols.Count) { ($vols.MountPoint -join ', ') } else { 'none' }))
    Note ('No drive encryption is configured, per your requirement. Consequence, stated once: ' +
          'anyone with physical access can boot other media, read every file on this disk and ' +
          'take the SAM database offline to crack password hashes. None of the settings this ' +
          'script applies prevent that - they only apply while Windows is running. If the ' +
          'machine ever leaves a trusted location, encrypt it.')
}

# -------------------------------------------------------- Direct Memory Access --
# ASD page 24.

Section 'DMA' {
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection' 'DeviceEnumerationPolicy' 0   # Block All
    $dir = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
    Set-Pol $dir 'DenyDeviceIDs' 1
    Set-Pol $dir 'DenyDeviceIDsRetroactive' 1
    Set-Pol "$dir\DenyDeviceIDs" '1' 'PCI\CC_0C0010' 'String'   # FireWire (1394) controller
    Set-Pol "$dir\DenyDeviceIDs" '2' 'PCI\CC_0C0A'   'String'   # Thunderbolt controller
    Set-Pol $dir 'DenyDeviceClasses' 1
    Set-Pol $dir 'DenyDeviceClassesRetroactive' 1
    Set-Pol "$dir\DenyDeviceClasses" '1' '{d48179be-ec20-11d1-b6b8-00c04fa372a7}' 'String'  # SBP-2 / 1394 storage
    Note 'FireWire, Thunderbolt controllers and SBP-2 storage are now blocked at the device-install layer. A Thunderbolt dock or eGPU will stop working - re-run with -Skip DMA if you use one.'
}

# ------------------------------------------------------------------ FIPS --
# Opt-in only: FIPS mode breaks .NET MD5/SHA1 use, several Visual Studio
# components, Chrome and many build tools.

Section 'FIPS' {
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy' 'Enabled' 1
    Note 'FIPS mode is ON. If a build or tool starts failing with "not a valid FIPS algorithm", this is why.'
}

# Opt-in only: prompts for a password every time a private key is used, which
# breaks unattended code signing and any automated certificate use.
Section 'StrongKeyProtection' {
    Set-Pol 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography' 'ForceKeyProtection' 2
    Note 'Strong key protection is ON: Windows now prompts for a password every time a stored private key is used.'
}

# --------------------------- Account policy, user rights, security options --
# ASD pages 15, 34, 46-48. Applied via secedit.

Section 'AccountPolicy' {
    # Must be set before a minimum password length above 14 will take effect.
    Set-Pol 'HKLM:\SYSTEM\CurrentControlSet\Control\SAM' 'RelaxMinimumPasswordLengthLimits' 1

    $inf = Join-Path $env:TEMP 'asd-secpol.inf'
    $db  = Join-Path $env:TEMP 'asd-secpol.sdb'

    $lines = @(
        '[Unicode]'
        'Unicode=yes'
        '[Version]'
        'signature="$CHICAGO$"'
        'Revision=1'
        '[System Access]'
        'MinimumPasswordLength = 15'
        'PasswordComplexity = 0'
        'MaximumPasswordAge = -1'
        'MinimumPasswordAge = 0'
        'PasswordHistorySize = 24'
        'ClearTextPassword = 0'
        'LockoutBadCount = 5'
        'ResetLockoutCount = 15'
        'LockoutDuration = 15'
        'AllowAdministratorLockout = 1'
        'EnableGuestAccount = 0'
        'LSAAnonymousNameLookup = 0'
        '[Privilege Rights]'
        'SeTrustedCredManAccessPrivilege ='
        'SeTcbPrivilege ='
        'SeCreateTokenPrivilege ='
        'SeCreatePermanentPrivilege ='
        'SeEnableDelegationPrivilege ='
        'SeLockMemoryPrivilege ='
        "SeNetworkLogonRight = $($SID.RemoteDesktopUsers)"
        "SeInteractiveLogonRight = $($SID.Users),$($SID.Administrators)"
        "SeRemoteInteractiveLogonRight = $($SID.RemoteDesktopUsers)"
        "SeDenyNetworkLogonRight = $($SID.Administrators),$($SID.LocalAccount)"
        "SeDenyRemoteInteractiveLogonRight = $($SID.Administrators),$($SID.LocalAccount)"
        "SeDenyServiceLogonRight = $($SID.Administrators)"
        "SeCreatePagefilePrivilege = $($SID.Administrators)"
        "SeCreateGlobalPrivilege = $($SID.Administrators),$($SID.LocalService),$($SID.NetworkService),$($SID.Service)"
        "SeImpersonatePrivilege = $($SID.Administrators),$($SID.LocalService),$($SID.NetworkService),$($SID.Service)"
        "SeDebugPrivilege = $($SID.Administrators)"
        "SeRemoteShutdownPrivilege = $($SID.Administrators)"
        "SeLoadDriverPrivilege = $($SID.Administrators)"
        "SeSystemEnvironmentPrivilege = $($SID.Administrators)"
        "SeManageVolumePrivilege = $($SID.Administrators)"
        "SeProfileSingleProcessPrivilege = $($SID.Administrators)"
        "SeTakeOwnershipPrivilege = $($SID.Administrators)"
        "SeBackupPrivilege = $($SID.Administrators)"
        "SeRestorePrivilege = $($SID.Administrators)"
        "SeSecurityPrivilege = $($SID.Administrators)"
        "SeSystemTimePrivilege = $($SID.Administrators),$($SID.LocalService)"
    )

    if ($Verify) {
        Write-Log 'account policy / user rights are applied via secedit and are not re-read by -Verify' 'SKIP'
    } elseif ($DryRun) {
        Write-Log "write $inf and run: secedit /configure /db $db /cfg $inf /areas SECURITYPOLICY USER_RIGHTS" 'WOULD'
        $lines | ForEach-Object { Write-Log "  $_" 'WOULD' }
    } else {
        Invoke-Step 'apply account policy and user rights via secedit' {
            Set-Content -LiteralPath $inf -Value $lines -Encoding Unicode -Force
            $out = secedit /configure /db $db /cfg $inf /areas SECURITYPOLICY USER_RIGHTS /quiet 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($out | Out-String).Trim() }
        }
    }

    Note ('Account lockout duration is 15 minutes, not the ASD value of 0 (locked until an ' +
          'administrator unlocks it). On a single-admin standalone machine, 0 plus ' +
          '"Allow Administrator account lockout" can lock you out of your own PC permanently. ' +
          'Change LockoutDuration in secpol.msc if you want the strict value.')
    Note ('"Allow log on locally" is granted to Users AND Administrators. ASD lists Users only, ' +
          'and separately denies Administrators - correct on a domain where you log on as a ' +
          'standard user, but on this machine it would lock you out at the console.')
    Note ('"Deny log on as a batch job = Administrators" is NOT applied - it would break any ' +
          'scheduled task you create under your own account.')
    Note ('Inbound network logon is now limited to the Remote Desktop Users group, and local ' +
          'accounts are denied it. Other machines can no longer reach shares on this PC.')
}

# ------------------------------------------------------ hardware reporting --
# Not scriptable: Secure Boot, TPM, UEFI password, boot order.

Section 'HardwareCheck' {
    $sb = try { Confirm-SecureBootUEFI } catch { $null }
    Write-Log ("Secure Boot: {0}" -f $(if ($null -eq $sb) { 'unknown / legacy BIOS' } elseif ($sb) { 'ENABLED' } else { 'DISABLED' })) `
        $(if ($sb -eq $true) { 'INFO' } else { 'WARN' })

    $tpm = try { Get-Tpm } catch { $null }
    if ($tpm) {
        Write-Log ("TPM present={0} ready={1} version={2}" -f $tpm.TpmPresent, $tpm.TpmReady,
            (Get-CimInstance -Namespace 'root/cimv2/security/microsofttpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue).SpecVersion)
    } else {
        Write-Log 'TPM: not detected' 'WARN'
    }

    $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg) { Write-Log ("Device Guard running services: {0} (1=Credential Guard, 2=HVCI)" -f (($dg.SecurityServicesRunning -join ',') -replace '^$', 'none')) }

    Write-Log 'Set a UEFI/BIOS supervisor password and restrict the boot order to the internal disk. Neither can be done from Windows.' 'WARN'
}

# ----------------------------------------------------------------- summary --

Write-Log 'SUMMARY' 'HEAD'

if ($Verify) {
    if ($script:Drift.Count -eq 0) {
        Write-Log 'No drift. Every checked value matches the intended configuration.'
    } else {
        Write-Log "$($script:Drift.Count) value(s) do not match:" 'WARN'
        foreach ($d in $script:Drift) { Write-Log "  $d" 'DRIFT' }
    }
} else {
    Write-Log ("changed: {0}   already correct: {1}   failed: {2}" -f $script:Changed, $script:Same, $script:Failed)
}

Write-Log "sections available: $($script:Sections -join ', ')"

if ($script:Notes.Count -gt 0) {
    Write-Host ''
    Write-Log 'THINGS THAT WILL SURPRISE YOU' 'HEAD'
    $i = 1
    foreach ($n in $script:Notes) { Write-Log "$i. $n" 'WARN'; $i++ }
}

Write-Host ''
Write-Log 'NOT APPLIED - by your requirement' 'HEAD'
@(
    'Prevent access to the command prompt / batch and script processing (page 23)'
    'Prevent access to registry editing tools (page 38)'
    'PowerShell "Turn on Script Execution: Allow only signed scripts" (page 37)'
    'All Removable Storage classes: Deny all access, and every per-class deny rule (page 28)'
    'Microsoft Defender Antivirus configuration (pages 16-18) - Malwarebytes Premium is the engine'
    'Attack Surface Reduction rules (pages 3-4) - requires Defender as the primary real-time scanner'
    'Controlled Folder Access (page 6) - same dependency on Defender'
    'All BitLocker drive encryption policy (pages 24-28) - encryption is not in use'
    'Block all consumer Microsoft account user authentication / Allow Microsoft accounts to be optional (page 32)'
    'Prevent the usage of OneDrive for file storage (page 32)'
    'Turn off access to the Store / Turn off the Store application / Remove default Store packages (page 52)'
    'Remote Desktop Services "Allow users to connect remotely" - RDP is disabled instead (page 39)'
) | ForEach-Object { Write-Log "  - $_" 'SKIP' }

Write-Host ''
Write-Log 'NOT APPLIED - would break or brick this machine' 'HEAD'
@(
    '"Accounts: Administrator account status = Enabled" (page 10) - only correct with LAPS managing the password; enabling the built-in Administrator on a standalone PC adds an attackable account'
    '"Deny log on locally = Administrators" (page 48) - would lock you out at the console'
    '"Allow log on locally = Users" only (page 47) - same reason; Administrators is kept'
    '"Deny log on as a batch job = Administrators" (page 48) - breaks your own scheduled tasks'
    'Account lockout duration of 0 (page 15) - replaced with 15 minutes'
    'Mandatory (force-relocate) ASLR - breaks a large amount of software'
    'UEFI lock on Credential Guard, HVCI and LSA protection - enabled unlocked so you can recover'
) | ForEach-Object { Write-Log "  - $_" 'SKIP' }

Write-Host ''
Write-Log 'NOT AUTOMATED - do these yourself' 'HEAD'
@(
    'Set a UEFI supervisor password and restrict boot devices to the internal disk (pages 21, 47)'
    'Turn on the Malwarebytes equivalents of ASR and Controlled Folder Access: Exploit Protection, Ransomware Protection, Web Protection, archive and removable-drive scanning'
    'Application control - WDAC or AppLocker ruleset built from scratch (page 2)'
    'LAPS, WSUS, AD recovery-key escrow, centralised log forwarding - all need a domain (pages 10, 13, 23)'
    'Harden Microsoft Edge and Office using the Microsoft Security Baselines (pages 2, 11)'
    'Corporate Windows Error Reporting server (page 41)'
    'CLFS log file authentication (page 19) - no documented standalone registry equivalent'
) | ForEach-Object { Write-Log "  - $_" 'SKIP' }

Write-Host ''
if (-not $Verify -and -not $DryRun) {
    Write-Log 'REBOOT REQUIRED. Credential Guard, HVCI, Secure Launch, SMBv1 removal and the audit policy all need a restart.' 'WARN'
    Write-Log "Full log: $LogPath" 'INFO'
    Write-Log 'After the reboot, re-run this script with -Verify to confirm nothing was reverted.' 'INFO'
}
