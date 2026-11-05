// LibrarySort (05-library 6.3.3 / 6.7, 8 L3).
import 'package:feature_library/src/model/view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

const _name = LibrarySortField.name;
const _created = LibrarySortField.createdAt;
const _updated = LibrarySortField.updatedAt;
const _custom = LibrarySortField.custom;

void main() {
  test('defaults: updatedAt descending', () {
    expect(LibrarySort.defaults.field, _updated);
    expect(LibrarySort.defaults.descending, isTrue);
  });

  group('select', () {
    final cases = <(String, LibrarySort, LibrarySortField, LibrarySort)>[
      (
        'same field toggles (updatedAt desc → asc)',
        LibrarySort.defaults,
        _updated,
        const LibrarySort(_updated, descending: false),
      ),
      (
        'same field toggles back (name asc → desc)',
        const LibrarySort(_name, descending: false),
        _name,
        const LibrarySort(_name, descending: true),
      ),
      (
        'other field: name starts ascending',
        LibrarySort.defaults,
        _name,
        const LibrarySort(_name, descending: false),
      ),
      (
        'other field: createdAt starts descending',
        const LibrarySort(_name, descending: false),
        _created,
        const LibrarySort(_created, descending: true),
      ),
      (
        'other field: updatedAt starts descending',
        const LibrarySort(_created, descending: false),
        _updated,
        LibrarySort.defaults,
      ),
      (
        'custom is ascending',
        LibrarySort.defaults,
        _custom,
        const LibrarySort(_custom, descending: false),
      ),
      (
        'custom stays ascending when selected again',
        const LibrarySort(_custom, descending: false),
        _custom,
        const LibrarySort(_custom, descending: false),
      ),
      (
        'leaving custom: name ascending',
        const LibrarySort(_custom, descending: false),
        _name,
        const LibrarySort(_name, descending: false),
      ),
    ];
    for (final (name, from, field, expected) in cases) {
      test(name, () => expect(from.select(field), expected));
    }
  });

  test('queryFor passes field, direction and folder to LibraryQuery', () {
    expect(
      const LibrarySort(_name, descending: false).queryFor('f1'),
      const LibraryQuery(folderId: 'f1', sort: _name, descending: false),
    );
    expect(LibrarySort.defaults.queryFor(null), const LibraryQuery());
  });

  test('value equality', () {
    expect(
      const LibrarySort(_name, descending: true),
      isNot(const LibrarySort(_name, descending: false)),
    );
    expect(
      const LibrarySort(_name, descending: true).hashCode,
      const LibrarySort(_name, descending: true).hashCode,
    );
  });
}
