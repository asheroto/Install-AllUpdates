#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
    INSTALL ALL PENDING WINDOWS UPDATES, OPTIONAL ONES INCLUDED, THEN RESTART

    Run from an admin PowerShell on the device. It installs the NuGet provider and the
    PSWindowsUpdate module if they are missing, then installs every update Windows Update
    has on offer, including the optional ones (driver updates and optional quality
    updates), and restarts the device with a 60 second warning if any update asks for it.
    Feature updates are left out unless asked for. Nothing is installed from anywhere but
    Windows Update.

    Options:
      -ExcludeOptional   Skip the optional updates, the ones Settings > Windows Update >
                         Advanced options > Optional updates shows. Default installs them.
      -IncludeFeatureUpdates
                         Also install feature updates, the ones that move Windows to a new
                         version (for example 23H2 to 24H2, or Windows 10 to 11). Default
                         skips them. Monthly cumulative and security updates always install.
      -NoReboot          Install, report whether a restart is needed, and do not restart.

    Safe to run again. Each run installs whatever is still pending. Some updates only
    appear after others are installed and the device has restarted, so run it, let it
    restart, and run it once more until it reports nothing pending.

    Log: C:\ProgramData\InstallAllUpdates\Logs
#>

[CmdletBinding()]
param(
    [switch] $ExcludeOptional,
    [switch] $IncludeFeatureUpdates,
    [switch] $NoReboot
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$LogDir  = Join-Path $env:ProgramData 'InstallAllUpdates\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir "Updates_$(Get-Date -f 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param(
        [Parameter(Mandatory, Position = 0)][string] $Message,
        [Parameter(Position = 1)][ValidateSet('INFO', 'WARN', 'ERROR')][string] $Level = 'INFO'
    )
    $line = '[{0}] {1,-5} {2}' -f (Get-Date -f 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}

$exitCode = 1
try {
    $excluded = @(if ($ExcludeOptional) { 'optional' }; if (-not $IncludeFeatureUpdates) { 'feature updates' })
    Write-Log "=== Install all pending updates$(if ($excluded) { " ($($excluded -join ', ') excluded)" }) ==="
    Write-Log "Device : $env:COMPUTERNAME"
    Write-Log "Log    : $LogFile"

    # ------------------------------------------------ NuGet + PSWindowsUpdate ---

    # PS 5.1 can default to TLS 1.0, which the PowerShell Gallery refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Set-ExecutionPolicy Bypass -Scope Process -Force

    if (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue) {
        Write-Log 'NuGet provider already installed.'
    }
    else {
        Write-Log 'Installing the NuGet package provider.'
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }

    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Write-Log 'PSWindowsUpdate module already installed.'
    }
    else {
        # PowerShellGet 1.0.0.1 (stock on 5.1) often has no PSGallery registration, or a
        # stale one, and then reports "No match was found" instead of a repository error.
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $gallery) {
            Write-Log 'PSGallery repository missing. Registering the default repository.'
            Register-PSRepository -Default -ErrorAction Stop
        }
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop

        Write-Log 'Installing the PSWindowsUpdate module from the PowerShell Gallery.'
        try {
            Install-Module -Name PSWindowsUpdate -Repository PSGallery -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
        }
        catch {
            # A broken registration survives the check above. Re-register once and retry.
            Write-Log "Install failed ($($_.Exception.Message)). Re-registering PSGallery and retrying." 'WARN'
            Unregister-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
            Register-PSRepository -Default -ErrorAction Stop
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
            Install-Module -Name PSWindowsUpdate -Repository PSGallery -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
        }
    }
    Import-Module PSWindowsUpdate -ErrorAction Stop
    Write-Log "PSWindowsUpdate $((Get-Module PSWindowsUpdate).Version) loaded."

    # Microsoft Update (not just Windows Update) is where most driver updates come from.
    try { Add-WUServiceManager -MicrosoftUpdate -Confirm:$false -ErrorAction Stop | Out-Null }
    catch { Write-Log "Could not register the Microsoft Update service, continuing with Windows Update only: $($_.Exception.Message)" 'WARN' }

    # ----------------------------------------------------------- pre-checks ---

    if (Get-WURebootStatus -Silent) {
        Write-Log 'A restart is already pending from earlier updates. Installs may fail until it is taken.' 'WARN'
    }

    # A search without BrowseOnly returns required and optional updates together. Adding
    # BrowseOnly=0 drops the optional ones (drivers, optional quality updates).
    $criteria = if ($ExcludeOptional) { 'IsInstalled=0 and IsHidden=0 and BrowseOnly=0' } else { 'IsInstalled=0 and IsHidden=0' }

    # The search criteria language cannot exclude a category, so feature updates are
    # dropped after the search. They sit in the Upgrades category, and the title match
    # catches enablement packages and version offers filed elsewhere.
    $filter = if (-not $IncludeFeatureUpdates) {
        @{ NotCategory = 'Upgrades'; NotTitle = 'Feature update|Windows 1[01], version|Upgrade to Windows' }
    } else { @{} }

    Write-Log 'Searching Windows Update. This can take a minute or two.'
    # Some devices reject a Microsoft Update search ("Value does not fall within the expected
    # range") when that service registration is pending or broken. Fall back to Windows Update.
    $source = @{ MicrosoftUpdate = $true }
    try { $pending = @(Get-WindowsUpdate @source @filter -Criteria $criteria | ForEach-Object { $_ }) }
    catch {
        Write-Log "Microsoft Update search failed, retrying with Windows Update only: $($_.Exception.Message)" 'WARN'
        $source  = @{}
        try { $pending = @(Get-WindowsUpdate @filter -Criteria $criteria | ForEach-Object { $_ }) }
        catch {
            # Both sources failed, so the update agent's own database is the likely problem.
            Write-Log "Windows Update search failed too: $($_.Exception.Message)" 'ERROR'
            Write-Log 'Reset the Windows Update components by pasting this line into this admin PowerShell, then run this script again:' 'ERROR'
            $reset = 'Stop-Service wuauserv,bits,cryptsvc -Force; Remove-Item C:\Windows\SoftwareDistribution.old,C:\Windows\System32\catroot2.old -Recurse -Force -ErrorAction SilentlyContinue; Rename-Item C:\Windows\SoftwareDistribution SoftwareDistribution.old; Rename-Item C:\Windows\System32\catroot2 catroot2.old; Start-Service wuauserv,bits,cryptsvc'
            # Printed bare, with no timestamp prefix, so it copies cleanly.
            Write-Host $reset -ForegroundColor Yellow
            try { Add-Content -Path $LogFile -Value $reset -Encoding UTF8 } catch { }
            throw
        }
    }
    # PSWindowsUpdate 2.2.1.5 returns every update bundled in one object. Piping through
    # ForEach-Object above splits them back out, one object per update.
    if (-not $pending.Count) {
        Write-Log 'Nothing pending. The device is up to date.'
        $exitCode = 0
    }
    else {
        Write-Log "Updates to install ($($pending.Count)):"
        foreach ($u in $pending) {
            Write-Log ('  {0,-10} {1,-7} {2}' -f "$($u.KB)", "$($u.Size)", "$($u.Title)")
        }

        # --------------------------------------------------------- install ---

        # -IgnoreReboot keeps PSWindowsUpdate from restarting on its own mid-run. The
        # restart is scheduled below instead, so the user gets a warning and -NoReboot
        # can stop it.
        # Left uncaptured, so the console shows the normal Install-WindowsUpdate table and
        # progress bar live, exactly as when typed by hand. -OutVariable keeps a copy of the
        # rows for the summary without changing what is shown.
        Write-Log 'Downloading and installing.'
        $ProgressPreference = 'Continue'
        Install-WindowsUpdate @source @filter -Criteria $criteria -AcceptAll -IgnoreReboot -OutVariable installRows
        $ProgressPreference = 'SilentlyContinue'

        # The rows may arrive bundled, and there is one per stage (accepted, downloaded,
        # installed). Split them out and keep the last row for each update.
        $results = @(@($installRows | ForEach-Object { $_ }) |
            Group-Object { "$($_.KB)|$($_.Title)" } | ForEach-Object { $_.Group[-1] })

        $failed = @($results | Where-Object { "$($_.Result)" -ne 'Installed' })
        Write-Log "Installed: $($results.Count - $failed.Count), failed: $($failed.Count)"
        foreach ($f in $failed) { Write-Log ('  {0,-10} {1,-10} {2}' -f "$($f.Result)", "$($f.KB)", "$($f.Title)") 'ERROR' }
        $exitCode = if ($failed.Count) { 30 } else { 0 }
    }
}
catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" 'ERROR'
    Write-Log $_.ScriptStackTrace 'ERROR'
    $exitCode = 1
}

# ---------------------------------------------------------------- restart ---

$rebootNeeded = $false
try { $rebootNeeded = [bool](Get-WURebootStatus -Silent) } catch { }

if ($rebootNeeded -and $NoReboot) {
    Write-Log 'A restart is needed to finish. NoReboot is set, so restart the device by hand.' 'WARN'
}
elseif ($rebootNeeded) {
    Write-Log 'A restart is needed to finish. Restarting in 60 seconds.'
    & shutdown.exe /r /t 60 /c 'Restarting to finish installing Windows updates. Please save your work.'
}
else {
    Write-Log 'No restart needed.'
}

Write-Log "[STATUS=$(switch ($exitCode) { 0 { 'SUCCESS' } 30 { 'PARTIAL' } default { 'ERROR' } })] [EXITCODE=$exitCode] [REBOOT=$rebootNeeded]"
# Run as a file (.\Install-AllUpdates.ps1, RMM, powershell -File): hand the code to the caller.
# Pasted or run from a gist with Invoke-Expression: exit would close the console, so
# just record the code in $LASTEXITCODE and let the console live.
if ($PSCommandPath) { exit $exitCode }
$global:LASTEXITCODE = $exitCode