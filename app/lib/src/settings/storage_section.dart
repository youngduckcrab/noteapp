import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../app/strings.dart';
import '../errors/app_error_log.dart';
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
/// consecutive failures. (v2.14-ui, UI stage 1) Outside developer mode
/// (core.developerModeProvider) only usage / quota, 첨부 파일 and the search
/// index row (+ the failing-writes warning and the buttons); the rest is the
/// developer diagnostics table.
/// 2차 (docs/plans/m5-7/01-infra.md 6.18):
/// - '첨부 파일 n개 · x MB (녹음 a MB · 이미지 b MB · PDF c MB)' from
///   AssetStore.usage() (bytesByType; a missing type is 0) — queried when the
///   section is shown and again with "다시 확인" (the 1차 rule).
/// - '검색 색인: 대기 n개 · 재구축 중' over SearchIndex.status + [다시 만들기]
///   (key app.storage.rebuildIndex): confirm dialog → SearchIndex.rebuild();
///   the button is disabled while this section's rebuild runs or the status
///   says rebuilding. A failed rebuild → a note + one AppErrorLog record
///   (source manual).
class StorageSection extends ConsumerStatefulWidget {
  const StorageSection({super.key});

  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  late Future<AssetStorageUsage> _usage;
  StreamSubscription<SearchIndexStatus>? _indexStatus;
  SearchIndexStatus _index = const SearchIndexStatus();
  bool _rebuilding = false;
  bool _rebuildFailed = false;

  @override
  void initState() {
    super.initState();
    _usage = _queryUsage();
    _indexStatus = ref.read(searchIndexProvider).status.listen((status) {
      if (mounted) setState(() => _index = status);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    unawaited(_indexStatus?.cancel());
    super.dispose();
  }

  Future<AssetStorageUsage> _queryUsage() =>
      ref.read(assetStoreProvider).usage();

  void _refresh() {
    ref.invalidate(latestStorageInfoProvider);
    final usage = _queryUsage();
    setState(() {
      _usage = usage;
    });
  }

  Future<void> _rebuildIndex() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.storageSearchIndex),
        content: const Text(AppStrings.storageRebuildConfirm),
        actions: [
          TextButton(
            key: const Key('app.storage.rebuildIndex.cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: const Key('app.storage.rebuildIndex.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.storageRebuildIndex),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _rebuilding) return;
    final index = ref.read(searchIndexProvider);
    final errorLog = ref.read(appErrorLogProvider);
    setState(() {
      _rebuilding = true;
      _rebuildFailed = false;
    });
    try {
      await index.rebuild();
    } catch (error, stackTrace) {
      errorLog.add(
        AppErrorRecord.fromError(
          error,
          stackTrace,
          source: AppErrorSource.manual,
        ),
      );
      if (mounted) setState(() => _rebuildFailed = true);
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final developer = ref.watch(developerModeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (developer) ...[
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
        ],
        _InfoRow(
          label: AppStrings.storageUsage,
          value: usage == null && quota == null
              ? AppStrings.unknown
              : '${usage == null ? '?' : AppStrings.bytes(usage)} / '
                    '${quota == null ? '?' : AppStrings.bytes(quota)}',
        ),
        FutureBuilder<AssetStorageUsage>(
          future: _usage,
          builder: (context, snapshot) => _InfoRow(
            key: const Key('storage-assets'),
            label: AppStrings.storageAssets,
            value: switch (snapshot) {
              AsyncSnapshot(:final data?) => AppStrings.storageAssetUsage(
                count: data.assetCount,
                total: data.totalBytes,
                audio: data.bytesByType[AssetType.audio] ?? 0,
                image: data.bytesByType[AssetType.image] ?? 0,
                pdf: data.bytesByType[AssetType.pdf] ?? 0,
              ),
              AsyncSnapshot(hasError: true) => AppStrings.storageAssetsUnread,
              _ => '…',
            },
            warn: snapshot.hasError,
          ),
        ),
        if (developer) ...[
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
        ],
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
        _InfoRow(
          key: const Key('storage-search-index'),
          label: AppStrings.storageSearchIndex,
          value: AppStrings.storageSearchIndexStatus(
            _index.pendingOwners,
            rebuilding: _index.rebuilding || _rebuilding,
          ),
        ),
        if (_rebuildFailed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              AppStrings.storageRebuildFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const Key('storage-refresh'),
                onPressed: latest.isLoading ? null : _refresh,
                icon: latest.isLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text(AppStrings.storageRefresh),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const ValueKey<String>('app.storage.rebuildIndex'),
                onPressed: _rebuilding || _index.rebuilding
                    ? null
                    : _rebuildIndex,
                icon: const Icon(Icons.manage_search),
                label: const Text(AppStrings.storageRebuildIndex),
              ),
            ),
          ],
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
  const _InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.warn = false,
  });

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
