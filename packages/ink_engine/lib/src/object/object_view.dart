// lib/src/object/object_view.dart — INTERNAL (m5-7/03-ink 6.8.1, T32a).
//
// The render-side view of page objects and the items of a layer:
// - InkObjectView: one per core.PageObject instance (Expando — the same
//   identity rule as InkStroke.of, K-4): its L-1 layer and CORE bounds as a
//   Rect. The per-kind preparations (shape paths, text paragraphs, image
//   display sizes) are added by the render tasks (T33~T36) as lazy fields with
//   the instance's lifetime.
// - InkLayerItem: an entry of a layer's chunk cache — a stroke (InkStrokeItem,
//   one per InkStroke) or an object (InkObjectView). The ink layer is the
//   strokes of InkLayer.ink and the ShapeObjects merged by
//   core.Stroke.compareOrder (two sorted lists, O(n + m)).
import 'dart:ui' show Rect;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../interop/core_interop.dart' as interop;
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../render/ink_page_content.dart';

/// A stroke or an object in one layer, in z order (core.Stroke.compareOrder).
@internal
sealed class InkLayerItem {
  const InkLayerItem();

  /// The element id (strokes and objects never share ids — CORE ids).
  String get id;

  /// The CORE bounds (every rendered pixel is inside — K-1 / K-6).
  Rect get bounds;

  /// The CORE element (z order).
  core.PageElement get element;

  /// z order of two items: core.Stroke.compareOrder of their elements.
  static int compareOrder(InkLayerItem a, InkLayerItem b) =>
      core.Stroke.compareOrder(a.element, b.element);
}

final Expando<InkStrokeItem> _strokeItems = Expando<InkStrokeItem>(
  'InkStrokeItem',
);

/// The layer item of one stroke; the same InkStroke gives the same item.
@internal
final class InkStrokeItem extends InkLayerItem {
  InkStrokeItem._(this.stroke);

  factory InkStrokeItem.of(InkStroke stroke) =>
      _strokeItems[stroke] ??= InkStrokeItem._(stroke);

  final InkStroke stroke;

  @override
  String get id => stroke.id;

  @override
  Rect get bounds => stroke.bounds;

  @override
  core.PageElement get element => stroke.source;

  @override
  String toString() => 'InkStrokeItem(${stroke.id})';
}

final Expando<InkObjectView> _views = Expando<InkObjectView>('InkObjectView');

/// Render-side view of ONE page object instance (see the file comment).
/// Equality = identical(object) — the factory gives one view per instance.
@internal
final class InkObjectView extends InkLayerItem {
  InkObjectView._(this.object);

  factory InkObjectView.of(core.PageObject object) =>
      _views[object] ??= InkObjectView._(object);

  final core.PageObject object;

  @override
  String get id => object.id;

  /// object.bounds as a Rect — the CORE value (7.2.2); INK never recomputes it.
  @override
  Rect get bounds => _bounds;
  late final Rect _bounds = interop.rectOf(object.bounds);

  @override
  core.PageElement get element => object;

  /// L-1 layer: image → underlay, shape → ink, text / math / unknown → annotation.
  InkObjectLayer get layer => objectLayerOf(object);

  @override
  String toString() => 'InkObjectView(${object.type} ${object.id})';
}

/// The ink-layer strokes (InkLayer.ink — not the highlighter, not the cover
/// layer) of [strokes] and the [shapes], both in compareOrder, merged into one
/// compareOrder list. O(n + m); equal keys keep strokes first (ids differ in
/// practice, so the order is total).
@internal
List<InkLayerItem> mergeInkLayer(
  List<InkStroke> strokes,
  List<InkObjectView> shapes,
) {
  final out = <InkLayerItem>[];
  var j = 0;
  for (final s in strokes) {
    if (s.layer != InkLayer.ink) continue;
    final item = InkStrokeItem.of(s);
    while (j < shapes.length &&
        InkLayerItem.compareOrder(shapes[j], item) < 0) {
      out.add(shapes[j++]);
    }
    out.add(item);
  }
  while (j < shapes.length) {
    out.add(shapes[j++]);
  }
  return out;
}

final Expando<_ContentItems> _contentItems = Expando<_ContentItems>(
  'InkContentItems',
);

/// Per-content lists, computed once per InkPageContent instance.
final class _ContentItems {
  _ContentItems(this.content);
  final InkPageContent content;

  late final List<InkObjectView> underlay = List.unmodifiable(
    underlayObjectsOf(content).map(InkObjectView.of),
  );
  late final List<InkObjectView> shapes = List.unmodifiable(
    inkObjectsOf(content).map(InkObjectView.of),
  );
  late final List<InkObjectView> annotation = List.unmodifiable(
    annotationObjectsOf(content).map(InkObjectView.of),
  );
  late final List<InkLayerItem> ink = List.unmodifiable(
    mergeInkLayer(content.strokes, shapes),
  );
}

_ContentItems _itemsOf(InkPageContent content) =>
    _contentItems[content] ??= _ContentItems(content);

/// The object views of [layer] of [content], bottom → top (cached per content).
@internal
List<InkObjectView> objectViewsOf(
  InkPageContent content,
  InkObjectLayer layer,
) => switch (layer) {
  InkObjectLayer.underlay => _itemsOf(content).underlay,
  InkObjectLayer.ink => _itemsOf(content).shapes,
  InkObjectLayer.annotation => _itemsOf(content).annotation,
};

/// The ink layer of [content]: its InkLayer.ink strokes and shapes merged by
/// compareOrder (cached per content).
@internal
List<InkLayerItem> inkLayerItemsOf(InkPageContent content) =>
    _itemsOf(content).ink;
