import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  const a = SyncBadge(
    display: SyncDisplayState.inProgress,
    pendingChanges: 3,
    lastSyncedAt: 100,
    issueCode: 'quota',
  );

  test('value equality over all four fields (7.2.13 v1.1)', () {
    const a2 = SyncBadge(
      display: SyncDisplayState.inProgress,
      pendingChanges: 3,
      lastSyncedAt: 100,
      issueCode: 'quota',
    );
    expect(a2, a);
    expect(a2.hashCode, a.hashCode);
    final variants = [
      const SyncBadge(
        display: SyncDisplayState.done,
        pendingChanges: 3,
        lastSyncedAt: 100,
        issueCode: 'quota',
      ),
      const SyncBadge(
        display: SyncDisplayState.inProgress,
        pendingChanges: 4,
        lastSyncedAt: 100,
        issueCode: 'quota',
      ),
      const SyncBadge(
        display: SyncDisplayState.inProgress,
        pendingChanges: 3,
        lastSyncedAt: 101,
        issueCode: 'quota',
      ),
      const SyncBadge(
        display: SyncDisplayState.inProgress,
        pendingChanges: 3,
        lastSyncedAt: 100,
      ),
    ];
    for (final v in variants) {
      expect(v == a, isFalse, reason: '$v');
    }
  });

  test('.distinct() drops an equal badge', () async {
    const a2 = SyncBadge(
      display: SyncDisplayState.inProgress,
      pendingChanges: 3,
      lastSyncedAt: 100,
      issueCode: 'quota',
    );
    const b = SyncBadge(display: SyncDisplayState.done);
    final out = await Stream.fromIterable([a, a2, b]).distinct().toList();
    expect(out, [a, b]);
    expect(identical(out.first, a), isTrue);
  });

  test('off is the default badge', () {
    expect(SyncBadge.off.display, SyncDisplayState.off);
    expect(SyncBadge.off.pendingChanges, 0);
    expect(SyncBadge.off.lastSyncedAt, isNull);
    expect(SyncBadge.off.issueCode, isNull);
  });
}
