// T16-v2 (integration stage 3 — 07-sync 6.7.2, 6.2.2, 6.2.5, 6.2.6): page objects between
// two real CORE stores, edited the way EDITOR edits them (a session's AddObjects /
// TransformElements / UpdateObjects / RemoveElements, DeletePages). What only real CORE
// shows: CORE C-11 (only the JSON keys whose value changed get a new field version) meeting
// SYNC's one object unit, a remote orphan object adopted when its page arrives, and remote
// objects in an open session's PageContent.objects (N-7).
//
// O1 (S23) move on A vs restyle on B: B's later snapshot wins the whole object (A's move is
// gone); edits of other objects stay. O2 (S24) delete on A vs restyle on B: deleted, with
// B's style. O3 (S25 a) page deleted on A vs a new image object on it from B, in both
// connect orders: the page comes back once, the object shows. O4 a text editing session's
// end on A (text + frame height) vs a move on B: one unit — A's text with A's frame, never
// A's text in B's frame. O5 (S30) purge on A vs B's unsent objects, recording and result:
// B's recovery copy carries them (CORE duplicateNoteForRecovery, 6.14.1).
//
// CORE milestones (6.7.2 table): O1–O4 T27 · T28, O5 T29.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:sync_engine/sync_engine.dart';

import 'support/core_sync_device.dart';

const int _red = 0xFFFF0000;
const int _blue = 0xFF0000FF;
const int _green = 0xFF00AA00;

Map<String, Object?> _styleOf(Map<String, Object?> json) =>
    json['style']! as Map<String, Object?>;

/// A note on [a] with [pages] blank pages, known to [b] too.
Future<(NoteId, List<PageId>)> _sharedNote(
  CoreScenario s,
  CoreSyncDevice a,
  CoreSyncDevice b,
  String title, {
  int pages = 1,
}) async {
  final note = (await a.store.library.createNote(
    title: title,
    pages: [for (var i = 0; i < pages; i++) PageDraft.blankA4],
  )).id;
  await s.converge([a, b], [note]);
  return (note, await a.pageIdsOf(note));
}

void main() {
  coreScenario(
    'O1 move on A vs restyle on B, both offline: B\'s later snapshot '
    'wins the object (A\'s move gone); other objects keep both edits; B\'s '
    'open session shows the remote objects',
    (s) async {
      final a = await s.device('A');
      final b = await s.device('B');
      final (note, pages) = await _sharedNote(s, a, b, 'O1');
      final page = pages.single;

      // N-7: B has the note open while A's objects arrive.
      final session = await b.store.openSession(note);
      await session.openPage(page);
      final x = await a.core.addObject(
        PageObjectFixtures.shape(pageId: page, id: a.newId(), createdAt: a.now),
      );
      final y = await a.core.addObject(
        PageObjectFixtures.textBox(
          pageId: page,
          id: a.newId(),
          createdAt: a.now,
        ),
      );
      final z = await a.core.addObject(
        PageObjectFixtures.math(pageId: page, id: a.newId(), createdAt: a.now),
      );
      await s.converge([a, b], [note]);
      expect(
        [for (final o in session.pageIfLoaded(page)!.objects) o.id],
        unorderedEquals([x.id, y.id, z.id]),
        reason: 'remote objects in the open session',
      );
      session.closePage(page);
      await session.close();
      final original = (await b.jsonOf(EntityKind.pageObject, x.id))!;

      a.goOffline();
      b.goOffline();
      await a.core.moveElements(page, [x.id], dx: 40, dy: 25); // t1
      final yOnA = (await a.core.objectOf(page, y.id))! as TextBoxObject;
      await a.core.updateObjects(page, [yOnA.copyWith(text: 'A의 글')]);
      final moved = (await a.jsonOf(EntityKind.pageObject, x.id))!;
      expect(moved['geometry'], isNot(original['geometry']));
      await nextMillisecond();
      final xOnB = (await b.core.objectOf(page, x.id))! as ShapeObject;
      await b.core.updateObjects(page, [
        xOnB.copyWith(style: xOnB.style.copyWith(strokeColorArgb: _red)),
      ]); // t2 > t1
      final zOnB = (await b.core.objectOf(page, z.id))! as MathObject;
      await b.core.updateObjects(page, [
        zOnB.copyWith(style: zOnB.style.copyWith(colorArgb: _blue)),
      ]);
      a.goOnline();
      b.goOnline();
      await s.converge([a, b], [note]);

      for (final d in [a, b]) {
        final json = (await d.jsonOf(EntityKind.pageObject, x.id))!;
        expect(_styleOf(json)['strokeColorArgb'], _red, reason: d.name);
        expect(
          json['geometry'],
          original['geometry'],
          reason:
              '${d.name}: '
              'not moved',
        );
        expect(json['frame'], original['frame'], reason: d.name);
        expect(
          (await d.jsonOf(EntityKind.pageObject, y.id))!['text'],
          'A의 글',
          reason: d.name,
        );
        expect(
          _styleOf((await d.jsonOf(EntityKind.pageObject, z.id))!)['colorArgb'],
          _blue,
          reason: d.name,
        );
        expect(
          await d.objectIdsOf(page),
          unorderedEquals([x.id, y.id, z.id]),
          reason: d.name,
        );
      }
    },
  );

  coreScenario(
    'O2 delete on A vs restyle on B (offline): deleted on both, with '
    'B\'s style',
    (s) async {
      final a = await s.device('A');
      final b = await s.device('B');
      final (note, pages) = await _sharedNote(s, a, b, 'O2');
      final page = pages.single;
      final x = await a.core.addObject(
        PageObjectFixtures.shape(pageId: page, id: a.newId(), createdAt: a.now),
      );
      await s.converge([a, b], [note]);

      b.goOffline();
      await a.core.removeElements(page, [x.id]);
      await s.settle([a]);
      await nextMillisecond();
      final xOnB = (await b.core.objectOf(page, x.id))! as ShapeObject;
      await b.core.updateObjects(page, [
        xOnB.copyWith(style: xOnB.style.copyWith(strokeColorArgb: _red)),
      ]);
      b.goOnline();

      final ref = EntityRef(EntityKind.pageObject, x.id);
      await s.converge([a, b], [note], extra: [ref]);
      for (final d in [a, b]) {
        final json = (await d.jsonOf(EntityKind.pageObject, x.id))!;
        expect(json['deletedAt'], isNotNull, reason: d.name);
        expect(_styleOf(json)['strokeColorArgb'], _red, reason: d.name);
        expect(await d.objectIdsOf(page), isEmpty, reason: d.name);
      }
    },
  );

  for (final bFirst in [true, false]) {
    coreScenario(
      'O3 (${bFirst ? 'a1' : 'a2'}) page deleted on A vs a new image '
      'object on it from B, ${bFirst ? 'B' : 'A'} connects first: the page '
      'comes back once, the object shows',
      (s) async {
        final a = await s.device('A');
        final b = await s.device('B');
        final restored = listenNotices<PageRestored>([a, b]);
        final (note, pages) = await _sharedNote(s, a, b, 'O3', pages: 2);
        final page = pages.last;

        a.goOffline();
        b.goOffline();
        await a.core.deletePages(note, [page]);
        final asset = await b.store.assets.put(
          Uint8List.fromList(utf8.encode('png of O3')),
          type: AssetType.image,
          mimeType: 'image/png',
        );
        final image = await b.core.addObject(
          PageObjectFixtures.image(
            pageId: page,
            assetId: asset.id,
            id: b.newId(),
            createdAt: b.now,
          ),
        );
        await nextMillisecond();
        final (first, second) = bFirst ? (b, a) : (a, b);
        first.goOnline();
        await s.settle([first]);
        second.goOnline();

        await s.converge(
          [a, b],
          [note],
          extra: [EntityRef(EntityKind.page, page)],
        );
        for (final d in [a, b]) {
          expect(
            (await d.store.content.getPage(page))!.isDeleted,
            isFalse,
            reason: d.name,
          );
          expect(await d.pageIdsOf(note), contains(page), reason: d.name);
          expect(await d.objectIdsOf(page), [image.id], reason: d.name);
        }
        expect(restored.seen.map((n) => n.pageId), [page]);
        await restored.cancel();
      },
    );
  }

  coreScenario(
    'O4 a text editing session\'s end on A (text + height) vs a move '
    'on B, both offline: one unit — A\'s text in A\'s frame',
    (s) async {
      final a = await s.device('A');
      final b = await s.device('B');
      final (note, pages) = await _sharedNote(s, a, b, 'O4');
      final page = pages.single;
      final t = await a.core.addObject(
        PageObjectFixtures.textBox(
          pageId: page,
          id: a.newId(),
          createdAt: a.now,
        ),
      );
      await s.converge([a, b], [note]);
      final original = (await a.jsonOf(EntityKind.pageObject, t.id))!;

      a.goOffline();
      b.goOffline();
      await b.core.moveElements(page, [t.id], dx: 30, dy: 50); // t1
      final movedOnB = (await b.jsonOf(EntityKind.pageObject, t.id))!;
      expect(movedOnB['frame'], isNot(original['frame']));
      await nextMillisecond();
      final onA = (await a.core.objectOf(page, t.id))! as TextBoxObject;
      final r = onA.frame.rect;
      await a.core.updateObjects(page, [
        onA.copyWith(
          text: '첫 줄\n둘째 줄',
          frame: ElementFrame(
            PageRect(r.left, r.top, r.right, r.bottom + 40),
            rotation: onA.frame.rotation,
          ),
        ),
      ]); // t2 > t1: the session's one UpdateObjects
      final edited = (await a.jsonOf(EntityKind.pageObject, t.id))!;
      a.goOnline();
      b.goOnline();
      await s.converge([a, b], [note]);

      for (final d in [a, b]) {
        final json = (await d.jsonOf(EntityKind.pageObject, t.id))!;
        expect(json['text'], '첫 줄\n둘째 줄', reason: d.name);
        expect(json['frame'], edited['frame'], reason: '${d.name}: A\'s frame');
        expect(json['frame'], isNot(movedOnB['frame']), reason: d.name);
      }
    },
  );

  coreScenario(
    'O5 purge on A vs unsent objects, recording and result on B: B\'s '
    'recovery copy carries all of them',
    (s) async {
      final a = await s.device('A');
      final b = await s.device('B');
      final recovered = listenNotices<NoteRecoveredFromPurge>([b]);
      final (note, pages) = await _sharedNote(s, a, b, 'O5');
      final page = pages.single;
      final math = await a.core.addObject(
        PageObjectFixtures.math(pageId: page, id: a.newId(), createdAt: a.now),
      );
      await a.core.addStroke(page, seed: 1);
      await s.converge([a, b], [note]);

      b.goOffline();
      await a.core.trashAndPurge(note);
      await s.settle([a]);
      final shape = await b.core.addObject(
        PageObjectFixtures.shape(pageId: page, id: b.newId(), createdAt: b.now),
      );
      final text = await b.core.addObject(
        PageObjectFixtures.textBox(
          pageId: page,
          id: b.newId(),
          createdAt: b.now,
        ),
      );
      final mathOnB = (await b.core.objectOf(page, math.id))! as MathObject;
      await b.core.updateObjects(page, [
        mathOnB.copyWith(style: mathOnB.style.copyWith(colorArgb: _green)),
      ]);
      final recording = await b.core.createRecording(note, durationMs: 4000);
      await b.store.recordings.renameRecording(recording.id, '1강');
      final linked = await b.core.addStroke(
        page,
        seed: 2,
        recordingId: recording.id,
        recordingOffsetMs: 1500,
      );
      await b.core.putHandwriting(page, ['극한', '연속']);
      await nextMillisecond();
      b.goOnline();

      await s.until('B\'s recovery copy', () => recovered.seen.isNotEmpty);
      final copy = recovered.seen.single.copyNoteId;
      expect(recovered.seen.single.purgedNoteId, note);
      await s.converge([a, b], [copy]);
      expect(recovered.seen, hasLength(1));
      await recovered.cancel();

      final originals = {
        EntityRef(EntityKind.note, note),
        EntityRef(EntityKind.page, page),
        EntityRef(EntityKind.handwriting, HandwritingText.idFor(page)),
        EntityRef(EntityKind.recording, recording.id),
        EntityRef(EntityKind.stroke, linked.id),
        for (final o in [math, shape, text])
          EntityRef(EntityKind.pageObject, o.id),
      };
      for (final d in [a, b]) {
        for (final ref in originals) {
          expect(
            await d.read(ref.kind, ref.id),
            isNull,
            reason:
                '${d.name}: '
                '$ref purged',
          );
        }
        expect(
          (await d.store.library.getNote(copy))!.title,
          'O5 (동기화 복구)',
          reason: d.name,
        );
        final copyPage = (await d.pageIdsOf(copy)).single;
        // Objects: new ids, B's unsent edits inside.
        final objects = await d.core.objectsOf(copyPage);
        expect(
          {for (final o in objects) o.toJson()['type']},
          {'shape', 'text', 'math'},
          reason: d.name,
        );
        expect(objects, hasLength(3), reason: d.name);
        expect(
          {for (final o in objects) o.id}
              .intersection({for (final r in originals) r.id}),
          isEmpty,
          reason: d.name,
        );
        final copiedMath = objects.whereType<MathObject>().single;
        expect(copiedMath.style.colorArgb, _green, reason: d.name);
        // The recording: a new id, the same asset and title.
        final recordings = await d.store.recordings.recordingsOf(copy);
        expect(recordings, hasLength(1), reason: d.name);
        final copied = recordings.single;
        expect(copied.id, isNot(recording.id), reason: d.name);
        expect(copied.assetId, recording.assetId, reason: d.name);
        expect(copied.title, '1강', reason: d.name);
        expect(copied.durationMs, 4000, reason: d.name);
        // The strokes: the linked one points at the new recording.
        final strokes = (await d.store.content.loadPage(copyPage)).strokes;
        expect(strokes, hasLength(2), reason: d.name);
        expect(
          [for (final st in strokes) st.recordingId],
          unorderedEquals([null, copied.id]),
          reason: d.name,
        );
        // The handwriting result of the copied page, over the copied strokes.
        final hw = (await d.store.handwriting.forPage(copyPage))!;
        expect(hw.id, HandwritingText.idFor(copyPage), reason: d.name);
        expect(hw.noteId, copy, reason: d.name);
        expect(
          [for (final l in hw.lines) l.text],
          ['극한', '연속'],
          reason: d.name,
        );
        final strokeIds = {for (final st in strokes) st.id};
        for (final l in hw.lines) {
          expect(strokeIds, containsAll(l.strokeIds), reason: d.name);
        }
      }
    },
  );
}
