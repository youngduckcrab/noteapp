// TestDevice edit helpers (T6): the JSON they build has exactly the CORE 6.3 keys, decodes
// with EntityJson.decode, and records the CORE 6.5 changed fields.
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
}
