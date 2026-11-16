// lib/src/model/page_object.dart — (v2.0) part of stroke.dart. 2nd-round contract 7.2.2 /
// 02-core 4.2, 4.3, 6.2: PageObject (sealed) and PageObjectLimits.
part of 'stroke.dart';

/// (v2.0) Every page element that is not a Stroke: EntityKind.pageObject, table
/// `page_objects`, subtype chosen by JSON `type`.
sealed class PageObject extends PageElement {
  const PageObject();
  @override
  EntityKind get kind => EntityKind.pageObject;
  String get type; // 'shape' | 'text' | 'image' | 'math' | unknown
  ElementFrame get frame;
  @override
  EpochMillis? get deletedAt;
  @override
  Hlc? get version;
  @override
  bool get isDeleted => deletedAt != null;

  /// Assets this object references (ImageObject: {assetId}); others empty.
  Set<AssetId> get referencedAssets;

  /// (v2.13-rec) The recording this object was made during (as Stroke.recordingId): set by
  /// EDITOR when the object is created while this note is being recorded, or — for an object
  /// converted from strokes (shape snap, math pen, text pen, conversion) — taken from its
  /// earliest recorded source stroke. Playback dims the object until [recordingOffsetMs]
  /// and tap-to-seek on it seeks there. null: not linked (the object is drawn as usual).
  /// JSON: 'recordingId' / 'recordingOffsetMs', written only when set (older JSON reads as
  /// null). Kept by copyWith / transformed / copyTo (paste, duplicate — as a stroke's).
  /// UnknownObject: read from rawJson when it carries the keys.
  RecordingId? get recordingId;

  /// (v2.13-rec) Audio-timeline ms of the object's creation in [recordingId] (the same scale
  /// as Stroke.recordingOffsetMs); null when not linked.
  int? get recordingOffsetMs;

  /// (v2.13-rec) This object linked to [recordingId] at [recordingOffsetMs] (every other
  /// value unchanged — the same rule for every type, through the JSON).
  PageObject withRecording({
    required RecordingId recordingId,
    required int recordingOffsetMs,
  }) => PageObject.fromJson({
    ...toJson(),
    'recordingId': recordingId,
    'recordingOffsetMs': recordingOffsetMs,
  });

  /// (v2.1) THE object transform rule. CORE's resolver (TransformElements) and every preview
  /// (INK selection / pending display, EDITOR) call this same function (INK review M-2):
  ///   frame / geometry transformed by m; s = m.uniformScale;
  ///   ShapeObject: style.strokeWidth × s clamped [0.1, 30] when [scaleWidth];
  ///   TextBoxObject: style.fontSizePt × s clamped [6, 144] (CP-2 — wrap width and text scale
  ///   together, so the frame height still fits; K-6);
  ///   MathObject: style.fontSizePt × s clamped [6, 144]; ImageObject: frame only;
  ///   UnknownObject: returns itself unchanged.
  PageObject transformed(Affine2 m, {bool scaleWidth = true});

  /// Paste / duplicate / page copy: new id, page and createdAt; version and deletedAt cleared.
  PageObject copyTo({
    required ElementId id,
    required PageId pageId,
    required EpochMillis createdAt,
  });
  PageObject copyWithMeta({
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  });

  /// (v2.1, CP-4) History memory estimate (02-core 4.3 formula).
  /// (contract: '02-core 4.3 formula') History memory estimate (6.4.4):
  /// 160 B + 2·text.length (text) | 2·latex.length (math) | 16·points (polyline)
  /// | 2·(UTF-16 length of jsonEncode(rawJson)) (unknown).
  int get estimatedBytes;
  @override
  Map<String, Object?> toJson();

  /// Dispatches on `type`; an unknown type → UnknownObject (never throws for that reason).
  /// (v2.1, CP-6) A known type with an enum name this app does not know (`shape`, `dash`,
  /// `arrowHeads`, `align`) is also read as UnknownObject. Never normalizes (remote values
  /// round-trip unchanged; normalization happens when a LOCAL command is resolved).
  /// (CORE 6.2.6) A missing or wrong required key of a known type is a FormatException (the
  /// record is dropped — as Stroke.fromJson); unknown keys of a known type are ignored.
  factory PageObject.fromJson(Map<String, Object?> json) {
    final type = readString(json, 'type');
    try {
      switch (type) {
        case 'shape':
          return ShapeObject._fromJson(json);
        case 'text':
          return TextBoxObject._fromJson(json);
        case 'image':
          return ImageObject._fromJson(json);
        case 'math':
          return MathObject._fromJson(json);
      }
    } on UnknownEnumNameException {
      return UnknownObject(json);
    }
    return UnknownObject(json);
  }
}

/// The common keys every object writes, in the 7.2.7 order: id, pageId, type, frame, then the
/// type's keys ([body]), then createdAt, updatedAt, deletedAt, version (CORE 6.3).
Map<String, Object?> _objectJson(PageObject o, Map<String, Object?> body) => {
  'id': o.id,
  'pageId': o.pageId,
  'type': o.type,
  'frame': o.frame.toJson(),
  ...body,
  // (v2.13-rec) only when linked: older JSON (and every unlinked object) keeps its key set
  if (o.recordingId != null) ...{
    'recordingId': o.recordingId,
    'recordingOffsetMs': o.recordingOffsetMs,
  },
  'createdAt': o.createdAt,
  'updatedAt': o.updatedAt,
  'deletedAt': o.deletedAt,
  'version': o.version?.toString(),
};

/// [value] × m.uniformScale clamped to [min, max] (CORE 6.2.5).
double _scaled(double value, Affine2 m, double min, double max) =>
    (value * m.uniformScale).clamp(min, max).toDouble();

ElementFrame _readFrame(Map<String, Object?> json) =>
    ElementFrame.fromJson(readList(json, 'frame'));

abstract final class PageObjectLimits {
  static const int maxObjectsPerPage = 2000;
  static const int maxTextLength = 10000; // TextBoxObject.text, String.length
  static const int maxLatexLength = 4000;
  static const int maxPolylinePoints = 64;

  /// (math pen) MathObject.ink: at most this many strokes …
  static const int maxMathInkStrokes = 400;

  /// … and this many points over all of them.
  static const int maxMathInkPoints = 40000;
}
