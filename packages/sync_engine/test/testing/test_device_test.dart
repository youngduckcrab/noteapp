// TestDevice edit helpers (T6): the JSON they build has exactly the CORE 6.3 keys, decodes
// with EntityJson.decode, and records the CORE 6.5 changed fields. (2nd round, S2-4b —
// 07-sync 4.3, 6.5) The page object / handwriting / recording helpers: contract keys, and the
// changed fields are exactly the JSON keys whose value changed (CORE C-11).
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/testing.dart';

import '../support/entity_fixtures.dart';

final DateTime start = DateTime.utc(2026, 11, 1);

/// A harness with device 'A' (write log on) inside fakeAsync.
void withDevice(void Function(SyncTestHarness h, TestDevice a) body) {
  fakeAsync((async) {
    final h = SyncTestHarness(
      clock: async.getClock(start),
      elapse: async.elapse,
      flushMicrotasks: async.flushMicrotasks,
    );
    final a = h.device('A');
    a.store.writeLog = [];
    body(h, a);
  }, initialTime: start);
}

/// Writes logged by [body].
List<FakeLocalWrite> logged(TestDevice d, void Function() body) {
  final log = d.store.writeLog!..clear();
  body();
  return List.of(log);
}

void main() {
  test('every helper builds CORE 6.3 JSON that EntityJson.decode accepts', () {
    withDevice((h, a) {
      final f = a.createFolder('F');
      final f2 = a.createFolder('G', parentId: f);
      final n = a.createNote('N', folderId: f, pages: 2);
      final p = a.pageIdsOf(n).first;
      a.renameNote(n, 'N2');
      a.moveNote(n, f2);
      a.moveFolder(f2, null);
      a.trashNote(n);
      a.restoreNote(n);
      a.insertPage(n, afterPageId: p);
      a.deletePage(p);
      final s = a.addStroke(a.pageIdsOf(n).first, seed: 3, points: 20);
      a.recolorStroke(s, 0xFF00AA00);
      a.moveStroke(s, dx: 5, dy: 1);
      a.eraseStroke(s);
      a.seedDefaultPresets();
      a.renamePreset('preset-default-pencil', '샤프');
      a.setSetting('editor.theme', 'dark');
      a.setSetting('editor.theme', 'light');
      a.setSetting('editor.theme', null);
      a.setSetting('editor.theme', 'dark');
      final kinds = <EntityKind>{};
      for (final w in a.store.writeLog!) {
        kinds.add(w.kind);
        final keys = w.json.keys.toSet()..remove('version');
        expect(
          keys,
          kCoreJsonKeys[w.kind]!.difference({'version'}),
          reason: '${w.kind.name} ${w.json}',
        );
        expect(
          () => EntityJson.decode(w.kind, {...w.json, 'version': hlcText(kT0)}),
          returnsNormally,
        );
      }
      expect(kinds, {
        EntityKind.folder,
        EntityKind.note,
        EntityKind.page,
        EntityKind.stroke,
        EntityKind.penPreset,
        EntityKind.setting,
      });
    });
  });

  test('changed fields follow the CORE 6.5 table', () {
    withDevice((h, a) {
      Set<String> fieldsOf(void Function() body) {
        final writes = logged(a, body);
        expect(writes, hasLength(1));
        return writes.single.changedFields;
      }

      final f = a.createFolder('F');
      final g = a.createFolder('G');
      late String n;
      final created = logged(a, () => n = a.createNote('N', pages: 2));
      expect(created.map((w) => w.kind), [
        EntityKind.note,
        EntityKind.page,
        EntityKind.page,
      ]);
      expect(
        created.every((w) => w.changedFields.single == kAllFields),
        isTrue,
      );
      final p = a.pageIdsOf(n).first;
      expect(fieldsOf(() => a.renameNote(n, 'x')), {'title'});
      expect(fieldsOf(() => a.moveNote(n, f)), {'folderId', 'sortKey'});
      expect(fieldsOf(() => a.moveFolder(g, f)), {'parentId', 'sortKey'});
      expect(fieldsOf(() => a.trashNote(n)), {'deletedAt', 'trashRootId'});
      expect(fieldsOf(() => a.restoreNote(n)), {'deletedAt', 'trashRootId'});
      expect(fieldsOf(() => a.insertPage(n)), {kAllFields});
      expect(fieldsOf(() => a.deletePage(p)), {'deletedAt'});
      late String s;
      expect(fieldsOf(() => s = a.addStroke(a.pageIdsOf(n).first)), {
        kAllFields,
      });
      expect(fieldsOf(() => a.recolorStroke(s, 0xFF112233)), {'style'});
      expect(fieldsOf(() => a.moveStroke(s)), {'points'});
      expect(fieldsOf(() => a.eraseStroke(s)), {'deletedAt'});
      a.seedDefaultPresets();
      expect(fieldsOf(() => a.renamePreset('preset-default-marker', 'm')), {
        'name',
      });
      expect(fieldsOf(() => a.setSetting('k.a', 1)), {kAllFields});
      expect(fieldsOf(() => a.setSetting('k.a', 2)), {'valueJson'});
      expect(fieldsOf(() => a.setSetting('k.a', null)), {'deletedAt'});
      expect(fieldsOf(() => a.setSetting('k.a', 3)), {
        'valueJson',
        'deletedAt',
      });

      // Restoring into a trashed folder moves the note to the nearest active ancestor.
      final inner = a.createFolder('inner', parentId: f);
      final m = a.createNote('M', folderId: inner);
      a.trashNote(m);
      a.store.localWrite([
        FakeLocalWrite(
          EntityKind.folder,
          {
            ...a.doc(EntityKind.folder, inner)!.json,
            'deletedAt': 1,
            'trashRootId': inner,
          },
          changedFields: const {'deletedAt', 'trashRootId'},
        ),
      ]);
      expect(fieldsOf(() => a.restoreNote(m)), {
        'deletedAt',
        'trashRootId',
        'folderId',
        'sortKey',
      });
      expect(a.doc(EntityKind.note, m)!.json['folderId'], f);
    });
  });

  test('the store records the changes: outbox fields, hints, new-row *', () {
    withDevice((h, a) {
      final n = a.createNote('N');
      final p = a.pageIdsOf(n).single;
      final s = a.addStroke(p);
      final entries = {for (final e in a.store.outbox) e.entityId: e};
      expect(entries[n]!.changedFields, {kAllFields});
      expect(entries[p]!.noteId, n);
      expect(entries[s]!.noteId, n);
      expect(entries[s]!.pageId, p);
      expect(
        a.store.rows.values.every((r) => r.entity.version == r.versions.max),
        isTrue,
      );
    });
  });

  test('moveFolder refuses a cycle and writes nothing', () {
    withDevice((h, a) {
      final x = a.createFolder('X');
      final y = a.createFolder('Y', parentId: x);
      final z = a.createFolder('Z', parentId: y);
      final before = a.store.canonicalDump();
      expect(() => a.moveFolder(x, z), throwsStateError);
      expect(() => a.moveFolder(x, x), throwsStateError);
      expect(a.store.canonicalDump(), before);
      a.moveFolder(z, null);
      expect(a.doc(EntityKind.folder, z)!.json['parentId'], isNull);
    });
  });

  test('pages: order, insert after, equal-key repair, last page kept', () {
    withDevice((h, a) {
      final n = a.createNote('N', pages: 3);
      final pages = a.pageIdsOf(n);
      expect(pages, hasLength(3));
      final mid = a.insertPage(n, afterPageId: pages[0]);
      expect(a.pageIdsOf(n), [pages[0], mid, pages[1], pages[2]]);
      final last = a.insertPage(n);
      expect(a.pageIdsOf(n).last, last);

      // Two devices inserted after the same page: equal sort keys, ordered by id.
      final twinKey = a.doc(EntityKind.page, mid)!.json['sortKey']! as String;
      final twinId = 'page-zzzz-twin';
      final twin = EntityJson.decode(EntityKind.page, {
        ...a.doc(EntityKind.page, mid)!.json,
        'id': twinId,
        'version': hlcText(kT0 + 1, node: kNodeB),
      });
      h.run(
        a.store.sync.applyRemote([
          RemoteUpsert(twin, EntityFieldVersions(twin.version!)),
        ], policy: (l, r, p) => const TakeRemote()),
      );
      expect(a.pageIdsOf(n).sublist(1, 3), [mid, twinId]);
      final repaired = a.insertPage(n, afterPageId: mid);
      final order = a.pageIdsOf(n);
      expect(order.sublist(1, 4), [mid, repaired, twinId]);
      final keys = [
        for (final id in order)
          a.doc(EntityKind.page, id)!.json['sortKey']! as String,
      ];
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i].compareTo(keys[i - 1]), greaterThan(0), reason: '$keys');
      }
      expect(a.doc(EntityKind.page, mid)!.json['sortKey'], twinKey);

      for (final id in a.pageIdsOf(n).skip(1)) {
        a.deletePage(id);
      }
      expect(a.pageIdsOf(n), hasLength(1));
      expect(() => a.deletePage(a.pageIdsOf(n).single), throwsStateError);
    });
  });

  test('strokes: seeded points, recolor, move, erase, active list', () {
    withDevice((h, a) {
      final n = a.createNote('N');
      final p = a.pageIdsOf(n).single;
      final s1 = a.addStroke(p, seed: 7, points: 30);
      h.elapse(const Duration(milliseconds: 5));
      final s2 = a.addStroke(p, seed: 7, points: 30);
      final s3 = a.addStroke(p, seed: 8, points: 30);
      String points(String id) =>
          a.doc(EntityKind.stroke, id)!.json['points']! as String;
      expect(points(s1), points(s2));
      expect(points(s1), isNot(points(s3)));
      expect(StrokePointsCodec.decodeBase64(points(s1)).length, 30);

      a.recolorStroke(s1, 0x00336699);
      final style = a.doc(EntityKind.stroke, s1)!.json['style']! as Map;
      expect(style['color'], 0xFF336699);
      final before = StrokePointsCodec.decodeBase64(points(s2));
      a.moveStroke(s2, dx: 10, dy: -4);
      final after = StrokePointsCodec.decodeBase64(points(s2));
      expect(after.x(0), closeTo(before.x(0) + 10, 0.011));
      expect(after.y(0), closeTo(before.y(0) - 4, 0.011));

      a.eraseStroke(s3);
      expect([for (final d in a.activeStrokesOf(p)) d.id], [s1, s2]);
      expect(a.doc(EntityKind.stroke, s3)!.isDeleted, isTrue);
    });
  });

  test('trash, restore and purge', () {
    withDevice((h, a) {
      final n = a.createNote('N', pages: 2);
      final p = a.pageIdsOf(n).first;
      final s = a.addStroke(p);
      a.trashNote(n);
      expect(a.doc(EntityKind.note, n)!.isDeleted, isTrue);
      a.restoreNote(n);
      expect(a.doc(EntityKind.note, n)!.isDeleted, isFalse);
      a.purgeNote(n);
      expect(a.doc(EntityKind.note, n), isNull);
      expect(a.doc(EntityKind.page, p), isNull);
      expect(a.doc(EntityKind.stroke, s), isNull);
      final purge = a.store.outbox.single;
      expect(purge.op, OutboxOp.purge);
      expect(purge.entityId, n);
    });
  });

  test('default presets: CORE ids, seed HLC, outbox *, once', () {
    withDevice((h, a) {
      a.seedDefaultPresets();
      a.seedDefaultPresets();
      const seed = Hlc(1, 0, '0000000000000000');
      final presets = [
        for (final r in a.store.rows.values)
          if (r.entity is PenPreset) r,
      ];
      expect(presets.map((r) => r.entity.id).toSet(), {
        'preset-default-ballpoint',
        'preset-default-fountain',
        'preset-default-highlighter',
        'preset-default-pencil',
        'preset-default-marker',
      });
      for (final r in presets) {
        expect(r.versions, const EntityFieldVersions(seed));
        expect(r.entity.version, seed);
      }
      expect(
        a.doc(EntityKind.penPreset, 'preset-default-fountain')!.json['name'],
        '만년필',
      );
      expect(a.store.outbox, hasLength(5));
      expect(
        a.store.outbox.every((e) => e.changedFields.single == kAllFields),
        isTrue,
      );
      expect(a.store.outbox.every((e) => e.hlc == seed), isTrue);
      a.renamePreset('preset-default-pencil', '샤프');
      final renamed =
          a.store.rows[const EntityRef(
            EntityKind.penPreset,
            'preset-default-pencil',
          )]!;
      expect(renamed.versions.of('name') > seed, isTrue);
      expect(renamed.versions.of('style'), seed);
    });
  });

  test('putAsset stores bytes under their sha-256; doc() reads rows', () {
    withDevice((h, a) {
      final bytes = Uint8List.fromList(List.generate(300, (i) => i % 7));
      final id = h.run(a.putAsset(bytes));
      expect(id, sha256.convert(bytes).toString());
      expect(a.doc(EntityKind.asset, id)!.json['size'], 300);
      expect(h.run(a.store.assets.hasBytes(id)), isTrue);
      expect(a.doc(EntityKind.note, 'unknown'), isNull);
    });
  });

  test('goOffline / goOnline switch the link and the connectivity signal', () {
    withDevice((h, a) {
      expect(a.link.online, isTrue);
      expect(a.connectivity.isOnline, isTrue);
      a.goOffline();
      expect(a.link.online, isFalse);
      expect(a.connectivity.isOnline, isFalse);
      a.goOnline();
      expect(a.link.online, isTrue);
      expect(a.connectivity.isOnline, isTrue);
    });
  });

  group('2nd-round helpers (07-sync 4.3)', () {
    /// The one write of [body] (none: null).
    FakeLocalWrite? writeOf(TestDevice d, void Function() body) {
      final writes = logged(d, body);
      expect(writes.length, lessThanOrEqualTo(1));
      return writes.firstOrNull;
    }

    /// Row JSON of [kind] / [id] (version and updatedAt left out).
    Map<String, Object?> rowJson(TestDevice d, EntityKind kind, String id) =>
        Map.of(d.doc(kind, id)!.json)
          ..remove('version')
          ..remove('updatedAt');

    /// C-11: the written fields are the JSON keys whose value changed in the row.
    Set<String> changed(
      TestDevice d,
      EntityKind kind,
      String id,
      void Function() body,
    ) {
      final before = rowJson(d, kind, id);
      final write = writeOf(d, body);
      final after = rowJson(d, kind, id);
      final diff = {
        for (final k in {...before.keys, ...after.keys})
          if (jsonEncode(before[k]) != jsonEncode(after[k]) ||
              before.containsKey(k) != after.containsKey(k))
            k,
      };
      expect(write?.changedFields ?? const <String>{}, diff, reason: 'C-11');
      return diff;
    }

    test('objects: contract keys per type, decodable, defaults of '
        'PageObjectFixtures, {*} on add', () {
      withDevice((h, a) {
        final n = a.createNote('N');
        final p = a.pageIdsOf(n).single;
        final image = h.run(
          a.putAsset(
            Uint8List.fromList(List.generate(64, (i) => i)),
            type: AssetType.image,
            mimeType: 'image/png',
          ),
        );
        for (final type in ['shape', 'text', 'image', 'math']) {
          late String id;
          final write = writeOf(
            a,
            () => id = a.addObject(p, type: type, assetId: image),
          )!;
          expect(write.kind, EntityKind.pageObject);
          expect(write.changedFields, {kAllFields});
          expect(
            write.json.keys.toSet()..remove('version'),
            kPageObjectTypeKeys[type]!.difference({'version'}),
            reason: type,
          );
          final object = EntityJson.decode(EntityKind.pageObject, {
            ...write.json,
            'version': hlcText(kT0),
          });
          expect(object, isA<PageObject>().having((o) => o.type, 'type', type));
          expect(write.json['id'], id);
          expect(write.json['pageId'], p);
        }
        final objects = [for (final d in a.activeObjectsOf(p)) d.toEntity()];
        final shape = objects.whereType<ShapeObject>().single;
        expect(shape.shapeKind, ShapeKind.rectangle);
        expect(shape.frame.bounds, const PageRect(100, 100, 300, 220));
        expect(shape.style.strokeColorArgb, 0xFF1A1A1A);
        expect(
          objects.whereType<TextBoxObject>().single,
          isA<TextBoxObject>()
              .having((o) => o.text, 'text', '안녕 hello')
              .having(
                (o) => o.frame.bounds,
                'rect',
                const PageRect(100, 300, 400, 340),
              ),
        );
        expect(
          objects.whereType<ImageObject>().single,
          isA<ImageObject>()
              .having((o) => o.assetId, 'assetId', image)
              .having((o) => o.pixelWidth, 'w', 400)
              .having((o) => o.pixelHeight, 'h', 300),
        );
        expect(objects.whereType<MathObject>().single.latex, r'\frac{a}{b}');
        // seed moves the rectangle; an image needs an asset; unknown types are refused.
        final moved = a.addObject(p, seed: 2);
        expect(
          a.doc(EntityKind.pageObject, moved)!.toEntity(),
          isA<ShapeObject>().having(
            (o) => o.frame.bounds,
            'rect',
            const PageRect(120, 120, 320, 240),
          ),
        );
        expect(() => a.addObject(p, type: 'image'), throwsArgumentError);
        expect(() => a.addObject(p, type: 'sticker'), throwsArgumentError);
        expect(() => a.addObject('no-page'), throwsStateError);
      });
    });

    test('objects: changed fields are the changed JSON keys (CORE C-11)', () {
      withDevice((h, a) {
        final n = a.createNote('N');
        final p = a.pageIdsOf(n).single;
        final image = h.run(
          a.putAsset(
            Uint8List.fromList(List.generate(64, (i) => i)),
            type: AssetType.image,
            mimeType: 'image/png',
          ),
        );
        final shape = a.addObject(p);
        final text = a.addObject(p, type: 'text');
        final pic = a.addObject(p, type: 'image', assetId: image);
        final math = a.addObject(p, type: 'math');
        const o = EntityKind.pageObject;
        expect(changed(a, o, shape, () => a.moveObject(shape)), {
          'frame',
          'geometry',
        });
        for (final id in [text, pic, math]) {
          expect(changed(a, o, id, () => a.moveObject(id, dy: 5)), {'frame'});
        }
        for (final id in [shape, text, math]) {
          expect(changed(a, o, id, () => a.restyleObject(id, 0x80FF0000)), {
            'style',
          });
        }
        // Normalized like a local command: the alpha is forced to 0xFF.
        expect(
          (a.doc(o, shape)!.toEntity() as ShapeObject).style.strokeColorArgb,
          0xFFFF0000,
        );
        expect(
          changed(a, o, shape, () => a.restyleObject(shape, 0xFFFF0000)),
          isEmpty,
        );
        expect(() => a.restyleObject(pic, 0xFF000000), throwsStateError);
        expect(changed(a, o, text, () => a.editText(text, '새 글')), {'text'});
        expect(changed(a, o, text, () => a.editText(text, '새 글')), isEmpty);
        expect(() => a.editText(math, 'x'), throwsStateError);
        expect(changed(a, o, math, () => a.moveObject(math, dx: 0)), isEmpty);
        expect(changed(a, o, shape, () => a.deleteObject(shape)), {
          'deletedAt',
        });
        expect(changed(a, o, shape, () => a.deleteObject(shape)), isEmpty);
        expect([for (final d in a.activeObjectsOf(p)) d.id], [text, pic, math]);
      });
    });

    test('putRawObject: an unknown type is kept key for key; it cannot be '
        'moved or restyled, only deleted', () {
      withDevice((h, a) {
        final n = a.createNote('N');
        final p = a.pageIdsOf(n).single;
        final raw = {
          'id': 'o-sticker',
          'type': 'sticker',
          'frame': [400.0, 100.0, 450.0, 150.0, 0.0],
          'stickerId': 'cat-01',
          'tint': {
            'argb': 4294940672,
            'stops': [0.0, 0.5, 1.0],
          },
        };
        final write = writeOf(a, () => a.putRawObject(p, raw))!;
        expect(write.changedFields, {kAllFields});
        final doc = a.doc(EntityKind.pageObject, 'o-sticker')!;
        expect(doc.toEntity(), isA<UnknownObject>());
        for (final key in ['stickerId', 'tint', 'frame', 'type']) {
          expect(jsonEncode(doc.json[key]), jsonEncode(raw[key]), reason: key);
        }
        expect(doc.json['pageId'], p);
        expect(doc.json['deletedAt'], isNull);
        const o = EntityKind.pageObject;
        expect(
          changed(a, o, 'o-sticker', () => a.moveObject('o-sticker')),
          isEmpty,
        );
        expect(
          () => a.restyleObject('o-sticker', 0xFF000000),
          throwsStateError,
        );
        // A newer app's rewrite: the keys that changed, a key gone included.
        expect(
          changed(
            a,
            o,
            'o-sticker',
            () => a.putRawObject(
              p,
              {...raw, 'stickerId': 'dog-02'}..remove('tint'),
            ),
          ),
          {'stickerId', 'tint'},
        );
        expect(changed(a, o, 'o-sticker', () => a.deleteObject('o-sticker')), {
          'deletedAt',
        });
        expect(
          a.doc(o, 'o-sticker')!.json['stickerId'],
          'dog-02',
          reason: 'deleting keeps the unknown keys',
        );
        expect(() => a.putRawObject(p, {'type': 'x'}), throwsArgumentError);
      });
    });

    test('handwriting: hw_<pageId>, contract keys, input strokes, the same '
        'value writes nothing, lines only → {lines}', () {
      withDevice((h, a) {
        final n = a.createNote('N');
        final p = a.pageIdsOf(n).single;
        final s = [for (var i = 0; i < 3; i++) a.addStroke(p, seed: i)];
        final write = writeOf(a, () => a.putHandwriting(p, ['가나', 'hello']))!;
        expect(write.kind, EntityKind.handwriting);
        expect(write.changedFields, {kAllFields});
        expect(
          write.json.keys.toSet()..remove('version'),
          kCoreJsonKeys[EntityKind.handwriting]!.difference({'version'}),
        );
        final hw = a.handwritingOf(p)!.toEntity() as HandwritingText;
        expect(hw.id, HandwritingText.idFor(p));
        expect(hw.noteId, n);
        expect(hw.engineId, 'fake');
        expect([for (final l in hw.lines) l.text], ['가나', 'hello']);
        expect(hw.lines[0].strokeIds, [s[0], s[2]]);
        expect(hw.lines[1].strokeIds, [s[1]]);
        final input = [
          for (final id in s)
            a.doc(EntityKind.stroke, id)!.toEntity() as Stroke,
        ];
        expect(hw.sourceRev, HandwritingText.sourceRevOf(input));
        const k = EntityKind.handwriting;
        final id = hw.id;
        expect(
          changed(a, k, id, () => a.putHandwriting(p, ['가나', 'hello'])),
          isEmpty,
        );
        expect(changed(a, k, id, () => a.putHandwriting(p, ['가나', 'world'])), {
          'lines',
        });
        expect(
          changed(a, k, id, () {
            a.putHandwriting(p, ['가나', 'world'], engineId: 'other');
          }),
          {'engineId'},
        );
        a.eraseStroke(s[2]);
        expect(changed(a, k, id, () => a.putHandwriting(p, ['가나', 'world'])), {
          'lines',
          'sourceRev',
          'engineId',
        });
        expect(changed(a, k, id, () => a.removeHandwriting(p)), {'deletedAt'});
        expect(a.handwritingOf(p), isNull);
        expect(changed(a, k, id, () => a.removeHandwriting(p)), isEmpty);
        expect(changed(a, k, id, () => a.putHandwriting(p, ['가나', 'world'])), {
          'deletedAt',
        });
        expect(a.handwritingOf(p), isNotNull);
        expect(
          (a.handwritingOf(p)!.toEntity() as HandwritingText).createdAt,
          hw.createdAt,
          reason: 'createdAt kept from the stored row',
        );
        expect(a.handwritingOf('no-page'), isNull);
        expect(() => a.putHandwriting('no-page', ['x']), throwsStateError);
      });
    });

    test('recordings: audio asset first, contract keys with title, rename '
        '{title}, delete {deletedAt}', () {
      withDevice((h, a) {
        final n = a.createNote('N');
        late String r;
        final writes = logged(a, () => r = h.run(a.addRecording(n)));
        final write = writes.single;
        expect(write.kind, EntityKind.recording);
        expect(write.changedFields, {kAllFields});
        expect(
          write.json.keys.toSet()..remove('version'),
          kCoreJsonKeys[EntityKind.recording]!.difference({'version'}),
        );
        final rec = a.doc(EntityKind.recording, r)!.toEntity() as Recording;
        expect(rec.noteId, n);
        expect(rec.durationMs, 1000);
        expect(rec.title, isNull);
        final asset = a.doc(EntityKind.asset, rec.assetId)!.toEntity() as Asset;
        expect(asset.type, AssetType.audio);
        expect(h.run(a.store.assets.hasBytes(asset.id)), isTrue);
        final other = h.run(
          a.addRecording(n, assetId: asset.id, durationMs: 61000),
        );
        expect(
          (a.doc(EntityKind.recording, other)!.toEntity() as Recording).assetId,
          asset.id,
        );
        const k = EntityKind.recording;
        expect(changed(a, k, r, () => a.renameRecording(r, '  1교시 ')), {
          'title',
        });
        expect(a.doc(k, r)!.json['title'], '1교시');
        expect(changed(a, k, r, () => a.renameRecording(r, '1교시')), isEmpty);
        expect(changed(a, k, r, () => a.renameRecording(r, '  ')), {'title'});
        expect(a.doc(k, r)!.json['title'], isNull);
        expect(changed(a, k, r, () => a.deleteRecording(r)), {'deletedAt'});
        expect(changed(a, k, r, () => a.deleteRecording(r)), isEmpty);
        // Like CORE (02-core 6.6): a deleted recording cannot be renamed.
        expect(() => a.renameRecording(r, '2교시'), throwsStateError);
        expect(a.doc(k, r)!.json['title'], isNull);
      });
    });

    test('outbox hints: objects and handwriting carry noteId and pageId', () {
      withDevice((h, a) {
        final n = a.createNote('N');
        final p = a.pageIdsOf(n).single;
        final o = a.addObject(p);
        a.putHandwriting(p, ['x']);
        final r = h.run(a.addRecording(n));
        final entries = {for (final e in a.store.outbox) e.entityId: e};
        expect((entries[o]!.noteId, entries[o]!.pageId), (n, p));
        final hw = HandwritingText.idFor(p);
        expect((entries[hw]!.noteId, entries[hw]!.pageId), (n, p));
        expect(entries[r]!.noteId, n);
      });
    });
  });
}
