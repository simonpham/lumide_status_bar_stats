## 1.0.1

### ⚡️ Performance

- Read disk space through the system library instead of running `df`. On Linux, the status bar items no longer start any processes.
- On macOS, read memory, swap and network counters through the system libraries instead of running `vm_stat`, `sysctl` and `netstat` on every refresh: about 6 commands a minute instead of about 100 at the default 2-second refresh.
- On Windows, read network counters of the connected network adapters through `GetIfTable2` instead of running `netstat -e` on every refresh.
- Read `/proc` and `/sys` files synchronously and remember where the battery is, for less work per refresh.

### 🐛 Bug Fixes

- Kill commands that are still running when the plugin stops, so none are left behind, and kill timed-out commands with SIGKILL.
- Deactivate only once, and don't finish activating if Lumide stops the plugin while it starts.

## 1.0.0

### 🚀 New Features

- Show CPU, memory, disk, network, battery and CPU temperature in the status bar, plus an optional session uptime item.
- Color items orange or red when usage, temperature or battery level needs attention.
- Click an item to change its display style, hide it, or open the other options.
- Open a dashboard with live charts and top processes (macOS and Windows), or write a report to the Output pane.
- Refresh less often on battery power with Battery Saver.
- Configure every item from Lumide's plugin settings or the quick menu.
- Supports Linux, macOS (Intel and Apple Silicon) and Windows.
