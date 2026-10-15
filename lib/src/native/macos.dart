/// macOS readings through system libraries, without spawning processes:
/// CPU ticks from Mach, load averages from libc, and temperatures and fan
/// speeds from the System Management Controller (SMC, read-only).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../parsers.dart';

typedef _MachHostSelfC = Uint32 Function();
typedef _MachHostSelf = int Function();
typedef _HostStatisticsC = Int32 Function(
    Uint32, Int32, Pointer<Int32>, Pointer<Uint32>);
typedef _HostStatistics = int Function(
    int, int, Pointer<Int32>, Pointer<Uint32>);
typedef _GetLoadAvgC = Int32 Function(Pointer<Double>, Int32);
typedef _GetLoadAvg = int Function(Pointer<Double>, int);

const _hostCpuLoadInfo = 3; // HOST_CPU_LOAD_INFO
const _cpuStateMax = 4; // user, system, idle, nice
const _cpuStateIdle = 2;

/// CPU ticks and load averages from libSystem.
class MacSystem {
  MacSystem._() {
    try {
      final lib = DynamicLibrary.process();
      final hostSelf = lib.lookupFunction<_MachHostSelfC, _MachHostSelf>(
        'mach_host_self',
      );
      _hostStatistics = lib.lookupFunction<_HostStatisticsC, _HostStatistics>(
        'host_statistics',
      );
      _getLoadAvg = lib.lookupFunction<_GetLoadAvgC, _GetLoadAvg>('getloadavg');
      // Each call adds a port reference, so look the host port up once.
      _host = hostSelf();
    } catch (_) {
      _hostStatistics = null;
      _getLoadAvg = null;
    }
  }

  static MacSystem? _instance;

  /// The shared instance, or `null` when not running on macOS.
  static MacSystem? get instance {
    if (!Platform.isMacOS) return null;
    return _instance ??= MacSystem._();
  }

  int _host = 0;
  _HostStatistics? _hostStatistics;
  _GetLoadAvg? _getLoadAvg;

  /// Cumulative CPU ticks of all cores.
  CpuTimes? cpuTimes() {
    final hostStatistics = _hostStatistics;
    if (hostStatistics == null || _host == 0) return null;
    final info = calloc<Int32>(_cpuStateMax);
    final count = calloc<Uint32>()..value = _cpuStateMax;
    try {
      if (hostStatistics(_host, _hostCpuLoadInfo, info, count) != 0) {
        return null;
      }
      // natural_t counters are unsigned 32-bit values.
      final ticks = [
        for (var i = 0; i < _cpuStateMax; i++) info[i] & 0xFFFFFFFF,
      ];
      return CpuTimes(
        idle: ticks[_cpuStateIdle],
        total: ticks.fold(0, (sum, v) => sum + v),
      );
    } finally {
      calloc.free(info);
      calloc.free(count);
    }
  }

  /// 1, 5 and 15 minute load averages.
  List<double>? loadAverage() {
    final getLoadAvg = _getLoadAvg;
    if (getLoadAvg == null) return null;
    final values = calloc<Double>(3);
    try {
      if (getLoadAvg(values, 3) != 3) return null;
      return [values[0], values[1], values[2]];
    } finally {
      calloc.free(values);
    }
  }
}

// --- SMC ---------------------------------------------------------------------

typedef _IOServiceMatchingC = Pointer<Void> Function(Pointer<Utf8>);
typedef _IOServiceMatching = Pointer<Void> Function(Pointer<Utf8>);
typedef _IOServiceGetMatchingServiceC = Uint32 Function(Uint32, Pointer<Void>);
typedef _IOServiceGetMatchingService = int Function(int, Pointer<Void>);
typedef _IOServiceOpenC = Int32 Function(
    Uint32, Uint32, Uint32, Pointer<Uint32>);
typedef _IOServiceOpen = int Function(int, int, int, Pointer<Uint32>);
typedef _IOObjectReleaseC = Int32 Function(Uint32);
typedef _IOObjectRelease = int Function(int);
typedef _IOConnectCallStructMethodC = Int32 Function(
  Uint32,
  Uint32,
  Pointer<Void>,
  Size,
  Pointer<Void>,
  Pointer<Size>,
);
typedef _IOConnectCallStructMethod = int Function(
    int, int, Pointer<Void>, int, Pointer<Void>, Pointer<Size>);

/// `SMCKeyData_t` from the AppleSMC user client (80 bytes).
final class _SmcKeyData extends Struct {
  @Uint32()
  external int key; // 0
  @Array(6)
  external Array<Uint8> vers; // 4
  @Array(16)
  external Array<Uint8> pLimitData; // 10 (12 in C, never read)
  @Uint32()
  external int dataSize; // 28
  @Uint32()
  external int dataType; // 32
  @Uint8()
  external int dataAttributes; // 36
  @Array(3)
  external Array<Uint8> keyInfoPadding;
  @Uint8()
  external int result; // 40
  @Uint8()
  external int status; // 41
  @Uint8()
  external int data8; // 42
  @Uint32()
  external int data32; // 44
  @Array(32)
  external Array<Uint8> bytes; // 48
}

const _kernelIndexSmc = 2;
const _smcCmdReadBytes = 5;
const _smcCmdReadKeyInfo = 9;

/// CPU temperature keys, from exelban/stats. Intel Macs use `TC0*`; Apple
/// Silicon generations use `Tp*`, `Te*` and `Tf*` core sensors.
const smcCpuTemperatureKeys = [
  // Intel
  'TC0P', 'TC0D', 'TC0E', 'TC0F', 'TC0H',
  // M1
  'Tp09', 'Tp0T', 'Tp01', 'Tp05', 'Tp0D', 'Tp0H', 'Tp0L', 'Tp0P', 'Tp0X',
  'Tp0b',
  // M2
  'Tp1h', 'Tp1t', 'Tp1p', 'Tp1l', 'Tp0f', 'Tp0j',
  // M3
  'Te05', 'Te0L', 'Te0P', 'Te0S', 'Tf04', 'Tf09', 'Tf0A', 'Tf0B', 'Tf0D',
  'Tf0E', 'Tf44', 'Tf49', 'Tf4A', 'Tf4B', 'Tf4D', 'Tf4E',
  // M4
  'Te09', 'Te0H', 'Tp0V', 'Tp0Y', 'Tp0e',
];

/// Decodes an SMC value of [type] (a four-character code such as `sp78`).
///
/// Integer and fixed-point types are big-endian. `flt ` is a little-endian
/// IEEE float, as written by Apple Silicon.
double? decodeSmcValue(String type, List<int> bytes) {
  int byte(int i) => i < bytes.length ? bytes[i] : 0;
  switch (type.trim()) {
    case 'sp78':
      final raw = (byte(0) << 8) | byte(1);
      return (raw >= 0x8000 ? raw - 0x10000 : raw) / 256;
    case 'fpe2':
      return ((byte(0) << 8) | byte(1)) / 4;
    case 'flt':
      if (bytes.length < 4) return null;
      return ByteData.sublistView(
        Uint8List.fromList(bytes.sublist(0, 4)),
      ).getFloat32(0, Endian.little);
    case 'ui8':
      return byte(0).toDouble();
    case 'ui16':
      return ((byte(0) << 8) | byte(1)).toDouble();
    case 'ui32':
      return ((byte(0) << 24) | (byte(1) << 16) | (byte(2) << 8) | byte(3))
          .toDouble();
    default:
      return null;
  }
}

/// Read-only access to the Apple SMC through IOKit.
class AppleSmc {
  AppleSmc._() {
    try {
      final ioKit = DynamicLibrary.open(
        '/System/Library/Frameworks/IOKit.framework/IOKit',
      );
      final matching =
          ioKit.lookupFunction<_IOServiceMatchingC, _IOServiceMatching>(
        'IOServiceMatching',
      );
      final getService = ioKit.lookupFunction<_IOServiceGetMatchingServiceC,
          _IOServiceGetMatchingService>('IOServiceGetMatchingService');
      final open = ioKit.lookupFunction<_IOServiceOpenC, _IOServiceOpen>(
        'IOServiceOpen',
      );
      final release = ioKit.lookupFunction<_IOObjectReleaseC, _IOObjectRelease>(
        'IOObjectRelease',
      );
      _call = ioKit.lookupFunction<_IOConnectCallStructMethodC,
          _IOConnectCallStructMethod>('IOConnectCallStructMethod');
      final taskSelf =
          DynamicLibrary.process().lookup<Uint32>('mach_task_self_').value;

      final name = 'AppleSMC'.toNativeUtf8();
      // IOServiceGetMatchingService consumes the matching dictionary.
      final service = getService(0, matching(name));
      malloc.free(name);
      if (service == 0) return;

      final connection = calloc<Uint32>();
      try {
        if (open(service, taskSelf, 0, connection) == 0) {
          _connection = connection.value;
        }
      } finally {
        calloc.free(connection);
        release(service);
      }
    } catch (_) {
      _connection = 0;
    }
  }

  static AppleSmc? _instance;

  /// The shared instance, or `null` when not running on macOS.
  static AppleSmc? get instance {
    if (!Platform.isMacOS) return null;
    return _instance ??= AppleSmc._();
  }

  _IOConnectCallStructMethod? _call;
  int _connection = 0;
  final _keyInfo = <String, ({int size, String type})?>{};
  List<String>? _temperatureKeys;

  bool get isAvailable => _connection != 0 && _call != null;

  static int _fourCharCode(String key) =>
      key.codeUnits.fold(0, (code, unit) => (code << 8) | (unit & 0xFF));

  static String _fourCharString(int code) => String.fromCharCodes([
        (code >> 24) & 0xFF,
        (code >> 16) & 0xFF,
        (code >> 8) & 0xFF,
        code & 0xFF,
      ]);

  bool _send(Pointer<_SmcKeyData> input, Pointer<_SmcKeyData> output) {
    final size = calloc<Size>()..value = sizeOf<_SmcKeyData>();
    try {
      final status = _call!(
        _connection,
        _kernelIndexSmc,
        input.cast(),
        sizeOf<_SmcKeyData>(),
        output.cast(),
        size,
      );
      return status == 0 && output.ref.result == 0;
    } finally {
      calloc.free(size);
    }
  }

  /// Reads a four-character SMC key, or returns `null` if it doesn't exist.
  double? readKey(String key) {
    if (!isAvailable || key.length != 4) return null;
    final input = calloc<_SmcKeyData>();
    final output = calloc<_SmcKeyData>();
    try {
      final code = _fourCharCode(key);
      if (!_keyInfo.containsKey(key)) {
        input.ref
          ..key = code
          ..data8 = _smcCmdReadKeyInfo;
        _keyInfo[key] = _send(input, output)
            ? (
                size: output.ref.dataSize,
                type: _fourCharString(output.ref.dataType),
              )
            : null;
      }
      final info = _keyInfo[key];
      if (info == null || info.size <= 0 || info.size > 32) return null;

      input.ref
        ..key = code
        ..dataSize = info.size
        ..data8 = _smcCmdReadBytes;
      if (!_send(input, output)) return null;
      final bytes = [for (var i = 0; i < info.size; i++) output.ref.bytes[i]];
      return decodeSmcValue(info.type, bytes);
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }

  /// Average of the CPU core temperature sensors this Mac has, in °C.
  double? cpuTemperature() {
    if (!isAvailable) return null;
    // Probe every known key once, then only read the ones that exist.
    final keys = _temperatureKeys ??= smcCpuTemperatureKeys
        .where((k) => _isPlausibleTemperature(readKey(k)))
        .toList();
    final values = keys
        .map(readKey)
        .where(_isPlausibleTemperature)
        .cast<double>()
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Average actual fan speed in RPM, or `null` on fanless Macs.
  int? fanRpm() {
    if (!isAvailable) return null;
    final count = readKey('FNum')?.toInt() ?? 0;
    final speeds = [
      for (var i = 0; i < count; i++) readKey('F${i}Ac'),
    ].whereType<double>().where((rpm) => rpm >= 0 && rpm < 20000).toList();
    if (speeds.isEmpty) return null;
    return (speeds.reduce((a, b) => a + b) / speeds.length).round();
  }

  static bool _isPlausibleTemperature(double? celsius) =>
      celsius != null && celsius > 5 && celsius < 130;
}
