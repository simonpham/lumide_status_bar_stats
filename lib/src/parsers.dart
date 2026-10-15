/// Pure parsers for the files and command output the collector reads.
///
/// They take text and return values, so they can be tested on any platform.
library;

import 'models/system_stats.dart';

final _whitespace = RegExp(r'\s+');

/// Cumulative CPU time counters, in arbitrary ticks.
class CpuTimes {
  final int idle;
  final int total;

  const CpuTimes({required this.idle, required this.total});

  /// Usage between [previous] and this sample, or `null` if no time passed
  /// or the counters went backwards.
  double? usageSince(CpuTimes previous) {
    final totalDelta = total - previous.total;
    final idleDelta = idle - previous.idle;
    if (totalDelta <= 0 || idleDelta < 0) return null;
    return ((totalDelta - idleDelta) / totalDelta * 100).clamp(0, 100);
  }
}

/// Parses the aggregate `cpu` line of Linux `/proc/stat`.
///
/// Idle time includes `iowait`; `guest` and `guest_nice` are left out because
/// `user` and `nice` already include them.
CpuTimes? parseProcStat(String content) {
  for (final line in content.split('\n')) {
    if (!line.startsWith('cpu ')) continue;
    final values = line
        .trim()
        .split(_whitespace)
        .skip(1)
        .map(int.tryParse)
        .toList();
    if (values.length < 4 || values.take(4).any((v) => v == null)) {
      return null;
    }
    final fields = values.take(8).map((v) => v ?? 0).toList();
    final idle = fields[3] + (fields.length > 4 ? fields[4] : 0);
    final total = fields.fold<int>(0, (sum, v) => sum + v);
    return CpuTimes(idle: idle, total: total);
  }
  return null;
}

/// Parses `/proc/loadavg` (Linux) or `sysctl -n vm.loadavg` (macOS, wrapped
/// in braces).
LoadAverage? parseLoadAverage(String content) {
  final parts = content
      .replaceAll('{', ' ')
      .replaceAll('}', ' ')
      .trim()
      .split(_whitespace);
  if (parts.length < 3) return null;
  final values = parts.take(3).map(double.tryParse).toList();
  if (values.any((v) => v == null)) return null;
  return LoadAverage(values[0]!, values[1]!, values[2]!);
}

/// Parses Linux `/proc/meminfo`.
///
/// Used memory is `MemTotal - MemAvailable`, which matches what `free` and
/// most system monitors report.
RamStats? parseMeminfo(String content) {
  final kb = <String, int>{};
  for (final line in content.split('\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final value = int.tryParse(
      line.substring(colon + 1).trim().split(_whitespace).first,
    );
    if (value != null) kb[line.substring(0, colon)] = value;
  }
  final total = kb['MemTotal'];
  if (total == null || total <= 0) return null;
  final available =
      kb['MemAvailable'] ??
      (kb['MemFree'] ?? 0) + (kb['Buffers'] ?? 0) + (kb['Cached'] ?? 0);
  final swapTotal = kb['SwapTotal'];
  final swapFree = kb['SwapFree'];
  return RamStats(
    totalBytes: total * 1024,
    usedBytes: ((total - available).clamp(0, total)) * 1024,
    swapUsedBytes: swapTotal != null && swapFree != null
        ? (swapTotal - swapFree).clamp(0, swapTotal) * 1024
        : null,
  );
}

/// Parses macOS `vm_stat` output into used bytes.
///
/// Used memory = app memory (anonymous - purgeable) + wired + compressed,
/// the same formula as Activity Monitor's "Memory Used".
int? parseVmStatUsedBytes(String output) {
  final pageSize =
      int.tryParse(
        RegExp(r'page size of (\d+) bytes').firstMatch(output)?.group(1) ?? '',
      ) ??
      4096;
  final pages = <String, int>{};
  for (final line in output.split('\n')) {
    final match = RegExp(r'^"?([^":]+)"?:\s+(\d+)\.?$').firstMatch(line.trim());
    if (match != null) pages[match.group(1)!] = int.parse(match.group(2)!);
  }
  final wired = pages['Pages wired down'];
  final compressed = pages['Pages occupied by compressor'] ?? 0;
  if (wired == null) return null;
  final anonymous = pages['Anonymous pages'];
  final appPages = anonymous != null
      ? anonymous - (pages['Pages purgeable'] ?? 0)
      : pages['Pages active'] ?? 0;
  return (appPages.clamp(0, 1 << 62) + wired + compressed) * pageSize;
}

/// Parses macOS `sysctl -n vm.swapusage`, e.g.
/// `total = 2048.00M  used = 1093.50M  free = 954.50M  (encrypted)`.
int? parseSwapUsage(String output) {
  final match = RegExp(r'used = ([\d.]+)([KMGT])').firstMatch(output);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  const multipliers = {'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30, 'T': 1 << 40};
  return (value * multipliers[match.group(2)]!).round();
}

/// Parses POSIX `df -kP <path>` output.
DiskStats? parseDf(String output) {
  final lines = output.trim().split('\n');
  if (lines.length < 2) return null;
  // Columns: Filesystem 1024-blocks Used Available Capacity Mounted-on.
  // Read from the right: the filesystem name may contain spaces.
  final parts = lines.last.trim().split(_whitespace);
  if (parts.length < 6) return null;
  final mount = parts.last;
  final available = int.tryParse(parts[parts.length - 3]);
  final used = int.tryParse(parts[parts.length - 4]);
  final total = int.tryParse(parts[parts.length - 5]);
  if (total == null || used == null || available == null || total <= 0) {
    return null;
  }
  return DiskStats(
    volume: mount,
    totalBytes: total * 1024,
    usedBytes: used * 1024,
    freeBytes: available * 1024,
  );
}

/// Received and sent byte counters of a network interface.
class NetCounters {
  final int received;
  final int sent;

  const NetCounters(this.received, this.sent);

  @override
  bool operator ==(Object other) =>
      other is NetCounters && other.received == received && other.sent == sent;

  @override
  int get hashCode => Object.hash(received, sent);

  @override
  String toString() => 'NetCounters($received, $sent)';
}

/// Interface names that never carry internet traffic or would count the same
/// bytes twice (loopback, container bridges, virtual Ethernet pairs).
bool _isVirtualInterface(String name) =>
    name == 'lo' ||
    name.startsWith('veth') ||
    name.startsWith('docker') ||
    name.startsWith('br-') ||
    name.startsWith('virbr') ||
    name.startsWith('vnet');

/// Parses Linux `/proc/net/dev`.
///
/// Returns the counters of [interfaces] if given, otherwise the sum of all
/// physical-looking interfaces.
NetCounters? parseProcNetDev(String content, {Set<String>? interfaces}) {
  var received = 0;
  var sent = 0;
  var found = false;
  for (final line in content.split('\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final name = line.substring(0, colon).trim();
    if (interfaces != null
        ? !interfaces.contains(name)
        : _isVirtualInterface(name)) {
      continue;
    }
    final fields = line.substring(colon + 1).trim().split(_whitespace);
    if (fields.length < 9) continue;
    final rx = int.tryParse(fields[0]);
    final tx = int.tryParse(fields[8]);
    if (rx == null || tx == null) continue;
    received += rx;
    sent += tx;
    found = true;
  }
  return found ? NetCounters(received, sent) : null;
}

/// Parses Linux `/proc/net/route` and returns the interfaces that hold a
/// default route (destination `00000000`).
Set<String> parseProcNetRouteDefaults(String content) {
  final result = <String>{};
  for (final line in content.split('\n').skip(1)) {
    final fields = line.trim().split(_whitespace);
    if (fields.length >= 8 &&
        fields[1] == '00000000' &&
        fields[7] == '00000000') {
      result.add(fields[0]);
    }
  }
  return result;
}

/// Parses macOS `route -n get default` and returns the interface name.
String? parseRouteGetDefault(String output) =>
    RegExp(r'interface:\s*(\S+)').firstMatch(output)?.group(1);

/// Parses macOS `netstat -b -n -I <interface>` output.
///
/// Uses the `<Link#n>` row, which carries the interface totals. Columns are
/// read from the right because the Address column is empty for some
/// interfaces (e.g. `utun0`).
NetCounters? parseNetstatInterface(String output, String interface) {
  for (final line in output.split('\n')) {
    final parts = line.trim().split(_whitespace);
    if (parts.length < 7 || parts.first != interface) continue;
    if (!line.contains('<Link#')) continue;
    // ... Ibytes Opkts Oerrs Obytes Coll
    final received = int.tryParse(parts[parts.length - 5]);
    final sent = int.tryParse(parts[parts.length - 2]);
    if (received != null && sent != null) return NetCounters(received, sent);
  }
  return null;
}

/// Parses Windows `netstat -e`.
///
/// The first row whose last two columns are numbers is the `Bytes` row. This
/// avoids matching the localized row label.
NetCounters? parseWindowsNetstatE(String output) {
  for (final line in output.split('\n')) {
    final parts = line.trim().split(_whitespace);
    if (parts.length < 3) continue;
    final received = int.tryParse(parts[parts.length - 2]);
    final sent = int.tryParse(parts[parts.length - 1]);
    if (received != null && sent != null) return NetCounters(received, sent);
  }
  return null;
}

/// Parses macOS `pmset -g batt`, e.g.
/// ` -InternalBattery-0 (id=1234)	85%; discharging; 3:12 remaining present: true`.
BatteryStats? parsePmsetBatt(String output) {
  final line = output
      .split('\n')
      .where((l) => l.contains('InternalBattery'))
      .firstOrNull;
  if (line == null) return null;
  final percent = int.tryParse(
    RegExp(r'(\d+)%').firstMatch(line)?.group(1) ?? '',
  );
  if (percent == null) return null;

  final fields = line.split(';').map((f) => f.trim().toLowerCase()).toList();
  final status = fields.length > 1 ? fields[1] : '';
  final onAc = output.contains("'AC Power'");
  final state = switch (status) {
    'charging' => BatteryState.charging,
    'discharging' => onAc ? BatteryState.notCharging : BatteryState.discharging,
    'charged' || 'finishing charge' => BatteryState.full,
    'ac attached' => BatteryState.notCharging,
    _ => onAc ? BatteryState.notCharging : BatteryState.unknown,
  };

  final time = RegExp(r'(\d+):(\d{2}) remaining').firstMatch(line);
  final minutes = time == null
      ? null
      : int.parse(time.group(1)!) * 60 + int.parse(time.group(2)!);
  return BatteryStats(
    levelPercent: percent.clamp(0, 100),
    state: state,
    timeRemainingMinutes: minutes == 0 ? null : minutes,
  );
}

/// Parses the Linux sysfs `status` file of a battery.
BatteryState parseSysfsBatteryStatus(String status) =>
    switch (status.trim().toLowerCase()) {
      'charging' => BatteryState.charging,
      'discharging' => BatteryState.discharging,
      'full' => BatteryState.full,
      'not charging' => BatteryState.notCharging,
      _ => BatteryState.unknown,
    };

/// Estimates minutes remaining from sysfs energy/charge readings.
///
/// [now] and [full] are `energy_now`/`energy_full` (µWh) or
/// `charge_now`/`charge_full` (µAh); [rate] is `power_now` (µW) or
/// `current_now` (µA).
int? estimateBatteryMinutes({
  required BatteryState state,
  int? now,
  int? full,
  int? rate,
}) {
  if (now == null || rate == null || rate <= 0) return null;
  final double hours;
  if (state == BatteryState.discharging) {
    hours = now / rate;
  } else if (state == BatteryState.charging && full != null && full > now) {
    hours = (full - now) / rate;
  } else {
    return null;
  }
  final minutes = (hours * 60).round();
  return minutes > 0 && minutes < 48 * 60 ? minutes : null;
}

/// A temperature sensor found under `/sys/class/hwmon` or
/// `/sys/class/thermal`.
class LinuxTempSensor {
  /// hwmon `name` (e.g. `k10temp`) or thermal zone `type` (e.g.
  /// `x86_pkg_temp`).
  final String chip;

  /// hwmon `tempN_label` (e.g. `Tctl`, `Package id 0`), if any.
  final String? label;
  final double celsius;

  const LinuxTempSensor(this.chip, this.label, this.celsius);

  String get description => label == null ? chip : '$chip $label';
}

/// Parses a sysfs temperature in millidegrees Celsius.
double? parseMilliCelsius(String raw) {
  final value = int.tryParse(raw.trim());
  if (value == null) return null;
  final celsius = value / 1000;
  return celsius > 0 && celsius < 150 ? celsius : null;
}

/// Picks the sensor that best represents the CPU temperature.
///
/// Prefers CPU package sensors (Intel `coretemp` "Package id", AMD `k10temp`
/// Tctl/Tdie, ARM `cpu_thermal`), then any CPU-related sensor, then ACPI
/// zones. Returns `null` rather than guessing from unrelated sensors such as
/// NVMe drives, GPUs or Wi-Fi cards.
LinuxTempSensor? pickCpuTemperature(List<LinuxTempSensor> sensors) {
  int rank(LinuxTempSensor s) {
    final chip = s.chip.toLowerCase();
    final label = (s.label ?? '').toLowerCase();
    if (chip == 'coretemp' && label.startsWith('package')) return 0;
    if ((chip == 'k10temp' || chip == 'zenpower') &&
        (label == 'tdie' || label == 'tctl')) {
      return 0;
    }
    if (chip == 'x86_pkg_temp') return 1;
    if (chip == 'cpu_thermal' ||
        chip == 'cpu-thermal' ||
        chip == 'soc_thermal' ||
        chip == 'cpu' ||
        chip.startsWith('cpu')) {
      return 1;
    }
    if (chip == 'coretemp' || chip == 'k10temp' || chip == 'zenpower') {
      return 2;
    }
    if (chip == 'acpitz') return 3;
    return 99;
  }

  LinuxTempSensor? best;
  var bestRank = 99;
  for (final sensor in sensors) {
    final r = rank(sensor);
    if (r < bestRank ||
        (r == bestRank && best != null && sensor.celsius > best.celsius)) {
      best = sensor;
      bestRank = r;
    }
  }
  return bestRank < 99 ? best : null;
}

/// Parses `ps -A -o pcpu=,rss=,comm=` output (macOS and Linux).
///
/// `comm` may contain spaces on macOS, so everything after the second column
/// is the command. Absolute paths (macOS) are shortened to the file name.
List<TopProcessInfo> parsePs(String output) {
  final result = <TopProcessInfo>[];
  for (final line in output.split('\n')) {
    final parts = line.trim().split(_whitespace);
    if (parts.length < 3) continue;
    final cpu = double.tryParse(parts[0].replaceAll(',', '.'));
    final rssKb = int.tryParse(parts[1]);
    if (cpu == null || rssKb == null) continue;
    final command = parts.sublist(2).join(' ');
    final name = command.startsWith('/')
        ? command.substring(command.lastIndexOf('/') + 1)
        : command;
    if (name.isEmpty) continue;
    result.add(
      TopProcessInfo(name: name, cpuPercent: cpu, rssBytes: rssKb * 1024),
    );
  }
  return result;
}

/// Returns the [count] entries with the highest [key].
List<TopProcessInfo> topBy(
  List<TopProcessInfo> processes,
  num Function(TopProcessInfo) key, {
  int count = 5,
}) {
  final sorted = [...processes]..sort((a, b) => key(b).compareTo(key(a)));
  return sorted.take(count).toList();
}
