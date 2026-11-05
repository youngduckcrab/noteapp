// lib/src/sync/sync_display.dart — contract 00-overview 7.2.13 / CORE 4.8.2.
import 'package:meta/meta.dart';

import '../common/ids.dart';

// PLAN F-07 + off
enum SyncDisplayState { off, done, inProgress, offline, error }

@immutable
final class SyncBadge {
  const SyncBadge({
    required this.display,
    this.pendingChanges = 0,
    this.lastSyncedAt,
    this.issueCode,
  });

  static const SyncBadge off = SyncBadge(display: SyncDisplayState.off);

  final SyncDisplayState display;
  final int pendingChanges; // local changes not yet acknowledged
  final EpochMillis? lastSyncedAt;
  // SYNC SyncIssueCode.name of the first blocking issue
  final String? issueCode;

  /// (v1.1) Value equality over all four fields (7.4.4) — the M4 override uses .distinct().
  @override
  bool operator ==(Object other) =>
      other is SyncBadge &&
      other.display == display &&
      other.pendingChanges == pendingChanges &&
      other.lastSyncedAt == lastSyncedAt &&
      other.issueCode == issueCode;

  @override
  int get hashCode =>
      Object.hash(display, pendingChanges, lastSyncedAt, issueCode);

  @override
  String toString() =>
      'SyncBadge(${display.name}, pending: $pendingChanges, '
      'lastSyncedAt: $lastSyncedAt, issue: $issueCode)';
}
