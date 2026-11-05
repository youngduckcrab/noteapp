import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

enum SyncIssueCode {
  reauthRequired, // blocking: session expired, user must sign in again
  accountMismatch, // blocking: device bound to another account (6.10.4)
  permissionDenied, // blocking: rules/project misconfigured
  backendMisconfigured, // blocking: failedPrecondition (missing index etc.)
  localStoreFailure, // blocking: CORE write failed repeatedly
  // blocking: a clock is off by more than 24 h (6.2.5). nodeId == own
  // deviceNodeId → uploads and remote apply paused (K3) or future records held
  // back (K4); other nodeId → that device's records held (K1)
  clockSkew,
  quotaExceeded, // slowed down (SyncConfig.quotaBackoff)
  entityTooLarge, // one entity > chunk hard limit, kept local only
  rejectedByServer, // invalidArgument for one entity, kept local only
  malformedRemoteData, // undecodable chunk/record skipped
  foreignOwnerData, // record with another ownerId skipped
  needsAppUpdate, // chunk format newer than this app, deferred
  clockSkewWarning, // |server - local| in (2 min, 24 h]: data applied normally (6.2.4)
  assetTooLarge,
  assetUploadFailed,
  assetDownloadFailed,
  assetCorrupt; // downloaded bytes failed hash check twice

  /// The first six.
  bool get isBlocking => index <= clockSkew.index;
}

@immutable
final class SyncIssue {
  const SyncIssue({
    required this.code,
    required this.message,
    required this.firstAt,
    required this.lastAt,
    this.count = 1,
    this.ref,
    this.assetId,
    this.nodeId,
  });
  final SyncIssueCode code;

  /// English, for developer overlay / logs (UI maps code → 한국어).
  final String message;
  final EpochMillis firstAt, lastAt;
  final int count;
  final EntityRef? ref;
  final AssetId? assetId;

  /// clockSkew: the device whose clock is off.
  final String? nodeId;

  bool get isBlocking => code.isBlocking;

  /// (contract 7.2.20 v1.1) Value equality over all eight fields (EntityRef has value ==).
  @override
  bool operator ==(Object other) =>
      other is SyncIssue &&
      other.code == code &&
      other.message == message &&
      other.firstAt == firstAt &&
      other.lastAt == lastAt &&
      other.count == count &&
      other.ref == ref &&
      other.assetId == assetId &&
      other.nodeId == nodeId;

  @override
  int get hashCode =>
      Object.hash(code, message, firstAt, lastAt, count, ref, assetId, nodeId);

  @override
  String toString() => 'SyncIssue(${code.name}, $message)';
}
