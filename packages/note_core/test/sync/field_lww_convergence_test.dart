// CORE T14 — field versions make field-level LWW converge (SYNC 6.3.4 counter-example,
// CORE 6.10.2): two stores, A renames a note offline (t1), B moves it (t2 > t1); B pushes
// first, A receives (folder taken, title kept and queued by WriteMerged), A pushes, B
// receives (title taken). Both stores end equal with empty outboxes. Judging by the
// entity version alone (control) leaves them diverged.
@TestOn('vm')
library;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import 'support/sync_support.dart';

const String _nodeA = '000000000000000a';
const String _nodeB = '000000000000000b';

final class _Device {
  _Device(this.store, this._setNow);
  final NoteStore store;
  final void Function(Duration) _setNow;

  /// Sets this device's wall clock to the scenario start + [d].
  void at(Duration d) => _setNow(d);
}

Future<_Device> _open(String node, DateTime base) async {
  var now = base;
  final store = await openTestNoteStore(
    clock: Clock(() => now),
    ids: SequentialIdGenerator(prefix: node),
    deviceNodeId: node,
    seedDefaultPenPresets: false,
  );
  return _Device(store, (d) => now = base.add(d));
}

typedef _Outcome = ({
  Map<String, Object?> a,
  Map<String, Object?> b,
  Map<String, Object?> aVersions,
  Map<String, Object?> bVersions,
  int aPending,
  int bPending,
});

Future<_Outcome> _scenario(RemoteMergePolicy policy) async {
  final base = DateTime.utc(2026, 11, 5, 9);
  final a = await _open(_nodeA, base);
  final b = await _open(_nodeB, base);
  try {
    // Shared start: A creates a folder and a note; B receives them.
    final folder = await a.store.library.createFolder(name: 'Folder');
    final note = await a.store.library.createNote(title: 'Draft');
    await push(a.store, b.store, policy);

    // Offline: A renames at t1, B moves into the folder at t2 > t1.
    a.at(const Duration(minutes: 1));
    await a.store.library.renameNote(note.id, 'Final title');
    b.at(const Duration(minutes: 2));
    await b.store.library.moveItems([
      NoteRef(note.id),
    ], targetFolderId: folder.id);
    a.at(const Duration(minutes: 3));
    b.at(const Duration(minutes: 3));

    // B pushes first; A receives. A pushes; B receives.
    await push(b.store, a.store, policy);
    await push(a.store, b.store, policy);

    final ref = EntityRef(EntityKind.note, note.id);
    final va = (await a.store.sync.readVersioned([ref])).single!;
    final vb = (await b.store.sync.readVersioned([ref])).single!;
    return (
      a: va.entity.toJson(),
      b: vb.entity.toJson(),
      aVersions: va.versions.toJson(),
      bVersions: vb.versions.toJson(),
      aPending: (await a.store.sync.pendingChanges()).length,
      bPending: (await b.store.sync.pendingChanges()).length,
    );
  } finally {
    await a.store.close();
    await b.store.close();
  }
}

void main() {
  // Two devices = two databases open at once on purpose.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  test('field-level LWW with field versions converges', () async {
    final o = await _scenario(fieldLwwPolicy());
    expect(o.a, o.b);
    expect(o.aVersions, o.bVersions);
    expect(o.a['title'], 'Final title');
    expect(o.a['folderId'], isNotNull);
    expect((o.aPending, o.bPending), (0, 0));
  });

  test('control: judging by the entity version alone diverges', () async {
    final o = await _scenario(fieldLwwPolicy(entityVersionOnly: true));
    expect(o.a['title'], 'Final title');
    expect(o.b['title'], 'Draft', reason: 'B rejected the older title');
    expect(o.a, isNot(o.b));
    expect((o.aPending, o.bPending), (0, 0));
  });
}
