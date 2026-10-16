import 'dart:async';
import 'dart:io';

import 'command_runner.dart';
import 'models/system_stats.dart';
import 'native/macos.dart';
import 'native/posix.dart';
import 'native/windows.dart';
import 'parsers.dart';

/// The metrics [SystemStatsCollector.collect] can read.
enum Metric { cpu, ram, disk, network, battery, thermal }

/// Reads system metrics on Linux, macOS and Windows.
///
/// Sources by platform:
/// - Linux: `/proc`, `/sys/class/{hwmon,thermal,power_supply}`, and
///   `statvfs`. No processes are started.
/// - macOS: Mach, libc (`statfs`, `sysctl`) and SMC through FFI, `route`
///   (every 30 seconds) and `pmset` (with battery). `vm_stat`, `sysctl`,
///   `df` and `netstat` are only run if the FFI readers fail.
/// - Windows: kernel32 and iphlpapi through FFI. `netstat -e` is only run if
///   the FFI reader fails.
///
/// Top processes (dashboard only) come from `ps` on Linux and macOS.
///
/// Disk and battery change slowly, so they are re-read at most every
/// [diskInterval] and [batteryInterval]; other metrics are read on every call.
///
/// Call [dispose] when done: it kills commands that are still running.
class SystemStatsCollector {
  SystemStatsCollector({
    this.diskInterval = const Duration(seconds: 30),
    this.batteryInterval = const Duration(seconds: 15),
  });

  final Duration diskInterval;
  final Duration batteryInterval;

  final DateTime _startTime = DateTime.now();

  CpuTimes? _previousCpu;
  NetCounters? _previousNet;
  String? _previousNetInterface;
  DateTime? _previousNetTime;

  String? _macInterface;
  DateTime? _macInterfaceTime;
  int? _macTotalMemory;

  ({DateTime time, DiskStats? value})? _diskCache;
  ({DateTime time, BatteryStats? value})? _batteryCache;

  bool _linuxSensorSearched = false;
  ({String path, String description})? _linuxSensor;

  /// Battery directories under `/sys/class/power_supply`, re-listed every
  /// [_linuxBatteryScanInterval].
  List<String>? _linuxBatteryPaths;
  DateTime? _linuxBatteryScanTime;
  static const _linuxBatteryScanInterval = Duration(minutes: 5);

  Future<SystemStatsSnapshot>? _inFlight;

  final _commands = CommandRunner();

  /// Number of commands started so far, for tests and diagnostics.
  int get processesStarted => _commands.started;

  /// Kills commands that are still running and stops starting new ones.
  /// Later [collect] calls return only what can be read without them.
  void dispose() {
    _commands.dispose();
    MacSystem.instance?.dispose();
  }

  /// Reads [metrics] (all by default). Metrics that aren't requested or
  /// can't be read are `null` in the snapshot.
  ///
  /// Concurrent calls share the same read.
  Future<SystemStatsSnapshot> collect({
    Set<Metric> metrics = const {...Metric.values},
    bool includeProcesses = false,
  }) {
    return _inFlight ??= _collect(metrics, includeProcesses).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<SystemStatsSnapshot> _collect(
    Set<Metric> metrics,
    bool includeProcesses,
  ) async {
    Future<T?> read<T>(Metric metric, Future<T?> Function() reader) async {
      if (!metrics.contains(metric)) return null;
      try {
        return await reader();
      } catch (_) {
        return null;
      }
    }

    final processesFuture = includeProcesses
        ? _readProcesses().catchError((Object _) => <TopProcessInfo>[])
        : Future.value(<TopProcessInfo>[]);
    final cpuFuture = read(Metric.cpu, _readCpu);
    final ramFuture = read(Metric.ram, _readRam);
    final diskFuture = read(Metric.disk, _readDiskCached);
    final netFuture = read(Metric.network, _readNetwork);
    final batteryFuture = read(Metric.battery, _readBatteryCached);
    final thermalFuture = read(Metric.thermal, _readThermal);

    final processes = await processesFuture;
    var cpu = await cpuFuture;
    var ram = await ramFuture;
    if (processes.isNotEmpty) {
      if (cpu != null) {
        cpu = CpuStats(
          usagePercent: cpu.usagePercent,
          coreCount: cpu.coreCount,
          loadAverage: cpu.loadAverage,
          topProcesses: topBy(processes, (p) => p.cpuPercent),
        );
      }
      ram = ram?.withTopProcesses(topBy(processes, (p) => p.rssBytes));
    }

    return SystemStatsSnapshot(
      timestamp: DateTime.now(),
      cpu: cpu,
      ram: ram,
      disk: await diskFuture,
      network: await netFuture,
      battery: await batteryFuture,
      thermal: await thermalFuture,
      session: SessionStats(
        uptime: DateTime.now().difference(_startTime),
        pluginRssBytes: ProcessInfo.currentRss,
      ),
    );
  }

  // --- Processes -------------------------------------------------------------

  /// Reads a small `/proc` or `/sys` file. These are generated in memory by
  /// the kernel, so a synchronous read is cheaper than an asynchronous one.
  String? _readFile(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Reads a file without blocking: used for the one-time sensor scan,
  /// where some drivers (e.g. disk temperatures) can be slow to answer.
  Future<String?> _readFileAsync(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  Future<List<TopProcessInfo>> _readProcesses() async {
    if (Platform.isWindows) return const [];
    final output = await _commands.run('ps', ['-A', '-o', 'pcpu=,rss=,comm=']);
    if (output == null) return const [];
    // Leave out the `ps` process that produced the list.
    return parsePs(output).where((p) => p.name != 'ps').toList();
  }

  // --- CPU -------------------------------------------------------------------

  Future<CpuTimes?> _readCpuTimes() async {
    if (Platform.isLinux) {
      final content = _readFile('/proc/stat');
      return content == null ? null : parseProcStat(content);
    }
    if (Platform.isMacOS) return MacSystem.instance?.cpuTimes();
    if (Platform.isWindows) return WindowsSystem.instance?.cpuTimes();
    return null;
  }

  Future<CpuStats?> _readCpu() async {
    var previous = _previousCpu;
    var current = await _readCpuTimes();
    if (current == null) return null;
    if (previous == null) {
      // Usage needs two samples. Take a short second one the first time.
      previous = current;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      current = await _readCpuTimes();
      if (current == null) return null;
    }
    _previousCpu = current;
    final usage = current.usageSince(previous);
    if (usage == null) return null;
    return CpuStats(
      usagePercent: usage,
      coreCount: Platform.numberOfProcessors,
      loadAverage: await _readLoadAverage(),
    );
  }

  Future<LoadAverage?> _readLoadAverage() async {
    if (Platform.isLinux) {
      final content = _readFile('/proc/loadavg');
      return content == null ? null : parseLoadAverage(content);
    }
    if (Platform.isMacOS) {
      final values = MacSystem.instance?.loadAverage();
      return values == null
          ? null
          : LoadAverage(values[0], values[1], values[2]);
    }
    return null;
  }

  // --- Memory ----------------------------------------------------------------

  Future<RamStats?> _readRam() async {
    if (Platform.isLinux) {
      final content = _readFile('/proc/meminfo');
      return content == null ? null : parseMeminfo(content);
    }
    if (Platform.isWindows) return WindowsSystem.instance?.memory();
    if (Platform.isMacOS) {
      final native = MacSystem.instance?.memory();
      if (native != null) return native;
      final total = _macTotalMemory ??= int.tryParse(
        (await _commands.run('sysctl', ['-n', 'hw.memsize']))?.trim() ?? '',
      );
      if (total == null || total <= 0) return null;
      final results = await Future.wait([
        _commands.run('vm_stat', const []),
        _commands.run('sysctl', ['-n', 'vm.swapusage']),
      ]);
      final used = results[0] == null
          ? null
          : parseVmStatUsedBytes(results[0]!);
      if (used == null) return null;
      return RamStats(
        totalBytes: total,
        usedBytes: used.clamp(0, total),
        swapUsedBytes: results[1] == null ? null : parseSwapUsage(results[1]!),
      );
    }
    return null;
  }

  // --- Disk ------------------------------------------------------------------

  Future<DiskStats?> _readDiskCached() async {
    final cache = _diskCache;
    if (cache != null && DateTime.now().difference(cache.time) < diskInterval) {
      return cache.value;
    }
    final value = await _readDisk();
    _diskCache = (time: DateTime.now(), value: value);
    return value;
  }

  Future<DiskStats?> _readDisk() async {
    if (Platform.isWindows) {
      final drive = Platform.environment['SystemDrive'] ?? 'C:';
      return WindowsSystem.instance?.disk('$drive\\');
    }
    final native = PosixDisk.instance?.read('/');
    if (native != null) return native;
    final output = await _commands.run('df', ['-kP', '/']);
    return output == null ? null : parseDf(output);
  }

  // --- Network ---------------------------------------------------------------

  Future<NetworkStats?> _readNetwork() async {
    final reading = await _readNetCounters();
    if (reading == null) return null;
    final now = DateTime.now();
    final previous = _previousNet;
    final previousTime = _previousNetTime;
    final sameInterface = _previousNetInterface == reading.interface;
    _previousNet = reading.counters;
    _previousNetTime = now;
    _previousNetInterface = reading.interface;

    var down = 0.0;
    var up = 0.0;
    if (previous != null && previousTime != null && sameInterface) {
      final seconds = now.difference(previousTime).inMicroseconds / 1e6;
      final received = reading.counters.received - previous.received;
      final sent = reading.counters.sent - previous.sent;
      // Counters reset when an interface goes down; skip that sample.
      if (seconds > 0 && received >= 0 && sent >= 0) {
        down = received / seconds;
        up = sent / seconds;
      }
    }
    return NetworkStats(
      interface: reading.interface,
      downloadBytesPerSec: down,
      uploadBytesPerSec: up,
    );
  }

  Future<({NetCounters counters, String? interface})?>
  _readNetCounters() async {
    if (Platform.isLinux) {
      final dev = _readFile('/proc/net/dev');
      if (dev == null) return null;
      final route = _readFile('/proc/net/route');
      final defaults = route == null
          ? <String>{}
          : parseProcNetRouteDefaults(route);
      final counters =
          (defaults.isEmpty
              ? null
              : parseProcNetDev(dev, interfaces: defaults)) ??
          parseProcNetDev(dev);
      if (counters == null) return null;
      return (
        counters: counters,
        interface: defaults.isEmpty
            ? null
            : (defaults.toList()..sort()).join(', '),
      );
    }

    if (Platform.isMacOS) {
      final interface = await _macDefaultInterface();
      if (interface == null) return null;
      var counters = MacSystem.instance?.interfaceCounters(interface);
      if (counters == null) {
        final output = await _commands.run('netstat', [
          '-b',
          '-n',
          '-I',
          interface,
        ]);
        counters = output == null
            ? null
            : parseNetstatInterface(output, interface);
      }
      if (counters == null) {
        _macInterface = null; // Look the route up again next time.
        return null;
      }
      return (counters: counters, interface: interface);
    }

    if (Platform.isWindows) {
      var counters = WindowsSystem.instance?.networkCounters();
      if (counters == null) {
        final output = await _commands.run('netstat', ['-e']);
        counters = output == null ? null : parseWindowsNetstatE(output);
      }
      return counters == null ? null : (counters: counters, interface: null);
    }
    return null;
  }

  /// The interface of the default route, refreshed every 30 seconds so that
  /// switching between Wi-Fi and Ethernet is picked up.
  Future<String?> _macDefaultInterface() async {
    final time = _macInterfaceTime;
    if (_macInterface != null &&
        time != null &&
        DateTime.now().difference(time) < const Duration(seconds: 30)) {
      return _macInterface;
    }
    final output = await _commands.run('route', ['-n', 'get', 'default']);
    _macInterface = output == null ? null : parseRouteGetDefault(output);
    _macInterfaceTime = DateTime.now();
    return _macInterface;
  }

  // --- Battery ---------------------------------------------------------------

  Future<BatteryStats?> _readBatteryCached() async {
    final cache = _batteryCache;
    if (cache != null &&
        DateTime.now().difference(cache.time) < batteryInterval) {
      return cache.value;
    }
    final value = await _readBattery();
    _batteryCache = (time: DateTime.now(), value: value);
    return value;
  }

  /// Forgets cached disk and battery readings so the next [collect] reads
  /// them again.
  void invalidateCaches() {
    _diskCache = null;
    _batteryCache = null;
    _linuxBatteryPaths = null;
  }

  Future<BatteryStats?> _readBattery() async {
    if (Platform.isMacOS) {
      final output = await _commands.run('pmset', ['-g', 'batt']);
      return output == null ? null : parsePmsetBatt(output);
    }
    if (Platform.isWindows) return WindowsSystem.instance?.battery();
    if (Platform.isLinux) return _readLinuxBattery();
    return null;
  }

  /// System batteries under `/sys/class/power_supply`. Peripheral batteries
  /// (mice, keyboards) reported by HID drivers are left out.
  List<String> _linuxBatteries() {
    final scanTime = _linuxBatteryScanTime;
    final cached = _linuxBatteryPaths;
    if (cached != null &&
        scanTime != null &&
        DateTime.now().difference(scanTime) < _linuxBatteryScanInterval) {
      return cached;
    }
    final paths = <String>[];
    try {
      for (final entity in Directory('/sys/class/power_supply').listSync()) {
        final path = entity.path;
        if (_readFile('$path/type')?.trim() != 'Battery') continue;
        if (_readFile('$path/scope')?.trim() == 'Device') continue;
        paths.add(path);
      }
    } on FileSystemException {
      // No power_supply class: no battery.
    }
    paths.sort();
    _linuxBatteryScanTime = DateTime.now();
    return _linuxBatteryPaths = paths;
  }

  Future<BatteryStats?> _readLinuxBattery() async {
    for (final path in _linuxBatteries()) {
      final capacity = int.tryParse(_readFile('$path/capacity')?.trim() ?? '');
      if (capacity == null) continue;
      final state = parseSysfsBatteryStatus(_readFile('$path/status') ?? '');
      int? readInt(String name) =>
          int.tryParse(_readFile('$path/$name')?.trim() ?? '');
      final energyNow = readInt('energy_now');
      final minutes = energyNow != null
          ? estimateBatteryMinutes(
              state: state,
              now: energyNow,
              full: readInt('energy_full'),
              rate: readInt('power_now')?.abs(),
            )
          : estimateBatteryMinutes(
              state: state,
              now: readInt('charge_now'),
              full: readInt('charge_full'),
              rate: readInt('current_now')?.abs(),
            );
      return BatteryStats(
        levelPercent: capacity.clamp(0, 100),
        state: state,
        timeRemainingMinutes: minutes,
      );
    }
    return null;
  }

  // --- Thermal ---------------------------------------------------------------

  Future<ThermalStats?> _readThermal() async {
    if (Platform.isMacOS) {
      final smc = AppleSmc.instance;
      final celsius = smc?.cpuTemperature();
      if (smc == null || celsius == null) return null;
      return ThermalStats(
        temperatureCelsius: celsius,
        source: 'SMC',
        fanRpm: smc.fanRpm(),
      );
    }
    if (Platform.isLinux) return _readLinuxThermal();
    // Windows only exposes temperatures to administrators (WMI), so the
    // metric is unavailable there.
    return null;
  }

  Future<ThermalStats?> _readLinuxThermal() async {
    if (!_linuxSensorSearched) {
      _linuxSensorSearched = true;
      _linuxSensor = await _findLinuxCpuSensor();
    }
    final sensor = _linuxSensor;
    if (sensor == null) return null;
    final raw = _readFile(sensor.path);
    final celsius = raw == null ? null : parseMilliCelsius(raw);
    if (celsius == null) return null;
    return ThermalStats(
      temperatureCelsius: celsius,
      source: sensor.description,
    );
  }

  Future<({String path, String description})?> _findLinuxCpuSensor() async {
    final candidates = <({String path, LinuxTempSensor sensor})>[];

    Future<void> scan(String root, String prefix) async {
      final dir = Directory(root);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (!name.startsWith(prefix)) continue;
        if (prefix == 'hwmon') {
          final chip = (await _readFileAsync('${entity.path}/name'))?.trim();
          if (chip == null) continue;
          for (var i = 1; i <= 16; i++) {
            final path = '${entity.path}/temp${i}_input';
            final raw = await _readFileAsync(path);
            if (raw == null) continue;
            final celsius = parseMilliCelsius(raw);
            if (celsius == null) continue;
            final label = (await _readFileAsync(
              '${entity.path}/temp${i}_label',
            ))?.trim();
            candidates.add((
              path: path,
              sensor: LinuxTempSensor(chip, label, celsius),
            ));
          }
        } else {
          final type = (await _readFileAsync('${entity.path}/type'))?.trim();
          final path = '${entity.path}/temp';
          final raw = await _readFileAsync(path);
          final celsius = raw == null ? null : parseMilliCelsius(raw);
          if (type == null || celsius == null) continue;
          candidates.add((
            path: path,
            sensor: LinuxTempSensor(type, null, celsius),
          ));
        }
      }
    }

    await scan('/sys/class/hwmon', 'hwmon');
    await scan('/sys/class/thermal', 'thermal_zone');
    final best = pickCpuTemperature(candidates.map((c) => c.sensor).toList());
    if (best == null) return null;
    final match = candidates.firstWhere((c) => identical(c.sensor, best));
    return (path: match.path, description: best.description);
  }
}
