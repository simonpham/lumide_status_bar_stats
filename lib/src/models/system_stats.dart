import 'dart:convert';

import '../format.dart';

/// Severity of a metric, used to color its status bar item.
enum MetricLevel { normal, warning, critical }

/// One sample of every metric.
///
/// A metric is `null` when it can't be read on this machine (for example,
/// no battery, no temperature sensor, or a command that isn't available).
class SystemStatsSnapshot {
  final DateTime timestamp;
  final CpuStats? cpu;
  final RamStats? ram;
  final DiskStats? disk;
  final NetworkStats? network;
  final BatteryStats? battery;
  final ThermalStats? thermal;
  final SessionStats session;

  const SystemStatsSnapshot({
    required this.timestamp,
    required this.session,
    this.cpu,
    this.ram,
    this.disk,
    this.network,
    this.battery,
    this.thermal,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'cpu': cpu?.toJson(),
        'ram': ram?.toJson(),
        'disk': disk?.toJson(),
        'network': network?.toJson(),
        'battery': battery?.toJson(),
        'thermal': thermal?.toJson(),
        'session': session.toJson(),
      };

  String toFormattedJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

/// A process in the dashboard's "Top processes" lists.
class TopProcessInfo {
  final String name;
  final double cpuPercent;
  final int rssBytes;

  const TopProcessInfo({
    required this.name,
    required this.cpuPercent,
    required this.rssBytes,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'cpuPercent': cpuPercent,
        'rssBytes': rssBytes,
        'rss': formatBytes(rssBytes),
      };
}

/// 1, 5 and 15 minute load averages (macOS and Linux only).
class LoadAverage {
  final double one;
  final double five;
  final double fifteen;

  const LoadAverage(this.one, this.five, this.fifteen);

  @override
  String toString() => '${one.toStringAsFixed(2)}, ${five.toStringAsFixed(2)}, '
      '${fifteen.toStringAsFixed(2)}';

  Map<String, dynamic> toJson() => {'1m': one, '5m': five, '15m': fifteen};
}

/// CPU usage across all cores.
class CpuStats {
  final double usagePercent;
  final int coreCount;
  final LoadAverage? loadAverage;
  final List<TopProcessInfo> topProcesses;

  const CpuStats({
    required this.usagePercent,
    required this.coreCount,
    this.loadAverage,
    this.topProcesses = const [],
  });

  MetricLevel get level => usagePercent >= 90
      ? MetricLevel.critical
      : usagePercent >= 75
          ? MetricLevel.warning
          : MetricLevel.normal;

  Map<String, dynamic> toJson() => {
        'usagePercent': usagePercent,
        'coreCount': coreCount,
        'loadAverage': loadAverage?.toJson(),
        'topProcesses': topProcesses.map((p) => p.toJson()).toList(),
      };
}

/// Physical memory and swap.
class RamStats {
  final int totalBytes;
  final int usedBytes;
  final int? swapUsedBytes;
  final List<TopProcessInfo> topProcesses;

  const RamStats({
    required this.totalBytes,
    required this.usedBytes,
    this.swapUsedBytes,
    this.topProcesses = const [],
  });

  int get availableBytes => (totalBytes - usedBytes).clamp(0, totalBytes);

  double get usagePercent =>
      totalBytes > 0 ? (usedBytes / totalBytes * 100).clamp(0, 100) : 0;

  MetricLevel get level => usagePercent >= 90
      ? MetricLevel.critical
      : usagePercent >= 80
          ? MetricLevel.warning
          : MetricLevel.normal;

  RamStats withTopProcesses(List<TopProcessInfo> processes) => RamStats(
        totalBytes: totalBytes,
        usedBytes: usedBytes,
        swapUsedBytes: swapUsedBytes,
        topProcesses: processes,
      );

  Map<String, dynamic> toJson() => {
        'totalBytes': totalBytes,
        'usedBytes': usedBytes,
        'availableBytes': availableBytes,
        'usagePercent': usagePercent,
        'swapUsedBytes': swapUsedBytes,
        'used': formatBytes(usedBytes),
        'total': formatBytes(totalBytes),
        'available': formatBytes(availableBytes),
        'swapUsed': swapUsedBytes == null ? null : formatBytes(swapUsedBytes!),
        'topProcesses': topProcesses.map((p) => p.toJson()).toList(),
      };
}

/// Space on the volume that holds the system (`/`, or the system drive on
/// Windows).
class DiskStats {
  final String volume;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;

  const DiskStats({
    required this.volume,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
  });

  /// Percentage used, computed like `df` (used / (used + available)) so that
  /// blocks reserved for root don't count as free.
  double get usagePercent {
    final denominator = usedBytes + freeBytes;
    return denominator > 0 ? (usedBytes / denominator * 100).clamp(0, 100) : 0;
  }

  MetricLevel get level => usagePercent >= 95
      ? MetricLevel.critical
      : usagePercent >= 85
          ? MetricLevel.warning
          : MetricLevel.normal;

  Map<String, dynamic> toJson() => {
        'volume': volume,
        'totalBytes': totalBytes,
        'usedBytes': usedBytes,
        'freeBytes': freeBytes,
        'usagePercent': usagePercent,
        'total': formatBytes(totalBytes),
        'free': formatBytes(freeBytes),
      };
}

/// Network throughput of the primary interface.
class NetworkStats {
  final String? interface;
  final double downloadBytesPerSec;
  final double uploadBytesPerSec;

  const NetworkStats({
    required this.downloadBytesPerSec,
    required this.uploadBytesPerSec,
    this.interface,
  });

  String get formattedDownload => formatRate(downloadBytesPerSec);
  String get formattedUpload => formatRate(uploadBytesPerSec);

  Map<String, dynamic> toJson() => {
        'interface': interface,
        'downloadBytesPerSec': downloadBytesPerSec,
        'uploadBytesPerSec': uploadBytesPerSec,
        'download': formattedDownload,
        'upload': formattedUpload,
      };
}

/// Whether the battery is charging, discharging, or plugged in but idle.
enum BatteryState { charging, discharging, full, notCharging, unknown }

class BatteryStats {
  final int levelPercent;
  final BatteryState state;

  /// Estimated minutes until empty (discharging) or full (charging).
  final int? timeRemainingMinutes;

  const BatteryStats({
    required this.levelPercent,
    required this.state,
    this.timeRemainingMinutes,
  });

  bool get isCharging => state == BatteryState.charging;

  /// True when the machine runs on battery power.
  bool get isOnBattery => state == BatteryState.discharging;

  String get stateLabel => switch (state) {
        BatteryState.charging => 'Charging',
        BatteryState.discharging => 'On battery',
        BatteryState.full => 'Fully charged',
        BatteryState.notCharging => 'Plugged in, not charging',
        BatteryState.unknown => 'Unknown',
      };

  MetricLevel get level => !isOnBattery
      ? MetricLevel.normal
      : levelPercent <= 10
          ? MetricLevel.critical
          : levelPercent <= 20
              ? MetricLevel.warning
              : MetricLevel.normal;

  Map<String, dynamic> toJson() => {
        'levelPercent': levelPercent,
        'state': state.name,
        'stateLabel': stateLabel,
        'timeRemainingMinutes': timeRemainingMinutes,
      };
}

/// CPU temperature, plus fan speed where the hardware reports it.
class ThermalStats {
  final double temperatureCelsius;

  /// Where the reading came from, for example `k10temp Tctl` or `SMC`.
  final String source;
  final int? fanRpm;

  const ThermalStats({
    required this.temperatureCelsius,
    required this.source,
    this.fanRpm,
  });

  double get temperatureFahrenheit => temperatureCelsius * 9 / 5 + 32;

  MetricLevel get level => temperatureCelsius >= 90
      ? MetricLevel.critical
      : temperatureCelsius >= 80
          ? MetricLevel.warning
          : MetricLevel.normal;

  String get status => switch (level) {
        MetricLevel.normal => 'Normal',
        MetricLevel.warning => 'Warm',
        MetricLevel.critical => 'Hot',
      };

  Map<String, dynamic> toJson() => {
        'temperatureCelsius': temperatureCelsius,
        'temperatureFahrenheit': temperatureFahrenheit,
        'status': status,
        'source': source,
        'fanRpm': fanRpm,
      };
}

/// How long Lumide has been running this plugin, and the plugin's memory.
class SessionStats {
  final Duration uptime;
  final int pluginRssBytes;

  const SessionStats({required this.uptime, required this.pluginRssBytes});

  Map<String, dynamic> toJson() => {
        'uptimeSeconds': uptime.inSeconds,
        'uptime': formatDuration(uptime),
        'pluginRssBytes': pluginRssBytes,
        'pluginRss': formatBytes(pluginRssBytes),
      };
}
