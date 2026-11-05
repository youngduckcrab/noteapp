// formatLibraryDate / formatTrashRemaining (05-library 6.18, 8 L1).
import 'package:feature_library/src/l10n/library_date_format.dart';
import 'package:flutter_test/flutter_test.dart';

int _ms(DateTime t) => t.millisecondsSinceEpoch;

void main() {
  // Wednesday 2026-11-04 14:05 local (the TestClock default).
  final now = DateTime(2026, 11, 4, 14, 5);

  group('formatLibraryDate', () {
    final cases = <(String, DateTime, String)>[
      ('today, afternoon', DateTime(2026, 11, 4, 14, 5), '오늘 오후 2:05'),
      ('today, morning', DateTime(2026, 11, 4, 9, 30), '오늘 오전 9:30'),
      ('today, midnight → 오전 12', DateTime(2026, 11, 4, 0, 0), '오늘 오전 12:00'),
      ('today, 0:59', DateTime(2026, 11, 4, 0, 59), '오늘 오전 12:59'),
      ('today, 11:59', DateTime(2026, 11, 4, 11, 59), '오늘 오전 11:59'),
      ('today, noon → 오후 12', DateTime(2026, 11, 4, 12, 0), '오늘 오후 12:00'),
      ('today, 12:30', DateTime(2026, 11, 4, 12, 30), '오늘 오후 12:30'),
      ('today, 13:00', DateTime(2026, 11, 4, 13, 0), '오늘 오후 1:00'),
      ('yesterday', DateTime(2026, 11, 3, 9, 30), '어제 오전 9:30'),
      ('yesterday, last minute', DateTime(2026, 11, 3, 23, 59), '어제 오후 11:59'),
      ('yesterday, first minute', DateTime(2026, 11, 3, 0, 0), '어제 오전 12:00'),
      ('two days ago', DateTime(2026, 11, 2, 23, 59), '11월 2일'),
      ('this year', DateTime(2026, 1, 1, 0, 0), '1월 1일'),
      ('last year', DateTime(2025, 11, 4, 14, 5), '2025. 11. 4.'),
      ('last year, December', DateTime(2025, 12, 31, 23, 59), '2025. 12. 31.'),
      (
        'future (clock skew), later today',
        DateTime(2026, 11, 4, 18, 0),
        '오늘 오후 6:00',
      ),
      (
        'future (clock skew), next day',
        DateTime(2026, 11, 5, 8, 7),
        '오늘 오전 8:07',
      ),
    ];
    for (final (name, t, expected) in cases) {
      test(name, () => expect(formatLibraryDate(_ms(t), now: now), expected));
    }

    test('yesterday across a month and a year boundary', () {
      expect(
        formatLibraryDate(
          _ms(DateTime(2026, 10, 31, 22)),
          now: DateTime(2026, 11, 1, 1),
        ),
        '어제 오후 10:00',
      );
      expect(
        formatLibraryDate(
          _ms(DateTime(2025, 12, 31, 7, 5)),
          now: DateTime(2026, 1, 1, 9),
        ),
        '어제 오전 7:05',
      );
      expect(
        formatLibraryDate(
          _ms(DateTime(2025, 12, 30, 7, 5)),
          now: DateTime(2026, 1, 1, 9),
        ),
        '2025. 12. 30.',
      );
    });
  });

  group('trash days', () {
    const day = Duration(days: 1);
    final cases = <(String, DateTime, int, String)>[
      ('30 days', now.add(const Duration(days: 30)), 30, '30일 남음'),
      (
        '29 days and a bit → 30',
        now.add(const Duration(days: 29, hours: 1)),
        30,
        '30일 남음',
      ),
      ('3 days', now.add(const Duration(days: 3)), 3, '3일 남음'),
      ('one minute → 1', now.add(const Duration(minutes: 1)), 1, '1일 남음'),
      ('exactly now → 0', now, 0, '오늘 삭제'),
      ('past → 0', now.subtract(day), 0, '오늘 삭제'),
    ];
    for (final (name, expiresAt, days, text) in cases) {
      test(name, () {
        expect(trashDaysLeft(_ms(expiresAt), now: now), days);
        expect(formatTrashRemaining(_ms(expiresAt), now: now), text);
      });
    }
  });
}
