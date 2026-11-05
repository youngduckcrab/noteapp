// syncBadgeOf (4.4.1, contract 7.2.20 / 7.3.3 v1.1, SYNC-3-1): four fields mapped, the first
// blocking issue's code, null for non-blocking issues only; states that differ only outside
// the badge give the same SyncBadge, so statusStream.map(syncBadgeOf).distinct() emits once.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';

SyncIssue issue(SyncIssueCode code) =>
    SyncIssue(code: code, message: code.name, firstAt: 1, lastAt: 1);

const SyncStatus base = SyncStatus(
  phase: SyncPhase.live,
  display: SyncDisplayState.inProgress,
  pendingUploads: 3,
  lastSyncedAt: 42,
);

SyncStatus copy(
  SyncStatus s, {
  int? pendingUploads,
  bool? isPushing,
  InitialSyncProgress? initialSync,
  AssetTransferSummary? assets,
  int? nextRetryAt,
  Duration? clockSkew,
  List<SyncIssue>? issues,
}) => SyncStatus(
  phase: s.phase,
  display: s.display,
  user: s.user,
  pendingUploads: pendingUploads ?? s.pendingUploads,
  quarantinedUploads: s.quarantinedUploads,
  isPushing: isPushing ?? s.isPushing,
  initialSync: initialSync ?? s.initialSync,
  assets: assets ?? s.assets,
  lastSyncedAt: s.lastSyncedAt,
  nextRetryAt: nextRetryAt ?? s.nextRetryAt,
  issues: issues ?? s.issues,
  isOnline: s.isOnline,
  clockSkew: clockSkew ?? s.clockSkew,
);

void main() {
  test('maps display, pendingUploads, lastSyncedAt; no issue → null code', () {
    expect(
      syncBadgeOf(base),
      const SyncBadge(
        display: SyncDisplayState.inProgress,
        pendingChanges: 3,
        lastSyncedAt: 42,
      ),
    );
  });

  test('issueCode = the first blocking issue\'s code name', () {
    final s = copy(
      base,
      issues: [
        issue(SyncIssueCode.malformedRemoteData),
        issue(SyncIssueCode.clockSkew),
        issue(SyncIssueCode.reauthRequired),
      ],
    );
    expect(syncBadgeOf(s).issueCode, 'clockSkew');
  });

  test('non-blocking issues only → null issueCode', () {
    final s = copy(
      base,
      issues: [
        issue(SyncIssueCode.clockSkewWarning),
        issue(SyncIssueCode.needsAppUpdate),
        issue(SyncIssueCode.assetCorrupt),
      ],
    );
    expect(syncBadgeOf(s).issueCode, isNull);
  });

  test('states differing only outside the badge give the same SyncBadge; '
      'map(syncBadgeOf).distinct() emits once', () async {
    final others = [
      copy(base, assets: const AssetTransferSummary(downloadsActive: 2)),
      copy(
        base,
        initialSync: const InitialSyncProgress(
          chunksApplied: 3,
          recordsApplied: 9,
          startedAt: 1,
        ),
      ),
      copy(base, isPushing: true),
      copy(base, nextRetryAt: 99),
      copy(base, clockSkew: const Duration(minutes: 5)),
      copy(base, issues: [issue(SyncIssueCode.clockSkewWarning)]),
    ];
    for (final s in others) {
      expect(s, isNot(base));
      expect(syncBadgeOf(s), syncBadgeOf(base));
    }
    final badges = await Stream.fromIterable([base, ...others])
        .map(syncBadgeOf)
        .distinct()
        .toList();
    expect(badges, [syncBadgeOf(base)]);
  });

  test('pendingUploads alone differs → another SyncBadge; distinct() emits '
      'twice', () async {
    final more = copy(base, pendingUploads: 4);
    expect(syncBadgeOf(more), isNot(syncBadgeOf(base)));
    expect(syncBadgeOf(more).pendingChanges, 4);
    final badges = await Stream.fromIterable([base, more])
        .map(syncBadgeOf)
        .distinct()
        .toList();
    expect(badges, hasLength(2));
  });
}
