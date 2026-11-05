// LibraryPrefsNotifier / LibraryViewPrefs.fromSnapshot / newNoteDefaultsProvider
// (05-library 6.3.3 / 6.3.4, 8 L3).
import 'package:feature_library/src/model/new_note_spec.dart';
import 'package:feature_library/src/model/view_prefs.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';

/// SettingsRepository whose writes fail (reads go to the real one).
final class _FailingWrites implements SettingsRepository {
  _FailingWrites(this._inner);
  final SettingsRepository _inner;

  @override
  Future<T> get<T>(SettingKey<T> key) => _inner.get(key);
  @override
  Stream<T> watch<T>(SettingKey<T> key) => _inner.watch(key);
  @override
  Stream<SettingsSnapshot> watchAll() => _inner.watchAll();
  @override
  Future<void> set<T>(SettingKey<T> key, T value) async =>
      throw StateError('write failed');
  @override
  Future<void> reset<T>(SettingKey<T> key) => _inner.reset(key);
}

void main() {
  late FakeLibraryBackend backend;
  late ProviderContainer container;

  setUp(() {
    backend = FakeLibraryBackend();
    container = ProviderContainer.test(overrides: backend.overrides);
  });
  tearDown(() => backend.dispose());

  /// Keeps libraryPrefsProvider alive and waits for the first snapshot.
  Future<void> load() async {
    container.listen(libraryPrefsProvider, (_, _) {});
    await container.read(settingsSnapshotProvider.future);
  }

  LibraryViewPrefs prefs() => container.read(libraryPrefsProvider);

  test('defaults with isLoaded == false until the first snapshot', () async {
    expect(prefs(), const LibraryViewPrefs());
    expect(prefs().isLoaded, isFalse);
    await load();
    expect(prefs().isLoaded, isTrue);
    expect(prefs().viewMode, LibraryViewMode.grid);
    expect(prefs().sort, LibrarySort.defaults);
    expect(prefs().sidebarVisible, isTrue);
  });

  test('setViewMode is applied at once, then stored', () async {
    await load();
    final saved = container
        .read(libraryPrefsProvider.notifier)
        .setViewMode(LibraryViewMode.list);
    expect(prefs().viewMode, LibraryViewMode.list); // optimistic
    await saved;
    expect(
      await backend.store.settings.get(LibrarySettingsKeys.viewMode),
      'list',
    );
    await pumpEventQueue();
    expect(prefs().viewMode, LibraryViewMode.list);
    expect(prefs().isLoaded, isTrue);
  });

  test('selectSort follows LibrarySort.select and stores both keys', () async {
    await load();
    final notifier = container.read(libraryPrefsProvider.notifier);
    final settings = backend.store.settings;

    final first = notifier.selectSort(LibrarySortField.name);
    expect(
      prefs().sort,
      const LibrarySort(LibrarySortField.name, descending: false),
    );
    await first;
    expect(await settings.get(LibrarySettingsKeys.sortField), 'name');
    expect(await settings.get(LibrarySettingsKeys.sortDescending), isFalse);

    await notifier.selectSort(LibrarySortField.name);
    await pumpEventQueue();
    expect(
      prefs().sort,
      const LibrarySort(LibrarySortField.name, descending: true),
    );
    expect(await settings.get(LibrarySettingsKeys.sortDescending), isTrue);

    await notifier.selectSort(LibrarySortField.custom);
    await pumpEventQueue();
    expect(
      prefs().sort,
      const LibrarySort(LibrarySortField.custom, descending: false),
    );
    expect(await settings.get(LibrarySettingsKeys.sortField), 'custom');
  });

  test('setSidebarVisible is stored', () async {
    await load();
    await container
        .read(libraryPrefsProvider.notifier)
        .setSidebarVisible(false);
    await pumpEventQueue();
    expect(prefs().sidebarVisible, isFalse);
    expect(
      await backend.store.settings.get(LibrarySettingsKeys.sidebarVisible),
      isFalse,
    );
  });

  test('stored values from another writer reach the state', () async {
    await load();
    final s = backend.store.settings;
    await s.set(LibrarySettingsKeys.viewMode, 'list');
    await s.set(LibrarySettingsKeys.sortField, 'createdAt');
    await s.set(LibrarySettingsKeys.sortDescending, false);
    await pumpEventQueue();
    expect(prefs().viewMode, LibraryViewMode.list);
    expect(
      prefs().sort,
      const LibrarySort(LibrarySortField.createdAt, descending: false),
    );
  });

  test('unknown stored strings → defaults', () async {
    final s = backend.store.settings;
    await s.set(LibrarySettingsKeys.viewMode, 'tiles');
    await s.set(LibrarySettingsKeys.sortField, 'size');
    await load();
    expect(prefs().viewMode, LibraryViewMode.grid);
    expect(prefs().sort.field, LibrarySortField.updatedAt);
  });

  test('fromSnapshot of an empty snapshot = loaded defaults', () {
    final p = LibraryViewPrefs.fromSnapshot(const SettingsSnapshot({}));
    expect(p, const LibraryViewPrefs(isLoaded: true));
  });

  test('a failed write is reported and the optimistic state kept', () async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    final failing = ProviderContainer.test(
      overrides: [
        ...backend.overrides,
        settingsRepositoryProvider.overrideWithValue(
          _FailingWrites(backend.store.settings),
        ),
      ],
    );
    failing.listen(libraryPrefsProvider, (_, _) {});
    await failing.read(settingsSnapshotProvider.future);
    await failing
        .read(libraryPrefsProvider.notifier)
        .setViewMode(LibraryViewMode.list);
    expect(failing.read(libraryPrefsProvider).viewMode, LibraryViewMode.list);
    expect(errors, hasLength(1));
    expect(errors.single.library, 'feature_library');
    expect(errors.single.exception, isStateError);
  });

  group('newNoteDefaultsProvider', () {
    test('defaults before the settings load and for an empty value', () async {
      expect(container.read(newNoteDefaultsProvider), const NewNoteOptions());
      container.listen(newNoteDefaultsProvider, (_, _) {});
      await container.read(settingsSnapshotProvider.future);
      expect(container.read(newNoteDefaultsProvider), const NewNoteOptions());
    });

    test(
      'reads library.newNote.defaults (toJson) and follows changes',
      () async {
        container.listen(newNoteDefaultsProvider, (_, _) {});
        await container.read(settingsSnapshotProvider.future);
        const options = NewNoteOptions(
          preset: PageSizePreset.letter,
          template: PageTemplateKind.grid,
          paperColorArgb: PaperColors.ivory,
        );
        await backend.store.settings.set(
          LibrarySettingsKeys.newNoteDefaults,
          options.toJson(),
        );
        await pumpEventQueue();
        expect(container.read(newNoteDefaultsProvider), options);
      },
    );
  });
}
