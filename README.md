# Install-AllUpdates.ps1

Installs every update Windows Update has on offer, optional ones included, then restarts the device if an update needs it. One command to bring a Windows 10 or 11 device fully up to date, drivers and all. Feature updates (a new Windows version) are skipped unless you pass `-IncludeFeatureUpdates`.

## What it does

1. Installs the NuGet provider and the [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate) module if they are missing.
2. Registers Microsoft Update, where most driver updates come from.
3. Lists what is pending, then downloads and installs all of it. The normal Install-WindowsUpdate table and progress bar show live, so you can see which update it is working on.
4. If a restart is needed, restarts the device with a 60 second warning on screen.

Nothing is installed from anywhere but Windows Update. Logs go to `C:\ProgramData\InstallAllUpdates\Logs`.

## Running it

Always run it from an admin PowerShell.

From the gist:

```powershell
irm <gist raw URL> | iex
```

To pass options when running from the gist:

```powershell
& ([scriptblock]::Create((irm <gist raw URL>))) -NoReboot
```

From a local copy:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Install-AllUpdates.ps1
```

| Option | Effect |
|---|---|
| `-ExcludeOptional` | Skip the optional updates (Settings > Windows Update > Advanced options > Optional updates). Default installs them. |
| `-IncludeFeatureUpdates` | Also install feature updates, the ones that move Windows to a new version (for example 23H2 to 24H2, or Windows 10 to 11). Default skips them. Monthly cumulative and security updates always install. |
| `-NoReboot` | Install, report whether a restart is needed, do not restart. |

## Reading the result

The last line of output is the result:

```
[STATUS=SUCCESS] [EXITCODE=0] [REBOOT=True]
```

| STATUS | Meaning |
|---|---|
| `SUCCESS` | Everything pending installed, or nothing was pending. |
| `PARTIAL` | At least one update failed. The lines above name it. Restart and run again. |
| `ERROR` | The script itself hit a problem. Check the log. |

`REBOOT=True` means a restart was needed. Unless `-NoReboot` was set, it is already scheduled.

When run as a file, the script exits with the code shown. When run from the gist, it leaves the console open and puts the code in `$LASTEXITCODE` instead.

## If the update search fails

Some devices reject the Microsoft Update search with "Value does not fall within the expected range". The script logs a warning and retries against plain Windows Update. Some driver updates may be missing from that run.

If the plain Windows Update search fails too, the Windows Update database on the device is likely damaged. The script prints a one-line reset command in yellow. Copy it, paste it into the same admin PowerShell, then run the script again. It looks like this:

```powershell
Stop-Service wuauserv,bits,cryptsvc -Force; Remove-Item C:\Windows\SoftwareDistribution.old,C:\Windows\System32\catroot2.old -Recurse -Force -ErrorAction SilentlyContinue; Rename-Item C:\Windows\SoftwareDistribution SoftwareDistribution.old; Rename-Item C:\Windows\System32\catroot2 catroot2.old; Start-Service wuauserv,bits,cryptsvc
```

It is safe to run more than once. The script prints this command but never runs it itself.

## Notes

- Some updates only appear after others are installed and the device has restarted. Run it, let it restart, and run it again until it reports nothing pending.
- Run from the gist, the script does not check for admin rights up front. A non-admin session fails a few lines in instead.
- The user cannot cancel the restart from the warning. An admin can with `shutdown /a` within the 60 seconds.
- The 60 second delay is set on the `shutdown.exe` line near the end of the script.