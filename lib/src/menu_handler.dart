import 'dart:async';
import 'dart:convert';

import 'package:lumide_api/lumide_api.dart';

import 'config.dart';
import 'dashboard.dart';
import 'models/system_stats.dart';
import 'status_bar_manager.dart';

/// Commands, quick menus, the dashboard webview and the Output report.
class MenuHandler {
  MenuHandler({
    required this.context,
    required this.config,
    required this.setSetting,
    required this.refresh,
    required this.latestSnapshot,
  });

  final LumideContext context;
  final LumideStatsConfig config;

  /// Saves a setting to Lumide and applies it.
  final Future<void> Function(String key, Object value) setSetting;

  /// Collects new metrics and updates the status bar and dashboard.
  final Future<void> Function() refresh;

  /// Returns the latest snapshot, collecting one if there is none yet.
  final Future<SystemStatsSnapshot> Function() latestSnapshot;

  LumideWebviewPanel? _dashboard;
  LumideOutputChannel? _output;

  /// Whether the dashboard webview is open.
  bool get isDashboardOpen => _dashboard != null;

  Future<void> registerCommands() async {
    Future<void> register(
      String id,
      String title,
      Future<void> Function(Map<String, int>? position) action,
    ) => context.commands.registerCommand(
      id: id,
      title: title,
      category: 'System Stats',
      callback: ([args]) => action(_parsePosition(args)),
    );

    await register(
      'lumide-stats.showQuickMenu',
      'System Stats: Open Quick Menu',
      showQuickMenu,
    );
    await register(
      'lumide-stats.showDashboard',
      'System Stats: Show Dashboard',
      (_) => showDashboard(),
    );
    await register(
      'lumide-stats.showReport',
      'System Stats: Show Report in Output',
      (_) => showReport(),
    );
    await register(
      'lumide-stats.refresh',
      'System Stats: Refresh Now',
      (_) => refresh(),
    );
    await register(
      'lumide-stats.toggleTopBarIcon',
      'System Stats: Toggle Toolbar Icon',
      (_) =>
          setSetting(LumideStatsConfig.toolbarIconKey, !config.showTopBarIcon),
    );
    for (final metric in StatusMetric.values) {
      await register(
        toggleCommand(metric),
        'System Stats: Toggle ${metric.label}',
        (_) => _toggleMetric(metric),
      );
      // Run when the status bar item is clicked.
      await register(
        metricMenuCommand(metric),
        'System Stats: ${metric.label} Options',
        (position) => showMetricMenu(metric, position),
      );
    }
  }

  /// Command id that shows or hides [metric], e.g. `lumide-stats.toggleCpu`.
  static String toggleCommand(StatusMetric metric) =>
      'lumide-stats.toggle${metric.settingSuffix}';

  static Map<String, int>? _parsePosition(Map<String, dynamic>? args) {
    final position = args?['position'];
    if (position is Map && position['x'] is num && position['y'] is num) {
      return {
        'x': (position['x'] as num).round(),
        'y': (position['y'] as num).round(),
      };
    }
    return null;
  }

  Future<String?> _pick(
    List<QuickPickItem> items,
    String placeholder,
    Map<String, int>? position,
  ) async {
    final selected = await context.window.showQuickPick(
      items,
      placeholder: placeholder,
      position: position,
    );
    final payload = selected?.payload;
    if (payload is Map) return payload['payload']?.toString();
    return payload?.toString();
  }

  Future<void> _toggleMetric(StatusMetric metric) =>
      setSetting(metric.enableKey, !config.isEnabled(metric));

  Future<void> _toggleStyle(StatusMetric metric) =>
      setSetting(metric.compactKey, !config.isCompact(metric));

  Future<void> _toggleUnit() =>
      setSetting(LumideStatsConfig.fahrenheitKey, !config.useFahrenheit);

  String get _unitLabel =>
      config.useFahrenheit ? 'Fahrenheit (°F)' : 'Celsius (°C)';

  /// The menu shown when a status bar item is clicked.
  Future<void> showMetricMenu(
    StatusMetric metric,
    Map<String, int>? position,
  ) async {
    final compact = config.isCompact(metric);
    final items = <QuickPickItem>[
      QuickPickItem(
        label: 'Display Style',
        description: compact ? 'Compact' : 'With label',
        tooltip: compact
            ? 'Add a text label, e.g. "${metric.label} 42%"'
            : 'Show only the icon and value',
        icon: 'type',
        payload: 'style',
      ),
      if (metric == StatusMetric.thermal)
        QuickPickItem(
          label: 'Temperature Unit',
          description: _unitLabel,
          icon: 'thermometer',
          payload: 'unit',
        ),
      QuickPickItem(
        label: 'Hide ${metric.label}',
        tooltip: 'Remove this item from the status bar',
        icon: 'eye-off',
        payload: 'hide',
      ),
      const QuickPickItem(label: 'System Stats', isSeparator: true),
      const QuickPickItem(
        label: 'Show Dashboard',
        icon: 'gauge',
        payload: 'dashboard',
      ),
      const QuickPickItem(
        label: 'More Options...',
        icon: 'settings',
        payload: 'more',
      ),
    ];

    switch (await _pick(items, metric.label, position)) {
      case 'style':
        await _toggleStyle(metric);
      case 'unit':
        await _toggleUnit();
      case 'hide':
        await setSetting(metric.enableKey, false);
      case 'dashboard':
        await showDashboard();
      case 'more':
        await showQuickMenu(position);
    }
  }

  /// The main menu (toolbar icon and Command Palette).
  Future<void> showQuickMenu([Map<String, int>? position]) async {
    final items = <QuickPickItem>[
      const QuickPickItem(
        label: 'Show Dashboard',
        tooltip: 'Live charts and top processes',
        icon: 'gauge',
        payload: 'dashboard',
      ),
      const QuickPickItem(
        label: 'Show Report in Output',
        tooltip: 'Write a text summary to the Output pane',
        icon: 'file-text',
        payload: 'report',
      ),
      const QuickPickItem(
        label: 'Refresh Now',
        icon: 'refresh-cw',
        payload: 'refresh',
      ),
      QuickPickItem(
        label: 'Refresh Interval',
        description: '${config.updateIntervalSeconds}s',
        icon: 'timer',
        payload: 'interval',
      ),
      QuickPickItem(
        label: 'Temperature Unit',
        description: _unitLabel,
        icon: 'thermometer',
        payload: 'unit',
      ),
      QuickPickItem(
        label: 'Battery Saver',
        description: config.batterySaverMode ? 'On' : 'Off',
        tooltip:
            'Refresh every ${LumideStatsConfig.batterySaverInterval}s or '
            'slower while on battery power',
        icon: 'battery',
        payload: 'saver',
      ),
      QuickPickItem(
        label: 'Toolbar Icon',
        description: config.showTopBarIcon ? 'Shown' : 'Hidden',
        icon: 'gauge',
        payload: 'toolbar',
      ),
      const QuickPickItem(
        label: 'Display Styles...',
        tooltip: 'Compact or labeled text for each item',
        icon: 'type',
        payload: 'styles',
      ),
      const QuickPickItem(label: 'Status Bar Items', isSeparator: true),
      for (final metric in StatusMetric.values)
        QuickPickItem(
          label: metric.label,
          description: config.isEnabled(metric) ? 'Shown' : 'Hidden',
          tooltip: config.isEnabled(metric)
              ? 'Hide ${metric.label}'
              : 'Show ${metric.label}',
          icon: config.isEnabled(metric) ? 'eye' : 'eye-off',
          payload: 'toggle:${metric.name}',
        ),
    ];

    final key = await _pick(items, 'System Stats', position);
    if (key == null) return;
    if (key.startsWith('toggle:')) {
      final metric = StatusMetric.values.asNameMap()[key.substring(7)];
      if (metric != null) await _toggleMetric(metric);
      return;
    }
    switch (key) {
      case 'dashboard':
        await showDashboard();
      case 'report':
        await showReport();
      case 'refresh':
        await refresh();
      case 'interval':
        await _showIntervalMenu(position);
      case 'unit':
        await _toggleUnit();
      case 'saver':
        await setSetting(
          LumideStatsConfig.batterySaverKey,
          !config.batterySaverMode,
        );
      case 'toolbar':
        await setSetting(
          LumideStatsConfig.toolbarIconKey,
          !config.showTopBarIcon,
        );
      case 'styles':
        await _showStylesMenu(position);
    }
  }

  Future<void> _showIntervalMenu(Map<String, int>? position) async {
    const options = [1, 2, 5, 10, 30];
    final items = [
      for (final seconds in options)
        QuickPickItem(
          label: '$seconds second${seconds == 1 ? '' : 's'}',
          description: config.updateIntervalSeconds == seconds
              ? 'Current'
              : null,
          icon: config.updateIntervalSeconds == seconds ? 'check' : 'timer',
          payload: '$seconds',
        ),
    ];
    final seconds = int.tryParse(
      await _pick(items, 'Refresh Interval', position) ?? '',
    );
    if (seconds != null) {
      await setSetting(LumideStatsConfig.intervalKey, seconds);
    }
  }

  Future<void> _showStylesMenu(Map<String, int>? position) async {
    final items = [
      for (final metric in StatusMetric.values)
        QuickPickItem(
          label: metric.label,
          description: config.isCompact(metric) ? 'Compact' : 'With label',
          icon: metric.icon,
          payload: metric.name,
        ),
    ];
    final name = await _pick(items, 'Display Styles', position);
    final metric = StatusMetric.values.asNameMap()[name];
    if (metric != null) await _toggleStyle(metric);
  }

  /// Opens the dashboard webview. Falls back to the Output report where
  /// Lumide has no webview support (Linux).
  Future<void> showDashboard() async {
    final snapshot = await latestSnapshot();
    // Lumide has no API to focus an open panel, so replace it.
    await _closeDashboard();
    final LumideWebviewPanel panel;
    try {
      panel = await context.window.createWebviewPanel(
        'lumideStatsDashboard',
        'System Stats',
        options: {
          'html': buildDashboardHtml(snapshot, config.useFahrenheit),
          'enableScripts': true,
        },
      );
    } catch (_) {
      await showReport();
      return;
    }
    _dashboard = panel;
    panel.onDidReceiveMessage((message) {
      if (identical(panel, _dashboard)) unawaited(_onDashboardMessage(message));
    });
    // Collect top processes for the dashboard right away.
    unawaited(refresh());
  }

  Future<void> _onDashboardMessage(Object message) async {
    Object? decoded = message;
    if (message is String) {
      try {
        decoded = jsonDecode(message);
      } catch (_) {
        decoded = message;
      }
    }
    if (decoded is! Map) {
      if (message.toString().contains('webviewDisposed')) _forgetDashboard();
      return;
    }
    if (decoded['lumideEvent'] == 'webviewDisposed') {
      _forgetDashboard();
      return;
    }
    switch (decoded['action']) {
      case 'toggleTempUnit':
        await _toggleUnit();
      case 'refresh':
        await refresh();
    }
  }

  void _forgetDashboard() {
    _dashboard = null;
  }

  Future<void> _closeDashboard() async {
    final panel = _dashboard;
    if (panel == null) return;
    _forgetDashboard();
    try {
      await panel.dispose();
    } catch (_) {}
  }

  /// Sends [snapshot] to the dashboard, if it's open.
  Future<void> pushSnapshot(SystemStatsSnapshot snapshot) async {
    final panel = _dashboard;
    if (panel == null) return;
    try {
      await panel.postMessage(
        dashboardUpdateMessage(snapshot, config.useFahrenheit),
      );
    } catch (_) {
      // The panel was closed.
      _forgetDashboard();
    }
  }

  /// Writes a text report to the "System Stats" Output channel.
  Future<void> showReport() async {
    final snapshot = await latestSnapshot();
    final report = buildTextReport(snapshot, fahrenheit: config.useFahrenheit);
    try {
      final output = _output ??= await context.window.createOutputChannel(
        'System Stats',
      );
      await output.appendLine('$report\n');
      await output.show();
    } catch (_) {
      await context.window.showMessage(report, title: 'System Stats');
    }
  }

  Future<void> dispose() async {
    await _closeDashboard();
    try {
      await _output?.dispose();
    } catch (_) {}
    _output = null;
  }
}
