// lib/src/indexer/line_reuse.dart — (internal, pure) what the indexer writes
// and how it merges with the stored value (m5-7/05-library 6.9.3, 6.9.4).
//
// L2-10a: the computed page result (IndexerResult — everything the merge
// needs, so the transform stays pure and synchronous: no clock, no ids, no
// store — 02-core 6.9.4), the freshness rule (sourceRev + language tail) and
// mergeIndexerResult steps 1 and 5 (stored value already fresh → null; the
// value to store). L2-10b adds line reuse (① — reuseLine) and the confirmed
// line rules (② steps 2–4: keep / replace / joined lines).
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

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
  const LineGeometry({required this.strokeBoxes, required this.glyphHeight});

  /// Stroke id → its point box (page pt).
  final Map<core.ElementId, core.PageRect> strokeBoxes;

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

/// 6.9.4 ② — runs inside HandwritingRepository.update's transform: pure and
/// synchronous. [current] is the STORED value (null if none / deleted).
/// L2-10a: step 1 (current fresh → null, nothing written) and step 5 (the
/// computed lines as the page's value). Steps 2–4 (confirmed lines) — L2-10b.
core.HandwritingText? mergeIndexerResult(
  core.HandwritingText? current,
  IndexerResult computed, {
  required core.NoteId noteId,
  required core.PageId pageId,
}) {
  if (current != null && isFreshResult(current, computed.rev, computed.lang)) {
    return null;
  }
  return core.HandwritingText(
    noteId: noteId,
    pageId: pageId,
    engineId: computed.engineId,
    sourceRev: computed.rev,
    lines: computed.lines,
    createdAt: current?.createdAt ?? computed.nowMs,
    updatedAt: computed.nowMs,
  );
}
