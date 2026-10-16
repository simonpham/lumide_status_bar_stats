import 'dart:io';
import 'dart:typed_data';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_status_bar_stats/lumide_status_bar_stats.dart';
import 'package:lumide_status_bar_stats/src/command_runner.dart';
import 'package:lumide_status_bar_stats/src/dashboard.dart';
import 'package:lumide_status_bar_stats/src/menu_handler.dart';
import 'package:lumide_status_bar_stats/src/native/macos.dart';
import 'package:lumide_status_bar_stats/src/native/posix.dart';
import 'package:lumide_status_bar_stats/src/native/windows.dart';
import 'package:lumide_status_bar_stats/src/parsers.dart';
import 'package:lumide_status_bar_stats/src/status_bar_manager.dart';
import 'package:test/test.dart';

SystemStatsSnapshot _snapshot({
  CpuStats? cpu,
  RamStats? ram,
  DiskStats? disk,
  NetworkStats? network,
  BatteryStats? battery,
  ThermalStats? thermal,
}) => SystemStatsSnapshot(
  timestamp: DateTime(2026),
  cpu: cpu,
  ram: ram,
  disk: disk,
  network: network,
  battery: battery,
  thermal: thermal,
  session: const SessionStats(
    uptime: Duration(hours: 1, minutes: 5),
    pluginRssBytes: 50 << 20,
  ),
);

void main() {
  group('plugin.yaml', () {
    final manifest = LumideManifest.fromYaml(
      File('plugin.yaml').readAsStringSync(),
    );
    final pubspec = File('pubspec.yaml').readAsStringSync();

    test('matches the package', () {
      expect(manifest.id, 'lumide_status_bar_stats');
      expect(pubspec, contains('name: ${manifest.id}\n'));
      expect(pubspec, contains('version: ${manifest.version}\n'));
      expect(manifest.entryPoint, 'bin/main.dart');
      expect(manifest.activationEvents, contains('onStartup'));
    });

    test('declares exactly the settings the plugin reads', () {
      expect(
        manifest.configuration.map((p) => p.key).toSet(),
        LumideStatsConfig.allKeys.toSet(),
      );
    });

    test('defaults match LumideStatsConfig', () {
      final defaults = {
        for (final p in manifest.configuration) p.key: p.defaultValue,
      };
      final fromYaml = LumideStatsConfig()..apply(defaults);
      final config = LumideStatsConfig();
      expect(fromYaml.enabledMetrics, config.enabledMetrics);
      expect(fromYaml.compactMetrics, config.compactMetrics);
      expect(fromYaml.updateIntervalSeconds, config.updateIntervalSeconds);
      expect(fromYaml.useFahrenheit, config.useFahrenheit);
      expect(fromYaml.batterySaverMode, config.batterySaverMode);
      expect(fromYaml.priorityBase, config.priorityBase);
      expect(fromYaml.showTopBarIcon, config.showTopBarIcon);
    });

    test('contributes the toggle commands', () {
      final ids = manifest.commands.map((c) => c.id).toSet();
      for (final metric in StatusMetric.values) {
        expect(ids, contains(MenuHandler.toggleCommand(metric)));
      }
      expect(
        ids,
        containsAll([
          'lumide-stats.showQuickMenu',
          'lumide-stats.showDashboard',
          'lumide-stats.showReport',
          'lumide-stats.refresh',
          'lumide-stats.toggleTopBarIcon',
        ]),
      );
    });
  });

  group('format', () {
    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(150 * 1024), '150 KB');
      expect(formatBytes(1023.6 * 1024), '1.0 MB');
      expect(formatBytes(2.5 * (1 << 30)), '2.5 GB');
      expect(formatBytes(256 * (1 << 30)), '256 GB');
      expect(formatBytes(-5), '0 B');
    });

    test('formatRate', () {
      expect(formatRate(0), '0 B/s');
      expect(formatRate(150000), '146 KB/s');
      expect(formatRate(2500000), '2.4 MB/s');
    });

    test('formatPercent and formatTemperature', () {
      expect(formatPercent(42.4), '42%');
      expect(formatPercent(99.6), '100%');
      expect(formatTemperature(63.4), '63°C');
      expect(formatTemperature(100, fahrenheit: true), '212°F');
    });

    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 45)), '45s');
      expect(formatDuration(const Duration(minutes: 12, seconds: 3)), '12m');
      expect(formatDuration(const Duration(hours: 3, minutes: 5)), '3h 05m');
      expect(formatDuration(const Duration(days: 2, hours: 4)), '2d 4h');
      expect(formatDuration(const Duration(seconds: -1)), '0s');
    });

    test('formatMinutes', () {
      expect(formatMinutes(23), '23m');
      expect(formatMinutes(83), '1h 23m');
    });
  });

  group('Linux parsers', () {
    test('parseProcStat counts iowait as idle and all busy fields', () {
      final first = parseProcStat(
        'cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 1 2 3 4\n',
      )!;
      final second = parseProcStat('cpu  200 0 100 1000 100 0 0 0 0 0\n')!;
      expect(first.total, 1000);
      expect(first.idle, 850);
      // 400 ticks passed, 250 idle.
      expect(second.usageSince(first), closeTo(37.5, 0.001));
      expect(first.usageSince(second), isNull);
      expect(parseProcStat('intr 1 2 3'), isNull);
    });

    test('parseLoadAverage reads Linux and macOS formats', () {
      final linux = parseLoadAverage('0.96 0.76 0.57 2/1234 5678\n')!;
      expect([linux.one, linux.five, linux.fifteen], [0.96, 0.76, 0.57]);
      final mac = parseLoadAverage('{ 2.10 1.95 1.80 }\n')!;
      expect(mac.fifteen, 1.80);
      expect(parseLoadAverage('nope'), isNull);
    });

    test('parseMeminfo uses MemAvailable', () {
      final ram = parseMeminfo('''
MemTotal:       16000000 kB
MemFree:         1000000 kB
MemAvailable:    6000000 kB
Buffers:          200000 kB
Cached:          3000000 kB
SwapTotal:       2000000 kB
SwapFree:        1500000 kB
''')!;
      expect(ram.totalBytes, 16000000 * 1024);
      expect(ram.usedBytes, 10000000 * 1024);
      expect(ram.swapUsedBytes, 500000 * 1024);
      expect(ram.usagePercent, closeTo(62.5, 0.001));
    });

    test('parseMeminfo falls back without MemAvailable', () {
      final ram = parseMeminfo('''
MemTotal:       1000 kB
MemFree:         100 kB
Buffers:         100 kB
Cached:          200 kB
''')!;
      expect(ram.usedBytes, 600 * 1024);
      expect(ram.swapUsedBytes, isNull);
      expect(parseMeminfo(''), isNull);
    });

    const netDev = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 44002764  307944    0    0    0     0          0         0 44002764  307944    0    0    0     0       0          0
enp6s0: 5629415   20250    0  228    0     0          0      9438  2351315    9868    0    0    0     0       0          0
wlp5s0: 2709795341 2054436    0  691    0     0          0         0 181755965  789173    0   51    0     0       0          0
docker0: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0
''';

    test('parseProcNetDev sums physical interfaces by default', () {
      expect(
        parseProcNetDev(netDev),
        const NetCounters(5629415 + 2709795341, 2351315 + 181755965),
      );
    });

    test('parseProcNetDev filters to given interfaces', () {
      expect(
        parseProcNetDev(netDev, interfaces: {'wlp5s0'}),
        const NetCounters(2709795341, 181755965),
      );
      expect(parseProcNetDev(netDev, interfaces: {'eth9'}), isNull);
    });

    test('parseProcNetRouteDefaults', () {
      const route = '''
Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT
wlp5s0	00000000	0101A8C0	0003	0	0	600	00000000	0	0	0
wlp5s0	0001A8C0	00000000	0001	0	0	600	00FFFFFF	0	0	0
docker0	000011AC	00000000	0001	0	0	0	0000FFFF	0	0	0
''';
      expect(parseProcNetRouteDefaults(route), {'wlp5s0'});
      expect(parseProcNetRouteDefaults(''), isEmpty);
    });

    test('df output, reading columns from the right', () {
      final disk = parseDf('''
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/nvme0n1p6   465536672 172766504 269048696      40% /
''')!;
      expect(disk.volume, '/');
      expect(disk.totalBytes, 465536672 * 1024);
      expect(disk.freeBytes, 269048696 * 1024);
      // Reserved blocks don't count as free.
      expect(disk.usagePercent, closeTo(39.1, 0.1));
      expect(disk.level, MetricLevel.normal);

      final mac = parseDf('''
Filesystem     1024-blocks      Used Available Capacity  Mounted on
/dev/disk3s1s1   971350180  10912956 512391384     3%    /
''')!;
      expect(mac.usedBytes, 10912956 * 1024);
      expect(parseDf('df: /: No such file'), isNull);
    });

    test('battery status and time estimate', () {
      expect(
        parseSysfsBatteryStatus('Discharging\n'),
        BatteryState.discharging,
      );
      expect(parseSysfsBatteryStatus('Not charging'), BatteryState.notCharging);
      expect(parseSysfsBatteryStatus('Full'), BatteryState.full);
      expect(parseSysfsBatteryStatus('weird'), BatteryState.unknown);
      expect(
        estimateBatteryMinutes(
          state: BatteryState.discharging,
          now: 30000000,
          rate: 15000000,
        ),
        120,
      );
      expect(
        estimateBatteryMinutes(
          state: BatteryState.charging,
          now: 30000000,
          full: 45000000,
          rate: 30000000,
        ),
        30,
      );
      expect(
        estimateBatteryMinutes(state: BatteryState.full, now: 1, rate: 1),
        isNull,
      );
      expect(
        estimateBatteryMinutes(
          state: BatteryState.discharging,
          now: 1,
          rate: 0,
        ),
        isNull,
      );
    });

    test('pickCpuTemperature prefers the CPU package sensor', () {
      final sensors = [
        const LinuxTempSensor('nvme', 'Composite', 42.9),
        const LinuxTempSensor('amdgpu', 'edge', 49),
        const LinuxTempSensor('k10temp', 'Tccd1', 70),
        const LinuxTempSensor('k10temp', 'Tctl', 63.3),
        const LinuxTempSensor('acpitz', null, 30),
      ];
      expect(pickCpuTemperature(sensors)!.description, 'k10temp Tctl');
      expect(
        pickCpuTemperature([
          const LinuxTempSensor('acpitz', null, 30),
          const LinuxTempSensor('x86_pkg_temp', null, 55),
        ])!.chip,
        'x86_pkg_temp',
      );
      expect(
        pickCpuTemperature([
          const LinuxTempSensor('coretemp', 'Core 0', 50),
          const LinuxTempSensor('coretemp', 'Package id 0', 58),
        ])!.label,
        'Package id 0',
      );
      // Unrelated sensors only: report nothing rather than a GPU or SSD.
      expect(
        pickCpuTemperature([const LinuxTempSensor('nvme', 'Composite', 40)]),
        isNull,
      );
    });

    test('parseMilliCelsius', () {
      expect(parseMilliCelsius('63250\n'), 63.25);
      expect(parseMilliCelsius('0'), isNull);
      expect(parseMilliCelsius('-273000'), isNull);
      expect(parseMilliCelsius('x'), isNull);
    });
  });

  group('macOS parsers', () {
    test('parseVmStatUsedBytes matches Activity Monitor', () {
      const output = '''
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               12345.
Pages active:                            400000.
Pages inactive:                          380000.
Pages speculative:                        10000.
Pages throttled:                              0.
Pages wired down:                        150000.
Pages purgeable:                          20000.
"Translation faults":                 123456789.
Pages copy-on-write:                    1234567.
Anonymous pages:                         500000.
Pages occupied by compressor:             50000.
''';
      expect(
        parseVmStatUsedBytes(output),
        (500000 - 20000 + 150000 + 50000) * 16384,
      );
      expect(parseVmStatUsedBytes('garbage'), isNull);
    });

    test('parseSwapUsage', () {
      expect(
        parseSwapUsage(
          'total = 2048.00M  used = 1093.50M  free = 954.50M  (encrypted)',
        ),
        (1093.5 * (1 << 20)).round(),
      );
      expect(parseSwapUsage('total = 0.00M  used = 0.00M  free = 0.00M'), 0);
      expect(parseSwapUsage('used = 1.50G'), (1.5 * (1 << 30)).round());
      expect(parseSwapUsage(''), isNull);
    });

    test('parseRouteGetDefault and parseNetstatInterface', () {
      expect(
        parseRouteGetDefault('''
   route to: default
destination: default
    gateway: 192.168.1.1
  interface: en0
'''),
        'en0',
      );
      expect(parseRouteGetDefault('route: writing to routing socket'), isNull);

      const netstat = '''
Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
en0        1500  <Link#11>   a4:83:e7:00:00:01  3446453     0 3965823094  1505453     0  267296005     0
en0        1500  192.168.1     192.168.1.20     3446453     - 3965823094  1505453     -  267296005     -
utun4      1380  <Link#20>                          100     0      20000       50     0       9000     0
''';
      expect(
        parseNetstatInterface(netstat, 'en0'),
        const NetCounters(3965823094, 267296005),
      );
      expect(
        parseNetstatInterface(netstat, 'utun4'),
        const NetCounters(20000, 9000),
      );
      expect(parseNetstatInterface(netstat, 'en1'), isNull);
    });

    test('parsePmsetBatt', () {
      final discharging = parsePmsetBatt('''
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=4653155)	85%; discharging; 3:12 remaining present: true
''')!;
      expect(discharging.levelPercent, 85);
      expect(discharging.state, BatteryState.discharging);
      expect(discharging.isOnBattery, isTrue);
      expect(discharging.timeRemainingMinutes, 192);

      final charging = parsePmsetBatt('''
Now drawing from 'AC Power'
 -InternalBattery-0 (id=4653155)	42%; charging; 1:05 remaining present: true
''')!;
      expect(charging.state, BatteryState.charging);
      expect(charging.isOnBattery, isFalse);

      final full = parsePmsetBatt('''
Now drawing from 'AC Power'
 -InternalBattery-0 (id=4653155)	100%; charged; 0:00 remaining present: true
''')!;
      expect(full.state, BatteryState.full);
      expect(full.timeRemainingMinutes, isNull);

      final noEstimate = parsePmsetBatt('''
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=4653155)	97%; discharging; (no estimate) present: true
''')!;
      expect(noEstimate.timeRemainingMinutes, isNull);

      final held = parsePmsetBatt('''
Now drawing from 'AC Power'
 -InternalBattery-0 (id=4653155)	80%; AC attached; not charging present: true
''')!;
      expect(held.state, BatteryState.notCharging);

      expect(parsePmsetBatt("Now drawing from 'AC Power'\n"), isNull);
    });

    test('decodeSmcValue', () {
      expect(decodeSmcValue('sp78', [0x3F, 0x80]), closeTo(63.5, 0.001));
      expect(decodeSmcValue('fpe2', [0x1F, 0x40]), 2000);
      // 55.5 as a little-endian float32.
      expect(decodeSmcValue('flt ', [0x00, 0x00, 0x5E, 0x42]), 55.5);
      expect(decodeSmcValue('ui8 ', [2]), 2);
      expect(decodeSmcValue('ui16', [0x01, 0x00]), 256);
      expect(decodeSmcValue('????', [1, 2]), isNull);
    });
  });

  group('other parsers', () {
    test('parseWindowsNetstatE ignores the localized label', () {
      const output = '''
Interface Statistics

                           Received            Sent

Bytes                    3285611542       304718227
Unicast packets             2919046         1532040
''';
      expect(
        parseWindowsNetstatE(output),
        const NetCounters(3285611542, 304718227),
      );
      expect(
        parseWindowsNetstatE(output.replaceFirst('Bytes', 'Octets')),
        const NetCounters(3285611542, 304718227),
      );
    });

    test('parsePs and topBy', () {
      final processes = parsePs('''
 12.5 204800 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
  0.0   1024 kworker/0:1
 50,0  10240 dart
garbage
''');
      expect(processes.map((p) => p.name), [
        'Google Chrome',
        'kworker/0:1',
        'dart',
      ]);
      expect(processes.last.cpuPercent, 50);
      expect(topBy(processes, (p) => p.cpuPercent).first.name, 'dart');
      expect(
        topBy(processes, (p) => p.rssBytes, count: 1).single.name,
        'Google Chrome',
      );
    });
  });

  group('LumideStatsConfig', () {
    test('defaults', () {
      final config = LumideStatsConfig();
      expect(config.updateIntervalSeconds, 2);
      expect(config.isEnabled(StatusMetric.cpu), isTrue);
      expect(config.isEnabled(StatusMetric.uptime), isFalse);
      expect(config.isCompact(StatusMetric.ram), isTrue);
    });

    test('apply reads full keys and ignores bad values', () {
      final config = LumideStatsConfig()
        ..apply({
          'lumideStats.updateIntervalSeconds': 500,
          'lumideStats.useFahrenheit': true,
          'lumideStats.enableDisk': false,
          'lumideStats.enableUptime': true,
          'lumideStats.compactRam': false,
          'lumideStats.priorityBase': 'high',
          'enableCpu': false,
        });
      expect(config.updateIntervalSeconds, LumideStatsConfig.maxInterval);
      expect(config.useFahrenheit, isTrue);
      expect(config.isEnabled(StatusMetric.disk), isFalse);
      expect(config.isEnabled(StatusMetric.uptime), isTrue);
      expect(config.isEnabled(StatusMetric.cpu), isTrue);
      expect(config.isCompact(StatusMetric.ram), isFalse);
      expect(config.priorityBase, 1000);

      config.apply({'lumideStats.updateIntervalSeconds': 0});
      expect(config.updateIntervalSeconds, LumideStatsConfig.minInterval);
    });
  });

  group('status bar items', () {
    final full = _snapshot(
      cpu: const CpuStats(
        usagePercent: 92.4,
        coreCount: 8,
        loadAverage: LoadAverage(1, 2, 3),
      ),
      ram: RamStats(totalBytes: 16 << 30, usedBytes: 8 << 30),
      disk: DiskStats(
        volume: '/',
        totalBytes: 500 << 30,
        usedBytes: 450 << 30,
        freeBytes: 50 << 30,
      ),
      network: const NetworkStats(
        downloadBytesPerSec: 2500000,
        uploadBytesPerSec: 1024,
      ),
      battery: const BatteryStats(
        levelPercent: 15,
        state: BatteryState.discharging,
        timeRemainingMinutes: 40,
      ),
      thermal: const ThermalStats(temperatureCelsius: 63, source: 'test'),
    );

    test('compact items with alert colors', () {
      final items = {
        for (final i in buildStatusItems(full, LumideStatsConfig()))
          i.metric: i,
      };
      expect(items.keys, isNot(contains(StatusMetric.uptime)));
      expect(items[StatusMetric.cpu]!.text, '92%');
      expect(items[StatusMetric.cpu]!.color, '#F44336');
      expect(items[StatusMetric.cpu]!.tooltip, contains('Load average'));
      expect(items[StatusMetric.ram]!.text, '50%');
      expect(items[StatusMetric.ram]!.color, isNull);
      expect(items[StatusMetric.disk]!.text, '50 GB');
      expect(items[StatusMetric.disk]!.color, '#FF9800');
      expect(items[StatusMetric.network]!.text, '↓2.4 MB/s ↑1.0 KB/s');
      expect(items[StatusMetric.battery]!.text, '15%');
      expect(items[StatusMetric.battery]!.color, '#FF9800');
      expect(items[StatusMetric.battery]!.tooltip, contains('40m remaining'));
      expect(items[StatusMetric.thermal]!.text, '63°C');
      expect(items[StatusMetric.cpu]!.command, 'lumide-stats.showCpuMenu');
      expect(items[StatusMetric.cpu]!.priority, 1000);
      expect(items[StatusMetric.ram]!.priority, 999);
    });

    test('labeled items, Fahrenheit and uptime', () {
      final config = LumideStatsConfig(useFahrenheit: true)
        ..compactMetrics.clear()
        ..enabledMetrics.add(StatusMetric.uptime);
      final items = {
        for (final i in buildStatusItems(full, config)) i.metric: i,
      };
      expect(items[StatusMetric.cpu]!.text, 'CPU 92%');
      expect(items[StatusMetric.ram]!.text, 'RAM 8.0 GB / 16 GB');
      expect(items[StatusMetric.disk]!.text, 'Disk 50 GB free');
      expect(items[StatusMetric.thermal]!.text, 'CPU 145°F');
      expect(items[StatusMetric.uptime]!.text, 'Uptime 1h 05m');
    });

    test('unavailable and disabled metrics get no item', () {
      final config = LumideStatsConfig()
        ..enabledMetrics.remove(StatusMetric.cpu);
      final items = buildStatusItems(_snapshot(cpu: full.cpu), config);
      expect(items, isEmpty);
    });

    test('battery on AC power is never flagged', () {
      const battery = BatteryStats(
        levelPercent: 5,
        state: BatteryState.charging,
      );
      expect(battery.level, MetricLevel.normal);
      final items = buildStatusItems(
        _snapshot(battery: battery),
        LumideStatsConfig(),
      );
      expect(items.single.icon, 'battery-charging');
    });
  });

  group('dashboard', () {
    test('HTML embeds data without breaking out of the script', () {
      final snapshot = _snapshot(
        cpu: const CpuStats(
          usagePercent: 10,
          coreCount: 4,
          topProcesses: [
            TopProcessInfo(
              name: '</script><img src=x onerror=alert(1)>',
              cpuPercent: 1,
              rssBytes: 1,
            ),
          ],
        ),
      );
      final html = buildDashboardHtml(snapshot, false);
      expect(html, isNot(contains('</script><img')));
      expect(html, isNot(contains('googleapis')));
    });

    test('text report lists unavailable metrics', () {
      final report = buildTextReport(_snapshot());
      expect(report, contains('CPU: not available'));
      expect(report, contains('Battery: none'));
      expect(report, contains('Lumide session: 1h 05m'));
    });
  });

  group('native readers', () {
    test('diskStatsFromBlocks reports like df', () {
      final disk = diskStatsFromBlocks(
        volume: '/',
        blockSize: 4096,
        blocks: 1000,
        freeBlocks: 300,
        availableBlocks: 250,
      )!;
      expect(disk.volume, '/');
      expect(disk.totalBytes, 1000 * 4096);
      expect(disk.usedBytes, 700 * 4096);
      expect(disk.freeBytes, 250 * 4096);
      // Implausible values fall back to df.
      for (final (size, blocks, free, available) in [
        (0, 1000, 300, 250),
        (4096, 0, 0, 0),
        (4096, 1000, 1001, 250),
        (4096, 1000, 300, -1),
      ]) {
        expect(
          diskStatsFromBlocks(
            volume: '/',
            blockSize: size,
            blocks: blocks,
            freeBlocks: free,
            availableBlocks: available,
          ),
          isNull,
        );
      }
    });

    test('statvfs matches df -kP /', () async {
      final native = PosixDisk.instance!.read('/')!;
      final df = parseDf(
        (await Process.run('df', ['-kP', '/'])).stdout as String,
      )!;
      expect(native.volume, df.volume);
      expect(native.totalBytes, closeTo(df.totalBytes, 1024));
      // Other processes may write in between.
      expect(native.usedBytes, closeTo(df.usedBytes, 64 << 20));
      expect(native.freeBytes, closeTo(df.freeBytes, 64 << 20));
    }, skip: Platform.isLinux || Platform.isMacOS ? false : 'POSIX only');

    test('macUsedMemoryBytes counts app, wired and compressed pages', () {
      expect(
        macUsedMemoryBytes(
          pageSize: 16384,
          wired: 100,
          compressed: 50,
          anonymous: 400,
          purgeable: 30,
          active: 999,
        ),
        (370 + 100 + 50) * 16384,
      );
      expect(
        macUsedMemoryBytes(pageSize: 4096, wired: 1, compressed: 0, active: 9),
        10 * 4096,
      );
    });

    test('parseIfList2 finds the interface counters', () {
      // RTM_IFINFO2 messages are 160 bytes; other messages are skipped.
      final data = ByteData(160 * 3 + 20);
      var offset = 0;
      void message(
        int type,
        int length, {
        int index = 0,
        int rx = 0,
        int tx = 0,
      }) {
        data
          ..setUint16(offset, length, Endian.little)
          ..setUint8(offset + 2, 7)
          ..setUint8(offset + 3, type)
          ..setUint16(offset + 12, index, Endian.little);
        if (length >= 112) {
          data
            ..setUint64(offset + 96, rx, Endian.little)
            ..setUint64(offset + 104, tx, Endian.little);
        }
        offset += length;
      }

      message(0x12, 160, index: 1, rx: 11, tx: 12); // lo0
      message(0x0e, 20, index: 4); // RTM_NEWADDR for en0
      message(0x12, 160, index: 4, rx: 5000000000, tx: 6000000000); // en0
      message(0x12, 160, index: 5, rx: 7, tx: 8);

      expect(
        parseIfList2(data, offset, 4),
        const NetCounters(5000000000, 6000000000),
      );
      expect(parseIfList2(data, offset, 1), const NetCounters(11, 12));
      expect(parseIfList2(data, offset, 9), isNull);
      // A truncated buffer ends the walk instead of reading past it.
      expect(parseIfList2(data, 160 + 20 + 100, 4), isNull);
    });

    test('parseIfTable2 sums connected hardware adapters only', () {
      final rows = [
        // (flags, type, operStatus, in, out)
        (0x01, 6, 1, 1000, 100), // Ethernet
        (0x01, 71, 1, 2000, 200), // Wi-Fi
        (0x03, 71, 1, 2000, 200), // Wi-Fi filter driver row (duplicate)
        (0x00, 24, 1, 9999, 9999), // loopback
        (0x00, 53, 1, 500, 50), // VPN adapter
        (0x01, 6, 2, 7777, 7777), // disconnected adapter
      ];
      final data = ByteData(8 + rows.length * ifRow2Size)
        ..setUint32(0, rows.length, Endian.little);
      for (final (i, (flags, type, status, rx, tx)) in rows.indexed) {
        final row = 8 + i * ifRow2Size;
        data
          ..setUint32(row + 1128, type, Endian.little)
          ..setUint8(row + 1152, flags)
          ..setUint32(row + 1156, status, Endian.little)
          ..setUint64(row + 1208, rx, Endian.little)
          ..setUint64(row + 1280, tx, Endian.little);
      }
      expect(parseIfTable2(data, rows.length), const NetCounters(3000, 300));
      expect(parseIfTable2(data, 0), isNull);
    });
  });

  group('CommandRunner', () {
    final posix = Platform.isLinux || Platform.isMacOS
        ? false
        : 'needs sleep and ps';

    Future<bool> alive(int pid) async =>
        (await Process.run('ps', ['-p', '$pid'])).exitCode == 0;

    test('returns stdout and kills commands that time out', () async {
      final runner = CommandRunner();
      expect(await runner.run('echo', ['hi']), 'hi\n');
      expect(await runner.run('false', []), isNull);
      expect(await runner.run('no-such-command-xyz', []), isNull);

      final watch = Stopwatch()..start();
      final pending = runner.run('sleep', [
        '30',
      ], timeout: const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final pid = runner.runningPids.single;
      expect(await pending, isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(runner.runningPids, isEmpty);
      expect(await alive(pid), isFalse);
    }, skip: posix);

    test('dispose kills running commands and refuses new ones', () async {
      final runner = CommandRunner();
      final pending = runner.run('sleep', ['30']);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final pid = runner.runningPids.single;
      runner.dispose();
      expect(await pending, isNull);
      expect(await alive(pid), isFalse);
      final started = runner.started;
      expect(await runner.run('echo', ['hi']), isNull);
      expect(runner.started, started);
    }, skip: posix);
  });

  group('SystemStatsCollector on this machine', () {
    test('reads real values', () async {
      final collector = SystemStatsCollector();
      await collector.collect();
      final snapshot = await collector.collect(includeProcesses: true);
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        expect(snapshot.cpu, isNotNull);
        expect(snapshot.cpu!.usagePercent, inInclusiveRange(0, 100));
        expect(snapshot.ram, isNotNull);
        expect(snapshot.ram!.totalBytes, greaterThan(0));
        expect(snapshot.disk, isNotNull);
        expect(snapshot.disk!.totalBytes, greaterThan(0));
      }
      final thermal = snapshot.thermal;
      if (thermal != null) {
        expect(thermal.temperatureCelsius, inExclusiveRange(0, 150));
      }
      expect(snapshot.toFormattedJson(), contains('"session"'));
    });

    test('starts no processes on Linux', () async {
      final collector = SystemStatsCollector(diskInterval: Duration.zero);
      for (var i = 0; i < 3; i++) {
        await collector.collect();
      }
      expect(collector.processesStarted, 0);
      collector.dispose();
    }, skip: Platform.isLinux ? false : 'Linux only');

    test('only reads requested metrics', () async {
      final snapshot = await SystemStatsCollector().collect(
        metrics: {Metric.ram},
      );
      expect(snapshot.cpu, isNull);
      expect(snapshot.disk, isNull);
      expect(snapshot.network, isNull);
    });
  });
}
