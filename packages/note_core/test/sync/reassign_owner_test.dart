// CORE T14 — SyncStore.reassignOwner (6.10.5, contract 7.2.10 v1.1): rows switch owner,
// the store's ownerId switches at runtime and persists, library streams re-emit, the outbox
// stays, ChangeBatch(origin: remote).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import 'support/sync_support.dart';

const String _uid = 'firebase-uid-1';

void main() {
  group('in memory', () {
    late DriftNoteStore store;
    late List<ChangeBatch> batches;
    late StreamSubscription<ChangeBatch> sub;

    setUp(() async {
      store = await openStore();
      batches = [];
      sub = store.changes.listen(batches.add);
    });
    tearDown(() async {
      await sub.cancel();
      await store.close();
    });

    Future<Set<String>> ownersOf(String table) async => {
      for (final r
          in await store.db
              .customSelect('SELECT DISTINCT owner_id FROM $table')
              .get())
        r.read<String>('owner_id'),
    };

    test('every row of from gets to; ownerId switches; outbox stays', () async {
      final f = await store.library.createFolder(name: 'f');
      final n = await store.library.createNote(title: 'n', folderId: f.id);
      await store.penPresets.createPreset(
        name: 'pen',
        style: StrokeStyle.defaultsFor(PenTool.ballpoint),
      );
      await store.assets.put(
        Uint8List.fromList([1, 2]),
        type: AssetType.image,
        mimeType: 'image/png',
      );
      final outbox = await store.sync.pendingChanges(limit: 1000);
      final versions = await store.sync.readVersioned([
        for (final e in outbox) e.ref,
      ]);
      await pumpEventQueue();
      batches.clear();

      await store.sync.reassignOwner(from: kLocalOwnerId, to: _uid);

      expect(store.ownerId, _uid);
      expect(store.sync.ownerId, _uid);
      for (final t in ['folders', 'notes', 'pen_presets', 'assets']) {
        expect(await ownersOf(t), {_uid}, reason: t);
      }
      expect(await store.sync.pendingChanges(limit: 1000), outbox);
      final after = await store.sync.readVersioned([
        for (final e in outbox) e.ref,
      ]);
      for (var i = 0; i < after.length; i++) {
        expect(
          after[i]!.versions.toJson(),
          versions[i]!.versions.toJson(),
          reason: 'no version change',
        );
      }
      expect((await store.library.getNote(n.id))!.ownerId, _uid);
      await pumpEventQueue();
      final b = batches.single;
      expect(b.origin, ChangeOrigin.remote);
      expect(
        {for (final c in b.changes) c.kind},
        {
          EntityKind.folder,
          EntityKind.note,
          EntityKind.penPreset,
          EntityKind.asset,
        },
      );
      // New local writes use the new owner.
      final later = await store.library.createNote(title: 'later');
      expect(later.ownerId, _uid);
    });

    test('library streams re-emit for the new owner', () async {
      await store.library.createFolder(name: 'mine');
      // A folder of the account arrives before the first login switch: invisible.
      await store.sync.applyRemote([
        upsert(
          Folder(
            id: 'cloud',
            ownerId: _uid,
            name: 'cloud',
            sortKey: 'a5',
            createdAt: 1,
            updatedAt: 1,
          ),
          remoteAfter(store),
        ),
      ], policy: (_, _, _) => const TakeRemote());
      final trees = <FolderTree>[];
      final s = store.library.watchFolderTree().listen(trees.add);
      await pumpEventQueue();
      expect(trees.last.folders.map((f) => f.name), ['mine']);
      await store.sync.reassignOwner(from: kLocalOwnerId, to: _uid);
      expect(trees.last.folders.map((f) => f.name).toSet(), {'mine', 'cloud'});
      await s.cancel();
    });

    test(
      'from != the current owner → StateError; from == to → nothing',
      () async {
        await store.library.createFolder(name: 'f');
        await pumpEventQueue();
        batches.clear();
        await expectLater(
          store.sync.reassignOwner(from: 'someone-else', to: _uid),
          throwsA(isA<StateError>()),
        );
        expect(store.ownerId, kLocalOwnerId);
        final count = store.queue.debugTransactionCount;
        await store.sync.reassignOwner(from: kLocalOwnerId, to: kLocalOwnerId);
        await pumpEventQueue();
        expect(batches, isEmpty);
        expect(store.ownerId, kLocalOwnerId);
        expect(store.queue.debugTransactionCount - count, lessThanOrEqualTo(1));
        // Two reassigns in a row: the second sees the first.
        unawaited(store.sync.reassignOwner(from: kLocalOwnerId, to: 'a'));
        await store.sync.reassignOwner(from: 'a', to: 'b');
        expect(store.ownerId, 'b');
      },
    );
  });

  test(
    'a reopened file store keeps the new owner over config.ownerId',
    () async {
      final dir = await Directory.systemTemp.createTemp('note_core_owner_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.db';
      final first = await openStore(filePath: path);
      final n = await first.library.createNote(title: 'n');
      await first.sync.reassignOwner(from: kLocalOwnerId, to: _uid);
      await first.close();
      final again = await openStore(filePath: path); // config.ownerId: 'local'
      addTearDown(again.close);
      expect(again.ownerId, _uid);
      expect(again.sync.ownerId, _uid);
      expect((await again.library.getNote(n.id))!.ownerId, _uid);
    },
  );
}
