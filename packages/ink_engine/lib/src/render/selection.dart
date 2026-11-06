// lib/src/render/selection.dart — 03-ink 4.8. Math: SelectionGeometry (4.7).
// (v2.0) Selections cover page objects too (2nd round contract 7.2.9, m5-7/03-ink 4.6,
// 6.14): objectIds / allIds / objects; preview, commit, delete, duplicate and recolor
// include the objects. Object previews use CORE PageObject.transformed(m, scaleWidth: true)
// — the resolver's function, so preview = commit (CD2-07).
import 'dart:collection';
import 'dart:ui' show Offset, Rect;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../edit/ink_edit.dart';
import '../edit/selection_geometry.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_stroke.dart';
import '../tuning.dart';
import 'ink_page_content.dart';
import 'page_host.dart';

/// Active selection on one page (PLAN 5.1 올가미). Math: SelectionGeometry (4.7).
final class InkSelection {
  InkSelection._(this._host, Iterable<String> ids)
    : _ids = LinkedHashSet<String>.of(ids);

  final InkPageHost _host;
  final LinkedHashSet<String> _ids;
  core.Affine2 _preview = core.Affine2.identity;
  bool _disposed = false;

  /// The selected strokes' ids (v1.4 meaning: strokes only).
  Set<String> get strokeIds {
    final content = _host.content;
    if (content == null) return const {};
    return UnmodifiableSetView({
      for (final id in _ids)
        if (content.strokeById(id) != null) id,
    });
  }

  /// (v2.0) The selected page objects' ids.
  Set<String> get objectIds {
    final content = _host.content;
    if (content == null) return const {};
    return UnmodifiableSetView({
      for (final id in _ids)
        if (objectByIdOf(content, id) != null) id,
    });
  }

  /// (v2.0) Strokes and objects, z order (core.Stroke.compareOrder).
  Set<String> get allIds =>
      UnmodifiableSetView({for (final e in _elements()) e.id});

  /// z-order
  List<InkStroke> get strokes {
    final content = _host.content;
    if (content == null) return const [];
    final out = <InkStroke>[for (final id in _ids) ?content.strokeById(id)];
    out.sort(
      (a, b) => content.zIndexOf(a.id).compareTo(content.zIndexOf(b.id)),
    );
    return List.unmodifiable(out);
  }

  /// (v2.0) The selected objects, z order.
  List<core.PageObject> get objects {
    final content = _host.content;
    if (content == null) return const [];
    final out = <core.PageObject>[
      for (final id in _ids) ?objectByIdOf(content, id),
    ]..sort(core.Stroke.compareOrder);
    return List.unmodifiable(out);
  }

  bool get isEmpty => _ids.isEmpty;

  /// SelectionGeometry.boundsOf(strokes) ∪ the objects' CORE bounds, before the preview
  /// (rotated objects count with their AABB).
  Rect get bounds {
    final strokes = this.strokes;
    Rect? out = strokes.isEmpty ? null : SelectionGeometry.boundsOf(strokes);
    for (final o in objects) {
      final b = interop.rectOf(o.bounds);
      out = out == null ? b : out.expandToInclude(b);
    }
    return out ?? Rect.zero;
  }

  /// core.Affine2.identity initially
  core.Affine2 get previewTransform => _preview;

  /// SelectionGeometry.transformedBounds(bounds, previewTransform)
  Rect get previewBounds =>
      SelectionGeometry.transformedBounds(bounds, _preview);

  /// replaced by another selection / strokes gone
  bool get isDisposed => _disposed;

  /// Live move / resize / rotate preview (6.22). No edit yet. Ignored once disposed.
  /// (v2.0) Objects are previewed as object.transformed(m, scaleWidth: true); an
  /// UnknownObject stays in place.
  void setPreviewTransform(core.Affine2 t) {
    if (_disposed || isEmpty || t == _preview) return;
    _preview = t;
    _host.displayChanged();
  }

  /// transformStrokes(targetIds: allIds without UnknownObjects, transform: previewTransform);
  /// null if identity (or only unknown objects are selected).
  /// The preview stays until updateContent shows the transformed elements (or discardEdit).
  InkEdit? commitTransform() {
    if (_disposed || isEmpty || _preview.isIdentity) return null;
    final targets = <String>{
      for (final e in _elements())
        if (e is! core.UnknownObject) e.id,
    };
    if (targets.isEmpty) return null;
    final edit = InkEdit(
      pageId: _host.pageId,
      kind: InkEditKind.transformStrokes,
      targetIds: Set.unmodifiable(targets),
      transform: _preview,
    );
    _host.addPending(edit);
    return edit;
  }

  /// deleteStrokes(removedIds: allIds, removedObjectIds: objectIds) — RemoveElements when
  /// objects are part of it.
  InkEdit delete() {
    _checkUsable('delete');
    final elements = _elements();
    final edit = InkEdit(
      pageId: _host.pageId,
      kind: InkEditKind.deleteStrokes,
      removedIds: Set.unmodifiable({for (final e in elements) e.id}),
      removedObjectIds: Set.unmodifiable({
        for (final e in elements)
          if (e is core.PageObject) e.id,
      }),
    );
    _host.addPending(edit);
    return edit;
  }

  /// duplicateStrokes: copies with new ids, createdAt = nowMillis() + z rank (strokes and
  /// objects ranked together), moved by [offset] without width scaling (6.22). Objects:
  /// object.copyTo(...).transformed(move) — an UnknownObject copy stays in place.
  InkEdit duplicate({
    Offset offset = const Offset(
      InkTuning.duplicateOffsetPt,
      InkTuning.duplicateOffsetPt,
    ),
  }) {
    _checkUsable('duplicate');
    final base = _host.services.nowMillis();
    final elements = _elements();
    final strokeCopies = <core.Stroke>[];
    final objectCopies = <core.PageObject>[];
    final move = core.Affine2.translation(offset.dx, offset.dy);
    for (var k = 0; k < elements.length; k++) {
      final e = elements[k];
      final id = _host.services.newStrokeId();
      switch (e) {
        case core.Stroke():
          strokeCopies.add(
            interop.duplicateOf(e, id: id, createdAt: base + k, offset: offset),
          );
        case core.PageObject():
          objectCopies.add(
            e
                .copyTo(id: id, pageId: _host.pageId, createdAt: base + k)
                .transformed(move, scaleWidth: false),
          );
      }
    }
    final edit = InkEdit(
      pageId: _host.pageId,
      kind: InkEditKind.duplicateStrokes,
      added: List.unmodifiable(strokeCopies),
      addedObjects: List.unmodifiable(objectCopies),
    );
    _host.addPending(edit);
    return edit;
  }

  /// recolorStrokes; color alpha forced to 0xFF (K-5). (v2.0) Objects: shape stroke color,
  /// text and math color (in updatedObjects); images and unknown objects are left out. When
  /// nothing can be recolored the edit isEmpty (EDITOR does not run it — S-14).
  InkEdit recolor(int colorArgb) {
    _checkUsable('recolor');
    final color = interop.opaqueArgb(colorArgb);
    final targets = <String>{};
    final updated = <core.PageObject>[];
    for (final e in _elements()) {
      switch (e) {
        case core.Stroke():
          targets.add(e.id);
        case core.ShapeObject():
          targets.add(e.id);
          updated.add(
            e.copyWith(style: e.style.copyWith(strokeColorArgb: color)),
          );
        case core.TextBoxObject():
          targets.add(e.id);
          updated.add(e.copyWith(style: e.style.copyWith(colorArgb: color)));
        case core.MathObject():
          targets.add(e.id);
          updated.add(e.copyWith(style: e.style.copyWith(colorArgb: color)));
        case core.ImageObject() || core.UnknownObject():
          break;
      }
    }
    final edit = InkEdit(
      pageId: _host.pageId,
      kind: InkEditKind.recolorStrokes,
      targetIds: Set.unmodifiable(targets),
      colorArgb: color,
      updatedObjects: List.unmodifiable(updated),
    );
    if (!edit.isEmpty) _host.addPending(edit);
    return edit;
  }

  /// The selected strokes' CORE values and objects of the current content, z order (ids no
  /// longer there are dropped).
  List<core.PageElement> _elements() {
    final content = _host.content;
    if (content == null) return const [];
    final out = <core.PageElement>[
      for (final id in _ids)
        ?(content.strokeById(id)?.source ?? objectByIdOf(content, id)),
    ]..sort(core.Stroke.compareOrder);
    return out;
  }

  void _checkUsable(String what) {
    if (isEmpty) throw StateError('Cannot $what an empty selection');
    if (_disposed) throw StateError('Cannot $what a disposed selection');
  }
}

@internal
InkSelection newInkSelection(InkPageHost host, Iterable<String> ids) =>
    InkSelection._(host, ids);

@internal
void disposeInkSelection(InkSelection selection) {
  selection._disposed = true;
}

/// Ends the preview transform (commit resolved or discarded).
@internal
void resetSelectionPreview(InkSelection selection) {
  selection._preview = core.Affine2.identity;
}

/// Keeps only ids for which [keep] is true; returns true when ids remain.
@internal
bool retainSelectionIds(InkSelection selection, bool Function(String) keep) {
  selection._ids.retainWhere(keep);
  return selection._ids.isNotEmpty;
}

/// The ids of the selection (strokes and objects, insertion order).
@internal
Set<String> selectionIdsOf(InkSelection selection) => selection._ids;
