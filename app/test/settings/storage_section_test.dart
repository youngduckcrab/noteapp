// StorageSection (docs/plans/01-infra.md 4.5.8, 4.5.10, 9.1; 계약 7.2.12
// v1.1): CORE StorageInfo through latestStorageInfoProvider (the shell's
// only refreshStorageInfo() caller, which then invalidates
// storageInfoProvider) and PersistenceStatus through
// persistenceStatusProvider (first frame: NoteStore.persistenceStatus).
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/app/strings.dart';
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
}) async {
  final harness = SettingsHarness(store: store, build: BuildInfo.local);
  final show = ValueNotifier(true);
  addTearDown(show.dispose);
  final container = await harness.pump(tester, _Page(showSection: show));
  if (settle) await tester.pumpAndSettle();
  return (harness, container, show);
}

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
}
