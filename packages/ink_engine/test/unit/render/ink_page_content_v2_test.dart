// T24 (m5-7/03-ink 8.1 content_diff v2, 4.2): InkPageContent.fromCore(objects:) —
// deleted objects dropped, compareOrder (sorted input kept), another page →
// ArgumentError, == by identity, the L-1 layer assignment.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/render/ink_page_content.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

void main() {
  final page = SyntheticInk.page();
  final shape = PageObjectFixtures.shape(pageId: 'p1', id: 'a', createdAt: 5);
  final text = PageObjectFixtures.textBox(pageId: 'p1', id: 'b', createdAt: 2);
  final image = PageObjectFixtures.image(
    pageId: 'p1',
    assetId: 'asset-1',
    id: 'c',
    createdAt: 9,
  );
  final math = PageObjectFixtures.math(pageId: 'p1', id: 'd', createdAt: 1);
  final unknown = PageObjectFixtures.unknown(pageId: 'p1', id: 'e');

  test('objects default to none; v1.4 calls still compile and work', () {
    final c = InkPageContent.fromCore(
      page: page,
      strokes: const [],
      revision: 1,
    );
    expect(c.objects, isEmpty);
  });

  test('objects in compareOrder; deleted ones dropped', () {
    final deleted = text.copyWithMeta(deletedAt: 10) as core.TextBoxObject;
    final c = InkPageContent.fromCore(
      page: page,
      strokes: const [],
      objects: [shape, image, math, unknown, deleted],
      revision: 1,
    );
    expect(c.objects.map((o) => o.id), ['d', 'e', 'a', 'c']);
    expect(() => c.objects.add(text), throwsUnsupportedError);
  });

  test('already sorted input is kept as given', () {
    final sorted = [math, unknown, text, shape, image];
    final c = InkPageContent.fromCore(
      page: page,
      strokes: const [],
      objects: sorted,
      revision: 1,
    );
    for (var i = 0; i < sorted.length; i++) {
      expect(identical(c.objects[i], sorted[i]), isTrue);
    }
  });

  test('an object of another page → ArgumentError', () {
    final other = PageObjectFixtures.shape(pageId: 'p2', id: 'x');
    expect(
      () => InkPageContent.fromCore(
        page: page,
        strokes: const [],
        objects: [other],
        revision: 1,
      ),
      throwsArgumentError,
    );
  });

  test('== compares object instances (identity, K-4)', () {
    InkPageContent make(List<core.PageObject> o) => InkPageContent.fromCore(
      page: page,
      strokes: const [],
      objects: o,
      revision: 3,
    );
    expect(make([shape, text]), make([text, shape]));
    expect(make([shape, text]).hashCode, make([shape, text]).hashCode);
    // the same value in a new instance is a change
    final sameValue = shape.copyWith();
    expect(sameValue, shape);
    expect(make([shape]) == make([sameValue]), isFalse);
    expect(make([shape]) == make([shape, text]), isFalse);
  });

  test('L-1 layers: image → underlay, shape → ink, the rest → annotation', () {
    final c = InkPageContent.fromCore(
      page: page,
      strokes: const [],
      objects: [shape, text, image, math, unknown],
      revision: 1,
    );
    expect(underlayObjectsOf(c), [same(image)]);
    expect(inkObjectsOf(c), [same(shape)]);
    expect(annotationObjectsOf(c).map((o) => o.id), ['d', 'e', 'b']);
    expect(objectByIdOf(c, 'a'), same(shape));
    expect(objectByIdOf(c, 'zz'), isNull);
  });

  test('SyntheticInk.pageContentWith builds strokes and objects', () {
    final c = SyntheticInk.pageContentWith(objects: [shape], revision: 7);
    expect(c.pageId, 'p1');
    expect(c.revision, 7);
    expect(c.objects, [same(shape)]);
  });
}
