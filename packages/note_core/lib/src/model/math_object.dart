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
  }) => MathObject(
    id: id,
    pageId: pageId,
    frame: frame ?? this.frame,
    latex: latex ?? this.latex,
    style: style ?? this.style,
    engineId: engineId ?? this.engineId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt,
    version: version,
  );

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

  /// (CORE 6.2.5) frame.transformed(m) + fontSizePt × s clamped [6, 144].
  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) => copyWith(
    frame: frame.transformed(m),
    style: style.copyWith(
      fontSizePt: _scaled(
        style.fontSizePt,
        m,
        MathStyle.minFontSize,
        MathStyle.maxFontSize,
      ),
    ),
  );

  @override
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  }) => MathObject(
    id: id,
    pageId: pageId,
    frame: frame,
    latex: latex,
    style: style,
    engineId: engineId,
    createdAt: createdAt,
  );

  @override
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => MathObject(
    id: id,
    pageId: pageId,
    frame: frame,
    latex: latex,
    style: style,
    engineId: engineId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );

  @override
  int get estimatedBytes => 160 + 2 * latex.length;

  /// `engine` is always written (null when [engineId] is unset — 7.2.7 v2.1).
  @override
  Map<String, Object?> toJson() => _objectJson(this, {
    'latex': latex,
    'style': style.toJson(),
    'engine': engineId,
  });

  factory MathObject._fromJson(Map<String, Object?> json) => MathObject(
    id: readString(json, 'id'),
    pageId: readString(json, 'pageId'),
    frame: _readFrame(json),
    latex: readString(json, 'latex'),
    style: MathStyle.fromJson(readMap(json, 'style')),
    engineId: readStringOrNull(json, 'engine'),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
  );

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
