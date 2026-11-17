import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/field_merge.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

void main() {
  test('keysOf is the CORE 6.3 key table', () {
    for (final kind in EntityKind.values) {
      expect(FieldUnits.keysOf(kind), kCoreJsonKeys[kind], reason: kind.name);
    }
  });

  test('groups follow table 6.3.1', () {
    expect(FieldUnits.groupsOf(EntityKind.folder), [
      {'parentId', 'sortKey'},
      {'deletedAt', 'trashRootId'},
    ]);
    expect(FieldUnits.groupsOf(EntityKind.note), [
      {'folderId', 'sortKey'},
      {'deletedAt', 'trashRootId'},
    ]);
    expect(FieldUnits.groupsOf(EntityKind.page), [
      {'noteId', 'sortKey'},
    ]);
    expect(FieldUnits.groupsOf(EntityKind.stroke), [
      {'recordingId', 'recordingOffsetMs'},
    ]);
    expect(FieldUnits.groupsOf(EntityKind.setting), [
      {'valueJson', 'deletedAt'},
    ]);
    for (final k in [
      EntityKind.penPreset,
      EntityKind.asset,
      EntityKind.recording,
      // (2nd round) merged by wholeUnitExcept instead (07-sync 6.2.2).
      EntityKind.pageObject,
      EntityKind.handwriting,
    ]) {
      expect(FieldUnits.groupsOf(k), isEmpty, reason: k.name);
    }
  });

  test('the pageObject keys are the union of the known object types', () {
    expect(kPageObjectTypeKeys.keys, ['shape', 'text', 'image', 'math']);
    final union = {for (final keys in kPageObjectTypeKeys.values) ...keys};
    expect(union, kCoreJsonKeys[EntityKind.pageObject]);
    expect(union, FieldUnits.keysOf(EntityKind.pageObject));
    // C21-11: math always writes engine, also when it is null.
    expect(kPageObjectTypeKeys['math'], contains('engine'));
    // (math pen) ink: in the one object unit (not excepted).
    expect(kPageObjectTypeKeys['math'], contains('ink'));
    expect(
      FieldUnits.wholeUnitExcept(EntityKind.pageObject),
      isNot(contains('ink')),
    );
  });

  // --- (2nd round, S2-1) one object / result unit (contract 7.2.8, 07-sync 6.2.2) ---
  test('wholeUnitExcept: the excepted keys of the one-unit kinds, null for the '
      'v1.4 kinds', () {
    expect(FieldUnits.wholeUnitExcept(EntityKind.pageObject), {
      'pageId',
      'deletedAt',
      'engine',
    });
    expect(FieldUnits.wholeUnitExcept(EntityKind.handwriting), {
      'noteId',
      'pageId',
      'deletedAt',
    });
    for (final kind in EntityKind.values) {
      if (kind == EntityKind.pageObject || kind == EntityKind.handwriting) {
        continue;
      }
      expect(FieldUnits.wholeUnitExcept(kind), isNull, reason: kind.name);
    }
    for (final kind in [EntityKind.pageObject, EntityKind.handwriting]) {
      // The excepted keys are CORE keys and never meta keys.
      final except = FieldUnits.wholeUnitExcept(kind)!;
      expect(kCoreJsonKeys[kind]!.containsAll(except), isTrue);
      expect(except.intersection(FieldUnits.metaKeys), isEmpty);
    }
  });

  test('unit table of the new kinds (6.2.2)', () {
    expect(
      FieldUnits.unitsFor(
        EntityKind.pageObject,
        FieldUnits.keysOf(EntityKind.pageObject),
      ),
      [
        {
          'assetId',
          'frame',
          'geometry',
          'ink',
          'latex',
          'px',
          'shape',
          'style',
          'text',
          'type',
        },
        {'deletedAt'},
        {'engine'},
        {'pageId'},
      ],
    );
    expect(
      FieldUnits.unitsFor(
        EntityKind.handwriting,
        FieldUnits.keysOf(EntityKind.handwriting),
      ),
      [
        {'engineId', 'lines', 'sourceRev'},
        {'deletedAt'},
        {'noteId'},
        {'pageId'},
      ],
    );
    // recording: no groups — title is a unit of its own like every other key.
    final recording = FieldUnits.unitsFor(
      EntityKind.recording,
      FieldUnits.keysOf(EntityKind.recording),
    );
    expect(recording, anyElement(equals({'title'})));
    expect(recording.every((u) => u.length == 1), isTrue);
  });

  test('per object type: the keys of the type are one unit, the excepted '
      'keys their own', () {
    for (final MapEntry(key: type, value: keys)
        in kPageObjectTypeKeys.entries) {
      final units = FieldUnits.unitsFor(EntityKind.pageObject, keys);
      final except = FieldUnits.wholeUnitExcept(EntityKind.pageObject)!;
      expect(
        units.first,
        keys.difference(FieldUnits.metaKeys).difference(except),
        reason: type,
      );
      expect(units.skip(1).toList(), [
        for (final k in keys.intersection(except).toList()..sort()) {k},
      ], reason: type);
    }
  });

  test('unknown keys join the object / result unit', () {
    final object = objectFixture('sticker').toJson().keys;
    final units = FieldUnits.unitsFor(EntityKind.pageObject, object);
    expect(units.first, containsAll(['stickerId', 'tint', 'type', 'frame']));
    expect(units.skip(1), everyElement(hasLength(1)));
    final hw = FieldUnits.unitsFor(EntityKind.handwriting, [
      ...FieldUnits.keysOf(EntityKind.handwriting),
      'layout',
    ]);
    expect(hw.first, {'engineId', 'lines', 'sourceRev', 'layout'});
  });

  test('only excepted keys present: no empty unit', () {
    expect(
      FieldUnits.unitsFor(EntityKind.pageObject, [
        'deletedAt',
        'id',
        'version',
      ]),
      [
        {'deletedAt'},
      ],
    );
    expect(FieldUnits.unitsFor(EntityKind.handwriting, ['id']), isEmpty);
  });

  // 07-sync 6.2.2 counter-example: a later app adds key K to a known object type.
  // A moves the object (frame, t1), B changes K (t2 > t1), C is an old app whose
  // CORE drops K when it reads A's snapshot. With K in the one unit every app picks
  // B's whole object, so the known keys converge.
  test('mixed app versions converge: an unknown key decides with the object '
      'unit', () {
    const k = 'anchor';
    final base = objectFixture('text').toJson();
    Hlc t(int ms) => Hlc(kT0 + ms, 0, kNodeA);
    UpsertRecord snap(Map<String, Object?> json, Map<String, int> fv) {
      final versions = EntityFieldVersions(t(0), {
        for (final e in fv.entries) e.key: t(e.value),
      });
      return UpsertRecord(
        SyncDoc(
          kind: EntityKind.pageObject,
          id: 'o-text',
          json: {...json, 'version': versions.max.toString()},
        ),
        versions,
      );
    }

    const moved = [150.0, 300.0, 450.0, 340.0, 0.0];
    final a = snap({...base, 'frame': moved, k: 'left'}, {'frame': 1});
    final b = snap({...base, k: 'right'}, {k: 2});
    final cViewOfA = snap({...base, 'frame': moved}, {'frame': 1});

    final newApp = FieldMerge.mergeRecords(a, b);
    final oldApp = FieldMerge.mergeRecords(cViewOfA, b);
    for (final m in [newApp, oldApp, FieldMerge.mergeRecords(b, cViewOfA)]) {
      expect(m.doc.json['frame'], base['frame'], reason: 'B wins the object');
      expect(m.doc.json[k], 'right');
    }
    for (final key in kPageObjectTypeKeys['text']!) {
      if (FieldUnits.metaKeys.contains(key)) continue;
      expect(oldApp.doc.json[key], newApp.doc.json[key], reason: key);
    }
    // With K as a unit of its own (the per-key reading), the old app would keep
    // A's move while the new apps drop it — they would never converge.
    expect(
      FieldUnits.unitsFor(
        EntityKind.pageObject,
        a.doc.json.keys,
      ).where((u) => u.contains(k)).single,
      contains('frame'),
    );
  });

  test('meta keys are identity and derived values', () {
    expect(FieldUnits.metaKeys, {
      'id',
      'key',
      'version',
      'createdAt',
      'updatedAt',
    });
  });

  test('group keys exist in the CORE 6.3 key table', () {
    for (final kind in EntityKind.values) {
      for (final group in FieldUnits.groupsOf(kind)) {
        expect(
          kCoreJsonKeys[kind]!.containsAll(group),
          isTrue,
          reason: '${kind.name} $group',
        );
      }
    }
  });

  test('every CORE 6.3 key except meta keys is in exactly one unit', () {
    for (final kind in EntityKind.values) {
      final keys = kCoreJsonKeys[kind]!;
      final units = FieldUnits.unitsFor(kind, keys);
      final flat = [for (final u in units) ...u];
      expect(
        flat.toSet(),
        keys.difference(FieldUnits.metaKeys),
        reason: kind.name,
      );
      expect(flat, hasLength(flat.toSet().length), reason: kind.name);
    }
  });

  // (2nd round, SYNC-M4) compared per kind: a page object serializes the keys of its
  // type, not the union (07-sync 6.4).
  test('the CORE key table matches what CORE entities serialize', () {
    for (final kind in EntityKind.values) {
      if (kind == EntityKind.pageObject) continue;
      expect(
        fixtureEntity(kind).toJson().keys.toSet(),
        kCoreJsonKeys[kind],
        reason: kind.name,
      );
    }
  });

  test('each known page object type serializes the keys of '
      'kPageObjectTypeKeys', () {
    for (final MapEntry(key: type, value: keys)
        in kPageObjectTypeKeys.entries) {
      final object = objectFixture(type);
      expect(object.type, type);
      final json = object.toJson();
      expect(json.keys.toSet(), keys, reason: type);
      final decoded = EntityJson.decode(EntityKind.pageObject, json);
      expect(decoded, object, reason: type);
      expect(decoded.toJson().keys.toSet(), keys, reason: type);
    }
  });

  test('an unknown object type is left out of the key comparison and '
      'round-trips key for key', () {
    final object = objectFixture('sticker');
    expect(object, isA<UnknownObject>());
    expect(kPageObjectTypeKeys, isNot(contains(object.type)));
    final json = object.toJson();
    expect(json, containsPair('stickerId', 'cat-01'));
    expect(EntityJson.decode(EntityKind.pageObject, json).toJson(), json);
  });

  test('a key outside the table is a unit of its own', () {
    final units = FieldUnits.unitsFor(EntityKind.note, ['title', 'futureKey']);
    expect(units, [
      {'futureKey'},
      {'title'},
    ]);
  });

  test('one key of a group brings the whole group', () {
    expect(FieldUnits.unitsFor(EntityKind.folder, ['parentId']), [
      {'parentId', 'sortKey'},
    ]);
    expect(FieldUnits.unitsFor(EntityKind.setting, ['deletedAt']), [
      {'valueJson', 'deletedAt'},
    ]);
  });

  test('meta keys never form units', () {
    expect(
      FieldUnits.unitsFor(EntityKind.stroke, FieldUnits.metaKeys),
      isEmpty,
    );
  });

  test('units are in a deterministic order', () {
    final a = FieldUnits.unitsFor(
      EntityKind.note,
      kCoreJsonKeys[EntityKind.note]!,
    );
    final b = FieldUnits.unitsFor(
      EntityKind.note,
      kCoreJsonKeys[EntityKind.note]!.toList().reversed,
    );
    expect(a, b);
  });

  // --- (v2.17-md, C217M-06) the MD 문서 body ---
  test(
    'markdown: keys = CORE keys, units {noteId} {text} {deletedAt}, no groups, '
    'not a one-unit kind',
    () {
      expect(
        FieldUnits.keysOf(EntityKind.markdown),
        kCoreJsonKeys[EntityKind.markdown],
      );
      expect(FieldUnits.groupsOf(EntityKind.markdown), isEmpty);
      expect(FieldUnits.wholeUnitExcept(EntityKind.markdown), isNull);
      expect(
        FieldUnits.unitsFor(
          EntityKind.markdown,
          FieldUnits.keysOf(EntityKind.markdown),
        ).toSet(),
        {
          {'noteId'},
          {'text'},
          {'deletedAt'},
        },
      );
      // The note's keys are unchanged: the format is the schemaVersion range.
      expect(FieldUnits.keysOf(EntityKind.note), isNot(contains('format')));
    },
  );
}
