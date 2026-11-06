// lib/src/tools/element_clipboard.dart — 04-editor 6.6.7 (app-internal
// clipboard); (v2, E2-07a — m5-7/04-editor 6.8) renamed from
// stroke_clipboard.dart: strokes AND page objects.
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

@immutable
class ElementClipboardContent {
  const ElementClipboardContent({required this.elements, required this.bounds});

  /// Strokes and objects together, core.Stroke.compareOrder (z order); ids
  /// replaced on paste.
  final List<core.PageElement> elements;

  /// page pt, union of element bounds
  final Rect bounds;

  int get objectCount => elements.whereType<core.PageObject>().length;

  /// The strokes, z order.
  List<core.Stroke> get strokes =>
      List.unmodifiable(elements.whereType<core.Stroke>());
}

/// Global, app lifetime (copy in one note, paste in another).
class ElementClipboardNotifier extends Notifier<ElementClipboardContent?> {
  /// Pastes without an explicit point since the last copy.
  int _offsetCount = 0;

  /// Offset step of a repeated paste without an explicit point (pt).
  static const double repeatOffset = 16;

  @override
  ElementClipboardContent? build() => null;

  /// From session.pageIfLoaded(pageId)!.elementById(id) for each selected id
  /// (CORE state). Resets the paste offset counter; empty → cleared.
  void copy(List<core.PageElement> elements) {
    _offsetCount = 0;
    if (elements.isEmpty) {
      state = null;
      return;
    }
    final ordered = [...elements]..sort(core.Stroke.compareOrder);
    Rect? bounds;
    for (final e in ordered) {
      final b = e.bounds;
      final r = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
    state = ElementClipboardContent(
      elements: List.unmodifiable(ordered),
      bounds: bounds!,
    );
  }

  /// v1.4 placement rules: the content centred at [center] (page pt) on
  /// [pageId], clamped inside [pageSize] (if larger than the page: top-left
  /// at 0,0); each paste without an explicit point is offset by +16 pt × n
  /// since the last copy. Each element i (z order, strokes and objects ranked
  /// together — they keep their relative order, on top): stroke →
  /// s.transformed(move, scaleWidth: false).copyWith(id: newId(), pageId,
  /// createdAt: createdAt + i); object → o.transformed(move).copyTo(id:
  /// newId(), pageId, createdAt: createdAt + i) — an UnknownObject stays
  /// where it was (transformed returns it unchanged), an image keeps its
  /// assetId. Empty when the clipboard is empty.
  ({List<core.Stroke> strokes, List<core.PageObject> objects}) instantiate({
    required String pageId,
    required Size pageSize,
    required Offset center,
    required bool explicitPoint,
    required String Function()
    newId, // ref.read(core.idGeneratorProvider).newId
    required core.EpochMillis createdAt, // clock.now().millisecondsSinceEpoch
  }) {
    final content = state;
    if (content == null) return (strokes: const [], objects: const []);
    final bounds = content.bounds;
    var target = center;
    if (!explicitPoint) {
      target += Offset(repeatOffset, repeatOffset) * _offsetCount.toDouble();
      _offsetCount++;
    }
    double place(double centre, double extent, double limit) {
      if (extent > limit) return 0;
      return (centre - extent / 2).clamp(0.0, limit - extent).toDouble();
    }

    final left = place(target.dx, bounds.width, pageSize.width);
    final top = place(target.dy, bounds.height, pageSize.height);
    final move = core.Affine2.translation(left - bounds.left, top - bounds.top);
    final strokes = <core.Stroke>[];
    final objects = <core.PageObject>[];
    for (var i = 0; i < content.elements.length; i++) {
      switch (content.elements[i]) {
        case final core.Stroke s:
          strokes.add(
            s
                .transformed(move, scaleWidth: false)
                .copyWith(
                  id: newId(),
                  pageId: pageId,
                  createdAt: createdAt + i,
                ),
          );
        case final core.PageObject o:
          objects.add(
            o
                .transformed(move)
                .copyTo(id: newId(), pageId: pageId, createdAt: createdAt + i),
          );
      }
    }
    return (
      strokes: List.unmodifiable(strokes),
      objects: List.unmodifiable(objects),
    );
  }
}

final editorClipboardProvider =
    NotifierProvider<ElementClipboardNotifier, ElementClipboardContent?>(
      ElementClipboardNotifier.new,
      name: 'editorClipboardProvider',
    );
