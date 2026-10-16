/// Windows readings through kernel32 and iphlpapi, without spawning
/// processes.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../models/system_stats.dart';
import '../parsers.dart';

/// `MEMORYSTATUSEX` (64 bytes).
final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

/// `SYSTEM_POWER_STATUS` (12 bytes).
final class _SystemPowerStatus extends Struct {
  @Uint8()
  external int acLineStatus;
  @Uint8()
  external int batteryFlag;
  @Uint8()
  external int batteryLifePercent;
  @Uint8()
  external int systemStatusFlag;
  @Uint32()
  external int batteryLifeTime;
  @Uint32()
  external int batteryFullLifeTime;
}

typedef _GetSystemTimesC =
    Int32 Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetSystemTimes =
    int Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GlobalMemoryStatusExC = Int32 Function(Pointer<_MemoryStatusEx>);
typedef _GlobalMemoryStatusEx = int Function(Pointer<_MemoryStatusEx>);
typedef _GetDiskFreeSpaceExC =
    Int32 Function(
      Pointer<Utf16>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );
typedef _GetDiskFreeSpaceEx =
    int Function(
      Pointer<Utf16>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );
typedef _GetSystemPowerStatusC = Int32 Function(Pointer<_SystemPowerStatus>);
typedef _GetSystemPowerStatus = int Function(Pointer<_SystemPowerStatus>);

typedef _GetIfTable2C = Uint32 Function(Pointer<Pointer<Uint8>>);
typedef _GetIfTable2 = int Function(Pointer<Pointer<Uint8>>);
typedef _FreeMibTableC = Void Function(Pointer<Uint8>);
typedef _FreeMibTable = void Function(Pointer<Uint8>);

/// `sizeof(MIB_IF_ROW2)`. Rows start at offset 8 of `MIB_IF_TABLE2`, after
/// the 32-bit `NumEntries`.
const ifRow2Size = 1352;
const _ifTable2RowsOffset = 8;

// MIB_IF_ROW2 field offsets.
const _ifRow2Type = 1128; // IFTYPE Type
const _ifRow2Flags = 1152; // InterfaceAndOperStatusFlags (bit field byte)
const _ifRow2OperStatus = 1156; // IF_OPER_STATUS OperStatus
const _ifRow2InOctets = 1208; // ULONG64 InOctets
const _ifRow2OutOctets = 1280; // ULONG64 OutOctets

const _ifTypeSoftwareLoopback = 24;
const _ifOperStatusUp = 1;
const _hardwareInterfaceFlag = 0x01;
const _filterInterfaceFlag = 0x02;

/// Sums the byte counters of the connected hardware network adapters in a
/// `MIB_IF_TABLE2` of [rows] rows starting at [data] offset 0.
///
/// Filter-driver rows (which repeat their adapter's counters), software
/// loopback and virtual adapters (VPNs, whose traffic also crosses a
/// hardware adapter) are left out, so bytes aren't counted twice.
NetCounters? parseIfTable2(ByteData data, int rows) {
  var received = 0;
  var sent = 0;
  var found = false;
  for (var i = 0; i < rows; i++) {
    final row = _ifTable2RowsOffset + i * ifRow2Size;
    if (row + ifRow2Size > data.lengthInBytes) break;
    final flags = data.getUint8(row + _ifRow2Flags);
    if (flags & _hardwareInterfaceFlag == 0 ||
        flags & _filterInterfaceFlag != 0 ||
        data.getUint32(row + _ifRow2Type, Endian.little) ==
            _ifTypeSoftwareLoopback ||
        data.getUint32(row + _ifRow2OperStatus, Endian.little) !=
            _ifOperStatusUp) {
      continue;
    }
    received += data.getUint64(row + _ifRow2InOctets, Endian.little);
    sent += data.getUint64(row + _ifRow2OutOctets, Endian.little);
    found = true;
  }
  return found ? NetCounters(received, sent) : null;
}

/// CPU, memory, disk and battery readings from kernel32, and network
/// counters from iphlpapi.
class WindowsSystem {
  WindowsSystem._() {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _getSystemTimes = kernel32
          .lookupFunction<_GetSystemTimesC, _GetSystemTimes>('GetSystemTimes');
      _globalMemoryStatusEx = kernel32
          .lookupFunction<_GlobalMemoryStatusExC, _GlobalMemoryStatusEx>(
            'GlobalMemoryStatusEx',
          );
      _getDiskFreeSpaceEx = kernel32
          .lookupFunction<_GetDiskFreeSpaceExC, _GetDiskFreeSpaceEx>(
            'GetDiskFreeSpaceExW',
          );
      _getSystemPowerStatus = kernel32
          .lookupFunction<_GetSystemPowerStatusC, _GetSystemPowerStatus>(
            'GetSystemPowerStatus',
          );
    } catch (_) {}
    try {
      final iphlpapi = DynamicLibrary.open('iphlpapi.dll');
      _getIfTable2 = iphlpapi.lookupFunction<_GetIfTable2C, _GetIfTable2>(
        'GetIfTable2',
      );
      _freeMibTable = iphlpapi.lookupFunction<_FreeMibTableC, _FreeMibTable>(
        'FreeMibTable',
      );
    } catch (_) {
      _getIfTable2 = null;
    }
  }

  static WindowsSystem? _instance;

  /// The shared instance, or `null` when not running on Windows.
  static WindowsSystem? get instance {
    if (!Platform.isWindows) return null;
    return _instance ??= WindowsSystem._();
  }

  _GetSystemTimes? _getSystemTimes;
  _GlobalMemoryStatusEx? _globalMemoryStatusEx;
  _GetDiskFreeSpaceEx? _getDiskFreeSpaceEx;
  _GetSystemPowerStatus? _getSystemPowerStatus;
  _GetIfTable2? _getIfTable2;
  _FreeMibTable? _freeMibTable;

  /// Total bytes received and sent by the connected hardware adapters.
  NetCounters? networkCounters() {
    final getIfTable2 = _getIfTable2;
    final freeMibTable = _freeMibTable;
    if (getIfTable2 == null || freeMibTable == null) return null;
    final tablePointer = calloc<Pointer<Uint8>>();
    try {
      if (getIfTable2(tablePointer) != 0) return null;
      final table = tablePointer.value;
      if (table == nullptr) return null;
      try {
        final rows = table.cast<Uint32>().value;
        final bytes = table.asTypedList(
          _ifTable2RowsOffset + rows * ifRow2Size,
        );
        return parseIfTable2(ByteData.sublistView(bytes), rows);
      } finally {
        freeMibTable(table);
      }
    } finally {
      calloc.free(tablePointer);
    }
  }

  /// Cumulative CPU time. Kernel time includes idle time.
  CpuTimes? cpuTimes() {
    final getSystemTimes = _getSystemTimes;
    if (getSystemTimes == null) return null;
    final times = calloc<Uint64>(3);
    try {
      if (getSystemTimes(times, times + 1, times + 2) == 0) return null;
      final idle = times[0];
      return CpuTimes(idle: idle, total: times[1] + times[2]);
    } finally {
      calloc.free(times);
    }
  }

  RamStats? memory() {
    final globalMemoryStatusEx = _globalMemoryStatusEx;
    if (globalMemoryStatusEx == null) return null;
    final status = calloc<_MemoryStatusEx>();
    try {
      status.ref.dwLength = sizeOf<_MemoryStatusEx>();
      if (globalMemoryStatusEx(status) == 0) return null;
      final total = status.ref.ullTotalPhys;
      if (total <= 0) return null;
      final committed =
          status.ref.ullTotalPageFile - status.ref.ullAvailPageFile;
      final used = total - status.ref.ullAvailPhys;
      return RamStats(
        totalBytes: total,
        usedBytes: used,
        // Commit charge beyond physical memory is backed by the page file.
        swapUsedBytes: (committed - used).clamp(0, 1 << 62),
      );
    } finally {
      calloc.free(status);
    }
  }

  /// Space on [root], e.g. `C:\`.
  DiskStats? disk(String root) {
    final getDiskFreeSpaceEx = _getDiskFreeSpaceEx;
    if (getDiskFreeSpaceEx == null) return null;
    final path = root.toNativeUtf16();
    final values = calloc<Uint64>(3);
    try {
      if (getDiskFreeSpaceEx(path, values, values + 1, values + 2) == 0) {
        return null;
      }
      final freeToUser = values[0];
      final total = values[1];
      final totalFree = values[2];
      if (total <= 0) return null;
      return DiskStats(
        volume: root,
        totalBytes: total,
        usedBytes: total - totalFree,
        freeBytes: freeToUser,
      );
    } finally {
      calloc.free(path);
      calloc.free(values);
    }
  }

  /// Battery state, or `null` on machines without a battery.
  BatteryStats? battery() {
    final getSystemPowerStatus = _getSystemPowerStatus;
    if (getSystemPowerStatus == null) return null;
    final status = calloc<_SystemPowerStatus>();
    try {
      if (getSystemPowerStatus(status) == 0) return null;
      final flag = status.ref.batteryFlag;
      final percent = status.ref.batteryLifePercent;
      // 128 = no system battery, 255 = unknown status.
      if (flag == 255 || flag & 128 != 0 || percent > 100) return null;
      final onAc = status.ref.acLineStatus == 1;
      final charging = flag & 8 != 0;
      final state = charging
          ? BatteryState.charging
          : onAc
          ? (percent >= 100 ? BatteryState.full : BatteryState.notCharging)
          : BatteryState.discharging;
      final seconds = status.ref.batteryLifeTime;
      return BatteryStats(
        levelPercent: percent,
        state: state,
        timeRemainingMinutes:
            state == BatteryState.discharging && seconds != 0xFFFFFFFF
            ? seconds ~/ 60
            : null,
      );
    } finally {
      calloc.free(status);
    }
  }
}
