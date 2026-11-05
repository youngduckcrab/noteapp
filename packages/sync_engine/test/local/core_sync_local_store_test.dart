// T16 (adapter): CoreSyncLocalStore is a thin view of a CORE NoteStore (4.9) — sync and assets
// are the store's own, localChanges is store.changes filtered to origin local / undo / redo
// (remote writes and loads do not schedule a push, 5.1.2 S-9). The real-CORE contract suite and
// scenarios run in the integration stage (test/integration/, tag 'integration').
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart' as core_testing;
import 'package:sync_engine/sync_engine.dart';

/// A NoteStore whose change stream the test drives; every other member is the fake store's.
final class _ScriptedChanges implements NoteStore {
  _ScriptedChanges(this._inner);

  final NoteStore _inner;
  final StreamController<ChangeBatch> controller = StreamController.broadcast();

  @override
  Stream<ChangeBatch> get changes => controller.stream;

  Future<void> closeChanges() => controller.close();

  @override
  SyncStore get sync => _inner.sync;

  @override
  AssetStore get assets => _inner.assets;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('sync and assets are the store\'s own', () {
    final store = core_testing.createFakeNoteStore();
    final local = CoreSyncLocalStore(store);
    expect(local.sync, same(store.sync));
    expect(local.assets, same(store.assets));
  });

  test('localChanges: one event per local / undo / redo batch; remote and '
      'load batches are dropped', () async {
    final store = _ScriptedChanges(core_testing.createFakeNoteStore());
    final local = CoreSyncLocalStore(store);
    var events = 0;
    final sub = local.localChanges.listen((_) => events++);
    for (final origin in ChangeOrigin.values) {
      store.controller.add(
        ChangeBatch(origin: origin, changes: const [], committedAt: 1),
      );
    }
    await Future<void>.delayed(Duration.zero);
    expect(events, 3);
    await sub.cancel();
    await store.closeChanges();
  });

  test(
    'a repository command of the CORE fake store is a local change',
    () async {
      final store = core_testing.createFakeNoteStore();
      var events = 0;
      final sub = CoreSyncLocalStore(store).localChanges
          .listen((_) => events++);
      await store.library.createFolder(name: 'from the library');
      await Future<void>.delayed(Duration.zero);
      expect(events, greaterThanOrEqualTo(1));
      await sub.cancel();
    },
  );
}
