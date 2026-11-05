// flattenFolderTree / compareFolderNames / folderTreeOrderFor (05-library 6.5,
// 8 L5). Trees are built directly from CORE Folder values (no store), so a
// sync cycle (parent links pointing at each other) can be made by hand.
import 'package:feature_library/src/model/tree_rows.dart';
import 'package:feature_library/src/model/view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

Folder folder(
  String id,
  String name, {
  String? parent,
  String? sortKey,
  int? color,
  String? icon,
}) => Folder(
  id: id,
  ownerId: kLocalOwnerId,
  parentId: parent,
  name: name,
  colorArgb: color,
  icon: icon,
  sortKey: sortKey ?? id,
  createdAt: 0,
  updatedAt: 0,
);

/// 'id@depth' for every row, plus '+' (expanded) / '-' (collapsed) when the
/// row has children.
List<String> describe(List<FolderTreeRow> rows) => [
  for (final r in rows) '${r.folder.id}@${r.depth}${_flag(r)}',
];

String _flag(FolderTreeRow r) =>
    r.hasChildren ? (r.isExpanded ? '+' : '-') : '';

void main() {
  // Home: b 'Beta' (sortKey 1), a 'alpha' (sortKey 2), c 'Gamma' (sortKey 0).
  // a has a1 'Zed' (0) and a2 'Ant' (1); a1 has a1x 'X'.
  final tree = FolderTree([
    folder('b', 'Beta', sortKey: '1'),
    folder('a', 'alpha', sortKey: '2'),
    folder('c', 'Gamma', sortKey: '0'),
    folder('a1', 'Zed', parent: 'a', sortKey: '0'),
    folder('a2', 'Ant', parent: 'a', sortKey: '1'),
    folder('a1x', 'X', parent: 'a1'),
  ]);

  group('compareFolderNames', () {
    test('trim, collapse whitespace, lower case, then id', () {
      expect(compareFolderNames(folder('1', 'b'), folder('2', 'A')), 1);
      expect(compareFolderNames(folder('1', 'a'), folder('2', 'B')), -1);
      // ' Math  1 ' == 'math 1' by name → id decides.
      expect(
        compareFolderNames(folder('2', ' Math  1 '), folder('1', 'math 1')),
        1,
      );
      expect(
        compareFolderNames(folder('1', 'Math\t1'), folder('2', 'math 1')),
        -1,
      );
      expect(compareFolderNames(folder('x', '수학'), folder('x', '수학')), 0);
    });

    test('Korean names sort by code point', () {
      final list = [folder('1', '영어'), folder('2', '국어'), folder('3', '수학')]
        ..sort(compareFolderNames);
      expect([for (final f in list) f.name], ['국어', '수학', '영어']);
    });
  });

  group('folderTreeOrderFor', () {
    test('custom only for the custom sort field', () {
      expect(
        folderTreeOrderFor(
          const LibrarySort(LibrarySortField.custom, descending: false),
        ),
        FolderTreeOrder.custom,
      );
      for (final field in [
        LibrarySortField.name,
        LibrarySortField.createdAt,
        LibrarySortField.updatedAt,
      ]) {
        expect(
          folderTreeOrderFor(LibrarySort(field, descending: true)),
          FolderTreeOrder.name,
        );
      }
    });
  });

  group('expand / collapse', () {
    test('everything collapsed → top level only, name order', () {
      final rows = flattenFolderTree(
        tree,
        expanded: const {},
        order: FolderTreeOrder.name,
      );
      expect(describe(rows), ['a@0-', 'b@0', 'c@0']);
    });

    test('expanded folders show their children (pre-order)', () {
      final rows = flattenFolderTree(
        tree,
        expanded: const {'a', 'a1'},
        order: FolderTreeOrder.name,
      );
      expect(describe(rows), [
        'a@0+',
        'a2@1', // 'Ant' before 'Zed'
        'a1@1+',
        'a1x@2',
        'b@0',
        'c@0',
      ]);
    });

    test('a collapsed parent hides an expanded child', () {
      final rows = flattenFolderTree(
        tree,
        expanded: const {'a1'},
        order: FolderTreeOrder.name,
      );
      expect(describe(rows), ['a@0-', 'b@0', 'c@0']);
    });

    test('expanded ids of leaves or unknown folders are harmless', () {
      final rows = flattenFolderTree(
        tree,
        expanded: const {'b', 'nope'},
        order: FolderTreeOrder.name,
      );
      // b has no children: hasChildren false, isExpanded still reported.
      expect(describe(rows), ['a@0-', 'b@0', 'c@0']);
      expect(rows[1].isExpanded, isTrue);
      expect(rows[1].hasChildren, isFalse);
    });
  });

  group('order', () {
    test('custom keeps the CORE (sortKey, id) order at every level', () {
      final rows = flattenFolderTree(
        tree,
        expanded: const {'a'},
        order: FolderTreeOrder.custom,
      );
      expect(describe(rows), ['c@0', 'b@0', 'a@0+', 'a1@1-', 'a2@1']);
    });

    test('name order ignores case and surrounding spaces', () {
      final t = FolderTree([
        folder('1', '  banana', sortKey: '0'),
        folder('2', 'Apple', sortKey: '1'),
        folder('3', 'cherry', sortKey: '2'),
      ]);
      final rows = flattenFolderTree(
        t,
        expanded: const {},
        order: FolderTreeOrder.name,
      );
      expect(describe(rows), ['2@0', '1@0', '3@0']);
    });
  });

  test('row value equality: id, name, color, icon, depth, flags', () {
    const row = FolderTreeRow(
      folder: Folder(
        id: 'a',
        ownerId: kLocalOwnerId,
        name: 'A',
        sortKey: 'k',
        createdAt: 0,
        updatedAt: 0,
      ),
      depth: 1,
      hasChildren: true,
      isExpanded: false,
    );
    FolderTreeRow withFolder(Folder f) => FolderTreeRow(
      folder: f,
      depth: 1,
      hasChildren: true,
      isExpanded: false,
    );
    // sortKey / updatedAt do not matter for a row.
    expect(withFolder(row.folder.copyWith(sortKey: 'z', updatedAt: 5)), row);
    expect(
      withFolder(row.folder.copyWith(sortKey: 'z')).hashCode,
      row.hashCode,
    );
    expect(withFolder(row.folder.copyWith(name: 'B')), isNot(row));
    expect(withFolder(row.folder.copyWith(colorArgb: 0xFF112233)), isNot(row));
    expect(withFolder(row.folder.copyWith(icon: 'book')), isNot(row));
    expect(
      FolderTreeRow(
        folder: row.folder,
        depth: 2,
        hasChildren: true,
        isExpanded: false,
      ),
      isNot(row),
    );
    expect(
      FolderTreeRow(
        folder: row.folder,
        depth: 1,
        hasChildren: true,
        isExpanded: true,
      ),
      isNot(row),
    );
  });

  test('depth 50 chain, all expanded (iterative, no recursion limit)', () {
    final chain = [
      for (var i = 0; i < 50; i++)
        folder('f$i', 'Level $i', parent: i == 0 ? null : 'f${i - 1}'),
    ];
    final rows = flattenFolderTree(
      FolderTree(chain),
      expanded: {for (final f in chain) f.id},
      order: FolderTreeOrder.name,
    );
    expect(rows, hasLength(50));
    for (var i = 0; i < 50; i++) {
      expect(rows[i].folder.id, 'f$i');
      expect(rows[i].depth, i);
      expect(rows[i].hasChildren, i < 49);
    }
  });

  test('2,000 folders, everything expanded', () {
    // 20 top-level folders × 9 children × 10 grandchildren = 20 + 180 + 1,800.
    final folders = <Folder>[];
    for (var i = 0; i < 20; i++) {
      final top = 't${i.toString().padLeft(2, '0')}';
      folders.add(folder(top, 'Top $top'));
      for (var j = 0; j < 9; j++) {
        final mid = '$top-$j';
        folders.add(folder(mid, 'Mid $mid', parent: top));
        for (var k = 0; k < 10; k++) {
          folders.add(folder('$mid-$k', 'Leaf $mid-$k', parent: mid));
        }
      }
    }
    expect(folders, hasLength(2000));
    final t = FolderTree(folders);
    final all = {for (final f in folders) f.id};

    final rows = flattenFolderTree(
      t,
      expanded: all,
      order: FolderTreeOrder.name,
    );
    expect(rows, hasLength(2000));
    expect({for (final r in rows) r.folder.id}, all);
    // Pre-order: every row's parent is the nearest earlier row one level up.
    final parentAt = <int, String>{};
    for (final r in rows) {
      if (r.depth > 0) expect(r.folder.parentId, parentAt[r.depth - 1]);
      parentAt[r.depth] = r.folder.id;
    }
    expect(rows.first.folder.id, 't00');
    expect(rows[1].folder.id, 't00-0');
    expect(rows[2].folder.id, 't00-0-0');

    final custom = flattenFolderTree(
      t,
      expanded: all,
      order: FolderTreeOrder.custom,
    );
    expect(custom, hasLength(2000));

    final collapsed = flattenFolderTree(
      t,
      expanded: const {},
      order: FolderTreeOrder.name,
    );
    expect(collapsed, hasLength(20));
  });

  test('orphan folders (parent missing) are shown at the top level', () {
    final t = FolderTree([
      folder('a', 'A'),
      folder('o', 'Orphan', parent: 'gone'),
      folder('oc', 'Orphan child', parent: 'o'),
    ]);
    final rows = flattenFolderTree(
      t,
      expanded: const {'o'},
      order: FolderTreeOrder.name,
    );
    expect(describe(rows), ['a@0', 'o@0+', 'oc@1']);
  });

  group('folders caught in a sync cycle (tree.folders)', () {
    // x ↔ y point at each other; z sits below y; no root reaches them.
    final cyc = FolderTree([
      folder('h', 'Home folder'),
      folder('x', 'Xylo', parent: 'y'),
      folder('y', 'Yarn', parent: 'x'),
      folder('z', 'Zinc', parent: 'y'),
    ]);

    test('the precondition: CORE roots do not include them', () {
      expect([for (final f in cyc.roots) f.id], ['h']);
      expect(cyc.length, 4);
      expect(cyc.findCycles(), [
        ['x', 'y'],
      ]);
    });

    test('collapsed → the first by name is shown once at the top level', () {
      final rows = flattenFolderTree(
        cyc,
        expanded: const {},
        order: FolderTreeOrder.name,
      );
      expect(describe(rows), ['h@0', 'x@0-']);
    });

    test('expanded → each folder appears once, the cycle stops', () {
      final rows = flattenFolderTree(
        cyc,
        expanded: const {'x', 'y'},
        order: FolderTreeOrder.name,
      );
      expect(describe(rows), ['h@0', 'x@0+', 'y@1+', 'z@2']);
      expect(rows.map((r) => r.folder.id).toSet(), hasLength(rows.length));
    });

    test('custom order shows them after the rooted rows too', () {
      final rows = flattenFolderTree(
        cyc,
        expanded: const {'x', 'y'},
        order: FolderTreeOrder.custom,
      );
      expect(describe(rows), ['h@0', 'x@0+', 'y@1+', 'z@2']);
    });

    test('a self-parented folder is shown', () {
      final t = FolderTree([folder('s', 'Self', parent: 's')]);
      expect(t.roots, isEmpty);
      final rows = flattenFolderTree(
        t,
        expanded: const {'s'},
        order: FolderTreeOrder.name,
      );
      expect(describe(rows), ['s@0+']);
    });

    test('two separate cycles are both shown, in name order', () {
      final t = FolderTree([
        folder('p', 'Pear', parent: 'q'),
        folder('q', 'Quince', parent: 'p'),
        folder('m', 'Mango', parent: 'n'),
        folder('n', 'Nut', parent: 'm'),
      ]);
      final rows = flattenFolderTree(
        t,
        expanded: const {},
        order: FolderTreeOrder.name,
      );
      expect(describe(rows), ['m@0-', 'p@0-']);
    });
  });

  test('empty tree → no rows', () {
    expect(
      flattenFolderTree(
        FolderTree(const []),
        expanded: const {},
        order: FolderTreeOrder.name,
      ),
      isEmpty,
    );
  });
}
