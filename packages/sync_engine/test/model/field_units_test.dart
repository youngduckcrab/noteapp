import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
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
      // (2nd round, R2-B7a) general records until S2-1 (07-sync 6.2.2).
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
}
