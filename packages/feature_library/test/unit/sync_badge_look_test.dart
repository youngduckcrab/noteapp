// SyncBadgeLook (05-library 6.16.1, 8 L9): the 5 SyncDisplayState values →
// icon, label, tooltip and color role; inProgress with n = 0 / 3, done with
// and without lastSyncedAt, error keeps the generic wording.
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/ui/sidebar/sync_badge_indicator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

void main() {
  final now = DateTime(2026, 11, 4, 14, 5);

  test('off → 이 기기에 저장', () {
    expect(
      SyncBadgeLook.of(SyncBadge.off, now: now),
      const SyncBadgeLook(
        icon: Icons.save_outlined,
        label: '이 기기에 저장',
        tooltip: '노트는 이 기기에만 저장돼요',
        role: SyncBadgeColorRole.onSurfaceVariant,
      ),
    );
  });

  group('done', () {
    test('with lastSyncedAt → 마지막 동기화 <date>', () {
      final at = DateTime(2026, 11, 4, 9, 30).millisecondsSinceEpoch;
      expect(
        SyncBadgeLook.of(
          SyncBadge(display: SyncDisplayState.done, lastSyncedAt: at),
          now: now,
        ),
        const SyncBadgeLook(
          icon: Icons.cloud_done_outlined,
          label: '동기화됨',
          tooltip: '마지막 동기화 오늘 오전 9:30',
          role: SyncBadgeColorRole.onSurfaceVariant,
        ),
      );
      final yesterday = DateTime(2026, 11, 3, 14).millisecondsSinceEpoch;
      expect(
        SyncBadgeLook.of(
          SyncBadge(display: SyncDisplayState.done, lastSyncedAt: yesterday),
          now: now,
        ).tooltip,
        '마지막 동기화 어제 오후 2:00',
      );
    });

    test('without lastSyncedAt → 동기화됨', () {
      final look = SyncBadgeLook.of(
        const SyncBadge(display: SyncDisplayState.done),
        now: now,
      );
      expect(look.label, '동기화됨');
      expect(look.tooltip, '동기화됨');
      expect(look.icon, Icons.cloud_done_outlined);
    });
  });

  group('inProgress', () {
    test('n = 0 → 동기화 중', () {
      expect(
        SyncBadgeLook.of(
          const SyncBadge(display: SyncDisplayState.inProgress),
          now: now,
        ),
        const SyncBadgeLook(
          icon: Icons.sync,
          label: '동기화 중',
          tooltip: '동기화 중',
          role: SyncBadgeColorRole.primary,
        ),
      );
    });

    test('n = 3 → 동기화 중 · 3, 보내는 중인 변경 3개', () {
      expect(
        SyncBadgeLook.of(
          const SyncBadge(
            display: SyncDisplayState.inProgress,
            pendingChanges: 3,
          ),
          now: now,
        ),
        const SyncBadgeLook(
          icon: Icons.sync,
          label: '동기화 중 · 3',
          tooltip: '보내는 중인 변경 3개',
          role: SyncBadgeColorRole.primary,
        ),
      );
    });

    test('a negative count reads as 0', () {
      final look = SyncBadgeLook.of(
        const SyncBadge(
          display: SyncDisplayState.inProgress,
          pendingChanges: -1,
        ),
        now: now,
      );
      expect(look.label, '동기화 중');
      expect(look.tooltip, '동기화 중');
    });
  });

  test('offline → 오프라인', () {
    expect(
      SyncBadgeLook.of(
        const SyncBadge(display: SyncDisplayState.offline, pendingChanges: 2),
        now: now,
      ),
      const SyncBadgeLook(
        icon: Icons.cloud_off_outlined,
        label: '오프라인',
        tooltip: '연결되면 자동으로 동기화해요',
        role: SyncBadgeColorRole.onSurfaceVariant,
      ),
    );
  });

  test('error → 동기화 오류 with the generic tooltip for any issueCode', () {
    const expected = SyncBadgeLook(
      icon: Icons.sync_problem,
      label: '동기화 오류',
      tooltip: '동기화하지 못한 변경이 있어요. 설정에서 확인해 주세요.',
      role: SyncBadgeColorRole.error,
    );
    expect(
      SyncBadgeLook.of(
        const SyncBadge(display: SyncDisplayState.error),
        now: now,
      ),
      expected,
    );
    for (final code in ['quotaExceeded', 'authExpired', 'unknownFutureCode']) {
      expect(
        SyncBadgeLook.of(
          SyncBadge(display: SyncDisplayState.error, issueCode: code),
          now: now,
        ),
        expected,
        reason: code,
      );
    }
  });

  test('every display state has a look; the labels are LibraryStrings', () {
    final labels = {
      for (final display in SyncDisplayState.values)
        display: SyncBadgeLook.of(SyncBadge(display: display), now: now).label,
    };
    expect(labels, {
      SyncDisplayState.off: LibraryStrings.syncOff,
      SyncDisplayState.done: LibraryStrings.syncDone,
      SyncDisplayState.inProgress: LibraryStrings.syncInProgress,
      SyncDisplayState.offline: LibraryStrings.syncOffline,
      SyncDisplayState.error: LibraryStrings.syncError,
    });
  });
}
