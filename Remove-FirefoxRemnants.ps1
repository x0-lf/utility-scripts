#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Removes practical Mozilla Firefox remnants from Windows after Firefox has
    been uninstalled.

.DESCRIPTION
    Removes Firefox and Firefox Developer Edition program folders, profiles,
    caches, crash dumps, shortcuts, scheduled tasks, firewall rules, services,
    and known Firefox-specific registry registrations.

    Thunderbird-specific profiles and registry keys are intentionally preserved.
    The Mozilla Maintenance Service is preserved when another Mozilla product,
    such as Thunderbird, appears to remain installed.

    Use -WhatIf first. Profile removal permanently deletes bookmarks, passwords,
    cookies, browsing history, extensions, sessions, certificates, and settings.

.PARAMETER AllUsers
    Removes Firefox files from every local, non-special Windows user profile.
    Without this switch, only the current user's profile is cleaned.

.PARAMETER RemovePolicies
    Removes Firefox enterprise-policy keys from HKCU and HKLM.

.PARAMETER DeepClean
    Also removes practical Windows execution-history traces attributable to
    Firefox, including Prefetch, BAM/DAM, UserAssist, MUI cache, AppCompat,
    and recent-item entries. This is not a forensic-erasure guarantee.

.PARAMETER ForceEvenIfInstalled
    Continues when a registered Firefox installation with firefox.exe is found.
    Normally the script stops to prevent destroying a still-installed browser.

.PARAMETER KeepMaintenanceService
    Does not remove the Mozilla Maintenance Service, even when no other Mozilla
    product is detected.

.PARAMETER LogPath
    Path of the cleanup log. Defaults to the current user's TEMP directory.

.EXAMPLE
    .\Remove-FirefoxRemnants.ps1 -AllUsers -RemovePolicies -DeepClean -WhatIf

.EXAMPLE
    .\Remove-FirefoxRemnants.ps1 -AllUsers -RemovePolicies -DeepClean -Confirm:$false

.NOTES
    Run from 64-bit Windows PowerShell 5.1 or PowerShell 7 as Administrator.
    This script targets practical application remnants. Windows restore points,
    event logs, filesystem metadata, security-product history, search indexes,
    and other forensic artifacts are outside its scope.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$AllUsers,
    [switch]$RemovePolicies,
    [switch]$DeepClean,
    [switch]$ForceEvenIfInstalled,
    [switch]$KeepMaintenanceService,
    [string]$LogPath = (Join-Path $env:TEMP ("Remove-FirefoxRemnants-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This script supports Windows only.'
}

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    throw 'Run the script from 64-bit Windows PowerShell or 64-bit PowerShell 7.'
}

$programFilesNative = $env:ProgramFiles
$programFilesX86 = ${env:ProgramFiles(x86)}
if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
    $programFilesX86 = $programFilesNative
}

$script:RemovedCount = 0
$script:SkippedCount = 0
$script:FailedCount = 0
$script:LogPath = $LogPath

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'REMOVED', 'SKIPPED')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line

    try {
        $parent = Split-Path -Parent $script:LogPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
    catch {
        Write-Warning "Unable to write to log '$script:LogPath': $($_.Exception.Message)"
    }
}

function Invoke-Removal {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        [scriptblock]$Operation
    )

    if (-not $PSCmdlet.ShouldProcess($Target, $Action)) {
        $script:SkippedCount++
        Write-Log -Level SKIPPED -Message "$Action :: $Target"
        return
    }

    try {
        & $Operation
        $script:RemovedCount++
        Write-Log -Level REMOVED -Message "$Action :: $Target"
    }
    catch {
        $script:FailedCount++
        Write-Log -Level ERROR -Message "$Action failed :: $Target :: $($_.Exception.Message)"
    }
}

function Remove-PathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return
    }

    $resolved = $null
    try {
        $resolved = (Resolve-Path -LiteralPath $LiteralPath -ErrorAction Stop).Path
    }
    catch {
        $resolved = $LiteralPath
    }

    Invoke-Removal -Target $resolved -Action 'Delete file or directory' -Operation {
        Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction Stop
    }
}

function Remove-PathPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PathPattern
    )

    Get-ChildItem -Path $PathPattern -Force -ErrorAction SilentlyContinue |
        Sort-Object FullName -Unique |
        ForEach-Object { Remove-PathSafe -LiteralPath $_.FullName }
}

function Remove-RegistryKeySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Invoke-Removal -Target $Path -Action 'Delete registry key' -Operation {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
}

function Remove-RegistryValueSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Invoke-Removal -Target "$Path [$Name]" -Action 'Delete registry value' -Operation {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
    }
}

function Remove-RegistryValuesMatching {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [regex]$Pattern
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        foreach ($valueName in $key.GetValueNames()) {
            if ([string]::IsNullOrEmpty($valueName)) {
                continue
            }

            $valueData = $null
            try {
                $valueData = $key.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            }
            catch {
                $valueData = $null
            }

            $text = '{0} {1}' -f $valueName, ([string]$valueData)
            if ($Pattern.IsMatch($text)) {
                Remove-RegistryValueSafe -Path $Path -Name $valueName
            }
        }
    }
    catch {
        Write-Log -Level WARN -Message "Unable to inspect registry values :: $Path :: $($_.Exception.Message)"
    }
}

function Get-UninstallEntries {
    [CmdletBinding()]
    param()

    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($subKey in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            try {
                $item = Get-Item -LiteralPath $subKey.PSPath -ErrorAction Stop
                [pscustomobject]@{
                    RegistryPath    = $subKey.PSPath
                    DisplayName     = [string]$item.GetValue('DisplayName')
                    InstallLocation = [string]$item.GetValue('InstallLocation')
                    DisplayIcon     = [string]$item.GetValue('DisplayIcon')
                    UninstallString = [string]$item.GetValue('UninstallString')
                }
            }
            catch {
                continue
            }
        }
    }
}

function Get-LocalUserProfiles {
    [CmdletBinding()]
    param()

    if (-not $AllUsers) {
        return ,$env:USERPROFILE
    }

    $profiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object {
            -not $_.Special -and
            -not [string]::IsNullOrWhiteSpace($_.LocalPath) -and
            (Test-Path -LiteralPath $_.LocalPath)
        } |
        Select-Object -ExpandProperty LocalPath -Unique

    if (-not $profiles) {
        return ,$env:USERPROFILE
    }

    return $profiles
}

function Stop-FirefoxProcesses {
    [CmdletBinding()]
    param()

    $processNames = @(
        'firefox',
        'private_browsing',
        'default-browser-agent'
    )

    foreach ($name in $processNames) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            $process = $_
            Invoke-Removal -Target ("{0} (PID {1})" -f $process.ProcessName, $process.Id) -Action 'Stop process' -Operation {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            }
        }
    }
}

function Remove-FirefoxScheduledTasks {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        Write-Log -Level WARN -Message 'ScheduledTasks module is unavailable; scheduled-task cleanup was skipped.'
        return
    }

    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object {
            ('{0}{1}' -f $_.TaskPath, $_.TaskName) -match '(?i)firefox|default browser agent'
        } |
        ForEach-Object {
            $task = $_
            $fullName = '{0}{1}' -f $task.TaskPath, $task.TaskName
            Invoke-Removal -Target $fullName -Action 'Unregister scheduled task' -Operation {
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
            }
        }
}

function Remove-FirefoxFirewallRules {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) {
        Write-Log -Level WARN -Message 'NetSecurity module is unavailable; firewall-rule cleanup was skipped.'
        return
    }

    foreach ($rule in Get-NetFirewallRule -ErrorAction SilentlyContinue) {
        $program = ''
        try {
            $filters = $rule | Get-NetFirewallApplicationFilter -ErrorAction Stop
            $program = ($filters.Program -join ' ')
        }
        catch {
            $program = ''
        }

        $text = '{0} {1} {2}' -f $rule.DisplayName, $rule.Description, $program
        if ($text -match '(?i)firefox|\\Mozilla Firefox\\|\\Firefox Developer Edition\\|\\firefox\.exe(?:"|$)') {
            $capturedRule = $rule
            Invoke-Removal -Target $rule.DisplayName -Action 'Delete firewall rule' -Operation {
                Remove-NetFirewallRule -Name $capturedRule.Name -ErrorAction Stop
            }
        }
    }
}

function Remove-MaintenanceService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$OtherMozillaProductPresent
    )

    if ($KeepMaintenanceService) {
        Write-Log -Level SKIPPED -Message 'Mozilla Maintenance Service preserved by -KeepMaintenanceService.'
        return
    }

    if ($OtherMozillaProductPresent) {
        Write-Log -Level SKIPPED -Message 'Mozilla Maintenance Service preserved because another Mozilla product appears installed.'
        return
    }

    $service = Get-Service -Name 'MozillaMaintenance' -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne 'Stopped') {
            Invoke-Removal -Target 'MozillaMaintenance' -Action 'Stop Windows service' -Operation {
                Stop-Service -Name 'MozillaMaintenance' -Force -ErrorAction Stop
            }
        }

        Invoke-Removal -Target 'MozillaMaintenance' -Action 'Delete Windows service' -Operation {
            $output = & sc.exe delete MozillaMaintenance 2>&1
            if ($LASTEXITCODE -ne 0 -and ($output -join ' ') -notmatch 'does not exist|1060') {
                throw ($output -join [Environment]::NewLine)
            }
        }
    }

    Remove-RegistryKeySafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\MozillaMaintenance'
}

function Remove-FirefoxClasses {
    [CmdletBinding()]
    param()

    $classRoots = @(
        'HKCU:\Software\Classes',
        'HKLM:\Software\Classes',
        'HKLM:\Software\WOW6432Node\Classes'
    )

    foreach ($root in $classRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '(?i)^(Firefox|MozillaFirefox)' } |
            ForEach-Object { Remove-RegistryKeySafe -Path $_.PSPath }

        Remove-RegistryKeySafe -Path (Join-Path $root 'Applications\firefox.exe')
        Remove-RegistryKeySafe -Path (Join-Path $root 'Applications\private_browsing.exe')
    }
}

function Remove-FirefoxStartMenuRegistrations {
    [CmdletBinding()]
    param()

    $clientRoots = @(
        'HKCU:\Software\Clients\StartMenuInternet',
        'HKLM:\Software\Clients\StartMenuInternet',
        'HKLM:\Software\WOW6432Node\Clients\StartMenuInternet'
    )

    foreach ($root in $clientRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($subKey in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $defaultValue = ''
            try {
                $registryKey = Get-Item -LiteralPath $subKey.PSPath -ErrorAction Stop
                $defaultValue = [string]$registryKey.GetValue('')
            }
            catch {
                $defaultValue = ''
            }

            if ($subKey.PSChildName -match '(?i)firefox' -or $defaultValue -match '(?i)firefox') {
                Remove-RegistryKeySafe -Path $subKey.PSPath
            }
        }
    }

    $registeredApplicationRoots = @(
        'HKCU:\Software\RegisteredApplications',
        'HKLM:\Software\RegisteredApplications',
        'HKLM:\Software\WOW6432Node\RegisteredApplications'
    )

    foreach ($path in $registeredApplicationRoots) {
        Remove-RegistryValuesMatching -Path $path -Pattern ([regex]'(?i)firefox|mozilla.*browser')
    }
}

function Remove-FirefoxDefaultAssociations {
    [CmdletBinding()]
    param()

    $protocolRoot = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations'
    foreach ($protocol in @('http', 'https', 'ftp')) {
        $userChoice = Join-Path $protocolRoot "$protocol\UserChoice"
        if (Test-Path -LiteralPath $userChoice) {
            $progId = [string](Get-ItemPropertyValue -LiteralPath $userChoice -Name 'ProgId' -ErrorAction SilentlyContinue)
            if ($progId -match '(?i)^Firefox') {
                Remove-RegistryKeySafe -Path $userChoice
            }
        }
    }

    $fileExtRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts'
    if (Test-Path -LiteralPath $fileExtRoot) {
        foreach ($extensionKey in Get-ChildItem -LiteralPath $fileExtRoot -ErrorAction SilentlyContinue) {
            $userChoice = Join-Path $extensionKey.PSPath 'UserChoice'
            if (Test-Path -LiteralPath $userChoice) {
                $progId = [string](Get-ItemPropertyValue -LiteralPath $userChoice -Name 'ProgId' -ErrorAction SilentlyContinue)
                if ($progId -match '(?i)^Firefox') {
                    Remove-RegistryKeySafe -Path $userChoice
                }
            }

            Remove-RegistryValuesMatching -Path (Join-Path $extensionKey.PSPath 'OpenWithProgids') -Pattern ([regex]'(?i)^Firefox')
            Remove-RegistryValuesMatching -Path (Join-Path $extensionKey.PSPath 'OpenWithList') -Pattern ([regex]'(?i)firefox\.exe')
        }
    }
}

function Remove-FirefoxRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$PreserveMaintenanceService
    )

    $directKeys = @(
        'HKCU:\Software\Mozilla\Firefox',
        'HKCU:\Software\Mozilla\Mozilla Firefox',
        'HKCU:\Software\Mozilla\NativeMessagingHosts',
        'HKLM:\Software\Mozilla\Firefox',
        'HKLM:\Software\Mozilla\Mozilla Firefox',
        'HKLM:\Software\Mozilla\NativeMessagingHosts',
        'HKLM:\Software\WOW6432Node\Mozilla\Firefox',
        'HKLM:\Software\WOW6432Node\Mozilla\Mozilla Firefox',
        'HKLM:\Software\WOW6432Node\Mozilla\NativeMessagingHosts',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe'
    )

    foreach ($path in $directKeys) {
        Remove-RegistryKeySafe -Path $path
    }

    foreach ($legacyRoot in @(
        'HKCU:\Software\Mozilla.org\Mozilla',
        'HKLM:\Software\Mozilla.org\Mozilla',
        'HKLM:\Software\WOW6432Node\Mozilla.org\Mozilla'
    )) {
        if (Test-Path -LiteralPath $legacyRoot) {
            Get-ChildItem -LiteralPath $legacyRoot -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '(?i)firefox' } |
                ForEach-Object { Remove-RegistryKeySafe -Path $_.PSPath }
        }
    }

    foreach ($entry in Get-UninstallEntries) {
        $text = '{0} {1} {2} {3}' -f $entry.DisplayName, $entry.InstallLocation, $entry.DisplayIcon, $entry.UninstallString
        $isMaintenanceService = $text -match '(?i)mozilla maintenance service'
        $isFirefoxEntry = $text -match '(?i)mozilla firefox|firefox developer edition|\\firefox\.exe'

        if ($isFirefoxEntry -or ($isMaintenanceService -and -not $PreserveMaintenanceService)) {
            Remove-RegistryKeySafe -Path $entry.RegistryPath
        }
    }

    Remove-FirefoxClasses
    Remove-FirefoxStartMenuRegistrations
    Remove-FirefoxDefaultAssociations

    $valueLocations = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\JumplistData'
    )

    foreach ($path in $valueLocations) {
        Remove-RegistryValuesMatching -Path $path -Pattern ([regex]'(?i)firefox|mozilla firefox|firefox developer edition|\\firefox\.exe')
    }

    if ($RemovePolicies) {
        foreach ($path in @(
            'HKCU:\Software\Policies\Mozilla\Firefox',
            'HKLM:\Software\Policies\Mozilla\Firefox',
            'HKLM:\Software\WOW6432Node\Policies\Mozilla\Firefox'
        )) {
            Remove-RegistryKeySafe -Path $path
        }
    }
}

function ConvertTo-Rot13 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $characters = foreach ($character in $Text.ToCharArray()) {
        $code = [int][char]$character
        if ($code -ge 65 -and $code -le 90) {
            [char](65 + (($code - 65 + 13) % 26))
        }
        elseif ($code -ge 97 -and $code -le 122) {
            [char](97 + (($code - 97 + 13) % 26))
        }
        else {
            $character
        }
    }

    return -join $characters
}

function Get-LoadedUserRegistryRoots {
    [CmdletBinding()]
    param()

    $hku = 'Registry::HKEY_USERS'
    if (-not (Test-Path -LiteralPath $hku)) {
        return @()
    }

    $sidKeys = Get-ChildItem -LiteralPath $hku -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-(?:\d+-){3}\d+$' }

    if ($AllUsers) {
        return @($sidKeys | Select-Object -ExpandProperty PSPath)
    }

    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return @($sidKeys | Where-Object { $_.PSChildName -eq $currentSid } | Select-Object -ExpandProperty PSPath)
}

function Remove-FirefoxExecutionHistory {
    [CmdletBinding()]
    param()

    foreach ($path in @(
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store',
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
        'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
        'HKCU:\Software\Microsoft\Windows\ShellNoRoam\MUICache'
    )) {
        Remove-RegistryValuesMatching -Path $path -Pattern ([regex]'(?i)firefox|mozilla firefox|firefox developer edition|\\firefox\.exe')
    }

    foreach ($root in Get-LoadedUserRegistryRoots) {
        $userAssist = Join-Path $root 'Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
        if (Test-Path -LiteralPath $userAssist) {
            $encodedFirefox = [regex]::Escape((ConvertTo-Rot13 -Text 'firefox'))
            $encodedDeveloper = [regex]::Escape((ConvertTo-Rot13 -Text 'developer edition'))
            $pattern = [regex]("(?i)$encodedFirefox|$encodedDeveloper")

            Get-ChildItem -LiteralPath $userAssist -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -eq 'Count' } |
                ForEach-Object { Remove-RegistryValuesMatching -Path $_.PSPath -Pattern $pattern }
        }
    }

    foreach ($root in @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings',
        'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings',
        'HKLM:\SYSTEM\CurrentControlSet\Services\dam\State\UserSettings',
        'HKLM:\SYSTEM\CurrentControlSet\Services\dam\UserSettings'
    )) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-RegistryValuesMatching -Path $_.PSPath -Pattern ([regex]'(?i)firefox|mozilla firefox|firefox developer edition|\\firefox\.exe')
            }
    }
}

Write-Log -Level INFO -Message 'Firefox-remnant cleanup started.'
Write-Log -Level INFO -Message "AllUsers=$AllUsers; RemovePolicies=$RemovePolicies; DeepClean=$DeepClean; WhatIf=$WhatIfPreference"

$uninstallEntries = @(Get-UninstallEntries)
$firefoxInstallEntries = @($uninstallEntries | Where-Object { $_.DisplayName -match '(?i)firefox' })
$otherMozillaEntries = @($uninstallEntries | Where-Object {
    $_.DisplayName -match '(?i)mozilla|thunderbird|seamonkey' -and
    $_.DisplayName -notmatch '(?i)firefox|maintenance service'
})
$preserveMaintenanceService = $KeepMaintenanceService -or ($otherMozillaEntries.Count -gt 0)

$knownExecutablePaths = @(
    (Join-Path $programFilesNative 'Mozilla Firefox\firefox.exe'),
    (Join-Path $programFilesNative 'Firefox Developer Edition\firefox.exe'),
    (Join-Path $programFilesX86 'Mozilla Firefox\firefox.exe'),
    (Join-Path $programFilesX86 'Firefox Developer Edition\firefox.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Mozilla Firefox\firefox.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Firefox Developer Edition\firefox.exe')
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$existingExecutables = @($knownExecutablePaths | Where-Object { Test-Path -LiteralPath $_ })
$appxFirefoxPackages = @()
if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
    if ($AllUsers) {
        $appxFirefoxPackages = @(Get-AppxPackage -AllUsers -Name 'Mozilla.Firefox' -ErrorAction SilentlyContinue)
    }
    else {
        $appxFirefoxPackages = @(Get-AppxPackage -Name 'Mozilla.Firefox' -ErrorAction SilentlyContinue)
    }
}

if ((($firefoxInstallEntries.Count -gt 0 -and $existingExecutables.Count -gt 0) -or $appxFirefoxPackages.Count -gt 0) -and -not $ForceEvenIfInstalled) {
    $details = @($firefoxInstallEntries | ForEach-Object { $_.DisplayName } | Where-Object { $_ })
    $details += @($appxFirefoxPackages | ForEach-Object { $_.Name } | Where-Object { $_ })
    $detailsText = ($details | Sort-Object -Unique) -join ', '
    throw "Firefox still appears installed ($detailsText). Uninstall it first, or rerun with -ForceEvenIfInstalled if destruction is intentional."
}

Stop-FirefoxProcesses
Remove-FirefoxScheduledTasks
Remove-FirefoxFirewallRules
Remove-MaintenanceService -OtherMozillaProductPresent ($otherMozillaEntries.Count -gt 0)

$systemPaths = @(
    (Join-Path $programFilesNative 'Mozilla Firefox'),
    (Join-Path $programFilesNative 'Firefox Developer Edition'),
    (Join-Path $programFilesNative 'Mozilla Maintenance Service'),
    (Join-Path $programFilesX86 'Mozilla Firefox'),
    (Join-Path $programFilesX86 'Firefox Developer Edition'),
    (Join-Path $programFilesX86 'Mozilla Maintenance Service'),
    (Join-Path $env:ProgramData 'Mozilla'),
    (Join-Path $env:ProgramData 'Mozilla-1de4eec8-1241-4177-a864-e594e8d1fb38')
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

foreach ($path in $systemPaths) {
    if ($path -match '(?i)Maintenance Service' -and $preserveMaintenanceService) {
        continue
    }

    if ($otherMozillaEntries.Count -gt 0 -and $path -in @(
        (Join-Path $env:ProgramData 'Mozilla'),
        (Join-Path $env:ProgramData 'Mozilla-1de4eec8-1241-4177-a864-e594e8d1fb38')
    )) {
        Write-Log -Level SKIPPED -Message "Shared Mozilla ProgramData directory preserved: $path"
        if ($path -eq (Join-Path $env:ProgramData 'Mozilla')) {
            Remove-PathPattern -PathPattern (Join-Path $path '*Firefox*')
        }
        continue
    }

    Remove-PathSafe -LiteralPath $path
}

foreach ($pattern in @(
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\*Firefox*.lnk'),
    (Join-Path $env:Public 'Desktop\*Firefox*.lnk'),
    (Join-Path $env:windir 'Temp\Firefox*')
)) {
    Remove-PathPattern -PathPattern $pattern
}

if ($otherMozillaEntries.Count -eq 0) {
    Remove-PathPattern -PathPattern (Join-Path $env:windir 'Temp\Mozilla*')
}

foreach ($profileRoot in Get-LocalUserProfiles) {
    Write-Log -Level INFO -Message "Cleaning user profile: $profileRoot"

    $profilePaths = @(
        (Join-Path $profileRoot 'AppData\Roaming\Mozilla\Firefox'),
        (Join-Path $profileRoot 'AppData\Roaming\Mozilla\Extensions\{ec8030f7-c20a-464f-9b0e-13a3a9e97384}'),
        (Join-Path $profileRoot 'AppData\Local\Mozilla\Firefox'),
        (Join-Path $profileRoot 'AppData\Local\Mozilla\updates'),
        (Join-Path $profileRoot 'AppData\LocalLow\Mozilla\Firefox'),
        (Join-Path $profileRoot 'AppData\Local\Firefox'),
        (Join-Path $profileRoot 'AppData\Local\Programs\Mozilla Firefox'),
        (Join-Path $profileRoot 'AppData\Local\Programs\Firefox Developer Edition'),
        (Join-Path $profileRoot 'Desktop\Old Firefox Data')
    )

    foreach ($path in $profilePaths) {
        if ($path -match '(?i)AppData\\Local\\Mozilla\\updates$' -and $otherMozillaEntries.Count -gt 0) {
            Write-Log -Level SKIPPED -Message "Shared Mozilla update directory preserved: $path"
            continue
        }
        Remove-PathSafe -LiteralPath $path
    }

    foreach ($pattern in @(
        (Join-Path $profileRoot 'AppData\Local\Packages\Mozilla.Firefox_*'),
        (Join-Path $profileRoot 'AppData\Local\CrashDumps\firefox.exe.*.dmp'),
        (Join-Path $profileRoot 'AppData\Local\CrashDumps\default-browser-agent.exe.*.dmp'),
        (Join-Path $profileRoot 'AppData\Local\Temp\Firefox*'),
        (Join-Path $profileRoot 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\*Firefox*.lnk'),
        (Join-Path $profileRoot 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\*Firefox*.lnk'),
        (Join-Path $profileRoot 'AppData\Roaming\Microsoft\Windows\Recent\*Firefox*.lnk'),
        (Join-Path $profileRoot 'Desktop\*Firefox*.lnk')
    )) {
        Remove-PathPattern -PathPattern $pattern
    }

    if ($otherMozillaEntries.Count -eq 0) {
        foreach ($pattern in @(
            (Join-Path $profileRoot 'AppData\Local\CrashDumps\plugin-container.exe.*.dmp'),
            (Join-Path $profileRoot 'AppData\Local\Temp\Mozilla*'),
            (Join-Path $profileRoot 'AppData\Local\Temp\mozilla-temp-files')
        )) {
            Remove-PathPattern -PathPattern $pattern
        }
    }
}

Remove-FirefoxRegistry -PreserveMaintenanceService $preserveMaintenanceService

if ($DeepClean) {
    foreach ($pattern in @(
        (Join-Path $env:windir 'Prefetch\FIREFOX.EXE-*.pf'),
        (Join-Path $env:windir 'Prefetch\PRIVATE_BROWSING.EXE-*.pf'),
        (Join-Path $env:windir 'Prefetch\DEFAULT-BROWSER-AGENT.EXE-*.pf')
    )) {
        Remove-PathPattern -PathPattern $pattern
    }

    if ($otherMozillaEntries.Count -eq 0) {
        foreach ($pattern in @(
            (Join-Path $env:windir 'Prefetch\MAINTENANCESERVICE.EXE-*.pf'),
            (Join-Path $env:windir 'Prefetch\PINGSENDER.EXE-*.pf')
        )) {
            Remove-PathPattern -PathPattern $pattern
        }
    }

    Remove-FirefoxExecutionHistory
}

Write-Log -Level INFO -Message ("Cleanup completed. Removed={0}; Skipped={1}; Failed={2}; Log={3}" -f $script:RemovedCount, $script:SkippedCount, $script:FailedCount, $script:LogPath)

if ($script:FailedCount -gt 0) {
    Write-Warning "Cleanup completed with $script:FailedCount failure(s). Review: $script:LogPath"
    exit 1
}

exit 0
