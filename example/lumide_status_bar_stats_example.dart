import 'package:lumide_status_bar_stats/lumide_status_bar_stats.dart';

void main() async {
  final collector = SystemStatsCollector();
  final snapshot = await collector.collect();

  print('=== Lumide Status Bar System Monitor Snapshot ===');
  print(
    'CPU Usage: ${snapshot.cpu.usagePercent}% (${snapshot.cpu.coreCount} Cores)',
  );
  print(
    'RAM Usage: ${snapshot.ram.usedGb.toStringAsFixed(1)} / ${snapshot.ram.totalGb.toStringAsFixed(1)} GB (${snapshot.ram.usagePercent}%)',
  );
  print(
    'Disk Free: ${snapshot.disk.freeGb.toStringAsFixed(1)} GB (${(100 - snapshot.disk.usagePercent).toStringAsFixed(0)}% free)',
  );
  print(
    'Network Speed: Download ${snapshot.network.formattedDownload} | Upload ${snapshot.network.formattedUpload}',
  );
  print(
    'Battery: ${snapshot.battery.levelPercent}% (Charging: ${snapshot.battery.isCharging})',
  );
  print(
    'Thermal: ${snapshot.thermal.temperatureCelsius}°C (${snapshot.thermal.status})',
  );
  print('Session Uptime: ${snapshot.session.formattedUptime}');
  print('Plugin RSS Memory: ${snapshot.session.rssMb.toStringAsFixed(1)} MB');
}
