// lib/src/repo/status.dart, storage_warning.dart — contract 00-overview 7.2.12 / CORE 4.8.1.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/ids.dart';

@immutable
final class PersistenceStatus {
  const PersistenceStatus({
    required this.pendingOps,
    required this.isWriting,
    this.lastCommittedAt,
    this.lastCommitLatency,
    this.lastError,
    this.lastErrorAt,
    this.consecutiveFailures = 0,
  });

  final int pendingOps;
  final bool isWriting;
  final EpochMillis? lastCommittedAt;
  final Duration? lastCommitLatency; // enqueue → commit of the last batch
  final Object? lastError;
  final EpochMillis? lastErrorAt;
  final int consecutiveFailures; // storageWarningOf: >= 3 → writeFailing

  @override
  bool operator ==(Object other) =>
      other is PersistenceStatus &&
      other.pendingOps == pendingOps &&
      other.isWriting == isWriting &&
      other.lastCommittedAt == lastCommittedAt &&
      other.lastCommitLatency == lastCommitLatency &&
      other.lastError == lastError &&
      other.lastErrorAt == lastErrorAt &&
      other.consecutiveFailures == consecutiveFailures;

  @override
  int get hashCode => Object.hash(
    pendingOps,
    isWriting,
    lastCommittedAt,
    lastCommitLatency,
    lastError,
    lastErrorAt,
    consecutiveFailures,
  );

  @override
  String toString() =>
      'PersistenceStatus(pending: $pendingOps, writing: $isWriting, '
      'failures: $consecutiveFailures, lastError: $lastError)';
}

enum StorageBackend {
  nativeFile,
  nativeMemory,
  webOpfsShared,
  webOpfsLocks,
  webSharedIndexedDb,
  webUnsafeIndexedDb,
  webInMemory,
}

@immutable
final class StorageInfo {
  const StorageInfo({
    required this.backend,
    this.missingBrowserFeatures = const [],
    this.persistGranted,
    this.usageBytes,
    this.quotaBytes,
  });

  final StorageBackend backend;

  /// False for webInMemory, nativeMemory.
  bool get isDurable =>
      backend != StorageBackend.webInMemory &&
      backend != StorageBackend.nativeMemory;

  /// False for webUnsafeIndexedDb.
  bool get isMultiTabSafe => backend != StorageBackend.webUnsafeIndexedDb;
  final List<String> missingBrowserFeatures;
  final bool? persistGranted; // navigator.storage.persisted(); null off-web
  // StorageManager.estimate(); null if unsupported
  final int? usageBytes, quotaBytes;

  @override
  bool operator ==(Object other) =>
      other is StorageInfo &&
      other.backend == backend &&
      const ListEquality<String>().equals(
        other.missingBrowserFeatures,
        missingBrowserFeatures,
      ) &&
      other.persistGranted == persistGranted &&
      other.usageBytes == usageBytes &&
      other.quotaBytes == quotaBytes;

  @override
  int get hashCode => Object.hash(
    backend,
    const ListEquality<String>().hash(missingBrowserFeatures),
    persistGranted,
    usageBytes,
    quotaBytes,
  );

  @override
  String toString() =>
      'StorageInfo(${backend.name}, persist: $persistGranted, '
      'usage: $usageBytes / $quotaBytes)';
}

enum StorageWarning { writeFailing, notDurable }

/// writeFailing when status.consecutiveFailures >= 3, else notDurable when !info.isDurable,
/// else null. LIBRARY (library screen) and EDITOR (editor screen) show the same banner text.
StorageWarning? storageWarningOf(StorageInfo info, PersistenceStatus status) {
  if (status.consecutiveFailures >= 3) return StorageWarning.writeFailing;
  if (!info.isDurable) return StorageWarning.notDurable;
  return null;
}
