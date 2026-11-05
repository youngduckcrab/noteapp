// CORE T14 — the field version invariant (6.10.2): after every write path (session
// edits, undo / redo, library commands, applyRemote with each decision, commitRepairs,
// markUploaded, reassignOwner, duplicateNoteForRecovery) every touched row has
// version == field_versions.max (overrides only above the base), and readVersioned gives
// entity.version == versions.max. Seeded random walk of 500 steps.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import 'support/sync_support.dart';

const Map<EntityKind, (String, String)> _tables = {
  EntityKind.folder: ('folders', 'id'),
  EntityKind.note: ('notes', 'id'),
  EntityKind.page: ('pages', 'id'),
  EntityKind.stroke: ('strokes', 'id'),
  EntityKind.penPreset: ('pen_presets', 'id'),
  EntityKind.asset: ('assets', 'id'),
  EntityKind.recording: ('recordings', 'id'),
  EntityKind.setting: ('settings', 'key'),
};

/// The stored row of [ref] breaks the invariant: a message, or null when it holds
/// (or the row is gone).
Future<String?> _rowViolation(DriftNoteStore store, EntityRef ref) async {
  final (table, idColumn) = _tables[ref.kind]!;
  final row = await store.db
      .customSelect(
        'SELECT version, field_versions FROM $table WHERE $idColumn = ?',
        variables: [Variable<String>(ref.id)],
      )
      .getSingleOrNull();
  if (row == null) return null;
  final version = Hlc.parse(row.read<String>('version'));
  final column = row.read<String?>('field_versions');
  if (column == null) return null;
  final fv = EntityFieldVersions.fromJson(
    jsonDecode(column) as Map<String, Object?>,
  );
  if (fv.overrides.isEmpty) return '$ref: field_versions without overrides';
  if (fv.max != version) return '$ref: version $version != max ${fv.max}';
  for (final MapEntry(:key, :value) in fv.overrides.entries) {
    if (!(value > fv.base)) return '$ref: override $key not above the base';
  }
  return null;
}

Future<List<EntityRef>> _allRefs(DriftNoteStore store) async => [
  for (final MapEntry(key: kind, value: (table, id)) in _tables.entries)
    for (final r in await store.db.customSelect('SELECT $id FROM $table').get())
      EntityRef(kind, r.read<String>(id)),
];

void main() {
  test('entity.version == versions.max after every step (500 steps)', () async {
    final store = await openStore();
    addTearDown(store.close);
    final rnd = Random(20261105);
    final touched = <EntityRef>{};
    final sub = store.changes.listen((b) {
      for (final c in b.changes) {
        if (!c.purged) touched.add(EntityRef(c.kind, c.id));
      }
    });
    addTearDown(sub.cancel);

    // Start: a folder, the session note (2 pages, loaded), another note, an asset.
    final start = await store.library.createFolder(name: 'start');
    final main = await store.library.createNote(
      title: 'main',
      pages: const [PageDraft.blankA4, PageDraft.blankA4],
    );
    await store.library.createNote(title: 'other', folderId: start.id);
    final asset = await store.assets.put(
      Uint8List.fromList([1, 2, 3, 4]),
      type: AssetType.image,
      mimeType: 'image/png',
    );
    final session = await store.openSession(main.id);
    for (final p in session.pages) {
      await session.openPage(p.id);
    }
    var owner = 0;
    var seed = 0;

    T pick<T>(List<T> items) => items[rnd.nextInt(items.length)];

    List<Page> loaded() => [
      for (final p in session.pages)
        if (session.pageIfLoaded(p.id) != null) p,
    ];

    Future<List<String>> ids(String table, {String where = '1'}) async => [
      for (final r
          in await store.db
              .customSelect('SELECT id FROM $table WHERE $where')
              .get())
        r.read<String>('id'),
    ];

    Future<EntityRef?> randomRef() async {
      final kind = pick(const [
        EntityKind.folder,
        EntityKind.note,
        EntityKind.page,
        EntityKind.stroke,
      ]);
      final list = await ids(_tables[kind]!.$1);
      return list.isEmpty ? null : EntityRef(kind, pick(list));
    }

    /// A remote record of [v] with one field newer (or older) than the local one.
    RemoteUpsert remoteOf(VersionedEntity v) {
      final json = v.entity.toJson();
      final String field;
      switch (v.entity.kind) {
        case EntityKind.note:
          field = 'title';
          json[field] = 'remote ${seed++}';
        case EntityKind.folder:
          field = 'name';
          json[field] = 'remote ${seed++}';
        case EntityKind.page:
          field = 'background';
        default:
          field = 'style';
      }
      final rv = rnd.nextBool()
          ? remoteAfter(store, 1 + rnd.nextInt(5))
          : Hlc(v.versions.base.millis + 1, 0, kRemoteNode);
      final versions = EntityFieldVersions(v.versions.base, {
        for (final MapEntry(:key, :value) in v.versions.overrides.entries)
          if (key != field) key: value,
        if (rv > v.versions.base) field: rv,
      });
      json['version'] = versions.max.toString();
      return RemoteUpsert(EntityJson.decode(v.entity.kind, json), versions);
    }

    final ops = <String, Future<void> Function()>{
      'add strokes': () async {
        final p = pick(loaded());
        await session
            .execute(
              AddStrokes(
                pageId: p.id,
                strokes: [
                  for (var i = 0; i < 1 + rnd.nextInt(3); i++)
                    StrokeFixtures.synthetic(
                      pageId: p.id,
                      ids: store.ids,
                      seed: seed++,
                      pointCount: 8,
                    ),
                ],
              ),
            )
            .persisted;
      },
      'remove strokes': () async {
        final p = pick(loaded());
        final strokes = session.pageIfLoaded(p.id)!.strokes;
        if (strokes.isEmpty) return;
        await session
            .execute(RemoveStrokes(pageId: p.id, strokeIds: [pick(strokes).id]))
            .persisted;
      },
      'restyle strokes': () async {
        final p = pick(loaded());
        final strokes = session.pageIfLoaded(p.id)!.strokes;
        if (strokes.isEmpty) return;
        await session
            .execute(
              RestyleStrokes(
                pageId: p.id,
                strokeIds: [pick(strokes).id],
                patch: StrokeStylePatch(colorArgb: 0xFF000000 + seed++),
              ),
            )
            .persisted;
      },
      'insert page': () async {
        await session
            .execute(
              const InsertPages(
                drafts: [PageDraft.blankA4],
                position: PageAtEnd(),
              ),
            )
            .persisted;
        await session.openPage(session.pages.last.id);
      },
      'delete page': () async {
        if (session.pages.length < 2) return;
        await session
            .execute(DeletePages(pageIds: [pick(session.pages).id]))
            .persisted;
      },
      'undo': () async => session.undo(),
      'redo': () async => session.redo(),
      'create note': () async {
        await store.library.createNote(title: 'n${seed++}');
      },
      'create folder': () async {
        await store.library.createFolder(name: 'f${seed++}');
      },
      'rename note': () async {
        final list = await ids('notes', where: 'deleted_at IS NULL');
        await store.library.renameNote(pick(list), 'renamed ${seed++}');
      },
      'favorite': () async {
        final list = await ids('notes', where: 'deleted_at IS NULL');
        await store.library.setFavorite([pick(list)], rnd.nextBool());
      },
      'move note': () async {
        final notes = await ids('notes', where: 'deleted_at IS NULL');
        final folders = await ids('folders', where: 'deleted_at IS NULL');
        await store.library.moveItems([
          NoteRef(pick(notes)),
        ], targetFolderId: rnd.nextBool() ? null : pick(folders));
      },
      'trash and restore': () async {
        final notes = await ids(
          'notes',
          where: "deleted_at IS NULL AND id != '${main.id}'",
        );
        if (notes.isEmpty) return;
        final ref = NoteRef(pick(notes));
        await store.library.trashItems([ref]);
        if (rnd.nextBool()) await store.trash.restore([ref]);
      },
      'applyRemote': () async {
        final ref = await randomRef();
        final changes = <RemoteChange>[
          upsert(folder(store.ids.newId(), name: 'cloud'), remoteAfter(store)),
        ];
        if (ref != null) {
          final v = (await store.sync.readVersioned([ref])).single;
          if (v != null) changes.add(remoteOf(v));
        }
        final MergeDecision Function(
          VersionedEntity?,
          VersionedEntity,
          Set<String>?,
        )
        policy = switch (rnd.nextInt(3)) {
          0 => (_, _, _) => const KeepLocal(),
          1 => (_, _, _) => TakeRemote(dropPendingLocal: rnd.nextBool()),
          _ => fieldLwwPolicy(),
        };
        await store.sync.applyRemote(changes, policy: policy);
      },
      'commitRepairs': () async {
        final ref = await randomRef();
        if (ref == null) return;
        final v = (await store.sync.readVersioned([ref])).single!;
        final field = switch (ref.kind) {
          EntityKind.note => 'title',
          EntityKind.folder => 'name',
          EntityKind.page => 'background',
          _ => 'style',
        };
        await store.sync.commitRepairs([
          (entity: v.entity, fields: {field}),
        ]);
      },
      'markUploaded': () => store.assets.markUploaded(
        asset.id,
        'users/u/assets/${asset.id}#${seed++}',
      ),
      'reassignOwner': () async {
        final to = 'owner-${++owner}';
        await store.sync.reassignOwner(from: store.ownerId, to: to);
      },
      'duplicate': () async {
        final list = await ids('notes');
        await store.sync.duplicateNoteForRecovery(
          pick(list),
          titleSuffix: ' (${seed++})',
        );
      },
      'acknowledge': () async {
        final pending = await store.sync.pendingChanges(limit: 20);
        await store.sync.acknowledge([for (final e in pending) e.ack]);
      },
    };
    final names = ops.keys.toList();
    final ran = <String, int>{};

    Future<void> check(Iterable<EntityRef> refs, String step) async {
      final list = refs.toList();
      for (final ref in list) {
        expect(await _rowViolation(store, ref), isNull, reason: step);
      }
      final read = await store.sync.readVersioned(list);
      for (final v in read) {
        if (v != null) {
          expect(v.entity.version, v.versions.max, reason: step);
        }
      }
    }

    for (var step = 0; step < 500; step++) {
      final name = pick(names);
      try {
        await ops[name]!();
        ran.update(name, (n) => n + 1, ifAbsent: () => 1);
      } on ArgumentError {
        // a command refused for the current state (e.g. a page not loaded)
      } on StateError {
        // ditto
      } on NoteCoreException {
        // ditto
      }
      await pumpEventQueue(times: 2);
      await check(touched, 'step $step ($name)');
      touched.clear();
      if (step % 50 == 49) await check(await _allRefs(store), 'all @ $step');
    }
    await session.close();
    await check(await _allRefs(store), 'all at the end');
    expect(ran.keys.toSet(), names.toSet(), reason: 'every path ran: $ran');
  });
}
