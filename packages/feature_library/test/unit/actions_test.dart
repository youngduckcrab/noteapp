// LibraryActions (05-library 6.11, 8 L7): every method leaves the right entry
// in backend.calls and changes CORE; failures are classified and reported
// (except folderCycle / invalidName); markOpened is never called (S-5).
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/folder_appearance_value.dart';
import 'package:feature_library/src/model/item_key.dart';
import 'package:feature_library/src/model/new_note_spec.dart';
import 'package:feature_library/src/state/library_actions.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';

void main() {
  late FakeLibraryBackend backend;
  late SampleLibrary lib;
  late LibraryActions actions;
  late List<String> reported;

  setUp(() async {
    backend = FakeLibraryBackend();
    lib = await seedSampleLibrary(backend);
    reported = [];
    actions = LibraryActions(
      library: backend.library,
      trash: backend.trash,
      report: (error, stack, context) => reported.add('$context: $error'),
    );
  });
  tearDown(() async {
    // S-5: LIBRARY never records '최근' itself.
    expect(backend.calls.where((c) => c.startsWith('markOpened')), isEmpty);
    await backend.dispose();
  });

  T successOf<T>(ActionOutcome<T> outcome) => switch (outcome) {
    ActionSuccess(:final value) => value,
    ActionFailure() => fail('expected success, got $outcome'),
  };

  LibraryFailureKind failureOf(ActionOutcome<Object?> outcome) =>
      switch (outcome) {
        ActionFailure(:final kind) => kind,
        ActionSuccess() => fail('expected failure, got $outcome'),
      };

  Future<Folder> folder(FolderId id) async =>
      (await backend.store.library.getFolder(id))!;
  Future<Note> note(NoteId id) async =>
      (await backend.store.library.getNote(id))!;

  group('calls and CORE effects', () {
    test('createNote: title, one page from the options, cover', () async {
      final created = successOf(
        await actions.createNote(
          const NewNoteSpec(
            title: '새 노트 1',
            options: NewNoteOptions(
              preset: PageSizePreset.widescreen16x9,
              orientation: PageOrientationChoice.landscape,
              template: PageTemplateKind.grid,
              paperColorArgb: PaperColors.black,
            ),
            cover: ColorCover(0xFF336699),
          ),
          folderId: lib.math.id,
        ),
      );
      expect(backend.calls, [
        "createNote f:${lib.math.id} '새 노트 1' pages:1 cover:color:0xFF336699",
      ]);
      expect(created.title, '새 노트 1');
      expect(created.folderId, lib.math.id);
      expect(created.cover, const ColorCover(0xFF336699));
      final page = (await backend.store.content.pagesOf(created.id)).single;
      expect(page.size, PageSize.widescreen16x9);
      expect(
        page.background,
        isA<TemplateBackground>()
            .having((b) => b.template.kind, 'kind', PageTemplateKind.grid)
            .having((b) => b.paperColorArgb, 'paper', PaperColors.black),
      );
    });

    test('createFolder: name, color and icon', () async {
      final created = successOf(
        await actions.createFolder(
          const NewFolderSpec(
            name: '물리',
            appearance: FolderAppearance(colorArgb: 0xFF00AA00, icon: 'book'),
          ),
          parentId: null,
        ),
      );
      expect(backend.calls, [
        "createFolder home '물리' color:0xFF00AA00 icon:book",
      ]);
      expect(created.parentId, isNull);
      expect(created.colorArgb, 0xFF00AA00);
      expect(created.icon, 'book');
    });

    test('rename folder / note', () async {
      successOf(await actions.rename(folderKey(lib.math.id), '수학 I'));
      successOf(
        await actions.rename(noteKey(lib.homeNotes.first.id), '회의록 11월'),
      );
      expect(backend.calls, [
        "renameFolder f:${lib.math.id} '수학 I'",
        "renameNote n:${lib.homeNotes.first.id} '회의록 11월'",
      ]);
      expect((await folder(lib.math.id)).name, '수학 I');
      expect((await note(lib.homeNotes.first.id)).title, '회의록 11월');
    });

    test('setFolderAppearance: none → clearColor / clearIcon', () async {
      final id = lib.english.id;
      successOf(
        await actions.setFolderAppearance(
          id,
          const FolderAppearance(colorArgb: 0xFFAA0000, icon: 'star'),
        ),
      );
      expect((await folder(id)).colorArgb, 0xFFAA0000);
      expect((await folder(id)).icon, 'star');
      successOf(
        await actions.setFolderAppearance(id, const FolderAppearance()),
      );
      expect(backend.calls, [
        'setFolderAppearance f:$id color:0xFFAA0000 icon:star',
        'setFolderAppearance f:$id clearColor clearIcon',
      ]);
      expect((await folder(id)).colorArgb, isNull);
      expect((await folder(id)).icon, isNull);
    });

    test('setCover / setFavorite', () async {
      final a = lib.homeNotes[0].id;
      final b = lib.homeNotes[1].id;
      successOf(await actions.setCover(a, const ColorCover(0xFF123456)));
      successOf(await actions.setFavorite([a, b], true));
      expect(backend.calls, [
        'setCover n:$a color:0xFF123456',
        'setFavorite [n:$a, n:$b] true',
      ]);
      expect((await note(a)).cover, const ColorCover(0xFF123456));
      expect((await note(a)).isFavorite, isTrue);
      expect((await note(b)).isFavorite, isTrue);
    });

    test('move → receipt of the items that really moved → undoMove', () async {
      final n0 = lib.homeNotes[0].id; // at home
      final deep = lib.deepNote.id; // in 연습 문제
      final calc = lib.nested.first.id; // 미적분, in 수학
      final target = lib.english.id;
      final there = (await backend.seedNote('영어 노트', folderId: target)).id;
      final receipt = successOf(
        await actions.move(
          [noteKey(n0), noteKey(deep), folderKey(calc), noteKey(there)],
          target: target,
          originalParents: {
            noteKey(n0): null,
            noteKey(deep): lib.deepest.id,
            folderKey(calc): lib.math.id,
            // Already in the target: CORE ignores it (C-4), so does the
            // receipt.
            noteKey(there): target,
          },
        ),
      );
      expect(backend.calls, [
        'moveItems [n:$n0, n:$deep, f:$calc, n:$there] -> f:$target',
      ]);
      expect(
        receipt,
        MoveReceipt({
          noteKey(n0): null,
          noteKey(deep): lib.deepest.id,
          folderKey(calc): lib.math.id,
        }),
      );
      expect((await note(n0)).folderId, target);
      expect((await note(deep)).folderId, target);
      expect((await folder(calc)).parentId, target);
      backend.calls.clear();

      successOf(await actions.undoMove(receipt));
      // Grouped by original parent, one moveItems per parent.
      expect(backend.calls, [
        'moveItems [n:$n0] -> home',
        'moveItems [n:$deep] -> f:${lib.deepest.id}',
        'moveItems [f:$calc] -> f:${lib.math.id}',
      ]);
      expect((await note(n0)).folderId, isNull);
      expect((await note(deep)).folderId, lib.deepest.id);
      expect((await folder(calc)).parentId, lib.math.id);
      expect((await note(there)).folderId, target);
    });

    test('undoMove groups items of the same parent into one call', () async {
      final a = lib.homeNotes[0].id;
      final b = lib.homeNotes[1].id;
      final f = lib.science.id;
      final receipt = successOf(
        await actions.move(
          [noteKey(a), folderKey(f), noteKey(b)],
          target: lib.english.id,
          originalParents: {
            noteKey(a): null,
            folderKey(f): null,
            noteKey(b): null,
          },
        ),
      );
      backend.calls.clear();
      successOf(await actions.undoMove(receipt));
      expect(backend.calls, ['moveItems [n:$a, f:$f, n:$b] -> home']);
      expect((await folder(f)).parentId, isNull);
    });

    test('copy with a suffix', () async {
      final refs = successOf(
        await actions.copy(
          [noteKey(lib.homeNotes[2].id)],
          target: null,
          nameSuffix: LibraryStrings.copySuffix,
        ),
      );
      expect(backend.calls, [
        "copyItems [n:${lib.homeNotes[2].id}] -> home suffix:' 사본'",
      ]);
      final copy = await note(refs.single.id);
      expect(copy.title, '아이디어 사본');
      expect(copy.folderId, isNull);
    });

    test('reorder: one item → reorderItem, after / before', () async {
      final [a, b, c, _] = [for (final n in lib.homeNotes) n.id];
      successOf(
        await actions.reorder([noteKey(a)], anchor: noteKey(c), after: true),
      );
      successOf(
        await actions.reorder([noteKey(c)], anchor: noteKey(b), after: false),
      );
      expect(backend.calls, [
        'reorderItem n:$a after:n:$c',
        'reorderItem n:$c before:n:$b',
      ]);
    });

    test('reorder: several items → ONE reorderItems, after / before', () async {
      final [a, b, c, d] = [for (final n in lib.homeNotes) n.id];
      successOf(
        await actions.reorder(
          [noteKey(c), noteKey(a)],
          anchor: noteKey(d),
          after: true,
        ),
      );
      expect(backend.calls, ['reorderItems [n:$c, n:$a] after:n:$d']);
      final custom = await backend.store.library
          .watchListing(const LibraryQuery(sort: LibrarySortField.custom))
          .first;
      // CORE keeps the items' current relative order (a before c).
      expect([for (final n in custom.notes) n.id], [b, d, a, c]);

      backend.calls.clear();
      successOf(
        await actions.reorder(
          [noteKey(a), noteKey(d)],
          anchor: noteKey(b),
          after: false,
        ),
      );
      expect(backend.calls, ['reorderItems [n:$a, n:$d] before:n:$b']);
      final again = await backend.store.library
          .watchListing(const LibraryQuery(sort: LibrarySortField.custom))
          .first;
      expect([for (final n in again.notes) n.id], [d, a, b, c]);
    });

    test('reorder with no items calls nothing', () async {
      successOf(
        await actions.reorder(
          const [],
          anchor: noteKey(lib.homeNotes[0].id),
          after: true,
        ),
      );
      expect(backend.calls, isEmpty);
    });

    test('trash → restore (undo) → trash → purge, emptyTrash', () async {
      final n = lib.homeNotes[3].id;
      final f = lib.science.id;
      successOf(await actions.trash([noteKey(n), folderKey(f)]));
      expect((await note(n)).isDeleted, isTrue);
      expect((await folder(f)).isDeleted, isTrue);
      successOf(await actions.restore([noteKey(n), folderKey(f)]));
      expect((await note(n)).isDeleted, isFalse);
      successOf(await actions.trash([noteKey(n)]));
      successOf(await actions.purge([noteKey(n)]));
      expect(await backend.store.library.getNote(n), isNull);
      successOf(await actions.trash([folderKey(f)]));
      successOf(await actions.emptyTrash());
      expect(await backend.store.library.getFolder(f), isNull);
      expect(backend.calls, [
        'trashItems [n:$n, f:$f]',
        'restore [n:$n, f:$f]',
        'trashItems [n:$n]',
        'purge [n:$n]',
        'trashItems [f:$f]',
        'emptyTrash',
      ]);
    });

    test('locate: parent after restore, null when gone', () async {
      final deep = lib.deepNote.id;
      await actions.trash([noteKey(deep)]);
      await actions.restore([noteKey(deep)]);
      expect(await actions.locate(noteKey(deep)), (parentId: lib.deepest.id));
      expect(await actions.locate(folderKey(lib.math.id)), (parentId: null));
      expect(await actions.locate(folderKey(lib.nested.first.id)), (
        parentId: lib.math.id,
      ));
      expect(await actions.locate(noteKey('nope')), isNull);
      expect(await actions.locate(folderKey('nope')), isNull);
      expect(reported, isEmpty);
    });
  });

  group('default names', () {
    test('uniqueNoteTitle looks at the notes of the target folder', () async {
      expect(await actions.uniqueNoteTitle(null), '제목 없는 노트');
      await backend.seedNote('제목 없는 노트');
      await backend.seedNote('제목 없는 노트 2');
      expect(await actions.uniqueNoteTitle(null), '제목 없는 노트 3');
      // Another folder has its own names.
      expect(await actions.uniqueNoteTitle(lib.math.id), '제목 없는 노트');
      expect(backend.calls, isEmpty);
    });

    test('uniqueFolderName looks at the sub-folders in the tree', () async {
      await backend.seedFolder('새 폴더');
      await backend.seedFolder('새 폴더', parentId: lib.math.id);
      await backend.seedFolder('새 폴더 2', parentId: lib.math.id);
      final tree = await backend.store.library.watchFolderTree().first;
      expect(actions.uniqueFolderName(null, tree), '새 폴더 2');
      expect(actions.uniqueFolderName(lib.math.id, tree), '새 폴더 3');
      expect(actions.uniqueFolderName(lib.english.id, tree), '새 폴더');
    });
  });

  group('classification and reporting', () {
    test(
      'a folder into its own sub-folder → folderCycle, not reported',
      () async {
        final outcome = await actions.move(
          [noteKey(lib.homeNotes[0].id), folderKey(lib.math.id)],
          target: lib.deepest.id,
          originalParents: {folderKey(lib.math.id): null},
        );
        expect(failureOf(outcome), LibraryFailureKind.folderCycle);
        expect((outcome as ActionFailure).error, isA<FolderCycleException>());
        expect(reported, isEmpty);
        // Atomic: nothing moved, the note neither.
        expect((await folder(lib.math.id)).parentId, isNull);
        expect((await note(lib.homeNotes[0].id)).folderId, isNull);
      },
    );

    test('unknown id → notFound, reported', () async {
      final outcome = await actions.rename(noteKey('nope'), 'x');
      expect(failureOf(outcome), LibraryFailureKind.notFound);
      expect(reported, hasLength(1));
      expect(reported.single, startsWith('library action: rename: '));
    });

    test('201-character name → invalidName, not reported', () async {
      final outcome = await actions.rename(folderKey(lib.math.id), 'ㄱ' * 201);
      expect(failureOf(outcome), LibraryFailureKind.invalidName);
      expect((outcome as ActionFailure).error, isA<ArgumentError>());
      expect(reported, isEmpty);
      expect((await folder(lib.math.id)).name, '수학');
      // 200 is fine.
      successOf(await actions.rename(folderKey(lib.math.id), 'ㄱ' * 200));
    });

    test('blank name → invalidName', () async {
      final outcome = await actions.createFolder(
        const NewFolderSpec(name: '   '),
        parentId: null,
      );
      expect(failureOf(outcome), LibraryFailureKind.invalidName);
      expect(reported, isEmpty);
    });

    test('any other error (failNextMutation = StateError) → unknown, '
        'reported', () async {
      backend.failNextMutation = StateError('disk');
      final outcome = await actions.trash([noteKey(lib.homeNotes[0].id)]);
      expect(failureOf(outcome), LibraryFailureKind.unknown);
      expect((outcome as ActionFailure).error, isA<StateError>());
      expect(reported, ['library action: trash: Bad state: disk']);
      // The call was still logged; nothing changed; the next one works.
      expect(backend.calls, ['trashItems [n:${lib.homeNotes[0].id}]']);
      expect((await note(lib.homeNotes[0].id)).isDeleted, isFalse);
      successOf(await actions.trash([noteKey(lib.homeNotes[0].id)]));
    });

    test('classifyLibraryError', () {
      expect(
        classifyLibraryError(const FolderCycleException('x')),
        LibraryFailureKind.folderCycle,
      );
      expect(
        classifyLibraryError(const EntityNotFoundException('x')),
        LibraryFailureKind.notFound,
      );
      expect(
        classifyLibraryError(ArgumentError('x')),
        LibraryFailureKind.invalidName,
      );
      expect(
        classifyLibraryError(RangeError('x')),
        LibraryFailureKind.invalidName,
      );
      expect(
        classifyLibraryError(const ReadOnlyNoteException('x')),
        LibraryFailureKind.unknown,
      );
      expect(classifyLibraryError('text'), LibraryFailureKind.unknown);
    });

    test('a failed read for a default title → base name, reported', () async {
      final failing = LibraryActions(
        library: _FailingListing(backend.library),
        trash: backend.trash,
        report: (error, stack, context) => reported.add(context),
      );
      expect(await failing.uniqueNoteTitle(null), '제목 없는 노트');
      expect(reported, ['library action: uniqueNoteTitle']);
    });
  });

  test(
    'libraryActionsProvider reports with library: feature_library',
    () async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      final container = ProviderContainer.test(overrides: backend.overrides);
      final fromProvider = container.read(libraryActionsProvider);

      successOf(await fromProvider.rename(folderKey(lib.math.id), '수학 II'));
      expect(backend.calls, ["renameFolder f:${lib.math.id} '수학 II'"]);

      backend.failNextMutation = StateError('boom');
      failureOf(await fromProvider.setFavorite([lib.homeNotes[0].id], true));
      failureOf(
        await fromProvider.move(
          [folderKey(lib.math.id)],
          target: lib.deepest.id,
          originalParents: const {},
        ),
      );
      expect(errors, hasLength(1)); // the cycle is not reported
      expect(errors.single.library, 'feature_library');
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.context.toString(), 'library action: setFavorite');
    },
  );
}

/// LibraryRepository whose watchListing fails (everything else delegates).
final class _FailingListing implements LibraryRepository {
  _FailingListing(this._inner);
  final LibraryRepository _inner;

  @override
  Stream<LibraryListing> watchListing(LibraryQuery query) =>
      Stream.error(StateError('listing'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} via $_inner');
}
