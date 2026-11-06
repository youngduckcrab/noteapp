// CORE dev_tools seedSyntheticNote (CORE 4.10, 6.2.4) — (v2.0, CORE CP-9) objectsPerPage on
// the fake and the real store: the 17-object mix (shapes of every kind, text boxes, math,
// images of one PNG asset), a grid inside the page, reproducible per seed, argument checks;
// the PNG itself (signature, IHDR, chunk CRCs, zlib stream).
@TestOn('vm')
library;

import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/dev/synthetic_objects.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

Future<List<Stroke>> _strokes(NoteStore store, NoteId noteId) async => [
  for (final p in await store.content.pagesOf(noteId))
    ...(await store.content.loadPage(p.id)).strokes,
];

void main() {
  test(
    'pages: 3, strokesPerPage: 10 → 1 note, 3 pages, 30 strokes with widthQ',
    () async {
      final store = createFakeNoteStore();
      final id = await seedSyntheticNote(
        store,
        pages: 3,
        strokesPerPage: 10,
        pointsPerStroke: 50,
      );
      final note = (await store.library.getNote(id))!;
      expect(note.title, 'perf-test');
      expect(note.pageCount, 3);
      expect(await store.content.pagesOf(id), hasLength(3));
      final strokes = await _strokes(store, id);
      expect(strokes, hasLength(30));
      for (final s in strokes) {
        expect(s.points.length, 50);
        final q = {
          for (var i = 0; i < s.points.length; i++) s.points.widthQ(i),
        };
        expect(q.length, greaterThan(1), reason: 'widthQ channel varies');
        expect(s.points.maxWidthQ, inInclusiveRange(0.05, 1));
        expect(s.version, isNotNull);
      }
      final session = await store.openSession(id);
      expect(session.history.undoDepth, 0, reason: 'seeding is not undoable');
      await session.close();
      await store.close();
    },
  );

  test('the same seed gives the same points', () async {
    final a = createFakeNoteStore();
    final b = createFakeNoteStore();
    final idA = await seedSyntheticNote(
      a,
      pages: 2,
      strokesPerPage: 5,
      seed: 7,
    );
    final idB = await seedSyntheticNote(
      b,
      pages: 2,
      strokesPerPage: 5,
      seed: 7,
    );
    final sa = await _strokes(a, idA);
    final sb = await _strokes(b, idB);
    expect(sa, hasLength(10));
    for (var i = 0; i < sa.length; i++) {
      expect(sa[i].points.contentEquals(sb[i].points), isTrue);
    }
    final c = createFakeNoteStore();
    final idC = await seedSyntheticNote(
      c,
      pages: 2,
      strokesPerPage: 5,
      seed: 8,
    );
    final sc = await _strokes(c, idC);
    expect(sc.first.points.contentEquals(sa.first.points), isFalse);
    await a.close();
    await b.close();
    await c.close();
  });

  test('argument errors', () async {
    final store = createFakeNoteStore();
    await expectLater(seedSyntheticNote(store, pages: 0), throwsArgumentError);
    await expectLater(
      seedSyntheticNote(store, pages: 1, objectsPerPage: -1),
      throwsArgumentError,
    );
    await expectLater(
      seedSyntheticNote(
        store,
        pages: 1,
        objectsPerPage: PageObjectLimits.maxObjectsPerPage + 1,
      ),
      throwsArgumentError,
    );
    expect(
      await store.library.watchRecentNotes().first,
      isEmpty,
      reason: 'checked before anything is written',
    );
    await store.close();
  });

  for (final (name, open) in <(String, Future<NoteStore> Function())>[
    ('fake', () async => createFakeNoteStore()),
    ('real', () => openTestNoteStore(seedDefaultPenPresets: false)),
  ]) {
    group('(CP-9) objectsPerPage on the $name store', () {
      late NoteStore store;
      setUp(() async => store = await open());
      tearDown(() => store.close());

      test(
        '340: every page has 200 shapes (every kind), 100 text boxes, 20 math '
        'and 20 images of one PNG asset, inside the page, after the strokes; '
        'nothing to undo',
        () async {
          final id = await seedSyntheticNote(
            store,
            pages: 2,
            strokesPerPage: 5,
            pointsPerStroke: 20,
            objectsPerPage: 340,
          );
          final assets = await store.assets.listAssets();
          expect(assets, hasLength(1));
          final png = assets.single;
          expect(
            (png.type, png.mimeType, png.size),
            (AssetType.image, 'image/png', syntheticPng().length),
          );
          expect(await store.assets.readBytes(png.id), syntheticPng());
          for (final page in await store.content.pagesOf(id)) {
            final content = await store.content.loadPage(page.id);
            expect(content.strokes, hasLength(5));
            final objects = content.objects;
            expect(objects, hasLength(340));
            final shapes = objects.whereType<ShapeObject>().toList();
            expect(shapes, hasLength(200));
            expect(
              shapes.map((s) => s.shapeKind).toSet(),
              ShapeKind.values.toSet(),
            );
            expect(objects.whereType<TextBoxObject>(), hasLength(100));
            expect(objects.whereType<MathObject>(), hasLength(20));
            final images = objects.whereType<ImageObject>().toList();
            expect(images, hasLength(20));
            for (final image in images) {
              expect(image.assetId, png.id);
              expect((image.pixelWidth, image.pixelHeight), (64, 48));
              final r = image.frame.rect;
              expect(r.width / r.height, closeTo(64 / 48, 1e-9));
            }
            final pageRect = PageRect(0, 0, page.size.width, page.size.height);
            for (final o in objects) {
              expect(o.pageId, page.id);
              final b = o.bounds;
              expect(
                pageRect.containsPoint(b.left, b.top) &&
                    pageRect.containsPoint(b.right, b.bottom),
                isTrue,
                reason: '$o',
              );
              expect(o.version, isNotNull);
            }
            final firstObject = objects
                .map((o) => o.createdAt)
                .reduce((a, b) => a < b ? a : b);
            expect(
              content.strokes.every((s) => s.createdAt < firstObject),
              isTrue,
              reason: 'objects are added after the strokes',
            );
          }
          final session = await store.openSession(id);
          expect(
            session.history.undoDepth,
            0,
            reason: 'seeding is not undoable',
          );
          await session.close();
        },
      );

      test(
        'fewer than 17 objects: no image and no asset; the page limit with no '
        'strokes',
        () async {
          final small = await seedSyntheticNote(
            store,
            pages: 1,
            strokesPerPage: 0,
            objectsPerPage: 16,
          );
          final page = (await store.content.pagesOf(small)).single;
          final objects = (await store.content.loadPage(page.id)).objects;
          expect(objects, hasLength(16));
          expect(objects.whereType<ImageObject>(), isEmpty);
          expect(await store.assets.listAssets(), isEmpty);

          final full = await seedSyntheticNote(
            store,
            pages: 1,
            strokesPerPage: 0,
            objectsPerPage: PageObjectLimits.maxObjectsPerPage,
          );
          final fullPage = (await store.content.pagesOf(full)).single;
          final content = await store.content.loadPage(fullPage.id);
          expect(content.strokes, isEmpty);
          expect(
            content.objects,
            hasLength(PageObjectLimits.maxObjectsPerPage),
          );
        },
      );
    });
  }

  test('(CP-9) the same seed gives the same objects; another seed, other text '
      'and another PNG', () async {
    Future<List<Map<String, Object?>>> objectsOf(int seed) async {
      final store = createFakeNoteStore();
      final id = await seedSyntheticNote(
        store,
        pages: 1,
        strokesPerPage: 0,
        objectsPerPage: 40,
        seed: seed,
      );
      final page = (await store.content.pagesOf(id)).single;
      final objects = (await store.content.loadPage(page.id)).objects;
      await store.close();
      return [
        for (final o in objects)
          Map.of(o.toJson())
            ..remove('id')
            ..remove('pageId')
            ..remove('assetId')
            ..remove('createdAt')
            ..remove('updatedAt')
            ..remove('version'),
      ];
    }

    final a = await objectsOf(3);
    expect(await objectsOf(3), a);
    expect(await objectsOf(4), isNot(a));
    expect(syntheticPng(seed: 3), syntheticPng(seed: 3));
    expect(syntheticPng(seed: 4), isNot(syntheticPng(seed: 3)));
  });

  test('(CP-9) the PNG: signature, IHDR 64 × 48 RGB, CRC of every chunk, zlib '
      'stream of the filtered rows', () {
    expect(crc32('123456789'.codeUnits), 0xCBF43926);
    expect(adler32('Wikipedia'.codeUnits), 0x11E60398);
    final png = syntheticPng(seed: 5);
    expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final data = ByteData.sublistView(png);
    final chunks = <String, Uint8List>{};
    var at = 8;
    while (at < png.length) {
      final length = data.getUint32(at);
      final type = String.fromCharCodes(png.sublist(at + 4, at + 8));
      final body = png.sublist(at + 8, at + 8 + length);
      expect(
        data.getUint32(at + 8 + length),
        crc32(png.sublist(at + 4, at + 8 + length)),
        reason: '$type CRC',
      );
      chunks[type] = body;
      at += 12 + length;
    }
    expect(at, png.length);
    expect(chunks.keys, ['IHDR', 'IDAT', 'IEND']);
    final ihdr = ByteData.sublistView(chunks['IHDR']!);
    expect(
      [for (var i = 8; i < 13; i++) ihdr.getUint8(i)],
      [8, 2, 0, 0, 0], // 8-bit RGB, deflate, filter 0, no interlace
    );
    expect((ihdr.getUint32(0), ihdr.getUint32(4)), (64, 48));
    final rows = ZLibDecoder().convert(chunks['IDAT']!); // checks the Adler-32
    expect(rows, hasLength((1 + 3 * 64) * 48));
    for (var y = 0; y < 48; y++) {
      expect(rows[y * (1 + 3 * 64)], 0, reason: 'row $y filter');
    }
  });
}
