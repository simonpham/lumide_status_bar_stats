/// Disk space through libc on Linux and macOS, without spawning `df`.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../models/system_stats.dart';

typedef _StatC = Int32 Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _Stat = int Function(Pointer<Utf8>, Pointer<Uint8>);

/// Large enough for `struct statvfs` (112 bytes on 64-bit Linux) and
/// `struct statfs` (2168 bytes on macOS).
const _bufferSize = 4096;

/// Builds [DiskStats] from filesystem block counts, the way `df -kP` reports
/// them: used = total - free, and free space is what non-root users can use.
///
/// Returns `null` for values that can't be right, so callers can fall back
/// to `df`.
DiskStats? diskStatsFromBlocks({
  required String volume,
  required int blockSize,
  required int blocks,
  required int freeBlocks,
  required int availableBlocks,
}) {
  if (blockSize <= 0 || blockSize > (1 << 24) || blocks <= 0) return null;
  if (freeBlocks < 0 || freeBlocks > blocks) return null;
  if (availableBlocks < 0 || availableBlocks > blocks) return null;
  return DiskStats(
    volume: volume,
    totalBytes: blocks * blockSize,
    usedBytes: (blocks - freeBlocks) * blockSize,
    freeBytes: availableBlocks * blockSize,
  );
}

/// Reads disk space with `statvfs` (Linux) or `statfs` (macOS).
class PosixDisk {
  PosixDisk._() {
    try {
      final libc = DynamicLibrary.process();
      if (Platform.isLinux && sizeOf<IntPtr>() == 8) {
        _stat = libc.lookupFunction<_StatC, _Stat>('statvfs');
      } else if (Platform.isMacOS) {
        // Intel Macs export the 64-bit-inode layout under a suffixed name;
        // on Apple Silicon it is the only `statfs`.
        _stat = libc.providesSymbol(r'statfs$INODE64')
            ? libc.lookupFunction<_StatC, _Stat>(r'statfs$INODE64')
            : Abi.current() == Abi.macosArm64
            ? libc.lookupFunction<_StatC, _Stat>('statfs')
            : null;
      }
    } catch (_) {
      _stat = null;
    }
  }

  static PosixDisk? _instance;

  /// The shared instance, or `null` on platforms without a known layout
  /// (Windows, 32-bit Linux).
  static PosixDisk? get instance {
    final disk = _instance ??= PosixDisk._();
    return disk._stat == null ? null : disk;
  }

  _Stat? _stat;

  /// Space on the filesystem holding [path], or `null` if it can't be read.
  DiskStats? read(String path) {
    final stat = _stat;
    if (stat == null) return null;
    final nativePath = path.toNativeUtf8();
    final buffer = calloc<Uint8>(_bufferSize);
    try {
      if (stat(nativePath, buffer) != 0) return null;
      final words = buffer.cast<Uint64>();
      if (Platform.isLinux) {
        // struct statvfs: f_bsize, f_frsize, f_blocks, f_bfree, f_bavail
        // (all 64-bit). Block counts are in f_frsize units.
        return diskStatsFromBlocks(
          volume: path,
          blockSize: words[1],
          blocks: words[2],
          freeBlocks: words[3],
          availableBlocks: words[4],
        );
      }
      // struct statfs (64-bit inodes): uint32 f_bsize, int32 f_iosize,
      // uint64 f_blocks, f_bfree, f_bavail.
      return diskStatsFromBlocks(
        volume: path,
        blockSize: buffer.cast<Uint32>()[0],
        blocks: words[1],
        freeBlocks: words[2],
        availableBlocks: words[3],
      );
    } finally {
      calloc.free(nativePath);
      calloc.free(buffer);
    }
  }
}
