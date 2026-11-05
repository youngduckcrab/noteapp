// FieldMerge properties (6.3.2) shared by the VM test
// (merge/field_merge_properties_test.dart, seeds 1..20) and Chrome
// (web/pure_logic_browser_test.dart, seeds 1..3): commutative, associative and
// idempotent, equality = doc.json and versions.toJson(). Snapshots are random
// (small value and version pools so ties happen), not necessarily obeying the
// invariant 6.3.3 — the tie-break keeps the merge total.
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/field_merge.dart';
import 'package:sync_engine/sync_engine.dart';

const int _t0 = 1793750400000;
const List<String> _nodes = ['3f2a9c0d11e0b7a4', 'b7a43f2a9c0d11e0'];
const DeepCollectionEquality _eq = DeepCollectionEquality();

/// Value pools per kind; 'id' / 'key' are fixed per kind.
const Map<EntityKind, Map<String, List<Object?>>> _pools = {
  EntityKind.note: {
    'ownerId': ['u1'],
    'folderId': [null, 'f1', 'f2'],
    'title': ['a', 'b', '강의'],
    'cover': [
      {'type': 'color', 'color': 1},
      {'type': 'color', 'color': 2},
    ],
    'tags': [
      <String>[],
      ['x'],
      ['x', 'y'],
    ],
    'isFavorite': [true, false],
    'sortKey': ['a0', 'a1', 'a2'],
    'schemaVersion': [1, 2, 3],
    'deletedAt': [null, _t0 + 1, _t0 + 2],
    'trashRootId': [null, 'n1', 'f1'],
    'createdAt': [_t0, _t0 - 5],
    'updatedAt': [_t0, _t0 + 9, _t0 + 3],
  },
  EntityKind.page: {
    'noteId': ['n1', 'n2'],
    'sortKey': ['a0', 'a1'],
    'size': [
      [100.5, 200.5],
      [300.5, 400.5],
    ],
    'background': [
      {'type': 'blank', 'paperColor': 1},
      {'type': 'blank', 'paperColor': 2},
    ],
    'deletedAt': [null, _t0 + 1],
    'createdAt': [_t0],
    'updatedAt': [_t0, _t0 + 4],
  },
  EntityKind.stroke: {
    'pageId': ['p1'],
    'style': [
      {'color': 1, 'width': 2.5},
      {'color': 2, 'width': 2.5},
    ],
    'points': ['AQ==', 'Ag=='],
    'recordingId': [null, 'r1'],
    'recordingOffsetMs': [null, 5, 9],
    'deletedAt': [null, _t0 + 1, _t0 + 2],
    'createdAt': [_t0],
    'updatedAt': [_t0, _t0 + 7],
  },
  EntityKind.asset: {
    'ownerId': ['u1'],
    'type': ['pdf'],
    'mimeType': ['application/pdf'],
    'size': [10, 20],
    'fileName': ['a.pdf', 'b.pdf'],
    'storagePath': [null, 'users/u1/assets/a', 'users/u1/assets/b'],
    'deletedAt': [null, _t0 + 1],
    'createdAt': [_t0, _t0 - 1],
  },
  EntityKind.setting: {
    'valueJson': ['"dark"', '"light"', '1'],
    'deletedAt': [null, _t0 + 1],
    'updatedAt': [_t0, _t0 + 2],
  },
  EntityKind.folder: {
    'ownerId': ['u1'],
    'parentId': [null, 'f2', 'f3'],
    'name': ['수업', 'x'],
    'color': [1, 2],
    'icon': [null, 'school'],
    'sortKey': ['a0', 'a1'],
    'deletedAt': [null, _t0 + 1],
    'trashRootId': [null, 'f1'],
    'createdAt': [_t0],
    'updatedAt': [_t0, _t0 + 1],
  },
};

const Set<String> _meta = {'id', 'key', 'version', 'createdAt', 'updatedAt'};

Hlc _hlc(Random rng) =>
    Hlc(_t0 + rng.nextInt(4), rng.nextInt(2), _nodes[rng.nextInt(2)]);

UpsertRecord randomSnapshot(Random rng, EntityKind kind) {
  final pool = _pools[kind]!;
  final json = <String, Object?>{
    if (kind == EntityKind.setting) 'key': 'editor.theme' else 'id': 'e1',
  };
  for (final MapEntry(:key, :value) in pool.entries) {
    // Rarely leave a non-meta key out (older writer).
    if (!_meta.contains(key) && rng.nextInt(12) == 0) continue;
    json[key] = value[rng.nextInt(value.length)];
  }
  final base = _hlc(rng);
  final overrides = <String, Hlc>{
    for (final k in json.keys)
      if (!_meta.contains(k) && rng.nextBool()) k: _hlc(rng),
  };
  final versions = EntityFieldVersions(base, {
    for (final e in overrides.entries)
      if (e.value > base) e.key: e.value,
  });
  json['version'] = versions.max.toString();
  return UpsertRecord(
    SyncDoc(
      kind: kind,
      id: kind == EntityKind.setting ? 'editor.theme' : 'e1',
      json: json,
    ),
    versions,
  );
}

/// Equality of the property tests: doc.json and versions.toJson().
bool sameRecord(UpsertRecord a, UpsertRecord b) =>
    a.doc.kind == b.doc.kind &&
    a.doc.id == b.doc.id &&
    _eq.equals(a.doc.json, b.doc.json) &&
    _eq.equals(a.versions.toJson(), b.versions.toJson());

String describe(UpsertRecord r) => '${r.doc.json} ${r.versions.toJson()}';

void mergePropertiesCases({required Iterable<int> seeds, int pairs = 100}) {
  final kinds = _pools.keys.toList();

  test('commutative: merge(a, b) == merge(b, a)', () {
    for (final seed in seeds) {
      final rng = Random(seed);
      for (var i = 0; i < pairs; i++) {
        final kind = kinds[rng.nextInt(kinds.length)];
        final a = randomSnapshot(rng, kind), b = randomSnapshot(rng, kind);
        final ab = FieldMerge.mergeRecords(a, b);
        final ba = FieldMerge.mergeRecords(b, a);
        expect(
          sameRecord(ab, ba),
          isTrue,
          reason:
              'seed $seed #$i\na: ${describe(a)}\nb: ${describe(b)}\n'
              'ab: ${describe(ab)}\nba: ${describe(ba)}',
        );
      }
    }
  });

  test('associative: merge(merge(a, b), c) == merge(a, merge(b, c))', () {
    for (final seed in seeds) {
      final rng = Random(seed);
      for (var i = 0; i < pairs; i++) {
        final kind = kinds[rng.nextInt(kinds.length)];
        final a = randomSnapshot(rng, kind);
        final b = randomSnapshot(rng, kind);
        final c = randomSnapshot(rng, kind);
        final left = FieldMerge.mergeRecords(FieldMerge.mergeRecords(a, b), c);
        final right = FieldMerge.mergeRecords(a, FieldMerge.mergeRecords(b, c));
        expect(
          sameRecord(left, right),
          isTrue,
          reason:
              'seed $seed #$i\na: ${describe(a)}\nb: ${describe(b)}\n'
              'c: ${describe(c)}\nleft: ${describe(left)}\n'
              'right: ${describe(right)}',
        );
      }
    }
  });

  test('idempotent: merge(a, a) == a', () {
    for (final seed in seeds) {
      final rng = Random(seed);
      for (var i = 0; i < pairs; i++) {
        final kind = kinds[rng.nextInt(kinds.length)];
        final a = randomSnapshot(rng, kind);
        final aa = FieldMerge.mergeRecords(a, a);
        expect(
          sameRecord(aa, a),
          isTrue,
          reason: 'seed $seed #$i\na: ${describe(a)}\naa: ${describe(aa)}',
        );
        // Merging the result again changes nothing either.
        final b = randomSnapshot(rng, kind);
        final ab = FieldMerge.mergeRecords(a, b);
        expect(sameRecord(FieldMerge.mergeRecords(ab, b), ab), isTrue);
        expect(sameRecord(FieldMerge.mergeRecords(ab, a), ab), isTrue);
      }
    }
  });

  test('the merged version is the max of the merged field versions', () {
    for (final seed in seeds) {
      final rng = Random(seed);
      for (var i = 0; i < pairs; i++) {
        final kind = kinds[rng.nextInt(kinds.length)];
        final m = FieldMerge.mergeRecords(
          randomSnapshot(rng, kind),
          randomSnapshot(rng, kind),
        );
        expect(m.doc.json['version'], m.versions.max.toString());
      }
    }
  });
}
