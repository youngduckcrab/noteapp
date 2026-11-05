// lib/src/l10n/library_date_format.dart — 05-library 6.18. Local time; no
// intl (contract 7.4.5). Callers pass now = ref.watch(clockProvider).now().
import 'package:note_core/note_core.dart' show EpochMillis;

const int _dayMs = 24 * 60 * 60 * 1000;

/// Local time. Same day → '오늘 오후 2:05'; previous calendar day → '어제 오전 9:30';
/// same year → '11월 4일'; else → '2025. 11. 4.'. 12-hour clock: 0 h → '오전 12:xx',
/// 12 h → '오후 12:xx'. Future timestamps (clock skew) → treated as today.
String formatLibraryDate(EpochMillis millis, {required DateTime now}) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  final localNow = now.toLocal();
  if (t.isAfter(localNow) || _sameDay(t, localNow)) return '오늘 ${_time(t)}';
  final yesterday = DateTime(localNow.year, localNow.month, localNow.day - 1);
  if (_sameDay(t, yesterday)) return '어제 ${_time(t)}';
  if (t.year == localNow.year) return '${t.month}월 ${t.day}일';
  return '${t.year}. ${t.month}. ${t.day}.';
}

/// max(0, ceil((expiresAt - now) / 1 day)) → '$n일 남음' | '오늘 삭제'.
String formatTrashRemaining(EpochMillis expiresAt, {required DateTime now}) {
  final n = trashDaysLeft(expiresAt, now: now);
  return n == 0 ? '오늘 삭제' : '$n일 남음';
}

/// max(0, ceil((expiresAt - now) / 1 day)).
int trashDaysLeft(EpochMillis expiresAt, {required DateTime now}) {
  final left = expiresAt - now.millisecondsSinceEpoch;
  if (left <= 0) return 0;
  return (left / _dayMs).ceil();
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// '오전 9:30', '오후 2:05', '오전 12:00' (0 h), '오후 12:00' (12 h).
String _time(DateTime t) {
  final period = t.hour < 12 ? '오전' : '오후';
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final mm = t.minute.toString().padLeft(2, '0');
  return '$period $h12:$mm';
}
