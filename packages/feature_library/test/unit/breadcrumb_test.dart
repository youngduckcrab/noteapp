// compressBreadcrumb / breadcrumbPath (05-library 6.6, 8 L5).
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/breadcrumb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

const home = BreadcrumbItem(folderId: null, label: LibraryStrings.home);

BreadcrumbItem item(String id) => BreadcrumbItem(folderId: id, label: id);

/// '홈 › … › D › E*' — '*' marks the current crumb, '…' the overflow.
String render(List<BreadcrumbSlot> slots) => [
  for (final s in slots)
    switch (s) {
      BreadcrumbCrumb(:final item, :final isCurrent) =>
        '${item.label}${isCurrent ? '*' : ''}',
      BreadcrumbOverflow() => '…',
    },
].join(' › ');

List<BreadcrumbItem> hiddenOf(List<BreadcrumbSlot> slots) =>
    slots.whereType<BreadcrumbOverflow>().single.hidden;

void main() {
  // 홈 › A › B › C › D › E (6 crumbs).
  final six = [
    home,
    for (final id in ['A', 'B', 'C', 'D', 'E']) item(id),
  ];

  group('6.6 examples', () {
    test('4 crumbs (expanded): 홈 › … › D › E, … = A, B, C', () {
      final slots = compressBreadcrumb(six, maxVisible: 4);
      expect(render(slots), '홈 › … › D › E*');
      expect(hiddenOf(slots), [item('A'), item('B'), item('C')]);
    });

    test('3 crumbs (medium): 홈 › … › E, … = A, B, C, D', () {
      final slots = compressBreadcrumb(six, maxVisible: 3);
      expect(render(slots), '홈 › … › E*');
      expect(hiddenOf(slots), [item('A'), item('B'), item('C'), item('D')]);
    });

    test('2 crumbs (compact): … › E, … = 홈, A, B, C, D', () {
      final slots = compressBreadcrumb(six, maxVisible: 2);
      expect(render(slots), '… › E*');
      expect(hiddenOf(slots), [
        home,
        item('A'),
        item('B'),
        item('C'),
        item('D'),
      ]);
    });
  });

  test('a path that fits is shown whole, only the last is current', () {
    final path = [home, item('A'), item('B')];
    final slots = compressBreadcrumb(path, maxVisible: 4);
    expect(slots, [
      const BreadcrumbCrumb(home, isCurrent: false),
      BreadcrumbCrumb(item('A'), isCurrent: false),
      BreadcrumbCrumb(item('B'), isCurrent: true),
    ]);
    expect(compressBreadcrumb(path, maxVisible: 3), slots);
    expect(render(compressBreadcrumb(path, maxVisible: 2)), '… › B*');
  });

  test('home alone is the current crumb', () {
    for (final max in [2, 3, 4]) {
      expect(compressBreadcrumb([home], maxVisible: max), [
        const BreadcrumbCrumb(home, isCurrent: true),
      ]);
    }
  });

  test('length <= maxVisible, nothing lost, order kept', () {
    for (var n = 1; n <= 12; n++) {
      final path = [home, for (var i = 1; i < n; i++) item('F$i')];
      for (final max in [2, 3, 4, 5]) {
        final slots = compressBreadcrumb(path, maxVisible: max);
        expect(slots.length, lessThanOrEqualTo(max), reason: 'n=$n max=$max');
        // Expanding the overflow gives back the whole path in order.
        final flat = [
          for (final s in slots)
            ...switch (s) {
              BreadcrumbCrumb(:final item) => [item],
              BreadcrumbOverflow(:final hidden) => hidden,
            },
        ];
        expect(flat, path, reason: 'n=$n max=$max');
        // The last slot is always the current crumb.
        expect(
          slots.last,
          BreadcrumbCrumb(path.last, isCurrent: true),
          reason: 'n=$n max=$max',
        );
        expect(
          slots.whereType<BreadcrumbCrumb>().where((c) => c.isCurrent),
          hasLength(1),
        );
        if (n > max) {
          expect(slots, hasLength(max));
          expect(slots.whereType<BreadcrumbOverflow>(), hasLength(1));
        } else {
          expect(slots.whereType<BreadcrumbOverflow>(), isEmpty);
        }
      }
    }
  });

  test('slot value equality', () {
    expect(item('A'), const BreadcrumbItem(folderId: 'A', label: 'A'));
    expect(item('A'), isNot(const BreadcrumbItem(folderId: 'A', label: 'B')));
    expect(
      BreadcrumbOverflow([item('A'), item('B')]),
      BreadcrumbOverflow([item('A'), item('B')]),
    );
    expect(
      BreadcrumbOverflow([item('A'), item('B')]).hashCode,
      BreadcrumbOverflow([item('A'), item('B')]).hashCode,
    );
    expect(
      BreadcrumbOverflow([item('A')]),
      isNot(BreadcrumbOverflow([item('B')])),
    );
    expect(
      BreadcrumbCrumb(item('A'), isCurrent: true),
      isNot(BreadcrumbCrumb(item('A'), isCurrent: false)),
    );
  });

  group('breadcrumbPath', () {
    Folder f(String id, String name, {String? parent}) => Folder(
      id: id,
      ownerId: kLocalOwnerId,
      parentId: parent,
      name: name,
      sortKey: id,
      createdAt: 0,
      updatedAt: 0,
    );
    final tree = FolderTree([
      f('m', '수학'),
      f('c', '미적분', parent: 'm'),
      f('l', '극한', parent: 'c'),
    ]);

    test('home → [홈]', () {
      expect(breadcrumbPath(tree, null), [home]);
    });

    test('nested folder → 홈 then top level → folder', () {
      expect(breadcrumbPath(tree, 'l'), [
        home,
        const BreadcrumbItem(folderId: 'm', label: '수학'),
        const BreadcrumbItem(folderId: 'c', label: '미적분'),
        const BreadcrumbItem(folderId: 'l', label: '극한'),
      ]);
    });

    test('folder missing from the tree → [홈]', () {
      expect(breadcrumbPath(tree, 'gone'), [home]);
    });
  });
}
