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
    List<Stroke> ink = const [],
    required this.createdAt,
    int? updatedAt,
    this.deletedAt,
    this.version,
    this.recordingId,
    this.recordingOffsetMs,
  }) : ink = List.unmodifiable(ink),
       updatedAt = updatedAt ?? createdAt;
  @override
  String get type => 'math';

  /// Laid out by INK InkMathRenderer at style.fontSizePt when inserted / edited; INK draws the
  /// formula contain-fitted into the frame (K-6), so devices with other metrics stay inside.
  @override
  final ElementFrame frame;
  final String latex; // ≤ maxLatexLength; INK validate() == null before insert
  final MathStyle style;
  final String? engineId; // provenance: 'manual', 'mathpix/…', 'claude/…'

  /// (math pen, phase 1 — m5-7/research/math-pen-phase1.md 5) The handwriting this formula was
  /// converted from, so it can be reopened as strokes. Each stroke has pageId == [pageId] and
  /// version == null; its id is informational only (reopening gives new ids). Page coordinates:
  /// moved / scaled / rotated with the formula ([transformed]); a LaTeX edit keeps it. Empty for
  /// a formula made another way (math pad, typed LaTeX) or read from JSON without the key.
  /// At most [PageObjectLimits.maxMathInkStrokes] strokes and
  /// [PageObjectLimits.maxMathInkPoints] points in all (checked when a local command is
  /// resolved).
  final List<Stroke> ink;
  @override
  PageRect get bounds => frame.bounds;
  MathObject copyWith({
    ElementFrame? frame,
    String? latex,
    MathStyle? style,
    String? engineId,
    List<Stroke>? ink,
    EpochMillis? updatedAt,
  }) => MathObject(
    id: id,
    pageId: pageId,
    frame: frame ?? this.frame,
    latex: latex ?? this.latex,
    style: style ?? this.style,
    engineId: engineId ?? this.engineId,
    ink: ink ?? this.ink,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt,
    version: version,
    recordingId: recordingId,
    recordingOffsetMs: recordingOffsetMs,
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
  final RecordingId? recordingId;
  @override
  final int? recordingOffsetMs;

  @override
  Set<AssetId> get referencedAssets => const {};

  /// (CORE 6.2.5) frame.transformed(m) + fontSizePt × s clamped [6, 144]; (math pen) every
  /// [ink] stroke through Stroke.transformed with the same m and [scaleWidth].
  ///
  /// (math resize fix) When the font size stops at 6 or 144 pt the frame (and [ink]) stops
  /// with it: m is followed by a uniform scale of clamped ÷ (fontSizePt × s) about the
  /// transformed frame's centre, so the frame stays the formula's laid-out size. Before,
  /// the frame kept growing past 144 pt and the formula raster, laid out at 144 pt, was
  /// stretched over it (blurry), or the frame shrank under 6 pt around a formula that
  /// could not.
  @override
  PageObject transformed(Affine2 m, {bool scaleWidth = true}) {
    final font = _scaled(
      style.fontSizePt,
      m,
      MathStyle.minFontSize,
      MathStyle.maxFontSize,
    );
    final wanted = style.fontSizePt * m.uniformScale;
    var t = m;
    if (wanted > 0 && wanted.isFinite && font != wanted) {
      final c = frame.center.transformed(m);
      final k = font / wanted;
      t = m.then(Affine2.scaling(k, k, originX: c.x, originY: c.y));
    }
    return copyWith(
      frame: frame.transformed(t),
      ink: [for (final s in ink) s.transformed(t, scaleWidth: scaleWidth)],
      style: style.copyWith(fontSizePt: font),
    );
  }

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
    ink: [for (final s in ink) s.copyWith(pageId: pageId)],
    createdAt: createdAt,
    recordingId: recordingId,
    recordingOffsetMs: recordingOffsetMs,
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
    ink: ink,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
    recordingId: recordingId,
    recordingOffsetMs: recordingOffsetMs,
  );

  /// 02-core 4.3 formula + (math pen) the [ink] strokes' Stroke.estimatedBytes.
  @override
  int get estimatedBytes {
    var bytes = 160 + 2 * latex.length;
    for (final s in ink) {
      bytes += s.estimatedBytes;
    }
    return bytes;
  }

  /// `engine` is always written (null when [engineId] is unset — 7.2.7 v2.1). (math pen) `ink`
  /// is always written too: the Stroke JSON list, or null when [ink] is empty.
  @override
  Map<String, Object?> toJson() => _objectJson(this, {
    'latex': latex,
    'style': style.toJson(),
    'engine': engineId,
    'ink': ink.isEmpty ? null : [for (final s in ink) s.toJson()],
  });

  factory MathObject._fromJson(Map<String, Object?> json) => MathObject(
    id: readString(json, 'id'),
    pageId: readString(json, 'pageId'),
    frame: _readFrame(json),
    latex: readString(json, 'latex'),
    style: MathStyle.fromJson(readMap(json, 'style')),
    engineId: readStringOrNull(json, 'engine'),
    ink: _readInk(json),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
    recordingId: readStringOrNull(json, 'recordingId'),
    recordingOffsetMs: readIntOrNull(json, 'recordingOffsetMs'),
  );

  /// (math pen) `ink` is optional: a missing key (JSON of an older app) or null → empty; a
  /// list with any unreadable entry also reads as empty, so the formula itself is kept (the
  /// broken handwriting is lost — design note 5.3, risk R3).
  static List<Stroke> _readInk(Map<String, Object?> json) {
    final raw = json['ink'];
    if (raw is! List) return const [];
    try {
      return [for (final e in raw) Stroke.fromJson(asMap(e, 'ink'))];
    } on FormatException {
      return const [];
    } on ArgumentError {
      return const []; // RangeError included
    } on TypeError {
      return const [];
    }
  }

  static const ListEquality<Stroke> _inkEquality = ListEquality<Stroke>();

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
      _inkEquality.equals(other.ink, ink) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version &&
      other.recordingId == recordingId &&
      other.recordingOffsetMs == recordingOffsetMs;

  @override
  int get hashCode => Object.hash(
    id,
    pageId,
    frame,
    latex,
    style,
    engineId,
    _inkEquality.hash(ink),
    createdAt,
    updatedAt,
    deletedAt,
    version,
    recordingId,
    recordingOffsetMs,
  );

  @override
  String toString() =>
      'MathObject($id, page: $pageId, ${latex.length} chars'
      '${ink.isEmpty ? '' : ', ${ink.length} ink strokes'}'
      '${isDeleted ? ', deleted' : ''})';
}
