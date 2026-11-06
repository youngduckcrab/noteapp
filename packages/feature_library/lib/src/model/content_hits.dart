// lib/src/model/content_hits.dart — (v2) 05-library 4.4.10, 6.1.2, 6.1.4: the '노트 내용'
// group of the search results. CORE gives the hits already ordered (score); LIBRARY only
// groups them by note (L2-D1) and turns a hit's rects into one focus rect (L2-D2).
import 'dart:ui' show Rect;

import 'package:collection/collection.dart' show ListEquality;
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart' show NoteId, PageSearchHit;

const ListEquality<PageSearchHit> _hitsEq = ListEquality<PageSearchHit>();

/// The content hits of one note, in CORE order.
@immutable
final class ContentHitGroup {
  const ContentHitGroup({required this.noteId, required this.hits});

  final NoteId noteId;

  /// CORE order (score), never re-sorted.
  final List<PageSearchHit> hits;

  @override
  bool operator ==(Object other) =>
      other is ContentHitGroup &&
      other.noteId == noteId &&
      _hitsEq.equals(other.hits, hits);

  @override
  int get hashCode => Object.hash(noteId, _hitsEq.hash(hits));

  @override
  String toString() => 'ContentHitGroup($noteId, ${hits.length} hits)';
}

/// Stable group-by noteId: groups in the order of each note's first hit (L2-D1).
///
/// 6.1.2: `[(A,p3), (B,p1), (A,p1), (C,p2), (B,p4)]` → `[A: p3, p1] [B: p1, p4] [C: p2]`.
/// A repeated `(noteId, pageId)` is kept as it is (CORE groups by page; LIBRARY never
/// fixes CORE results).
List<ContentHitGroup> groupContentHits(List<PageSearchHit> hits) {
  if (hits.isEmpty) return const [];
  final byNote = <NoteId, List<PageSearchHit>>{};
  for (final hit in hits) {
    (byNote[hit.noteId] ??= []).add(hit);
  }
  return List.unmodifiable([
    for (final MapEntry(key: noteId, value: noteHits) in byNote.entries)
      ContentHitGroup(noteId: noteId, hits: List.unmodifiable(noteHits)),
  ]);
}

/// Union of hit.rects (note page pt) or null when empty (L2-D2).
Rect? focusRectOf(PageSearchHit hit) {
  final rects = hit.rects;
  if (rects.isEmpty) return null;
  var left = rects.first.left;
  var top = rects.first.top;
  var right = rects.first.right;
  var bottom = rects.first.bottom;
  for (final r in rects.skip(1)) {
    if (r.left < left) left = r.left;
    if (r.top < top) top = r.top;
    if (r.right > right) right = r.right;
    if (r.bottom > bottom) bottom = r.bottom;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}
