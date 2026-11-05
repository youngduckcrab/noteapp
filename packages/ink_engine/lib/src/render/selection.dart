// lib/src/render/selection.dart — 03-ink 4.8. Math: SelectionGeometry (4.7).
import 'dart:collection';
import 'dart:ui' show Offset, Rect;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../edit/ink_edit.dart';
import '../edit/selection_geometry.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_stroke.dart';
import '../tuning.dart';
import 'page_host.dart';

/// Active selection on one page (PLAN 5.1 올가미). Math: SelectionGeometry (4.7).
final class InkSelection {
  InkSelection._(this._host, Iterable<String> ids)
    : _ids = LinkedHashSet<String>.of(ids);

  final InkPageHost _host;
  final LinkedHashSet<String> _ids;
  core.Affine2 _preview = core.Affine2.identity;
  bool _disposed = false;

  Set<String> get strokeIds => UnmodifiableSetView(_ids);

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

  bool get isEmpty => _ids.isEmpty;

  /// SelectionGeometry.boundsOf(strokes), before the preview
  Rect get bounds => SelectionGeometry.boundsOf(strokes);

  /// core.Affine2.identity initially
  core.Affine2 get previewTransform => _preview;

  /// SelectionGeometry.transformedBounds(bounds, previewTransform)
  Rect get previewBounds =>
      SelectionGeometry.transformedBounds(bounds, _preview);

  /// replaced by another selection / strokes gone
  bool get isDisposed => _disposed;

  /// Live move / resize / rotate preview (6.22). No edit yet. Ignored once disposed.
  void setPreviewTransform(core.Affine2 t) {
    if (_disposed || isEmpty || t == _preview) return;
    _preview = t;
    _host.displayChanged();
  }

  /// transformStrokes(targetIds: strokeIds, transform: previewTransform); null if identity.
  /// The preview stays until updateContent shows the transformed strokes (or discardEdit).
  InkEdit? commitTransform() {
    if (_disposed || isEmpty || _preview.isIdentity) return null;
    final edit = InkEdit(
      pageId: _host.pageId,
      kind: InkEditKind.transformStrokes,
      targetIds: _orderedIds(),
      transform: _preview,
    );
    _host.addPending(edit);
    return edit;
  }

  /// deleteStrokes.
  InkEdit delete() {
    _checkUsable('delete');
    final edit = InkEdit(
      pageId: _host.pageId,
      kind: InkEditKind.deleteStrokes,
      removedIds: _orderedIds(),
    );
    _host.addPending(edit);
    return edit;
  }

  /// duplicateStrokes: copies with new ids, createdAt = nowMillis() + z rank, moved by [offset]
  /// without width scaling (6.22).
  InkEdit duplicate({
    Offset offset = const Offset(
      InkTuning.duplicateOffsetPt,
      InkTuning.duplicateOffsetPt,
    ),
  }) {
    _checkUsable('duplicate');
    final base = _host.services.nowMillis();
    final sources = strokes;
    final copies = <core.Stroke>[
      for (var k = 0; k < sources.length; k++)
        interop.duplicateOf(
          sources[k].source,
          id: _host.services.newStrokeId(),
          createdAt: base + k,
          offset: offset,
        ),
    ];
    final edit = InkEdit(
      pageId: _host.pageId,
      kind: InkEditKind.duplicateStrokes,
      added: List.unmodifiable(copies),
    );
    _host.addPending(edit);
    return edit;
  }

  /// recolorStrokes; color alpha forced to 0xFF (K-5).
  InkEdit recolor(int colorArgb) {
    _checkUsable('recolor');
    final edit = InkEdit(
      pageId: _host.pageId,
      kind: InkEditKind.recolorStrokes,
      targetIds: _orderedIds(),
      colorArgb: interop.opaqueArgb(colorArgb),
    );
    _host.addPending(edit);
    return edit;
  }

  /// Ids in z-order of the current content (ids no longer there are dropped).
  Set<String> _orderedIds() =>
      Set.unmodifiable(LinkedHashSet<String>.of(strokes.map((s) => s.id)));

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
