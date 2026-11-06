// libraryContentProvider / sidebarRowsProvider / folderLookupProvider /
// trashCountProvider (05-library 6.3.2 / 6.3.3, 8 L6) over the CORE fake.
// (v2, L2-01) the search's content groups, the debounced requery (6.1.6 —
// fakeAsync) and notePageIndexProvider (6.1.5).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:feature_library/src/model/content.dart';
import 'package:feature_library/src/model/content_hits.dart';
import 'package:feature_library/src/model/item_key.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/model/view_prefs.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/state/search_requery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';

void main() {
  late FakeLibraryBackend backend;
  late ProviderContainer container;
  late SampleLibrary lib;

  ProviderContainer makeContainer([List<Override> extra = const []]) =>
      ProviderContainer.test(overrides: [...backend.overrides, ...extra]);

  setUp(() async {
    backend = FakeLibraryBackend();
    lib = await seedSampleLibrary(backend);
    container = makeContainer();
  });
  tearDown(() => backend.dispose());

  /// Listens to [p] (keeps autoDispose providers alive) and returns a reader.
  AsyncValue<T> Function() listen<T>(ProviderListenable<AsyncValue<T>> p) {
    final sub = container.listen(p, (_, _) {});
    return sub.read;
  }

  /// Waits until [read] gives data that satisfies [test] (default: any data).
  Future<T> until<T>(
    AsyncValue<T> Function() read, [
    bool Function(T value)? test,
  ]) async {
    for (var i = 0; i < 40; i++) {
      final v = read();
      if (v is AsyncData<T> && (test == null || test(v.value))) return v.value;
      await pumpEventQueue();
    }
    fail('no matching data; last: ${read()}');
  }

  Future<LibraryContent> contentOf(LibrarySection section) =>
      until(listen(libraryContentProvider(section)));

  List<String> titles(LibraryContent c) => [for (final n in c.notes) n.title];
  List<String> names(LibraryContent c) => [for (final f in c.folders) f.name];

  group('libraryContentProvider — five sections', () {
    test('home folder: listing with the current sort, folders first', () async {
      final c = await contentOf(const FolderSection(null));
      expect(c.section, const FolderSection(null));
      // Default sort: updatedAt descending.
      expect(names(c), ['과학', '영어', '수학']);
      expect(titles(c), ['일기', '아이디어', '독서 기록', '회의록']);
      expect(c.truncated, isFalse);
      expect(c.isEmpty, isFalse);
      expect(c.orderedKeys.first, folderKey(lib.science.id));
      expect(c.orderedKeys.last, noteKey(lib.homeNotes.first.id));
      expect(c.orderedKeys, hasLength(7));
      expect(
        backend.queries,
        contains('watchListing LibraryQuery(folder: null, updatedAt, desc)'),
      );
    });

    test('sub folder and the stored sort (name ascending)', () async {
      await backend.store.settings.set(LibrarySettingsKeys.sortField, 'name');
      await backend.store.settings.set(
        LibrarySettingsKeys.sortDescending,
        false,
      );
      final c = await contentOf(FolderSection(lib.deepest.id));
      expect(titles(c), ['극한 정리']);
      expect(c.folders, isEmpty);
      expect(
        backend.queries,
        contains(
          'watchListing LibraryQuery(folder: ${lib.deepest.id}, name, asc)',
        ),
      );
    });

    test('a sort change re-queries the listing', () async {
      final read = listen(libraryContentProvider(const FolderSection(null)));
      await until(read);
      await container
          .read(libraryPrefsProvider.notifier)
          .selectSort(LibrarySortField.name);
      final c = await until(read, (c) => c.folders.first.name == '과학');
      // Name ascending: 과학 < 수학 < 영어.
      expect(names(c), ['과학', '수학', '영어']);
      expect(
        backend.queries,
        contains('watchListing LibraryQuery(folder: null, name, asc)'),
      );
    });

    test('unknown folder → empty listing (C-2)', () async {
      final c = await contentOf(const FolderSection('nope'));
      expect(c.isEmpty, isTrue);
      expect(c.orderedKeys, isEmpty);
    });

    test('recent: notes only, after openSession', () async {
      expect((await contentOf(const RecentSection())).isEmpty, isTrue);
      final read = listen(libraryContentProvider(const RecentSection()));
      await until(read);
      await backend.seedOpened(lib.homeNotes[1].id);
      final c = await until(read, (c) => c.notes.isNotEmpty);
      expect(titles(c), ['독서 기록']);
      expect(c.folders, isEmpty);
    });

    test('favorites: notes only', () async {
      await backend.seedNote('즐겨찾는 노트', favorite: true);
      final c = await contentOf(const FavoritesSection());
      expect(titles(c), ['즐겨찾는 노트']);
      expect(c.folders, isEmpty);
    });

    test('search: folders and notes of the whole library', () async {
      final c = await contentOf(
        const SearchSection('극한', returnTo: FolderSection(null)),
      );
      expect(names(c), ['극한']);
      expect(titles(c), ['극한 정리']);
      expect(c.truncated, isFalse);
      expect(backend.queries, contains("searchLibrary '극한' limit:50"));
    });

    test('trash: empty content (the trash view reads the trash)', () async {
      final c = await contentOf(const TrashSection());
      expect(c, const LibraryContent(section: TrashSection()));
      expect(c.isEmpty, isTrue);
    });
  });

  group('search truncated', () {
    test('50 notes → truncated, 49 → not', () async {
      for (var i = 0; i < 49; i++) {
        await backend.seedNote('단어장 $i');
      }
      var c = await contentOf(
        const SearchSection('단어장', returnTo: RecentSection()),
      );
      expect(c.notes, hasLength(49));
      expect(c.truncated, isFalse);

      await backend.seedNote('단어장 49');
      await backend.seedNote('단어장 50');
      // The search is a one-time query: invalidate to search again.
      container.invalidate(librarySearchProvider('단어장'));
      c = await until(
        listen(
          libraryContentProvider(
            const SearchSection('단어장', returnTo: RecentSection()),
          ),
        ),
        (c) => c.notes.length == 50,
      );
      expect(c.truncated, isTrue);
    });

    test('50 folders → truncated', () async {
      for (var i = 0; i < 50; i++) {
        await backend.seedFolder('묶음 $i');
      }
      final c = await contentOf(
        const SearchSection('묶음', returnTo: RecentSection()),
      );
      expect(c.folders, hasLength(50));
      expect(c.notes, isEmpty);
      expect(c.truncated, isTrue);
    });
  });

  group('loading until the view settings are loaded', () {
    test('first read is loading, then data', () async {
      final read = listen(libraryContentProvider(const FolderSection(null)));
      expect(read(), isA<AsyncLoading<LibraryContent>>());
      expect(container.read(libraryPrefsProvider).isLoaded, isFalse);
      await until(read);
      expect(container.read(libraryPrefsProvider).isLoaded, isTrue);
    });

    test('listing ready but settings never arrive → still loading', () async {
      final never = StreamController<SettingsSnapshot>();
      addTearDown(never.close);
      container = makeContainer([
        settingsSnapshotProvider.overrideWith((ref) => never.stream),
      ]);
      final read = listen(libraryContentProvider(const FolderSection(null)));
      final rows = listen(sidebarRowsProvider);
      final listing = listen(
        libraryListingProvider(LibrarySort.defaults.queryFor(null)),
      );
      await until(listing);
      await pumpEventQueue();
      expect(read(), isA<AsyncLoading<LibraryContent>>());
      expect(rows(), isA<AsyncLoading<Object?>>());
      // Every section waits, the trash placeholder too.
      for (final section in const [RecentSection(), TrashSection()]) {
        expect(
          container.read(libraryContentProvider(section)),
          isA<AsyncLoading<LibraryContent>>(),
        );
      }
    });

    test('a settings stream error counts as loaded (defaults)', () async {
      container = makeContainer([
        settingsSnapshotProvider.overrideWith(
          (ref) => Stream<SettingsSnapshot>.error(StateError('settings')),
        ),
      ]);
      final c = await until(
        listen(libraryContentProvider(const FolderSection(null))),
      );
      expect(names(c), ['과학', '영어', '수학']);
      expect(await until(listen(sidebarRowsProvider)), hasLength(3));
    });
  });

  test('a CORE stream error is passed through as AsyncError', () async {
    container = makeContainer([
      recentNotesProvider.overrideWith(
        (ref) => Stream<List<Note>>.error(StateError('recent')),
      ),
    ]);
    final read = listen(libraryContentProvider(const RecentSection()));
    for (var i = 0; i < 40 && read() is! AsyncError; i++) {
      await pumpEventQueue();
    }
    expect(read(), isA<AsyncError<LibraryContent>>());
    expect(read().error, isA<StateError>());
  });

  group('sidebarRowsProvider', () {
    test('top level in name order, expanded folders open', () async {
      final read = listen(sidebarRowsProvider);
      var rows = await until(read);
      expect([for (final r in rows) r.folder.name], ['과학', '수학', '영어']);
      expect(rows[1].hasChildren, isTrue);
      expect(rows[1].isExpanded, isFalse);

      container.read(folderExpansionProvider.notifier).expand(lib.math.id);
      rows = await until(read, (r) => r.length == 4);
      expect(
        [for (final r in rows) '${r.folder.name}@${r.depth}'],
        ['과학@0', '수학@0', '미적분@1', '영어@0'],
      );
    });

    test('custom sort → CORE order (creation order here)', () async {
      final read = listen(sidebarRowsProvider);
      await until(read);
      await container
          .read(libraryPrefsProvider.notifier)
          .selectSort(LibrarySortField.custom);
      final rows = await until(read, (r) => r.first.folder.name == '수학');
      expect([for (final r in rows) r.folder.name], ['수학', '영어', '과학']);
    });

    test('a new folder from another device appears', () async {
      final read = listen(sidebarRowsProvider);
      await until(read);
      await backend.remoteChange((s) => s.library.createFolder(name: '가나다'));
      final rows = await until(read, (r) => r.length == 4);
      expect(rows.first.folder.name, '가나다');
    });
  });

  group('folderLookupProvider', () {
    test('folder in the tree → active', () async {
      expect(
        await until(listen(folderLookupProvider(lib.math.id))),
        FolderLookupState.active,
      );
    });

    test('unknown id → missing', () async {
      expect(
        await until(listen(folderLookupProvider('nope'))),
        FolderLookupState.missing,
      );
    });

    test('trashed → trashed; restored → active; purged → missing', () async {
      final read = listen(folderLookupProvider(lib.english.id));
      expect(await until(read), FolderLookupState.active);

      await backend.remoteChange(
        (s) => s.library.trashItems([FolderRef(lib.english.id)]),
      );
      expect(
        await until(read, (v) => v == FolderLookupState.trashed),
        FolderLookupState.trashed,
      );

      await backend.remoteChange(
        (s) => s.trash.restore([FolderRef(lib.english.id)]),
      );
      expect(
        await until(read, (v) => v == FolderLookupState.active),
        FolderLookupState.active,
      );

      await backend.remoteChange(
        (s) => s.library.trashItems([FolderRef(lib.english.id)]),
      );
      await until(read, (v) => v == FolderLookupState.trashed);
      await backend.remoteChange(
        (s) => s.trash.purge([FolderRef(lib.english.id)]),
      );
      expect(
        await until(read, (v) => v == FolderLookupState.missing),
        FolderLookupState.missing,
      );
    });

    test('a sub folder of a trashed folder → trashed', () async {
      await backend.remoteChange(
        (s) => s.library.trashItems([FolderRef(lib.math.id)]),
      );
      expect(
        await until(listen(folderLookupProvider(lib.deepest.id))),
        FolderLookupState.trashed,
      );
    });
  });

  group('trashCountProvider', () {
    test('0 while loading, then the number of trash entries', () async {
      final sub = container.listen(trashCountProvider, (_, _) {});
      expect(sub.read(), 0);
      await backend.seedTrashed([
        FolderRef(lib.english.id),
        NoteRef(lib.homeNotes.first.id),
      ], at: DateTime(2026, 11, 3));
      for (var i = 0; i < 40 && sub.read() != 2; i++) {
        await pumpEventQueue();
      }
      expect(sub.read(), 2);
    });

    test('0 after a stream error', () async {
      container = makeContainer([
        trashItemsProvider.overrideWith(
          (ref) => Stream<List<TrashItem>>.error(StateError('trash')),
        ),
      ]);
      final sub = container.listen(trashCountProvider, (_, _) {});
      await pumpEventQueue();
      expect(sub.read(), 0);
    });
  });

  group('(v2) search content groups', () {
    const meetingQuery = SearchSection('회의', returnTo: FolderSection(null));

    test('CORE pages grouped by note, CORE order, pagesTruncated', () async {
      final sample = await seedContentHits(backend);
      final c = await contentOf(meetingQuery);
      final result = await backend.store.library.searchLibrary('회의');
      expect(result.pages, isNotEmpty);
      expect(c.contentGroups, groupContentHits(result.pages));
      expect(c.contentTruncated, isFalse);
      expect(c.isEmpty, isFalse);
      // Every note of the sample that has a '회의' source is a group once.
      expect(
        {for (final g in c.contentGroups) g.noteId},
        {sample.meeting.id, sample.calculus.id, sample.report.id},
      );
      expect(c.contentGroups.map((g) => g.noteId).toSet(), hasLength(3));
      final meetingHits = c.contentGroups
          .firstWhere((g) => g.noteId == sample.meeting.id)
          .hits;
      expect(meetingHits.map((h) => h.source).toSet(), {
        SearchSource.text,
        SearchSource.ink,
      });
      // The title '회의록 2026-11' is a note hit too (1차 group).
      expect(titles(c), contains('회의록 2026-11'));
    });

    test('math source and its rects', () async {
      final sample = await seedContentHits(backend);
      final c = await contentOf(
        const SearchSection('frac', returnTo: FolderSection(null)),
      );
      final hits = [for (final g in c.contentGroups) ...g.hits];
      expect(hits.map((h) => h.source), [SearchSource.math]);
      expect(hits.single.pageId, sample.calculusPages[1]);
      expect(focusRectOf(hits.single), isNotNull);
    });

    test('pagesTruncated → contentTruncated', () async {
      container = makeContainer([
        librarySearchProvider.overrideWith(
          (ref, q) async => LibrarySearchResult(
            query: q,
            folders: const [],
            notes: const [],
            pages: [
              PageSearchHit(
                noteId: 'n1',
                pageId: 'p1',
                source: SearchSource.pdf,
                snippet: q,
                matchRange: (0, q.length),
                score: 1,
              ),
            ],
            pagesTruncated: true,
          ),
        ),
      ]);
      final c = await contentOf(meetingQuery);
      expect(c.contentTruncated, isTrue);
      expect(c.truncated, isFalse);
      expect(c.contentGroups.single.noteId, 'n1');
    });

    test('other sections never have content groups', () async {
      await seedContentHits(backend);
      for (final section in const [
        FolderSection(null),
        RecentSection(),
        FavoritesSection(),
        TrashSection(),
      ]) {
        final c = await contentOf(section);
        expect(c.contentGroups, isEmpty, reason: '$section');
        expect(c.contentTruncated, isFalse, reason: '$section');
      }
    });
  });

  group('(v2) notePageIndexProvider', () {
    test('1-based index among the active pages, CORE order', () async {
      final sample = await seedContentHits(backend);
      final index = await until(
        listen(notePageIndexProvider(sample.calculus.id)),
      );
      expect(index, {sample.calculusPages[0]: 1, sample.calculusPages[1]: 2});
    });

    test('unknown note → empty map', () async {
      expect(await until(listen(notePageIndexProvider('nope'))), isEmpty);
    });
  });

  group('(v2) requery after changes (6.1.6, fakeAsync)', () {
    test('a page object change: none at 999 ms, one at 1 s', () {
      _RequeryRig.scenario((rig) {
        final session = rig.openCalculus();
        rig.mark();
        rig.run(
          session
              .execute(
                AddObjects(
                  pageId: rig.sample.calculusPages[0],
                  objects: [
                    PageObjectFixtures.textBox(
                      pageId: rig.sample.calculusPages[0],
                      text: '새 회의 메모',
                    ),
                  ],
                ),
              )
              .persisted,
        );
        rig.advance(999);
        expect(rig.requeries, isEmpty);
        rig.advance(1);
        expect(rig.requeries, [1000]);
        rig.advance(10000);
        expect(rig.requeries, [1000]);
        rig.run(session.close());
      });
    });

    test('handwriting every 0.4 s × 20 → 5.0 s (cap) and 8.6 s (quiet)', () {
      _RequeryRig.scenario((rig) {
        rig.mark();
        for (var i = 0; i < 20; i++) {
          rig.run(rig.putHandwriting('회의 $i'));
          if (i < 19) rig.advance(400);
        }
        expect(rig.requeries, [5000]);
        rig.advance(999);
        expect(rig.requeries, [5000]);
        rig.advance(1);
        expect(rig.requeries, [5000, 8600]);
        rig.advance(10000);
        expect(rig.requeries, [5000, 8600]);
      });
    });

    test('a stroke change asks nothing', () {
      _RequeryRig.scenario((rig) {
        final session = rig.openCalculus();
        rig.mark();
        final pageId = rig.sample.calculusPages[0];
        rig.run(
          session
              .execute(
                AddStrokes(
                  pageId: pageId,
                  strokes: [
                    StrokeFixtures.synthetic(
                      pageId: pageId,
                      ids: SequentialIdGenerator(prefix: 'stroke'),
                    ),
                  ],
                ),
              )
              .persisted,
        );
        rig.advance(10000);
        expect(rig.requeries, isEmpty);
        rig.run(session.close());
      });
    });

    test('a folder change asks at once and ends a pending wait', () {
      _RequeryRig.scenario((rig) {
        rig.mark();
        rig.run(rig.putHandwriting('회의 대기'));
        rig.advance(500);
        rig.run(rig.backend.store.library.createFolder(name: '회의 폴더'));
        expect(rig.requeries, [500]);
        rig.advance(10000);
        expect(rig.requeries, [500]);
        // The new result has the folder; the content stays.
        final c = rig.content.value!;
        expect(c.folders.map((f) => f.name), ['회의 폴더']);
        expect(c.contentGroups, isNotEmpty);
      });
    });

    test('a trashed note asks at once', () {
      _RequeryRig.scenario((rig) {
        rig.mark();
        rig.run(
          rig.backend.store.library.trashItems([NoteRef(rig.sample.report.id)]),
        );
        expect(rig.requeries, [0]);
        rig.advance(10000);
        final c = rig.content.value!;
        expect(
          c.contentGroups.map((g) => g.noteId),
          isNot(contains(rig.sample.report.id)),
        );
      });
    });

    test('the previous result stays while CORE is asked again', () {
      _RequeryRig.scenario((rig) {
        final before = rig.content.value!;
        expect(before.contentGroups, isNotEmpty);
        rig.mark();
        for (var i = 0; i < 3; i++) {
          rig.run(rig.putHandwriting('회의 다시 $i'));
          rig.advance(1000);
        }
        expect(rig.requeries, [1000, 2000, 3000]);
        expect(rig.statesSinceMark, isNotEmpty);
        for (final state in rig.statesSinceMark) {
          expect(state.hasValue, isTrue, reason: '$state');
          expect(state.value!.contentGroups, isNotEmpty, reason: '$state');
        }
        expect(rig.statesSinceMark.any((s) => s.isLoading), isTrue);
        expect(rig.content.isLoading, isFalse);
      });
    });

    test('a requery also refreshes the page numbers', () {
      _RequeryRig.scenario((rig) {
        final calculus = rig.sample.calculus.id;
        final index = rig.container.listen(
          notePageIndexProvider(calculus),
          (_, _) {},
        );
        rig.advance(0);
        expect(index.read().value, {
          rig.sample.calculusPages[0]: 1,
          rig.sample.calculusPages[1]: 2,
        });
        final session = rig.openCalculus();
        rig.mark();
        rig.run(
          session
              .execute(DeletePages(pageIds: [rig.sample.calculusPages[0]]))
              .persisted,
        );
        rig.advance(999);
        expect(index.read().value, hasLength(2));
        rig.advance(1);
        expect(rig.requeries, [1000]);
        rig.advance(0);
        expect(index.read().value, {rig.sample.calculusPages[1]: 1});
        rig.run(session.close());
        index.close();
      });
    });

    test('disposing the search stops the timers', () {
      _RequeryRig.scenario((rig) {
        rig.mark();
        rig.run(rig.putHandwriting('회의 끝'));
        rig.closeContent();
        rig.advance(10000);
        expect(rig.requeries, isEmpty);
        expect(rig.async.pendingTimers, isEmpty);
      });
    });
  });

  group('(v2) searchRequeryOf (6.1.6 table)', () {
    ChangeBatch batch(List<EntityChange> changes) => ChangeBatch(
      origin: ChangeOrigin.local,
      changes: changes,
      committedAt: 0,
    );
    EntityChange change(
      EntityKind kind, {
      bool deleted = false,
      bool purged = false,
    }) => EntityChange(
      kind: kind,
      id: kind.name,
      deleted: deleted,
      purged: purged,
    );

    test('one kind per batch', () {
      final expected = {
        EntityKind.folder: SearchRequery.immediate,
        EntityKind.note: SearchRequery.immediate,
        EntityKind.page: SearchRequery.debounced,
        EntityKind.pageObject: SearchRequery.debounced,
        EntityKind.handwriting: SearchRequery.debounced,
        EntityKind.stroke: SearchRequery.none,
        EntityKind.penPreset: SearchRequery.none,
        EntityKind.asset: SearchRequery.none,
        EntityKind.recording: SearchRequery.none,
        EntityKind.setting: SearchRequery.none,
      };
      expect(expected.keys.toSet(), EntityKind.values.toSet());
      for (final MapEntry(key: kind, value: want) in expected.entries) {
        expect(searchRequeryOf(batch([change(kind)])), want, reason: '$kind');
      }
      expect(searchRequeryOf(batch(const [])), SearchRequery.none);
    });

    test(
      'session commits: the note updatedAt beside content does not count',
      () {
        expect(
          searchRequeryOf(
            batch([change(EntityKind.pageObject), change(EntityKind.note)]),
          ),
          SearchRequery.debounced,
        );
        expect(
          searchRequeryOf(
            batch([change(EntityKind.stroke), change(EntityKind.note)]),
          ),
          SearchRequery.none,
        );
      },
    );

    test('a folder, or a deleted / purged note, is always at once', () {
      for (final first in [
        change(EntityKind.folder),
        change(EntityKind.note, deleted: true),
        change(EntityKind.note, purged: true),
      ]) {
        expect(
          searchRequeryOf(
            batch([change(EntityKind.stroke), change(EntityKind.page), first]),
          ),
          SearchRequery.immediate,
          reason: '$first',
        );
      }
    });
  });
}

/// One fakeAsync world for the requery tests: the CORE fake store seeded
/// with [seedContentHits], a container and a listener on the '회의' search.
final class _RequeryRig {
  _RequeryRig._(this.async) {
    backend = FakeLibraryBackend();
    sample = run(seedContentHits(backend));
    container = ProviderContainer(overrides: backend.overrides);
    _content = container.listen(
      libraryContentProvider(query),
      (_, next) => _states.add(next),
      fireImmediately: true,
    );
    for (var i = 0; i < 20 && content is! AsyncData; i++) {
      async.elapse(Duration.zero);
    }
    expect(content.value, isNotNull);
  }

  static void scenario(void Function(_RequeryRig rig) body) {
    fakeAsync((async) {
      final rig = _RequeryRig._(async);
      body(rig);
      rig._dispose();
    });
  }

  static const SearchSection query = SearchSection(
    '회의',
    returnTo: FolderSection(null),
  );

  final FakeAsync async;
  late final FakeLibraryBackend backend;
  late final ContentHitsSample sample;
  late final ProviderContainer container;
  ProviderSubscription<AsyncValue<LibraryContent>>? _content;
  final List<AsyncValue<LibraryContent>> _states = [];
  int _statesAtMark = 0;
  int _queriesAtMark = 0;
  Duration _markAt = Duration.zero;

  /// Milliseconds after [mark] of each searchLibrary('회의') call since then.
  final List<int> requeries = [];

  AsyncValue<LibraryContent> get content => _content!.read();

  List<AsyncValue<LibraryContent>> get statesSinceMark =>
      _states.sublist(_statesAtMark);

  int get _searches =>
      backend.queries.where((q) => q == "searchLibrary '회의' limit:50").length;

  /// Starts the clock of [requeries] (time 0) and forgets earlier searches.
  void mark() {
    _queriesAtMark = _searches;
    _statesAtMark = _states.length;
    _markAt = async.elapsed;
    requeries.clear();
  }

  void _note() {
    final ms = (async.elapsed - _markAt).inMilliseconds;
    while (_queriesAtMark + requeries.length < _searches) {
      requeries.add(ms);
    }
  }

  /// Advances fake time in 50 ms steps (1 ms for the rest), noting when a
  /// search runs.
  void advance(int ms) {
    var left = ms;
    while (left > 0) {
      final step = left >= 50 ? 50 : left;
      async.elapse(Duration(milliseconds: step));
      left -= step;
      _note();
    }
    async.elapse(Duration.zero);
    _note();
  }

  T run<T>(Future<T> future) {
    late T result;
    var done = false;
    future.then((v) {
      result = v;
      done = true;
    });
    for (var i = 0; i < 40 && !done; i++) {
      async.elapse(Duration.zero);
    }
    expect(done, isTrue, reason: 'future did not complete');
    _note();
    return result;
  }

  /// Opens a session on the calculus note (its markOpened note change asks
  /// at once — call [mark] after this).
  NoteSession openCalculus() {
    final session = run(backend.store.openSession(sample.calculus.id));
    for (final page in sample.calculusPages) {
      run(session.openPage(page));
    }
    run(backend.store.flush());
    advance(0);
    return session;
  }

  Future<void> putHandwriting(String text) => backend.store.handwriting.put(
    HandwritingText(
      noteId: sample.meeting.id,
      pageId: sample.meetingPages[1],
      engineId: 'fake/1:ko',
      sourceRev: '0000000000000000',
      lines: [
        HandwritingLine(
          text: text,
          rect: ContentHitsSample.inkLine1,
          strokeIds: const ['seed-ink-1'],
        ),
      ],
      createdAt: 1,
    ),
  );

  void closeContent() {
    _content?.close();
    _content = null;
    async.elapse(Duration.zero);
  }

  void _dispose() {
    _content?.close();
    container.dispose();
    run(backend.dispose());
  }
}
