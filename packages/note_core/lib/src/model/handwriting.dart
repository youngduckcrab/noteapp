// lib/src/model/handwriting.dart — (v2.0) 2nd-round contract 7.2.5 / 02-core 4.6, 6.9:
// HandwritingLine, HandwritingText (EntityKind.handwriting, one per page, deterministic id).
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/geometry.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/pending.dart';
import 'stroke.dart';
import 'sync_entity.dart';

@immutable
final class HandwritingLine {
  const HandwritingLine({
    required this.text,
    this.alternatives = const [],
    required this.rect,
    required this.strokeIds,
    this.languageTag = 'ko',
    this.userConfirmed = false,
  });
  final String text; // best, user-chosen or user-edited text
  final List<String> alternatives; // ≤ 5, engine order
  final PageRect rect; // union of the line strokes' pointBounds, page pt
  final List<ElementId> strokeIds;
  final String languageTag; // BCP-47 of the model that produced [text]
  /// Set by the conversion UI. (v2.1) Auto re-recognition keeps a confirmed line's text while
  /// ≥ 80 % of its old strokeIds are still in the new line and the added strokes are small (each
  /// box ≤ the line's median glyph height); otherwise the engine text replaces it, userConfirmed
  /// becomes false and the old confirmed text goes first in alternatives. Rule owner: recog
  /// (05-library 6.9.4); writers merge through HandwritingRepository.update (G-4).
  final bool userConfirmed;
  Map<String, Object?> toJson() => notYet('T20a', 'HandwritingLine.toJson');
  factory HandwritingLine.fromJson(Map<String, Object?> json) =>
      notYet('T20a', 'HandwritingLine.fromJson');

  // CORE 4.6: argument list of the contract's '(v2.1, CP-13) copyWith'
  HandwritingLine copyWith({
    String? text,
    List<String>? alternatives,
    PageRect? rect,
    List<ElementId>? strokeIds,
    String? languageTag,
    bool? userConfirmed,
  }) => notYet('T21', 'HandwritingLine.copyWith');

  // CORE 4.6: ==, hashCode
  @override
  bool operator ==(Object other) =>
      other is HandwritingLine &&
      other.text == text &&
      const ListEquality<String>().equals(other.alternatives, alternatives) &&
      other.rect == rect &&
      const ListEquality<ElementId>().equals(other.strokeIds, strokeIds) &&
      other.languageTag == languageTag &&
      other.userConfirmed == userConfirmed;

  @override
  int get hashCode => Object.hash(
    text,
    const ListEquality<String>().hash(alternatives),
    rect,
    const ListEquality<ElementId>().hash(strokeIds),
    languageTag,
    userConfirmed,
  );

  @override
  String toString() =>
      'HandwritingLine("$text", ${strokeIds.length} strokes, $languageTag'
      '${userConfirmed ? ', confirmed' : ''})';
}

final class HandwritingText implements SyncEntity {
  HandwritingText({
    required this.noteId,
    required this.pageId,
    required this.engineId,
    required this.sourceRev,
    required this.lines,
    required this.createdAt,
    int? updatedAt,
    this.deletedAt,
    this.version,
  }) : id = idFor(pageId),
       updatedAt = updatedAt ?? createdAt;
  static String idFor(PageId pageId) => 'hw_$pageId';

  /// Input strokes = active strokes of the page whose tool is not highlighter / tape / laser.
  /// sourceRev = first 16 hex chars of sha256 over "id:updatedAt;" of those strokes sorted by id.
  static String sourceRevOf(Iterable<Stroke> inputStrokes) =>
      notYet('T21', 'HandwritingText.sourceRevOf');
  static bool isRecognitionInput(Stroke s) =>
      notYet('T21', 'HandwritingText.isRecognitionInput');
  @override
  final String id;
  final NoteId noteId;
  final PageId pageId;
  final String engineId; // 'mlkit-digital-ink/19.0.0:ko' — provenance only.
  // (v2.1) Freshness = same sourceRev AND same language tail (':ko'); a result from another engine,
  // engine version or device is fresh (no double recognition across devices after 실연결).
  final String sourceRev;
  final List<HandwritingLine> lines; // reading order
  @override
  EntityKind get kind => EntityKind.handwriting;
  // createdAt, updatedAt, deletedAt, version, isDeleted, toJson / fromJson, ==,
  // (v2.1, CP-13) copyWith (HandwritingLine too); put validation: 02-core 6.9.4
  final EpochMillis createdAt;
  final EpochMillis updatedAt; // constructor: updatedAt ?? createdAt
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;
  @override
  bool get isDeleted => deletedAt != null;

  @override
  Map<String, Object?> toJson() => notYet('T20a', 'HandwritingText.toJson');
  factory HandwritingText.fromJson(Map<String, Object?> json) =>
      notYet('T20a', 'HandwritingText.fromJson');

  // CORE 4.6: argument list of the contract's '(v2.1, CP-13) copyWith'
  HandwritingText copyWith({
    String? engineId,
    String? sourceRev,
    List<HandwritingLine>? lines,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => notYet('T21', 'HandwritingText.copyWith');

  // CORE 4.6: ==, hashCode, toString
  @override
  bool operator ==(Object other) =>
      other is HandwritingText &&
      other.id == id &&
      other.noteId == noteId &&
      other.pageId == pageId &&
      other.engineId == engineId &&
      other.sourceRev == sourceRev &&
      const ListEquality<HandwritingLine>().equals(other.lines, lines) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    pageId,
    engineId,
    sourceRev,
    const ListEquality<HandwritingLine>().hash(lines),
    createdAt,
    updatedAt,
    deletedAt,
    version,
  );

  @override
  String toString() =>
      'HandwritingText($id, note: $noteId, ${lines.length} lines, $sourceRev'
      '${isDeleted ? ', deleted' : ''})';
}
