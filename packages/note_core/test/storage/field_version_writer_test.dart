// CORE T7 — field versions of local writes (6.10.2) and the row mappers.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/field_version_writer.dart';
import 'package:note_core/src/storage/row_mappers.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';
import 'storage_support.dart';

const Hlc _h1 = Hlc(100, 0, kTestNode);
const Hlc _h2 = Hlc(200, 0, kTestNode);
const Hlc _h3 = Hlc(300, 0, kTestNode);

void main() {
  group('localVersionsAfter', () {
    test('* or a new row → only a base (column NULL)', () {
      final a = localVersionsAfter(null, {'title'}, _h1);
      expect(a, const EntityFieldVersions(_h1));
      expect(fieldVersionsColumn(a), isNull);
      final b = localVersionsAfter(
        const EntityFieldVersions(_h1, {'title': _h2}),
        {kAllFields},
        _h3,
      );
      expect(b, const EntityFieldVersions(_h3));
      expect(fieldVersionsColumn(b), isNull);
    });

    test('partial fields → overrides on the current base; max = the stamp', () {
      final a = localVersionsAfter(const EntityFieldVersions(_h1), {
        'title',
      }, _h2);
      expect(a.base, _h1);
      expect(a.overrides, {'title': _h2});
      expect(a.max, _h2);
      expect(fieldVersionsColumn(a), isNotNull);
      final b = localVersionsAfter(a, {'tags'}, _h3);
      expect(b.of('title'), _h2);
      expect(b.of('tags'), _h3);
      expect(b.of('cover'), _h1);
      expect(b.max, _h3);
    });
  });

  group('rows', () {
    test('every sample entity round-trips through its row', () async {
      final store = await openStore();
      addTearDown(store.close);
      for (final MapEntry(key: name, value: e) in kSampleEntities.entries) {
        final versions = EntityFieldVersions(e.version!);
        await writeEntityRow(store.db, e, versions);
        final back = await readVersionedRow(store.db, EntityRef(e.kind, e.id));
        expect(back, isNotNull, reason: name);
        expect(back!.versions, versions, reason: name);
        expect(back.entity.toJson(), e.toJson(), reason: name);
      }
    });

    test('version column = versions.max; overrides kept as JSON', () async {
      final store = await openStore();
      addTearDown(store.close);
      const v = EntityFieldVersions(_h1, {'name': _h3, 'icon': _h2});
      await writeEntityRow(store.db, folder('f1'), v);
      final back = await readVersionedRow(
        store.db,
        const EntityRef(EntityKind.folder, 'f1'),
      );
      expect(back!.versions, v);
      expect(back.entity.version, _h3);
      final row = await store.db
          .customSelect('SELECT version, field_versions FROM folders')
          .getSingle();
      expect(row.read<String>('version'), _h3.toString());
      expect(row.read<String?>('field_versions'), contains('"o"'));
    });

    test('a damaged field_versions column is recovered from version', () async {
      final store = await openStore();
      addTearDown(store.close);
      await writeEntityRow(
        store.db,
        folder('f1'),
        const EntityFieldVersions(_h1, {'name': _h2}),
      );
      await store.db.customStatement(
        "UPDATE folders SET field_versions = '{\"b\": \"bad\"}'",
      );
      final back = await readVersionedRow(
        store.db,
        const EntityRef(EntityKind.folder, 'f1'),
      );
      expect(back!.versions, const EntityFieldVersions(_h2));
      expect(back.entity.version, back.versions.max);
    });

    test('keepLocal keeps local-only columns of an existing row', () async {
      final store = await openStore();
      addTearDown(store.close);
      await writeEntityRow(
        store.db,
        note('n1', pageCount: 4),
        const EntityFieldVersions(_h1),
      );
      await writeEntityRow(
        store.db,
        note('n1', title: 'remote'),
        const EntityFieldVersions(_h2),
        keepLocal: true,
      );
      final back = await readVersionedRow(
        store.db,
        const EntityRef(EntityKind.note, 'n1'),
      );
      final n = back!.entity as Note;
      expect(n.title, 'remote');
      expect(n.pageCount, 4);
    });
  });
}
