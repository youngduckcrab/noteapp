// Shared body of the LibraryRepository contract (C-1..C-10, 00-overview 7.2.9, CORE 4.5 /
// 6.8 / 9.1) and the TrashRepository rules of 6.8 (CORE T9). Runs on createFakeNoteStore() (test/repo/library_contract_fake_test.dart)
// and on openTestNoteStore() (test/repo/library_contract_real_test.dart, CORE T8) so the
// two implementations keep the same meaning (6.19).
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

/// Opens a store on [clock] (the tests use a clock that advances 1 ms per read).
typedef ClockedStoreFactory = FutureOr<NoteStore> Function(Clock clock);

const int kLibraryContractStart = 1793750400000;

void defineLibraryContractTests(ClockedStoreFactory open) {
  late NoteStore store;
  late LibraryRepository lib;
  var ms = kLibraryContractStart;

  setUp(() async {
    ms = kLibraryContractStart;
    store = await open(
      Clock(() => DateTime.fromMillisecondsSinceEpoch(ms++, isUtc: true)),
    );
    lib = store.library;
  });

  tearDown(() => store.close());

  /// Collects the values of [stream] until the returned stop function runs.
  Future<List<T>> Function() record<T>(Stream<T> stream, List<T> into) {
    final sub = stream.listen(into.add);
    return () async {
      await sub.cancel();
      return into;
    };
  }

  group('C-1 watch streams', () {
    test('listing: current value on listen, again after affecting commits '
        'only', () async {
      final parent = await lib.createFolder(name: 'p');
      final values = <LibraryListing>[];
      final stop = record(lib.watchListing(const LibraryQuery()), values);
      await pumpEventQueue();
      expect(values, hasLength(1));
      expect(values.single.folders.map((f) => f.id), [parent.id]);
      await lib.createNote(title: 'a');
      await pumpEventQueue();
      expect(values, hasLength(2));
      expect(values.last.notes.single.title, 'a');
      await lib.createFolder(name: 'child', parentId: parent.id);
      await pumpEventQueue();
      expect(
        values,
        hasLength(2),
        reason: 'a commit that does not change the result does not re-emit',
      );
      await lib.renameFolder(parent.id, 'renamed');
      await pumpEventQueue();
      expect(values, hasLength(3));
      expect(values.last.folders.single.name, 'renamed');
      await stop();
    });

    test('folder tree, note, recent and favorite streams re-emit', () async {
      final n = await lib.createNote(title: 'n');
      final trees = <FolderTree>[];
      final notes = <Note?>[];
      final recents = <List<Note>>[];
      final favorites = <List<Note>>[];
      final stops = [
        record(lib.watchFolderTree(), trees),
        record(lib.watchNote(n.id), notes),
        record(lib.watchRecentNotes(), recents),
        record(lib.watchFavoriteNotes(), favorites),
      ];
      await pumpEventQueue();
      expect(trees.single.length, 0);
      expect(notes.single, n);
      expect(recents.single, isEmpty);
      expect(favorites.single, isEmpty);

      final f = await lib.createFolder(name: 'f');
      await lib.setFavorite([n.id], true);
      await lib.markOpened(n.id);
      await pumpEventQueue();
      expect(trees.last.byId(f.id), isNotNull);
      expect(notes.last!.isFavorite, isTrue);
      expect(recents.last.map((x) => x.id), [n.id]);
      expect(favorites.last.map((x) => x.id), [n.id]);
      expect(trees, hasLength(2));

      await lib.trashItems([NoteRef(n.id)]);
      await pumpEventQueue();
      expect(notes.last!.isDeleted, isTrue, reason: 'C-3: still visible');
      expect(recents.last, isEmpty);
      expect(favorites.last, isEmpty);
      for (final stop in stops) {
        await stop();
      }
    });

    test('unknown note → null', () async {
      expect(await lib.watchNote('missing').first, isNull);
      expect(await lib.getNote('missing'), isNull);
      expect(await lib.getFolder('missing'), isNull);
    });
  });

  group('C-2 listing', () {
    test('folders first, ordered as asked; unknown folder → empty', () async {
      final f1 = await lib.createFolder(name: 'Beta');
      final f2 = await lib.createFolder(name: 'alpha');
      final n1 = await lib.createNote(title: 'Zeta');
      final n2 = await lib.createNote(title: 'eta');
      Future<LibraryListing> list(LibraryQuery q) => lib.watchListing(q).first;

      final byName = await list(
        const LibraryQuery(sort: LibrarySortField.name, descending: false),
      );
      expect(byName.folders.map((f) => f.id), [f2.id, f1.id]);
      expect(byName.notes.map((n) => n.id), [n2.id, n1.id]);
      final byNameDesc = await list(
        const LibraryQuery(sort: LibrarySortField.name),
      );
      expect(byNameDesc.folders.map((f) => f.id), [f1.id, f2.id]);
      expect(byNameDesc.notes.map((n) => n.id), [n1.id, n2.id]);
      final created = await list(
        const LibraryQuery(sort: LibrarySortField.createdAt, descending: false),
      );
      expect(created.folders.map((f) => f.id), [f1.id, f2.id]);
      expect(created.notes.map((n) => n.id), [n1.id, n2.id]);
      final createdDesc = await list(
        const LibraryQuery(sort: LibrarySortField.createdAt),
      );
      expect(createdDesc.notes.map((n) => n.id), [n2.id, n1.id]);
      final updated = await list(const LibraryQuery());
      expect(updated.notes.map((n) => n.id), [n2.id, n1.id]);
      await lib.renameNote(n1.id, 'Zeta 2');
      final updated2 = await list(const LibraryQuery());
      expect(updated2.notes.map((n) => n.id), [n1.id, n2.id]);
      final updatedAsc = await list(
        const LibraryQuery(sort: LibrarySortField.updatedAt, descending: false),
      );
      expect(updatedAsc.notes.map((n) => n.id), [n2.id, n1.id]);
      final custom = await list(
        const LibraryQuery(sort: LibrarySortField.custom),
      );
      expect(custom.folders.map((f) => f.id), [f1.id, f2.id]);
      expect(custom.notes.map((n) => n.id), [n1.id, n2.id]);
      final customDesc = await list(
        const LibraryQuery(sort: LibrarySortField.custom, descending: true),
      );
      expect(customDesc.notes.map((n) => n.id), [
        n1.id,
        n2.id,
      ], reason: 'descending is ignored for custom');

      final unknown = await list(const LibraryQuery(folderId: 'nope'));
      expect(unknown.folderId, 'nope');
      expect(unknown.folders, isEmpty);
      expect(unknown.notes, isEmpty);
    });

    test('a folder lists only its own children', () async {
      final f = await lib.createFolder(name: 'f');
      final sub = await lib.createFolder(name: 'sub', parentId: f.id);
      final inF = await lib.createNote(title: 'inF', folderId: f.id);
      await lib.createNote(title: 'top');
      await lib.createNote(title: 'inSub', folderId: sub.id);
      final listing = await lib
          .watchListing(LibraryQuery(folderId: f.id))
          .first;
      expect(listing.folderId, f.id);
      expect(listing.folders.map((x) => x.id), [sub.id]);
      expect(listing.notes.map((x) => x.id), [inF.id]);
      final top = await lib.watchListing(const LibraryQuery()).first;
      expect(top.folders.map((x) => x.id), [f.id]);
      expect(top.notes.map((x) => x.title), ['top']);
      await lib.trashItems([FolderRef(f.id)]);
      final gone = await lib.watchListing(LibraryQuery(folderId: f.id)).first;
      expect(gone.folders, isEmpty, reason: 'a trashed folder lists nothing');
      expect(gone.notes, isEmpty);
    });
  });

  group('C-3 get', () {
    test('getNote / getFolder also return trashed items', () async {
      final f = await lib.createFolder(name: 'f');
      final n = await lib.createNote(title: 'n', folderId: f.id);
      await lib.trashItems([FolderRef(f.id)]);
      final tf = (await lib.getFolder(f.id))!;
      final tn = (await lib.getNote(n.id))!;
      expect(tf.isDeleted, isTrue);
      expect(tf.trashRootId, f.id);
      expect(tn.isDeleted, isTrue);
      expect(tn.trashRootId, f.id);
      expect(await lib.getNote('purged-or-unknown'), isNull);
    });
  });

  group('C-4 move', () {
    test(
      'ignores items already there; a cycle throws and changes nothing',
      () async {
        final a = await lib.createFolder(name: 'a');
        final b = await lib.createFolder(name: 'b', parentId: a.id);
        final n = await lib.createNote(title: 'n');
        await expectLater(
          lib.moveItems([NoteRef(n.id), FolderRef(a.id)], targetFolderId: b.id),
          throwsA(isA<FolderCycleException>()),
        );
        expect((await lib.getNote(n.id))!.folderId, isNull, reason: 'atomic');
        await expectLater(
          lib.moveItems([FolderRef(a.id)], targetFolderId: a.id),
          throwsA(isA<FolderCycleException>()),
        );
        final bBefore = (await lib.getFolder(b.id))!;
        await lib.moveItems([
          NoteRef(n.id),
          FolderRef(b.id),
        ], targetFolderId: a.id);
        expect((await lib.getNote(n.id))!.folderId, a.id);
        expect(
          await lib.getFolder(b.id),
          bBefore,
          reason: 'already in the target: untouched',
        );
        await lib.moveItems([NoteRef(n.id)], targetFolderId: null);
        expect((await lib.getNote(n.id))!.folderId, isNull);
        await expectLater(
          lib.moveItems([NoteRef(n.id)], targetFolderId: 'missing'),
          throwsA(isA<EntityNotFoundException>()),
        );
        await expectLater(
          lib.moveItems([NoteRef('missing')], targetFolderId: a.id),
          throwsA(isA<EntityNotFoundException>()),
        );
      },
    );

    test(
      'moved items go after the last item of the target, in order',
      () async {
        final target = await lib.createFolder(name: 't');
        final existing = await lib.createNote(title: 'e', folderId: target.id);
        final n1 = await lib.createNote(title: '1');
        final n2 = await lib.createNote(title: '2');
        await lib.moveItems([
          NoteRef(n2.id),
          NoteRef(n1.id),
        ], targetFolderId: target.id);
        final custom = await lib
            .watchListing(
              LibraryQuery(folderId: target.id, sort: LibrarySortField.custom),
            )
            .first;
        expect(custom.notes.map((n) => n.id), [existing.id, n1.id, n2.id]);
      },
    );
  });

  group('C-5 / copy', () {
    test('copy cuts the original name, never a surrogate pair', () async {
      final emoji = '😀' * 99 + 'ab'; // 200 code units
      final n = await lib.createNote(title: emoji);
      final copies = await lib.copyItems(
        [NoteRef(n.id)],
        targetFolderId: null,
        nameSuffix: ' 사본',
      );
      final copy = (await lib.getNote(copies.single.id))!;
      expect(copy.title.length, lessThanOrEqualTo(200));
      expect(copy.title.endsWith(' 사본'), isTrue);
      final body = copy.title.substring(0, copy.title.length - 3);
      expect(body.codeUnits.last, isNot(inInclusiveRange(0xD800, 0xDBFF)));
      expect(copy.id, isNot(n.id));

      final short = await lib.createNote(title: 'short');
      final c2 = await lib.copyItems(
        [NoteRef(short.id)],
        targetFolderId: null,
        nameSuffix: ' (2)',
      );
      expect((await lib.getNote(c2.single.id))!.title, 'short (2)');
    });

    test('deep: folders, notes, pages, strokes under new ids', () async {
      final f = await lib.createFolder(name: 'f', colorArgb: 0xFF2196F3);
      final sub = await lib.createFolder(name: 'sub', parentId: f.id);
      const pageA = '0193f1d2-7c40-7000-8000-0000000000a1';
      final strokes = [
        for (var i = 0; i < 3; i++)
          StrokeFixtures.synthetic(
            pageId: pageA,
            ids: store.ids,
            seed: i,
            createdAt: 100 + i,
          ),
      ];
      final note = await lib.createNote(
        title: 'n',
        folderId: sub.id,
        pages: [
          PageDraft(
            id: pageA,
            size: PageSize.a4Portrait,
            background: const BlankBackground(),
            strokes: strokes,
          ),
          PageDraft.blankA4,
        ],
      );
      final copies = await lib.copyItems(
        [FolderRef(f.id)],
        targetFolderId: null,
        nameSuffix: ' 사본',
      );
      final tree = await lib.watchFolderTree().first;
      final copyRoot = tree.byId(copies.single.id)!;
      expect(copyRoot.name, 'f 사본');
      expect(copyRoot.colorArgb, 0xFF2196F3);
      expect(copyRoot.parentId, isNull);
      final copySub = tree.childrenOf(copyRoot.id).single;
      expect(
        copySub.name,
        'sub',
        reason: 'only the copied items get the suffix',
      );
      final copied =
          (await lib.watchListing(LibraryQuery(folderId: copySub.id)).first)
              .notes
              .single;
      expect(copied.id, isNot(note.id));
      expect(copied.title, 'n');
      expect(copied.pageCount, 2);
      final pages = await store.content.pagesOf(copied.id);
      expect(pages, hasLength(2));
      expect(copied.firstPageId, pages.first.id);
      expect(pages.first.id, isNot(pageA));
      final content = await store.content.loadPage(pages.first.id);
      expect(content.strokes, hasLength(3));
      final original = await store.content.loadPage(pageA);
      for (var i = 0; i < 3; i++) {
        expect(content.strokes[i].id, isNot(original.strokes[i].id));
        expect(content.strokes[i].pageId, pages.first.id);
        expect(
          content.strokes[i].points.contentEquals(original.strokes[i].points),
          isTrue,
        );
        expect(content.strokes[i].createdAt, original.strokes[i].createdAt);
      }
      // The original is untouched.
      expect((await lib.getNote(note.id))!.folderId, sub.id);
      expect(original.strokes, hasLength(3));
    });

    test(
      'missing items or target → EntityNotFoundException, nothing copied',
      () async {
        final n = await lib.createNote(title: 'n');
        await expectLater(
          lib.copyItems([
            NoteRef(n.id),
            NoteRef('missing'),
          ], targetFolderId: null),
          throwsA(isA<EntityNotFoundException>()),
        );
        await expectLater(
          lib.copyItems([NoteRef(n.id)], targetFolderId: 'missing'),
          throwsA(isA<EntityNotFoundException>()),
        );
        expect(
          (await lib.watchListing(const LibraryQuery()).first).notes,
          hasLength(1),
        );
      },
    );
  });

  group('C-6 names', () {
    test(
      'trimmed, 1..200 chars, else ArgumentError before any write',
      () async {
        expect((await lib.createFolder(name: '  hi  ')).name, 'hi');
        expect((await lib.createNote(title: ' t ')).title, 't');
        expect((await lib.createNote(title: 'x' * 200)).title, hasLength(200));
        await expectLater(lib.createFolder(name: '   '), throwsArgumentError);
        await expectLater(
          lib.createNote(title: 'x' * 201),
          throwsArgumentError,
        );
        await expectLater(
          lib.createNote(title: 'ok', pages: const []),
          throwsArgumentError,
        );
        await expectLater(
          lib.createNote(
            title: 'ok',
            pages: List.filled(2001, PageDraft.blankA4),
          ),
          throwsArgumentError,
        );
        final f = await lib.createFolder(name: 'f');
        await expectLater(lib.renameFolder(f.id, ''), throwsArgumentError);
        await expectLater(
          lib.setTags((await lib.createNote(title: 'n')).id, ['']),
          throwsArgumentError,
        );
        expect(store.persistenceStatus.pendingOps, 0);
        await expectLater(
          lib.renameNote('missing', 'x'),
          throwsA(isA<EntityNotFoundException>()),
        );
      },
    );

    test('rename / appearance / cover / tags / favorite round trip', () async {
      final f = await lib.createFolder(name: 'f', icon: 'school');
      await lib.renameFolder(f.id, 'g');
      await lib.setFolderAppearance(f.id, colorArgb: 0xFF00FF00);
      var got = (await lib.getFolder(f.id))!;
      expect(got.name, 'g');
      expect(got.colorArgb, 0xFF00FF00);
      expect(got.icon, 'school');
      expect(got.updatedAt, greaterThan(f.updatedAt));
      await lib.setFolderAppearance(f.id, clearColor: true, clearIcon: true);
      got = (await lib.getFolder(f.id))!;
      expect(got.colorArgb, isNull);
      expect(got.icon, isNull);

      final n = await lib.createNote(title: 'n');
      await lib.renameNote(n.id, 'm');
      await lib.setCover(n.id, const ColorCover(0xFFFF0000));
      await lib.setTags(n.id, [' math ', '2학기']);
      await lib.setFavorite([n.id, 'missing'], true);
      final gotNote = (await lib.getNote(n.id))!;
      expect(gotNote.title, 'm');
      expect(gotNote.cover, const ColorCover(0xFFFF0000));
      expect(gotNote.tags, ['math', '2학기']);
      expect(gotNote.isFavorite, isTrue);
      expect(gotNote.version! > n.version!, isTrue);
    });
  });

  group('C-7 recent / favorites / search', () {
    test('exclude trashed; empty query → empty; NFD titles match', () async {
      final nfdTitle = String.fromCharCodes([
        0x1100, 0x1161, 0x11BC, 0x110B, 0x1174, 0x0020, //
        0x1102, 0x1169, 0x1110, 0x1173,
      ]); // '강의 노트' (NFD)
      final a = await lib.createNote(title: nfdTitle);
      final b = await lib.createNote(title: 'Lecture');
      final f = await lib.createFolder(name: '강의 자료');
      await lib.setFavorite([a.id, b.id], true);
      await lib.markOpened(a.id);
      expect((await lib.watchRecentNotes().first).map((n) => n.id), [a.id]);
      expect(await lib.watchFavoriteNotes().first, hasLength(2));
      final r = await lib.searchLibrary('강의');
      expect(r.query, '강의');
      expect(r.notes.map((n) => n.id), [a.id]);
      expect(r.folders.map((x) => x.id), [f.id]);
      expect((await lib.searchLibrary('LECT')).notes.map((n) => n.id), [b.id]);
      expect((await lib.searchLibrary('  ')).notes, isEmpty);
      expect((await lib.searchLibrary('')).folders, isEmpty);
      await lib.trashItems([NoteRef(a.id), FolderRef(f.id)]);
      expect(await lib.watchRecentNotes().first, isEmpty);
      expect((await lib.watchFavoriteNotes().first).map((n) => n.id), [b.id]);
      final after = await lib.searchLibrary('강의');
      expect(after.notes, isEmpty);
      expect(after.folders, isEmpty);
    });

    test('recent: newest first, limit; search: newest first, limit', () async {
      final notes = [
        for (var i = 0; i < 4; i++) await lib.createNote(title: 'note $i'),
      ];
      for (final n in notes.reversed) {
        await lib.markOpened(n.id);
      }
      expect((await lib.watchRecentNotes(limit: 3).first).map((n) => n.id), [
        notes[0].id,
        notes[1].id,
        notes[2].id,
      ]);
      final s = await lib.searchLibrary('NOTE', limit: 2);
      expect(s.notes.map((n) => n.id), [notes[3].id, notes[2].id]);
    });

    test('search treats % _ \\ literally', () async {
      final pct = await lib.createNote(title: '100% done');
      final under = await lib.createNote(title: 'a_b');
      final slash = await lib.createNote(title: r'c\d');
      await lib.createNote(title: 'axb');
      expect((await lib.searchLibrary('%')).notes.map((n) => n.id), [pct.id]);
      expect((await lib.searchLibrary('a_b')).notes.map((n) => n.id), [
        under.id,
      ]);
      expect((await lib.searchLibrary(r'\')).notes.map((n) => n.id), [
        slash.id,
      ]);
    });
  });

  group('C-9 derived note values', () {
    test('createNote: pageCount and firstPageId = first active page', () async {
      final note = await lib.createNote(
        title: 'n',
        pages: const [PageDraft.blankA4, PageDraft.blankA4],
      );
      final pages = await store.content.pagesOf(note.id);
      expect(note.pageCount, 2);
      expect(note.firstPageId, pages.first.id);
      expect(await lib.getNote(note.id), note);
      expect(pages.every((p) => p.contentRevision == 0), isTrue);
      expect(note.version, isNotNull);
    });
  });

  group('C-10 / reorderItems', () {
    test(
      'call order; one commit; relative order kept; mixed rejected',
      () async {
        final n = [
          for (var i = 0; i < 4; i++) await lib.createNote(title: 'n$i'),
        ];
        await lib.reorderItem(NoteRef(n[3].id), before: NoteRef(n[0].id));
        final batches = <ChangeBatch>[];
        final sub = store.changes.listen(batches.add);
        await lib.reorderItems([
          NoteRef(n[2].id),
          NoteRef(n[1].id),
        ], after: NoteRef(n[3].id));
        await pumpEventQueue();
        await sub.cancel();
        expect(batches, hasLength(1), reason: 'ONE commit');
        final custom = await lib
            .watchListing(const LibraryQuery(sort: LibrarySortField.custom))
            .first;
        expect(custom.notes.map((x) => x.title), ['n3', 'n1', 'n2', 'n0']);

        // Consecutive calls without awaiting apply in call order.
        final f1 = lib.reorderItem(NoteRef(n[0].id));
        final f2 = lib.reorderItem(NoteRef(n[3].id));
        await Future.wait([f1, f2]);
        final again = await lib
            .watchListing(const LibraryQuery(sort: LibrarySortField.custom))
            .first;
        expect(again.notes.map((x) => x.title), ['n1', 'n2', 'n0', 'n3']);

        final f = await lib.createFolder(name: 'f');
        await expectLater(
          lib.reorderItems([NoteRef(n[0].id), FolderRef(f.id)]),
          throwsArgumentError,
        );
        final inF = await lib.createNote(title: 'x', folderId: f.id);
        await expectLater(
          lib.reorderItems([NoteRef(n[0].id), NoteRef(inF.id)]),
          throwsArgumentError,
        );
        await expectLater(
          lib.reorderItem(NoteRef(n[0].id), after: NoteRef(inF.id)),
          throwsArgumentError,
        );
        await expectLater(
          lib.reorderItem(NoteRef(n[0].id), after: NoteRef(n[0].id)),
          throwsArgumentError,
        );
        await lib.reorderItems(const []);
      },
    );

    test('folders reorder among folders', () async {
      final a = await lib.createFolder(name: 'a');
      final b = await lib.createFolder(name: 'b');
      final c = await lib.createFolder(name: 'c');
      await lib.reorderItem(FolderRef(c.id), after: FolderRef(a.id));
      final tree = await lib.watchFolderTree().first;
      expect(tree.roots.map((x) => x.id), [a.id, c.id, b.id]);
    });
  });

  group('C-8 / trash', () {
    test('restore moves to the nearest active ancestor', () async {
      final parent = await lib.createFolder(name: 'parent');
      final child = await lib.createFolder(name: 'child', parentId: parent.id);
      final note = await lib.createNote(title: 'n', folderId: child.id);
      await lib.trashItems([NoteRef(note.id)]);
      expect((await lib.getNote(note.id))!.isDeleted, isTrue);
      await lib.trashItems([FolderRef(child.id)]);
      await store.trash.restore([NoteRef(note.id)]);
      final restored = (await lib.getNote(note.id))!;
      expect(restored.isDeleted, isFalse);
      expect(restored.trashRootId, isNull);
      expect(restored.folderId, parent.id);
      final listing = await lib
          .watchListing(LibraryQuery(folderId: parent.id))
          .first;
      expect(listing.notes.map((n) => n.id), [note.id]);
    });

    test('restore: parent purged → top level, at the end', () async {
      final f = await lib.createFolder(name: 'f');
      final n = await lib.createNote(title: 'n', folderId: f.id);
      final top = await lib.createNote(title: 'top');
      await lib.trashItems([NoteRef(n.id)]);
      await lib.trashItems([FolderRef(f.id)]);
      await store.trash.purge([FolderRef(f.id)]);
      expect(await lib.getFolder(f.id), isNull);
      await store.trash.restore([NoteRef(n.id)]);
      final restored = (await lib.getNote(n.id))!;
      expect(restored.folderId, isNull);
      final custom = await lib
          .watchListing(const LibraryQuery(sort: LibrarySortField.custom))
          .first;
      expect(custom.notes.map((x) => x.id), [top.id, n.id]);
    });

    test('a group restores together; the representative keeps its place '
        'when the parent is active', () async {
      final f = await lib.createFolder(name: 'f');
      final sub = await lib.createFolder(name: 'sub', parentId: f.id);
      final inSub = await lib.createNote(title: 'inSub', folderId: sub.id);
      await lib.trashItems([FolderRef(sub.id)]);
      await store.trash.restore([FolderRef(sub.id)]);
      expect((await lib.getFolder(sub.id))!.parentId, f.id);
      expect((await lib.getFolder(sub.id))!.isDeleted, isFalse);
      expect((await lib.getNote(inSub.id))!.isDeleted, isFalse);
      expect((await lib.getNote(inSub.id))!.folderId, sub.id);
      // Restoring an active item does nothing; an unknown one throws.
      await store.trash.restore([NoteRef(inSub.id)]);
      await expectLater(
        store.trash.restore([NoteRef('missing')]),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('watchTrash: representatives newest first, counts, expiresAt; '
        'purge removes the group', () async {
      final f = await lib.createFolder(name: 'f');
      final sub = await lib.createFolder(name: 'sub', parentId: f.id);
      final inSub = await lib.createNote(title: 'inSub', folderId: sub.id);
      final early = await lib.createNote(title: 'early', folderId: f.id);
      final values = <List<TrashItem>>[];
      final sub$ = store.trash.watchTrash().listen(values.add);
      await pumpEventQueue();
      expect(values.single, isEmpty);
      await lib.trashItems([NoteRef(early.id)]);
      await lib.trashItems([FolderRef(f.id)]);
      await pumpEventQueue();
      final trash = values.last;
      expect(trash.map((t) => t.ref), [FolderRef(f.id), NoteRef(early.id)]);
      final folderItem = trash.first as TrashedFolder;
      expect(folderItem.name, 'f');
      expect(folderItem.folderCount, 1);
      expect(folderItem.noteCount, 1);
      expect(
        folderItem.expiresAt,
        folderItem.deletedAt + const Duration(days: 30).inMilliseconds,
      );
      expect((trash.last as TrashedNote).note.id, early.id);
      await store.trash.restore([FolderRef(f.id)]);
      expect((await lib.getNote(inSub.id))!.isDeleted, isFalse);
      expect((await lib.getNote(early.id))!.isDeleted, isTrue);
      await store.trash.purge([NoteRef(early.id), NoteRef(inSub.id)]);
      expect(await lib.getNote(early.id), isNull);
      expect(
        await lib.getNote(inSub.id),
        isNotNull,
        reason: 'purge ignores items that are not in the trash',
      );
      await pumpEventQueue();
      expect(values.last, isEmpty);
      await sub$.cancel();
    });

    test('purge deletes the pages and strokes of the group', () async {
      const pageId = '0193f1d2-7c40-7000-8000-0000000000a9';
      final n = await lib.createNote(
        title: 'n',
        pages: [
          PageDraft(
            id: pageId,
            size: PageSize.a4Portrait,
            background: const BlankBackground(),
            strokes: [StrokeFixtures.synthetic(pageId: pageId, ids: store.ids)],
          ),
        ],
      );
      await lib.trashItems([NoteRef(n.id)]);
      expect((await store.content.loadPage(pageId)).strokes, hasLength(1));
      await store.trash.purge([NoteRef(n.id)]);
      expect(await store.content.getPage(pageId), isNull);
      expect(await store.content.pagesOf(n.id), isEmpty);
      await expectLater(
        store.content.loadPage(pageId),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('emptyTrash purges every group', () async {
      final f = await lib.createFolder(name: 'f');
      final a = await lib.createNote(title: 'a', folderId: f.id);
      final b = await lib.createNote(title: 'b');
      final keep = await lib.createNote(title: 'keep');
      await lib.trashItems([FolderRef(f.id), NoteRef(b.id)]);
      await store.trash.emptyTrash();
      expect(await store.trash.watchTrash().first, isEmpty);
      expect(await lib.getFolder(f.id), isNull);
      expect(await lib.getNote(a.id), isNull);
      expect(await lib.getNote(b.id), isNull);
      expect(await lib.getNote(keep.id), isNotNull);
    });

    test(
      'purgeExpired: 29 days 23 hours kept, 30 days 1 minute purged',
      () async {
        final n = await lib.createNote(title: 'old');
        final m = await lib.createNote(title: 'newer');
        await lib.trashItems([NoteRef(n.id)]);
        final deletedAt = (await lib.getNote(n.id))!.deletedAt!;
        ms = deletedAt + const Duration(days: 10).inMilliseconds;
        await lib.trashItems([NoteRef(m.id)]);
        ms = deletedAt + const Duration(days: 29, hours: 23).inMilliseconds;
        expect(await store.trash.purgeExpired(), 0);
        expect(await lib.getNote(n.id), isNotNull);
        ms = deletedAt + const Duration(days: 30, minutes: 1).inMilliseconds;
        expect(await store.trash.purgeExpired(), 1);
        expect(await lib.getNote(n.id), isNull);
        expect(await lib.getNote(m.id), isNotNull);
        expect((await store.trash.watchTrash().first).map((t) => t.ref), [
          NoteRef(m.id),
        ]);
      },
    );
  });

  group('changes and trash', () {
    test('one local ChangeBatch per commit with hints', () async {
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      final note = await lib.createNote(
        title: 'n',
        pages: const [PageDraft.blankA4],
      );
      await pumpEventQueue();
      expect(batches, hasLength(1));
      final b = batches.single;
      expect(b.origin, ChangeOrigin.local);
      expect(b.changes.first.kind, EntityKind.note);
      expect(b.changes.first.id, note.id);
      final pageChange = b.changes.firstWhere((c) => c.kind == EntityKind.page);
      expect(pageChange.noteId, note.id);
      await lib.markOpened(note.id);
      await pumpEventQueue();
      expect(batches, hasLength(1), reason: 'markOpened is local only');
      await sub.cancel();
    });

    test(
      'trashItems: folder takes its active subtree; a note only itself',
      () async {
        final f = await lib.createFolder(name: 'f');
        final sub = await lib.createFolder(name: 'sub', parentId: f.id);
        final inSub = await lib.createNote(title: 'inSub', folderId: sub.id);
        final early = await lib.createNote(title: 'early', folderId: f.id);
        final other = await lib.createNote(title: 'other');
        await lib.trashItems([NoteRef(early.id)]);
        await lib.trashItems([FolderRef(f.id)]);
        expect((await lib.getFolder(sub.id))!.trashRootId, f.id);
        expect((await lib.getNote(inSub.id))!.trashRootId, f.id);
        expect(
          (await lib.getNote(early.id))!.trashRootId,
          early.id,
          reason: 'keeps its own group',
        );
        expect((await lib.getNote(other.id))!.isDeleted, isFalse);
        await lib.trashItems([FolderRef(f.id)]); // already trashed: no-op
        await expectLater(
          lib.trashItems([NoteRef('missing')]),
          throwsA(isA<EntityNotFoundException>()),
        );
        final top = await lib.watchListing(const LibraryQuery()).first;
        expect(top.folders, isEmpty);
        expect(top.notes.map((n) => n.id), [other.id]);
      },
    );
  });
}
