// package:note_core/testing.dart — web-safe, test/ only
/// Test helpers of note_core (contract 00-overview 7.6 'B2 테스트·개발 도우미', CORE 4.10):
/// the shared in-memory fake store, stroke fixtures and a test merge policy.
/// (v2.0) PageObjectFixtures, FakeAudioRecorder, FakeAudioPlayback — 2nd-round contract 7.6
/// '기반 단계 시험 도우미' (m5-7/02-core 4.9, 6.8.3, 6.8.4).
/// Import from `test/` only (7.1 rule 2).
library;

import 'package:clock/clock.dart';

import 'src/common/hlc.dart';
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

export 'src/fake/fake_audio.dart' show FakeAudioPlayback, FakeAudioRecorder;
export 'src/fake/fake_write_queue.dart' show FakeNoteStoreFaults;
export 'src/fake/page_object_fixtures.dart' show PageObjectFixtures;

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
/// (v2.0, 2nd-round contract 7.6) v1.4 signature unchanged. v2.0 behaviour: page objects
/// (AddObjects / UpdateObjects / RemoveElements / TransformElements / ClearPage.includeObjects /
/// PageDraft.objects), recordings (RecordingRepository), recording drafts (memory), handwriting
/// (HandwritingRepository, (v2.1) incl. update / notesWithStalePages) and a memory SearchIndex
/// that applies (v2.1, CP-14) the SAME judgement, candidate order and ranking code as the real
/// FTS index — results AND order equal the real store for the 7.7 V10 query set.
/// openTestNoteStore (testing_vm.dart) is the real CORE v2.
/// CORE (m5-7/02-core 6.17): the fake indexes text boxes, math and handwriting itself; pdf
/// comes through store.search (SearchIndexWriter). Page objects, recordings, handwriting and
/// the search index are in exportBackupJson / copyItems / purge like the real store. Recording
/// drafts keep the real blob key layout in memory (`rd/<draftId>/<n>`, `rd/<draftId>/meta`).
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

/// (v2.17-md, m5-7/08-markdown 12.1) Sync situations of an MD 문서 in the fake store
/// (createFakeNoteStore only; any other store → ArgumentError).
abstract final class FakeMarkdownHooks {
  static FakeNoteStore _fake(NoteStore store) => store is FakeNoteStore
      ? store
      : throw ArgumentError.value(store, 'store', 'not createFakeNoteStore()');

  /// The body of [noteId] removed — the note arrived before its body
  /// (`MarkdownDoc.bodyPresent` false, read-only).
  static Future<void> removeBody(NoteStore store, NoteId noteId) =>
      _fake(store).markdown.debugRemoveBody(noteId);

  /// [text] stored as if another device's write had arrived (origin remote, a newer
  /// version of another node, no conflict copy). Returns the new text version.
  static Future<Hlc> remoteText(NoteStore store, NoteId noteId, String text) =>
      _fake(store).markdown.debugRemoteText(noteId, text);
}
