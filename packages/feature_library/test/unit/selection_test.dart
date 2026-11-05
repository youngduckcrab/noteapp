// LibrarySelection / LibrarySelectionNotifier (05-library 6.3.3 / 6.9, 8 L4).
import 'package:feature_library/src/model/item_key.dart';
import 'package:feature_library/src/model/selection.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/state/selection_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';

void main() {
  final f1 = folderKey('f1');
  final f2 = folderKey('f2');
  final n1 = noteKey('n1');
  final n2 = noteKey('n2');
  final n3 = noteKey('n3');

  group('LibrarySelection', () {
    test('none is inactive and empty', () {
      expect(LibrarySelection.none.active, isFalse);
      expect(LibrarySelection.none.count, 0);
      expect(LibrarySelection.none.contains(n1), isFalse);
    });

    test('keys in insertion order, duplicates dropped', () {
      final s = LibrarySelection.activeWith([n2, f1, n2, n1]);
      expect(s.keys, [n2, f1, n1]);
      expect(s.count, 3);
      expect(s.contains(f1), isTrue);
      expect(s.contains(f2), isFalse);
      expect(s.hasFolders, isTrue);
      expect(s.hasNotes, isTrue);
      expect(s.folderIds, ['f1']);
      expect(s.noteIds, ['n2', 'n1']);
    });

    test(
      'inDisplayOrder follows the display order, not the selection order',
      () {
        final s = LibrarySelection.activeWith([n3, f2, n1]);
        expect(s.inDisplayOrder([f1, f2, n1, n2, n3]), [f2, n1, n3]);
        expect(s.inDisplayOrder(const []), isEmpty);
      },
    );

    test('kinds are told apart by the key, not the id', () {
      final s = LibrarySelection.activeWith([folderKey('x')]);
      expect(s.contains(noteKey('x')), isFalse);
      expect(s.hasNotes, isFalse);
    });

    test('value equality', () {
      expect(
        LibrarySelection.activeWith([n1, f1]),
        LibrarySelection.activeWith([n1, f1]),
      );
      expect(
        LibrarySelection.activeWith([n1, f1]),
        isNot(LibrarySelection.activeWith([f1, n1])),
      );
      expect(
        LibrarySelection.activeWith(const []),
        isNot(LibrarySelection.none),
      );
    });

    test('keys convert to CORE refs', () {
      expect(f1.toRef(), const FolderRef('f1'));
      expect(n1.toRef(), const NoteRef('n1'));
      expect(keyOfRef(const NoteRef('n1')), n1);
      expect(f1.isFolder, isTrue);
      expect(n1.isFolder, isFalse);
    });
  });

  group('LibrarySelectionNotifier', () {
    late FakeLibraryBackend backend;
    late ProviderContainer container;
    late LibrarySelection Function() selection;
    late LibrarySelectionNotifier notifier;

    setUp(() {
      backend = FakeLibraryBackend();
      container = ProviderContainer.test(overrides: backend.overrides);
      selection = container
          .listen(librarySelectionProvider('f1'), (_, _) {})
          .read;
      notifier = container.read(librarySelectionProvider('f1').notifier);
    });
    tearDown(() => backend.dispose());

    test('begin with and without a first item', () {
      notifier.begin();
      expect(selection().active, isTrue);
      expect(selection().keys, isEmpty);
      notifier.end();
      notifier.begin(n1);
      expect(selection().keys, [n1]);
      notifier.begin(n2);
      expect(selection().keys, [n1, n2]);
    });

    test('toggle adds and removes; mode stays on when empty', () {
      notifier.toggle(n1);
      notifier.toggle(f1);
      expect(selection().keys, [n1, f1]);
      notifier.toggle(n1);
      expect(selection().keys, [f1]);
      notifier.toggle(f1);
      expect(selection().active, isTrue);
      expect(selection().keys, isEmpty);
    });

    test('add keeps existing keys and ignores a selected one', () {
      notifier.add(n1);
      notifier.add(n2);
      notifier.add(n1);
      expect(selection().keys, [n1, n2]);
    });

    test('selectAll, clearKeys and end', () {
      notifier.selectAll([f1, n1, n2]);
      expect(selection().keys, [f1, n1, n2]);
      notifier.clearKeys();
      expect(selection().active, isTrue);
      expect(selection().count, 0);
      notifier.end();
      expect(selection(), LibrarySelection.none);
    });

    test('retainVisible drops keys that disappeared', () {
      notifier.selectAll([f1, n1, n2]);
      final before = selection();
      notifier.retainVisible({f1, n1, n2, n3});
      expect(selection(), same(before)); // unchanged: no new state
      notifier.retainVisible({n2, f2});
      expect(selection().keys, [n2]);
      expect(selection().active, isTrue);
      notifier.end();
      notifier.retainVisible(const <LibraryItemKey>{});
      expect(selection(), LibrarySelection.none);
    });

    test('a section change of the same route clears the selection', () {
      final section = container.read(librarySectionProvider('f1').notifier);
      notifier.selectAll([n1, n2]);
      section.showRecent();
      expect(selection(), LibrarySelection.none);

      notifier.begin(n1);
      section.search('a');
      expect(selection(), LibrarySelection.none);
      notifier.begin(n1);
      section.search('ab'); // another query is another section
      expect(selection(), LibrarySelection.none);
      notifier.begin(n1);
      section.exitSearch();
      expect(selection(), LibrarySelection.none);
    });

    test("another route's section change does not touch this selection", () {
      container.listen(librarySelectionProvider(null), (_, _) {});
      notifier.selectAll([n1]);
      container.read(librarySectionProvider(null).notifier).showTrash();
      expect(selection().keys, [n1]);
    });

    test('setting the same section again keeps the selection', () {
      notifier.selectAll([n1]);
      container.read(librarySectionProvider('f1').notifier).showRouteFolder();
      expect(selection().keys, [n1]);
    });
  });
}
