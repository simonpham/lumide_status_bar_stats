/// Formatting helpers for status bar text and tooltips.
library;

const _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

/// Formats a byte count with binary units, e.g. `512 MB`, `1.5 GB`.
///
/// Values below 10 in their unit keep one decimal; larger ones are rounded.
String formatBytes(num bytes) {
  if (bytes.isNaN || bytes <= 0) return '0 B';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  // Rounding can push a value to 1024 (e.g. 1023.6 KB), so promote it.
  if (value.round() >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '${value.round()} B';
  final digits = value < 10 ? 1 : 0;
  return '${value.toStringAsFixed(digits)} ${_units[unit]}';
}

/// Formats a transfer rate, e.g. `0 B/s`, `12 KB/s`, `1.2 MB/s`.
String formatRate(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// Formats a percentage without decimals, e.g. `42%`.
String formatPercent(num percent) => '${percent.round()}%';

/// Formats a temperature in the chosen unit, e.g. `63°C` or `145°F`.
String formatTemperature(double celsius, {bool fahrenheit = false}) {
  final value = fahrenheit ? celsius * 9 / 5 + 32 : celsius;
  return '${value.round()}°${fahrenheit ? 'F' : 'C'}';
}

/// Formats a duration for the status bar: `45s`, `12m`, `3h 05m`, `2d 4h`.
///
/// Uses minutes as the smallest unit after the first minute, so the text
/// changes at most once a minute.
String formatDuration(Duration duration) {
  if (duration.isNegative) duration = Duration.zero;
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (duration.inHours > 0) {
    return '${duration.inHours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (duration.inMinutes > 0) return '${duration.inMinutes}m';
  return '${duration.inSeconds}s';
}

/// Formats minutes as `1h 23m` or `23m`.
String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}
