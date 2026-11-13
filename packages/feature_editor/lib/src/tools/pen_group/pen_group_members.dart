// lib/src/tools/pen_group/pen_group_members.dart — the part of a pen group
// (수식 펜 / 텍스트 펜) that follows the page: which strokes are members, and
// how a page change (undo / redo / remote / the eraser) moves them. Shared
// by MathPenController and TextPenController (m5-7/04-editor 6.21).
//
// A partial-eraser piece keeps its stroke's createdAt, style and recording
// (Stroke.fragment) and lies inside the erased stroke's bounds: it stays in
// the group. A pasted copy of the same ink lies elsewhere and stays out.
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:note_core/note_core.dart' as core;

import '../math_pen/math_pen_group.dart' show strokePointBounds;

/// What a partial-eraser piece of a member keeps (Stroke.fragment): the
/// piece belongs to the group when it matches the erased member.
final class PenStrokeOrigin {
  PenStrokeOrigin(core.Stroke s)
    : createdAt = s.createdAt,
      style = s.style,
      recordingId = s.recordingId,
      recordingOffsetMs = s.recordingOffsetMs,
      bounds = strokePointBounds(s).inflate(0.5);

  final int createdAt;
  final core.StrokeStyle style;
  final String? recordingId;
  final int? recordingOffsetMs;
  final Rect bounds;

  bool isPieceOf(core.Stroke piece) {
    if (piece.createdAt != createdAt ||
        piece.style != style ||
        piece.recordingId != recordingId ||
        piece.recordingOffsetMs != recordingOffsetMs) {
      return false;
    }
    final b = strokePointBounds(piece);
    return bounds.contains(b.topLeft) && bounds.contains(b.bottomRight);
  }
}

/// What a page change did to a group ([PenGroupMembers.sync]).
enum PenGroupSync {
  /// Nothing of the group changed.
  none,

  /// Members came or went (ids holds the new list — maybe empty).
  members,

  /// A member changed in place (a remote edit, a recolour).
  updatedInPlace,
}

/// The members of one pen group on [pageId], z order.
class PenGroupMembers {
  PenGroupMembers(this.pageId, List<core.Stroke> strokes) {
    strokes.forEach(add);
  }

  final String pageId;
  final List<String> ids = [];
  final Set<String> known = {};
  final Map<String, PenStrokeOrigin> originOf = {};

  void add(core.Stroke s) {
    if (!ids.contains(s.id)) ids.add(s.id);
    known.add(s.id);
    originOf[s.id] = PenStrokeOrigin(s);
  }

  /// Follows [change] of this group's page: a member updated in place
  /// moves its origin, partial-eraser pieces of a gone member join, and
  /// [ids] becomes the members still on the page (page z order).
  PenGroupSync sync(core.PageContentChange change) {
    final content = change.content;
    // A member moved / recoloured in place: its pieces follow the new one.
    for (final id in change.updated) {
      final s = known.contains(id) ? content.strokeById(id) : null;
      if (s != null) originOf[id] = PenStrokeOrigin(s);
    }
    final gone = [
      for (final id in ids)
        if (content.strokeById(id) == null) id,
    ];
    if (gone.isNotEmpty && change.added.isNotEmpty) {
      // Partial-eraser pieces: the erased member's createdAt, style and
      // recording, inside its bounds (a pasted copy of the same ink is
      // elsewhere).
      final origins = [for (final id in gone) ?originOf[id]];
      for (final id in change.added) {
        final s = content.strokeById(id);
        if (s != null &&
            !known.contains(id) &&
            origins.any((o) => o.isPieceOf(s))) {
          add(s);
        }
      }
    }
    final next = [
      for (final s in content.strokes)
        if (known.contains(s.id)) s.id,
    ];
    if (!listEquals(next, ids)) {
      ids
        ..clear()
        ..addAll(next);
      return PenGroupSync.members;
    }
    if (change.updated.any(known.contains)) return PenGroupSync.updatedInPlace;
    return PenGroupSync.none;
  }

  /// Whether [change] of [pageId] is the undo of the conversion of these
  /// members: one of them came back and all of them are on the page.
  bool cameBackIn(core.PageContentChange change) =>
      change.content.page.id == pageId &&
      ids.isNotEmpty &&
      ids.any(
        (id) => change.added.contains(id) || change.updated.contains(id),
      ) &&
      ids.every((id) => change.content.strokeById(id) != null);
}
