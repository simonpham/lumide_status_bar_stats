import 'package:lumide_api/lumide_api.dart';

/// A status bar metric that can be shown or hidden.
enum StatusMetric {
  cpu('Cpu', 'CPU', 'cpu'),
  ram('Ram', 'RAM', 'memory-stick'),
  disk('Disk', 'Disk', 'hard-drive'),
  network('Network', 'Network', 'arrow-down-up'),
  battery('Battery', 'Battery', 'battery'),
  thermal('Thermal', 'Temperature', 'thermometer'),
  uptime('Uptime', 'Uptime', 'timer');

  const StatusMetric(this.settingSuffix, this.label, this.icon);

  /// Suffix of the `lumideStats.enable*` and `lumideStats.compact*` settings.
  final String settingSuffix;
  final String label;
  final String icon;

  String get enableKey => '${LumideStatsConfig.prefix}.enable$settingSuffix';
  String get compactKey => '${LumideStatsConfig.prefix}.compact$settingSuffix';
}

/// Plugin settings, declared in `plugin.yaml` under `lumideStats.*`.
class LumideStatsConfig {
  static const prefix = 'lumideStats';
  static const intervalKey = '$prefix.updateIntervalSeconds';
  static const fahrenheitKey = '$prefix.useFahrenheit';
  static const priorityKey = '$prefix.priorityBase';
  static const batterySaverKey = '$prefix.batterySaverMode';
  static const toolbarIconKey = '$prefix.showTopBarIcon';

  static const minInterval = 1;
  static const maxInterval = 60;

  /// Refresh interval used on battery power when battery saver is on.
  static const batterySaverInterval = 10;

  int updateIntervalSeconds;
  final Set<StatusMetric> enabledMetrics;
  final Set<StatusMetric> compactMetrics;
  bool useFahrenheit;
  bool batterySaverMode;
  int priorityBase;
  bool showTopBarIcon;

  LumideStatsConfig({
    this.updateIntervalSeconds = 2,
    Set<StatusMetric>? enabledMetrics,
    Set<StatusMetric>? compactMetrics,
    this.useFahrenheit = false,
    this.batterySaverMode = true,
    this.priorityBase = 1000,
    this.showTopBarIcon = true,
  })  : enabledMetrics = enabledMetrics ??
            (StatusMetric.values.toSet()..remove(StatusMetric.uptime)),
        compactMetrics = compactMetrics ?? StatusMetric.values.toSet();

  /// Every setting key this plugin reads.
  static List<String> get allKeys => [
        intervalKey,
        fahrenheitKey,
        priorityKey,
        batterySaverKey,
        toolbarIconKey,
        for (final m in StatusMetric.values) ...[m.enableKey, m.compactKey],
      ];

  bool isEnabled(StatusMetric metric) => enabledMetrics.contains(metric);
  bool isCompact(StatusMetric metric) => compactMetrics.contains(metric);

  /// Applies settings keyed by their full name (e.g. `lumideStats.enableCpu`),
  /// as sent by `workspace.onDidChangeConfiguration`. Unknown keys and values
  /// of the wrong type are ignored.
  void apply(Map<String, Object?> settings) {
    final interval = settings[intervalKey];
    if (interval is num) {
      updateIntervalSeconds = interval.round().clamp(minInterval, maxInterval);
    }
    final fahrenheit = settings[fahrenheitKey];
    if (fahrenheit is bool) useFahrenheit = fahrenheit;
    final priority = settings[priorityKey];
    if (priority is num) priorityBase = priority.round();
    final saver = settings[batterySaverKey];
    if (saver is bool) batterySaverMode = saver;
    final toolbar = settings[toolbarIconKey];
    if (toolbar is bool) showTopBarIcon = toolbar;

    for (final metric in StatusMetric.values) {
      final enabled = settings[metric.enableKey];
      if (enabled is bool) {
        enabled ? enabledMetrics.add(metric) : enabledMetrics.remove(metric);
      }
      final compact = settings[metric.compactKey];
      if (compact is bool) {
        compact ? compactMetrics.add(metric) : compactMetrics.remove(metric);
      }
    }
  }

  /// Reads every setting from Lumide. Settings that can't be read keep their
  /// defaults.
  static Future<LumideStatsConfig> load(LumideWorkspace workspace) async {
    final config = LumideStatsConfig();
    final values = <String, Object?>{};
    await Future.wait(
      allKeys.map((key) async {
        try {
          values[key] = await workspace.getConfiguration(key);
        } catch (_) {}
      }),
    );
    config.apply(values);
    return config;
  }
}
