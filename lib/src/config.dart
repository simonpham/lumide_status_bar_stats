import 'package:lumide_api/lumide_api.dart';

/// Configuration & Settings Manager for Lumide Stats Plugin
class LumideStatsConfig {
  int updateIntervalSeconds;
  Set<String> enabledMetrics;
  bool useFahrenheit; // false = Celsius (°C), true = Fahrenheit (°F)
  bool compactMode;
  Map<String, String>
  metricDisplayStyles; // Per-metric: 'compact' or 'standard'
  bool batterySaverMode;
  int priorityBase; // Base priority for status bar grouping
  double highCpuThreshold;
  double highRamThreshold;
  bool showTopBarIcon;

  LumideStatsConfig({
    this.updateIntervalSeconds = 2,
    Set<String>? enabledMetrics,
    this.useFahrenheit = false,
    this.compactMode = true,
    Map<String, String>? metricDisplayStyles,
    this.batterySaverMode = true,
    this.priorityBase = 1000,
    this.highCpuThreshold = 75.0,
    this.highRamThreshold = 80.0,
    this.showTopBarIcon = true,
  }) : enabledMetrics =
           enabledMetrics ??
           {'cpu', 'ram', 'disk', 'network', 'battery', 'thermal', 'uptime'},
       metricDisplayStyles =
           metricDisplayStyles ??
           {
             'cpu': 'compact',
             'ram': 'compact',
             'disk': 'compact',
             'network': 'compact',
             'battery': 'compact',
             'thermal': 'compact',
             'uptime': 'compact',
           };

  /// Backward-compatible temperature unit string getter and setter
  String get temperatureUnit => useFahrenheit ? 'fahrenheit' : 'celsius';
  set temperatureUnit(String unit) =>
      useFahrenheit = (unit.toLowerCase() == 'fahrenheit');

  /// Check if a specific metric is set to compact mode
  bool isCompact(String metricKey) {
    final style = metricDisplayStyles[metricKey];
    if (style != null) {
      return style == 'compact';
    }
    return compactMode;
  }

  /// Toggle style between 'compact' and 'standard' for a metric
  void toggleMetricStyle(String metricKey) {
    final current =
        metricDisplayStyles[metricKey] ??
        (compactMode ? 'compact' : 'standard');
    metricDisplayStyles[metricKey] = current == 'compact'
        ? 'standard'
        : 'compact';
  }

  /// Update settings from workspace configuration dictionary
  void updateFromMap(Map<String, dynamic> map) {
    if (map.containsKey('updateIntervalSeconds')) {
      final val = map['updateIntervalSeconds'];
      if (val is int && val > 0) updateIntervalSeconds = val;
    }

    // Boolean switches for metric visibility
    final metricSwitches = {
      'enableCpu': 'cpu',
      'enableRam': 'ram',
      'enableDisk': 'disk',
      'enableNetwork': 'network',
      'enableBattery': 'battery',
      'enableThermal': 'thermal',
      'enableUptime': 'uptime',
    };

    for (final entry in metricSwitches.entries) {
      if (map.containsKey(entry.key)) {
        final enabled = map[entry.key] == true;
        if (enabled) {
          enabledMetrics.add(entry.value);
        } else {
          enabledMetrics.remove(entry.value);
        }
      }
    }

    // Boolean switches for per-metric compact mode
    final compactSwitches = {
      'compactCpu': 'cpu',
      'compactRam': 'ram',
      'compactDisk': 'disk',
      'compactNetwork': 'network',
      'compactBattery': 'battery',
      'compactThermal': 'thermal',
      'compactUptime': 'uptime',
    };

    for (final entry in compactSwitches.entries) {
      if (map.containsKey(entry.key)) {
        final isComp = map[entry.key] == true;
        metricDisplayStyles[entry.value] = isComp ? 'compact' : 'standard';
      }
    }

    // Array fallback for legacy configuration
    if (map.containsKey('enabledMetrics')) {
      final val = map['enabledMetrics'];
      if (val is List) {
        enabledMetrics = val.cast<String>().toSet();
      }
    }

    if (map.containsKey('useFahrenheit')) {
      final val = map['useFahrenheit'];
      if (val is bool) useFahrenheit = val;
    }
    if (map.containsKey('temperatureUnit')) {
      final val = map['temperatureUnit'].toString().toLowerCase();
      if (val == 'celsius' || val == 'fahrenheit') temperatureUnit = val;
    }
    if (map.containsKey('compactMode')) {
      final val = map['compactMode'];
      if (val is bool) compactMode = val;
    }
    if (map.containsKey('metricDisplayStyles')) {
      final val = map['metricDisplayStyles'];
      if (val is Map) {
        metricDisplayStyles = val.cast<String, String>();
      }
    }
    if (map.containsKey('batterySaverMode')) {
      final val = map['batterySaverMode'];
      if (val is bool) batterySaverMode = val;
    }
    if (map.containsKey('priorityBase')) {
      final val = map['priorityBase'];
      if (val is int) priorityBase = val;
    }
    if (map.containsKey('highCpuThreshold')) {
      final val = map['highCpuThreshold'];
      if (val is num) highCpuThreshold = val.toDouble();
    }
    if (map.containsKey('highRamThreshold')) {
      final val = map['highRamThreshold'];
      if (val is num) highRamThreshold = val.toDouble();
    }
    if (map.containsKey('showTopBarIcon')) {
      final val = map['showTopBarIcon'];
      if (val is bool) showTopBarIcon = val;
    }
  }

  /// Load settings from Lumide Workspace
  static Future<LumideStatsConfig> loadFromWorkspace(
    LumideWorkspace workspace,
  ) async {
    final config = LumideStatsConfig();
    try {
      final statsObj = await workspace.getConfiguration('lumideStats');
      if (statsObj is Map<String, dynamic>) {
        config.updateFromMap(statsObj);
      }
    } catch (_) {}
    return config;
  }
}
