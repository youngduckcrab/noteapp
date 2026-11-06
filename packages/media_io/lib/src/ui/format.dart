// lib/src/ui/format.dart — time and size text of the panel (m5-7/06-pdf 6.13.1). Internal.

/// '0:00'-style clock: 'mm:ss' under an hour ('03:12', '45:00'), 'h:mm:ss' from an hour on.
/// Negative values show as 00:00.
String formatClock(int ms) {
  final total = ms <= 0 ? 0 : ms ~/ 1000;
  final h = total ~/ 3600, m = total ~/ 60 % 60, s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
