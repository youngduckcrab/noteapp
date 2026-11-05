// decideDrop / canMoveInto (05-library 6.10.2, 8 L15): every branch of the
// decision rules, with the boundaries t = 0.25 / 0.5 / 0.75. Trees are built
// directly from CORE Folder values (no store).
import 'package:feature_library/src/dnd/drag_payload.dart';
import 'package:feature_library/src/dnd/drop_decision.dart';
import 'package:feature_library/src/model/item_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Axis, Offset, Size;
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

/// a ⊃ b ⊃ c, d (top level).
final FolderTree tree = FolderTree([
  folder('a'),
  folder('b', parent: 'a'),
  folder('c', parent: 'b'),
  folder('d'),
]);

LibraryDragPayload payload(
  Map<LibraryItemKey, FolderId?> parents, {
  LibraryDragSource source = LibraryDragSource.content,
}) => LibraryDragPayload(
  items: parents.keys.toList(),
  parents: parents,
  source: source,
);

void main() {
  final n1 = noteKey('n1');
  final n2 = noteKey('n2');
  final fa = folderKey('a');
  final fb = folderKey('b');
  final fd = folderKey('d');

  group('canMoveInto', () {
    test('a note into another folder', () {
      expect(canMoveInto(payload({n1: null}), 'a', tree), isTrue);
      expect(canMoveInto(payload({n1: 'a'}), null, tree), isTrue);
    });

    test('false when every item is already in the target', () {
      expect(canMoveInto(payload({n1: 'a', n2: 'a'}), 'a', tree), isFalse);
      expect(canMoveInto(payload({n1: null}), null, tree), isFalse);
      // One item elsewhere is enough.
      expect(canMoveInto(payload({n1: 'a', n2: null}), 'a', tree), isTrue);
    });

    test('false into a dragged folder itself or its sub-folders', () {
      expect(canMoveInto(payload({fa: null}), 'a', tree), isFalse);
      expect(canMoveInto(payload({fa: null}), 'b', tree), isFalse);
      expect(canMoveInto(payload({fa: null}), 'c', tree), isFalse);
      expect(canMoveInto(payload({fa: null}), 'd', tree), isTrue);
      expect(canMoveInto(payload({fb: 'a'}), 'c', tree), isFalse);
      expect(canMoveInto(payload({fb: 'a'}), 'd', tree), isTrue);
      expect(canMoveInto(payload({fb: 'a'}), null, tree), isTrue);
      // Mixed with notes: the folder still forbids its subtree.
      expect(canMoveInto(payload({n1: null, fb: 'a'}), 'c', tree), isFalse);
    });
  });

  group('FolderDropTarget', () {
    DropDecision? decide(LibraryDragPayload p, FolderId? f) => decideDrop(
      payload: p,
      target: FolderDropTarget(f),
      tree: tree,
      customSort: false,
    );

    test('DropInto when canMoveInto, else null', () {
      expect(decide(payload({n1: null}), 'a'), const DropInto('a'));
      expect(decide(payload({n1: 'a'}), null), const DropInto(null));
      expect(decide(payload({n1: 'a'}), 'a'), isNull);
      expect(decide(payload({fa: null}), 'c'), isNull);
      expect(
        decide(payload({fb: 'a'}, source: LibraryDragSource.sidebar), 'd'),
        const DropInto('d'),
      );
    });

    test('needs no position', () {
      expect(
        decideDrop(
          payload: payload({n1: null}),
          target: const FolderDropTarget('d'),
          tree: tree,
          customSort: true,
          localPosition: const Offset(1, 1),
          targetSize: const Size(10, 10),
        ),
        const DropInto('d'),
      );
    });
  });

  test('TrashDropTarget is always DropTrash', () {
    for (final p in [
      payload({n1: null}),
      payload({fa: null, n2: 'a'}),
      payload({fb: 'a'}, source: LibraryDragSource.sidebar),
    ]) {
      expect(
        decideDrop(
          payload: p,
          target: const TrashDropTarget(),
          tree: tree,
          customSort: false,
        ),
        const DropTrash(),
      );
    }
  });

  group('TileDropTarget', () {
    const size = Size(200, 300);

    /// Grid tile at t = x / width (y in the middle).
    DropDecision? onGrid(
      LibraryDragPayload p,
      LibraryItemKey key,
      double t, {
      bool customSort = true,
    }) => decideDrop(
      payload: p,
      target: TileDropTarget(key: key, axis: Axis.horizontal),
      tree: tree,
      customSort: customSort,
      localPosition: Offset(t * size.width, 150),
      targetSize: size,
    );

    test('an item of the drag itself → null', () {
      expect(onGrid(payload({fa: null, n1: null}), fa, 0.5), isNull);
      expect(onGrid(payload({n1: null}), n1, 0.1), isNull);
    });

    test('without a position or with an empty size → null', () {
      final target = TileDropTarget(key: fd, axis: Axis.horizontal);
      expect(
        decideDrop(
          payload: payload({n1: null}),
          target: target,
          tree: tree,
          customSort: false,
        ),
        isNull,
      );
      expect(
        decideDrop(
          payload: payload({n1: null}),
          target: target,
          tree: tree,
          customSort: false,
          localPosition: Offset.zero,
          targetSize: Size.zero,
        ),
        isNull,
      );
    });

    group('folder tile', () {
      test('outside the custom order: into everywhere', () {
        for (final t in [0.0, 0.1, 0.5, 0.9, 1.0]) {
          expect(
            onGrid(payload({n1: null}), fd, t, customSort: false),
            const DropInto('d'),
          );
          expect(
            onGrid(payload({fa: null}), fd, t, customSort: false),
            const DropInto('d'),
          );
        }
      });

      test('into is refused like canMoveInto', () {
        // Already in d.
        expect(onGrid(payload({n1: 'd'}), fd, 0.5), isNull);
        // b is inside the dragged a (a cycle).
        expect(onGrid(payload({fa: null}), fb, 0.5, customSort: false), isNull);
      });

      test(
        'custom order, folders from the content: outer quarters reorder',
        () {
          final p = payload({fa: null});
          expect(onGrid(p, fd, 0), DropReorder(anchor: fd, after: false));
          expect(onGrid(p, fd, 0.1), DropReorder(anchor: fd, after: false));
          expect(onGrid(p, fd, 0.2499), DropReorder(anchor: fd, after: false));
          expect(onGrid(p, fd, 0.25), const DropInto('d'));
          expect(onGrid(p, fd, 0.5), const DropInto('d'));
          expect(onGrid(p, fd, 0.75), const DropInto('d'));
          expect(onGrid(p, fd, 0.7501), DropReorder(anchor: fd, after: true));
          expect(onGrid(p, fd, 0.9), DropReorder(anchor: fd, after: true));
          expect(onGrid(p, fd, 1), DropReorder(anchor: fd, after: true));
          // A reorder does not check canMoveInto.
          expect(
            onGrid(payload({fd: null}), fa, 0.1),
            DropReorder(anchor: fa, after: false),
          );
        },
      );

      test('custom order without reorderable payload: into everywhere', () {
        // Notes onto a folder, mixed kinds, a sidebar drag.
        for (final p in [
          payload({n1: null}),
          payload({fa: null, n1: null}),
          payload({fa: null}, source: LibraryDragSource.sidebar),
        ]) {
          expect(onGrid(p, fd, 0.1), const DropInto('d'), reason: '$p');
          expect(onGrid(p, fd, 0.9), const DropInto('d'), reason: '$p');
        }
      });
    });

    group('note tile', () {
      test('outside the custom order → null', () {
        expect(onGrid(payload({n1: null}), n2, 0.1, customSort: false), isNull);
        expect(onGrid(payload({n1: null}), n2, 0.9, customSort: false), isNull);
      });

      test('custom order, notes from the content: halves', () {
        final p = payload({n1: null});
        expect(onGrid(p, n2, 0), DropReorder(anchor: n2, after: false));
        expect(onGrid(p, n2, 0.25), DropReorder(anchor: n2, after: false));
        expect(onGrid(p, n2, 0.4999), DropReorder(anchor: n2, after: false));
        expect(onGrid(p, n2, 0.5), DropReorder(anchor: n2, after: true));
        expect(onGrid(p, n2, 0.75), DropReorder(anchor: n2, after: true));
        expect(onGrid(p, n2, 1), DropReorder(anchor: n2, after: true));
      });

      test('custom order, other payloads → null', () {
        expect(onGrid(payload({fa: null}), n2, 0.1), isNull);
        expect(onGrid(payload({fa: null, n1: null}), n2, 0.9), isNull);
        expect(
          onGrid(
            payload({n1: null}, source: LibraryDragSource.sidebar),
            n2,
            0.1,
          ),
          isNull,
        );
      });
    });

    test('a list row (vertical) uses y / height', () {
      DropDecision? onRow(LibraryItemKey key, double y) => decideDrop(
        payload: payload({n1: null}),
        target: TileDropTarget(key: key, axis: Axis.vertical),
        tree: tree,
        customSort: true,
        // x far right: only y counts.
        localPosition: Offset(900, y),
        targetSize: const Size(1000, 64),
      );
      expect(onRow(n2, 10), DropReorder(anchor: n2, after: false));
      expect(onRow(n2, 32), DropReorder(anchor: n2, after: true));
      expect(onRow(n2, 60), DropReorder(anchor: n2, after: true));
      expect(onRow(fd, 8), const DropInto('d'));
      expect(onRow(fd, 32), const DropInto('d'));
    });
  });

  test('targets and decisions are values', () {
    expect(const FolderDropTarget('a'), const FolderDropTarget('a'));
    expect(const FolderDropTarget(null), isNot(const FolderDropTarget('a')));
    expect(
      TileDropTarget(key: n1, axis: Axis.vertical),
      TileDropTarget(key: n1, axis: Axis.vertical),
    );
    expect(
      DropReorder(anchor: n1, after: true),
      isNot(DropReorder(anchor: n1, after: false)),
    );
    expect(const DropInto(null), isNot(const DropInto('a')));
    expect(const DropTrash(), const DropTrash());
  });
}
