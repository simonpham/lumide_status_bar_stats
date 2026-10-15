import 'dart:convert';

import 'format.dart';
import 'models/system_stats.dart';

/// Plain-text summary of [snapshot], used for the Output channel report and
/// when webviews aren't available (Lumide doesn't support them on Linux).
String buildTextReport(
  SystemStatsSnapshot snapshot, {
  bool fahrenheit = false,
}) {
  final lines = <String>['System Stats — ${snapshot.timestamp.toLocal()}', ''];
  const unavailable = 'not available';

  final cpu = snapshot.cpu;
  lines.add(
    cpu == null
        ? 'CPU: $unavailable'
        : 'CPU: ${cpu.usagePercent.toStringAsFixed(1)}% of ${cpu.coreCount} cores'
              '${cpu.loadAverage == null ? '' : ' · load ${cpu.loadAverage}'}',
  );
  final ram = snapshot.ram;
  lines.add(
    ram == null
        ? 'Memory: $unavailable'
        : 'Memory: ${formatBytes(ram.usedBytes)} of ${formatBytes(ram.totalBytes)} '
              '(${formatPercent(ram.usagePercent)})'
              '${ram.swapUsedBytes == null ? '' : ' · swap ${formatBytes(ram.swapUsedBytes!)}'}',
  );
  final disk = snapshot.disk;
  lines.add(
    disk == null
        ? 'Disk: $unavailable'
        : 'Disk (${disk.volume}): ${formatBytes(disk.freeBytes)} free of '
              '${formatBytes(disk.totalBytes)} (${formatPercent(disk.usagePercent)} used)',
  );
  final network = snapshot.network;
  lines.add(
    network == null
        ? 'Network: $unavailable'
        : 'Network${network.interface == null ? '' : ' (${network.interface})'}: '
              '↓${network.formattedDownload} ↑${network.formattedUpload}',
  );
  final battery = snapshot.battery;
  lines.add(
    battery == null
        ? 'Battery: none'
        : 'Battery: ${battery.levelPercent}% · ${battery.stateLabel}'
              '${battery.timeRemainingMinutes == null ? '' : ' · ${formatMinutes(battery.timeRemainingMinutes!)}'}',
  );
  final thermal = snapshot.thermal;
  lines.add(
    thermal == null
        ? 'CPU temperature: $unavailable'
        : 'CPU temperature: ${formatTemperature(thermal.temperatureCelsius, fahrenheit: fahrenheit)} '
              '(${thermal.source})${thermal.fanRpm == null ? '' : ' · fan ${thermal.fanRpm} RPM'}',
  );
  lines.add(
    'Lumide session: ${formatDuration(snapshot.session.uptime)} · '
    'plugin memory ${formatBytes(snapshot.session.pluginRssBytes)}',
  );

  void addProcesses(String title, List<TopProcessInfo> processes, bool byCpu) {
    if (processes.isEmpty) return;
    lines
      ..add('')
      ..add(title);
    for (final p in processes) {
      final value = byCpu
          ? '${p.cpuPercent.toStringAsFixed(1)}%'
          : formatBytes(p.rssBytes);
      lines.add('  ${value.padLeft(8)}  ${p.name}');
    }
  }

  addProcesses('Top processes by CPU', cpu?.topProcesses ?? const [], true);
  addProcesses('Top processes by memory', ram?.topProcesses ?? const [], false);
  return lines.join('\n');
}

/// The message posted to the dashboard webview for each new snapshot.
String dashboardUpdateMessage(SystemStatsSnapshot snapshot, bool fahrenheit) =>
    jsonEncode({
      'type': 'update',
      'fahrenheit': fahrenheit,
      'data': snapshot.toJson(),
    });

/// HTML of the dashboard webview. All values are rendered by the script from
/// JSON with `textContent`, so process names can't inject markup.
String buildDashboardHtml(SystemStatsSnapshot snapshot, bool fahrenheit) {
  // Escape "<" so a value can't close the <script> element.
  final initial = dashboardUpdateMessage(
    snapshot,
    fahrenheit,
  ).replaceAll('<', r'\u003c');
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>System Stats</title>
<style>
  :root {
    --bg: #0f1113; --panel: #171a1d; --muted-bg: #262a2e; --text: #e4e1db;
    --muted: #9a978f; --divider: rgba(255,255,255,0.08);
    --accent: #d65d2e; --accent2: #6ca1b8; --warn: #ff9800; --crit: #f44336;
    --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font: 12px/1.35 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Ubuntu, sans-serif;
    background: var(--bg); color: var(--text); padding: 12px; }
  header { display: flex; justify-content: space-between; align-items: center;
    margin-bottom: 10px; padding-bottom: 6px; border-bottom: 1px solid var(--divider); }
  h1 { font-size: 13px; font-weight: 700; }
  button { background: var(--panel); color: var(--text); border: 1px solid var(--divider);
    padding: 3px 8px; border-radius: 6px; font: inherit; cursor: pointer; }
  button:hover { border-color: var(--accent); }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 8px; }
  .card { background: var(--panel); border: 1px solid var(--divider); border-radius: 8px; padding: 10px 12px; }
  .wide { grid-column: span 2; }
  @media (max-width: 520px) { .wide { grid-column: span 1; } }
  .title { font-size: 10px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; font-weight: 700; }
  .value { font-family: var(--mono); font-size: 20px; font-weight: 700; margin-top: 4px; }
  .sub { font-family: var(--mono); font-size: 10px; color: var(--muted); margin-top: 4px; }
  .bar { background: var(--muted-bg); height: 4px; border-radius: 2px; overflow: hidden; margin-top: 4px; }
  .fill { height: 100%; width: 0; background: var(--accent); transition: width .3s ease; }
  canvas { display: block; width: 100%; height: 36px; margin-top: 6px; }
  .split { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .procs { border-left: 1px solid var(--divider); padding-left: 10px; font-size: 10px; }
  .proc { display: flex; justify-content: space-between; gap: 8px; margin-top: 2px; }
  .proc span:first-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .proc span:last-child { font-family: var(--mono); color: var(--accent); }
  .warning { color: var(--warn); } .critical { color: var(--crit); }
</style>
</head>
<body>
<header>
  <h1>System Stats</h1>
  <button id="unit">°C / °F</button>
</header>
<div class="grid">
  <div class="card wide"><div class="split"><div>
    <div class="title">CPU</div><div id="cpu" class="value">–</div>
    <div class="bar"><div id="cpu-bar" class="fill"></div></div>
    <canvas id="cpu-chart"></canvas><div id="cpu-sub" class="sub"></div>
  </div><div id="cpu-procs" class="procs"></div></div></div>
  <div class="card wide"><div class="split"><div>
    <div class="title">Memory</div><div id="ram" class="value">–</div>
    <div class="bar"><div id="ram-bar" class="fill"></div></div>
    <canvas id="ram-chart"></canvas><div id="ram-sub" class="sub"></div>
  </div><div id="ram-procs" class="procs"></div></div></div>
  <div class="card"><div class="title">Disk</div><div id="disk" class="value">–</div>
    <div class="bar"><div id="disk-bar" class="fill"></div></div><div id="disk-sub" class="sub"></div></div>
  <div class="card"><div class="title">Network</div>
    <div id="down" class="value" style="font-size:15px;color:var(--accent2)">–</div>
    <div id="up" class="value" style="font-size:15px">–</div><div id="net-sub" class="sub"></div></div>
  <div class="card"><div class="title">CPU temperature</div><div id="temp" class="value">–</div>
    <div id="temp-sub" class="sub"></div></div>
  <div class="card"><div class="title">Power &amp; session</div><div id="battery" class="value" style="font-size:15px">–</div>
    <div id="battery-sub" class="sub"></div><div id="session" class="sub"></div></div>
</div>
<script>
  const MAX_SAMPLES = 30;
  const history = { cpu: [], ram: [] };
  const \$ = (id) => document.getElementById(id);

  function send(action) {
    const payload = JSON.stringify({ action: action });
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('postMessage', payload);
    } else if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(payload);
    }
  }
  \$('unit').addEventListener('click', () => send('toggleTempUnit'));

  function level(el, value, warn, crit) {
    el.classList.toggle('warning', value >= warn && value < crit);
    el.classList.toggle('critical', value >= crit);
  }
  function setBar(id, percent) { \$(id).style.width = Math.max(0, Math.min(100, percent)) + '%'; }
  function chart(id, data, color) {
    const canvas = \$(id);
    const w = canvas.width = canvas.clientWidth || 200;
    const h = canvas.height = canvas.clientHeight || 36;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, w, h);
    const gap = 2, bw = Math.max(2, (w - (MAX_SAMPLES - 1) * gap) / MAX_SAMPLES);
    const start = MAX_SAMPLES - data.length;
    data.forEach((v, i) => {
      const bh = Math.max(2, v / 100 * h);
      ctx.fillStyle = color;
      ctx.globalAlpha = i === data.length - 1 ? 1 : 0.6;
      ctx.fillRect((start + i) * (bw + gap), h - bh, bw, bh);
    });
  }
  function push(list, value) { list.push(value); while (list.length > MAX_SAMPLES) list.shift(); }
  function processes(id, list, byCpu) {
    const el = \$(id);
    el.replaceChildren();
    if (!list || !list.length) return;
    const title = document.createElement('div');
    title.className = 'title';
    title.textContent = 'Top processes';
    el.appendChild(title);
    list.forEach((p) => {
      const row = document.createElement('div');
      row.className = 'proc';
      const name = document.createElement('span');
      name.textContent = p.name;
      const value = document.createElement('span');
      value.textContent = byCpu ? p.cpuPercent.toFixed(1) + '%' : p.rss;
      row.append(name, value);
      el.appendChild(row);
    });
  }

  function render(message) {
    const d = message.data;
    const f = message.fahrenheit;
    if (d.cpu) {
      \$('cpu').textContent = d.cpu.usagePercent.toFixed(0) + '%';
      level(\$('cpu'), d.cpu.usagePercent, 75, 90);
      setBar('cpu-bar', d.cpu.usagePercent);
      push(history.cpu, d.cpu.usagePercent);
      chart('cpu-chart', history.cpu, '#d65d2e');
      const load = d.cpu.loadAverage;
      \$('cpu-sub').textContent = d.cpu.coreCount + ' cores' +
        (load ? ' · load ' + load['1m'].toFixed(2) + ' ' + load['5m'].toFixed(2) + ' ' + load['15m'].toFixed(2) : '');
      processes('cpu-procs', d.cpu.topProcesses, true);
    }
    if (d.ram) {
      \$('ram').textContent = d.ram.usagePercent.toFixed(0) + '%';
      level(\$('ram'), d.ram.usagePercent, 80, 90);
      setBar('ram-bar', d.ram.usagePercent);
      push(history.ram, d.ram.usagePercent);
      chart('ram-chart', history.ram, '#6ca1b8');
      \$('ram-sub').textContent = d.ram.used + ' / ' + d.ram.total + (d.ram.swapUsed ? ' · swap ' + d.ram.swapUsed : '');
      processes('ram-procs', d.ram.topProcesses, false);
    }
    if (d.disk) {
      \$('disk').textContent = d.disk.free + ' free';
      setBar('disk-bar', d.disk.usagePercent);
      \$('disk-sub').textContent = d.disk.volume + ' · ' + d.disk.usagePercent.toFixed(0) + '% of ' + d.disk.total + ' used';
    }
    if (d.network) {
      \$('down').textContent = '↓ ' + d.network.download;
      \$('up').textContent = '↑ ' + d.network.upload;
      \$('net-sub').textContent = d.network.interface || '';
    }
    if (d.thermal) {
      const c = d.thermal.temperatureCelsius;
      \$('temp').textContent = Math.round(f ? c * 9 / 5 + 32 : c) + (f ? '°F' : '°C');
      level(\$('temp'), c, 80, 90);
      \$('temp-sub').textContent = d.thermal.source + (d.thermal.fanRpm != null ? ' · fan ' + d.thermal.fanRpm + ' RPM' : '');
    } else {
      \$('temp-sub').textContent = 'No sensor available';
    }
    if (d.battery) {
      \$('battery').textContent = 'Battery ' + d.battery.levelPercent + '%';
      \$('battery-sub').textContent = d.battery.stateLabel;
    } else {
      \$('battery').textContent = 'AC power';
      \$('battery-sub').textContent = 'No battery';
    }
    \$('session').textContent = 'Session ' + d.session.uptime + ' · plugin ' + d.session.pluginRss;
  }

  function receive(data) {
    let message = data;
    if (typeof message === 'string') { try { message = JSON.parse(message); } catch (e) { return; } }
    if (message && message.type === 'update' && message.data) render(message);
  }
  window.addEventListener('message', (event) => receive(event.data));
  render($initial);
</script>
</body>
</html>
''';
}
