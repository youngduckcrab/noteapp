// LibraryDragHandle / LibraryDragPayload / contentDragPayload (05-library
// 6.10.1, 8 L15): the payload is built once, on first access; outside and
// inside selection mode the pressed item is always in it, in display order.
import 'package:feature_library/src/dnd/drag_payload.dart';
import 'package:feature_library/src/model/content.dart';
import 'package:feature_library/src/model/item_key.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/model/selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

Folder folder(String id, {String? parent}) => Folder(
  id: id,
  ownerId: kLocalOwnerId,
  parentId: parent,
  name: id,
  sortKey: id,
  createdAt: 0,
  updatedAt: 0,
);

Note note(String id, {String? folder}) => Note(
  id: id,
  ownerId: kLocalOwnerId,
  folderId: folder,
  title: id,
  sortKey: id,
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  group('LibraryDragHandle', () {
    LibraryDragPayload sample() => LibraryDragPayload(
      items: [noteKey('n1')],
      parents: {noteKey('n1'): null},
      source: LibraryDragSource.content,
    );

    test('builds the payload on first access only, once', () {
      var builds = 0;
      final handle = LibraryDragHandle(() {
        builds++;
        return sample();
      });
      expect(builds, 0);
      final first = handle.payload;
      expect(builds, 1);
      expect(identical(handle.payload, first), isTrue);
      expect(handle.payload, sample());
      expect(builds, 1);
    });

    test('dropped is set by markDropped', () {
      final handle = LibraryDragHandle(sample);
      expect(handle.dropped, isFalse);
      handle.markDropped();
      expect(handle.dropped, isTrue);
    });
  });

  test('payload kinds', () {
    final notes = LibraryDragPayload(
      items: [noteKey('n1'), noteKey('n2')],
      parents: const {},
      source: LibraryDragSource.content,
    );
    expect(notes.hasNotes, isTrue);
    expect(notes.hasFolders, isFalse);
    expect(notes.isSingleKind, isTrue);
    expect(notes.folderIds, isEmpty);
    final mixed = LibraryDragPayload(
      items: [folderKey('a'), noteKey('n1'), folderKey('b')],
      parents: const {},
      source: LibraryDragSource.content,
    );
    expect(mixed.isSingleKind, isFalse);
    expect(mixed.folderIds, ['a', 'b']);
  });

  group('contentDragPayload', () {
    // Folder 'x' shows folders a, b and notes n1..n3 (display order).
    final content = LibraryContent(
      section: const FolderSection('x'),
      folders: [
        folder('a', parent: 'x'),
        folder('b', parent: 'x'),
      ],
      notes: [
        note('n1', folder: 'x'),
        note('n2', folder: 'x'),
        note('n3', folder: 'x'),
      ],
    );

    LibraryDragPayload build(
      LibraryItemKey pressed,
      LibrarySelection selection, {
      LibraryContent? over,
      FolderId? pressedParent = 'x',
    }) => contentDragPayload(
      pressed: pressed,
      pressedParent: pressedParent,
      selection: selection,
      content: over ?? content,
    );

    test('outside selection mode: the pressed item alone', () {
      final p = build(noteKey('n2'), LibrarySelection.none);
      expect(p.items, [noteKey('n2')]);
      expect(p.parents, {noteKey('n2'): 'x'});
      expect(p.source, LibraryDragSource.content);
    });

    test('selection mode: the selection plus the pressed item, display '
        'order', () {
      final selection = LibrarySelection.activeWith([
        noteKey('n3'),
        folderKey('b'),
      ]);
      // Pressed not selected yet (onDragStarted has not run).
      final p = build(noteKey('n1'), selection);
      expect(p.items, [folderKey('b'), noteKey('n1'), noteKey('n3')]);
      expect(p.parents, {
        folderKey('b'): 'x',
        noteKey('n1'): 'x',
        noteKey('n3'): 'x',
      });
      // Pressed already selected (after onDragStarted): the same payload.
      final after = build(
        noteKey('n1'),
        LibrarySelection.activeWith([...selection.keys, noteKey('n1')]),
      );
      expect(after, p);
    });

    test('selection mode with an empty selection: the pressed item', () {
      final p = build(folderKey('a'), LibrarySelection.activeWith(const []));
      expect(p.items, [folderKey('a')]);
    });

    test('selected items no longer shown are left out; the pressed item '
        'always stays', () {
      final selection = LibrarySelection.activeWith([
        noteKey('gone'),
        noteKey('n2'),
      ]);
      final p = build(noteKey('n9'), selection, pressedParent: null);
      expect(p.items, [noteKey('n2'), noteKey('n9')]);
      expect(p.parents, {noteKey('n2'): 'x', noteKey('n9'): null});
      // Without any content.
      final alone = contentDragPayload(
        pressed: noteKey('n9'),
        pressedParent: null,
        selection: selection,
        content: null,
      );
      expect(alone.items, [noteKey('n9')]);
    });

    test('parents of mixed sections come from each item', () {
      final recent = LibraryContent(
        section: const RecentSection(),
        notes: [
          note('n1', folder: 'p'),
          note('n2'),
        ],
      );
      final p = build(
        noteKey('n2'),
        LibrarySelection.activeWith([noteKey('n1')]),
        over: recent,
        pressedParent: null,
      );
      expect(p.items, [noteKey('n1'), noteKey('n2')]);
      expect(p.parents, {noteKey('n1'): 'p', noteKey('n2'): null});
    });
  });
}
