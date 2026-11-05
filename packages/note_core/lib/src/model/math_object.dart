// lib/src/model/math_object.dart — (v2.0) part of stroke.dart. 2nd-round contract 7.2.2 /
// 02-core 4.2, 4.3.
part of 'stroke.dart';

final class MathObject extends PageObject {
  MathObject({
    required this.id,
    required this.pageId,
    required this.frame,
    required this.latex,
    required this.style,
    this.engineId,
    required this.createdAt,
    int? updatedAt,
    this.deletedAt,
    this.version,
  }) : updatedAt = updatedAt ?? createdAt;
  @override
  String get type => 'math';

  /// Laid out by INK InkMathRenderer at style.fontSizePt when inserted / edited; INK draws the
  /// formula contain-fitted into the frame (K-6), so devices with other metrics stay inside.
  @override
  final ElementFrame frame;
  final String latex; // ≤ maxLatexLength; INK validate() == null before insert
  final MathStyle style;
  final String? engineId; // provenance: 'manual', 'mathpix/…', 'claude/…'
  @override
  PageRect get bounds => frame.bounds;
  MathObject copyWith({
    ElementFrame? frame,
    String? latex,
    MathStyle? style,
    String? engineId,
    EpochMillis? updatedAt,
  }) => notYet('T20b', 'MathObject.copyWith');

  // CORE 4.3: same member set as ShapeObject
  @override
  final ElementId id;
  @override
  final PageId pageId;
  @override
  final EpochMillis createdAt;
  @override
  final EpochMillis updatedAt; // constructor: updatedAt ?? createdAt (as Stroke)
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;

  @override
  Set<AssetId> get referencedAssets => const {};

  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) =>
      notYet('T20b', 'MathObject.transformed');

  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => notYet('T20b', 'MathObject.copyTo');

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => notYet('T20b', 'MathObject.copyWithMeta');

  @override
  int get estimatedBytes => notYet('T20b', 'MathObject.estimatedBytes');

  @override
  Map<String, Object?> toJson() => notYet('T20a', 'MathObject.toJson');

  // CORE 4.3: ==, hashCode over every field
  @override
  bool operator ==(Object other) =>
      other is MathObject &&
      other.id == id &&
      other.pageId == pageId &&
      other.frame == frame &&
      other.latex == latex &&
      other.style == style &&
      other.engineId == engineId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    pageId,
    frame,
    latex,
    style,
    engineId,
    createdAt,
    updatedAt,
    deletedAt,
    version,
  );

  @override
  String toString() =>
      'MathObject($id, page: $pageId, ${latex.length} chars'
      '${isDeleted ? ', deleted' : ''})';
}
