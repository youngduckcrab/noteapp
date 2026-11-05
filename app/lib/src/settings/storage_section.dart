import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../app/strings.dart';
import '../providers.dart';

/// '저장 공간': CORE StorageInfo and PersistenceStatus.
/// - StorageInfo: shows latestStorageInfoProvider (re-queried when the section
///   is shown; "다시 확인" = ref.invalidate(latestStorageInfoProvider)), and
///   storageInfoProvider while that is loading. latestStorageInfoProvider is
///   the ONLY place in the app shell that calls refreshStorageInfo(); right
///   after it returns it calls ref.invalidate(storageInfoProvider) (계약 7.2.12
///   v1.1, C11-10) so the LIBRARY / EDITOR banners and diagnostics see the new
///   persistGranted / usage. This section uses the returned value directly.
/// - PersistenceStatus: persistenceStatusProvider (first value arrives right
///   after subscribing — 계약 7.2.12 v1.1, C11-09; the first frame falls back
///   to NoteStore.persistenceStatus).
/// Shows backend, durable, multi-tab safety, persistGranted, usage / quota,
/// missing browser features, pending writes, last commit time + latency,
/// consecutive failures.
class StorageSection extends ConsumerWidget {
  const StorageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestStorageInfoProvider);
    final StorageInfo info = latest.value ?? ref.watch(storageInfoProvider);
    final status =
        ref.watch(persistenceStatusProvider).value ??
        ref.watch(noteStoreProvider).persistenceStatus;
    final theme = Theme.of(context);
    final usage = info.usageBytes;
    final quota = info.quotaBytes;
    final committedAt = status.lastCommittedAt;
    final latency = status.lastCommitLatency;
    final lastError = status.lastError;
    final failing = status.consecutiveFailures >= 3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow(
          label: AppStrings.storageBackend,
          value: '${_backendLabel(info.backend)} (${info.backend.name})',
        ),
        _InfoRow(
          label: AppStrings.storageDurability,
          value: info.isDurable
              ? AppStrings.storageDurable
              : AppStrings.storageNotDurable,
          warn: !info.isDurable,
        ),
        _InfoRow(
          label: AppStrings.storageMultiTab,
          value: info.isMultiTabSafe
              ? AppStrings.storageMultiTabSafe
              : AppStrings.storageMultiTabUnsafe,
          warn: !info.isMultiTabSafe,
        ),
        _InfoRow(
          label: AppStrings.storagePersist,
          value: switch (info.persistGranted) {
            true => AppStrings.storagePersistGranted,
            false => AppStrings.storagePersistDenied,
            null => AppStrings.unknown,
          },
          warn: info.persistGranted == false,
        ),
        _InfoRow(
          label: AppStrings.storageUsage,
          value: usage == null && quota == null
              ? AppStrings.unknown
              : '${usage == null ? '?' : AppStrings.bytes(usage)} / '
                    '${quota == null ? '?' : AppStrings.bytes(quota)}',
        ),
        _InfoRow(
          label: AppStrings.storageMissingFeatures,
          value: info.missingBrowserFeatures.isEmpty
              ? AppStrings.none
              : info.missingBrowserFeatures.join(', '),
        ),
        _InfoRow(
          label: AppStrings.storagePending,
          value: AppStrings.storagePendingOps(
            status.pendingOps,
            writing: status.isWriting,
          ),
        ),
        _InfoRow(
          label: AppStrings.storageLastCommit,
          value: committedAt == null
              ? AppStrings.storageNoCommit
              : '${_clockTime(DateTime.fromMillisecondsSinceEpoch(committedAt))}'
                    '${latency == null ? '' : ' (${AppStrings.groupDigits(latency.inMilliseconds)}ms)'}',
        ),
        _InfoRow(
          label: AppStrings.storageFailures,
          value: AppStrings.storageFailureCount(status.consecutiveFailures),
          warn: failing,
        ),
        if (lastError != null)
          _InfoRow(
            label: AppStrings.storageLastError,
            value: [
              if (status.lastErrorAt case final at?)
                _clockTime(DateTime.fromMillisecondsSinceEpoch(at)),
              _shorten('$lastError', 200),
            ].join(' '),
            warn: failing,
          ),
        if (failing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              AppStrings.storageWriteFailing,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (latest.hasError && !latest.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              AppStrings.storageRefreshFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              key: const Key('storage-refresh'),
              onPressed: latest.isLoading
                  ? null
                  : () => ref.invalidate(latestStorageInfoProvider),
              icon: latest.isLoading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text(AppStrings.storageRefresh),
            ),
          ),
        ),
      ],
    );
  }

  /// Korean label of a CORE storage backend.
  static String _backendLabel(StorageBackend backend) => switch (backend) {
    StorageBackend.nativeFile => '이 기기의 파일',
    StorageBackend.nativeMemory => '메모리 (임시)',
    StorageBackend.webOpfsShared => 'OPFS · 공유 워커',
    StorageBackend.webOpfsLocks => 'OPFS · 웹 잠금',
    StorageBackend.webSharedIndexedDb => 'IndexedDB · 공유 워커',
    StorageBackend.webUnsafeIndexedDb => 'IndexedDB · 단일 탭',
    StorageBackend.webInMemory => '메모리 (임시)',
  };

  /// `18:20:31` (local time).
  static String _clockTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  static String _shorten(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1)}…';
}

/// One `label · value` line. The value wraps; the label column is fixed.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: warn ? scheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
