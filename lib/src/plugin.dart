import 'dart:async';
import 'package:lumide_api/lumide_api.dart';

import 'config.dart';
import 'menu_handler.dart';
import 'status_bar_manager.dart';
import 'system_stats_collector.dart';

/// Main Lumide IDE Status Bar System Monitor Plugin
class LumideStatusBarStatsPlugin extends LumidePlugin {
  late final LumideStatsConfig _config;
  late final SystemStatsCollector _collector;
  late final StatusBarManager _statusBarManager;
  late final MenuHandler _menuHandler;

  Timer? _timer;
  bool _isTicking = false;
  int _userSetInterval =
      2; // Remembers user interval when toggling Battery Saver

  @override
  Future<void> onActivate(LumideContext context) async {
    log('Activating Lumide Status Bar System Monitor Plugin...');

    // Load workspace settings
    _config = await LumideStatsConfig.loadFromWorkspace(context.workspace);
    _userSetInterval = _config.updateIntervalSeconds;

    _collector = SystemStatsCollector();
    _statusBarManager = StatusBarManager(context.statusBar, _config);
    _menuHandler = MenuHandler(
      context: context,
      config: _config,
      collector: _collector,
      statusBarManager: _statusBarManager,
    );

    // Listen for live settings changes in Lumide IDE
    try {
      context.workspace.onDidChangeConfiguration((settings) {
        log('Lumide Stats: Workspace settings updated');
        _config.updateFromMap(settings);
        _userSetInterval = _config.updateIntervalSeconds;
        _setupToolbar(context);
        _resetTimer();
        _tick();
      });
    } catch (_) {}

    // Register commands
    await _menuHandler.registerCommands();

    // Register Toolbar item if supported
    await _setupToolbar(context);

    // Perform initial collection and update
    await _tick();

    // Start periodic polling timer
    _resetTimer();

    log('Lumide Status Bar System Monitor Plugin activated successfully!');
  }

  Future<void> _setupToolbar(LumideContext context) async {
    try {
      if (_config.showTopBarIcon) {
        await context.toolbar.registerItem(
          id: 'lumide_stats_toolbar_menu',
          icon: 'gauge',
          tooltip: 'System Stats Quick Menu',
          alignment: ToolbarItemAlignment.left,
          priority: 100,
        );
      } else {
        await context.toolbar.unregisterItem('lumide_stats_toolbar_menu');
      }

      context.toolbar.onTap((id, position) {
        if (id == 'lumide_stats_toolbar_menu') {
          _menuHandler.showQuickMenu(position);
        }
      });
    } catch (_) {}
  }

  void _resetTimer() {
    _timer?.cancel();
    final interval = _config.updateIntervalSeconds;
    _timer = Timer.periodic(Duration(seconds: interval), (_) async {
      await _tick();
    });
  }

  Future<void> _tick() async {
    if (_isTicking) return; // Prevent concurrent overlapping ticks
    _isTicking = true;
    try {
      final snapshot = await _collector.collect();

      // Battery Saver Mode Logic:
      // If on battery, throttle to 10s. If AC power is re-connected, restore user configured interval!
      if (_config.batterySaverMode && snapshot.battery.isPresent) {
        if (!snapshot.battery.isCharging &&
            _config.updateIntervalSeconds < 10) {
          _userSetInterval = _config.updateIntervalSeconds;
          _config.updateIntervalSeconds = 10;
          _resetTimer();
        } else if (snapshot.battery.isCharging &&
            _config.updateIntervalSeconds != _userSetInterval) {
          _config.updateIntervalSeconds = _userSetInterval;
          _resetTimer();
        }
      }

      _menuHandler.updateSnapshot(snapshot);
      await _statusBarManager.update(snapshot);
    } catch (e, st) {
      log('Error updating system stats: $e\n$st');
    } finally {
      _isTicking = false;
    }
  }

  @override
  Future<void> onDeactivate() async {
    log('Deactivating Lumide Status Bar System Monitor Plugin...');
    _timer?.cancel();
    await _statusBarManager.disposeAll();
    log('Lumide Status Bar System Monitor Plugin deactivated.');
  }
}
