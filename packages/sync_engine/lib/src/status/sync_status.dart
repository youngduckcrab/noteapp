// SyncDisplayState is CORE's (contract 7.2.13): used here, never redefined or re-exported.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../auth/auth_user.dart';
import 'sync_issue.dart';

const ListEquality<SyncIssue> _issuesEq = ListEquality<SyncIssue>();

enum SyncPhase {
  disabled, // no backend configured (Firebase project not connected)
  signedOut,
  connecting, // attaching account, profile/device write, clock probe (6.2.4)
  initialSync, // first full download (no cursor yet)
  catchingUp, // incremental download since cursor
  live, // listener active, uploads flowing
  offline,
  paused, // user paused sync
  error, // blocking issue present (incl. this device's clock off by > 24 h, 6.2.5 K3)
}

@immutable
final class InitialSyncProgress {
  const InitialSyncProgress({
    required this.chunksApplied,
    this.estimatedTotalChunks,
    required this.recordsApplied,
    required this.startedAt,
  });
  final int chunksApplied;

  /// Backend count(), may be null.
  final int? estimatedTotalChunks;
  final int recordsApplied;
  final EpochMillis startedAt;

  /// null if total unknown; clamped 0..1.
  double? get fraction {
    final total = estimatedTotalChunks;
    if (total == null) return null;
    if (total <= 0) return 1;
    return (chunksApplied / total).clamp(0, 1).toDouble();
  }

  /// (contract 7.2.20 v1.1) Value equality over the four fields.
  @override
  bool operator ==(Object other) =>
      other is InitialSyncProgress &&
      other.chunksApplied == chunksApplied &&
      other.estimatedTotalChunks == estimatedTotalChunks &&
      other.recordsApplied == recordsApplied &&
      other.startedAt == startedAt;

  @override
  int get hashCode => Object.hash(
    chunksApplied,
    estimatedTotalChunks,
    recordsApplied,
    startedAt,
  );
}

@immutable
final class AssetTransferSummary {
  const AssetTransferSummary({
    this.uploadsPending = 0,
    this.uploadBytesDone = 0,
    this.uploadBytesTotal = 0,
    this.downloadsActive = 0,
    this.downloadBytesDone = 0,
    this.downloadBytesTotal = 0,
  });
  static const AssetTransferSummary idle = AssetTransferSummary();
  final int uploadsPending;

  /// Current upload batch.
  final int uploadBytesDone, uploadBytesTotal;
  final int downloadsActive;
  final int downloadBytesDone, downloadBytesTotal;

  bool get isIdle => uploadsPending == 0 && downloadsActive == 0;

  /// (contract 7.2.20 v1.1) Value equality over the six counters.
  @override
  bool operator ==(Object other) =>
      other is AssetTransferSummary &&
      other.uploadsPending == uploadsPending &&
      other.uploadBytesDone == uploadBytesDone &&
      other.uploadBytesTotal == uploadBytesTotal &&
      other.downloadsActive == downloadsActive &&
      other.downloadBytesDone == downloadBytesDone &&
      other.downloadBytesTotal == downloadBytesTotal;

  @override
  int get hashCode => Object.hash(
    uploadsPending,
    uploadBytesDone,
    uploadBytesTotal,
    downloadsActive,
    downloadBytesDone,
    downloadBytesTotal,
  );
}

@immutable
final class SyncStatus {
  const SyncStatus({
    required this.phase,
    required this.display,
    this.user,
    this.pendingUploads = 0,
    this.quarantinedUploads = 0,
    this.isPushing = false,
    this.initialSync,
    this.assets = AssetTransferSummary.idle,
    this.lastSyncedAt,
    this.nextRetryAt,
    this.issues = const [],
    this.isOnline = true,
    this.clockSkew,
  });
  final SyncPhase phase;

  /// CORE type (7.2.13), derived — 6.12.
  final SyncDisplayState display;
  final AuthUser? user;

  /// Outbox count (CORE SyncStore.watchPendingCount).
  final int pendingUploads;

  /// Entries the server rejected (6.5.6).
  final int quarantinedUploads;
  final bool isPushing;

  /// Non-null during initialSync.
  final InitialSyncProgress? initialSync;
  final AssetTransferSummary assets;

  /// Last successful push or applied pull.
  final EpochMillis? lastSyncedAt;

  /// While backing off / offline probe.
  final EpochMillis? nextRetryAt;

  /// Active issues, blocking first.
  final List<SyncIssue> issues;
  final bool isOnline;

  /// server - local, median estimate (6.2.4).
  final Duration? clockSkew;

  bool get hasBlockingIssue => issues.any((i) => i.isBlocking);

  /// (contract 7.2.20 v1.1) Value equality over every field; issues compared element-wise
  /// with ListEquality (package:collection, 7.4.4), user / initialSync / assets by their ==.
  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.display == display &&
      other.user == user &&
      other.pendingUploads == pendingUploads &&
      other.quarantinedUploads == quarantinedUploads &&
      other.isPushing == isPushing &&
      other.initialSync == initialSync &&
      other.assets == assets &&
      other.lastSyncedAt == lastSyncedAt &&
      other.nextRetryAt == nextRetryAt &&
      _issuesEq.equals(other.issues, issues) &&
      other.isOnline == isOnline &&
      other.clockSkew == clockSkew;

  @override
  int get hashCode => Object.hash(
    phase,
    display,
    user,
    pendingUploads,
    quarantinedUploads,
    isPushing,
    initialSync,
    assets,
    lastSyncedAt,
    nextRetryAt,
    _issuesEq.hash(issues),
    isOnline,
    clockSkew,
  );

  @override
  String toString() =>
      'SyncStatus(${phase.name}, ${display.name}, pending: $pendingUploads, '
      'issues: ${[for (final i in issues) i.code.name]})';
}
