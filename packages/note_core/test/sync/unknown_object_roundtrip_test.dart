// CORE T28 — an object of a type this app does not know round-trips unchanged (C-12;
// m5-7/02-core 6.2.6, 6.13): applyRemote → readVersioned → exportBackupJson keep the same key
// set and values, nested maps / arrays and unknown keys included; a remote update of it is
// stored as given; a known type with an enum name this app does not know (CP-6) does the same.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';
import '../storage/storage_support.dart';
import 'support/sync_support.dart';

void main() {
  late DriftNoteStore store;
  setUp(() async => store = await openStore());
  tearDown(() => store.close());

  Future<VersionedEntity> read(String id) async =>
      (await store.sync.readVersioned([EntityRef(EntityKind.pageObject, id)]))
          .single!;

  /// The `data` of [id]'s entity in the backup document, and its versions.
  Future<(Map<String, Object?>, Map<String, Object?>)> exported(
    String id,
  ) async {
    final doc = jsonDecode(
      utf8.decode(await store.exportBackupJson()),
    ) as Map<String, Object?>;
    final e = (doc['entities']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere(
          (e) =>
              e['kind'] == 'pageObject' &&
              (e['data']! as Map<String, Object?>)['id'] == id,
        );
    return (
      e['data']! as Map<String, Object?>,
      e['versions']! as Map<String, Object?>,
    );
  }

  /// [raw] as the remote sends it at [v] (version key = v).
  Map<String, Object?> atVersion(Map<String, Object?> raw, Hlc v) => {
    ...raw,
    'version': v.toString(),
  };

  test(
    'applyRemote → readVersioned → exportBackupJson: same keys, same values',
    () async {
      final n = await store.library.createNote(title: 'n');
      final pageId = (await store.library.getNote(n.id))!.firstPageId!;
      final sample = kSampleObjects['unknown']! as UnknownObject;
      final raw = {...sample.rawJson, 'pageId': pageId};
      final v = remoteAfter(store);
      await store.sync.applyRemote([
        upsert(UnknownObject(raw), v),
      ], policy: newerVersionWinsPolicy);
      final expected = atVersion(raw, v);

      final back = await read(sample.id);
      expect(back.entity, isA<UnknownObject>());
      expect(back.entity.toJson(), expected);
      expect(back.entity.toJson().keys.toSet(), expected.keys.toSet());
      expect(back.versions, EntityFieldVersions(v));

      final (data, versions) = await exported(sample.id);
      expect(data, expected);
      expect(data.keys.toSet(), expected.keys.toSet());
      expect(EntityFieldVersions.fromJson(versions), EntityFieldVersions(v));
      // Nested values exactly (maps, arrays, null, a non-ASCII string).
      expect(data['sticker'], raw['sticker']);
      expect(data['layers'], raw['layers']);
      expect(data['futureKey'], '미래');
    },
  );

  test('a remote update of an unknown object is stored as given', () async {
    final u = PageObjectFixtures.unknown(pageId: 'p1', id: 'u1');
    await store.sync.applyRemote([
      upsert(page('p1', 'n1'), remoteAfter(store)),
      upsert(u, remoteAfter(store)),
    ], policy: newerVersionWinsPolicy);
    final v2 = remoteAfter(store);
    final changed = {
      ...u.rawJson,
      'payload': {'fixture': false, 'added': <Object?>[]},
      'newKey': [
        {'deep': true},
      ],
      'updatedAt': 99,
    };
    await store.sync.applyRemote([
      upsert(UnknownObject(changed), v2),
    ], policy: newerVersionWinsPolicy);
    final back = await read('u1');
    expect(back.entity.toJson(), atVersion(changed, v2));
    final (data, _) = await exported('u1');
    expect(data, atVersion(changed, v2));
  });

  test(
    'a known type with an unknown enum name (CP-6) round-trips unchanged',
    () async {
      final shape = PageObjectFixtures.shape(pageId: 'p1', id: 'o1');
      final raw = {...shape.toJson(), 'shape': 'heart'};
      final v = remoteAfter(store);
      final remote = PageObject.fromJson(raw);
      expect(remote, isA<UnknownObject>());
      await store.sync.applyRemote([
        upsert(page('p1', 'n1'), remoteAfter(store)),
        upsert(remote, v),
      ], policy: newerVersionWinsPolicy);
      final back = await read('o1');
      expect(back.entity, isA<UnknownObject>());
      expect((back.entity as PageObject).type, 'shape');
      expect(back.entity.toJson(), atVersion(raw, v));
      final (data, _) = await exported('o1');
      expect(data, atVersion(raw, v));
    },
  );
}
