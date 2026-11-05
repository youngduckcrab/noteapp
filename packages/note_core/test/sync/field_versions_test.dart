import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

const _n = '3f2a9c0d11e0b7a4';

void main() {
  const b = Hlc(1000, 0, _n);
  const h1 = Hlc(2000, 0, _n);
  const h2 = Hlc(2000, 1, _n);

  test('of / max', () {
    const v = EntityFieldVersions(b, {'title': h1, 'folderId': h2});
    expect(v.of('title'), h1);
    expect(v.of('sortKey'), b);
    expect(v.max, h2);
    expect(const EntityFieldVersions(b).max, b);
  });

  test('JSON: "o" omitted when empty, keys sorted', () {
    expect(const EntityFieldVersions(b).toJson(), {'b': b.toString()});
    final json = const EntityFieldVersions(b, {'z': h1, 'a': h2}).toJson();
    expect(json['b'], b.toString());
    expect((json['o']! as Map).keys, ['a', 'z']);
  });

  test('fromJson normalizes overrides that are not newer than base', () {
    final v = EntityFieldVersions.fromJson({
      'b': h1.toString(),
      'o': {'old': b.toString(), 'same': h1.toString(), 'new': h2.toString()},
    });
    expect(v.overrides, {'new': h2});
    expect(v, EntityFieldVersions(h1, const {'new': h2}));
    expect(EntityFieldVersions.fromJson(v.toJson()), v);
  });

  test('toJson drops stale overrides too; equality ignores them', () {
    const raw = EntityFieldVersions(h1, {'old': b});
    expect(raw.toJson(), {'b': h1.toString()});
    expect(raw, const EntityFieldVersions(h1));
    expect(raw.hashCode, const EntityFieldVersions(h1).hashCode);
  });

  test('fromJson errors', () {
    expect(() => EntityFieldVersions.fromJson({}), throwsFormatException);
    expect(
      () => EntityFieldVersions.fromJson({'b': 'x'}),
      throwsFormatException,
    );
    expect(
      () => EntityFieldVersions.fromJson({
        'b': b.toString(),
        'o': {'t': 'bad'},
      }),
      throwsFormatException,
    );
  });

  test('VersionedEntity holds entity + versions', () {
    const folder = Folder(
      id: 'f',
      ownerId: 'local',
      name: 'n',
      sortKey: 'a0',
      createdAt: 1,
      updatedAt: 1,
      version: h2,
    );
    const ve = VersionedEntity(folder, EntityFieldVersions(b, {'name': h2}));
    expect(ve.entity.version, ve.versions.max);
  });
}
