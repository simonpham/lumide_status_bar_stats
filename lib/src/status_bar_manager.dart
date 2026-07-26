import 'package:lumide_api/lumide_api.dart';

import 'config.dart';
import 'models/system_stats.dart';

/// Status Bar Manager handles creating, updating, and disposing Lumide IDE status bar items.
class StatusBarManager {
  final LumideStatusBar _statusBar;
  final LumideStatsConfig _config;
  final Set<String> _createdItemIds = {};
  final Map<String, String> _lastItemStateCache = {};

  StatusBarManager(this._statusBar, this._config);

  /// Update all status bar items with the latest metrics snapshot
  Future<void> update(SystemStatsSnapshot snapshot) async {
    final activeMetrics = _config.enabledMetrics;
    final basePriority = _config.priorityBase;

    // Ensure any legacy main status bar item is cleaned up
    await _disposeItem('lumide.stats.main');

    // 2. Metric Items on the RIGHT

    // CPU Item (Priority: basePriority)
    if (activeMetrics.contains('cpu')) {
      final isCompact = _config.isCompact('cpu');
      await _upsertItem(
        id: 'lumide.stats.cpu',
        iconName: 'cpu',
        text: isCompact
            ? '${snapshot.cpu.usagePercent.toStringAsFixed(0)}%'
            : 'CPU ${snapshot.cpu.usagePercent.toStringAsFixed(0)}%',
        tooltip:
            'CPU Usage: ${snapshot.cpu.usagePercent}%\n'
            'Load Average: ${snapshot.cpu.load1m}, ${snapshot.cpu.load5m}, ${snapshot.cpu.load15m}\n'
            'Cores: ${snapshot.cpu.coreCount}\n'
            'Click to configure CPU settings',
        command: 'lumide-stats.showCpuMenu',
        color: snapshot.cpu.isCritical
            ? '#F44336'
            : (snapshot.cpu.isHigh ? '#FF9800' : null),
        priority: basePriority,
        alignment: 'right',
      );
    } else {
      await _disposeItem('lumide.stats.cpu');
    }

    // RAM Item (Priority: basePriority - 1)
    if (activeMetrics.contains('ram')) {
      final isCompact = _config.isCompact('ram');
      final ramText = isCompact
          ? '${snapshot.ram.usagePercent.toStringAsFixed(0)}%'
          : 'RAM ${snapshot.ram.usedGb.toStringAsFixed(1)}/${snapshot.ram.totalGb.toStringAsFixed(1)} GB (${snapshot.ram.usagePercent.toStringAsFixed(0)}%)';
      await _upsertItem(
        id: 'lumide.stats.ram',
        iconName: 'memory-stick',
        text: ramText,
        tooltip:
            'Memory Usage: ${snapshot.ram.usagePercent}%\n'
            'Used: ${snapshot.ram.usedGb.toStringAsFixed(2)} GB\n'
            'Free/Available: ${snapshot.ram.freeGb.toStringAsFixed(2)} GB\n'
            'Total: ${snapshot.ram.totalGb.toStringAsFixed(2)} GB\n'
            'Swap Used: ${snapshot.ram.swapUsedMb.toStringAsFixed(0)} MB\n'
            'Click to configure RAM settings',
        command: 'lumide-stats.showRamMenu',
        color: snapshot.ram.isCritical
            ? '#F44336'
            : (snapshot.ram.isHigh ? '#FF9800' : null),
        priority: basePriority - 1,
        alignment: 'right',
      );
    } else {
      await _disposeItem('lumide.stats.ram');
    }

    // Disk Item (Priority: basePriority - 2)
    if (activeMetrics.contains('disk')) {
      final isCompact = _config.isCompact('disk');
      final diskText = isCompact
          ? '${snapshot.disk.freeGb.toStringAsFixed(0)}G'
          : 'Disk ${snapshot.disk.freeGb.toStringAsFixed(1)} GB free (${(100 - snapshot.disk.usagePercent).toStringAsFixed(0)}%)';
      await _upsertItem(
        id: 'lumide.stats.disk',
        iconName: 'hard-drive',
        text: diskText,
        tooltip:
            'Disk Space: ${snapshot.disk.usagePercent}% used\n'
            'Free Space: ${snapshot.disk.freeGb.toStringAsFixed(1)} GB\n'
            'Used Space: ${snapshot.disk.usedGb.toStringAsFixed(1)} GB\n'
            'Total Capacity: ${snapshot.disk.totalGb.toStringAsFixed(1)} GB\n'
            'Click to configure Disk settings',
        command: 'lumide-stats.showDiskMenu',
        color: snapshot.disk.isHigh ? '#FF9800' : null,
        priority: basePriority - 2,
        alignment: 'right',
      );
    } else {
      await _disposeItem('lumide.stats.disk');
    }

    // Network Item (Priority: basePriority - 3)
    if (activeMetrics.contains('network')) {
      final isCompact = _config.isCompact('network');
      final netText = isCompact
          ? '↓${snapshot.network.formattedDownload}  ↑${snapshot.network.formattedUpload}'
          : 'Net ↓${snapshot.network.formattedDownload}  ↑${snapshot.network.formattedUpload}';
      await _upsertItem(
        id: 'lumide.stats.network',
        iconName: 'activity',
        text: netText,
        tooltip:
            'Network Traffic:\n'
            'Download Rate: ${snapshot.network.formattedDownload}\n'
            'Upload Rate: ${snapshot.network.formattedUpload}\n'
            'Click to configure Network settings',
        command: 'lumide-stats.showNetworkMenu',
        color: null,
        priority: basePriority - 3,
        alignment: 'right',
      );
    } else {
      await _disposeItem('lumide.stats.network');
    }

    // Battery Item (Priority: basePriority - 4)
    if (activeMetrics.contains('battery') && snapshot.battery.isPresent) {
      final isCompact = _config.isCompact('battery');
      final iconName = snapshot.battery.isCharging
          ? 'battery-charging'
          : 'battery';
      final batText = isCompact
          ? '${snapshot.battery.levelPercent}%'
          : 'Battery ${snapshot.battery.levelPercent}%${snapshot.battery.isCharging ? ' (Charging)' : ''}';
      final timeRemStr = snapshot.battery.timeRemainingMinutes != null
          ? '\nTime Remaining: ${snapshot.battery.timeRemainingMinutes! ~/ 60}h ${snapshot.battery.timeRemainingMinutes! % 60}m'
          : '';
      await _upsertItem(
        id: 'lumide.stats.battery',
        iconName: iconName,
        text: batText,
        tooltip:
            'Battery Level: ${snapshot.battery.levelPercent}%\n'
            'Power Source: ${snapshot.battery.isCharging ? "AC Power (Charging)" : "Battery Power"}'
            '$timeRemStr\n'
            'Click to configure Battery settings',
        command: 'lumide-stats.showBatteryMenu',
        color: snapshot.battery.isCritical
            ? '#F44336'
            : (snapshot.battery.isLow ? '#FF9800' : null),
        priority: basePriority - 4,
        alignment: 'right',
      );
    } else {
      await _disposeItem('lumide.stats.battery');
    }

    // Thermal Item (Priority: basePriority - 5)
    if (activeMetrics.contains('thermal')) {
      final isCompact = _config.isCompact('thermal');
      final isFahr = _config.temperatureUnit == 'fahrenheit';
      final tempVal = isFahr
          ? snapshot.thermal.temperatureFahrenheit.toStringAsFixed(0)
          : snapshot.thermal.temperatureCelsius.toStringAsFixed(0);
      final unitStr = isFahr ? '°F' : '°C';
      final tempText = isCompact ? '$tempVal$unitStr' : 'Temp $tempVal$unitStr';

      await _upsertItem(
        id: 'lumide.stats.thermal',
        iconName: 'thermometer',
        text: tempText,
        tooltip:
            'Average CPU Temp: ${snapshot.thermal.temperatureCelsius}°C / ${snapshot.thermal.temperatureFahrenheit.toStringAsFixed(1)}°F\n'
            'Fan Speed: ${snapshot.thermal.fanRpm > 0 ? "${snapshot.thermal.fanRpm} RPM" : "Auto (${snapshot.thermal.status})"}\n'
            'Click to configure Thermal & Fan settings',
        command: 'lumide-stats.showThermalMenu',
        color: snapshot.thermal.isCritical
            ? '#F44336'
            : (snapshot.thermal.isHigh ? '#FF9800' : null),
        priority: basePriority - 5,
        alignment: 'right',
      );
    } else {
      await _disposeItem('lumide.stats.thermal');
    }

    // Uptime Item (Priority: basePriority - 6)
    if (activeMetrics.contains('uptime')) {
      final isCompact = _config.isCompact('uptime');
      final uptimeText = isCompact
          ? snapshot.session.formattedUptime
          : 'Uptime ${snapshot.session.formattedUptime}';

      await _upsertItem(
        id: 'lumide.stats.uptime',
        iconName: 'timer',
        text: uptimeText,
        tooltip:
            'Lumide IDE Session:\n'
            'Uptime: ${snapshot.session.formattedUptime}\n'
            'Plugin RSS Memory: ${snapshot.session.rssMb.toStringAsFixed(1)} MB\n'
            'Click to configure Session settings',
        command: 'lumide-stats.showUptimeMenu',
        color: null,
        priority: basePriority - 6,
        alignment: 'right',
      );
    } else {
      await _disposeItem('lumide.stats.uptime');
    }
  }

  Future<void> _upsertItem({
    required String id,
    required String text,
    required String tooltip,
    required String command,
    required int priority,
    required String alignment,
    String? color,
    String? iconName,
  }) async {
    final stateKey =
        '$text|$color|$tooltip|$priority|$iconName|$command|$alignment';

    // Deduplicate RPC calls if state hasn't changed since last tick
    if (_lastItemStateCache[id] == stateKey) {
      return;
    }

    if (_createdItemIds.contains(id)) {
      await _statusBar.updateItem(
        id,
        text: text,
        tooltip: tooltip,
        command: command,
        color: color,
        iconName: iconName,
      );
    } else {
      await _statusBar.createItem(
        id: id,
        text: text,
        tooltip: tooltip,
        command: command,
        color: color,
        priority: priority,
        iconName: iconName,
        alignment: alignment,
      );
      _createdItemIds.add(id);
    }
    _lastItemStateCache[id] = stateKey;
  }

  Future<void> _disposeItem(String id) async {
    if (_createdItemIds.contains(id)) {
      await _statusBar.disposeItem(id);
      _createdItemIds.remove(id);
      _lastItemStateCache.remove(id);
    }
  }

  /// Clean up all status bar items
  Future<void> disposeAll() async {
    for (final id in _createdItemIds.toList()) {
      await _statusBar.disposeItem(id);
    }
    _createdItemIds.clear();
    _lastItemStateCache.clear();
  }
}
