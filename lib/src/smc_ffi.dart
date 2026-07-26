import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// --- FFI Bindings for macOS IOKit Framework ---

typedef CIOServiceMatching = Pointer<Void> Function(Pointer<Utf8> name);
typedef DartIOServiceMatching = Pointer<Void> Function(Pointer<Utf8> name);

typedef CIOServiceGetMatchingService =
    Int32 Function(Uint32 mainPort, Pointer<Void> matching);
typedef DartIOServiceGetMatchingService =
    int Function(int mainPort, Pointer<Void> matching);

typedef CIOServiceOpen =
    Int32 Function(
      Int32 service,
      Uint32 owningTask,
      Uint32 type,
      Pointer<Uint32> connect,
    );
typedef DartIOServiceOpen =
    int Function(
      int service,
      int owningTask,
      int type,
      Pointer<Uint32> connect,
    );

typedef CIOServiceClose = Int32 Function(Uint32 connect);
typedef DartIOServiceClose = int Function(int connect);

typedef CIOConnectCallStructMethod =
    Int32 Function(
      Uint32 connect,
      Uint32 selector,
      Pointer<Void> inputStruct,
      Size inputStructSize,
      Pointer<Void> outputStruct,
      Pointer<Size> outputStructSize,
    );
typedef DartIOConnectCallStructMethod =
    int Function(
      int connect,
      int selector,
      Pointer<Void> inputStruct,
      int inputStructSize,
      Pointer<Void> outputStruct,
      Pointer<Size> outputStructSize,
    );

/// 80-byte C struct for Apple SMC IOKit calls
base class SmcParamStruct extends Struct {
  @Uint32()
  external int key;

  // 6 bytes vers
  @Uint8()
  external int vers0;
  @Uint8()
  external int vers1;
  @Uint8()
  external int vers2;
  @Uint8()
  external int vers3;
  @Uint8()
  external int vers4;
  @Uint8()
  external int vers5;

  // 16 bytes pLimitData
  @Uint8()
  external int pLimit0;
  @Uint8()
  external int pLimit1;
  @Uint8()
  external int pLimit2;
  @Uint8()
  external int pLimit3;
  @Uint8()
  external int pLimit4;
  @Uint8()
  external int pLimit5;
  @Uint8()
  external int pLimit6;
  @Uint8()
  external int pLimit7;
  @Uint8()
  external int pLimit8;
  @Uint8()
  external int pLimit9;
  @Uint8()
  external int pLimit10;
  @Uint8()
  external int pLimit11;
  @Uint8()
  external int pLimit12;
  @Uint8()
  external int pLimit13;
  @Uint8()
  external int pLimit14;
  @Uint8()
  external int pLimit15;

  // 12 bytes keyInfo (dataSize @ 28, dataType @ 32, dataAttributes @ 36)
  @Uint32()
  external int keyInfoDataSize;
  @Uint32()
  external int keyInfoDataType;
  @Uint8()
  external int keyInfoDataAttributes;
  @Uint8()
  external int keyInfoPad0;
  @Uint8()
  external int keyInfoPad1;
  @Uint8()
  external int keyInfoPad2;

  @Uint8()
  external int result;
  @Uint8()
  external int status;
  @Uint8()
  external int data8;

  @Uint32()
  external int data32;

  // 32 bytes payload bytes
  @Uint8()
  external int b0;
  @Uint8()
  external int b1;
  @Uint8()
  external int b2;
  @Uint8()
  external int b3;
  @Uint8()
  external int b4;
  @Uint8()
  external int b5;
  @Uint8()
  external int b6;
  @Uint8()
  external int b7;
  @Uint8()
  external int b8;
  @Uint8()
  external int b9;
  @Uint8()
  external int b10;
  @Uint8()
  external int b11;
  @Uint8()
  external int b12;
  @Uint8()
  external int b13;
  @Uint8()
  external int b14;
  @Uint8()
  external int b15;
  @Uint8()
  external int b16;
  @Uint8()
  external int b17;
  @Uint8()
  external int b18;
  @Uint8()
  external int b19;
  @Uint8()
  external int b20;
  @Uint8()
  external int b21;
  @Uint8()
  external int b22;
  @Uint8()
  external int b23;
  @Uint8()
  external int b24;
  @Uint8()
  external int b25;
  @Uint8()
  external int b26;
  @Uint8()
  external int b27;
  @Uint8()
  external int b28;
  @Uint8()
  external int b29;
  @Uint8()
  external int b30;
  @Uint8()
  external int b31;
}

/// 100% Pure Dart Apple SMC (System Management Controller) Manager
class AppleSmc {
  static AppleSmc? _instance;
  static AppleSmc get shared => _instance ??= AppleSmc._();

  DynamicLibrary? _ioKit;
  DartIOServiceMatching? _ioServiceMatching;
  DartIOServiceGetMatchingService? _ioServiceGetMatchingService;
  DartIOServiceOpen? _ioServiceOpen;
  DartIOServiceClose? _ioServiceClose;
  DartIOConnectCallStructMethod? _ioConnectCallStructMethod;

  int _connection = 0;
  bool _isInitialized = false;

  AppleSmc._() {
    if (!Platform.isMacOS) return;
    try {
      _ioKit = DynamicLibrary.open(
        '/System/Library/Frameworks/IOKit.framework/IOKit',
      );

      _ioServiceMatching = _ioKit!
          .lookupFunction<CIOServiceMatching, DartIOServiceMatching>(
            'IOServiceMatching',
          );
      _ioServiceGetMatchingService = _ioKit!
          .lookupFunction<
            CIOServiceGetMatchingService,
            DartIOServiceGetMatchingService
          >('IOServiceGetMatchingService');
      _ioServiceOpen = _ioKit!
          .lookupFunction<CIOServiceOpen, DartIOServiceOpen>('IOServiceOpen');
      _ioServiceClose = _ioKit!
          .lookupFunction<CIOServiceClose, DartIOServiceClose>(
            'IOServiceClose',
          );
      _ioConnectCallStructMethod = _ioKit!
          .lookupFunction<
            CIOConnectCallStructMethod,
            DartIOConnectCallStructMethod
          >('IOConnectCallStructMethod');

      _openSMC();
    } catch (_) {}
  }

  void _openSMC() {
    if (_ioKit == null || _ioServiceMatching == null) return;
    final namePtr = 'AppleSMC'.toNativeUtf8();
    final matching = _ioServiceMatching!(namePtr);
    malloc.free(namePtr);

    final service = _ioServiceGetMatchingService!(0, matching);
    if (service == 0) return;

    final connPtr = calloc<Uint32>();
    final res = _ioServiceOpen!(service, 0, 0, connPtr);
    if (res == 0) {
      _connection = connPtr.value;
      _isInitialized = true;
    }
    calloc.free(connPtr);
  }

  bool get isAvailable => _isInitialized && _connection != 0;

  /// Helper to convert 4-character string key to 32-bit uint32 SMC key
  int _strToKey(String key) {
    if (key.length != 4) return 0;
    final codeUnits = key.codeUnits;
    return (codeUnits[0] << 24) |
        (codeUnits[1] << 16) |
        (codeUnits[2] << 8) |
        codeUnits[3];
  }

  /// Helper to convert 32-bit uint32 to String
  String _typeToStr(int type) {
    final c1 = String.fromCharCode((type >> 24) & 0xFF);
    final c2 = String.fromCharCode((type >> 16) & 0xFF);
    final c3 = String.fromCharCode((type >> 8) & 0xFF);
    final c4 = String.fromCharCode(type & 0xFF);
    return '$c1$c2$c3$c4';
  }

  /// Read raw SMC value for a 4-character key
  double? readKey(String key) {
    if (!isAvailable) return null;

    final inputPtr = calloc<SmcParamStruct>();
    final outputPtr = calloc<SmcParamStruct>();
    final sizePtr = calloc<Size>();
    sizePtr.value = sizeOf<SmcParamStruct>();

    try {
      final keyInt = _strToKey(key);
      inputPtr.ref.key = keyInt;
      inputPtr.ref.data8 = 9; // SMC_CMD_READ_KEYINFO

      // Query Key Info
      var result = _ioConnectCallStructMethod!(
        _connection,
        2, // KERNEL_INDEX_SMC
        inputPtr.cast<Void>(),
        sizeOf<SmcParamStruct>(),
        outputPtr.cast<Void>(),
        sizePtr,
      );

      if (result != 0) return null;

      final dataSize = outputPtr.ref.keyInfoDataSize;
      final dataType = outputPtr.ref.keyInfoDataType;
      final typeStr = _typeToStr(dataType).trim();

      // Read Key Bytes
      inputPtr.ref.key = keyInt;
      inputPtr.ref.keyInfoDataSize = dataSize;
      inputPtr.ref.data8 = 5; // SMC_CMD_READ_BYTES

      result = _ioConnectCallStructMethod!(
        _connection,
        2,
        inputPtr.cast<Void>(),
        sizeOf<SmcParamStruct>(),
        outputPtr.cast<Void>(),
        sizePtr,
      );

      if (result != 0) return null;

      final b0 = outputPtr.ref.b0;
      final b1 = outputPtr.ref.b1;
      final b2 = outputPtr.ref.b2;
      final b3 = outputPtr.ref.b3;

      if (typeStr == 'fpe2') {
        // Fan RPM fixed point (14.2)
        return ((b0 << 8) | b1) / 4.0;
      } else if (typeStr == 'sp78') {
        // Signed 8.8 fixed point (Temperature °C)
        final int val = (b0 << 8) | b1;
        final signedVal = val > 32767 ? val - 65536 : val;
        return signedVal / 256.0;
      } else if (typeStr == 'flt') {
        // 32-bit IEEE float
        final bytes = Uint8List.fromList([b3, b2, b1, b0]);
        final byteData = ByteData.view(bytes.buffer);
        return byteData.getFloat32(0, Endian.little);
      } else if (typeStr == 'ui8') {
        return b0.toDouble();
      } else if (typeStr == 'ui16') {
        return ((b0 << 8) | b1).toDouble();
      } else if (typeStr == 'ui32') {
        return ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3).toDouble();
      }

      return ((b0 << 8) | b1).toDouble();
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
      calloc.free(sizePtr);
    }
  }

  /// Write SMC value for a 4-character key matching stats SMC implementation
  bool writeKey(String key, int value, {int dataSize = 2}) {
    if (!isAvailable) return false;

    final inputPtr = calloc<SmcParamStruct>();
    final outputPtr = calloc<SmcParamStruct>();
    final sizePtr = calloc<Size>();
    sizePtr.value = sizeOf<SmcParamStruct>();

    try {
      final keyInt = _strToKey(key);

      // Query Key Info
      inputPtr.ref.key = keyInt;
      inputPtr.ref.data8 = 9; // SMC_CMD_READ_KEYINFO

      var result = _ioConnectCallStructMethod!(
        _connection,
        2,
        inputPtr.cast<Void>(),
        sizeOf<SmcParamStruct>(),
        outputPtr.cast<Void>(),
        sizePtr,
      );

      if (result != 0) return false;

      final actualSize = outputPtr.ref.keyInfoDataSize;

      // Prepare Write Command
      inputPtr.ref.key = keyInt;
      inputPtr.ref.keyInfoDataSize = actualSize;
      inputPtr.ref.data8 = 6; // SMC_CMD_WRITE_BYTES

      // Encode fpe2 / ui8 value for Fan control matching stats
      final fpe2Val = (value * 4).clamp(0, 65535);
      inputPtr.ref.b0 = (fpe2Val >> 8) & 0xFF;
      inputPtr.ref.b1 = fpe2Val & 0xFF;

      result = _ioConnectCallStructMethod!(
        _connection,
        2,
        inputPtr.cast<Void>(),
        sizeOf<SmcParamStruct>(),
        outputPtr.cast<Void>(),
        sizePtr,
      );

      return result == 0;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
      calloc.free(sizePtr);
    }
  }

  /// Unlock fan control on Apple Silicon (M1-M4) Macs matching stats algorithm
  bool unlockFanControl(int fanId) {
    if (!isAvailable) return false;

    final modeKey = 'F${fanId}Md';
    if (writeKey(modeKey, 1, dataSize: 1)) {
      return true;
    }

    // Try 'Ftst' unlock for Apple Silicon (M1-M4)
    writeKey('Ftst', 1, dataSize: 1);
    sleep(const Duration(milliseconds: 100));

    for (int attempt = 0; attempt < 5; attempt++) {
      if (writeKey(modeKey, 1, dataSize: 1)) {
        return true;
      }
      sleep(const Duration(milliseconds: 50));
    }
    return false;
  }

  /// Read total number of fans available on system ('FNum')
  int getFanCount() {
    final count = readKey('FNum');
    return count?.toInt() ?? 0;
  }

  /// Check if fan control is supported on current hardware (fan count > 0 and hardware min/max keys exist)
  bool isFanControlSupported() {
    if (!isAvailable) return false;
    final count = getFanCount();
    if (count <= 0) return false;

    final minRpm = readKey('F0Mn');
    final maxRpm = readKey('F0Mx');
    return minRpm != null && maxRpm != null && maxRpm > minRpm;
  }

  /// Set mode and target RPM dynamically based on hardware `F<id>Mn` & `F<id>Mx` keys
  bool setFanSpeed(int fanIndex, int percentage, {bool manual = true}) {
    if (!isAvailable) return false;

    final minRpm = readKey('F${fanIndex}Mn');
    final maxRpm = readKey('F${fanIndex}Mx');

    // If hardware min or max RPM registers cannot be found, assume unsupported and do not allow change
    if (minRpm == null || maxRpm == null || maxRpm <= minRpm) {
      return false;
    }

    final modeKey = 'F${fanIndex}Md';
    final targetKey = 'F${fanIndex}Tg';

    if (manual) {
      // 1. Unlock fan control if locked on Apple Silicon
      unlockFanControl(fanIndex);

      int speedToSet;
      if (percentage >= 100) {
        speedToSet = maxRpm.round();
      } else if (percentage <= 0) {
        speedToSet = minRpm.round();
      } else {
        // Dynamic linear interpolation between hardware min and max
        speedToSet = (minRpm + ((maxRpm - minRpm) * (percentage / 100.0)))
            .round();
      }

      // 2. Write target RPM to F<id>Tg key
      writeKey(modeKey, 1, dataSize: 1);
      return writeKey(targetKey, speedToSet);
    } else {
      // Automatic Mode: reset Ftst and F0Md to 0
      writeKey('Ftst', 0, dataSize: 1);
      writeKey(modeKey, 0, dataSize: 1);
      writeKey(targetKey, 0);
      return true;
    }
  }

  /// Close Apple SMC connection
  void close() {
    if (_connection != 0 && _ioServiceClose != null) {
      _ioServiceClose!(_connection);
      _connection = 0;
      _isInitialized = false;
    }
  }
}
