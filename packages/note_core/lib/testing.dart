// package:note_core/testing.dart — web-safe, test/ only
/// Test helpers of note_core (contract 00-overview 7.6 'B2 테스트·개발 도우미', CORE 4.10):
/// the shared in-memory fake store, stroke fixtures and a test merge policy.
/// Import from `test/` only (7.1 rule 2).
library;

import 'package:clock/clock.dart';

import 'src/common/ids.dart';
import 'src/dev/synthetic.dart';
import 'src/fake/fake_note_store.dart';
import 'src/fake/fake_write_queue.dart';
import 'src/model/pen_style.dart';
import 'src/model/stroke.dart';
import 'src/repo/note_store.dart';
import 'src/repo/status.dart';
import 'src/sync/field_versions.dart';
import 'src/sync/merge.dart';

export 'src/fake/fake_write_queue.dart' show FakeNoteStoreFaults;

/// In-memory NoteStore without SQLite — the shared fake of 7.4.8 (contract 7.6, CORE 6.19).
/// Behaviour (contract 7.6): library (C-1..C-10), trash, presets (ensureDefaults), settings,
/// sessions N-1..N-6 (N-7 does not apply — the fake has no remote path), thumbnail cache,
/// assets (+ bytesArrived), ids (default SequentialIdGenerator), clock, storageInfo (default
/// nativeFile = no banner; pass webInMemory → storageWarningOf == notDurable),
/// persistenceStatusStream (current value once right after listen, 7.2.12).
/// SyncStore: ownerId and deviceNodeId return values, pendingChanges() returns an empty list,
/// watchPendingCount() emits 0, EVERY other member throws UnsupportedError (SYNC contract
/// tests use openTestNoteStore). exportBackupJson: UnimplementedError in B2; the same format
/// as the real store from CORE T19.
NoteStore createFakeNoteStore({
  Clock? clock,
  IdGenerator? ids,
  OwnerId ownerId = kLocalOwnerId,
  bool seedDefaultPenPresets = true,
  StorageInfo storageInfo = const StorageInfo(
    backend: StorageBackend.nativeFile,
  ),
  FakeNoteStoreFaults? faults,
}) => FakeNoteStore(
  clock: clock ?? const Clock(),
  ids: ids ?? SequentialIdGenerator(),
  ownerId: ownerId,
  seedDefaultPenPresets: seedDefaultPenPresets,
  storageInfo: storageInfo,
  faults: faults ?? FakeNoteStoreFaults(),
);

// package:note_core/testing.dart (continued) — CORE 4.10
abstract final class StrokeFixtures {
  /// Deterministic handwriting-like stroke (6.2.4 generator, widthQ channel).
  static Stroke synthetic({
    required PageId pageId,
    required IdGenerator ids,
    int seed = 0,
    int pointCount = 100,
    double hz = 120,
    PenTool tool = PenTool.ballpoint,
    EpochMillis createdAt = 0,
    bool hasTilt = true,
  }) => syntheticStroke(
    pageId: pageId,
    ids: ids,
    seed: seed,
    pointCount: pointCount,
    hz: hz,
    tool: tool,
    createdAt: createdAt,
    hasTilt: hasTilt,
  );

  /// [count] strokes with seeds seed..seed+count-1 and createdAt 0..count-1 (drawing order).
  static List<Stroke> manySynthetic({
    required PageId pageId,
    required IdGenerator ids,
    required int count,
    int seed = 0,
  }) => [
    for (var i = 0; i < count; i++)
      synthetic(pageId: pageId, ids: ids, seed: seed + i, createdAt: i),
  ];
}

/// Entity-level "newer max version wins" policy for tests only (SYNC ships the real one).
MergeDecision newerVersionWinsPolicy(
  VersionedEntity? local,
  VersionedEntity remote,
  Set<String>? pendingLocalFields,
) {
  if (local == null) return const TakeRemote();
  return remote.versions.max > local.versions.max
      ? const TakeRemote()
      : const KeepLocal();
}
