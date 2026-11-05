// FolderExpansionNotifier (05-library 6.3.3 / 6.5, 8 L6): load + merge, save
// 500 ms after the last change (fakeAsync), at most 500 ids, vanished ids
// dropped, immediate save on dispose.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/state/expansion_notifier.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';

/// Delegates to the store's settings; records the expanded-folder writes and
/// can hold back the first read of that key.
final class _RecordingSettings implements SettingsRepository {
  _RecordingSettings(this._inner);

  final SettingsRepository _inner;
  final List<List<String>> expandedWrites = [];

  /// When set, get(expandedFolders) waits for it.
  Completer<void>? holdLoad;
  Error? failLoad;

  @override
  Future<T> get<T>(SettingKey<T> key) async {
    if (key.name == LibrarySettingsKeys.expandedFolders.name) {
      final hold = holdLoad;
      if (hold != null) await hold.future;
      final failure = failLoad;
      if (failure != null) throw failure;
    }
    return _inner.get(key);
  }

  @override
  Stream<T> watch<T>(SettingKey<T> key) => _inner.watch(key);
  @override
  Stream<SettingsSnapshot> watchAll() => _inner.watchAll();
  @override
  Future<void> set<T>(SettingKey<T> key, T value) {
    if (key.name == LibrarySettingsKeys.expandedFolders.name) {
      expandedWrites.add(List<String>.of(value as List<String>));
    }
    return _inner.set(key, value);
  }

  @override
  Future<void> reset<T>(SettingKey<T> key) => _inner.reset(key);
}

/// One fakeAsync world: backend, recording settings and a container.
final class _World {
  _World(this.async, {List<String> stored = const [], bool hold = false}) {
    backend = FakeLibraryBackend();
    settings = _RecordingSettings(backend.store.settings);
    if (stored.isNotEmpty) {
      run(
        backend.store.settings.set(LibrarySettingsKeys.expandedFolders, stored),
      );
    }
    if (hold) settings.holdLoad = Completer<void>();
    container = ProviderContainer(
      overrides: [
        ...backend.overrides,
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    sub = container.listen(folderExpansionProvider, (_, _) {});
  }

  final FakeAsync async;
  late final FakeLibraryBackend backend;
  late final _RecordingSettings settings;
  late final ProviderContainer container;
  late final ProviderSubscription<Set<FolderId>> sub;

  FolderExpansionNotifier get notifier =>
      container.read(folderExpansionProvider.notifier);
  List<String> get expanded => sub.read().toList();

  T run<T>(Future<T> future) {
    late T result;
    var done = false;
    future.then((v) {
      result = v;
      done = true;
    });
    async.flushMicrotasks();
    for (var i = 0; i < 20 && !done; i++) {
      async.elapse(Duration.zero);
    }
    expect(done, isTrue, reason: 'future did not complete');
    return result;
  }

  Folder folder(String name) => run(backend.seedFolder(name));

  Future<List<String>> stored() =>
      backend.store.settings.get(LibrarySettingsKeys.expandedFolders);

  void elapse(int ms) => async.elapse(Duration(milliseconds: ms));

  void close() {
    container.dispose();
    async.flushMicrotasks();
    run(backend.dispose());
  }
}

void main() {
  test('starts empty, then the stored ids are loaded', () {
    fakeAsync((async) {
      final w = _World(async, stored: ['a', 'b']);
      expect(w.expanded, isEmpty);
      async.flushMicrotasks();
      w.elapse(0);
      expect(w.expanded, ['a', 'b']);
      // Loading writes nothing.
      w.elapse(1000);
      expect(w.settings.expandedWrites, isEmpty);
      w.close();
    });
  });

  test('toggle / expand / collapse / expandAll', () {
    fakeAsync((async) {
      final w = _World(async);
      w.elapse(0);
      final n = w.notifier
        ..expand('a')
        ..toggle('b');
      expect(w.expanded, ['a', 'b']);
      n.toggle('a');
      expect(w.expanded, ['b']);
      n.collapse('zzz'); // not expanded: no change
      n.expandAll(['c', 'b', 'd']);
      expect(w.expanded, ['b', 'c', 'd']); // b keeps its place
      final before = w.sub.read();
      n.expandAll(['c', 'd']); // nothing new → same state object
      expect(w.sub.read(), same(before));
      n.collapse('c');
      expect(w.expanded, ['b', 'd']);
      w.close();
    });
  });

  test('save 500 ms after the LAST change, one write', () {
    fakeAsync((async) {
      final w = _World(async);
      final a = w.folder('A');
      final b = w.folder('B');
      w.elapse(0);
      w.notifier.expand(a.id);
      w.elapse(300);
      w.notifier.expand(b.id);
      w.elapse(499);
      expect(w.settings.expandedWrites, isEmpty);
      w.elapse(1);
      expect(w.settings.expandedWrites, [
        [a.id, b.id],
      ]);
      expect(w.run(w.stored()), [a.id, b.id]);

      w.notifier.collapse(a.id);
      w.elapse(500);
      expect(w.settings.expandedWrites.last, [b.id]);
      expect(w.settings.expandedWrites, hasLength(2));
      w.close();
    });
  });

  test('ids that the folder tree no longer has are not saved', () {
    fakeAsync((async) {
      final w = _World(async);
      final a = w.folder('A');
      final b = w.folder('B');
      w.elapse(0);
      w.notifier.expandAll([a.id, 'gone-1', b.id]);
      w.run(w.backend.store.library.trashItems([FolderRef(b.id)]));
      w.elapse(500);
      expect(w.settings.expandedWrites.single, [a.id]);
      // The in-memory set still has them (harmless for the tree).
      expect(w.expanded, [a.id, 'gone-1', b.id]);
      w.close();
    });
  });

  test('at most 500 ids, the most recently expanded kept', () {
    fakeAsync((async) {
      final w = _World(async);
      // Real folders: the save keeps only ids the tree has.
      final ids = [for (var i = 0; i < 520; i++) w.folder('F$i').id];
      w.elapse(0);
      for (final id in ids) {
        w.notifier.expand(id);
      }
      w.elapse(500);
      final saved = w.settings.expandedWrites.single;
      expect(saved, hasLength(FolderExpansionNotifier.maxSaved));
      expect(saved, ids.sublist(20));
      w.close();
    });
  });

  test('ids expanded before the load are merged after the stored ones', () {
    fakeAsync((async) {
      final w = _World(async, hold: true);
      final [s1, s2, s3, m1, m2] = [
        for (final name in ['s1', 's2', 's3', 'm1', 'm2']) w.folder(name).id,
      ];
      // Stored while the read is held back.
      w.run(
        w.backend.store.settings.set(LibrarySettingsKeys.expandedFolders, [
          s1,
          s2,
          s3,
        ]),
      );
      w.elapse(0);
      w.notifier
        ..expand(m1)
        ..expand(s2) // also stored: kept once, as the more recent one
        ..collapse(m1)
        ..expand(m2)
        // s3 expanded and collapsed again before the load: not restored.
        ..expand(s3)
        ..collapse(s3);
      expect(w.expanded, [s2, m2]);

      // The debounce fires while the load is still held: no write yet.
      w.elapse(600);
      expect(w.settings.expandedWrites, isEmpty);

      w.settings.holdLoad!.complete();
      w.elapse(0);
      expect(w.expanded, [s1, s2, m2]);
      // The held save runs 500 ms after the load.
      w.elapse(499);
      expect(w.settings.expandedWrites, isEmpty);
      w.elapse(1);
      expect(w.settings.expandedWrites, [
        [s1, s2, m2],
      ]);
      w.close();
    });
  });

  test('a pending save is written at once on dispose', () {
    fakeAsync((async) {
      final w = _World(async);
      final a = w.folder('A');
      w.elapse(0);
      w.notifier.expand(a.id);
      w.elapse(100);
      expect(w.settings.expandedWrites, isEmpty);
      w.container.dispose();
      expect(w.settings.expandedWrites, [
        [a.id],
      ]);
      async.flushMicrotasks();
      w.elapse(1000);
      expect(w.settings.expandedWrites, hasLength(1)); // timer cancelled
      expect(w.run(w.stored()), [a.id]);
      w.run(w.backend.dispose());
    });
  });

  test('nothing pending → dispose writes nothing', () {
    fakeAsync((async) {
      final w = _World(async, stored: ['a']);
      w.elapse(0);
      w.container.dispose();
      async.flushMicrotasks();
      expect(w.settings.expandedWrites, isEmpty);
      w.run(w.backend.dispose());
    });
  });

  test('a failed load is reported once and starts empty', () {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    fakeAsync((async) {
      final w = _World(async, hold: true);
      final a = w.folder('A').id;
      w.settings.failLoad = StateError('load');
      w.settings.holdLoad!.complete();
      w.elapse(0);
      expect(w.expanded, isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single.library, 'feature_library');
      // Still usable and saved.
      w.notifier.expand(a);
      w.elapse(500);
      expect(w.settings.expandedWrites, [
        [a],
      ]);
      w.close();
    });
  });
}
