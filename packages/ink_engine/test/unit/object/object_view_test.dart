// m5-7/03-ink T32a (6.8.1): InkObjectView — one view per core.PageObject
// instance (Expando, the InkStroke.of identity rule), its L-1 layer and CORE
// bounds; the ink layer = InkLayer.ink strokes + shapes merged by
// core.Stroke.compareOrder (highlighter strokes stay out), cached per content.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/object/object_view.dart';
import 'package:ink_engine/src/render/ink_page_content.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../../support/pixels.dart';

core.Stroke _stroke(
  String id,
  int createdAt, {
  core.PenTool tool = core.PenTool.ballpoint,
}) => strokeThrough(
  segment(const ui.Offset(40, 40), const ui.Offset(80, 50)),
  core.StrokeStyle.defaultsFor(tool),
  id: id,
).copyWith(createdAt: createdAt);

void main() {
  final page = SyntheticInk.page();

  test('one view per object instance; equal copies get their own view', () {
    final a = PageObjectFixtures.shape(pageId: page.id, id: 'a');
    final again = PageObjectFixtures.shape(pageId: page.id, id: 'a');
    expect(identical(a, again), isFalse);
    expect(InkObjectView.of(a), same(InkObjectView.of(a)));
    expect(InkObjectView.of(again), isNot(same(InkObjectView.of(a))));
    expect(InkObjectView.of(a).object, same(a));
    expect(InkObjectView.of(a).id, 'a');
    expect(InkObjectView.of(a).element, same(a));
  });

  test('bounds = the CORE bounds as a Rect', () {
    final shape = PageObjectFixtures.shape(
      pageId: page.id,
      kind: core.ShapeKind.ellipse,
    );
    final text = PageObjectFixtures.textBox(pageId: page.id);
    for (final o in <core.PageObject>[shape, text]) {
      final b = o.bounds;
      expect(
        InkObjectView.of(o).bounds,
        ui.Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
      );
    }
    // the shape's CORE bounds include its stroke width (inflated frame)
    expect(
      InkObjectView.of(shape).bounds.width,
      greaterThan(shape.frame.bounds.width),
    );
  });

  test('L-1 layer per kind', () {
    final layers = {
      for (final o in <core.PageObject>[
        PageObjectFixtures.image(pageId: page.id, assetId: 'x', id: 'i'),
        PageObjectFixtures.shape(pageId: page.id, id: 's'),
        PageObjectFixtures.textBox(pageId: page.id, id: 't'),
        PageObjectFixtures.math(pageId: page.id, id: 'm'),
        PageObjectFixtures.unknown(pageId: page.id, id: 'u'),
      ])
        o.id: InkObjectView.of(o).layer,
    };
    expect(layers, {
      'i': InkObjectLayer.underlay,
      's': InkObjectLayer.ink,
      't': InkObjectLayer.annotation,
      'm': InkObjectLayer.annotation,
      'u': InkObjectLayer.annotation,
    });
  });

  test('stroke items: one per InkStroke', () {
    final s = InkStroke.of(_stroke('s1', 1));
    expect(InkStrokeItem.of(s), same(InkStrokeItem.of(s)));
    expect(InkStrokeItem.of(s).id, 's1');
    expect(InkStrokeItem.of(s).bounds, s.bounds);
    expect(InkStrokeItem.of(s).element, same(s.source));
  });

  test('the ink layer merges ink strokes and shapes by compareOrder; '
      'highlighter strokes are not in it', () {
    final rnd = math.Random(32);
    final strokes = <core.Stroke>[];
    final objects = <core.PageObject>[];
    for (var i = 0; i < 300; i++) {
      final createdAt = rnd.nextInt(60); // ties: id breaks them
      switch (rnd.nextInt(4)) {
        case 0:
          strokes.add(
            _stroke('h$i', createdAt, tool: core.PenTool.highlighter),
          );
        case 1:
          objects.add(
            PageObjectFixtures.shape(
              pageId: page.id,
              id: 'o$i',
              createdAt: createdAt,
            ),
          );
        case 2:
          objects.add(
            PageObjectFixtures.textBox(
              pageId: page.id,
              id: 't$i',
              createdAt: createdAt,
            ),
          );
        default:
          strokes.add(_stroke('s$i', createdAt));
      }
    }
    final content = InkPageContent.fromCore(
      page: page,
      strokes: strokes,
      objects: objects,
      revision: 1,
    );
    final items = inkLayerItemsOf(content);
    final expected = <core.PageElement>[
      for (final s in strokes)
        if (s.style.tool != core.PenTool.highlighter) s,
      for (final o in objects)
        if (o is core.ShapeObject) o,
    ]..sort(core.Stroke.compareOrder);
    expect(items.map((i) => i.id).toList(), expected.map((e) => e.id).toList());
    for (var i = 1; i < items.length; i++) {
      expect(InkLayerItem.compareOrder(items[i - 1], items[i]), lessThan(0));
    }
    expect(
      items.whereType<InkStrokeItem>().every(
        (i) => i.stroke.layer == InkLayer.ink,
      ),
      isTrue,
    );
    // cached per content; the views are the per-instance views
    expect(inkLayerItemsOf(content), same(items));
    for (final v in items.whereType<InkObjectView>()) {
      expect(v, same(InkObjectView.of(v.object)));
    }
    expect(objectViewsOf(content, InkObjectLayer.annotation).map((v) => v.id), [
      for (final o in content.objects)
        if (o is core.TextBoxObject) o.id,
    ]);
    expect(
      objectViewsOf(content, InkObjectLayer.ink).map((v) => v.object),
      inkObjectsOf(content),
    );
  });

  test('a stroke and a shape at the same createdAt: id order', () {
    final shape = PageObjectFixtures.shape(
      pageId: page.id,
      id: 'b',
      createdAt: 5,
    );
    final content = InkPageContent.fromCore(
      page: page,
      strokes: [_stroke('a', 5), _stroke('c', 5)],
      objects: [shape],
      revision: 1,
    );
    expect(inkLayerItemsOf(content).map((i) => i.id), ['a', 'b', 'c']);
  });

  test('empty sides', () {
    final onlyStrokes = InkPageContent.fromCore(
      page: page,
      strokes: [_stroke('a', 1), _stroke('b', 2)],
      revision: 1,
    );
    expect(inkLayerItemsOf(onlyStrokes).map((i) => i.id), ['a', 'b']);
    final onlyShapes = InkPageContent.fromCore(
      page: page,
      strokes: const [],
      objects: [
        PageObjectFixtures.shape(pageId: page.id, id: 'x', createdAt: 2),
        PageObjectFixtures.shape(pageId: page.id, id: 'w', createdAt: 1),
      ],
      revision: 1,
    );
    expect(inkLayerItemsOf(onlyShapes).map((i) => i.id), ['w', 'x']);
  });
}
