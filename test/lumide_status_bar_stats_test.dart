import 'dart:io';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_status_bar_stats/lumide_status_bar_stats.dart';
import 'package:test/test.dart';

void main() {
  group('Lumide Plugin Manifest Validation', () {
    test('plugin.yaml exists and parses cleanly with LumideManifest', () async {
      final file = File('plugin.yaml');
      expect(await file.exists(), isTrue);

      final yamlContent = await file.readAsString();
      final manifest = LumideManifest.fromYaml(yamlContent);

      expect(manifest.id, equals('com.lumide.plugin.status-bar-stats'));
      expect(manifest.name, equals('Lumide Status Bar System Monitor'));
      expect(manifest.version, equals('1.0.0'));
      expect(manifest.entryPoint, equals('bin/main.dart'));
      expect(manifest.activationEvents, contains('onStartup'));
      expect(manifest.commands.length, equals(9));
      expect(manifest.configuration.length, equals(19));
      expect(manifest.keybindings.length, equals(2));
      expect(manifest.permissions, isNotEmpty);
    });
  });

  group('SystemStatsCollector Tests', () {
    final collector = SystemStatsCollector();

    test(
      'collect returns non-null SystemStatsSnapshot with all metrics',
      () async {
        final snapshot = await collector.collect();

        expect(snapshot, isNotNull);
        expect(snapshot.timestamp, isNotNull);
        expect(snapshot.cpu.coreCount, greaterThan(0));
        expect(snapshot.cpu.usagePercent, greaterThanOrEqualTo(0.0));
        expect(snapshot.ram.totalMb, greaterThan(0.0));
        expect(snapshot.ram.usagePercent, greaterThanOrEqualTo(0.0));
        expect(snapshot.disk.totalGb, greaterThan(0.0));
        expect(snapshot.disk.freeGb, greaterThanOrEqualTo(0.0));
        expect(snapshot.network, isNotNull);
        expect(snapshot.battery, isNotNull);
        expect(snapshot.thermal.temperatureCelsius, greaterThan(0.0));
        expect(snapshot.session.uptime.inSeconds, greaterThanOrEqualTo(0));
      },
    );

    test('snapshot JSON serialization works correctly', () async {
      final snapshot = await collector.collect();
      final jsonMap = snapshot.toJson();

      expect(jsonMap, contains('timestamp'));
      expect(jsonMap, contains('cpu'));
      expect(jsonMap, contains('ram'));
      expect(jsonMap, contains('disk'));
      expect(jsonMap, contains('network'));
      expect(jsonMap, contains('battery'));
      expect(jsonMap, contains('thermal'));
      expect(jsonMap, contains('session'));

      final formattedJson = snapshot.toFormattedJson();
      expect(formattedJson, contains('"usagePercent"'));
    });
  });

  group('LumideStatsConfig Tests', () {
    test('default configuration has correct initial values', () {
      final config = LumideStatsConfig();

      expect(config.updateIntervalSeconds, equals(2));
      expect(config.temperatureUnit, equals('celsius'));
      expect(config.useFahrenheit, isFalse);
      expect(config.compactMode, isTrue);
      expect(config.batterySaverMode, isTrue);
      expect(config.enabledMetrics, contains('cpu'));
      expect(config.enabledMetrics, contains('ram'));
      expect(config.enabledMetrics, contains('disk'));
      expect(config.enabledMetrics, contains('network'));
      expect(config.enabledMetrics, contains('battery'));
      expect(config.enabledMetrics, contains('thermal'));
      expect(config.enabledMetrics, contains('uptime'));
    });

    test(
      'updateFromMap modifies configuration parameters via boolean switches',
      () {
        final config = LumideStatsConfig();
        config.updateFromMap({
          'updateIntervalSeconds': 5,
          'useFahrenheit': true,
          'compactCpu': false,
          'enableCpu': true,
          'enableRam': true,
          'enableDisk': false,
          'enableNetwork': false,
          'enableBattery': false,
          'enableThermal': false,
          'enableUptime': false,
        });

        expect(config.updateIntervalSeconds, equals(5));
        expect(config.useFahrenheit, isTrue);
        expect(config.temperatureUnit, equals('fahrenheit'));
        expect(config.isCompact('cpu'), isFalse);
        expect(config.enabledMetrics.length, equals(2));
        expect(config.enabledMetrics, contains('cpu'));
        expect(config.enabledMetrics, contains('ram'));
        expect(config.enabledMetrics, isNot(contains('disk')));
      },
    );
  });

  group('Metric Models Edge Case Tests', () {
    test('CpuStats thresholds evaluate correctly', () {
      final normalCpu = CpuStats(
        usagePercent: 30.0,
        load1m: 1.0,
        load5m: 1.0,
        load15m: 1.0,
        coreCount: 8,
      );
      final highCpu = CpuStats(
        usagePercent: 80.0,
        load1m: 6.4,
        load5m: 5.0,
        load15m: 4.0,
        coreCount: 8,
      );
      final critCpu = CpuStats(
        usagePercent: 95.0,
        load1m: 7.8,
        load5m: 7.0,
        load15m: 6.5,
        coreCount: 8,
      );

      expect(normalCpu.isHigh, isFalse);
      expect(normalCpu.isCritical, isFalse);
      expect(highCpu.isHigh, isTrue);
      expect(highCpu.isCritical, isFalse);
      expect(critCpu.isHigh, isTrue);
      expect(critCpu.isCritical, isTrue);
    });

    test('ThermalStats temperature conversions and threshold checks', () {
      final thermal = ThermalStats(
        temperatureCelsius: 100.0,
        status: 'Critical',
      );

      expect(thermal.temperatureFahrenheit, equals(212.0));
      expect(thermal.isHigh, isTrue);
      expect(thermal.isCritical, isTrue);
    });

    test('NetworkStats formatting works for B/s, KB/s, and MB/s', () {
      final netB = NetworkStats(
        downloadBytesPerSec: 500,
        uploadBytesPerSec: 200,
        totalBytesDown: 5000,
        totalBytesUp: 2000,
      );
      final netKB = NetworkStats(
        downloadBytesPerSec: 150000,
        uploadBytesPerSec: 50000,
        totalBytesDown: 1500000,
        totalBytesUp: 500000,
      );
      final netMB = NetworkStats(
        downloadBytesPerSec: 2500000,
        uploadBytesPerSec: 1200000,
        totalBytesDown: 25000000,
        totalBytesUp: 12000000,
      );

      expect(netB.formattedDownload, equals('500 B/s'));
      expect(netKB.formattedDownload, equals('146 KB/s'));
      expect(netMB.formattedDownload, equals('2.4 MB/s'));
    });

    test(
      'QuickPickItem payload serialization matches lumide_flutter pattern',
      () {
        final item = const QuickPickItem(
          label: 'System Dashboard',
          description: 'View full telemetry',
          payload: 'dashboard',
        );
        final jsonMap = item.toJson();

        expect(jsonMap['label'], equals('System Dashboard'));
        expect(jsonMap['payload'], equals('dashboard'));

        final restoredItem = QuickPickItem.fromJson(jsonMap);
        expect(restoredItem.label, equals('System Dashboard'));
        expect(restoredItem.payload, equals('dashboard'));
      },
    );
  });
}
