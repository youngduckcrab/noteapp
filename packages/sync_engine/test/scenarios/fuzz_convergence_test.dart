// Random convergence (9.1.2): seeds 1..20, three devices, 500 random operations (strokes:
// add, erase, move, recolour; pages: insert, delete, move; notes: rename, move, trash,
// restore, create; folders: move, create; settings) with random offline periods and
// commit faults. At the end everyone is online → settle → converged, nothing lost, no
// folder loop. (2nd round, 07-sync 6.7.1 'random convergence v2') Also page objects (add,
// move, restyle, edit text, delete), handwriting results (put) and recordings (add,
// rename); no object is lost either.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

const int kSeeds = 20;
const int kOperations = 500;

List<T> rowsOf<T extends SyncEntity>(TestDevice d) => [
  for (final row in d.store.rows.values)
    if (row.entity case final T e) e,
];

T? pick<T>(Random random, List<T> list) =>
    list.isEmpty ? null : list[random.nextInt(list.length)];

final class Fuzz {
  Fuzz(this.h, this.random)
    : devices = [h.device('A'), h.device('B'), h.device('C')];

  final SyncTestHarness h;
  final Random random;
  final List<TestDevice> devices;
  final List<String> created = [];
  final Set<String> erased = {};

  /// (2nd round) Page objects added and those deleted.
  final List<String> createdObjects = [];
  final Set<String> deletedObjects = {};

  void run() {
    final a = devices.first;
    for (var i = 0; i < 3; i++) {
      a.createFolder('F$i');
    }
    for (var i = 0; i < 2; i++) {
      a.createNote('N$i', pages: 2);
    }
    h.settle();
    for (var op = 0; op < kOperations; op++) {
      final d = devices[random.nextInt(devices.length)];
      if (random.nextInt(25) == 0) {
        if (d.link.online) {
          d.goOffline();
        } else {
          d.goOnline();
        }
      }
      if (random.nextInt(60) == 0) {
        d.link.failNext(
          random.nextBool() ? const FakeNetworkError() : const FakeAckLost(),
          op: FakeOp.commit,
        );
      }
      operate(d);
      h.elapse(Duration(milliseconds: random.nextInt(400)));
    }
    for (final d in devices) {
      d.goOnline();
    }
    h.settle();
    // Injected faults can leave an engine in the offline phase (two connection failures in
    // a row) although its link is up: settle counts that as idle, the offline probe
    // reconnects within 30 s (6.8.2).
    for (var i = 0; i < 10 && !devices.every(_synced); i++) {
      h.elapse(const Duration(seconds: 31));
      h.settle();
    }
    expect(devices.every(_synced), isTrue);
    h.elapse(const Duration(seconds: 15)); // folder-loop grace (6.7.2)
    h.settle();
  }

  static bool _synced(TestDevice d) {
    final s = d.engine.status;
    return s.phase == SyncPhase.live && s.pendingUploads == 0;
  }

  void operate(TestDevice d) {
    final notes = rowsOf<Note>(d);
    final active = [
      for (final n in notes)
        if (!n.isDeleted) n,
    ];
    final note = pick(random, active);
    final pages = note == null ? const <String>[] : d.pageIdsOf(note.id);
    final strokes = [
      for (final s in rowsOf<Stroke>(d))
        if (!s.isDeleted && pages.contains(s.pageId)) s.id,
    ];
    final folders = [for (final f in rowsOf<Folder>(d)) f.id];
    final objects = [
      for (final o in rowsOf<PageObject>(d))
        if (!o.isDeleted && pages.contains(o.pageId)) o,
    ];
    final recordings = [
      for (final r in rowsOf<Recording>(d))
        if (!r.isDeleted && r.noteId == note?.id) r.id,
    ];
    switch (random.nextInt(24)) {
      case 0 || 1 || 2 || 3 when pages.isNotEmpty:
        created.add(
          d.addStroke(
            pick(random, pages)!,
            seed: random.nextInt(1 << 20),
            points: 8,
          ),
        );
      case 4 when strokes.isNotEmpty:
        final id = pick(random, strokes)!;
        d.eraseStroke(id);
        erased.add(id);
      case 5 when strokes.isNotEmpty:
        d.moveStroke(pick(random, strokes)!, dx: random.nextDouble() * 20);
      case 6 when strokes.isNotEmpty:
        d.recolorStroke(
          pick(random, strokes)!,
          0xFF000000 + random.nextInt(0xFFFFFF),
        );
      case 7 when note != null:
        d.insertPage(note.id, afterPageId: pick(random, pages));
      case 8 when pages.length > 1:
        d.deletePage(pick(random, pages)!);
      case 9 when pages.length > 1:
        final page = entityOn<Page>(d, EntityKind.page, pick(random, pages)!)!;
        final last = entityOn<Page>(d, EntityKind.page, pages.last)!;
        d.store.localWrite([
          FakeLocalWrite(
            EntityKind.page,
            {...page.toJson(), 'sortKey': SortKeys.between(last.sortKey, null)},
            changedFields: const {'sortKey'},
          ),
        ]);
      case 10 when note != null:
        d.renameNote(note.id, '${d.name} ${random.nextInt(1000)}');
      case 11 when note != null:
        d.moveNote(note.id, random.nextBool() ? null : pick(random, folders));
      case 12:
        final trashed = [
          for (final n in notes)
            if (n.isDeleted) n.id,
        ];
        if (trashed.isNotEmpty && random.nextBool()) {
          d.restoreNote(pick(random, trashed)!);
        } else if (active.length > 1) {
          d.trashNote(note!.id);
        }
      case 13 when folders.length > 1:
        final folder = pick(random, folders)!;
        final parent = random.nextInt(3) == 0 ? null : pick(random, folders);
        if (parent == folder) return;
        try {
          d.moveFolder(folder, parent);
        } on StateError {
          // Would make a loop on this device: CORE refuses it too.
        }
      case 14:
        d.setSetting('editor.fuzz', random.nextInt(5));
      case 15 || 16 when pages.isNotEmpty:
        createdObjects.add(
          d.addObject(
            pick(random, pages)!,
            type: pick(random, const ['shape', 'text', 'math'])!,
            seed: random.nextInt(20),
          ),
        );
      case 17 when objects.isNotEmpty:
        d.moveObject(
          pick(random, objects)!.id,
          dx: random.nextDouble() * 20,
          dy: random.nextDouble() * 20,
        );
      case 18 when objects.isNotEmpty:
        d.restyleObject(
          pick(random, objects)!.id,
          0xFF000000 + random.nextInt(0xFFFFFF),
        );
      case 19:
        final texts = [
          for (final o in objects)
            if (o is TextBoxObject) o.id,
        ];
        if (texts.isEmpty) return;
        d.editText(pick(random, texts)!, '${d.name} ${random.nextInt(1000)}');
      case 20 when objects.isNotEmpty:
        final id = pick(random, objects)!.id;
        d.deleteObject(id);
        deletedObjects.add(id);
      case 21 when pages.isNotEmpty:
        d.putHandwriting(pick(random, pages)!, [
          for (var i = 0; i <= random.nextInt(3); i++)
            '${d.name}${random.nextInt(100)}',
        ]);
      case 22 when note != null:
        if (recordings.isEmpty || random.nextInt(4) == 0) {
          h.run(d.addRecording(note.id, durationMs: 1 + random.nextInt(9999)));
        } else {
          d.renameRecording(
            pick(random, recordings)!,
            random.nextInt(5) == 0 ? null : '${d.name} ${random.nextInt(100)}강',
          );
        }
      default:
        if (random.nextBool()) {
          d.createNote('${d.name} note', pages: 1 + random.nextInt(2));
        } else {
          d.createFolder('${d.name} folder', parentId: pick(random, folders));
        }
    }
  }

  void check() {
    expectNoLoss(devices, created, erased: erased);
    for (final d in devices) {
      final lost = [
        for (final id in createdObjects)
          if (d.doc(EntityKind.pageObject, id) == null) id,
      ];
      expect(lost, isEmpty, reason: '${d.name}: page objects lost');
      final inactive = [
        for (final id in createdObjects)
          if (!deletedObjects.contains(id) &&
              d.doc(EntityKind.pageObject, id)!.json['deletedAt'] != null)
            id,
      ];
      expect(inactive, isEmpty, reason: '${d.name}: page objects deleted');
    }
    for (final d in devices) {
      for (final f in rowsOf<Folder>(d)) {
        final seen = <String>{};
        String? at = f.id;
        while (at != null) {
          expect(seen.add(at), isTrue, reason: '${d.name}: loop through $at');
          at = entityOn<Folder>(d, EntityKind.folder, at)?.parentId;
        }
      }
    }
    h.checkConverged(devices);
  }
}

void main() {
  for (var seed = 1; seed <= kSeeds; seed++) {
    syncScenario('random operations converge (seed $seed)', (h) {
      final fuzz = Fuzz(h, Random(seed))..run();
      expect(fuzz.created, isNotEmpty);
      expect(fuzz.createdObjects, isNotEmpty);
      fuzz.check();
    }, seed: seed);
  }
}
