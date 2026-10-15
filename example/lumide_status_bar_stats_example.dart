import 'package:lumide_status_bar_stats/lumide_status_bar_stats.dart';

/// Prints the metrics the plugin would show, without Lumide.
///
/// The plugin itself runs from `bin/main.dart`, started by Lumide.
Future<void> main() async {
  final collector = SystemStatsCollector();
  // Network rates need two samples.
  await collector.collect();
  await Future<void>.delayed(const Duration(seconds: 1));
  final snapshot = await collector.collect(includeProcesses: true);
  print(buildTextReport(snapshot));
}
