// lib/src/indexer/line_reuse.dart — (internal, pure) line reuse, the
// confirmed-line rule and the two update merges (m5-7/05-library 6.9.3,
// 6.9.4, 6.13.5; contract 7.2.5 HandwritingLine.userConfirmed comment).
//
// Everything here is pure and synchronous: the merges run inside
// HandwritingRepository.update's transform (no clock, no ids, no store —
// 02-core 6.9.4), so the values they need (nowMs, line geometry) come in
// IndexerResult. Three writers share a page's entity — the indexer
// (mergeIndexerResult), the conversion sheet (mergeConfirmed) and the remote
// apply — and both merges run on the STORED value (CD2-12).
//  - ① reuse (in the job): a stored line with exactly the stroke set of a new
//    line group, confirmed or of the job's language → that line, rect only
//    new; the engine id is not looked at.
//  - ② mergeIndexerResult: stored value fresh → null; confirmed lines paired
//    one to one with computed lines (most shared strokes first); kept while
//    ≥ 80 % of their strokes remain and every added glyph box is ≤ the line's
//    H, else replaced by the engine text with the old text first among the
//    alternatives; unpaired confirmed lines put their text first among the
//    alternatives of the line their strokes went to, or vanish with their
//    ink.
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../lines/glyph_boxes.dart';

/// Alternatives kept per line (contract: ≤ 5).
const int kMaxLineAlternatives = 5;

/// The language tail of a HandwritingText.engineId: 'fake:ko' → 'ko',
/// 'mlkit-digital-ink/19.0.0:en' → 'en'; '' without a ':'.
String languageOfEngineId(String engineId) {
  final i = engineId.lastIndexOf(':');
  return i < 0 ? '' : engineId.substring(i + 1);
}

/// (v2.1, review S-3) Fresh = same sourceRev AND same language tail; the
/// engine, its version and the device are provenance only (contract 7.2.5).
bool isFreshResult(core.HandwritingText value, String sourceRev, String lang) =>
    value.sourceRev == sourceRev && languageOfEngineId(value.engineId) == lang;

/// Geometry of one computed line, for the confirmed-line rule (6.9.4 ②).
@immutable
final class LineGeometry {
  const LineGeometry({
    required this.strokeBoxes,
    required this.strokeHeight,
    required this.glyphHeight,
  });

  /// Stroke id → its point box (page pt).
  final Map<core.ElementId, core.PageRect> strokeBoxes;

  /// h_s of the line — the median stroke-box height (6.5 step 2), pt.
  final double strokeHeight;

  /// H_G — the line's median glyph-box height (6.5 step 3), pt.
  final double glyphHeight;
}

/// What a page job computed (6.9.3), closed into the update transform.
@immutable
final class IndexerResult {
  const IndexerResult({
    required this.rev,
    required this.lang,
    required this.engineId,
    required this.lines,
    required this.geometry,
    required this.nowMs,
  });

  /// HandwritingText.sourceRevOf the input strokes the job read.
  final String rev;

  /// recog.language of the job.
  final String lang;

  /// `'<recognizer.engineId>:<lang>'`.
  final String engineId;

  /// Reading order (groupIntoLines).
  final List<core.HandwritingLine> lines;

  /// One per line, same order.
  final List<LineGeometry> geometry;

  /// store.clock at the end of the job (the transform reads no clock).
  final core.EpochMillis nowMs;
}

String _setKey(Iterable<core.ElementId> ids) =>
    (ids.toList()..sort()).join('\u0000');

/// 6.9.4 ① — the stored lines of a page by stroke set (read once per job).
final class LineReuse {
  LineReuse(core.HandwritingText? existing)
    : _bySet = {
        for (final l in existing?.lines ?? const <core.HandwritingLine>[])
          _setKey(l.strokeIds): l,
      };

  final Map<String, core.HandwritingLine> _bySet;

  /// The stored line with exactly [strokeIds] as its stroke set when it is
  /// confirmed or of [lang]: that line with [rect] and [strokeIds] (moving
  /// or recolouring strokes keeps their text). null → recognize the group.
  core.HandwritingLine? reuse(
    List<core.ElementId> strokeIds,
    String lang,
    core.PageRect rect,
  ) {
    final line = _bySet[_setKey(strokeIds)];
    if (line == null) return null;
    if (!line.userConfirmed && line.languageTag != lang) return null;
    return line.copyWith(rect: rect, strokeIds: strokeIds);
  }
}

/// [first] (when given) then [rest] without duplicates and without [text],
/// at most [kMaxLineAlternatives].
List<String> _alternatives(String text, List<String> first, List<String> rest) {
  final out = <String>[];
  for (final a in [...first, ...rest]) {
    if (out.length == kMaxLineAlternatives) break;
    if (a != text && !out.contains(a)) out.add(a);
  }
  return List.unmodifiable(out);
}

/// 6.9.4 ② step 3: may confirmed line [l] keep its text in computed line
/// [g]? ≥ 80 % of its strokes remain (integers — no rounding at 0.8) and
/// every glyph box of the added strokes (joined among themselves, widened
/// by the line's h_s) is no larger than the line's H in both directions.
bool keepsConfirmed(
  core.HandwritingLine l,
  core.HandwritingLine g,
  LineGeometry geometry,
) {
  final inG = g.strokeIds.toSet();
  final old = l.strokeIds.toSet();
  final kept = old.where(inG.contains).length;
  if (old.isEmpty || 5 * kept < 4 * old.length) return false;
  final added = [
    for (final id in g.strokeIds)
      if (!old.contains(id))
        if (geometry.strokeBoxes[id] case final r?)
          InkBox(r.left, r.top, r.right, r.bottom),
  ];
  if (added.isEmpty) return true;
  final glyphs = buildGlyphBoxes(added, strokeHeight: geometry.strokeHeight);
  return glyphs.every(
    (b) => math.max(b.box.width, b.box.height) <= geometry.glyphHeight,
  );
}

/// 6.9.4 ② — runs inside HandwritingRepository.update's transform: pure and
/// synchronous. [current] is the STORED value (null if none / deleted).
core.HandwritingText? mergeIndexerResult(
  core.HandwritingText? current,
  IndexerResult computed, {
  required core.NoteId noteId,
  required core.PageId pageId,
}) {
  // 1. Fresh already (the conversion sheet's full copy, another device).
  if (current != null && isFreshResult(current, computed.rev, computed.lang)) {
    return null;
  }
  final lines = List.of(computed.lines);
  final confirmed = [
    for (final l in current?.lines ?? const <core.HandwritingLine>[])
      if (l.userConfirmed) l,
  ];
  if (confirmed.isNotEmpty) {
    // 2. One-to-one pairs, most shared strokes first (then computed reading
    // order, then confirmed reading order).
    final computedSets = [for (final g in lines) g.strokeIds.toSet()];
    final pairs = <(int, int, int)>[]; // (shared, g, l)
    for (var li = 0; li < confirmed.length; li++) {
      for (var gi = 0; gi < lines.length; gi++) {
        final shared = confirmed[li].strokeIds
            .where(computedSets[gi].contains)
            .length;
        if (shared > 0) pairs.add((shared, gi, li));
      }
    }
    pairs.sort((a, b) {
      var c = b.$1.compareTo(a.$1);
      if (c != 0) return c;
      c = a.$2.compareTo(b.$2);
      return c != 0 ? c : a.$3.compareTo(b.$3);
    });
    final lineOf = <int, int>{}; // confirmed → computed
    final pairedComputed = <int>{};
    for (final (_, gi, li) in pairs) {
      if (lineOf.containsKey(li) || pairedComputed.contains(gi)) continue;
      lineOf[li] = gi;
      pairedComputed.add(gi);
    }
    // 3. Keep or replace each pair.
    final kept = <int>{};
    final replacedText = <int, String>{}; // computed → old confirmed text
    for (final MapEntry(key: li, value: gi) in lineOf.entries) {
      final l = confirmed[li], g = lines[gi];
      if (keepsConfirmed(l, g, computed.geometry[gi])) {
        lines[gi] = l.copyWith(rect: g.rect, strokeIds: g.strokeIds);
        kept.add(gi);
      } else {
        replacedText[gi] = l.text;
      }
    }
    // 4. Unpaired confirmed lines: their text goes to the line their strokes
    // went to (most shared, then reading order) unless that line kept a
    // confirmed text; no stroke left → dropped with the ink.
    final joinedTexts = <int, List<String>>{};
    for (var li = 0; li < confirmed.length; li++) {
      if (lineOf.containsKey(li)) continue;
      final best = pairs.where((p) => p.$3 == li).firstOrNull;
      if (best == null || kept.contains(best.$2)) continue;
      (joinedTexts[best.$2] ??= []).add(confirmed[li].text);
    }
    for (var gi = 0; gi < lines.length; gi++) {
      if (kept.contains(gi)) continue;
      final old = replacedText[gi];
      final joined = joinedTexts[gi] ?? const <String>[];
      if (old == null && joined.isEmpty) continue;
      final g = lines[gi];
      lines[gi] = g.copyWith(
        userConfirmed: false,
        alternatives: _alternatives(g.text, [?old, ...joined], g.alternatives),
      );
    }
  }
  // 5. The page's value.
  return core.HandwritingText(
    noteId: noteId,
    pageId: pageId,
    engineId: computed.engineId,
    sourceRev: computed.rev,
    lines: List.unmodifiable(lines),
    createdAt: current?.createdAt ?? computed.nowMs,
    updatedAt: computed.nowMs,
  );
}

int _readingOrder(core.HandwritingLine a, core.HandwritingLine b) {
  final c = a.rect.top.compareTo(b.rect.top);
  return c != 0 ? c : a.rect.left.compareTo(b.rect.left);
}

/// 6.13.5 — the conversion sheet's copy (inside update's transform, on the
/// STORED value): stored lines sharing a stroke with a converted line go,
/// the converted lines come in confirmed (alternatives ≤ 5), the other
/// stored lines stay; lines by rect top, then left. sourceRev / engineId:
/// [all] (the converted strokes are every input stroke) → [rev] /
/// [engineId]; otherwise the stored ones (a stale page stays stale — the
/// indexer fills the rest and keeps the confirmed lines by ① / ②).
core.HandwritingText mergeConfirmed(
  core.HandwritingText? current,
  List<core.HandwritingLine> converted, {
  required core.NoteId noteId,
  required core.PageId pageId,
  required String rev,
  required bool all,
  required String engineId,
  required core.EpochMillis nowMs,
}) {
  final convertedIds = {for (final l in converted) ...l.strokeIds};
  final unsorted = <core.HandwritingLine>[
    for (final l in current?.lines ?? const <core.HandwritingLine>[])
      if (!l.strokeIds.any(convertedIds.contains)) l,
    for (final l in converted)
      l.copyWith(
        userConfirmed: true,
        alternatives: _alternatives(l.text, const [], l.alternatives),
      ),
  ];
  // Stable: equal positions keep stored-then-converted order.
  final order = List<int>.generate(unsorted.length, (i) => i)
    ..sort((a, b) {
      final c = _readingOrder(unsorted[a], unsorted[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  final lines = [for (final i in order) unsorted[i]];
  return core.HandwritingText(
    noteId: noteId,
    pageId: pageId,
    engineId: all ? engineId : (current?.engineId ?? engineId),
    sourceRev: all ? rev : (current?.sourceRev ?? ''),
    lines: List.unmodifiable(lines),
    createdAt: current?.createdAt ?? nowMs,
    updatedAt: nowMs,
  );
}
