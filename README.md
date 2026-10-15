# lumide_status_bar_stats

[![pub package](https://img.shields.io/pub/v/lumide_status_bar_stats.svg)](https://pub.dev/packages/lumide_status_bar_stats) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

System stats in the [Lumide IDE](https://lumide.dev) status bar: CPU, memory, disk, network, battery and CPU temperature, refreshed every couple of seconds.

![System stats in the Lumide status bar](https://raw.githubusercontent.com/simonpham/lumide_status_bar_stats/develop/doc/status_bar.png)

## Features

- **CPU**: usage across all cores, with load averages in the tooltip (Linux and macOS).
- **Memory**: percentage used, or used and total; available memory and swap in the tooltip.
- **Disk**: free space on the system disk.
- **Network**: download and upload rates of the active connection.
- **Battery**: level, charging state and time remaining. Hidden on desktops.
- **CPU temperature**: from the CPU package sensor, in °C or °F. Fan speed on Macs with fans.
- **Session uptime** (off by default): how long Lumide has been running.
- **Alerts**: items turn orange or red when CPU, memory, disk, temperature or battery needs attention.
- **Quick menu**: click any item to change its style or hide it. The toolbar icon opens every option.
- **Dashboard**: live charts and the top processes by CPU and memory.
- **Battery Saver**: refreshes every 10 seconds or slower while on battery power.

![Quick menu](https://raw.githubusercontent.com/simonpham/lumide_status_bar_stats/develop/doc/quick_menu.png)

![Dashboard](https://raw.githubusercontent.com/simonpham/lumide_status_bar_stats/develop/doc/dashboard.png)

## Installation

1. Open the **Plugins** pane (`Cmd+Shift+X` / `Ctrl+Shift+X`).
2. Search for `lumide_status_bar_stats`, or browse the **Utilities** category.
3. Click **Install**. The items appear in the status bar right away.

## Commands

Open the Command Palette (`Cmd+Shift+P` / `Ctrl+Shift+P`) and type `System Stats`.

| Command | Purpose |
| --- | --- |
| `System Stats: Open Quick Menu` | All options: dashboard, refresh interval, units, items to show |
| `System Stats: Show Dashboard` | Live charts and top processes |
| `System Stats: Show Report in Output` | Write a text summary to the Output pane |
| `System Stats: Refresh Now` | Read every metric again |
| `System Stats: Toggle CPU` / `RAM` / `Disk` / `Network` / `Battery` / `Temperature` / `Uptime` | Show or hide an item |
| `System Stats: Toggle Toolbar Icon` | Show or hide the toolbar button |

Changes made from the menus are saved to your settings.

## Settings

Change these in the **Installed** tab of the Plugins pane (⚙ next to System Stats).

| Key | Default | Description |
| --- | --- | --- |
| `lumideStats.enableCpu` | `true` | Show CPU usage |
| `lumideStats.enableRam` | `true` | Show memory usage |
| `lumideStats.enableDisk` | `true` | Show free disk space |
| `lumideStats.enableNetwork` | `true` | Show network rates |
| `lumideStats.enableBattery` | `true` | Show the battery (only on machines with one) |
| `lumideStats.enableThermal` | `true` | Show CPU temperature (only where a sensor is available) |
| `lumideStats.enableUptime` | `false` | Show the session uptime |
| `lumideStats.compactCpu` … `compactUptime` | `true` | Show only the icon and value. Turn off to add a label, e.g. `CPU 42%` or `RAM 8.0 GB / 16 GB` |
| `lumideStats.useFahrenheit` | `false` | Show temperatures in °F |
| `lumideStats.updateIntervalSeconds` | `2` | Refresh interval, 1–60 seconds |
| `lumideStats.batterySaverMode` | `true` | Refresh every 10 seconds or slower on battery power |
| `lumideStats.priorityBase` | `1000` | Status bar priority. Change it to move the items |
| `lumideStats.showTopBarIcon` | `true` | Show the System Stats button in the toolbar |

Disk space is read at most every 30 seconds and the battery every 15 seconds. Hidden metrics aren't read, except the battery state, which Battery Saver needs.

## Platform support

| Metric | Linux | macOS | Windows |
| --- | --- | --- | --- |
| CPU | `/proc/stat` | Mach host statistics | `GetSystemTimes` |
| Memory | `/proc/meminfo` | `vm_stat`, `sysctl` | `GlobalMemoryStatusEx` |
| Disk | `df` | `df` | `GetDiskFreeSpaceExW` |
| Network | `/proc/net/dev`, `/proc/net/route` | `route`, `netstat` | `netstat -e` |
| Battery | `/sys/class/power_supply` | `pmset` | `GetSystemPowerStatus` |
| CPU temperature | `/sys/class/hwmon`, `/sys/class/thermal` | SMC (read-only) | Not available |
| Top processes | `ps` | `ps` | Not available |

- **Windows**: CPU temperature is only exposed to administrators, so the item stays hidden.
- **Linux**: Lumide doesn't support webviews on Linux yet, so **Show Dashboard** writes the report to the Output pane instead.
- **Network** counts the interface that holds the default route. With a VPN, that is usually the VPN interface.

## Permissions

The plugin only reads system information. It doesn't write files, change system settings, or make network requests. `plugin.yaml` lists what it reads:

- **Files (Linux)**: `/proc/stat`, `/proc/loadavg`, `/proc/meminfo`, `/proc/net/dev`, `/proc/net/route`, and `/sys/class/hwmon`, `/sys/class/thermal`, `/sys/class/power_supply`.
- **Commands**: `df` and `ps` (Linux and macOS); `vm_stat`, `sysctl`, `route` and `pmset` (macOS); `netstat` (macOS and Windows). `ps` only runs while the dashboard is open.
- **System libraries**: CPU usage, load averages and the SMC on macOS, and kernel32 on Windows, are read through Dart FFI.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
