# Lumide IDE Status Bar System Monitor (`lumide_status_bar_stats`)

A powerful, real-time system stats monitor plugin for **[Lumide IDE](https://pub.dev/packages/lumide_api)** built using `lumide_api`.

Drawing inspiration from macOS **Stats** (`exelban/stats`) and Windows Taskbar Stats, this plugin displays live hardware metrics directly in the Lumide IDE status bar with color alerts, interactive QuickPick menus, diagnostic reports, and customizable settings.

---

## 🌟 Key Features

- ⚡ **CPU Utilization & Load**: Real-time CPU percentage, 1m / 5m / 15m load averages, core count.
- 🧠 **RAM / Memory Monitor**: Used & total RAM in GB, percentage used, free memory, swap usage.
- 💾 **Disk Space & Utilization**: Available free disk space on root volume, used space, total capacity.
- 🌐 **Network I/O Traffic**: Dynamic real-time download & upload speeds (`KB/s` / `MB/s`).
- 🔋 **Battery State & Health**: Battery percentage, charging/discharging state, estimated time remaining.
- 🌡️ **Thermal Sensor Readout**: Temperature monitoring in Celsius (°C) or Fahrenheit (°F) with warning states.
- ⏱️ **IDE Session Uptime**: Plugin uptime counter and plugin RSS memory footprint tracker.
- 🎨 **Dynamic Color Alerts**: Green (Normal), Orange (Warning > 75%), Red (Critical > 90%).
- 📊 **Detailed Diagnostics Dashboard**: Interactive modal popups with complete system hardware breakdown.
- 🖱️ **Clickable Status Bar Items**: Clicking any status bar item opens the Lumide QuickPick menu.
- 🔋 **Smart Battery Saver Mode**: Automatically slows down polling rate when running on battery power to conserve energy.

---

## 🚀 Quick Start & Installation

### 1. Add to Lumide IDE Plugins
Include `lumide_status_bar_stats` in your Lumide plugin configuration or build as a standalone Dart binary executable.

```yaml
dependencies:
  lumide_api: ^1.7.0
  lumide_status_bar_stats: ^1.0.0
```

### 2. Entry Point
The plugin entry point is located at `bin/main.dart`:

```dart
import 'package:lumide_status_bar_stats/lumide_status_bar_stats.dart';

void main() => LumideStatusBarStatsPlugin().run();
```

---

## 🎮 Interactive QuickPick Menus & Commands

Clicking **any status bar item** or triggering `lumide-stats.showQuickMenu` from the Command Palette opens the interactive QuickPick menu:

- 📊 **Show Detailed Dashboard**: View complete system & IDE diagnostic stats.
- ⚙️ **Configure Visible Metrics**: Enable or disable CPU, RAM, Disk, Network, Battery, Thermal, or Uptime items.
- ⏱️ **Set Refresh Interval**: Choose polling rate (1s, 2s, 5s, 10s, 30s).
- 🌡️ **Temperature Unit**: Toggle between Celsius (°C) and Fahrenheit (°F).
- 🏷️ **Display Style**: Toggle between Compact Icon Mode and Standard Text Labels.
- 🔋 **Battery Saver Mode**: Toggle auto-throttling on battery.
- 🔄 **Refresh Metrics Now**: Instantly re-sample hardware statistics.
- 📋 **Copy Diagnostics Report**: Generate formatted JSON report for troubleshooting.

---

## ⚙️ Configuration Settings

Customize behavior via Lumide Workspace Settings (`settings.json`):

```json
{
  "lumideStats.updateIntervalSeconds": 2,
  "lumideStats.enabledMetrics": ["cpu", "ram", "disk", "network", "battery", "thermal", "uptime"],
  "lumideStats.temperatureUnit": "celsius",
  "lumideStats.compactMode": false,
  "lumideStats.batterySaverMode": true
}
```

---

## 📐 Architecture & Project Structure

```
lumide_status_bar_stats/
├── bin/
│   └── main.dart                     # Executable entrypoint for Lumide IDE RPC runner
├── lib/
│   ├── lumide_status_bar_stats.dart  # Main library export
│   └── src/
│       ├── config.dart               # Settings & workspace configuration manager
│       ├── menu_handler.dart         # QuickPick popups, commands, & dashboard
│       ├── plugin.dart               # Core plugin class extending LumidePlugin
│       ├── status_bar_manager.dart   # Status bar items, colors, tooltips & priority
│       ├── system_stats_collector.dart# Cross-platform (macOS/Linux/Windows) stats engine
│       └── models/
│           └── system_stats.dart     # System metric data models & JSON serializers
├── lumide_manifest.json              # Official Lumide plugin manifest schema
├── example/
│   └── lumide_status_bar_stats_example.dart
└── test/
    └── lumide_status_bar_stats_test.dart
```

---

## 🧪 Testing

Run the automated test suite:

```bash
dart test
```

Run static analysis:

```bash
dart analyze
```

---

## 📄 License

MIT License. Developed for **Lumide IDE**.
