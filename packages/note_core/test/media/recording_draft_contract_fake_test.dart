// The recording draft contract (m5-7/02-core 6.7.2) on createFakeNoteStore(): the hooks reach
// the fake's draft rows and memory blob map. The real store from CORE T31.
import 'dart:convert';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/fake/fake_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../shared/recording_draft_contract.dart';

final class _FakeHooks implements DraftStoreHooks {
  _FakeHooks(this.s);
  final FakeNoteStore s;

  @override
  List<String> get writeOrder => s.recordingDrafts.blobWrites;

  @override
  Future<void> loseRow(String draftId) async => s.draftRows.remove(draftId);

  @override
  Future<void> putOrphanChunk(String draftId) async =>
      s.draftBlobs['rd/$draftId/000000'] = Uint8List(4);

  @override
  Future<bool> hasBlobs(String draftId) async =>
      s.draftBlobs.keys.any((k) => k.startsWith('rd/$draftId/'));

  @override
  Future<void> discardBlobsOnly(String draftId) async =>
      s.draftBlobs.removeWhere((k, _) => k.startsWith('rd/$draftId/'));

  @override
  Future<NoteStore>? reopen() => null;
}

void main() {
  defineRecordingDraftContract((clock) {
    final store = createFakeNoteStore(clock: clock) as FakeNoteStore;
    return (store, _FakeHooks(store));
  });

  // The fake cannot be reopened, so the shared body cannot see its first-use cleanup: blobs
  // left before the first draft call stand in for what a closed tab left behind.
  test(
    'first use: only prefixes with neither a row nor a meta are removed',
    () async {
      final s = createFakeNoteStore() as FakeNoteStore;
      addTearDown(s.close);
      s.draftBlobs['rd/orphan/000000'] = Uint8List(4);
      s.draftBlobs['rd/orphan/000001'] = Uint8List(4);
      s.draftBlobs['rd/meta-only/meta'] = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'recordingId': 'rec-m',
            'noteId': 'n1',
            'mimeType': 'audio/webm',
            'startedAt': 5,
          }),
        ),
      );
      s.draftBlobs['rd/meta-only/000000'] = Uint8List(3);
      s.draftRows['row-only'] = const RecordingDraft(
        draftId: 'row-only',
        recordingId: 'rec-r',
        noteId: 'n1',
        mimeType: 'audio/mp4',
        startedAt: 9,
        chunkCount: 0,
        bytes: 0,
        activeMs: 2000,
        updatedAt: 9,
      );
      final listed = await s.recordingDrafts.listDrafts();
      expect(listed.map((d) => d.draftId), ['meta-only', 'row-only']);
      expect(listed.first.bytes, 3);
      expect(
        s.draftBlobs.keys.where((k) => k.startsWith('rd/orphan/')),
        isEmpty,
      );
      expect(s.draftBlobs.containsKey('rd/meta-only/meta'), isTrue);
    },
  );
}
