[![GitHub Downloads - All Releases](https://img.shields.io/github/downloads/asheroto/Install-AllUpdates/total?label=release%20downloads)](https://github.com/asheroto/Install-AllUpdates/releases)
[![Release](https://img.shields.io/github/v/release/asheroto/Install-AllUpdates)](https://github.com/asheroto/Install-AllUpdates/releases)
[![GitHub Release Date - Published_At](https://img.shields.io/github/release-date/asheroto/Install-AllUpdates)](https://github.com/asheroto/Install-AllUpdates/releases)

[![GitHub Sponsor](https://img.shields.io/github/sponsors/asheroto?label=Sponsor&logo=GitHub)](https://github.com/sponsors/asheroto?frequency=one-time&sponsor=asheroto)
<a href="https://ko-fi.com/asheroto"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Ko-Fi Button" height="20px"></a>
<a href="https://www.buymeacoffee.com/asheroto"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="40px"></a>

# Install All Windows Updates from PowerShell

**Installs every update Windows Update has on offer, optional ones and drivers included, then restarts the device if an update needs it. One command to bring a Windows 10 or 11 device fully up to date.**

## Table of Contents

-   [Requirements](#requirements)
-   [Features](#features)
-   [Script Functionality](#script-functionality)
-   [Setup](#setup)
    -   [Method 1 - One Line Command (Runs Immediately)](#method-1---one-line-command-runs-immediately)
        -   [Option A: asheroto.com short URL](#option-a-asherotocom-short-url)
        -   [Option B: direct release URL](#option-b-direct-release-url)
    -   [Method 2 - Download Locally and Run](#method-2---download-locally-and-run)
-   [Parameters](#parameters)
    -   [Example Parameters Usage](#example-parameters-usage)
-   [Reading the Result](#reading-the-result)
-   [Troubleshooting](#troubleshooting)
-   [Notes](#notes)

## Requirements

-   Requires PowerShell 5.1 or higher running with Administrator privileges
-   Compatible with:
    -   Windows 10
    -   Windows 11

## Features

-   Installs every pending update from Windows Update, optional updates included
-   Pulls driver updates from Microsoft Update
-   Skips feature updates (a new Windows version) unless `-IncludeFeatureUpdates` is passed
-   Shows the normal Install-WindowsUpdate table and progress bar live, so you can see which update it is working on
-   Restarts the device with a 60 second warning if an update needs it, or reports it with `-NoReboot`
-   Ends with a single result line that is easy to read by eye or from an RMM tool
-   Supports irm/iex one-line command using short URL
-   Nothing is installed from anywhere but Windows Update

## Script Functionality

-   Installs the NuGet package provider for PowerShell Gallery (if not already present)
-   Installs the [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate) module from PowerShell Gallery (if not already present)
-   Registers Microsoft Update, where most driver updates come from
-   Lists what is pending, then downloads and installs all of it
-   Falls back to plain Windows Update if the Microsoft Update search fails
-   If a restart is needed, restarts the device with a 60 second warning on screen
-   Logs to `C:\ProgramData\InstallAllUpdates\Logs`

## Setup

### Method 1 - One Line Command (Runs Immediately)

The URL [asheroto.com/updates](https://asheroto.com/updates) always redirects to the [latest release](https://github.com/asheroto/Install-AllUpdates/releases/latest/download/Install-AllUpdates.ps1) of the script.

If you just need to run the basic script without any parameters, open PowerShell as Administrator and use the following one-line command:

#### Option A: asheroto.com short URL

```powershell
irm asheroto.com/updates | iex
```

Due to the nature of how PowerShell works, you won't be able to use any parameters like `-NoReboot` with this command line. If you need to use a one-line command with parameters, you can use the following:

```powershell
&([ScriptBlock]::Create((irm asheroto.com/updates))) -NoReboot
```

#### Option B: direct release URL

Alternatively, you can of course use the latest release URL directly:

```powershell
irm https://github.com/asheroto/Install-AllUpdates/releases/latest/download/Install-AllUpdates.ps1 | iex
```

### Method 2 - Download Locally and Run

As a more conventional approach, download the latest [Install-AllUpdates.ps1](https://github.com/asheroto/Install-AllUpdates/releases/latest/download/Install-AllUpdates.ps1) from [Releases](https://github.com/asheroto/Install-AllUpdates/releases), then run the script from PowerShell as Administrator as follows:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Install-AllUpdates.ps1
```

## Parameters

**No parameters are required to run the script.**

| Parameter                | Description                                                                                                                                                                                 |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-ExcludeOptional`       | Skip the optional updates (Settings > Windows Update > Advanced options > Optional updates). Default installs them.                                                                        |
| `-IncludeFeatureUpdates` | Also install feature updates, the ones that move Windows to a new version (for example 23H2 to 24H2, or Windows 10 to 11). Default skips them. Monthly cumulative and security updates always install. |
| `-NoReboot`              | Install, report whether a restart is needed, do not restart.                                                                                                                                |

### Example Parameters Usage

```powershell
.\Install-AllUpdates.ps1 -NoReboot
```

```powershell
.\Install-AllUpdates.ps1 -ExcludeOptional -IncludeFeatureUpdates
```

```powershell
&([ScriptBlock]::Create((irm asheroto.com/updates))) -ExcludeOptional -NoReboot
```

## Reading the Result

The last line of output is the result:

```
[STATUS=SUCCESS] [EXITCODE=0] [REBOOT=True]
```

| STATUS    | Meaning                                                                      |
| --------- | ---------------------------------------------------------------------------- |
| `SUCCESS` | Everything pending installed, or nothing was pending.                        |
| `PARTIAL` | At least one update failed. The lines above name it. Restart and run again.  |
| `ERROR`   | The script itself hit a problem. Check the log.                              |

`REBOOT=True` means a restart was needed. Unless `-NoReboot` was set, it is already scheduled.

When run as a file, the script exits with the code shown. When run with the one-line command, it leaves the console open and puts the code in `$LASTEXITCODE` instead.

## Troubleshooting

-   Some devices reject the Microsoft Update search with "Value does not fall within the expected range". The script logs a warning and retries against plain Windows Update. Some driver updates may be missing from that run.
-   If the plain Windows Update search fails too, the Windows Update database on the device is likely damaged. The script prints a one-line reset command in yellow. Copy it, paste it into the same admin PowerShell, then run the script again. It looks like this:

    ```powershell
    Stop-Service wuauserv,bits,cryptsvc -Force; Remove-Item C:\Windows\SoftwareDistribution.old,C:\Windows\System32\catroot2.old -Recurse -Force -ErrorAction SilentlyContinue; Rename-Item C:\Windows\SoftwareDistribution SoftwareDistribution.old; Rename-Item C:\Windows\System32\catroot2 catroot2.old; Start-Service wuauserv,bits,cryptsvc
    ```

    It is safe to run more than once. The script prints this command but never runs it itself.

## Notes

-   Some updates only appear after others are installed and the device has restarted. Run it, let it restart, and run it again until it reports nothing pending.
-   Run with the one-line command, the script does not check for admin rights up front. A non-admin session fails a few lines in instead.
-   The user cannot cancel the restart from the warning. An admin can with `shutdown /a` within the 60 seconds.
-   The 60 second delay is set on the `shutdown.exe` line near the end of the script.
