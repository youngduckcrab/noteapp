// lib/src/render/ink_page_content.dart — contract 7.2.15 (03-ink 4.8); (v2.0) objects
// (2nd round contract 7.2.9, m5-7/03-ink 4.2). Final (T24).
import 'dart:ui' show Size;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../background/background_spec.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_stroke.dart';

/// Immutable drawable snapshot of one page, built from CORE state (so every stroke carries
/// CORE's bounds).
@immutable
final class InkPageContent {
  InkPageContent._(this.page, this.strokes, this.objects, this.revision);

  /// (v1.1) The ONLY constructor. Previews build a core.Page first, e.g.
  /// InkPageContent.fromCore(page: current.copyWith(size: s, background: b),
  ///     strokes: const [], revision: 0).
  ///
  /// Strokes with deletedAt != null are dropped; input already in core.Stroke.compareOrder
  /// is kept as is (checked in O(n)), otherwise sorted. Every stroke must belong to
  /// [page] (ArgumentError). (v2.0) [objects]: the same rules (deleted dropped,
  /// compareOrder, another page → ArgumentError).
  factory InkPageContent.fromCore({
    required core.Page page,
    required List<core.Stroke> strokes,
    List<core.PageObject> objects = const [],
    required int revision,
  }) {
    final active = _activeOrdered(page.id, strokes, 'strokes');
    final activeObjects = _activeOrdered(page.id, objects, 'objects');
    return InkPageContent._(
      page,
      List.unmodifiable(active.map(InkStroke.of)),
      List.unmodifiable(activeObjects),
      revision,
    );
  }

  /// Not deleted, on page [pageId], in core.Stroke.compareOrder (sorted only when needed).
  static List<T> _activeOrdered<T extends core.PageElement>(
    String pageId,
    List<T> elements,
    String argument,
  ) {
    var active = <T>[];
    var sorted = true;
    T? previous;
    for (final e in elements) {
      if (e.pageId != pageId) {
        throw ArgumentError.value(
          e.pageId,
          argument,
          'element ${e.id} belongs to another page than $pageId',
        );
      }
      if (_deletedAt(e) != null) continue;
      if (previous != null && core.Stroke.compareOrder(previous, e) > 0) {
        sorted = false;
      }
      active.add(e);
      previous = e;
    }
    if (!sorted) {
      active = List.of(active)..sort(core.Stroke.compareOrder);
    }
    return active;
  }

  static core.EpochMillis? _deletedAt(core.PageElement e) => switch (e) {
    core.Stroke(:final deletedAt) => deletedAt,
    core.PageObject(:final deletedAt) => deletedAt,
  };

  final core.Page page;

  /// page.id
  String get pageId => page.id;

  /// page.size (pt)
  Size get pageSize => interop.sizeOf(page.size);

  /// InkBackgroundSpec.fromCore(page.background)
  InkBackgroundSpec get background => _background;
  late final InkBackgroundSpec _background = InkBackgroundSpec.fromCore(
    page.background,
  );

  /// bottom → top, unmodifiable
  final List<InkStroke> strokes;

  /// (v2.0) page objects, bottom → top (core.Stroke.compareOrder), unmodifiable
  final List<core.PageObject> objects;

  /// EDITOR passes core.PageContent.revision
  final int revision;

  late final Map<String, int> _index = {
    for (var i = 0; i < strokes.length; i++) strokes[i].id: i,
  };

  late final Map<String, int> _objectIndex = {
    for (var i = 0; i < objects.length; i++) objects[i].id: i,
  };

  /// L-1 layer lists (03-ink 4.2), computed once.
  late final Map<InkObjectLayer, List<core.PageObject>> _byLayer = () {
    final out = {for (final l in InkObjectLayer.values) l: <core.PageObject>[]};
    for (final o in objects) {
      out[objectLayerOf(o)]!.add(o);
    }
    return {
      for (final e in out.entries)
        e.key: List<core.PageObject>.unmodifiable(e.value),
    };
  }();

  /// O(1)
  InkStroke? strokeById(String id) {
    final i = _index[id];
    return i == null ? null : strokes[i];
  }

  /// -1 if absent
  int zIndexOf(String id) => _index[id] ?? -1;

  /// Same page value, revision and the same stroke and object instances (identity, K-4).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InkPageContent ||
        other.revision != revision ||
        other.page != page ||
        other.strokes.length != strokes.length ||
        other.objects.length != objects.length) {
      return false;
    }
    for (var i = 0; i < strokes.length; i++) {
      if (!identical(other.strokes[i].source, strokes[i].source)) return false;
    }
    for (var i = 0; i < objects.length; i++) {
      if (!identical(other.objects[i], objects[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(page, revision, strokes.length, objects.length);

  @override
  String toString() =>
      'InkPageContent(${page.id}, ${strokes.length} strokes, '
      '${objects.length} objects, revision $revision)';
}

/// INTERNAL: the object [id] of [content], O(1); null if absent.
@internal
core.PageObject? objectByIdOf(InkPageContent content, String id) {
  final i = content._objectIndex[id];
  return i == null ? null : content.objects[i];
}

/// INTERNAL: the position of object [id] in content.objects, -1 if absent.
@internal
int objectZIndexOf(InkPageContent content, String id) =>
    content._objectIndex[id] ?? -1;

/// INTERNAL (L-1 layer assignment, m5-7/03-ink 4.2): ImageObject → underlay.
@internal
List<core.PageObject> underlayObjectsOf(InkPageContent content) =>
    content._byLayer[InkObjectLayer.underlay]!;

/// INTERNAL: ShapeObject → ink (mixed with the strokes by compareOrder).
@internal
List<core.PageObject> inkObjectsOf(InkPageContent content) =>
    content._byLayer[InkObjectLayer.ink]!;

/// INTERNAL: TextBoxObject, MathObject, UnknownObject → annotation.
@internal
List<core.PageObject> annotationObjectsOf(InkPageContent content) =>
    content._byLayer[InkObjectLayer.annotation]!;

/// The L-1 layer of a page object (03-ink 4.2).
@internal
enum InkObjectLayer { underlay, ink, annotation }

@internal
InkObjectLayer objectLayerOf(core.PageObject o) => switch (o) {
  core.ImageObject() => InkObjectLayer.underlay,
  core.ShapeObject() => InkObjectLayer.ink,
  core.TextBoxObject() ||
  core.MathObject() ||
  core.UnknownObject() => InkObjectLayer.annotation,
};
