import 'dart:convert';

/// Root container for a single snapshot of all system telemetry metrics
class SystemStatsSnapshot {
  final DateTime timestamp;
  final CpuStats cpu;
  final RamStats ram;
  final DiskStats disk;
  final NetworkStats network;
  final BatteryStats battery;
  final ThermalStats thermal;
  final SessionStats session;

  SystemStatsSnapshot({
    required this.timestamp,
    required this.cpu,
    required this.ram,
    required this.disk,
    required this.network,
    required this.battery,
    required this.thermal,
    required this.session,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'cpu': cpu.toJson(),
    'ram': ram.toJson(),
    'disk': disk.toJson(),
    'network': network.toJson(),
    'battery': battery.toJson(),
    'thermal': thermal.toJson(),
    'session': session.toJson(),
  };

  String toFormattedJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Top process entry info
class TopProcessInfo {
  final String name;
  final double cpuPercent;
  final double rssMb;

  TopProcessInfo({
    required this.name,
    required this.cpuPercent,
    required this.rssMb,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'cpuPercent': cpuPercent,
    'rssMb': rssMb,
  };

  factory TopProcessInfo.fromJson(Map<String, dynamic> json) => TopProcessInfo(
    name: json['name'] as String? ?? 'unknown',
    cpuPercent: (json['cpuPercent'] as num?)?.toDouble() ?? 0.0,
    rssMb: (json['rssMb'] as num?)?.toDouble() ?? 0.0,
  );
}

/// CPU load percentages and core counts
class CpuStats {
  final double usagePercent;
  final double load1m;
  final double load5m;
  final double load15m;
  final int coreCount;
  final List<TopProcessInfo> topProcesses;

  CpuStats({
    required this.usagePercent,
    required this.load1m,
    required this.load5m,
    required this.load15m,
    required this.coreCount,
    this.topProcesses = const [],
  });

  Map<String, dynamic> toJson() => {
    'usagePercent': usagePercent,
    'load1m': load1m,
    'load5m': load5m,
    'load15m': load15m,
    'coreCount': coreCount,
    'topProcesses': topProcesses.map((p) => p.toJson()).toList(),
  };

  bool get isHigh => usagePercent >= 75.0;
  bool get isCritical => usagePercent >= 90.0;
}

/// System RAM & Swap memory stats
class RamStats {
  final double usedMb;
  final double totalMb;
  final double freeMb;
  final double usagePercent;
  final double swapUsedMb;
  final List<TopProcessInfo> topProcesses;

  RamStats({
    required this.usedMb,
    required this.totalMb,
    required this.freeMb,
    required this.usagePercent,
    required this.swapUsedMb,
    this.topProcesses = const [],
  });

  double get usedGb => usedMb / 1024.0;
  double get totalGb => totalMb / 1024.0;
  double get freeGb => freeMb / 1024.0;

  Map<String, dynamic> toJson() => {
    'usedMb': usedMb,
    'totalMb': totalMb,
    'freeMb': freeMb,
    'usagePercent': usagePercent,
    'swapUsedMb': swapUsedMb,
    'topProcesses': topProcesses.map((p) => p.toJson()).toList(),
  };

  bool get isHigh => usagePercent >= 80.0;
  bool get isCritical => usagePercent >= 90.0;
}

/// Disk utilization and I/O speeds
class DiskStats {
  final double usedGb;
  final double totalGb;
  final double freeGb;
  final double usagePercent;
  final double readKbps;
  final double writeKbps;

  DiskStats({
    required this.usedGb,
    required this.totalGb,
    required this.freeGb,
    required this.usagePercent,
    required this.readKbps,
    required this.writeKbps,
  });

  Map<String, dynamic> toJson() => {
    'usedGb': usedGb,
    'totalGb': totalGb,
    'freeGb': freeGb,
    'usagePercent': usagePercent,
    'readKbps': readKbps,
    'writeKbps': writeKbps,
  };

  bool get isHigh => usagePercent >= 85.0;
}

/// Network transfer speeds and stats
class NetworkStats {
  final double downloadBytesPerSec;
  final double uploadBytesPerSec;
  final int totalBytesDown;
  final int totalBytesUp;

  NetworkStats({
    required this.downloadBytesPerSec,
    required this.uploadBytesPerSec,
    required this.totalBytesDown,
    required this.totalBytesUp,
  });

  String get formattedDownload {
    if (downloadBytesPerSec >= 1024 * 1024) {
      return '${(downloadBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (downloadBytesPerSec >= 1024) {
      return '${(downloadBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${downloadBytesPerSec.toStringAsFixed(0)} B/s';
  }

  String get formattedUpload {
    if (uploadBytesPerSec >= 1024 * 1024) {
      return '${(uploadBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (uploadBytesPerSec >= 1024) {
      return '${(uploadBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${uploadBytesPerSec.toStringAsFixed(0)} B/s';
  }

  Map<String, dynamic> toJson() => {
    'downloadBytesPerSec': downloadBytesPerSec,
    'uploadBytesPerSec': uploadBytesPerSec,
    'totalBytesDown': totalBytesDown,
    'totalBytesUp': totalBytesUp,
  };
}

/// Battery status and health
class BatteryStats {
  final int levelPercent;
  final bool isCharging;
  final bool isPresent;
  final int? timeRemainingMinutes;

  BatteryStats({
    required this.levelPercent,
    required this.isCharging,
    required this.isPresent,
    this.timeRemainingMinutes,
  });

  Map<String, dynamic> toJson() => {
    'levelPercent': levelPercent,
    'isCharging': isCharging,
    'isPresent': isPresent,
    'timeRemainingMinutes': timeRemainingMinutes,
  };

  bool get isLow => isPresent && !isCharging && levelPercent <= 20;
  bool get isCritical => isPresent && !isCharging && levelPercent <= 10;
}

/// Thermal sensors stats & Fan speed control monitoring (aligned with macOS Stats)
class ThermalStats {
  final double temperatureCelsius;
  final String status;
  final int fanRpm;
  final int fanCount;
  final String fanMode;

  ThermalStats({
    required this.temperatureCelsius,
    required this.status,
    this.fanRpm = 0,
    this.fanCount = 1,
    this.fanMode = 'Auto',
  });

  double get temperatureFahrenheit => (temperatureCelsius * 9 / 5) + 32;

  Map<String, dynamic> toJson() => {
    'temperatureCelsius': temperatureCelsius,
    'temperatureFahrenheit': temperatureFahrenheit,
    'status': status,
    'fanRpm': fanRpm,
    'fanCount': fanCount,
    'fanMode': fanMode,
  };

  bool get isHigh => temperatureCelsius >= 75.0;
  bool get isCritical => temperatureCelsius >= 88.0;
}

/// Session & Plugin process stats
class SessionStats {
  final Duration uptime;
  final int pluginRssBytes;

  SessionStats({required this.uptime, required this.pluginRssBytes});

  String get formattedUptime {
    final hours = uptime.inHours.toString().padLeft(2, '0');
    final minutes = (uptime.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (uptime.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  double get rssMb => pluginRssBytes / (1024 * 1024);

  Map<String, dynamic> toJson() => {
    'uptimeSeconds': uptime.inSeconds,
    'formattedUptime': formattedUptime,
    'pluginRssMb': rssMb,
  };
}
