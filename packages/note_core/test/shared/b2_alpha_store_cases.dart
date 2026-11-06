// Shared body of the B2-α store state (m5-7/02-core 8.1 'B2 상태', column 'B2-α 끝'):
// the 2nd-round store members read empty and their writes throw
// UnimplementedError('CORE <task>: …'); the stroke part of RemoveElements /
// ClearPage(includeObjects:) works as in v1.4. Runs on the real store
// (test/testing/open_test_store_test.dart, task T33a — 8.1 'B2 상태', column
// 'B2 전체(β) 끝'; recordings since T30, drafts since T31, handwriting since T32, the v1 copy
// since T24, objects since T27). The fake store
// left this state with CORE T23b; its v2 behaviour is in test/testing/fake_store_v2_test.dart
// and the shared contracts (test/shared/*_contract.dart). Web-safe (no dart:io).
import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

/// UnimplementedError whose message names CORE [task] (e.g. 'CORE T30: …').
Matcher throwsPending(String task) => throwsA(
  isA<UnimplementedError>().having(
    (e) => e.message,
    'message',
    startsWith('CORE $task: '),
  ),
);

/// The CORE tasks the store's 2nd-round writes wait for. [v1Copy]: null when the v1 copy API works (the real store since CORE T24 — an in-memory
/// store has no copy). [recordings]: null when the repository works (the real store since
/// CORE T30 — test/shared/recording_contract.dart). [drafts]: null when the draft store works
/// (the real store since CORE T31 — test/shared/recording_draft_contract.dart). [handwriting]:
/// null when the repository works (the real store since CORE T32 —
/// test/shared/handwriting_contract.dart).
typedef B2AlphaTasks = ({
  String? recordings,
  String? drafts,
  String? handwriting,
  String search,
  String? v1Copy,
});

void defineB2AlphaStoreTests(
  FutureOr<NoteStore> Function() open, {
  required B2AlphaTasks tasks,
  required bool hasV1CopyApi,
}) {
  late NoteStore store;
  late Note note;
  late NoteSession session;
  late PageId pageId;

  setUp(() async {
    store = await open();
    note = await store.library.createNote(
      title: 'b2-alpha',
      pages: const [PageDraft.blankA4, PageDraft.blankA4],
    );
    session = await store.openSession(note.id);
    pageId = session.pages.first.id;
    await session.openPage(pageId);
    await session
        .execute(
          AddStrokes(
            pageId: pageId,
            strokes: [
              StrokeFixtures.synthetic(
                pageId: pageId,
                ids: store.ids,
                createdAt: 1000,
              ),
              StrokeFixtures.synthetic(
                pageId: pageId,
                ids: store.ids,
                seed: 1,
                tool: PenTool.highlighter,
                createdAt: 1001,
              ),
            ],
          ),
        )
        .persisted;
  });

  tearDown(() async {
    if (!session.isClosed) await session.close();
    await store.close();
  });

  if (tasks.recordings case final recordingsTask?) {
    group('recordings', () {
      test('reads are empty', () async {
        final recordings = store.recordings;
        expect(await recordings.watchRecordings(note.id).first, isEmpty);
        expect(await recordings.recordingsOf(note.id), isEmpty);
        expect(await recordings.getRecording('r1'), isNull);
        expect(await recordings.audioBytesOf(note.id), 0);
      });

      test('writes throw UnimplementedError(CORE $recordingsTask)', () {
        final recordings = store.recordings;
        expect(
          recordings.createRecording(
            id: 'r1',
            noteId: note.id,
            assetId: 'a' * 64,
            durationMs: 1000,
            startedAt: 0,
          ),
          throwsPending(recordingsTask),
        );
        expect(
          recordings.renameRecording('r1', 'x'),
          throwsPending(recordingsTask),
        );
        expect(recordings.deleteRecording('r1'), throwsPending(recordingsTask));
      });
    });
  }

  if (tasks.drafts case final draftsTask?) {
    group('recording drafts', () {
      test('reads are empty; readAll knows no draft', () async {
        final drafts = store.recordingDrafts;
        expect(await drafts.listDrafts(), isEmpty);
        expect(drafts.readAll('d1'), throwsStateError);
      });

      test('writes throw UnimplementedError(CORE $draftsTask)', () {
        final drafts = store.recordingDrafts;
        expect(
          drafts.begin(
            recordingId: 'r1',
            noteId: note.id,
            mimeType: 'audio/mp4',
            startedAt: 0,
          ),
          throwsPending(draftsTask),
        );
        expect(
          drafts.append('d1', Uint8List(16), activeMs: 1000),
          throwsPending(draftsTask),
        );
        expect(drafts.discard('d1'), throwsPending(draftsTask));
      });
    });
  }

  if (tasks.handwriting case final handwritingTask?) {
    group('handwriting', () {
      test('reads are empty, also for a page with input strokes', () async {
        final hw = store.handwriting;
        expect(await hw.forPage(pageId), isNull);
        expect(await hw.watchPage(pageId).first, isNull);
        expect(await hw.stalePages(note.id), isEmpty);
        expect(await hw.notesWithStalePages(), isEmpty);
      });

      test('writes throw UnimplementedError(CORE $handwritingTask)', () {
        final hw = store.handwriting;
        final value = HandwritingText(
          noteId: note.id,
          pageId: pageId,
          engineId: 'fake',
          sourceRev: '0000000000000000',
          lines: const [],
          createdAt: 1,
        );
        expect(hw.put(value), throwsPending(handwritingTask));
        expect(hw.update(pageId, (_) => value), throwsPending(handwritingTask));
        expect(hw.removeForPage(pageId), throwsPending(handwritingTask));
      });
    });
  }

  group('search', () {
    test('reads are empty; status is the default', () async {
      final search = store.search;
      expect(await search.searchPages('b2'), isEmpty);
      expect(await search.searchPages('b', withinNote: note.id), isEmpty);
      expect(await search.sourceRevOf(SearchSource.pdf, 'a#0'), isNull);
      expect(await search.sourceRevs(SearchSource.pdf), isEmpty);
      expect(await search.status.first, const SearchIndexStatus());
      final result = await store.library.searchLibrary('b2');
      expect(result.notes.map((n) => n.id), [note.id]);
      expect(result.pages, isEmpty);
      expect(result.pagesTruncated, isFalse);
    });

    test('writes throw UnimplementedError(CORE ${tasks.search})', () {
      final search = store.search;
      expect(
        search.replaceUnits(SearchSource.pdf, 'a#0', const [
          SearchUnitDraft(body: 'x'),
        ], sourceRev: 'a:1'),
        throwsPending(tasks.search),
      );
      expect(
        search.removeOwner(SearchSource.pdf, 'a#0'),
        throwsPending(tasks.search),
      );
      expect(search.rebuild(), throwsPending(tasks.search));
    });
  });

  // Object commands work on both stores since CORE T27 (test/shared/
  // object_session_contract.dart); the stroke part of the 2nd-round commands stays v1.4.
  group('the stroke part of the 2nd-round commands (v1.4)', () {
    test('RemoveElements removes strokes as RemoveStrokes', () async {
      final ids = session.pageIfLoaded(pageId)!.strokes.map((s) => s.id);
      final receipt = session.execute(
        RemoveElements(
          pageId: pageId,
          elementIds: [ids.first, ids.first, 'unknown'],
        ),
      );
      await receipt.persisted;
      final content = session.pageIfLoaded(pageId)!;
      expect(content.strokes.map((s) => s.id), [ids.last]);
      expect(content.elementById(ids.last), isA<Stroke>());
      expect(session.history.undoLabel, 'remove-elements');
      await session.undo();
      expect(session.pageIfLoaded(pageId)!.strokeCount, 2);
    });

    test('ClearPage(includeObjects: true) clears strokes by filter', () async {
      await session
          .execute(
            ClearPage(
              pageId: pageId,
              filter: StrokeFilter.highlighterOnly,
              includeObjects: true,
            ),
          )
          .persisted;
      final content = session.pageIfLoaded(pageId)!;
      expect(content.strokeCount, 1);
      expect(content.strokes.single.style.tool, PenTool.ballpoint);
      expect(content.objectCount, 0);
    });

    test('PageDraft.copyOf carries the (empty) objects', () {
      final draft = PageDraft.copyOf(session.pageIfLoaded(pageId)!);
      expect(draft.strokes, hasLength(2));
      expect(draft.objects, isEmpty);
    });
  });

  test('EntityJson of the new kinds decodes (CORE T20a)', () {
    expect(
      () => EntityJson.decode(EntityKind.pageObject, const {}),
      throwsFormatException,
    );
    expect(
      () => EntityJson.decode(EntityKind.handwriting, const {}),
      throwsFormatException,
    );
  });

  test('v1 database copy API (dev_tools.dart, C22-01)', () async {
    expect(await v1DatabaseCopyInfo(store), isNull);
    final pending = tasks.v1Copy;
    if (hasV1CopyApi && pending != null) {
      expect(readV1DatabaseCopy(store).toList(), throwsPending(pending));
      expect(deleteV1DatabaseCopy(store), throwsPending(pending));
    } else {
      // A store without one (the fake store, an in-memory real store): nothing to read,
      // nothing to delete.
      expect(readV1DatabaseCopy(store).toList(), throwsStateError);
      await deleteV1DatabaseCopy(store);
    }
  });
}
