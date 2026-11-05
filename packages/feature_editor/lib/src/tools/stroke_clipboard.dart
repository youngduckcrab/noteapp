// lib/src/tools/stroke_clipboard.dart — 04-editor 6.6.7 (app-internal clipboard).
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

@immutable
class StrokeClipboardContent {
  const StrokeClipboardContent({required this.strokes, required this.bounds});
  final List<core.Stroke>
  strokes; // in core.Stroke.compareOrder order; ids replaced on paste
  final Rect bounds; // page pt (union of core.Stroke.bounds)
}

/// Global, app lifetime (copy in one note, paste in another).
class StrokeClipboardNotifier extends Notifier<StrokeClipboardContent?> {
  /// Pastes without an explicit point since the last copy.
  int _offsetCount = 0;

  /// Offset step of a repeated paste without an explicit point (pt).
  static const double repeatOffset = 16;

  @override
  StrokeClipboardContent? build() => null;

  /// From session.pageIfLoaded(pageId)!.strokeById(id) for each selected id.
  void copy(List<core.Stroke> strokes) {
    _offsetCount = 0;
    if (strokes.isEmpty) {
      state = null;
      return;
    }
    final ordered = [...strokes]..sort(core.Stroke.compareOrder);
    Rect? bounds;
    for (final s in ordered) {
      final b = s.bounds;
      final r = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
    state = StrokeClipboardContent(
      strokes: List.unmodifiable(ordered),
      bounds: bounds!,
    );
  }

  /// Places the content centred at [center] (page pt) on [pageId], clamped inside
  /// [pageSize] (if larger than the page: top-left at 0,0). Each paste without an
  /// explicit point is offset by +16 pt × n since the last copy.
  /// Every stroke: s.transformed(core.Affine2.translation(dx, dy), scaleWidth: false)
  ///   .copyWith(id: newId(), pageId: pageId, createdAt: createdAt + i)
  /// (i = index in z-order → pasted strokes keep their relative order, on top).
  /// Empty when the clipboard is empty.
  List<core.Stroke> instantiate({
    required String pageId,
    required Size pageSize,
    required Offset center,
    required bool explicitPoint,
    required String Function()
    newId, // ref.read(core.idGeneratorProvider).newId
    required core.EpochMillis createdAt, // clock.now().millisecondsSinceEpoch
  }) {
    final content = state;
    if (content == null) return const [];
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
    return [
      for (var i = 0; i < content.strokes.length; i++)
        content.strokes[i]
            .transformed(move, scaleWidth: false)
            .copyWith(id: newId(), pageId: pageId, createdAt: createdAt + i),
    ];
  }
}

final editorClipboardProvider =
    NotifierProvider<StrokeClipboardNotifier, StrokeClipboardContent?>(
      StrokeClipboardNotifier.new,
      name: 'editorClipboardProvider',
    );
