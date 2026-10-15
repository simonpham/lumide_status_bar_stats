import 'dart:convert';
import 'package:lumide_api/lumide_api.dart';

import 'config.dart';
import 'models/system_stats.dart';
import 'status_bar_manager.dart';
import 'system_stats_collector.dart';

/// Interactive QuickPick Menu, Commands, and Dashboard Handler for Lumide Stats Plugin
class MenuHandler {
  final LumideContext context;
  final LumideStatsConfig config;
  final SystemStatsCollector collector;
  final StatusBarManager statusBarManager;

  SystemStatsSnapshot? _latestSnapshot;
  LumideWebviewPanel? _dashboardPanel;

  MenuHandler({
    required this.context,
    required this.config,
    required this.collector,
    required this.statusBarManager,
  });

  /// Update the latest snapshot reference and post real-time updates to Webview panel
  void updateSnapshot(SystemStatsSnapshot snapshot) {
    _latestSnapshot = snapshot;
    if (_dashboardPanel != null) {
      final jsonStr = jsonEncode({
        'type': 'update',
        'data': _latestSnapshot!.toJson(),
      });
      final safeJson = jsonStr.replaceAll("'", r"\'");
      try {
        _dashboardPanel!.postMessage(safeJson);
      } catch (_) {
        _dashboardPanel = null;
      }
    }
  }

  /// Safely parse position coordinates from host command arguments
  Map<String, int>? _parsePosition(Map<String, dynamic>? args) {
    if (args == null) return null;
    if (args['x'] is num && args['y'] is num) {
      return {'x': (args['x'] as num).toInt(), 'y': (args['y'] as num).toInt()};
    }
    if (args['position'] is Map) {
      final posMap = args['position'] as Map;
      if (posMap['x'] is num && posMap['y'] is num) {
        return {
          'x': (posMap['x'] as num).toInt(),
          'y': (posMap['y'] as num).toInt(),
        };
      }
    }
    return null;
  }

  /// Extract metric identifier from clicked status bar item arguments
  String? _parseMetricId(Map<String, dynamic>? args) {
    if (args == null) return null;
    final rawId =
        args['id']?.toString() ??
        args['itemId']?.toString() ??
        args['metric']?.toString();
    if (rawId != null) {
      if (rawId.contains('cpu')) return 'cpu';
      if (rawId.contains('ram')) return 'ram';
      if (rawId.contains('disk')) return 'disk';
      if (rawId.contains('network')) return 'network';
      if (rawId.contains('battery')) return 'battery';
      if (rawId.contains('thermal')) return 'thermal';
      if (rawId.contains('uptime')) return 'uptime';
    }
    return null;
  }

  /// Extract explicit item payload key robustly from QuickPick selection
  String _extractSelectedKey(
    QuickPickItem selected,
    List<QuickPickItem> items,
  ) {
    final payload = selected.payload;

    if (payload is String) {
      return payload;
    }
    if (payload is num) {
      return payload.toString();
    }

    if (payload is Map) {
      if (payload['payload'] != null) {
        return payload['payload'].toString();
      }
      if (payload['label'] is String) {
        final label = payload['label'] as String;
        for (final item in items) {
          if (item.payload != null &&
              (label.contains(item.label) || item.label.contains(label))) {
            return item.payload.toString();
          }
        }
      }
    }

    for (final item in items) {
      if (item.payload != null) {
        final pStr = item.payload.toString();
        if (selected.label == pStr ||
            selected.label.contains(item.label) ||
            item.label.contains(selected.label)) {
          return pStr;
        }
      }
    }

    return '';
  }

  /// Register commands with Lumide IDE
  Future<void> registerCommands() async {
    await context.commands.registerCommand(
      id: 'lumide-stats.showQuickMenu',
      title: 'Lumide Stats: Open Quick Menu',
      category: 'System Stats',
      callback: ([args]) async {
        final pos = _parsePosition(args);
        final metric = _parseMetricId(args);
        await showQuickMenu(pos, metric);
      },
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.showDashboard',
      title: 'Lumide Stats: Show Detailed Dashboard',
      category: 'System Stats',
      callback: ([args]) async => showDashboard(),
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.toggleCpu',
      title: 'Lumide Stats: Toggle CPU Metric',
      category: 'System Stats',
      callback: ([args]) async => _toggleMetric('cpu'),
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.toggleRam',
      title: 'Lumide Stats: Toggle RAM Metric',
      category: 'System Stats',
      callback: ([args]) async => _toggleMetric('ram'),
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.toggleDisk',
      title: 'Lumide Stats: Toggle Disk Metric',
      category: 'System Stats',
      callback: ([args]) async => _toggleMetric('disk'),
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.toggleNetwork',
      title: 'Lumide Stats: Toggle Network Metric',
      category: 'System Stats',
      callback: ([args]) async => _toggleMetric('network'),
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.toggleBattery',
      title: 'Lumide Stats: Toggle Battery Metric',
      category: 'System Stats',
      callback: ([args]) async => _toggleMetric('battery'),
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.toggleSensors',
      title: 'Lumide Stats: Toggle Thermal Sensor Metric',
      category: 'System Stats',
      callback: ([args]) async => _toggleMetric('thermal'),
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.refresh',
      title: 'Lumide Stats: Refresh Metrics Now',
      category: 'System Stats',
      callback: ([args]) async => refreshNow(),
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.showCpuMenu',
      title: 'Lumide Stats: Open CPU Menu',
      category: 'System Stats',
      callback: ([args]) async {
        final pos = _parsePosition(args);
        await showQuickMenu(pos, 'cpu');
      },
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.showRamMenu',
      title: 'Lumide Stats: Open RAM Menu',
      category: 'System Stats',
      callback: ([args]) async {
        final pos = _parsePosition(args);
        await showQuickMenu(pos, 'ram');
      },
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.showDiskMenu',
      title: 'Lumide Stats: Open Disk Menu',
      category: 'System Stats',
      callback: ([args]) async {
        final pos = _parsePosition(args);
        await showQuickMenu(pos, 'disk');
      },
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.showNetworkMenu',
      title: 'Lumide Stats: Open Network Menu',
      category: 'System Stats',
      callback: ([args]) async {
        final pos = _parsePosition(args);
        await showQuickMenu(pos, 'network');
      },
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.showBatteryMenu',
      title: 'Lumide Stats: Open Battery Menu',
      category: 'System Stats',
      callback: ([args]) async {
        final pos = _parsePosition(args);
        await showQuickMenu(pos, 'battery');
      },
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.showThermalMenu',
      title: 'Lumide Stats: Open Thermal Menu',
      category: 'System Stats',
      callback: ([args]) async {
        final pos = _parsePosition(args);
        await showQuickMenu(pos, 'thermal');
      },
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.showUptimeMenu',
      title: 'Lumide Stats: Open Uptime Menu',
      category: 'System Stats',
      callback: ([args]) async {
        final pos = _parsePosition(args);
        await showQuickMenu(pos, 'uptime');
      },
    );

    await context.commands.registerCommand(
      id: 'lumide-stats.toggleTopBarIcon',
      title: 'Lumide Stats: Toggle Top Bar Main Icon',
      category: 'System Stats',
      callback: ([args]) async {
        config.showTopBarIcon = !config.showTopBarIcon;
        try {
          if (config.showTopBarIcon) {
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
        } catch (_) {}
      },
    );
  }

  /// Show QuickPick menu (per-item dedicated menu when clicking status item, or global menu)
  Future<void> showQuickMenu([
    Map<String, int>? position,
    String? clickedMetric,
  ]) async {
    if (clickedMetric != null && clickedMetric.isNotEmpty) {
      await _showPerMetricMenu(clickedMetric, position);
      return;
    }

    await _showGlobalMenu(position);
  }

  /// Show dedicated per-metric QuickPick configuration menu
  Future<void> _showPerMetricMenu(
    String metric,
    Map<String, int>? position,
  ) async {
    final metricNames = {
      'cpu': 'CPU',
      'ram': 'RAM',
      'disk': 'Disk',
      'network': 'Network',
      'battery': 'Battery',
      'thermal': 'Thermal',
      'uptime': 'Uptime',
    };
    final name = metricNames[metric] ?? metric.toUpperCase();
    final isCompact = config.isCompact(metric);
    final isC = config.temperatureUnit == 'celsius';

    final items = <QuickPickItem>[];

    // Specialized controls per metric
    if (metric == 'thermal') {
      items.addAll([
        QuickPickItem(
          label: 'Temp Unit',
          description: isC ? 'Celsius (°C)' : 'Fahrenheit (°F)',
          tooltip: 'Switch temperature unit between °C and °F',
          payload: 'temp',
          icon: 'thermometer',
        ),
      ]);
    }

    // Common per-metric display style and visibility controls
    items.addAll([
      QuickPickItem(
        label: 'Display Mode',
        description: isCompact ? 'Compact Icon' : 'Standard Text',
        tooltip: isCompact
            ? 'Switch $name to Standard Text mode'
            : 'Switch $name to Compact Icon mode',
        payload: 'toggle_style_$metric',
        icon: isCompact ? 'type' : 'cpu',
      ),
      QuickPickItem(
        label: 'Hide $name',
        tooltip: 'Remove $name metric from status bar',
        payload: 'hide_$metric',
        icon: 'eye-off',
      ),
    ]);

    items.add(const QuickPickItem(label: 'Global Options', isSeparator: true));
    items.addAll([
      const QuickPickItem(
        label: 'System Dashboard',
        tooltip: 'Open full system telemetry dashboard pane',
        payload: 'dashboard',
        icon: 'gauge',
      ),
      const QuickPickItem(
        label: 'Global Settings...',
        tooltip: 'Open complete Lumide Stats configuration menu',
        payload: 'global_menu',
        icon: 'settings',
      ),
    ]);

    final selected = await context.window.showQuickPick(
      items,
      placeholder: '$name Settings',
      position: position,
    );

    if (selected == null) return;

    final key = _extractSelectedKey(selected, items);
    if (key == 'global_menu') {
      await _showGlobalMenu(position);
      return;
    }

    if (key.startsWith('hide_')) {
      final targetMetric = key.replaceFirst('hide_', '');
      config.enabledMetrics.remove(targetMetric);
      await refreshNow();
      return;
    }

    if (key.startsWith('toggle_style_')) {
      final targetKey = key.replaceFirst('toggle_style_', '');
      config.toggleMetricStyle(targetKey);
      await refreshNow();
      return;
    }

    switch (key) {
      case 'dashboard':
        await showDashboard();
        break;
      case 'temp':
        config.temperatureUnit = config.temperatureUnit == 'celsius'
            ? 'fahrenheit'
            : 'celsius';
        await refreshNow();
        break;
    }
  }

  /// Show first-level global QuickPick menu
  Future<void> _showGlobalMenu([Map<String, int>? position]) async {
    final items = <QuickPickItem>[];
    final isC = config.temperatureUnit == 'celsius';

    // General options
    items.addAll([
      const QuickPickItem(
        label: 'Dashboard',
        tooltip: 'Open system telemetry webview panel',
        payload: 'dashboard',
        icon: 'gauge',
      ),
      QuickPickItem(
        label: 'Refresh Rate',
        description: '${config.updateIntervalSeconds}s',
        tooltip: 'Set polling interval',
        payload: 'speed',
        icon: 'timer',
      ),
      QuickPickItem(
        label: 'Temp Unit',
        description: isC ? 'Celsius (°C)' : 'Fahrenheit (°F)',
        tooltip: 'Switch between °C and °F',
        payload: 'temp',
        icon: 'thermometer',
      ),
      const QuickPickItem(
        label: 'Display Styles',
        description: 'Per-Item Mode',
        tooltip: 'Configure compact vs standard style for each metric',
        payload: 'display_styles',
        icon: 'cpu',
      ),
      QuickPickItem(
        label: 'Top Bar Main Icon',
        description: config.showTopBarIcon ? 'Visible' : 'Hidden',
        tooltip: config.showTopBarIcon
            ? 'Hide main icon from top toolbar'
            : 'Show main icon in top toolbar',
        payload: 'toggle_topbar_icon',
        icon: config.showTopBarIcon ? 'eye' : 'eye-off',
      ),
    ]);

    // Section Divider for Metrics Visibility
    items.add(
      const QuickPickItem(label: 'Metrics Visibility', isSeparator: true),
    );

    // Inline Metric Toggles
    final metrics = [
      {'key': 'cpu', 'label': 'CPU'},
      {'key': 'ram', 'label': 'RAM'},
      {'key': 'disk', 'label': 'Disk'},
      {'key': 'network', 'label': 'Network'},
      {'key': 'battery', 'label': 'Battery'},
      {'key': 'thermal', 'label': 'Thermal'},
      {'key': 'uptime', 'label': 'Uptime'},
    ];

    for (final m in metrics) {
      final key = m['key']!;
      final label = m['label']!;
      final isEnabled = config.enabledMetrics.contains(key);
      items.add(
        QuickPickItem(
          label: label,
          description: isEnabled ? 'Visible' : 'Hidden',
          tooltip: isEnabled ? 'Click to hide $label' : 'Click to show $label',
          icon: isEnabled ? 'eye' : 'eye-off',
          payload: 'toggle_$key',
        ),
      );
    }

    final selected = await context.window.showQuickPick(
      items,
      placeholder: 'System Monitor',
      position: position,
    );

    if (selected == null) return;

    final key = _extractSelectedKey(selected, items);

    if (key.startsWith('toggle_') && key != 'toggle_topbar_icon') {
      final targetMetric = key.replaceFirst('toggle_', '');
      if (config.enabledMetrics.contains(targetMetric)) {
        config.enabledMetrics.remove(targetMetric);
      } else {
        config.enabledMetrics.add(targetMetric);
      }
      await refreshNow();
      return;
    }

    switch (key) {
      case 'dashboard':
        await showDashboard();
        break;
      case 'speed':
        await _showSetIntervalMenu(position);
        break;
      case 'temp':
        config.temperatureUnit = config.temperatureUnit == 'celsius'
            ? 'fahrenheit'
            : 'celsius';
        await refreshNow();
        break;
      case 'display_styles':
        await _showDisplayStylesMenu(position);
        break;
      case 'toggle_topbar_icon':
        config.showTopBarIcon = !config.showTopBarIcon;
        try {
          if (config.showTopBarIcon) {
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
        } catch (_) {}
        break;
    }
  }

  /// Sub-menu to configure per-item compact vs standard display styles
  Future<void> _showDisplayStylesMenu([Map<String, int>? position]) async {
    final metrics = [
      {'key': 'cpu', 'label': 'CPU', 'icon': 'cpu'},
      {'key': 'ram', 'label': 'RAM', 'icon': 'memory-stick'},
      {'key': 'disk', 'label': 'Disk', 'icon': 'hard-drive'},
      {'key': 'network', 'label': 'Network', 'icon': 'activity'},
      {'key': 'battery', 'label': 'Battery', 'icon': 'battery'},
      {'key': 'thermal', 'label': 'Thermal', 'icon': 'thermometer'},
      {'key': 'uptime', 'label': 'Uptime', 'icon': 'timer'},
    ];

    final items = metrics.map((m) {
      final key = m['key']!;
      final label = m['label']!;
      final icon = m['icon']!;
      final isCompact = config.isCompact(key);
      return QuickPickItem(
        label: label,
        description: isCompact ? 'Compact' : 'Standard',
        tooltip: isCompact
            ? 'Switch $label to Standard Text'
            : 'Switch $label to Compact Icon',
        icon: icon,
        payload: 'toggle_style_$key',
      );
    }).toList();

    final selected = await context.window.showQuickPick(
      items,
      placeholder: 'Display Styles',
      position: position,
    );

    if (selected == null) return;

    final key = _extractSelectedKey(selected, items);
    if (key.startsWith('toggle_style_')) {
      final targetKey = key.replaceFirst('toggle_style_', '');
      config.toggleMetricStyle(targetKey);
      await refreshNow();
    }
  }

  /// Show detailed System Dashboard leveraging Lumide Webview Pane
  Future<void> showDashboard() async {
    _dashboardPanel = null;

    final snap = _latestSnapshot ?? await collector.collect();
    final html = _generateDashboardHtml(snap);

    try {
      _dashboardPanel = await context.window.createWebviewPanel(
        'lumideStatsDashboard',
        'System Dashboard',
        options: {'html': html, 'enableScripts': true},
      );

      _dashboardPanel!.onDidReceiveMessage((msg) async {
        Map<String, dynamic> payload = {};
        if (msg is Map) {
          payload = Map<String, dynamic>.from(msg);
        } else if (msg is String) {
          try {
            final decoded = jsonDecode(msg);
            if (decoded is Map) {
              payload = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        }

        final action = payload['action'] ?? payload['command'];
        if (action == 'ready' || action == 'refresh') {
          await refreshNow();
        } else if (action == 'copyReport') {
          await copyDiagnostics();
        } else if (action == 'toggleTempUnit') {
          config.temperatureUnit = config.temperatureUnit == 'celsius'
              ? 'fahrenheit'
              : 'celsius';
          await refreshNow();
        }
      });
    } catch (_) {
      await _showFallbackDashboard(snap);
    }
  }

  /// Fallback dialog if Webview panel creation fails
  Future<void> _showFallbackDashboard(SystemStatsSnapshot snap) async {
    final isFahr = config.temperatureUnit == 'fahrenheit';
    final tempStr = isFahr
        ? '${snap.thermal.temperatureFahrenheit.toStringAsFixed(1)}°F'
        : '${snap.thermal.temperatureCelsius.toStringAsFixed(1)}°C';

    final batStr = snap.battery.isPresent
        ? '${snap.battery.levelPercent}% (${snap.battery.isCharging ? "Charging" : "Discharging"})'
        : 'Not Present';

    final message =
        '''
SYSTEM STATS DASHBOARD
---------------------------------
CPU Usage: ${snap.cpu.usagePercent}% (${snap.cpu.coreCount} Cores)
Load Averages: ${snap.cpu.load1m} (1m), ${snap.cpu.load5m} (5m), ${snap.cpu.load15m} (15m)

Memory (RAM): ${snap.ram.usagePercent}%
Used: ${snap.ram.usedGb.toStringAsFixed(2)} GB / ${snap.ram.totalGb.toStringAsFixed(2)} GB
Free: ${snap.ram.freeGb.toStringAsFixed(2)} GB | Swap: ${snap.ram.swapUsedMb.toStringAsFixed(0)} MB

Disk Space: ${snap.disk.usagePercent}% used
Free Space: ${snap.disk.freeGb.toStringAsFixed(1)} GB / ${snap.disk.totalGb.toStringAsFixed(1)} GB Total

Network Speed:
Download: ${snap.network.formattedDownload} | Upload: ${snap.network.formattedUpload}

Battery: $batStr
Thermal Sensor: Average CPU $tempStr (${snap.thermal.status})

IDE Session Uptime: ${snap.session.formattedUptime}
Plugin RSS Memory: ${snap.session.rssMb.toStringAsFixed(1)} MB
''';

    await context.window.showMessage(message, title: 'Lumide System Dashboard');
  }

  /// Generate Stats-inspired clean HTML/CSS webview content without bloat/buzzwords
  String _generateDashboardHtml(SystemStatsSnapshot snap) {
    final isFahr = config.temperatureUnit == 'fahrenheit';
    final tempVal = isFahr
        ? snap.thermal.temperatureFahrenheit.toStringAsFixed(1)
        : snap.thermal.temperatureCelsius.toStringAsFixed(1);
    final tempUnit = isFahr ? '°F' : '°C';

    final ramUsedGb = snap.ram.usedGb.toStringAsFixed(1);
    final ramTotalGb = snap.ram.totalGb.toStringAsFixed(1);
    final diskFreeGb = snap.disk.freeGb.toStringAsFixed(1);
    final diskTotalGb = snap.disk.totalGb.toStringAsFixed(1);

    final cpuProcHtml = snap.cpu.topProcesses
        .map(
          (p) =>
              '<div style="display: flex; justify-content: space-between; font-size: 10px; margin-top: 2px;"><span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 140px; color: var(--text);">${p.name}</span><span class="mono-sub" style="color: var(--accent); font-weight: 600;">${p.cpuPercent.toStringAsFixed(1)}%</span></div>',
        )
        .join('');

    final ramProcHtml = snap.ram.topProcesses
        .map(
          (p) =>
              '<div style="display: flex; justify-content: space-between; font-size: 10px; margin-top: 2px;"><span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 140px; color: var(--text);">${p.name}</span><span class="mono-sub" style="color: var(--accent); font-weight: 600;">${p.rssMb >= 1024 ? "${(p.rssMb / 1024).toStringAsFixed(1)} GB" : "${p.rssMb.toStringAsFixed(0)} MB"}</span></div>',
        )
        .join('');

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>System Monitor</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Nunito:wght@400;500;600;700;800&display=swap');

    :root {
      --primary: #D65D2E;
      --secondary: #6CA1B8;
      --app-bg: #0B0B0B;
      --panel-bg: #14171A;
      --panel-muted: #25282C;
      --text: #E4E1DB;
      --text-muted: color-mix(in srgb, #E4E1DB 55%, transparent);
      --divider: rgba(255, 255, 255, 0.08);
      --accent: var(--primary);
      --accent-hover: color-mix(in srgb, var(--primary) 15%, transparent);
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      font-family: 'Nunito', -apple-system, BlinkMacSystemFont, sans-serif;
      background: var(--app-bg);
      color: var(--text);
      padding: 10px 12px;
      line-height: 1.3;
      font-size: 12px;
      -webkit-font-smoothing: antialiased;
    }

    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 10px;
      padding-bottom: 6px;
      border-bottom: 1px solid var(--divider);
    }

    .title {
      font-size: 13px;
      font-weight: 700;
      letter-spacing: -0.3px;
    }

    .badge {
      font-size: 10px;
      font-family: 'JetBrains Mono', monospace;
      background: color-mix(in srgb, var(--accent) 15%, transparent);
      color: var(--accent);
      padding: 1px 6px;
      border-radius: 4px;
      font-weight: 600;
    }

    .actions {
      display: flex;
      gap: 6px;
    }

    button {
      background: var(--panel-bg);
      color: var(--text);
      border: 1px solid var(--divider);
      padding: 3px 8px;
      border-radius: 6px;
      font-size: 11px;
      font-family: 'Nunito', sans-serif;
      font-weight: 600;
      cursor: pointer;
      transition: background 75ms ease, border-color 75ms ease;
    }

    button:hover {
      background: var(--accent-hover);
      border-color: var(--accent);
    }

    /* Clean Natural Bento Grid Layout */
    .bento-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 8px;
    }

    .card {
      background: var(--panel-bg);
      border: 1px solid var(--divider);
      border-radius: 8px;
      padding: 10px 12px;
      transition: border-color 75ms ease;
    }

    .card:hover {
      border-color: color-mix(in srgb, var(--accent) 35%, transparent);
    }

    .card-large {
      grid-column: span 2;
    }

    .card-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 4px;
    }

    .card-title {
      font-size: 10px;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.5px;
      font-weight: 700;
    }

    .card-value {
      font-family: 'JetBrains Mono', monospace;
      font-size: 20px;
      font-weight: 700;
      letter-spacing: -0.5px;
      color: var(--text);
    }

    .progress-bar-bg {
      background: var(--panel-muted);
      height: 4px;
      border-radius: 2px;
      overflow: hidden;
      margin-top: 4px;
    }

    .progress-bar-fill {
      height: 100%;
      background: var(--accent);
      border-radius: 2px;
      transition: width 0.3s ease;
    }

    .sparkline-canvas {
      display: block;
      width: 100%;
      height: 36px;
      margin-top: 6px;
    }

    .sub-text {
      font-size: 10px;
      color: var(--text-muted);
      margin-top: 3px;
      font-family: 'Nunito', sans-serif;
    }

    .mono-sub {
      font-family: 'JetBrains Mono', monospace;
    }

    .card-body-split {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
      margin-top: 4px;
    }

    @media (max-width: 640px) {
      .bento-grid {
        grid-template-columns: 1fr;
      }
      .card-large {
        grid-column: span 1;
      }
      .card-body-split {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <div class="header">
    <div class="title">System Monitor</div>
    <div class="actions">
      <button onclick="sendAction('toggleTempUnit')">°C / °F</button>
    </div>
  </div>

  <div class="bento-grid">
    <!-- CPU Bento Card (Large) -->
    <div class="card card-large">
      <div class="card-header">
        <span class="card-title">CPU Load</span>
        <span id="cpu-cores" class="sub-text mono-sub">${snap.cpu.coreCount} Cores</span>
      </div>
      <div class="card-body-split">
        <div>
          <div id="cpu-val" class="card-value">${snap.cpu.usagePercent}%</div>
          <div class="progress-bar-bg">
            <div id="cpu-bar" class="progress-bar-fill" style="width: ${snap.cpu.usagePercent}%;"></div>
          </div>
          <canvas id="cpu-sparkline" class="sparkline-canvas"></canvas>
          <div id="cpu-loads" class="sub-text mono-sub">1m: ${snap.cpu.load1m} | 5m: ${snap.cpu.load5m} | 15m: ${snap.cpu.load15m}</div>
        </div>
        <div id="cpu-procs" style="border-left: 1px solid var(--divider); padding-left: 10px;">
          ${cpuProcHtml.isNotEmpty ? '<div style="font-size: 10px; font-weight: 700; color: var(--text-muted); margin-bottom: 2px; text-transform: uppercase;">Top Processes</div>$cpuProcHtml' : ''}
        </div>
      </div>
    </div>

    <!-- RAM Bento Card (Large) -->
    <div class="card card-large">
      <div class="card-header">
        <span class="card-title">Memory (RAM)</span>
        <span id="ram-used" class="sub-text mono-sub">$ramUsedGb / $ramTotalGb GB</span>
      </div>
      <div class="card-body-split">
        <div>
          <div id="ram-val" class="card-value">${snap.ram.usagePercent}%</div>
          <div class="progress-bar-bg">
            <div id="ram-bar" class="progress-bar-fill" style="width: ${snap.ram.usagePercent}%;"></div>
          </div>
          <canvas id="ram-sparkline" class="sparkline-canvas"></canvas>
          <div id="ram-swap" class="sub-text mono-sub">Free: ${snap.ram.freeGb.toStringAsFixed(1)}G | Swap: ${snap.ram.swapUsedMb.toStringAsFixed(0)}M</div>
        </div>
        <div id="ram-procs" style="border-left: 1px solid var(--divider); padding-left: 10px;">
          ${ramProcHtml.isNotEmpty ? '<div style="font-size: 10px; font-weight: 700; color: var(--text-muted); margin-bottom: 2px; text-transform: uppercase;">Top Processes</div>$ramProcHtml' : ''}
        </div>
      </div>
    </div>

    <!-- Thermal Bento Card -->
    <div class="card">
      <div class="card-header">
        <span class="card-title">Thermal</span>
        <span id="thermal-status" class="badge">${snap.thermal.status}</span>
      </div>
      <div id="thermal-val" class="card-value">$tempVal$tempUnit</div>
      <div id="fan-rpm" class="sub-text mono-sub">Speed: ${snap.thermal.fanRpm > 0 ? "${snap.thermal.fanRpm} RPM" : "Auto"}</div>
    </div>

    <!-- Disk Storage Bento Card -->
    <div class="card">
      <div class="card-header">
        <span class="card-title">Disk Storage</span>
        <span id="disk-free" class="sub-text mono-sub">$diskFreeGb GB Free</span>
      </div>
      <div id="disk-val" class="card-value">${snap.disk.usagePercent}%</div>
      <div class="progress-bar-bg">
        <div id="disk-bar" class="progress-bar-fill" style="width: ${snap.disk.usagePercent}%;"></div>
      </div>
      <div id="disk-total" class="sub-text mono-sub" style="margin-top: 4px;">Capacity: $diskTotalGb GB</div>
    </div>

    <!-- Network Traffic Bento Card -->
    <div class="card">
      <div class="card-header">
        <span class="card-title">Network Traffic</span>
      </div>
      <div id="net-down" class="card-value mono-sub" style="font-size: 15px; color: var(--secondary);">↓ ${snap.network.formattedDownload}</div>
      <div id="net-up" class="card-value mono-sub" style="font-size: 15px; color: var(--primary); margin-top: 2px;">↑ ${snap.network.formattedUpload}</div>
    </div>

    <!-- Power & Session Bento Card -->
    <div class="card">
      <div class="card-header">
        <span class="card-title">Power & Session</span>
      </div>
      <div id="battery-val" class="card-value mono-sub" style="font-size: 15px;">Power: ${snap.battery.isPresent ? "${snap.battery.levelPercent}%" : "AC Power"}</div>
      <div id="uptime-val" class="sub-text mono-sub" style="margin-top: 4px;">Uptime: ${snap.session.formattedUptime}</div>
    </div>
  </div>

  <script>
    const MAX_SAMPLES = 30;
    const cpuHistory = [${snap.cpu.usagePercent}];
    const ramHistory = [${snap.ram.usagePercent}];

    const lumide = {
      postMessage: (message) => {
        const payload = typeof message === 'string' ? message : JSON.stringify(message);
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('postMessage', payload);
        } else if (window.lumide && window.lumide.postMessage) {
          window.lumide.postMessage(payload);
        } else if (window.parent) {
          window.parent.postMessage(payload, '*');
        }
      }
    };

    function sendAction(action, extra = {}) {
      lumide.postMessage(Object.assign({ command: action, action: action }, extra));
    }

    sendAction('ready');

    function drawSparkline(canvasId, historyData, color) {
      const canvas = document.getElementById(canvasId);
      if (!canvas) return;
      const ctx = canvas.getContext('2d');
      const w = canvas.width = canvas.clientWidth || 200;
      const h = canvas.height = canvas.clientHeight || 36;
      if (w === 0 || h === 0) return;
      ctx.clearRect(0, 0, w, h);

      if (!historyData || historyData.length === 0) return;

      const numBars = MAX_SAMPLES;
      const barGap = 2;
      const totalGaps = (numBars - 1) * barGap;
      const barWidth = Math.max(2, (w - totalGaps) / numBars);

      // Calculate start index so new history bars enter smoothly from the right
      const startIdx = numBars - historyData.length;

      for (let i = 0; i < historyData.length; i++) {
        const val = historyData[i];
        const barHeight = Math.max(2, (val / 100) * h);
        const x = (startIdx + i) * (barWidth + barGap);
        const y = h - barHeight;

        // Latest reading gets full color brightness, past history is slightly translucent
        const isLatest = i === historyData.length - 1;
        ctx.fillStyle = isLatest ? color : color + 'CC';
        ctx.fillRect(x, y, barWidth, barHeight);
      }
    }

    function renderTopProcesses(elementId, procs, isCpu) {
      const el = document.getElementById(elementId);
      if (!el || !procs || !procs.length) return;
      let html = '<div style="font-size: 10px; font-weight: 700; color: var(--text-muted); margin-bottom: 2px; text-transform: uppercase;">Top Processes</div>';
      procs.forEach(p => {
        const valStr = isCpu ? (p.cpuPercent.toFixed(1) + '%') : (p.rssMb >= 1024 ? (p.rssMb / 1024).toFixed(1) + ' GB' : p.rssMb.toFixed(0) + ' MB');
        html += '<div style="display: flex; justify-content: space-between; font-size: 10px; margin-top: 2px;">' +
                  '<span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 140px; color: var(--text);">' + p.name + '</span>' +
                  '<span class="mono-sub" style="color: var(--accent); font-weight: 600;">' + valStr + '</span>' +
                '</div>';
      });
      el.innerHTML = html;
    }

    function handleUpdate(data) {
      if (!data) return;
      if (data.cpu) {
        document.getElementById('cpu-val').innerText = data.cpu.usagePercent + '%';
        document.getElementById('cpu-bar').style.width = data.cpu.usagePercent + '%';
        cpuHistory.push(data.cpu.usagePercent);
        while (cpuHistory.length > MAX_SAMPLES) cpuHistory.shift();
        drawSparkline('cpu-sparkline', cpuHistory, '#D65D2E');
        if (data.cpu.topProcesses) {
          renderTopProcesses('cpu-procs', data.cpu.topProcesses, true);
        }
      }
      if (data.ram) {
        document.getElementById('ram-val').innerText = data.ram.usagePercent + '%';
        document.getElementById('ram-bar').style.width = data.ram.usagePercent + '%';
        ramHistory.push(data.ram.usagePercent);
        while (ramHistory.length > MAX_SAMPLES) ramHistory.shift();
        drawSparkline('ram-sparkline', ramHistory, '#6CA1B8');
        if (data.ram.topProcesses) {
          renderTopProcesses('ram-procs', data.ram.topProcesses, false);
        }
      }
      if (data.disk) {
        document.getElementById('disk-val').innerText = data.disk.usagePercent + '%';
        document.getElementById('disk-bar').style.width = data.disk.usagePercent + '%';
      }
      if (data.thermal) {
        document.getElementById('fan-rpm').innerText = 'Speed: ' + (data.thermal.fanRpm > 0 ? data.thermal.fanRpm + ' RPM' : 'Auto');
      }
      if (data.session) {
        document.getElementById('uptime-val').innerText = 'Uptime: ' + data.session.formattedUptime;
      }
    }

    function processMessage(eventData) {
      let msg = eventData;
      if (typeof msg === 'string') {
        try { msg = JSON.parse(msg); } catch (e) {}
      }
      if (msg && msg.type === 'update' && msg.data) {
        handleUpdate(msg.data);
      } else if (msg && msg.data && msg.data.cpu) {
        handleUpdate(msg.data);
      } else if (msg && msg.cpu) {
        handleUpdate(msg);
      }
    }

    window.addEventListener('message', function(event) { processMessage(event.data); });
    document.addEventListener('message', function(event) { processMessage(event.data); });
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.addEventListener('message', function(event) { processMessage(event.data); });
    }

    setTimeout(() => {
      drawSparkline('cpu-sparkline', cpuHistory, '#D65D2E');
      drawSparkline('ram-sparkline', ramHistory, '#6CA1B8');
    }, 50);

    // Auto heartbeat poll every 2s to guarantee real-time updates
    setInterval(function() {
      sendAction('refresh');
    }, 2000);
  </script>
</body>
</html>
''';
  }

  /// Sub-menu to set refresh polling rate
  Future<void> _showSetIntervalMenu([Map<String, int>? position]) async {
    final options = [
      {'sec': 1, 'desc': '1s (Fast)'},
      {'sec': 2, 'desc': '2s (Normal)'},
      {'sec': 5, 'desc': '5s (Eco)'},
      {'sec': 10, 'desc': '10s (Battery)'},
    ];

    final items = options.map((opt) {
      final sec = opt['sec'] as int;
      final desc = opt['desc'] as String;
      final isCurrent = config.updateIntervalSeconds == sec;
      return QuickPickItem(
        label: desc,
        description: isCurrent ? 'Active' : null,
        tooltip: 'Set polling interval to $sec second${sec > 1 ? "s" : ""}',
        icon: isCurrent ? 'check' : 'timer',
        payload: sec.toString(),
      );
    }).toList();

    final selected = await context.window.showQuickPick(
      items,
      placeholder: 'Refresh Speed',
      position: position,
    );

    if (selected == null) return;

    final key = _extractSelectedKey(selected, items);
    final sec = int.tryParse(key);
    if (sec != null && sec > 0) {
      config.updateIntervalSeconds = sec;
      await refreshNow();
    }
  }

  /// Force immediate metrics refresh
  Future<void> refreshNow() async {
    final snapshot = await collector.collect();
    updateSnapshot(snapshot);
    await statusBarManager.update(_latestSnapshot!);
  }

  /// Copy system diagnostics report to Lumide output / log
  Future<void> copyDiagnostics() async {
    final snapshot = _latestSnapshot ?? await collector.collect();
    final jsonReport = snapshot.toFormattedJson();
    await context.window.showMessage(
      'System Diagnostics Report Generated:\n\n$jsonReport',
      title: 'Lumide Diagnostics Export',
    );
  }

  Future<void> _toggleMetric(String key) async {
    if (config.enabledMetrics.contains(key)) {
      config.enabledMetrics.remove(key);
    } else {
      config.enabledMetrics.add(key);
    }
    await refreshNow();
  }
}
