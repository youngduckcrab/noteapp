// S30 (07-sync 6.7.1, 6.2.5, CORE 6.14.1): A purges note N while B, offline, adds two page
// objects, restyles a third, makes a recording, links a stroke to it and writes the page's
// handwriting result. B connects: its PurgeGuard makes the recovery copy N'
// (NoteRecoveredFromPurge) with the objects (new ids), the recording (new id, same asset
// and title), the stroke's recordingId moved to the new recording and the result as
// hw_<page of N'>; A receives N'. N is gone on both sides.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

const String _copyTitle = 'S30 (동기화 복구)';

List<T> rowsOf<T extends SyncEntity>(TestDevice d) => [
  for (final row in d.store.rows.values)
    if (row.entity case final T e) e,
];

List<Note> notesTitled(TestDevice d, String title) => [
  for (final n in rowsOf<Note>(d))
    if (!n.isDeleted && n.title == title) n,
];

void main() {
  syncScenario('S30 purge on A vs unsent objects, recording and handwriting on '
      'B: recovery copy with all of them', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final recovered = <NoteRecoveredFromPurge>[];
    final sub = b.engine.notices.listen((n) {
      if (n is NoteRecoveredFromPurge) recovered.add(n);
    });
    final note = a.createNote('S30');
    final page = a.pageIdsOf(note).single;
    final math = a.addObject(page, type: 'math');
    a.addStroke(page, seed: 1);
    h.settle();

    b.goOffline();
    a.purgeNote(note);
    h.settle();
    const green = 0xFF00AA00;
    final shape = b.addObject(page, seed: 3);
    final text = b.addObject(page, type: 'text', seed: 4);
    b.restyleObject(math, green);
    final recording = h.run(b.addRecording(note, durationMs: 4000));
    b.renameRecording(recording, '1강');
    final linked = b.addStroke(page, seed: 2);
    final stroke = b.doc(EntityKind.stroke, linked)!.json;
    b.store.localWrite([
      FakeLocalWrite(
        EntityKind.stroke,
        {...stroke, 'recordingId': recording, 'recordingOffsetMs': 1500},
        changedFields: const {'recordingId', 'recordingOffsetMs'},
      ),
    ]);
    b.putHandwriting(page, ['극한', '연속']);
    final asset = b.doc(EntityKind.recording, recording)!.json['assetId'];
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();

    expect(recovered, hasLength(1));
    expect(recovered.single.purgedNoteId, note);
    final copyId = notesTitled(b, _copyTitle).single.id;
    expect(recovered.single.copyNoteId, copyId);
    final originals = {shape, text, math, recording, linked, page};
    for (final d in [a, b]) {
      expect(entityOn<Note>(d, EntityKind.note, note), isNull, reason: d.name);
      for (final id in originals) {
        expect(
          d.store.rows.keys.where((r) => r.id == id),
          isEmpty,
          reason: '${d.name}: $id purged',
        );
      }
      expect(
        d.doc(EntityKind.handwriting, HandwritingText.idFor(page)),
        isNull,
        reason: d.name,
      );
      expect(notesTitled(d, _copyTitle).single.id, copyId, reason: d.name);
      final copyPage = d.pageIdsOf(copyId).single;
      // Objects: new ids, B's unsent edits inside.
      final objects = d.activeObjectsOf(copyPage);
      expect(
        {for (final o in objects) o.json['type']},
        {'shape', 'text', 'math'},
        reason: d.name,
      );
      expect(objects, hasLength(3), reason: d.name);
      expect(
        {for (final o in objects) o.json['id']}.intersection(originals),
        isEmpty,
        reason: d.name,
      );
      final copiedMath = objects.singleWhere((o) => o.json['type'] == 'math');
      expect(
        (copiedMath.json['style']! as Map)['colorArgb'],
        green,
        reason: d.name,
      );
      // The recording: a new id with the same asset and title.
      final recordings = [
        for (final r in rowsOf<Recording>(d))
          if (r.noteId == copyId && !r.isDeleted) r,
      ];
      expect(recordings, hasLength(1), reason: d.name);
      final copied = recordings.single;
      expect(copied.id, isNot(recording), reason: d.name);
      final copiedJson = d.doc(EntityKind.recording, copied.id)!.json;
      expect(copiedJson['assetId'], asset, reason: d.name);
      expect(copiedJson['title'], '1강', reason: d.name);
      expect(copiedJson['durationMs'], 4000, reason: d.name);
      // The strokes: the linked one points at the new recording.
      final strokes = d.activeStrokesOf(copyPage);
      expect(strokes, hasLength(2), reason: d.name);
      expect(
        [for (final s in strokes) s.json['recordingId']],
        unorderedEquals([null, copied.id]),
        reason: d.name,
      );
      // The handwriting result of the copied page.
      final hw = d.handwritingOf(copyPage)!;
      expect(hw.json['id'], HandwritingText.idFor(copyPage), reason: d.name);
      expect(hw.json['noteId'], copyId, reason: d.name);
      expect(
        [for (final l in hw.json['lines']! as List) (l as Map)['text']],
        ['극한', '연속'],
        reason: d.name,
      );
      final strokeIds = {for (final s in strokes) s.json['id']};
      for (final l in hw.json['lines']! as List) {
        for (final id in (l as Map)['strokeIds']! as List) {
          expect(strokeIds, contains(id), reason: '${d.name}: mapped ids');
        }
      }
    }
    h.checkConverged([a, b]);
    unawaited(sub.cancel());
  });
}
