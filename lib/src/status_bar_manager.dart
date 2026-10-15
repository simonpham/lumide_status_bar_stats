import 'package:lumide_api/lumide_api.dart';

import 'config.dart';
import 'format.dart';
import 'models/system_stats.dart';

const _warningColor = '#FF9800';
const _criticalColor = '#F44336';

String? _colorFor(MetricLevel level) => switch (level) {
      MetricLevel.normal => null,
      MetricLevel.warning => _warningColor,
      MetricLevel.critical => _criticalColor,
    };

/// What one status bar item should show.
class StatusItemSpec {
  final StatusMetric metric;
  final String text;
  final String tooltip;
  final String icon;
  final String? color;
  final int priority;

  const StatusItemSpec({
    required this.metric,
    required this.text,
    required this.tooltip,
    required this.icon,
    required this.priority,
    this.color,
  });

  String get id => 'lumide.stats.${metric.name}';

  /// Command run when the item is clicked: opens the metric's menu.
  String get command => metricMenuCommand(metric);

  String get _stateKey => '$text|$tooltip|$icon|$color|$priority|$command';
}

/// Command id of the per-metric menu, e.g. `lumide-stats.showCpuMenu`.
String metricMenuCommand(StatusMetric metric) =>
    'lumide-stats.show${metric.settingSuffix}Menu';

/// Builds the status bar items for [snapshot]. Metrics that are disabled or
/// couldn't be read get no item.
List<StatusItemSpec> buildStatusItems(
  SystemStatsSnapshot snapshot,
  LumideStatsConfig config,
) {
  final items = <StatusItemSpec>[];
  const clickHint = 'Click for options';

  void add(
    StatusMetric metric, {
    required String compact,
    required String standard,
    required String tooltip,
    String? icon,
    MetricLevel level = MetricLevel.normal,
  }) {
    if (!config.isEnabled(metric)) return;
    items.add(
      StatusItemSpec(
        metric: metric,
        text: config.isCompact(metric) ? compact : standard,
        tooltip: '$tooltip\n\n$clickHint',
        icon: icon ?? metric.icon,
        color: _colorFor(level),
        // Lumide places higher priorities farther from the center.
        priority: config.priorityBase - metric.index,
      ),
    );
  }

  final cpu = snapshot.cpu;
  if (cpu != null) {
    final usage = formatPercent(cpu.usagePercent);
    add(
      StatusMetric.cpu,
      compact: usage,
      standard: 'CPU $usage',
      level: cpu.level,
      tooltip: [
        'CPU: ${cpu.usagePercent.toStringAsFixed(1)}% of ${cpu.coreCount} cores',
        if (cpu.loadAverage != null) 'Load average: ${cpu.loadAverage}',
      ].join('\n'),
    );
  }

  final ram = snapshot.ram;
  if (ram != null) {
    final usage = formatPercent(ram.usagePercent);
    add(
      StatusMetric.ram,
      compact: usage,
      standard:
          'RAM ${formatBytes(ram.usedBytes)} / ${formatBytes(ram.totalBytes)}',
      level: ram.level,
      tooltip: [
        'Memory: $usage used',
        'Used: ${formatBytes(ram.usedBytes)} of ${formatBytes(ram.totalBytes)}',
        'Available: ${formatBytes(ram.availableBytes)}',
        if (ram.swapUsedBytes != null)
          'Swap used: ${formatBytes(ram.swapUsedBytes!)}',
      ].join('\n'),
    );
  }

  final disk = snapshot.disk;
  if (disk != null) {
    final free = formatBytes(disk.freeBytes);
    add(
      StatusMetric.disk,
      compact: free,
      standard: 'Disk $free free',
      level: disk.level,
      tooltip: [
        'Disk (${disk.volume}): ${formatPercent(disk.usagePercent)} used',
        'Free: $free of ${formatBytes(disk.totalBytes)}',
      ].join('\n'),
    );
  }

  final network = snapshot.network;
  if (network != null) {
    final rates = '↓${network.formattedDownload} ↑${network.formattedUpload}';
    add(
      StatusMetric.network,
      compact: rates,
      standard: 'Net $rates',
      tooltip: [
        'Network${network.interface == null ? '' : ' (${network.interface})'}',
        'Download: ${network.formattedDownload}',
        'Upload: ${network.formattedUpload}',
      ].join('\n'),
    );
  }

  final battery = snapshot.battery;
  if (battery != null) {
    final level = '${battery.levelPercent}%';
    final minutes = battery.timeRemainingMinutes;
    add(
      StatusMetric.battery,
      compact: level,
      standard:
          battery.isCharging ? 'Battery $level, charging' : 'Battery $level',
      icon: battery.isCharging ? 'battery-charging' : 'battery',
      level: battery.level,
      tooltip: [
        'Battery: $level',
        battery.stateLabel,
        if (minutes != null)
          battery.isCharging
              ? 'Full in ${formatMinutes(minutes)}'
              : '${formatMinutes(minutes)} remaining',
      ].join('\n'),
    );
  }

  final thermal = snapshot.thermal;
  if (thermal != null) {
    final temperature = formatTemperature(
      thermal.temperatureCelsius,
      fahrenheit: config.useFahrenheit,
    );
    add(
      StatusMetric.thermal,
      compact: temperature,
      standard: 'CPU $temperature',
      level: thermal.level,
      tooltip: [
        'CPU temperature: $temperature (${thermal.status})',
        'Sensor: ${thermal.source}',
        if (thermal.fanRpm != null) 'Fan: ${thermal.fanRpm} RPM',
      ].join('\n'),
    );
  }

  final uptime = formatDuration(snapshot.session.uptime);
  add(
    StatusMetric.uptime,
    compact: uptime,
    standard: 'Uptime $uptime',
    tooltip: [
      'Lumide session: $uptime',
      'Plugin memory: ${formatBytes(snapshot.session.pluginRssBytes)}',
    ].join('\n'),
  );

  return items;
}

/// Creates, updates and removes this plugin's status bar items.
class StatusBarManager {
  StatusBarManager(this._statusBar, this._config);

  final LumideStatusBar _statusBar;
  final LumideStatsConfig _config;
  final Map<String, String> _shown = {};

  /// Shows [snapshot]. Only items whose content changed are sent to Lumide.
  Future<void> update(SystemStatsSnapshot snapshot) async {
    final items = buildStatusItems(snapshot, _config);
    final wanted = {for (final item in items) item.id};

    for (final id in _shown.keys.toList()) {
      if (!wanted.contains(id)) await _dispose(id);
    }

    for (final item in items) {
      final state = item._stateKey;
      if (_shown[item.id] == state) continue;
      // Creating again replaces the item. Unlike an update, it can also
      // clear the color and change the priority.
      await _statusBar.createItem(
        id: item.id,
        text: item.text,
        tooltip: item.tooltip,
        command: item.command,
        color: item.color,
        iconName: item.icon,
        alignment: 'right',
        priority: item.priority,
      );
      _shown[item.id] = state;
    }
  }

  Future<void> _dispose(String id) async {
    _shown.remove(id);
    try {
      await _statusBar.disposeItem(id);
    } catch (_) {}
  }

  /// Removes every item.
  Future<void> disposeAll() async {
    for (final id in _shown.keys.toList()) {
      await _dispose(id);
    }
  }
}
