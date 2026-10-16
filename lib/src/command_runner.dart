import 'dart:async';
import 'dart:io';

/// Runs short system commands and makes sure none outlive their timeout or
/// the plugin.
class CommandRunner {
  final _running = <Process>{};
  bool _disposed = false;

  /// Number of processes started so far.
  int get started => _started;
  int _started = 0;

  /// Process ids of the commands that are still running.
  Set<int> get runningPids => {for (final p in _running) p.pid};

  /// Runs [executable] and returns its stdout, or `null` if it can't be
  /// started, exits with an error or takes longer than [timeout].
  ///
  /// On timeout the process is killed with SIGKILL: a command stuck that
  /// long may not react to SIGTERM. The commands this plugin runs don't
  /// start processes of their own, so there is no process tree to kill.
  Future<String?> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_disposed) return null;
    final Process process;
    try {
      process = await Process.start(executable, arguments);
    } on ProcessException {
      return null;
    }
    _started++;
    if (_disposed) {
      process.kill(ProcessSignal.sigkill);
      return null;
    }
    _running.add(process);
    // Read both pipes to the end so the process never blocks on a full pipe.
    // Errors only mean the output is lost; that is reported as `null`.
    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .join()
        .then<String?>((output) => output, onError: (Object _) => null);
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      final output = await stdoutFuture;
      return exitCode == 0 ? output : null;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return null;
    } finally {
      _running.remove(process);
    }
  }

  /// Kills every running command and refuses to start new ones. Pending
  /// [run] calls return `null`.
  void dispose() {
    _disposed = true;
    for (final process in _running) {
      process.kill(ProcessSignal.sigkill);
    }
  }
}
