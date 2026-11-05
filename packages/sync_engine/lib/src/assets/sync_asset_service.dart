import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../status/sync_issue.dart';
import '../status/sync_status.dart';

enum AssetAvailabilityState {
  local, // bytes on this device
  remoteReady, // uploaded; can download
  waitingForUpload, // metadata known, the source device has not uploaded yet
  downloading,
  queued, // download requested, waiting for a slot / connection
  offline, // requested but offline; resumes automatically
  failed, // see error; retried on next ensureLocal
  unknown, // no metadata on this device yet
  syncDisabled, // engine disabled or signed out and bytes not local
}

enum AssetPriority { visible, background }

enum AssetPrefetchPolicy { onDemand, recentNotes }

@immutable
final class AssetAvailability {
  const AssetAvailability({
    required this.id,
    required this.state,
    this.receivedBytes,
    this.totalBytes,
    this.error,
  });
  final AssetId id;
  final AssetAvailabilityState state;
  final int? receivedBytes, totalBytes;
  final SyncIssue? error;

  double? get progress {
    final received = receivedBytes, total = totalBytes;
    if (received == null || total == null) return null;
    if (total <= 0) return 1;
    return (received / total).clamp(0, 1).toDouble();
  }

  /// (contract 7.2.20 v1.1) Value equality over the five fields (error by SyncIssue ==).
  @override
  bool operator ==(Object other) =>
      other is AssetAvailability &&
      other.id == id &&
      other.state == state &&
      other.receivedBytes == receivedBytes &&
      other.totalBytes == totalBytes &&
      other.error == error;

  @override
  int get hashCode => Object.hash(id, state, receivedBytes, totalBytes, error);

  @override
  String toString() => 'AssetAvailability($id, ${state.name})';
}

abstract interface class SyncAssetService {
  Future<AssetAvailability> availability(AssetId id);

  /// Emits current availability on listen, then changes (by ==) until local.
  Stream<AssetAvailability> watch(AssetId id);

  /// Requests a download if needed. Completes true when bytes are local,
  /// false when it cannot finish now (offline, waitingForUpload, failed, disabled).
  /// Concurrent calls for the same id share one download.
  Future<bool> ensureLocal(
    AssetId id, {
    AssetPriority priority = AssetPriority.visible,
  });

  void cancel(AssetId id);

  Stream<AssetTransferSummary> get summary;
}
