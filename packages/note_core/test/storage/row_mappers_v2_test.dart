// CORE T26 — DB v2 row mappers (m5-7/02-core 6.11, 6.13, 8.2): page_objects / handwriting /
// recordings.title rows ↔ entities, UnknownObject keys kept (C-12), data_json without the
// column keys, derived columns (page_objects bounds / asset_id, pages.bg_*) written on every
// write, the page cache columns (ink_rev / ink_rev_at) never touched by an entity write.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/row_mappers.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';
import 'storage_support.dart';

const Hlc _h1 = Hlc(100, 0, kTestNode);
const Hlc _h2 = Hlc(200, 0, kTestNode);
const Hlc _h3 = Hlc(300, 0, kTestNode);
const String _assetA =
    '1111111111111111111111111111111111111111111111111111111111111111';
const String _assetB =
    '2222222222222222222222222222222222222222222222222222222222222222';

void main() {
  late DriftNoteStore store;
  setUp(() async => store = await openStore());
  tearDown(() => store.close());

  NoteDatabase db() => store.db;

  Future<VersionedEntity?> read(EntityKind kind, String id) =>
      readVersionedRow(db(), EntityRef(kind, id));

  Future<PageObjectRow> objectRow(String id) => (db().select(
    db().pageObjects,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<PageRow> pageRow(String id) =>
      (db().select(db().pages)..where((t) => t.id.equals(id))).getSingle();

  group('page_objects', () {
    test('every object sample round-trips through its row', () async {
      for (final MapEntry(key: name, value: o) in kSampleObjects.entries) {
        final versions = EntityFieldVersions(o.version!);
        await writeEntityRow(db(), o, versions, strokeNoteId: 'n1');
        final back = await read(EntityKind.pageObject, o.id);
        expect(back, isNotNull, reason: name);
        expect(back!.versions, versions, reason: name);
        expect(back.entity, o, reason: name);
        expect(back.entity.toJson(), o.toJson(), reason: name);
        expect(back.entity.runtimeType, o.runtimeType, reason: name);
      }
      final page = await readVersionedPage(
        db(),
        EntityKind.pageObject,
        limit: 100,
      );
      expect([
        for (final v in page) v.entity.id,
      ], [for (final o in kSampleObjects.values) o.id]..sort());
    });

    test('field versions with overrides survive the row', () async {
      final o = PageObjectFixtures.textBox(pageId: 'p1', id: 'o1');
      const v = EntityFieldVersions(_h1, {'text': _h3, 'style': _h2});
      await writeEntityRow(db(), o.copyWithMeta(version: _h3), v);
      final back = (await read(EntityKind.pageObject, 'o1'))!;
      expect(back.versions, v);
      expect(back.entity.version, _h3);
      final row = await objectRow('o1');
      expect(row.version, _h3.toString());
      expect(row.fieldVersions, contains('"o"'));
    });

    test('an UnknownObject keeps every key and value (C-12)', () async {
      final u = kSampleObjects['unknown']! as UnknownObject;
      await writeEntityRow(db(), u, EntityFieldVersions(u.version!));
      final back = (await read(EntityKind.pageObject, u.id))!.entity;
      expect(back, isA<UnknownObject>());
      final json = back.toJson();
      expect(json.keys.toSet(), u.toJson().keys.toSet());
      expect(jsonEncode(json), jsonEncode(u.toJson()), reason: 'same order');
      expect((back as UnknownObject).rawJson, u.rawJson);
      expect(back.frame, u.frame);

      // A fixture unknown object (version null in its rawJson) gets the row's version.
      final f = PageObjectFixtures.unknown(pageId: 'p1', id: 'u2');
      await writeEntityRow(db(), f, const EntityFieldVersions(_h1));
      final fb = (await read(EntityKind.pageObject, 'u2'))!.entity;
      expect(fb.toJson(), {...f.toJson(), 'version': _h1.toString()});
    });

    test('data_json has no column key; the columns hold them', () async {
      for (final o in kSampleObjects.values) {
        await writeEntityRow(
          db(),
          o,
          EntityFieldVersions(o.version!),
          strokeNoteId: 'n1',
        );
        final row = await objectRow(o.id);
        final data = jsonDecode(row.dataJson) as Map<String, Object?>;
        final expected = {...o.toJson()}
          ..removeWhere((k, _) => kObjectColumnKeys.contains(k));
        expect(data.keys.toSet().intersection(kObjectColumnKeys), isEmpty);
        expect(data, expected, reason: o.type);
        expect(data.containsKey('frame'), isTrue, reason: 'every type');
        expect(
          (row.id, row.pageId, row.noteId, row.type),
          (o.id, o.pageId, 'n1', o.type),
        );
        expect(
          (row.createdAt, row.updatedAt, row.deletedAt),
          (o.createdAt, o.updatedAt, o.deletedAt),
        );
        final b = o.bounds;
        expect(
          (row.minX, row.minY, row.maxX, row.maxY),
          (b.left, b.top, b.right, b.bottom),
          reason: '${o.type} bounds',
        );
      }
    });

    test(
      'asset_id: an image, an unknown object with an AssetId, else NULL',
      () async {
        final image = PageObjectFixtures.image(
          pageId: 'p1',
          assetId: _assetA,
          id: 'img',
        );
        final withAsset = UnknownObject({
          ...PageObjectFixtures.unknown(pageId: 'p1', id: 'u1').rawJson,
          'assetId': _assetB,
        });
        final notAnAsset = UnknownObject({
          ...PageObjectFixtures.unknown(pageId: 'p1', id: 'u2').rawJson,
          'assetId': 'not-a-sha256',
        });
        final shape = PageObjectFixtures.shape(pageId: 'p1', id: 'sh');
        for (final o in [image, withAsset, notAnAsset, shape]) {
          await writeEntityRow(db(), o, const EntityFieldVersions(_h1));
        }
        expect((await objectRow('img')).assetId, _assetA);
        expect((await objectRow('u1')).assetId, _assetB);
        expect((await objectRow('u2')).assetId, isNull);
        expect((await objectRow('sh')).assetId, isNull);
      },
    );

    test(
      'an update rewrites the derived columns; delete removes the row',
      () async {
        final o = PageObjectFixtures.textBox(pageId: 'p1', id: 'o1');
        await writeEntityRow(db(), o, const EntityFieldVersions(_h1));
        final moved = o.transformed(Affine2.translation(10, 20));
        await writeEntityRow(db(), moved, const EntityFieldVersions(_h2));
        final row = await objectRow('o1');
        expect(row.minX, moved.bounds.left);
        expect(row.minY, moved.bounds.top);
        expect(
          ((await read(EntityKind.pageObject, 'o1'))!.entity as PageObject)
              .bounds,
          moved.bounds,
        );

        expect(
          await deleteEntityRow(
            db(),
            const EntityRef(EntityKind.pageObject, 'o1'),
          ),
          isTrue,
        );
        expect(await read(EntityKind.pageObject, 'o1'), isNull);
        expect(
          await deleteEntityRow(
            db(),
            const EntityRef(EntityKind.pageObject, 'o1'),
          ),
          isFalse,
        );
      },
    );
  });

  group('handwriting', () {
    test('the sample round-trips through its row', () async {
      final h = kSampleHandwriting;
      final versions = EntityFieldVersions(h.version!, const {'lines': _h1});
      await writeEntityRow(db(), h.copyWith(version: versions.max), versions);
      final back = (await read(EntityKind.handwriting, h.id))!;
      expect(back.entity, h.copyWith(version: versions.max));
      expect(back.versions, versions);
      final row = await db().select(db().handwriting).getSingle();
      expect(
        (row.id, row.pageId, row.noteId, row.engineId, row.sourceRev),
        (h.id, h.pageId, h.noteId, h.engineId, h.sourceRev),
      );
      expect(jsonDecode(row.linesJson), h.toJson()['lines']);
      final page = await readVersionedPage(
        db(),
        EntityKind.handwriting,
        after: 'hw_',
        limit: 10,
      );
      expect([for (final v in page) v.entity.id], [h.id]);
      expect(
        await deleteEntityRow(db(), EntityRef(EntityKind.handwriting, h.id)),
        isTrue,
      );
      expect(await read(EntityKind.handwriting, h.id), isNull);
    });
  });

  group('recordings.title', () {
    test('a title and no title both round-trip', () async {
      final titled = recording('r1', 'n1').copyWith(title: '1교시');
      final untitled = recording('r2', 'n1');
      for (final r in [titled, untitled]) {
        await writeEntityRow(
          db(),
          r.copyWith(version: _h1),
          const EntityFieldVersions(_h1),
        );
      }
      expect(
        ((await read(EntityKind.recording, 'r1'))!.entity as Recording).title,
        '1교시',
      );
      expect(
        ((await read(EntityKind.recording, 'r2'))!.entity as Recording).title,
        isNull,
      );
      // Clearing the title writes NULL (the column is not kept on update).
      await writeEntityRow(
        db(),
        titled.copyWith(clearTitle: true, version: _h2),
        const EntityFieldVersions(_h2),
      );
      final rows = await db().select(db().recordings).get();
      expect({for (final r in rows) r.id: r.title}, {'r1': null, 'r2': null});
    });
  });

  group('pages: bg_* derived on every write, ink_rev cache kept', () {
    test('pdf → asset and index, image → asset, others → NULL', () async {
      final p = page('p1', 'n1');
      final cases = <(PageBackground, String?, int?)>[
        (const PdfBackground(assetId: _assetA, pdfPageIndex: 7), _assetA, 7),
        (const ImageBackground(assetId: _assetB), _assetB, null),
        (
          TemplateBackground(
            template: PageTemplate.defaults(PageTemplateKind.grid),
          ),
          null,
          null,
        ),
        (const PdfBackground(assetId: _assetB, pdfPageIndex: 0), _assetB, 0),
        (const BlankBackground(), null, null),
      ];
      var keepLocal = false;
      for (final (bg, asset, index) in cases) {
        // Alternates plain and keepLocal (remote / repair) writes.
        await writeEntityRow(
          db(),
          p.copyWith(background: bg),
          const EntityFieldVersions(_h1),
          keepLocal: keepLocal,
        );
        keepLocal = !keepLocal;
        final row = await pageRow('p1');
        expect((row.bgAssetId, row.bgPdfIndex), (asset, index), reason: '$bg');
      }
    });

    test('local and remote page writes fill bg_*', () async {
      final local = page('p1', 'n1').copyWith(
        background: const PdfBackground(assetId: _assetA, pdfPageIndex: 2),
      );
      await store.queue.run((tx) => tx.putLocal(local, const {kAllFields}));
      expect(
        ((await pageRow('p1')).bgAssetId, (await pageRow('p1')).bgPdfIndex),
        (_assetA, 2),
      );
      final remote = page(
        'p2',
        'n1',
      ).copyWith(background: const ImageBackground(assetId: _assetB));
      await store.queue.run(
        (tx) => tx.putRemote(remote, const EntityFieldVersions(_h3)),
        origin: ChangeOrigin.remote,
      );
      expect(
        ((await pageRow('p2')).bgAssetId, (await pageRow('p2')).bgPdfIndex),
        (_assetB, null),
      );
      await store.queue.run(
        (tx) => tx.putLocal(
          local.copyWith(background: const BlankBackground()),
          const {'background'},
        ),
      );
      expect(
        ((await pageRow('p1')).bgAssetId, (await pageRow('p1')).bgPdfIndex),
        (null, null),
      );
    });

    test('a new page has no ink_rev; an entity write keeps it', () async {
      final p = page('p1', 'n1');
      await writeEntityRow(db(), p, const EntityFieldVersions(_h1));
      var row = await pageRow('p1');
      expect((row.inkRev, row.inkRevAt), (null, null));
      await (db().update(db().pages)..where((t) => t.id.equals('p1'))).write(
        const PagesCompanion(
          inkRev: Value('0123456789abcdef'),
          inkRevAt: Value(0),
        ),
      );
      await writeEntityRow(
        db(),
        p.copyWith(sortKey: 'b0', contentRevision: 3),
        const EntityFieldVersions(_h2),
      );
      await writeEntityRow(
        db(),
        p.copyWith(sortKey: 'c0'),
        const EntityFieldVersions(_h3),
        keepLocal: true,
      );
      row = await pageRow('p1');
      expect((row.inkRev, row.inkRevAt), ('0123456789abcdef', 0));
      expect((row.sortKey, row.contentRev), ('c0', 3));
    });
  });

  group('(C211-01) strokes with a pen this version does not know', () {
    test('the row keeps the original name and decodes as ballpoint', () async {
      final sample = kSampleEntities['stroke']! as Stroke;
      final stroke = sample.copyWith(
        version: _h1,
        style: StrokeStyle.fromJson({
          ...sample.style.toJson(),
          'tool': 'stamp',
        }),
      );
      expect(stroke.style.tool, PenTool.ballpoint);
      final versions = EntityFieldVersions(_h1);
      await writeEntityRow(db(), stroke, versions, strokeNoteId: 'n1');
      final row = await (db().select(
        db().strokes,
      )..where((t) => t.id.equals(stroke.id))).getSingle();
      expect(row.tool, 'stamp');
      final back = await read(EntityKind.stroke, stroke.id);
      expect(back!.entity, stroke);
      expect((back.entity as Stroke).style.wireToolName, 'stamp');
    });
  });
}
