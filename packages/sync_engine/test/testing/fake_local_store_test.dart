// FakeLocalStore beyond the shared contract suite (T6): localWrite, localPurge, markOpened,
// failNextWrites, canonicalDump. Plain async tests on a hand-moved clock (the fake completes
// in microtasks).
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/testing.dart';

const String node = 'a1a1a1a1a1a1a1a1';
final DateTime start = DateTime.utc(2026, 11, 1, 9);

final class ManualClock {
  DateTime now = start;
  late final Clock clock = Clock(() => now);
  int get millis => now.millisecondsSinceEpoch;
  void advance(Duration d) => now = now.add(d);
}

FakeLocalWrite folderWrite(
  String id, {
  String? parentId,
  String? trashRootId,
}) => FakeLocalWrite(
  EntityKind.folder,
  {
    'id': id,
    'ownerId': 'local',
    'parentId': parentId,
    'name': id,
    'color': null,
    'icon': null,
    'sortKey': 'a0',
    'createdAt': 1,
    'deletedAt': trashRootId == null ? null : 2,
    'trashRootId': trashRootId,
  },
  changedFields: const {kAllFields},
);

FakeLocalWrite noteWrite(
  String id, {
  String title = 'n',
  String? folderId,
  String? trashRootId,
  Set<String> fields = const {kAllFields},
}) => FakeLocalWrite(EntityKind.note, {
  'id': id,
  'ownerId': 'local',
  'folderId': folderId,
  'title': title,
  'cover': {'type': 'firstPage'},
  'tags': <String>[],
  'isFavorite': false,
  'sortKey': 'a0',
  'schemaVersion': 1,
  'createdAt': 1,
  'deletedAt': trashRootId == null ? null : 2,
  'trashRootId': trashRootId,
}, changedFields: fields);

FakeLocalWrite pageWrite(
  String id,
  String noteId, {
  String sortKey = 'a0',
  int? deletedAt,
  Set<String> fields = const {kAllFields},
}) => FakeLocalWrite(EntityKind.page, {
  'id': id,
  'noteId': noteId,
  'sortKey': sortKey,
  'size': [595.2756, 841.8898],
  'background': {'type': 'blank', 'paperColor': 4294967295},
  'createdAt': 1,
  'deletedAt': deletedAt,
}, changedFields: fields);

FakeLocalWrite strokeWrite(String id, String pageId) => FakeLocalWrite(
  EntityKind.stroke,
  {
    'id': id,
    'pageId': pageId,
    'style': StrokeStyle.defaultsFor(PenTool.pencil).toJson(),
    'points': 'AQED0A9klgGgHzIA9AMyMgBUUg==',
    'recordingId': null,
    'recordingOffsetMs': null,
    'createdAt': 1,
    'deletedAt': null,
  },
  changedFields: const {kAllFields},
);

FakeLocalWrite recordingWrite(String id, String noteId) => FakeLocalWrite(
  EntityKind.recording,
  {
    'id': id,
    'noteId': noteId,
    'assetId':
        'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a',
    'durationMs': 1000,
    'startedAt': 1,
    'createdAt': 1,
    'deletedAt': null,
  },
  changedFields: const {kAllFields},
);

void main() {
  late ManualClock clock;
  late FakeLocalStore store;

  setUp(() {
    clock = ManualClock();
    store = FakeLocalStore(nodeId: node, clock: clock.clock);
  });

  VersionedEntity row(EntityKind kind, String id) =>
      store.rows[EntityRef(kind, id)]!;
  OutboxEntry? entry(EntityKind kind, String id) =>
      store.outbox.where((e) => e.kind == kind && e.entityId == id).firstOrNull;
  Note note(String id) => row(EntityKind.note, id).entity as Note;
  Page page(String id) => row(EntityKind.page, id).entity as Page;

  Future<int> eventsDuring(void Function() body) async {
    var count = 0;
    final sub = store.localChanges.listen((_) => count++);
    body();
    await pumpEventQueue();
    await sub.cancel();
    return count;
  }

  test('rejects a node id that is not 16 lowercase hex', () {
    expect(
      () => FakeLocalStore(nodeId: 'ABC', clock: clock.clock),
      throwsArgumentError,
    );
  });

  group('localWrite', () {
    test('one HLC per call on this node; version and updatedAt set; new rows '
        'queue *', () async {
      final events = await eventsDuring(
        () => store.localWrite([noteWrite('n1'), pageWrite('p1', 'n1')]),
      );
      expect(events, 1);
      final n = row(EntityKind.note, 'n1');
      final p = row(EntityKind.page, 'p1');
      expect(n.entity.version, p.entity.version);
      expect(n.entity.version!.nodeId, node);
      expect(n.versions, EntityFieldVersions(n.entity.version!));
      expect(note('n1').updatedAt, clock.millis);
      expect(page('p1').updatedAt, clock.millis);
      expect(entry(EntityKind.note, 'n1')!.changedFields, {kAllFields});
      expect(entry(EntityKind.page, 'p1')!.noteId, 'n1');
      expect(
        entry(EntityKind.note, 'n1')!.seq,
        lessThan(entry(EntityKind.page, 'p1')!.seq),
      );
    });

    test('stamps only the changed fields and merges the outbox entry', () {
      store.localWrite([noteWrite('n1')]);
      final created = row(EntityKind.note, 'n1');
      final first = entry(EntityKind.note, 'n1')!;
      clock.advance(const Duration(seconds: 1));
      store.localWrite([
        noteWrite('n1', title: 'renamed', fields: const {'title'}),
      ]);
      final renamed = row(EntityKind.note, 'n1');
      expect(renamed.versions.base, created.versions.base);
      expect(renamed.versions.overrides.keys, ['title']);
      expect(renamed.entity.version, renamed.versions.max);
      final merged = entry(EntityKind.note, 'n1')!;
      expect(merged.seq, first.seq);
      expect(merged.rev, first.rev + 1);
      expect(merged.changedFields, {kAllFields});
      expect(merged.hlc, renamed.versions.max);
    });

    test('a stroke bumps its note updatedAt without outbox (C-9) and its page '
        'contentRevision once per call; new pages start at 0', () async {
      store.localWrite([noteWrite('n1'), pageWrite('p1', 'n1')]);
      expect(page('p1').contentRevision, 0);
      final noteBefore = row(EntityKind.note, 'n1');
      await store.sync.acknowledge([entry(EntityKind.note, 'n1')!.ack]);
      clock.advance(const Duration(minutes: 1));
      store.localWrite([strokeWrite('s1', 'p1'), strokeWrite('s2', 'p1')]);
      expect(note('n1').updatedAt, clock.millis);
      expect(row(EntityKind.note, 'n1').versions, noteBefore.versions);
      expect(entry(EntityKind.note, 'n1'), isNull);
      expect(page('p1').contentRevision, 1);
      final s1 = entry(EntityKind.stroke, 's1')!;
      expect(s1.noteId, 'n1');
      expect(s1.pageId, 'p1');
    });

    test('recomputes pageCount / firstPageId and keeps lastOpenedAt', () {
      store.localWrite([
        noteWrite('n1'),
        pageWrite('p2', 'n1', sortKey: 'a1'),
        pageWrite('p1', 'n1', sortKey: 'a0'),
      ]);
      expect(note('n1').pageCount, 2);
      expect(note('n1').firstPageId, 'p1');
      clock.advance(const Duration(minutes: 1));
      store.markOpened('n1');
      final opened = note('n1').lastOpenedAt;
      expect(opened, clock.millis);
      store.localWrite([
        pageWrite('p1', 'n1', deletedAt: 5, fields: const {'deletedAt'}),
      ]);
      expect(note('n1').pageCount, 1);
      expect(note('n1').firstPageId, 'p2');
      store.localWrite([
        noteWrite('n1', title: 'x', fields: const {'title'}),
      ]);
      expect(note('n1').lastOpenedAt, opened);
      expect(note('n1').pageCount, 1);
    });

    test(
      'rejects meta keys, empty field sets and bad JSON without writing',
      () {
        store.localWrite([noteWrite('n1')]);
        final rows = Map.of(store.rows);
        final outbox = List.of(store.outbox);
        expect(
          () => store.localWrite([
            noteWrite('n2'),
            noteWrite('n1', fields: const {'title', 'updatedAt'}),
          ]),
          throwsArgumentError,
        );
        expect(
          () => store.localWrite([noteWrite('n1', fields: const {})]),
          throwsArgumentError,
        );
        expect(
          () => store.localWrite([
            noteWrite('n3'),
            FakeLocalWrite(
              EntityKind.page,
              const {'id': 'p9'},
              changedFields: const {kAllFields},
            ),
          ]),
          throwsFormatException,
        );
        expect(store.rows, rows);
        expect(store.outbox, outbox);
      },
    );
  });

  group('localPurge', () {
    test('removes the note with its pages, strokes and recordings; one purge '
        'entry, child entries dropped, one localChanges', () async {
      store.localWrite([
        noteWrite('n1'),
        pageWrite('p1', 'n1'),
        noteWrite('n2'),
        pageWrite('p2', 'n2'),
      ]);
      store.localWrite([
        strokeWrite('s1', 'p1'),
        strokeWrite('s2', 'p2'),
        recordingWrite('r1', 'n1'),
      ]);
      final noteEntry = entry(EntityKind.note, 'n1')!;
      store.localWrite([
        noteWrite(
          'n1',
          trashRootId: 'n1',
          fields: const {'deletedAt', 'trashRootId'},
        ),
      ]);
      final events = await eventsDuring(
        () => store.localPurge(
          const EntityRef(EntityKind.note, 'n1'),
          group: const [],
        ),
      );
      expect(events, 1);
      for (final ref in const [
        EntityRef(EntityKind.note, 'n1'),
        EntityRef(EntityKind.page, 'p1'),
        EntityRef(EntityKind.stroke, 's1'),
        EntityRef(EntityKind.recording, 'r1'),
      ]) {
        expect(store.rows.containsKey(ref), isFalse, reason: '$ref');
        expect(
          entry(ref.kind, ref.id),
          ref.kind == EntityKind.note ? isNotNull : isNull,
        );
      }
      expect(
        store.rows.keys,
        containsAll(const [
          EntityRef(EntityKind.note, 'n2'),
          EntityRef(EntityKind.page, 'p2'),
          EntityRef(EntityKind.stroke, 's2'),
        ]),
      );
      final purge = entry(EntityKind.note, 'n1')!;
      expect(purge.op, OutboxOp.purge);
      expect(purge.changedFields, {kAllFields});
      expect(purge.seq, noteEntry.seq);
      expect(purge.rev, greaterThan(noteEntry.rev));
    });

    test('purges every folder and note of the group', () async {
      store.localWrite([
        folderWrite('f1', trashRootId: 'f1'),
        noteWrite('n1', folderId: 'f1', trashRootId: 'f1'),
        pageWrite('p1', 'n1'),
      ]);
      await store.sync.acknowledge([for (final e in store.outbox) e.ack]);
      store.localPurge(
        const EntityRef(EntityKind.folder, 'f1'),
        group: const [EntityRef(EntityKind.note, 'n1')],
      );
      expect(store.rows, isEmpty);
      expect(
        [for (final e in store.outbox) (e.kind, e.entityId, e.op)],
        unorderedEquals([
          (EntityKind.folder, 'f1', OutboxOp.purge),
          (EntityKind.note, 'n1', OutboxOp.purge),
        ]),
      );
    });

    test('rejects members that are not folders or notes', () {
      expect(
        () => store.localPurge(
          const EntityRef(EntityKind.note, 'n1'),
          group: const [EntityRef(EntityKind.page, 'p1')],
        ),
        throwsArgumentError,
      );
    });
  });

  group('markOpened', () {
    test('sets lastOpenedAt only: no outbox, no localChanges', () async {
      store.localWrite([noteWrite('n1')]);
      await store.sync.acknowledge([for (final e in store.outbox) e.ack]);
      final before = row(EntityKind.note, 'n1');
      clock.advance(const Duration(hours: 1));
      final events = await eventsDuring(() => store.markOpened('n1'));
      expect(events, 0);
      expect(note('n1').lastOpenedAt, clock.millis);
      expect(row(EntityKind.note, 'n1').versions, before.versions);
      expect(note('n1').toJson(), before.entity.toJson());
      expect(store.outbox, isEmpty);
      expect(() => store.markOpened('nope'), throwsArgumentError);
    });
  });

  group('failNextWrites', () {
    test('the next writes through sync / assets throw StateError and change '
        'nothing; localWrite is not counted', () async {
      store.localWrite([noteWrite('n1')]);
      store.failNextWrites(2);
      store.localWrite([noteWrite('n2')]);
      final acks = [for (final e in store.outbox) e.ack];
      await expectLater(store.sync.acknowledge(acks), throwsStateError);
      await expectLater(
        store.sync.writeMeta({'sync.cursor': '1'}),
        throwsStateError,
      );
      expect(store.outbox, hasLength(2));
      expect(store.meta, isEmpty);
      await store.sync.writeMeta({'sync.cursor': '1'});
      expect(store.meta, {'sync.cursor': '1'});
      store.failNextWrites(1);
      await expectLater(
        store.assets.put(
          Uint8List.fromList([1, 2, 3]),
          type: AssetType.pdf,
          mimeType: 'application/pdf',
        ),
        throwsStateError,
      );
      expect(await store.assets.listAssets(), isEmpty);
      expect(() => store.failNextWrites(-1), throwsArgumentError);
    });
  });

  group('canonicalDump', () {
    test('sorted keys at every level, soft-deleted rows included, versions '
        'per merge unit, Note.updatedAt left out', () {
      store.localWrite([
        pageWrite('p1', 'n1'),
        noteWrite('n1', trashRootId: 'n1'),
        folderWrite('f1'),
      ]);
      final dump = store.canonicalDump();
      expect(dump.keys.toList(), ['folder/f1', 'note/n1', 'page/p1']);
      final noteDump = dump['note/n1']! as Map<String, Object?>;
      expect(noteDump.keys.toList(), ['entity', 'versions']);
      final entity = noteDump['entity']! as Map<String, Object?>;
      expect(entity.keys.toList(), [...entity.keys]..sort());
      expect(entity.containsKey('updatedAt'), isFalse);
      expect(entity['deletedAt'], 2);
      final pageEntity = (dump['page/p1']! as Map)['entity']! as Map;
      expect(pageEntity.containsKey('updatedAt'), isTrue);
      final versions = noteDump['versions']! as Map<String, Object?>;
      expect(versions.keys.toList(), [...versions.keys]..sort());
      final noteVersion = row(EntityKind.note, 'n1').versions.base.toString();
      expect(versions['title'], noteVersion);
      expect(versions['deletedAt+trashRootId'], noteVersion);
      expect(versions.containsKey('updatedAt'), isFalse, reason: 'meta key');
    });

    test('equal for equal content whatever Note.updatedAt says', () async {
      store.localWrite([noteWrite('n1'), pageWrite('p1', 'n1')]);
      final other = FakeLocalStore(
        nodeId: 'b2b2b2b2b2b2b2b2',
        clock: clock.clock,
      );
      final n = row(EntityKind.note, 'n1');
      final p = row(EntityKind.page, 'p1');
      await other.sync.applyRemote([
        RemoteUpsert(
          EntityJson.decode(EntityKind.note, {
            ...n.entity.toJson(),
            'updatedAt': note('n1').updatedAt + 3600000,
          }),
          n.versions,
        ),
        RemoteUpsert(p.entity, p.versions),
      ], policy: (l, r, x) => const TakeRemote());
      final otherNote =
          other.rows[const EntityRef(EntityKind.note, 'n1')]!.entity as Note;
      expect(otherNote.updatedAt, isNot(note('n1').updatedAt));
      expect(other.canonicalDump(), store.canonicalDump());
    });

    test('the same state in two version encodings dumps the same (per unit), '
        'a different unit version does not', () async {
      store.localWrite([noteWrite('n1'), pageWrite('p1', 'n1')]);
      final n = row(EntityKind.note, 'n1');
      final p = row(EntityKind.page, 'p1');
      final top = n.versions.max;
      final older = Hlc(top.millis - 1, 0, 'b2b2b2b2b2b2b2b2');
      Future<FakeLocalStore> copy(EntityFieldVersions noteVersions) async {
        final entity = EntityJson.decode(EntityKind.note, {
          ...n.entity.toJson(),
          'version': noteVersions.max.toString(),
        });
        final other = FakeLocalStore(
          nodeId: 'b2b2b2b2b2b2b2b2',
          clock: clock.clock,
        );
        await other.sync.applyRemote([
          RemoteUpsert(entity, noteVersions),
          RemoteUpsert(p.entity, p.versions),
        ], policy: (l, r, x) => const TakeRemote());
        return other;
      }

      // FieldMerge's form: a smaller base, every key overridden with the same versions.
      final merged = await copy(
        EntityFieldVersions(older, {
          for (final k in n.entity.toJson().keys) k: n.versions.of(k),
        }),
      );
      expect(
        merged.rows[const EntityRef(EntityKind.note, 'n1')]!.versions.toJson(),
        isNot(n.versions.toJson()),
      );
      expect(merged.canonicalDump(), store.canonicalDump());
      // Same entity (version = max) but the title unit older: a real difference.
      final titleOlder = await copy(
        EntityFieldVersions(older, {
          for (final k in n.entity.toJson().keys)
            if (k != 'title') k: n.versions.of(k),
        }),
      );
      expect(titleOlder.canonicalDump(), isNot(store.canonicalDump()));
    });

    test('views are read-only', () {
      store.localWrite([noteWrite('n1')]);
      expect(() => store.rows.clear(), throwsUnsupportedError);
      expect(() => store.outbox.clear(), throwsUnsupportedError);
      expect(() => store.meta['sync.x'] = '1', throwsUnsupportedError);
    });
  });
}
