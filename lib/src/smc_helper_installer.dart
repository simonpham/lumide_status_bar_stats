import 'dart:io';

import 'smc_ffi.dart';

class FanInfo {
  final int index;
  final double minRpm;
  final double maxRpm;
  final double actualRpm;
  final double targetRpm;
  final String mode;

  FanInfo({
    required this.index,
    required this.minRpm,
    required this.maxRpm,
    required this.actualRpm,
    required this.targetRpm,
    required this.mode,
  });
}

/// Manager for installing and executing the persistent passwordless SMC Fan Helper on macOS
class SmcHelperInstaller {
  static final String _userHome = Platform.environment['HOME'] ?? '';
  static final String helperPath = '$_userHome/.lumide/bin/lumide-smc-helper';
  static const String sudoersPath = '/etc/sudoers.d/lumide-smc-helper';

  /// Check if the helper script and sudoers permission rule are already installed
  static Future<bool> isInstalled() async {
    if (!Platform.isMacOS) return false;
    final file = File(helperPath);
    if (!await file.exists()) return false;

    try {
      final res = await Process.run('sudo', ['-n', helperPath, 'fans']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Get list of hardware fans with dynamic min/max RPM specs from helper or SMC FFI
  static Future<List<FanInfo>> getFanSpecs() async {
    if (!Platform.isMacOS) return [];

    final file = File(helperPath);
    if (await file.exists()) {
      try {
        final res = await Process.run('sudo', ['-n', helperPath, 'fans']);
        if (res.exitCode == 0) {
          final lines = (res.stdout as String).split('\n');
          final fans = <FanInfo>[];

          int currentIdx = -1;
          double minRpm = 0;
          double maxRpm = 0;
          double actualRpm = 0;
          double targetRpm = 0;
          String mode = 'automatic';

          for (final rawLine in lines) {
            final line = rawLine.trim();
            if (line.contains('Fan #')) {
              if (currentIdx >= 0 && maxRpm > 0) {
                fans.add(
                  FanInfo(
                    index: currentIdx,
                    minRpm: minRpm,
                    maxRpm: maxRpm,
                    actualRpm: actualRpm,
                    targetRpm: targetRpm,
                    mode: mode,
                  ),
                );
              }
              final parts = line.split('#');
              if (parts.length > 1) {
                currentIdx = int.tryParse(parts[1]) ?? 0;
              }
              minRpm = 0;
              maxRpm = 0;
              actualRpm = 0;
              targetRpm = 0;
              mode = 'automatic';
            } else if (line.startsWith('Minimal speed:')) {
              minRpm = double.tryParse(line.split(':')[1].trim()) ?? 0;
            } else if (line.startsWith('Maximum speed:')) {
              maxRpm = double.tryParse(line.split(':')[1].trim()) ?? 0;
            } else if (line.startsWith('Actual speed:')) {
              actualRpm = double.tryParse(line.split(':')[1].trim()) ?? 0;
            } else if (line.startsWith('Target speed:')) {
              targetRpm = double.tryParse(line.split(':')[1].trim()) ?? 0;
            } else if (line.startsWith('Mode:')) {
              mode = line.split(':')[1].trim();
            }
          }

          if (currentIdx >= 0 && maxRpm > 0) {
            fans.add(
              FanInfo(
                index: currentIdx,
                minRpm: minRpm,
                maxRpm: maxRpm,
                actualRpm: actualRpm,
                targetRpm: targetRpm,
                mode: mode,
              ),
            );
          }

          if (fans.isNotEmpty) return fans;
        }
      } catch (_) {}
    }

    // Fallback to AppleSmc FFI if helper is not yet initialized
    if (AppleSmc.shared.isAvailable) {
      final count = AppleSmc.shared.getFanCount();
      final fans = <FanInfo>[];
      for (int i = 0; i < count; i++) {
        final minRpm = AppleSmc.shared.readKey('F${i}Mn');
        final maxRpm = AppleSmc.shared.readKey('F${i}Mx');
        if (minRpm != null && maxRpm != null && maxRpm > minRpm) {
          fans.add(
            FanInfo(
              index: i,
              minRpm: minRpm,
              maxRpm: maxRpm,
              actualRpm: AppleSmc.shared.readKey('F${i}Ac') ?? minRpm,
              targetRpm: AppleSmc.shared.readKey('F${i}Tg') ?? minRpm,
              mode: 'automatic',
            ),
          );
        }
      }
      return fans;
    }

    return [];
  }

  /// Check if hardware fan control is supported on current system
  static Future<bool> isSupported() async {
    final fans = await getFanSpecs();
    return fans.isNotEmpty;
  }

  /// Compile helper binary from stats SMC source and create sudoers rule
  static Future<bool> install() async {
    if (!Platform.isMacOS) return false;

    try {
      final binDir = Directory('$_userHome/.lumide/bin');
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }

      final compileRes = await Process.run('swiftc', [
        '-O',
        '/Users/simon/Projects/Lumide/agyw/stats/SMC/smc.swift',
        '/Users/simon/Projects/Lumide/agyw/stats/SMC/main.swift',
        '-o',
        helperPath,
      ]);

      if (compileRes.exitCode != 0) {
        return false;
      }

      final userName = Platform.environment['USER'] ?? '';
      final sudoersRule = '$userName ALL=(ALL) NOPASSWD: $helperPath';

      final script =
          'do shell script "echo \\"$sudoersRule\\" > $sudoersPath && chmod 0440 $sudoersPath" with administrator privileges';

      final res = await Process.run('osascript', ['-e', script]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Run fan control command via helper under passwordless sudo dynamically calculating hardware speeds
  static Future<bool> setMode(String mode) async {
    if (!Platform.isMacOS) return false;

    try {
      final file = File(helperPath);
      if (!await file.exists()) return false;

      final fans = await getFanSpecs();
      if (fans.isEmpty) return false;

      if (mode == 'Auto') {
        for (final fan in fans) {
          await Process.run('sudo', [
            '-n',
            helperPath,
            'fan',
            '${fan.index}',
            '-m',
            '0',
          ]);
        }
      } else {
        double percentage = 1.0;
        if (mode == '75%') percentage = 0.75;
        if (mode == '50%') percentage = 0.50;
        if (mode == '25%') percentage = 0.25;
        if (mode == 'Quiet' || mode == 'Eco' || mode == '0%') percentage = 0.0;

        for (final fan in fans) {
          final targetSpeed =
              (fan.minRpm + ((fan.maxRpm - fan.minRpm) * percentage)).round();

          await Process.run('sudo', [
            '-n',
            helperPath,
            'fan',
            '${fan.index}',
            '-m',
            '1',
            '-v',
            '$targetSpeed',
          ]);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
