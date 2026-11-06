// PageObjectFixtures (2nd-round contract 7.6): the contract defaults, valid objects (AddObjects
// accepts them), JSON round trips. Web-safe.
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

void main() {
  test('defaults are the contract values', () {
    final shape = PageObjectFixtures.shape(pageId: 'p');
    expect(shape.shapeKind, ShapeKind.rectangle);
    expect(shape.frame.rect, const PageRect(100, 100, 300, 220));
    expect(shape.createdAt, 1);
    final text = PageObjectFixtures.textBox(pageId: 'p');
    expect(text.text, '안녕 hello');
    expect(text.frame.rect, const PageRect(100, 300, 400, 340));
    final image = PageObjectFixtures.image(pageId: 'p', assetId: 'a' * 64);
    expect([image.pixelWidth, image.pixelHeight], [400, 300]);
    expect(image.frame.rect, const PageRect(100, 400, 300, 550));
    final math = PageObjectFixtures.math(pageId: 'p');
    expect(math.latex, r'\frac{a}{b}');
    expect(math.frame.rect, const PageRect(100, 600, 200, 650));
    final unknown = PageObjectFixtures.unknown(pageId: 'p');
    expect(unknown.type, 'sticker');
    expect(unknown.frame.rect, const PageRect(400, 100, 450, 150));
    for (final o in <PageObject>[shape, text, image, math, unknown]) {
      expect(o.pageId, 'p');
      expect(o.version, isNull);
      expect(o.deletedAt, isNull);
      expect(isValidEntityId(o.id), isTrue);
    }
  });

  test('ids: given or unique; every shape kind has its template', () {
    expect(PageObjectFixtures.textBox(pageId: 'p', id: 'mine').id, 'mine');
    final ids = {
      for (var i = 0; i < 20; i++) PageObjectFixtures.shape(pageId: 'p').id,
    };
    expect(ids, hasLength(20));
    for (final kind in ShapeKind.values) {
      final s = PageObjectFixtures.shape(pageId: 'p', kind: kind);
      expect(s.shapeKind, kind);
      expect(s.bounds.width, greaterThan(0), reason: kind.name);
    }
    expect(
      PageObjectFixtures.shape(
        pageId: 'p',
        kind: ShapeKind.arrow,
      ).style.arrowHeads,
      ArrowHeads.end,
    );
  });

  test('JSON round trips', () {
    final objects = <PageObject>[
      for (final kind in ShapeKind.values)
        PageObjectFixtures.shape(pageId: 'p', kind: kind),
      PageObjectFixtures.textBox(pageId: 'p'),
      PageObjectFixtures.image(pageId: 'p', assetId: 'b' * 64),
      PageObjectFixtures.math(pageId: 'p'),
      PageObjectFixtures.unknown(pageId: 'p', type: 'video'),
    ];
    for (final o in objects) {
      expect(PageObject.fromJson(o.toJson()), o, reason: o.id);
    }
  });

  test('AddObjects accepts them', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: 'fixtures');
    final session = await store.openSession(note.id);
    addTearDown(session.close);
    final pageId = session.pages.single.id;
    await session.openPage(pageId);
    await session
        .execute(
          AddObjects(
            pageId: pageId,
            objects: [
              PageObjectFixtures.shape(pageId: pageId),
              PageObjectFixtures.textBox(pageId: pageId),
              PageObjectFixtures.image(pageId: pageId, assetId: 'c' * 64),
              PageObjectFixtures.math(pageId: pageId),
              PageObjectFixtures.unknown(pageId: pageId),
            ],
          ),
        )
        .persisted;
    expect(session.pageIfLoaded(pageId)!.objectCount, 5);
  });
}
