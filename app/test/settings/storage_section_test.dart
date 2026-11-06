// StorageSection (docs/plans/01-infra.md 4.5.8, 4.5.10, 9.1; 계약 7.2.12
// v1.1): CORE StorageInfo through latestStorageInfoProvider (the shell's
// only refreshStorageInfo() caller, which then invalidates
// storageInfoProvider) and PersistenceStatus through
// persistenceStatusProvider (first frame: NoteStore.persistenceStatus).
//
// 2차 J14 (docs/plans/m5-7/01-infra.md 6.18): the per-type attachment row
// (AssetStore.usage().bytesByType, re-queried when shown and by 다시 확인)
// and the search index row with [다시 만들기] (confirm dialog, disabled while
// rebuilding, failure note + one record) — over assetStoreProvider /
// searchIndexProvider fakes, plus one run on the CORE fake store's own usage.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/settings/storage_section.dart';

import '../fakes/counting_note_store.dart';
import '../support/settings_harness.dart';

const int _mb = 1024 * 1024;

/// Shows storageInfoProvider.persistGranted next to the section (another
/// screen's view of the same container, INFRA-2-5).
class _OtherScreen extends ConsumerWidget {
  const _OtherScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('other persist: ${ref.watch(storageInfoProvider).persistGranted}');
}

/// The section and [_OtherScreen]; the section can be removed while the
/// ProviderScope stays.
class _Page extends StatelessWidget {
  const _Page({required this.showSection});

  final ValueListenable<bool> showSection;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _OtherScreen(),
          ValueListenableBuilder<bool>(
            valueListenable: showSection,
            builder: (context, show, _) =>
                show ? const StorageSection() : const Text('closed'),
          ),
        ],
      ),
    ),
  );
}

Future<(SettingsHarness, ProviderContainer, ValueNotifier<bool>)> _pump(
  WidgetTester tester, {
  CountingNoteStore? store,
  bool settle = true,
  List<Override> extra = const [],
  Size logical = ipadPortrait,
}) async {
  final harness = SettingsHarness(store: store, build: BuildInfo.local);
  final show = ValueNotifier(true);
  addTearDown(show.dispose);
  final container = await harness.pump(
    tester,
    _Page(showSection: show),
    extra: extra,
    logical: logical,
  );
  if (settle) await tester.pumpAndSettle();
  return (harness, container, show);
}

/// AssetStore whose usage() answers from [usages] in order (the last one
/// repeats); [usageError] makes it throw. Counts calls.
final class _FakeAssets implements AssetStore {
  _FakeAssets(this.usages);

  final List<AssetStorageUsage> usages;
  Error? usageError;
  int usageCalls = 0;

  @override
  Future<AssetStorageUsage> usage() async {
    final index = usageCalls++;
    if (usageError case final error?) throw error;
    return usages[index < usages.length ? index : usages.length - 1];
  }

  @override
  Stream<AssetId> get bytesArrived => const Stream.empty();

  @override
  Future<Asset> put(
    Uint8List bytes, {
    required AssetType type,
    required String mimeType,
    String? fileName,
  }) => throw UnimplementedError();

  @override
  Future<Asset?> getAsset(AssetId id) => throw UnimplementedError();

  @override
  Future<Uint8List?> readBytes(AssetId id) => throw UnimplementedError();

  @override
  Future<bool> hasBytes(AssetId id) => throw UnimplementedError();

  @override
  Future<void> putDownloadedBytes(AssetId id, Uint8List bytes) =>
      throw UnimplementedError();

  @override
  Future<List<Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) =>
      throw UnimplementedError();

  @override
  Future<void> markUploaded(AssetId id, String storagePath) =>
      throw UnimplementedError();
}

/// SearchIndex with a status controller; rebuild() waits for [gate] (when
/// set) and throws [rebuildError] (when set). Counts rebuild calls.
final class _FakeIndex implements SearchIndex {
  final StreamController<SearchIndexStatus> statusEvents =
      StreamController<SearchIndexStatus>.broadcast();
  Completer<void>? gate;
  Error? rebuildError;
  int rebuildCalls = 0;
  Set<SearchSource>? lastSources;

  Future<void> close() => statusEvents.close();

  @override
  Stream<SearchIndexStatus> get status => statusEvents.stream;

  @override
  Future<void> rebuild({Set<SearchSource>? sources}) async {
    rebuildCalls++;
    lastSources = sources;
    await gate?.future;
    if (rebuildError case final error?) throw error;
  }

  @override
  Future<List<PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    NoteId? withinNote,
  }) async => const [];

  @override
  Future<String?> sourceRevOf(SearchSource source, String ownerKey) async =>
      null;

  @override
  Future<Map<String, String>> sourceRevs(SearchSource source) async => const {};

  @override
  Future<void> replaceUnits(
    SearchSource source,
    String ownerKey,
    List<SearchUnitDraft> units, {
    required String sourceRev,
  }) async {}

  @override
  Future<void> removeOwner(SearchSource source, String ownerKey) async {}
}

const Key _assetsRow = Key('storage-assets');
const ValueKey<String> _rebuild = ValueKey<String>('app.storage.rebuildIndex');
const Key _confirm = Key('app.storage.rebuildIndex.confirm');
const Key _cancel = Key('app.storage.rebuildIndex.cancel');

String _value(WidgetTester tester, Key row) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(row), matching: find.byType(Text)),
    )
    .last
    .data!;

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).enabled;

void main() {
  testWidgets('shows backend, durability, multi-tab, persist, usage, missing '
      'features', (tester) async {
    final store = CountingNoteStore(
      inner: createFakeNoteStore(
        storageInfo: const StorageInfo(
          backend: StorageBackend.webOpfsShared,
          persistGranted: true,
          usageBytes: 12 * _mb + 300 * 1024,
          quotaBytes: 1024 * _mb,
          missingBrowserFeatures: ['sharedArrayBuffers'],
        ),
      ),
    );
    await _pump(tester, store: store);

    expect(find.text('OPFS · 공유 워커 (webOpfsShared)'), findsOneWidget);
    expect(find.text(AppStrings.storageDurable), findsOneWidget);
    expect(find.text(AppStrings.storageMultiTabSafe), findsOneWidget);
    expect(find.text(AppStrings.storagePersistGranted), findsOneWidget);
    expect(find.text('12.3MB / 1.0GB'), findsOneWidget);
    expect(find.text('sharedArrayBuffers'), findsOneWidget);
    expect(find.text('0건'), findsOneWidget);
    expect(find.text(AppStrings.storageNoCommit), findsOneWidget);
    expect(find.text('0회'), findsOneWidget);
    expect(find.text(AppStrings.storageWriteFailing), findsNothing);
  });

  testWidgets('temporary and single-tab backends, unknown persist / usage', (
    tester,
  ) async {
    for (final (backend, durable, multiTab) in [
      (StorageBackend.webInMemory, false, true),
      (StorageBackend.webUnsafeIndexedDb, true, false),
    ]) {
      final store = CountingNoteStore(
        inner: createFakeNoteStore(storageInfo: StorageInfo(backend: backend)),
      );
      await _pump(tester, store: store);
      expect(
        find.text(AppStrings.storageNotDurable),
        durable ? findsNothing : findsOneWidget,
      );
      expect(
        find.text(AppStrings.storageMultiTabUnsafe),
        multiTab ? findsNothing : findsOneWidget,
      );
      // persistGranted, usage: null → 알 수 없음 (twice); no missing features.
      expect(find.text(AppStrings.unknown), findsNWidgets(2));
      expect(find.text(AppStrings.none), findsOneWidget);
    }
  });

  testWidgets('shown → refreshStorageInfo once; 다시 확인 → again', (tester) async {
    final store = CountingNoteStore();
    await _pump(tester, store: store);
    expect(store.refreshCount, 1);

    await tester.tap(find.byKey(const Key('storage-refresh')));
    await tester.pumpAndSettle();
    expect(store.refreshCount, 2);
  });

  testWidgets('while the refresh is loading the section shows '
      'storageInfoProvider, then the refreshed value', (tester) async {
    final gate = Completer<void>();
    final store = CountingNoteStore(
      inner: createFakeNoteStore(
        storageInfo: const StorageInfo(
          backend: StorageBackend.webOpfsLocks,
          persistGranted: false,
        ),
      ),
      refreshGate: gate,
      refreshResult: const StorageInfo(
        backend: StorageBackend.webOpfsLocks,
        persistGranted: true,
      ),
    );
    await _pump(tester, store: store, settle: false);
    await tester.pump();
    expect(store.refreshCount, 1);
    expect(find.text(AppStrings.storagePersistDenied), findsOneWidget);
    // The refresh button shows progress and is disabled meanwhile.
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('storage-refresh')))
          .enabled,
      isFalse,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.storagePersistGranted), findsOneWidget);
    expect(find.text(AppStrings.storagePersistDenied), findsNothing);
  });

  testWidgets('the status line is there from the first frame, then follows '
      'persistenceStatusStream', (tester) async {
    final store = CountingNoteStore()
      ..emitStatus(const PersistenceStatus(pendingOps: 4, isWriting: false));
    await _pump(tester, store: store, settle: false);
    // First frame: NoteStore.persistenceStatus (the stream value comes next).
    expect(find.text('4건'), findsOneWidget);

    store.emitStatus(
      PersistenceStatus(
        pendingOps: 1,
        isWriting: true,
        lastCommittedAt: DateTime(
          2026,
          11,
          4,
          18,
          20,
          31,
        ).millisecondsSinceEpoch,
        lastCommitLatency: const Duration(milliseconds: 1234),
      ),
    );
    // The stream event arrives in a microtask after the next frame.
    await tester.pumpAndSettle();
    expect(find.text('1건 (저장하는 중)'), findsOneWidget);
    expect(find.text('18:20:31 (1,234ms)'), findsOneWidget);
  });

  testWidgets('consecutiveFailures ≥ 3 → the failing note and the last error', (
    tester,
  ) async {
    final store = CountingNoteStore();
    await _pump(tester, store: store);

    store.emitStatus(
      const PersistenceStatus(
        pendingOps: 2,
        isWriting: true,
        consecutiveFailures: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2회'), findsOneWidget);
    expect(find.text(AppStrings.storageWriteFailing), findsNothing);

    store.emitStatus(
      PersistenceStatus(
        pendingOps: 2,
        isWriting: true,
        consecutiveFailures: 3,
        lastError: StateError('QuotaExceededError'),
        lastErrorAt: DateTime(2026, 11, 4, 18, 21, 5).millisecondsSinceEpoch,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3회'), findsOneWidget);
    expect(find.text(AppStrings.storageWriteFailing), findsOneWidget);
    expect(find.text('18:21:05 Bad state: QuotaExceededError'), findsOneWidget);
  });

  testWidgets('다시 확인 → storageInfoProvider is invalidated: another '
      'Consumer sees the new value (INFRA-2-5)', (tester) async {
    final store = CountingNoteStore();
    final (_, container, _) = await _pump(tester, store: store);
    expect(find.text('other persist: null'), findsOneWidget);
    expect(container.read(storageInfoProvider).persistGranted, isNull);

    store.refreshResult = const StorageInfo(
      backend: StorageBackend.webSharedIndexedDb,
      persistGranted: true,
    );
    await tester.tap(find.byKey(const Key('storage-refresh')));
    await tester.pumpAndSettle();

    expect(find.text('other persist: true'), findsOneWidget);
    expect(container.read(storageInfoProvider).persistGranted, isTrue);
    expect(
      container.read(storageInfoProvider).backend,
      StorageBackend.webSharedIndexedDb,
    );
    expect(find.text('IndexedDB · 공유 워커 (webSharedIndexedDb)'), findsOneWidget);
  });

  testWidgets('closing the section during the refresh await → no exception', (
    tester,
  ) async {
    final gate = Completer<void>();
    final store = CountingNoteStore(
      refreshGate: gate,
      refreshResult: const StorageInfo(
        backend: StorageBackend.nativeFile,
        persistGranted: true,
      ),
    );
    final (_, container, show) = await _pump(
      tester,
      store: store,
      settle: false,
    );
    await tester.pump();
    expect(store.refreshCount, 1);

    show.value = false;
    await tester.pumpAndSettle();
    expect(find.text('closed'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The disposed provider did not invalidate; the next refresh will.
    expect(find.text('other persist: null'), findsOneWidget);

    show.value = true;
    await tester.pumpAndSettle();
    expect(store.refreshCount, 2);
    expect(container.read(storageInfoProvider).persistGranted, isTrue);
    expect(find.text('other persist: true'), findsOneWidget);
  });

  testWidgets('a failed refresh shows a note and keeps storageInfoProvider', (
    tester,
  ) async {
    final store = CountingNoteStore(
      inner: createFakeNoteStore(
        storageInfo: const StorageInfo(
          backend: StorageBackend.webOpfsShared,
          persistGranted: true,
        ),
      ),
      refreshError: StateError('estimate failed'),
    );
    await _pump(tester, store: store);
    expect(find.text(AppStrings.storageRefreshFailed), findsOneWidget);
    expect(find.text(AppStrings.storagePersistGranted), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('첨부 파일 (J14 — 6.18)', () {
    testWidgets('per type: 녹음 · 이미지 · PDF, 1024-based MB', (tester) async {
      final assets = _FakeAssets([
        const AssetStorageUsage(
          assetCount: 3,
          totalBytes: 3 * _mb + 3 * _mb ~/ 2 + 10 * _mb,
          thumbnailBytes: 0,
          bytesByType: {
            AssetType.audio: 3 * _mb,
            AssetType.image: 3 * _mb ~/ 2,
            AssetType.pdf: 10 * _mb,
          },
        ),
      ]);
      await _pump(
        tester,
        extra: [assetStoreProvider.overrideWithValue(assets)],
      );
      expect(find.text(AppStrings.storageAssets), findsOneWidget);
      expect(
        _value(tester, _assetsRow),
        '3개 · 14.5 MB (녹음 3.0 MB · 이미지 1.5 MB · PDF 10.0 MB)',
      );
      expect(assets.usageCalls, 1);
    });

    testWidgets('a missing type reads 0 MB; small sizes', (tester) async {
      final assets = _FakeAssets([
        const AssetStorageUsage(
          assetCount: 2,
          totalBytes: 200 * 1024 + 10 * 1024,
          thumbnailBytes: 4096,
          bytesByType: {AssetType.image: 200 * 1024, AssetType.pdf: 10 * 1024},
        ),
      ]);
      await _pump(
        tester,
        extra: [assetStoreProvider.overrideWithValue(assets)],
      );
      expect(
        _value(tester, _assetsRow),
        '2개 · 0.2 MB (녹음 0 MB · 이미지 0.2 MB · PDF <0.1 MB)',
      );
    });

    testWidgets('no attachments: 0개 · 0 MB everywhere', (tester) async {
      final assets = _FakeAssets([
        const AssetStorageUsage(
          assetCount: 0,
          totalBytes: 0,
          thumbnailBytes: 0,
        ),
      ]);
      await _pump(
        tester,
        extra: [assetStoreProvider.overrideWithValue(assets)],
      );
      expect(
        _value(tester, _assetsRow),
        '0개 · 0 MB (녹음 0 MB · 이미지 0 MB · PDF 0 MB)',
      );
    });

    testWidgets('on the CORE fake store (createFakeNoteStore bytesByType)', (
      tester,
    ) async {
      final store = CountingNoteStore();
      await tester.runAsync(() async {
        await store.assets.put(
          Uint8List(3000),
          type: AssetType.audio,
          mimeType: 'audio/webm',
        );
        await store.assets.put(
          Uint8List.fromList(List.filled(2 * _mb, 7)),
          type: AssetType.image,
          mimeType: 'image/png',
        );
      });
      await _pump(tester, store: store);
      expect(
        _value(tester, _assetsRow),
        '2개 · 2.0 MB (녹음 <0.1 MB · 이미지 2.0 MB · PDF 0 MB)',
      );
    });

    testWidgets('shown → usage once; 다시 확인 → again with the new value', (
      tester,
    ) async {
      final assets = _FakeAssets([
        const AssetStorageUsage(
          assetCount: 1,
          totalBytes: _mb,
          thumbnailBytes: 0,
          bytesByType: {AssetType.audio: _mb},
        ),
        const AssetStorageUsage(
          assetCount: 2,
          totalBytes: 2 * _mb,
          thumbnailBytes: 0,
          bytesByType: {AssetType.audio: 2 * _mb},
        ),
      ]);
      final (_, _, show) = await _pump(
        tester,
        extra: [assetStoreProvider.overrideWithValue(assets)],
      );
      expect(assets.usageCalls, 1);
      expect(_value(tester, _assetsRow), startsWith('1개 · 1.0 MB'));

      await tester.tap(find.byKey(const Key('storage-refresh')));
      await tester.pumpAndSettle();
      expect(assets.usageCalls, 2);
      expect(_value(tester, _assetsRow), startsWith('2개 · 2.0 MB'));

      // Shown again → queried again.
      show.value = false;
      await tester.pumpAndSettle();
      show.value = true;
      await tester.pumpAndSettle();
      expect(assets.usageCalls, 3);
    });

    testWidgets('usage() fails → 읽지 못했어요 (warn colour), the rest stays', (
      tester,
    ) async {
      final assets = _FakeAssets(const [])..usageError = StateError('io');
      await _pump(
        tester,
        extra: [assetStoreProvider.overrideWithValue(assets)],
      );
      expect(_value(tester, _assetsRow), AppStrings.storageAssetsUnread);
      expect(find.text(AppStrings.storageDurable), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('검색 색인 (J14 — 6.18, C-13)', () {
    late _FakeIndex index;
    const indexRow = Key('storage-search-index');

    setUp(() => index = _FakeIndex());
    tearDown(() => index.close());

    Future<SettingsHarness> pumpIndex(
      WidgetTester tester, {
      Size logical = ipadPortrait,
    }) async {
      final (harness, _, _) = await _pump(
        tester,
        extra: [searchIndexProvider.overrideWithValue(index)],
        logical: logical,
      );
      return harness;
    }

    testWidgets('follows SearchIndex.status: 대기 n개 · 재구축 중', (tester) async {
      await pumpIndex(tester);
      expect(find.text(AppStrings.storageSearchIndex), findsOneWidget);
      expect(_value(tester, indexRow), '대기 0개');
      expect(_enabled(tester, _rebuild), isTrue);

      index.statusEvents.add(const SearchIndexStatus(pendingOwners: 3));
      // The event arrives in a microtask; the next pump builds its frame.
      await tester.pump();
      await tester.pump();
      expect(_value(tester, indexRow), '대기 3개');

      index.statusEvents.add(
        const SearchIndexStatus(pendingOwners: 2, rebuilding: true),
      );
      await tester.pump();
      await tester.pump();
      expect(_value(tester, indexRow), '대기 2개 · 재구축 중');
      // Rebuilding elsewhere (CORE on normalizerVersion change) → disabled.
      expect(_enabled(tester, _rebuild), isFalse);

      index.statusEvents.add(const SearchIndexStatus());
      await tester.pump();
      await tester.pump();
      expect(_value(tester, indexRow), '대기 0개');
      expect(_enabled(tester, _rebuild), isTrue);
    });

    testWidgets('다시 만들기 → confirm dialog; 취소 → no rebuild', (tester) async {
      await pumpIndex(tester);
      await tester.tap(find.byKey(_rebuild));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.storageRebuildConfirm), findsOneWidget);
      expect(find.text('검색 색인을 처음부터 다시 만들어요. 시간이 걸릴 수 있어요.'), findsOneWidget);

      await tester.tap(find.byKey(_cancel));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.storageRebuildConfirm), findsNothing);
      expect(index.rebuildCalls, 0);
    });

    testWidgets('confirm → rebuild() once (all sources); disabled until it '
        'ends', (tester) async {
      final h = await pumpIndex(tester);
      index.gate = Completer<void>();
      await tester.tap(find.byKey(_rebuild));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_confirm));
      await tester.pump();
      expect(index.rebuildCalls, 1);
      expect(index.lastSources, isNull);
      expect(_enabled(tester, _rebuild), isFalse);
      expect(_value(tester, indexRow), '대기 0개 · 재구축 중');

      // A tap while disabled does nothing.
      await tester.tap(find.byKey(_rebuild), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.storageRebuildConfirm), findsNothing);

      index.gate!.complete();
      await tester.pumpAndSettle();
      expect(_enabled(tester, _rebuild), isTrue);
      expect(_value(tester, indexRow), '대기 0개');
      expect(index.rebuildCalls, 1);
      expect(find.text(AppStrings.storageRebuildFailed), findsNothing);
      expect(h.errorLog.totalCount, 0);
    });

    testWidgets('rebuild fails → note + one record (manual); the next try '
        'clears the note', (tester) async {
      final h = await pumpIndex(tester);
      index.rebuildError = StateError('fts5 missing');
      await tester.tap(find.byKey(_rebuild));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_confirm));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.storageRebuildFailed), findsOneWidget);
      expect(h.errorLog.totalCount, 1);
      expect(h.errorLog.records.single.source, AppErrorSource.manual);
      expect(h.errorLog.records.single.summary, contains('fts5 missing'));
      expect(_enabled(tester, _rebuild), isTrue);

      index.rebuildError = null;
      await tester.tap(find.byKey(_rebuild));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_confirm));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.storageRebuildFailed), findsNothing);
      expect(index.rebuildCalls, 2);
      expect(h.errorLog.totalCount, 1);
    });

    testWidgets('closing the section during a rebuild → no exception, the '
        'status subscription ends', (tester) async {
      final (_, _, show) = await _pump(
        tester,
        extra: [searchIndexProvider.overrideWithValue(index)],
      );
      expect(index.statusEvents.hasListener, isTrue);
      index.gate = Completer<void>();
      await tester.tap(find.byKey(_rebuild));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_confirm));
      await tester.pump();
      show.value = false;
      await tester.pumpAndSettle();
      expect(index.statusEvents.hasListener, isFalse);
      index.gate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape: rows and buttons fit', (tester) async {
      await pumpIndex(tester, logical: ipadLandscape);
      expect(find.byKey(_rebuild), findsOneWidget);
      expect(find.byKey(_assetsRow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
