// locationLabel (05-library 6.14, 8 L5).
import 'package:feature_library/src/model/location_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

Folder f(String id, String name, {String? parent}) => Folder(
  id: id,
  ownerId: kLocalOwnerId,
  parentId: parent,
  name: name,
  sortKey: id,
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  // 수학 › 미적분 › 극한 › 연습 문제 › 심화
  final tree = FolderTree([
    f('m', '수학'),
    f('c', '미적분', parent: 'm'),
    f('l', '극한', parent: 'c'),
    f('p', '연습 문제', parent: 'l'),
    f('d', '심화', parent: 'p'),
    f('o', '고아', parent: 'gone'),
    f('x', 'X', parent: 'y'),
    f('y', 'Y', parent: 'x'),
  ]);

  test('null → 홈', () {
    expect(locationLabel(tree, null), '홈');
  });

  test('1 to 3 folder names → the whole path', () {
    expect(locationLabel(tree, 'm'), '홈 › 수학');
    expect(locationLabel(tree, 'c'), '홈 › 수학 › 미적분');
    expect(locationLabel(tree, 'l'), '홈 › 수학 › 미적분 › 극한');
  });

  test('more than 3 names → 홈 › … › parent › name', () {
    expect(locationLabel(tree, 'p'), '홈 › … › 극한 › 연습 문제');
    expect(locationLabel(tree, 'd'), '홈 › … › 연습 문제 › 심화');
  });

  test('folder missing from the tree → 홈', () {
    expect(locationLabel(tree, 'gone'), '홈');
    expect(locationLabel(FolderTree(const []), 'm'), '홈');
  });

  test('orphan → its own name under 홈', () {
    expect(locationLabel(tree, 'o'), '홈 › 고아');
  });

  test('a folder in a sync cycle does not loop', () {
    // pathTo is cycle-safe: y → x → (y seen) stops.
    expect(locationLabel(tree, 'y'), '홈 › X › Y');
  });
}
