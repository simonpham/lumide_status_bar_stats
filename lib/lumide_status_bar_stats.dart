/// System stats (CPU, memory, disk, network, battery, temperature) in the
/// Lumide IDE status bar.
library;

export 'src/config.dart' show LumideStatsConfig, StatusMetric;
export 'src/dashboard.dart' show buildTextReport;
export 'src/format.dart';
export 'src/models/system_stats.dart';
export 'src/plugin.dart';
export 'src/system_stats_collector.dart' show Metric, SystemStatsCollector;
