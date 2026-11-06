// T14: the public surface of sync_engine's four entry points (07-sync 4.0 table, contract
// 00-overview 7.1, 7.2.0 and 7.2.20 v1.1 / v1.2).
//
// - Source text (support/api_surface.dart): the public names each entry point exports, through
//   every export, equal the 4.0 table exactly — nothing more (internal files stay internal),
//   nothing re-exported from another package (CORE names are used, never re-exported).
// - Compile time: every table name is referred to through its entry point (imported without a
//   prefix), and the names that must not be visible (CORE names, the names removed in
//   revisions 1 and 2, syncScenario / expectConverged / FakeAsync, internal classes) are
//   declared again in support/absent_names.dart, imported next to the entry points: if an
//   entry point exported one, the reference would be ambiguous and this file would not
//   compile.
// - Members: SyncTestHarness.checkConverged exists; SyncTestHarness.async and
//   .expectConverged do not (an extension member returning [Absent] would lose to a class
//   member, and the assignment to Absent would not compile). (2nd round, 07-sync 4.3) the
//   harness's device(knownKinds:) / restart / checkConverged(kinds:) and the TestDevice
//   helpers have their 4.3 signatures (tear-offs assigned to the exact function types).
// - The contract types the other areas plug in (syncBadgeOf, SyncRemoteAssetFetcher,
//   SyncMergePolicy.decide) have the CORE types (contract 7.2.20, 7.3.3).
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:sync_engine/firebase.dart';
import 'package:sync_engine/platform.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/absent_names.dart';
import 'support/api_surface.dart';

extension on SyncTestHarness {
  Absent get async => const Absent();
  Absent expectConverged(Object? devices) => const Absent();
}

/// 07-sync 4.0: `sync_engine.dart` exports 4.1 ~ 4.9.
const Map<String, List<String>> kSyncEngineSurface = {
  '4.1': [
    'ServerCursor',
    'SyncErrorCode',
    'SyncBackendException',
    'SignInErrorCode',
    'SignInException',
    'SyncCancelToken',
  ],
  '4.2': [
    'SyncDoc',
    'SyncRecord',
    'UpsertRecord',
    'PurgeRecord',
    'FieldUnits',
    'SyncScopes',
  ],
  '4.3': ['AuthUser', 'AuthBackend', 'AuthStatus', 'AuthState', 'AuthService'],
  '4.4': [
    'SyncPhase',
    'SyncStatus',
    'InitialSyncProgress',
    'AssetTransferSummary',
    'SyncIssueCode',
    'SyncIssue',
    'SyncNotice',
    'FolderCycleResolved',
    'PageRestored',
    'NoteRecoveredFromPurge',
    'InitialSyncCompleted',
    'syncBadgeOf',
  ],
  '4.5': [
    'SyncBackendFactory',
    'SyncLifecycle',
    'SyncLogLevel',
    'SyncLogSink',
    'SyncUsage',
    'SyncEngine',
    'SyncEngineDebug',
    'ConnectivitySignal',
    'AlwaysOnlineSignal',
    'ManualConnectivitySignal',
    'AssetAvailabilityState',
    'AssetPriority',
    'AssetPrefetchPolicy',
    'AssetAvailability',
    'SyncAssetService',
    'SyncRemoteAssetFetcher',
  ],
  '4.6': ['DevicePlatform', 'CompactionConfig', 'SyncConfig'],
  '4.7': [
    'syncConfigProvider',
    'authBackendProvider',
    'syncBackendFactoryProvider',
    'connectivitySignalProvider',
    'syncLocalStoreProvider',
    'authServiceProvider',
    'authStateProvider',
    'syncEngineProvider',
    'syncStatusProvider',
    'syncNoticesProvider',
    'syncAssetServiceProvider',
    'assetAvailabilityProvider',
    'syncUsageProvider',
  ],
  '4.8': [
    'ChunkKind',
    'ChunkWrite',
    'RemoteChunk',
    'ChunkPage',
    'SyncBackend',
    'UserProfile',
    'DeviceInfo',
    'RemoteBlobInfo',
    'RemoteBlobStore',
  ],
  '4.9': ['SyncLocalStore', 'CoreSyncLocalStore', 'SyncMergePolicy'],
};

/// 07-sync 4.0: `testing.dart` exports 4.11 (syncScenario stays in test/).
const List<String> kTestingSurface = [
  'FakeSyncServer',
  'StoredChunk',
  'FakeSyncBackend',
  'FakeNetworkLink',
  'FakeOp',
  'FakeFault',
  'FakeNetworkError',
  'FakeAckLost',
  'FakeErrorCode',
  'FakeInterrupt',
  'FakeBlobStore',
  'FakeAuthBackend',
  'FakeLocalStore',
  'FakeLocalWrite',
  'TestDevice',
  'SyncTestHarness',
];

/// 07-sync 4.0: `firebase.dart` exports 4.10 (without ConnectivityPlusSignal).
const List<String> kFirebaseSurface = [
  'WebSignInMode',
  'FirebaseSyncOptions',
  'FirebaseSyncBindings',
  'NativeGoogleSignIn',
  'FirebaseSyncBackend',
  'FirestoreChunkMapper',
  'FirebaseBlobStore',
  'FirebaseAuthBackend',
  'mapFirebaseError',
  'mapSignInError',
];

/// 07-sync 4.0: `platform.dart` exports ConnectivityPlusSignal.
const List<String> kPlatformSurface = ['ConnectivityPlusSignal'];

/// Every name of support/absent_names.dart (the reference is the compile-time check).
final List<Object> _absent = [
  // CORE names (4.0, 5.1.1).
  EntityKind, EntityRef, Hlc, HlcClock, OutboxOp, OutboxEntry, OutboxAck,
  kAllFields, EntityFieldVersions, VersionedEntity, RemoteChange, RemoteUpsert,
  RemotePurge, MergeDecision, KeepLocal, TakeRemote, WriteMerged,
  RemoteMergePolicy, RemoteApplyReport, RepairWrite, SyncStore, AssetStore,
  Asset, AssetType, SyncEntity, EntityJson, SyncDisplayState, SyncBadge,
  RemoteAssetFetcher, RemoteAssetState, RemoteAssetProgress, FolderId, NoteId,
  PageId, AssetId, OwnerId, EpochMillis, kLocalOwnerId, noRetry,
  noteStoreProvider, clockProvider,
  // Removed in revision 1 (contract 7.2.20 v1.1 '삭제').
  syncDisplayStateProvider, syncClockProvider, FieldVersions, LocalRecord,
  AssetMeta, SyncMergeFn, MergeOutcome, KeepLocalOutcome, TakeRemoteOutcome,
  WriteMergedOutcome, LocalApplyReport, ApplyOutcomeKind, RepairReason,
  // Moved out of testing.dart in revision 2.
  syncScenario, expectConverged, FakeAsync,
  // Internal.
  EntityFieldVersionsMerge, MergeRecorder, MergeOutcomeKind, EngineController,
  ChunkCodec, ChunkPacker, FieldMerge, RecordGate, StatusBuilder,
  EngineAssetService, AssetUploader, AssetDownloader, Compactor,
];

/// Names declared in support/absent_names.dart, as text (for the source-text check).
Set<String> _absentNames() =>
    declaredNames(File('test/support/absent_names.dart').readAsStringSync())
        .difference({'Absent'});

void main() {
  setUpAll(() {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('name: sync_engine'),
      reason: 'run from packages/sync_engine (flutter test / ws test)',
    );
  });

  group('source text: exports = the 4.0 table', () {
    final expected = <String, Set<String>>{
      'sync_engine.dart': {for (final l in kSyncEngineSurface.values) ...l},
      'testing.dart': kTestingSurface.toSet(),
      'firebase.dart': kFirebaseSurface.toSet(),
      'platform.dart': kPlatformSurface.toSet(),
    };

    for (final MapEntry(key: entry, value: names) in expected.entries) {
      test(entry, () {
        final surface = publicSurface(entry);
        expect(
          surface.difference(names),
          isEmpty,
          reason: 'exported by $entry but not in the 4.0 table',
        );
        expect(
          names.difference(surface),
          isEmpty,
          reason: 'in the 4.0 table but not exported by $entry',
        );
      });
    }

    test('no entry point re-exports another package (CORE included)', () {
      for (final entry in expected.keys) {
        expect(
          publicSurface(entry).where((n) => n.contains(':')),
          isEmpty,
          reason: entry,
        );
      }
    });

    test('the entry points do not overlap, and none shows an absent name', () {
      final absent = _absentNames();
      expect(absent, hasLength(_absent.length));
      final seen = <String, String>{};
      for (final entry in expected.keys) {
        final surface = publicSurface(entry);
        expect(surface.intersection(absent), isEmpty, reason: entry);
        for (final name in surface) {
          final before = seen[name];
          expect(before, isNull, reason: '$name in $before and $entry');
          seen[name] = entry;
        }
      }
    });

    test('the reader finds every kind of declaration', () {
      expect(
        declaredNames('''
final class A {}
abstract interface class B {
  void notTopLevel();
}
sealed class C {}
enum D { x }
typedef E = void Function();
mixin F {}
extension type G(int v) {}
extension H on int {}
extension on String {}
final i = 1;
const String j = '';
int k(int x) => x;
List<T> l<T>() => [];
int get m => 1;
final _private = 0;
class _Private {}
''').toList()..sort(),
        ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'i', 'j', 'k', 'l', 'm'],
      );
    });
  });

  group('compile time', () {
    test('every 4.0 name is visible through its entry point', () {
      final syncEngine = <Object>[
        // 4.1
        ServerCursor, SyncErrorCode, SyncBackendException, SignInErrorCode,
        SignInException, SyncCancelToken,
        // 4.2
        SyncDoc, SyncRecord, UpsertRecord, PurgeRecord, FieldUnits, SyncScopes,
        // 4.3
        AuthUser, AuthBackend, AuthStatus, AuthState, AuthService,
        // 4.4
        SyncPhase, SyncStatus, InitialSyncProgress, AssetTransferSummary,
        SyncIssueCode, SyncIssue, SyncNotice, FolderCycleResolved, PageRestored,
        NoteRecoveredFromPurge, InitialSyncCompleted, syncBadgeOf,
        // 4.5
        SyncBackendFactory, SyncLifecycle, SyncLogLevel, SyncLogSink, SyncUsage,
        SyncEngine, SyncEngineDebug, ConnectivitySignal, AlwaysOnlineSignal,
        ManualConnectivitySignal, AssetAvailabilityState, AssetPriority,
        AssetPrefetchPolicy, AssetAvailability, SyncAssetService,
        SyncRemoteAssetFetcher,
        // 4.6
        DevicePlatform, CompactionConfig, SyncConfig,
        // 4.7
        syncConfigProvider, authBackendProvider, syncBackendFactoryProvider,
        connectivitySignalProvider, syncLocalStoreProvider, authServiceProvider,
        authStateProvider, syncEngineProvider, syncStatusProvider,
        syncNoticesProvider,
        syncAssetServiceProvider,
        assetAvailabilityProvider,
        syncUsageProvider,
        // 4.8
        ChunkKind, ChunkWrite, RemoteChunk, ChunkPage, SyncBackend, UserProfile,
        DeviceInfo, RemoteBlobInfo, RemoteBlobStore,
        // 4.9
        SyncLocalStore, CoreSyncLocalStore, SyncMergePolicy,
      ];
      final testing = <Object>[
        FakeSyncServer,
        StoredChunk,
        FakeSyncBackend,
        FakeNetworkLink,
        FakeOp,
        FakeFault,
        FakeNetworkError,
        FakeAckLost,
        FakeErrorCode,
        FakeInterrupt,
        FakeBlobStore,
        FakeAuthBackend,
        FakeLocalStore,
        FakeLocalWrite,
        TestDevice,
        SyncTestHarness,
      ];
      final firebase = <Object>[
        WebSignInMode,
        FirebaseSyncOptions,
        FirebaseSyncBindings,
        NativeGoogleSignIn,
        FirebaseSyncBackend,
        FirestoreChunkMapper,
        FirebaseBlobStore,
        FirebaseAuthBackend,
        mapFirebaseError,
        mapSignInError,
      ];
      final platform = <Object>[ConnectivityPlusSignal];
      expect(
        syncEngine,
        hasLength(kSyncEngineSurface.values.expand((l) => l).length),
      );
      expect(testing, hasLength(kTestingSurface.length));
      expect(firebase, hasLength(kFirebaseSurface.length));
      expect(platform, hasLength(kPlatformSurface.length));
    });

    test(
      'absent names: CORE names, removed names, syncScenario / '
      'expectConverged / FakeAsync and internal classes are not exported',
      () {
        expect(_absent, isNotEmpty);
        expect([
          kAllFields,
          noRetry,
          syncScenario,
          expectConverged,
          syncClockProvider,
        ], everyElement(const Absent()));
      },
    );

    test('SyncTestHarness: checkConverged (no matcher), no async / '
        'expectConverged members (contract 7.2.20 v1.1)', () {
      void Function(Iterable<TestDevice> devices, {bool includeServer}) check(
        SyncTestHarness h,
      ) => h.checkConverged;
      Absent asyncField(SyncTestHarness h) => h.async;
      Absent expectMember(SyncTestHarness h) => h.expectConverged(null);
      expect([check, asyncField, expectMember], hasLength(3));
    });

    test('(2nd round, 07-sync 4.3) SyncTestHarness device(knownKinds:), '
        'restart, checkConverged(kinds:) and the TestDevice helpers', () {
      TestDevice Function(
        String name, {
        String uid,
        Duration clockOffset,
        bool signedIn,
        SyncConfig? config,
        Duration latency,
        Set<core.EntityKind>? knownKinds,
      })
      device(SyncTestHarness h) => h.device;
      TestDevice Function(String name, {Set<core.EntityKind>? knownKinds})
      restart(SyncTestHarness h) => h.restart;
      void Function(
        Iterable<TestDevice> devices, {
        bool includeServer,
        Set<core.EntityKind>? kinds,
      })
      check(SyncTestHarness h) => h.checkConverged;
      String Function(
        String pageId, {
        String type,
        core.AssetId? assetId,
        int seed,
      })
      addObject(TestDevice d) => d.addObject;
      void Function(String objectId, {double dx, double dy}) moveObject(
        TestDevice d,
      ) => d.moveObject;
      void Function(String objectId, int colorArgb) restyleObject(
        TestDevice d,
      ) => d.restyleObject;
      void Function(String objectId, String text) editText(TestDevice d) =>
          d.editText;
      void Function(String objectId) deleteObject(TestDevice d) =>
          d.deleteObject;
      void Function(String pageId, Map<String, Object?> json) putRawObject(
        TestDevice d,
      ) => d.putRawObject;
      void Function(String pageId, List<String> lines, {String engineId})
      putHandwriting(TestDevice d) => d.putHandwriting;
      void Function(String pageId) removeHandwriting(TestDevice d) =>
          d.removeHandwriting;
      Future<String> Function(
        String noteId, {
        core.AssetId? assetId,
        int durationMs,
      })
      addRecording(TestDevice d) => d.addRecording;
      void Function(String recordingId, String? title) renameRecording(
        TestDevice d,
      ) => d.renameRecording;
      void Function(String recordingId) deleteRecording(TestDevice d) =>
          d.deleteRecording;
      List<SyncDoc> Function(String pageId) activeObjectsOf(TestDevice d) =>
          d.activeObjectsOf;
      SyncDoc? Function(String pageId) handwritingOf(TestDevice d) =>
          d.handwritingOf;
      expect([
        device,
        restart,
        check,
        addObject,
        moveObject,
        restyleObject,
        editText,
        deleteObject,
        putRawObject,
        putHandwriting,
        removeHandwriting,
        addRecording,
        renameRecording,
        deleteRecording,
        activeObjectsOf,
        handwritingOf,
      ], hasLength(16));
    });

    test(
      '(2nd round, 07-sync 4.2) SyncEngineDebug: heldRecords, '
      'heldRecordsMarked, reappliedChunks, reappliedRecords with defaults',
      () {
        const v1 = SyncEngineDebug(
          pushCycles: 0,
          commits: 0,
          chunksSent: 0,
          recordsSent: 0,
          chunksReceived: 0,
          recordsApplied: 0,
          recordsKept: 0,
          ownChunksSkipped: 0,
          repairsWritten: 0,
          quarantined: {},
          heldChunks: 0,
        );
        final int held = v1.heldRecords;
        final bool marked = v1.heldRecordsMarked;
        final (int, int) reapplied = (v1.reappliedChunks, v1.reappliedRecords);
        expect((held, marked, reapplied), (0, false, (0, 0)));
        const v2 = SyncEngineDebug(
          pushCycles: 0,
          commits: 0,
          chunksSent: 0,
          recordsSent: 0,
          chunksReceived: 0,
          recordsApplied: 0,
          recordsKept: 0,
          ownChunksSkipped: 0,
          repairsWritten: 0,
          quarantined: {},
          heldChunks: 0,
          heldRecords: 3,
          heldRecordsMarked: true,
          reappliedChunks: 2,
          reappliedRecords: 5,
        );
        expect(
          (
            v2.heldRecords,
            v2.heldRecordsMarked,
            v2.reappliedChunks,
            v2.reappliedRecords,
          ),
          (3, true, 2, 5),
        );
      },
    );

    test('contract types: syncBadgeOf, SyncRemoteAssetFetcher, '
        'SyncMergePolicy.decide, CoreSyncLocalStore (7.2.20, 7.3.3)', () {
      const core.SyncBadge Function(SyncStatus) badge = syncBadgeOf;
      const core.RemoteAssetFetcher Function(SyncAssetService) fetcher =
          SyncRemoteAssetFetcher.new;
      const core.RemoteMergePolicy policy = SyncMergePolicy.decide;
      const SyncLocalStore Function(core.NoteStore) local =
          CoreSyncLocalStore.new;
      expect([badge, fetcher, policy, local], hasLength(4));
      // SyncBadge is CORE's: the engine's status maps onto it.
      final badgeOf = syncBadgeOf(
        const SyncStatus(
          phase: SyncPhase.disabled,
          display: core.SyncDisplayState.off,
        ),
      );
      expect(badgeOf, core.SyncBadge.off);
    });
  });
}
