import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/field_merge.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

/// HLC at kT0 + [t] ms on [node].
Hlc h(int t, [String node = kNodeA]) => Hlc(kT0 + t, 0, node);

/// The fixture of [kind] with [set] applied, [remove] keys dropped, base
/// version h([base]) and per-field versions h(fv[f]). json['version'] = max.
UpsertRecord rec(
  EntityKind kind, {
  Map<String, Object?> set = const {},
  Set<String> remove = const {},
  int base = 0,
  Map<String, int> fv = const {},
  String node = kNodeA,
  Map<String, Object?>? from,
}) {
  final versions = EntityFieldVersions(h(base, node), {
    for (final e in fv.entries) e.key: h(e.value, node),
  });
  final json = {...from ?? fixtureJson(kind), ...set}
    ..removeWhere((k, _) => remove.contains(k));
  json['version'] = versions.max.toString();
  return UpsertRecord(
    SyncDoc(kind: kind, id: fixtureId(json), json: json),
    versions,
  );
}

/// One table row: local a, remote b, the expected merged values and field
/// versions (ms offsets; absent = the merged base), and which side changes.
final class Case {
  const Case(
    this.name,
    this.a,
    this.b, {
    this.values = const {},
    this.absent = const {},
    this.versions = const {},
    this.aChanges,
    this.bChanges,
  });
  final String name;
  final UpsertRecord a, b;
  final Map<String, Object?> values;
  final Set<String> absent;
  final Map<String, int> versions;

  /// Fields of the units a must change (b won), when checked.
  final Set<String>? aChanges;
  final Set<String>? bChanges;
}

Set<String> fieldsOf(List<Set<String>> units) => {for (final u in units) ...u};

void main() {
  const note = EntityKind.note;
  const folder = EntityKind.folder;
  const page = EntityKind.page;
  const stroke = EntityKind.stroke;
  const asset = EntityKind.asset;
  const setting = EntityKind.setting;
  const object = EntityKind.pageObject;
  const handwriting = EntityKind.handwriting;
  const recording = EntityKind.recording;
  // (2nd round) the object fixtures of 07-sync 6.4 (shape = fixtureJson(pageObject)).
  final textJson = objectFixture('text').toJson();
  final mathJson = objectFixture('math').toJson();
  final stickerJson = objectFixture('sticker').toJson();
  const moved = [150.0, 300.0, 450.0, 340.0, 0.0];
  const movedShape = [
    [150.0, 100.0],
    [350.0, 100.0],
    [350.0, 220.0],
    [150.0, 220.0],
  ];

  final cases = <Case>[
    // --- single-key units ---------------------------------------------------
    Case(
      'note title: local newer',
      rec(note, set: {'title': 'A'}, fv: {'title': 2}),
      rec(note, set: {'title': 'B'}, fv: {'title': 1}),
      values: {'title': 'A'},
      versions: {'title': 2},
      aChanges: {},
      bChanges: {'title'},
    ),
    Case(
      'note title: remote newer',
      rec(note, set: {'title': 'A'}, fv: {'title': 1}),
      rec(note, set: {'title': 'B'}, fv: {'title': 2}),
      values: {'title': 'B'},
      versions: {'title': 2},
      aChanges: {'title'},
      bChanges: {},
    ),
    Case(
      'note title and isFavorite are independent units',
      rec(note, set: {'title': 'A', 'isFavorite': false}, fv: {'title': 3}),
      rec(note, set: {'title': 'B', 'isFavorite': true}, fv: {'isFavorite': 4}),
      values: {'title': 'A', 'isFavorite': true},
      versions: {'title': 3, 'isFavorite': 4},
      aChanges: {'isFavorite'},
      bChanges: {'title'},
    ),
    Case(
      'note tags list is one unit',
      rec(
        note,
        set: {
          'tags': ['a'],
        },
        fv: {'tags': 1},
      ),
      rec(
        note,
        set: {
          'tags': ['b', 'c'],
        },
        fv: {'tags': 5},
      ),
      values: {
        'tags': ['b', 'c'],
      },
    ),
    Case(
      'note cover map is one unit',
      rec(
        note,
        set: {
          'cover': {'type': 'color', 'color': 1},
        },
        fv: {'cover': 6},
      ),
      rec(
        note,
        set: {
          'cover': {'type': 'color', 'color': 2},
        },
        fv: {'cover': 5},
      ),
      values: {
        'cover': {'type': 'color', 'color': 1},
      },
    ),
    // --- groups ---------------------------------------------------------------
    Case(
      'note {folderId, sortKey}: the newer member carries the whole group',
      rec(note, set: {'folderId': 'fA', 'sortKey': 'a5'}, fv: {'folderId': 5}),
      rec(note, set: {'folderId': 'fB', 'sortKey': 'a9'}, fv: {'sortKey': 3}),
      values: {'folderId': 'fA', 'sortKey': 'a5'},
      versions: {'folderId': 5, 'sortKey': 0},
      aChanges: {},
      bChanges: {'folderId', 'sortKey'},
    ),
    Case(
      'note {folderId, sortKey}: remote reorder newer than local move',
      rec(note, set: {'folderId': 'fA', 'sortKey': 'a5'}, fv: {'folderId': 5}),
      rec(note, set: {'folderId': 'f1', 'sortKey': 'a9'}, fv: {'sortKey': 7}),
      values: {'folderId': 'f1', 'sortKey': 'a9'},
      versions: {'folderId': 0, 'sortKey': 7},
    ),
    Case(
      'note {deletedAt, trashRootId}: remote trash wins over older local',
      rec(note, set: {'title': 'A'}, fv: {'title': 2}),
      rec(
        note,
        set: {'deletedAt': kT0 + 4, 'trashRootId': 'f1'},
        fv: {'deletedAt': 4, 'trashRootId': 4},
      ),
      values: {'title': 'A', 'deletedAt': kT0 + 4, 'trashRootId': 'f1'},
      aChanges: {'deletedAt', 'trashRootId'},
      bChanges: {'title'},
    ),
    Case(
      'note restore (deletedAt null, newer) beats the trash',
      rec(
        note,
        set: {'deletedAt': null, 'trashRootId': null},
        fv: {'deletedAt': 9, 'trashRootId': 9},
      ),
      rec(
        note,
        set: {'deletedAt': kT0 + 4, 'trashRootId': 'n1'},
        fv: {'deletedAt': 4, 'trashRootId': 4},
      ),
      values: {'deletedAt': null, 'trashRootId': null},
    ),
    Case(
      'folder {parentId, sortKey} group',
      rec(
        folder,
        set: {'parentId': 'X', 'sortKey': 'a3'},
        fv: {'parentId': 2, 'sortKey': 2},
      ),
      rec(folder, set: {'parentId': 'Y', 'sortKey': 'a4'}, fv: {'parentId': 3}),
      values: {'parentId': 'Y', 'sortKey': 'a4'},
      versions: {'parentId': 3, 'sortKey': 0},
    ),
    Case(
      'folder name and color are separate units',
      rec(folder, set: {'name': 'A', 'color': 1}, fv: {'name': 1, 'color': 3}),
      rec(folder, set: {'name': 'B', 'color': 2}, fv: {'name': 2, 'color': 2}),
      values: {'name': 'B', 'color': 1},
    ),
    Case(
      'folder {deletedAt, trashRootId}',
      rec(
        folder,
        set: {'deletedAt': kT0 + 1, 'trashRootId': 'f1'},
        fv: {'deletedAt': 1, 'trashRootId': 1},
      ),
      rec(folder, set: {'deletedAt': null, 'trashRootId': null}),
      values: {'deletedAt': kT0 + 1, 'trashRootId': 'f1'},
    ),
    Case(
      'page {noteId, sortKey}: move to another note',
      rec(
        page,
        set: {'noteId': 'n2', 'sortKey': 'b0'},
        fv: {'noteId': 4, 'sortKey': 4},
      ),
      rec(page, set: {'sortKey': 'a7'}, fv: {'sortKey': 2}),
      values: {'noteId': 'n2', 'sortKey': 'b0'},
    ),
    Case(
      'page size and background are separate units',
      rec(
        page,
        set: {
          'size': [10.5, 20.5],
        },
        fv: {'size': 3},
      ),
      rec(
        page,
        set: {
          'background': {'type': 'blank', 'paperColor': 7},
        },
        fv: {'background': 4},
      ),
      values: {
        'size': [10.5, 20.5],
        'background': {'type': 'blank', 'paperColor': 7},
      },
      aChanges: {'background'},
      bChanges: {'size'},
    ),
    Case(
      'stroke: delete vs recolor (S05) keep both',
      rec(stroke, set: {'deletedAt': kT0 + 5}, fv: {'deletedAt': 5}),
      rec(
        stroke,
        set: {
          'style': {'color': 1},
        },
        fv: {'style': 6},
        node: kNodeB,
      ),
      values: {
        'deletedAt': kT0 + 5,
        'style': {'color': 1},
      },
    ),
    Case(
      'stroke {recordingId, recordingOffsetMs} group',
      rec(
        stroke,
        set: {'recordingId': 'r1', 'recordingOffsetMs': 50},
        fv: {'recordingId': 2, 'recordingOffsetMs': 2},
      ),
      rec(
        stroke,
        set: {'recordingId': 'r2', 'recordingOffsetMs': 70},
        fv: {'recordingOffsetMs': 1},
      ),
      values: {'recordingId': 'r1', 'recordingOffsetMs': 50},
    ),
    Case(
      'stroke points is a unit of its own',
      rec(stroke, set: {'points': 'AQ=='}, fv: {'points': 1}),
      rec(stroke, set: {'points': 'Ag=='}, fv: {'points': 2}),
      values: {'points': 'Ag=='},
    ),
    Case(
      'penPreset name vs style',
      rec(EntityKind.penPreset, set: {'name': 'A'}, fv: {'name': 3}),
      rec(
        EntityKind.penPreset,
        set: {
          'style': {'tool': 'pencil'},
        },
        fv: {'style': 2},
      ),
      values: {
        'name': 'A',
        'style': {'tool': 'pencil'},
      },
    ),
    Case(
      'setting {valueJson, deletedAt}: newer value beats older delete',
      rec(setting, set: {'valueJson': '"light"'}, fv: {'valueJson': 5}),
      rec(setting, set: {'deletedAt': kT0 + 3}, fv: {'deletedAt': 3}),
      values: {'valueJson': '"light"', 'deletedAt': null},
      versions: {'valueJson': 5, 'deletedAt': 0},
    ),
    Case(
      'setting delete newer than the value',
      rec(setting, set: {'valueJson': '"light"'}, fv: {'valueJson': 2}),
      rec(setting, set: {'deletedAt': kT0 + 3}, fv: {'deletedAt': 3}),
      values: {'valueJson': '"dark"', 'deletedAt': kT0 + 3},
    ),
    Case(
      'recording durationMs',
      rec(EntityKind.recording, set: {'durationMs': 1}, fv: {'durationMs': 1}),
      rec(EntityKind.recording, set: {'durationMs': 2}),
      values: {'durationMs': 1},
    ),
    // --- special keys -----------------------------------------------------------
    Case(
      'note schemaVersion: larger value, larger version (value side older)',
      rec(note, set: {'schemaVersion': 3}),
      rec(note, set: {'schemaVersion': 2}, fv: {'schemaVersion': 5}),
      values: {'schemaVersion': 3},
      versions: {'schemaVersion': 5},
      aChanges: {'schemaVersion'},
      bChanges: {'schemaVersion'},
    ),
    Case(
      'note schemaVersion: larger value newer',
      rec(note, set: {'schemaVersion': 2}, fv: {'schemaVersion': 4}),
      rec(note, set: {'schemaVersion': 1}),
      values: {'schemaVersion': 2},
      versions: {'schemaVersion': 4},
      aChanges: {},
    ),
    Case(
      'asset storagePath: a value beats a newer null',
      rec(asset, set: {'storagePath': null}, fv: {'storagePath': 5}),
      rec(
        asset,
        set: {'storagePath': 'users/u/assets/x'},
        fv: {'storagePath': 1},
      ),
      values: {'storagePath': 'users/u/assets/x'},
      versions: {'storagePath': 1},
    ),
    Case(
      'asset storagePath: two values → LWW',
      rec(asset, set: {'storagePath': 'p/a'}, fv: {'storagePath': 2}),
      rec(asset, set: {'storagePath': 'p/b'}, fv: {'storagePath': 3}),
      values: {'storagePath': 'p/b'},
    ),
    Case(
      'asset storagePath: two nulls → LWW',
      rec(asset, set: {'storagePath': null}, fv: {'storagePath': 2}),
      rec(asset, set: {'storagePath': null}),
      values: {'storagePath': null},
      versions: {'storagePath': 2},
    ),
    // --- meta keys --------------------------------------------------------------
    Case(
      'updatedAt = larger value even when its side loses every unit',
      rec(note, set: {'title': 'A', 'updatedAt': kT0 + 1}, fv: {'title': 5}),
      rec(note, set: {'title': 'B', 'updatedAt': kT0 + 9}, fv: {'title': 4}),
      values: {'title': 'A', 'updatedAt': kT0 + 9},
    ),
    Case(
      'createdAt = smaller value',
      rec(note, set: {'createdAt': kT0 - 10}),
      rec(note, set: {'createdAt': kT0 - 20}),
      values: {'createdAt': kT0 - 20},
    ),
    Case(
      'asset has no updatedAt and gets none',
      rec(asset),
      rec(asset, fv: {'fileName': 1}),
      absent: {'updatedAt'},
    ),
    // --- absent and unknown keys --------------------------------------------------
    Case(
      'a newer snapshot without a key drops it (older writer wins its unit)',
      rec(note, set: {'trashRootId': 'f1'}),
      rec(note, remove: {'trashRootId'}, base: 2),
      absent: {'trashRootId'},
      values: {'deletedAt': null},
    ),
    Case(
      'an older snapshot without a key keeps the other side',
      rec(note, set: {'trashRootId': 'f1'}, base: 2),
      rec(note, remove: {'trashRootId'}),
      values: {'trashRootId': 'f1'},
    ),
    Case(
      'a key outside the table is a unit of its own',
      rec(note, set: {'futureKey': 1}, fv: {'futureKey': 3}),
      rec(note, set: {'futureKey': 2}, fv: {'futureKey': 2}),
      values: {'futureKey': 1},
      versions: {'futureKey': 3},
    ),
    // --- ties -----------------------------------------------------------------------
    Case(
      'equal snapshots: nothing changes on either side',
      rec(note, fv: {'title': 1}),
      rec(note, fv: {'title': 1}),
      values: {'title': '강의노트'},
      aChanges: {},
      bChanges: {},
    ),
    Case(
      'broken invariant (same version, other value): larger canonical value',
      rec(note, set: {'title': 'A'}, fv: {'title': 1}),
      rec(note, set: {'title': 'B'}, fv: {'title': 1}),
      values: {'title': 'B'},
    ),
    Case(
      'tie on the unit max: larger member versions win',
      rec(
        note,
        set: {'folderId': 'fA', 'sortKey': 'a1'},
        fv: {'folderId': 5, 'sortKey': 5},
      ),
      rec(note, set: {'folderId': 'fB', 'sortKey': 'a1'}, fv: {'folderId': 5}),
      values: {'folderId': 'fA'},
      versions: {'folderId': 5, 'sortKey': 5},
    ),
    // --- (2nd round, S2-1) one object / result unit — 07-sync 6.2.2 table ---------
    Case(
      'object: move (frame + geometry) vs restyle — the later edit takes the '
      'whole object',
      rec(
        object,
        set: {
          'frame': [150.0, 100.0, 350.0, 220.0, 0.0],
          'geometry': {'type': 'polyline', 'points': movedShape},
        },
        fv: {'frame': 1, 'geometry': 1},
      ),
      rec(
        object,
        set: {
          'style': {'strokeColorArgb': 1},
        },
        fv: {'style': 2},
      ),
      values: {
        'frame': fixtureJson(object)['frame'],
        'geometry': fixtureJson(object)['geometry'],
        'style': {'strokeColorArgb': 1},
      },
      versions: {'style': 2},
      aChanges: {
        ...FieldUnits.unitsFor(object, FieldUnits.keysOf(object)).first,
      },
      bChanges: {},
    ),
    Case(
      'text box: text edit (text + frame height) vs move — text and height '
      'never split',
      rec(
        object,
        from: textJson,
        set: {
          'text': '긴 글',
          'frame': [100.0, 300.0, 400.0, 380.0, 0.0],
        },
        fv: {'text': 3, 'frame': 3},
      ),
      rec(object, from: textJson, set: {'frame': moved}, fv: {'frame': 2}),
      values: {
        'text': '긴 글',
        'frame': [100.0, 300.0, 400.0, 380.0, 0.0],
      },
      versions: {'text': 3, 'frame': 3},
    ),
    Case(
      'object: delete vs edit — deleted, and the edit stays (like S05)',
      rec(object, set: {'deletedAt': kT0 + 1}, fv: {'deletedAt': 1}),
      rec(
        object,
        set: {
          'style': {'strokeColorArgb': 2},
        },
        fv: {'style': 2},
      ),
      values: {
        'deletedAt': kT0 + 1,
        'style': {'strokeColorArgb': 2},
      },
      versions: {'deletedAt': 1, 'style': 2},
      aChanges: {
        ...FieldUnits.unitsFor(object, FieldUnits.keysOf(object)).first,
      },
      bChanges: {'deletedAt'},
    ),
    Case(
      'math: re-recognition (latex + engine) vs a later move — the object '
      'unit goes to the move, engine is its own unit',
      rec(
        object,
        from: mathJson,
        set: {'latex': r'\sqrt{2}', 'engine': 'fake/1'},
        fv: {'latex': 1, 'engine': 1},
      ),
      rec(object, from: mathJson, set: {'frame': moved}, fv: {'frame': 2}),
      values: {'latex': r'\frac{a}{b}', 'frame': moved, 'engine': 'fake/1'},
      versions: {'frame': 2, 'engine': 1},
    ),
    Case(
      'math: a later re-recognition takes latex with the object, engine '
      'separately',
      rec(
        object,
        from: mathJson,
        set: {'latex': r'\sqrt{2}', 'engine': 'fake/1'},
        fv: {'latex': 3, 'engine': 3},
      ),
      rec(object, from: mathJson, set: {'frame': moved}, fv: {'frame': 2}),
      values: {
        'latex': r'\sqrt{2}',
        'frame': mathJson['frame'],
        'engine': 'fake/1',
      },
      versions: {'latex': 3, 'engine': 3},
    ),
    // (math pen) ink rides in the one object unit: a formula and its handwriting win
    // together. An older app's snapshot has no ink key at all.
    Case(
      'math ink: a later conversion with ink beats an older app\'s earlier '
      'move (no ink key) — frame and ink together',
      rec(
        object,
        from: mathJson,
        set: {
          'latex': 'x^{2}',
          'ink': [fixtureJson(stroke)],
        },
        fv: {'latex': 3, 'ink': 3},
      ),
      rec(
        object,
        from: Map.of(mathJson)..remove('ink'),
        set: {'frame': moved},
        fv: {'frame': 2},
      ),
      values: {
        'latex': 'x^{2}',
        'frame': mathJson['frame'],
        'ink': [fixtureJson(stroke)],
      },
      versions: {'latex': 3, 'ink': 3},
    ),
    Case(
      'math ink: an older app\'s later move (no ink key) takes the object '
      'unit — the ink goes with it, the formula stays',
      rec(
        object,
        from: mathJson,
        set: {
          'ink': [fixtureJson(stroke)],
        },
        fv: {'ink': 1},
      ),
      rec(
        object,
        from: Map.of(mathJson)..remove('ink'),
        set: {'frame': moved},
        fv: {'frame': 2},
      ),
      values: {'frame': moved, 'latex': mathJson['latex']},
      absent: {'ink'},
      versions: {'frame': 2},
    ),
    Case(
      'unknown object type: a later change of an unknown key takes the whole '
      'object',
      rec(
        object,
        from: stickerJson,
        set: {'stickerId': 'dog'},
        fv: {'stickerId': 4},
      ),
      rec(object, from: stickerJson, set: {'frame': moved}, fv: {'frame': 3}),
      values: {'stickerId': 'dog', 'frame': stickerJson['frame']},
      versions: {'stickerId': 4},
    ),
    Case(
      'object: a key the other snapshot lacks goes with the winner',
      rec(object, from: textJson, set: {'anchor': 'top'}, fv: {'anchor': 1}),
      rec(object, from: textJson, set: {'text': 'later'}, fv: {'text': 2}),
      values: {'text': 'later'},
      absent: {'anchor'},
      versions: {'text': 2},
    ),
    Case(
      'handwriting: a later result replaces lines, sourceRev and engineId '
      'together',
      rec(
        handwriting,
        set: {'lines': <Object?>[], 'sourceRev': 'aaaaaaaaaaaaaaaa'},
        fv: {'lines': 2, 'sourceRev': 2},
      ),
      rec(handwriting, set: {'engineId': 'other/1:ko'}, fv: {'engineId': 1}),
      values: {
        'lines': <Object?>[],
        'sourceRev': 'aaaaaaaaaaaaaaaa',
        'engineId': fixtureJson(handwriting)['engineId'],
      },
      versions: {'lines': 2, 'sourceRev': 2},
    ),
    Case(
      'handwriting: deletedAt is its own unit',
      rec(handwriting, set: {'deletedAt': kT0 + 1}, fv: {'deletedAt': 1}),
      rec(handwriting, set: {'lines': <Object?>[]}, fv: {'lines': 2}),
      values: {'deletedAt': kT0 + 1, 'lines': <Object?>[]},
      versions: {'deletedAt': 1, 'lines': 2},
    ),
    Case(
      '(S2-8) handwriting created on two devices: createdAt comes with the '
      'winning result, even when it is the larger one',
      rec(
        handwriting,
        set: {'createdAt': kT0 - 20, 'lines': <Object?>[]},
        fv: {'lines': 1},
      ),
      rec(
        handwriting,
        set: {'createdAt': kT0 - 10, 'sourceRev': 'ffffffffffffffff'},
        fv: {'sourceRev': 2},
      ),
      values: {
        'createdAt': kT0 - 10,
        'sourceRev': 'ffffffffffffffff',
        'lines': fixtureJson(handwriting)['lines'],
      },
      versions: {'sourceRev': 2},
    ),
    Case(
      '(S2-8) object: the same unit state on both sides → the smaller '
      'createdAt',
      rec(object, set: {'createdAt': kT0 - 10}),
      rec(object, set: {'createdAt': kT0 - 20}),
      values: {'createdAt': kT0 - 20},
    ),
    Case(
      'recording: title is its own unit (rename vs delete keeps both)',
      rec(recording, set: {'title': '2교시'}, fv: {'title': 2}),
      rec(recording, set: {'deletedAt': kT0 + 1}, fv: {'deletedAt': 1}),
      values: {'title': '2교시', 'deletedAt': kT0 + 1},
      versions: {'title': 2, 'deletedAt': 1},
      aChanges: {'deletedAt'},
      bChanges: {'title'},
    ),
  ];

  test('the table has at least 30 cases', () {
    expect(cases.length, greaterThanOrEqualTo(30));
  });

  for (final c in cases) {
    test(c.name, () {
      for (final (x, y) in [(c.a, c.b), (c.b, c.a)]) {
        final result = FieldMerge.merge(x, y);
        final m = result.merged;
        for (final MapEntry(:key, :value) in c.values.entries) {
          expect(m.doc.json.containsKey(key), isTrue, reason: key);
          expect(m.doc.json[key], value, reason: key);
        }
        for (final k in c.absent) {
          expect(m.doc.json.containsKey(k), isFalse, reason: k);
        }
        for (final MapEntry(:key, :value) in c.versions.entries) {
          expect(
            m.versions.of(key),
            h(value, m.versions.of(key).nodeId),
            reason: key,
          );
          expect(m.versions.of(key).millis, kT0 + value, reason: key);
        }
        expect(m.doc.json['version'], m.versions.max.toString());
        expect(m.doc.id, c.a.doc.id);
      }
      final forward = FieldMerge.merge(c.a, c.b);
      if (c.aChanges != null) {
        expect(fieldsOf(forward.changedForA), c.aChanges);
      }
      if (c.bChanges != null) {
        expect(fieldsOf(forward.changedForB), c.bChanges);
      }
    });
  }

  test('merged versions: base = smaller base, overrides only above it', () {
    final a = rec(note, base: 2, fv: {'title': 6});
    final b = rec(note, base: 1, fv: {'folderId': 4});
    final m = FieldMerge.mergeRecords(a, b);
    expect(m.versions.base, h(1));
    expect(m.versions.toJson(), {
      'b': h(1).toString(),
      'o': {
        // a's base covers every other key of a (2 > 1).
        for (final k in FieldUnits.keysOf(note))
          if (!FieldUnits.metaKeys.contains(k) &&
              k != 'title' &&
              k != 'folderId' &&
              k != 'sortKey')
            k: h(2).toString(),
        'title': h(6).toString(),
        'folderId': h(4).toString(),
        'sortKey': h(1).toString(),
      }..removeWhere((_, v) => v == h(1).toString()),
    });
  });

  test('the merged record decodes with CORE for every kind', () {
    for (final kind in EntityKind.values) {
      final a = rec(kind, base: 1);
      final b = rec(kind, base: 2, node: kNodeB);
      final m = FieldMerge.mergeRecords(a, b);
      final entity = m.doc.toEntity();
      expect(entity.version, m.versions.max);
    }
  });

  test('different kind, id or key is an ArgumentError', () {
    expect(
      () => FieldMerge.mergeRecords(rec(note), rec(page)),
      throwsArgumentError,
    );
    final other = UpsertRecord(
      SyncDoc(kind: note, id: 'n2', json: {...fixtureJson(note), 'id': 'n2'}),
      EntityFieldVersions(h(0)),
    );
    expect(
      () => FieldMerge.mergeRecords(rec(note), other),
      throwsArgumentError,
    );
  });
}
