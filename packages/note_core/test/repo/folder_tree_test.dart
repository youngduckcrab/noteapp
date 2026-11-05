import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

Folder _f(String id, String? parent, {String key = 'a0'}) => Folder(
  id: id,
  ownerId: 'local',
  parentId: parent,
  name: id,
  sortKey: key,
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  final tree = FolderTree([
    _f('a', null, key: 'a1'),
    _f('b', null, key: 'a0'),
    _f('a1', 'a', key: 'a1'),
    _f('a0', 'a', key: 'a0'),
    _f('a00', 'a0'),
    _f('orphan', 'gone'),
  ]);

  test('roots include orphans, ordered by (sortKey, id)', () {
    expect(tree.roots.map((f) => f.id), ['b', 'orphan', 'a']);
    expect(tree.childrenOf(null).map((f) => f.id), ['b', 'orphan', 'a']);
    expect(tree.childrenOf('a').map((f) => f.id), ['a0', 'a1']);
    expect(tree.childrenOf('missing'), isEmpty);
    expect(tree.length, 6);
    expect(tree.byId('a00')?.parentId, 'a0');
  });

  test('pathTo: top level → id', () {
    expect(tree.pathTo('a00').map((f) => f.id), ['a', 'a0', 'a00']);
    expect(tree.pathTo('orphan').map((f) => f.id), ['orphan']);
    expect(tree.pathTo('missing'), isEmpty);
  });

  test('descendantsOf and isSelfOrDescendant', () {
    expect(tree.descendantsOf('a'), {'a0', 'a1', 'a00'});
    expect(tree.descendantsOf('a00'), isEmpty);
    expect(tree.isSelfOrDescendant('a00', of: 'a'), isTrue);
    expect(tree.isSelfOrDescendant('a', of: 'a'), isTrue);
    expect(tree.isSelfOrDescendant('b', of: 'a'), isFalse);
  });

  test(
    'sync cycles: folders keeps them, findCycles reports them, pathTo is safe',
    () {
      final cyclic = FolderTree([
        _f('root', null),
        _f('x', 'y'),
        _f('y', 'z'),
        _f('z', 'x'),
        _f('self', 'self'),
        _f('tail', 'x'),
      ]);
      expect(cyclic.folders.map((f) => f.id).toSet(), {
        'root',
        'x',
        'y',
        'z',
        'self',
        'tail',
      });
      expect(cyclic.roots.map((f) => f.id), ['root']);
      final cycles = cyclic.findCycles();
      expect(
        cycles,
        unorderedEquals([
          ['self'],
          ['x', 'y', 'z'],
        ]),
      );
      expect(cyclic.pathTo('tail').map((f) => f.id), ['z', 'y', 'x', 'tail']);
      expect(cyclic.descendantsOf('x'), {'z', 'y', 'tail'});
      expect(tree.findCycles(), isEmpty);
    },
  );

  test('value equality', () {
    expect(FolderTree([_f('a', null)]), FolderTree([_f('a', null)]));
    expect(FolderTree([_f('a', null)]) == FolderTree([_f('b', null)]), isFalse);
  });
}
