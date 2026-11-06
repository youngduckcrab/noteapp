// CORE T31 — the recording draft contract (m5-7/02-core 6.7.2, the T23b shared body) on the
// SQLite store: a file database and an in-memory IndexedDB blob factory shared with the
// reopened store, so a reopen sees the same rows and chunks and runs the first-use orphan
// cleanup. The hooks reach the store's recording_drafts table and blob store.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:test/test.dart';

import '../shared/recording_draft_contract.dart';
import 'draft_store_support.dart';

final class RealDraftHooks implements DraftStoreHooks {
  RealDraftHooks(this.store, this.path, this.blobFactory, this.clock);
  final DriftNoteStore store;
  final String path;
  final IdbFactory blobFactory;
  final Clock clock;

  @override
  List<String> get writeOrder => store.recordingDrafts.debugWriteOrder;

  @override
  Future<void> loseRow(String draftId) => (store.db.delete(
    store.db.recordingDrafts,
  )..where((t) => t.draftId.equals(draftId))).go();

  @override
  Future<void> putOrphanChunk(String draftId) =>
      store.recordingDrafts.blobs.put('rd/$draftId/000000', Uint8List(4));

  @override
  Future<bool> hasBlobs(String draftId) async =>
      (await store.recordingDrafts.blobs.keys('rd/$draftId/')).isNotEmpty;

  @override
  Future<void> discardBlobsOnly(String draftId) =>
      store.recordingDrafts.blobs.deletePrefix('rd/$draftId/');

  @override
  Future<NoteStore>? reopen() =>
      openDraftStore(path, blobFactory, clock: clock);
}

void main() {
  defineRecordingDraftContract((clock) async {
    final dir = await Directory.systemTemp.createTemp('core_drafts_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/notes.sqlite';
    final blobs = newIdbFactoryMemory();
    final store = await openDraftStore(path, blobs, clock: clock);
    return (store, RealDraftHooks(store, path, blobs, clock));
  });
}
