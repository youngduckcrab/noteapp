// CORE T15 — NoteMigrator (6.15): a v0 → v1 step runs once in one transaction, a
// failure rolls back without retry and the note opens read-only, a newer note is
// read-only (ReadOnlyNoteException) and never migrated.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/migration/note_migrator.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';

const int _red = 0xFFFF0000;

void main() {
  late DriftNoteStore store;

  setUp(() async => store = await openStore());
  tearDown(() => store.close());

  /// A note of format [schemaVersion] with one page and two strokes.
  Future<void> seedNote(String id, int schemaVersion) async {
    await store.queue.run((tx) async {
      await tx.putLocal(
        Note(
          id: id,
          ownerId: kLocalOwnerId,
          title: 'v$schemaVersion',
          sortKey: 'a0',
          schemaVersion: schemaVersion,
          createdAt: 1,
          updatedAt: 1,
          pageCount: 1,
          firstPageId: '$id-p',
        ),
        const {kAllFields},
      );
      await tx.putLocal(page('$id-p', id), const {kAllFields});
      for (var i = 0; i < 2; i++) {
        await tx.putLocal(
          StrokeFixtures.synthetic(
            pageId: '$id-p',
            ids: SequentialIdGenerator(prefix: '$id-s$i'),
            seed: i,
            pointCount: 8,
          ),
          const {kAllFields},
          strokeNoteId: id,
        );
      }
    });
    await store.sync.acknowledge([
      for (final e in await store.sync.pendingChanges(limit: 1000)) e.ack,
    ]);
  }

  Future<List<Stroke>> strokesOf(String pageId) async {
    final rows = await (store.db.select(
      store.db.strokes,
    )..where((t) => t.pageId.equals(pageId))).get();
    return [
      for (final r in rows)
        (await store.sync.readVersioned([EntityRef(EntityKind.stroke, r.id)]))
                .single!
                .entity
            as Stroke,
    ];
  }

  /// v0 → v1: every stroke turns red.
  var runs = 0;
  Future<void> redStep(NoteMigrationContext ctx) async {
    runs++;
    expect(ctx.note.schemaVersion, 0);
    for (final p in await ctx.pages()) {
      for (final s in await ctx.strokesOf(p.id)) {
        ctx.putStroke(
          s.copyWith(style: s.style.copyWith(colorArgb: _red), updatedAt: 9),
        );
      }
    }
  }

  setUp(() => runs = 0);

  test('a v0 → v1 step runs once; changed fields go to the outbox', () async {
    await seedNote('n0', 0);
    final migrator = NoteMigrator({0: redStep}, store: store);
    final note = await migrator.migrateIfNeeded('n0');
    expect(note.schemaVersion, kNoteSchemaVersion);
    expect(runs, 1);
    final strokes = await strokesOf('n0-p');
    expect(strokes.map((s) => s.style.colorArgb), everyElement(_red));
    final stored = (await store.library.getNote('n0'))!;
    expect(stored.schemaVersion, kNoteSchemaVersion);
    final entries = await store.sync.pendingChanges();
    expect(
      {for (final e in entries) e.entityId: e.changedFields},
      {
        'n0': {'schemaVersion'},
        for (final s in strokes) s.id: {'style'},
      },
    );
    // Already current: the step does not run again.
    await migrator.migrateIfNeeded('n0');
    expect(runs, 1);
  });

  test('a failing step rolls back everything, no retry', () async {
    await seedNote('n0', 0);
    final before = await strokesOf('n0-p');
    final boom = Exception('step failed');
    final migrator = NoteMigrator({
      0: (ctx) async {
        await redStep(ctx);
        throw boom;
      },
    }, store: store);
    Object? caught;
    try {
      await migrator.migrateIfNeeded('n0');
    } on Object catch (e) {
      caught = e;
    }
    expect(caught, same(boom));
    expect(runs, 1, reason: 'not retried');
    expect(store.persistenceStatus.consecutiveFailures, 0);
    expect((await store.library.getNote('n0'))!.schemaVersion, 0);
    expect(await strokesOf('n0-p'), before);
    expect(await store.sync.pendingChanges(), isEmpty);
  });

  test('a missing step → StateError, nothing written', () async {
    await seedNote('n0', 0);
    await expectLater(
      NoteMigrator(const {}, store: store).migrateIfNeeded('n0'),
      throwsStateError,
    );
    expect((await store.library.getNote('n0'))!.schemaVersion, 0);
  });

  test(
    'openSession migrates first; the session sees the new content',
    () async {
      await seedNote('n0', 0);
      store.noteMigrator = NoteMigrator({0: redStep}, store: store);
      final session = await store.openSession('n0');
      expect(session.note.schemaVersion, kNoteSchemaVersion);
      expect(session.isReadOnly, isFalse);
      final content = await session.openPage('n0-p');
      expect(content.strokes.map((s) => s.style.colorArgb), everyElement(_red));
      await session.close();
    },
  );

  test('openSession after a failed migration: read-only, no writes', () async {
    await seedNote('n0', 0);
    store.noteMigrator = NoteMigrator({
      0: (_) async => throw StateError('broken'),
    }, store: store);
    final session = await store.openSession('n0');
    expect(session.note.schemaVersion, 0);
    expect(session.isReadOnly, isTrue);
    await session.openPage('n0-p');
    expect(
      () => session.execute(
        AddStrokes(
          pageId: 'n0-p',
          strokes: [StrokeFixtures.synthetic(pageId: 'n0-p', ids: store.ids)],
        ),
      ),
      throwsA(isA<ReadOnlyNoteException>()),
    );
    await session.close();
  });

  test('a note from a newer app: read-only and never migrated', () async {
    await seedNote('n2', kNoteSchemaVersion + 1);
    store.noteMigrator = NoteMigrator({
      for (var v = 0; v <= kNoteSchemaVersion + 1; v++) v: redStep,
    }, store: store);
    expect(
      (await store.noteMigrator.migrateIfNeeded('n2')).schemaVersion,
      kNoteSchemaVersion + 1,
    );
    final session = await store.openSession('n2');
    expect(runs, 0);
    expect(session.note.requiresNewerApp, isTrue);
    expect(session.isReadOnly, isTrue);
    await session.openPage('n2-p');
    expect(
      () => session.execute(ClearPage(pageId: 'n2-p')),
      throwsA(isA<ReadOnlyNoteException>()),
    );
    await expectLater(session.undo(), throwsA(isA<ReadOnlyNoteException>()));
    await session.close();
  });

  test('an unknown note → EntityNotFoundException', () async {
    await expectLater(
      store.noteMigrator.migrateIfNeeded('none'),
      throwsA(isA<EntityNotFoundException>()),
    );
  });
}
