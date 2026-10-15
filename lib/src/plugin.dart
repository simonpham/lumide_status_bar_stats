import 'dart:async';
import 'dart:math' show max;

import 'package:lumide_api/lumide_api.dart';

import 'config.dart';
import 'menu_handler.dart';
import 'models/system_stats.dart';
import 'status_bar_manager.dart';
import 'system_stats_collector.dart';

const _toolbarItemId = 'lumide_stats_toolbar_menu';

/// Shows CPU, memory, disk, network, battery and temperature in Lumide's
/// status bar.
class LumideStatusBarStatsPlugin extends LumidePlugin {
  late LumideContext _context;
  late LumideStatsConfig _config;
  late StatusBarManager _statusBar;
  late MenuHandler _menu;
  final _collector = SystemStatsCollector();

  Timer? _timer;
  Duration? _timerInterval;
  Future<void>? _tickInFlight;
  SystemStatsSnapshot? _latest;
  bool? _toolbarShown;
  bool _active = false;

  @override
  Future<void> onActivate(LumideContext context) async {
    _context = context;
    _config = await LumideStatsConfig.load(context.workspace);
    _statusBar = StatusBarManager(context.statusBar, _config);
    _menu = MenuHandler(
      context: context,
      config: _config,
      setSetting: _setSetting,
      refresh: _refresh,
      latestSnapshot: () async => _latest ?? await _collect(),
    );
    _active = true;

    await _menu.registerCommands();
    // Listeners are registered once and never removed: they return
    // nothing before lumide_api 1.12, and the process exits after
    // deactivation. `_active` stops them from doing work in between.
    context.workspace.onDidChangeConfiguration((settings) {
      _config.apply(settings);
      unawaited(_onConfigChanged());
    });
    context.toolbar.onTap((id, position) {
      if (_active && id == _toolbarItemId) {
        unawaited(_menu.showQuickMenu(position.isEmpty ? null : position));
      }
    });

    await _syncToolbar();
    _scheduleTimer();
    // Don't hold up activation while the first sample is taken.
    unawaited(_refresh());
  }

  @override
  Future<void> onDeactivate() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    try {
      await _menu.dispose();
      await _statusBar.disposeAll();
      if (_toolbarShown == true) {
        await _context.toolbar.unregisterItem(_toolbarItemId);
      }
    } catch (_) {
      // Lumide may already have closed the connection.
    }
  }

  /// Saves [key] to Lumide's settings and applies it right away.
  Future<void> _setSetting(String key, Object value) async {
    _config.apply({key: value});
    await _onConfigChanged();
    try {
      await _context.workspace.updateConfiguration(key, value);
    } catch (e) {
      log('System Stats: could not save $key: $e');
    }
  }

  Future<void> _onConfigChanged() async {
    if (!_active) return;
    await _syncToolbar();
    _scheduleTimer();
    final latest = _latest;
    // Redraw at once with the new display settings, then fetch metrics that
    // may have just been enabled.
    if (latest != null) await _statusBar.update(latest);
    await _refresh();
  }

  Future<void> _syncToolbar() async {
    final show = _config.showTopBarIcon;
    if (_toolbarShown == show) return;
    try {
      if (show) {
        await _context.toolbar.registerItem(
          id: _toolbarItemId,
          icon: 'gauge',
          tooltip: 'System Stats',
          alignment: ToolbarItemAlignment.left,
          priority: 100,
        );
      } else if (_toolbarShown != null) {
        await _context.toolbar.unregisterItem(_toolbarItemId);
      }
      _toolbarShown = show;
    } catch (e) {
      log('System Stats: toolbar unavailable: $e');
    }
  }

  /// The configured interval, slowed down on battery power when battery
  /// saver is on.
  Duration get _interval {
    var seconds = _config.updateIntervalSeconds;
    if (_config.batterySaverMode && (_latest?.battery?.isOnBattery ?? false)) {
      seconds = max(seconds, LumideStatsConfig.batterySaverInterval);
    }
    return Duration(seconds: seconds);
  }

  void _scheduleTimer() {
    final interval = _interval;
    if (!_active || (_timer != null && _timerInterval == interval)) return;
    _timer?.cancel();
    _timerInterval = interval;
    _timer = Timer.periodic(interval, (_) => unawaited(_refresh()));
  }

  Set<Metric> get _metricsToCollect {
    if (_menu.isDashboardOpen) return Metric.values.toSet();
    return {
      for (final metric in _config.enabledMetrics)
        if (_collectorMetric(metric) != null) _collectorMetric(metric)!,
      // Battery saver needs to know the power source.
      if (_config.batterySaverMode) Metric.battery,
    };
  }

  static Metric? _collectorMetric(StatusMetric metric) => switch (metric) {
        StatusMetric.cpu => Metric.cpu,
        StatusMetric.ram => Metric.ram,
        StatusMetric.disk => Metric.disk,
        StatusMetric.network => Metric.network,
        StatusMetric.battery => Metric.battery,
        StatusMetric.thermal => Metric.thermal,
        StatusMetric.uptime => null,
      };

  Future<SystemStatsSnapshot> _collect() async {
    final snapshot = await _collector.collect(
      metrics: _metricsToCollect,
      includeProcesses: _menu.isDashboardOpen,
    );
    _latest = snapshot;
    return snapshot;
  }

  /// Collects metrics and updates the status bar and dashboard. Calls made
  /// while a refresh is running share it.
  Future<void> _refresh() => _tickInFlight ??= _tick().whenComplete(() {
        _tickInFlight = null;
      });

  Future<void> _tick() async {
    if (!_active) return;
    try {
      final snapshot = await _collect();
      if (!_active) return;
      _scheduleTimer(); // Battery saver may have changed the interval.
      await _statusBar.update(snapshot);
      await _menu.pushSnapshot(snapshot);
    } catch (e, st) {
      log('System Stats: update failed: $e\n$st');
    }
  }
}
