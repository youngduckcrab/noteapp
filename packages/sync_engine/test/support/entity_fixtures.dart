// One CORE entity per kind in the sync/backup wire format (CORE 6.3 key table), shared by
// the model, codec and merge tests. Every map decodes with CORE EntityJson.decode.
//
// (2nd round, R2-B7a — 07-sync 6.4, 5.1.5) pageObject and handwriting JSON come from the
// contract constructors (real from CORE B2-alpha) and CORE's T20a toJson(); recording
// JSON carries `title`. The page object helpers of note_core/testing.dart (CORE T23b) are
// not used here, so every test that goes through these maps is decided at the CORE T20a
// commit (07-sync 8.1: no use of them in this package's test/).
import 'package:note_core/note_core.dart';

const String kNodeA = '3f2a9c0d11e0b7a4';
const String kNodeB = 'b7a43f2a9c0d11e0';

/// HLC text at [millis] / [counter] on [node].
String hlcText(int millis, {int counter = 0, String node = kNodeA}) =>
    Hlc(millis, counter, node).toString();

const int kT0 = 1793750400000;

/// CORE 6.3 keys per kind (the table, meta keys included).
const Map<EntityKind, Set<String>> kCoreJsonKeys = {
  EntityKind.folder: {
    'id', 'ownerId', 'parentId', 'name', 'color', 'icon', 'sortKey', //
    'createdAt', 'updatedAt', 'deletedAt', 'trashRootId', 'version',
  },
  EntityKind.note: {
    'id', 'ownerId', 'folderId', 'title', 'cover', 'tags', 'isFavorite', //
    'sortKey', 'schemaVersion', 'createdAt', 'updatedAt', 'deletedAt',
    'trashRootId', 'version',
  },
  EntityKind.page: {
    'id', 'noteId', 'sortKey', 'size', 'background', 'createdAt', //
    'updatedAt', 'deletedAt', 'version',
  },
  EntityKind.stroke: {
    'id', 'pageId', 'style', 'points', 'recordingId', 'recordingOffsetMs', //
    'createdAt', 'updatedAt', 'deletedAt', 'version',
  },
  EntityKind.penPreset: {
    'id', 'ownerId', 'name', 'style', 'group', 'pinned', 'sortKey', //
    'createdAt', 'updatedAt', 'deletedAt', 'version',
  },
  EntityKind.asset: {
    'id', 'ownerId', 'type', 'mimeType', 'size', 'fileName', 'storagePath', //
    'createdAt', 'deletedAt', 'version',
  },
  EntityKind.recording: {
    'id', 'noteId', 'assetId', 'durationMs', 'startedAt', 'title', //
    'createdAt', 'updatedAt', 'deletedAt', 'version',
  },
  EntityKind.setting: {'key', 'valueJson', 'updatedAt', 'deletedAt', 'version'},
  // The union of [kPageObjectTypeKeys] (07-sync 6.2.1).
  EntityKind.pageObject: {
    'id', 'pageId', 'type', 'frame', 'shape', 'geometry', 'style', 'text', //
    'assetId', 'px', 'latex', 'engine', 'ink', 'createdAt', 'updatedAt',
    'deletedAt', 'version',
  },
  EntityKind.handwriting: {
    'id', 'noteId', 'pageId', 'engineId', 'sourceRev', 'lines', 'createdAt', //
    'updatedAt', 'deletedAt', 'version',
  },
  // (v2.17-md, C217M-02)
  EntityKind.markdown: {
    'id', 'noteId', 'text', 'createdAt', 'updatedAt', 'deletedAt', 'version', //
  },
};

/// The 8 keys every page object writes (contract 7.2.7).
const Set<String> _kObjectCommonKeys = {
  'id', 'pageId', 'type', 'frame', 'createdAt', 'updatedAt', 'deletedAt', //
  'version',
};

/// Page object JSON keys per known `type` (contract 7.2.7, 07-sync 6.2.1). Every key is
/// always written, also when its value is null (`math` `engine` — C21-11). An unknown
/// `type` (UnknownObject) has no fixed key set and is not listed.
const Map<String, Set<String>> kPageObjectTypeKeys = {
  'shape': {..._kObjectCommonKeys, 'shape', 'geometry', 'style'},
  'text': {..._kObjectCommonKeys, 'text', 'style'},
  'image': {..._kObjectCommonKeys, 'assetId', 'px'},
  // (math pen) `ink`: always written, null when the formula has no handwriting.
  'math': {..._kObjectCommonKeys, 'latex', 'style', 'engine', 'ink'},
};

/// The asset of the image object fixture (64 lowercase hex).
const String kImageAssetId =
    '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

/// One page object of [type] on page 'p1' (version at [kT0] on [kNodeA]), built with the
/// contract constructors: 'shape' · 'text' · 'image' · 'math' → ShapeObject (rectangle,
/// PolylineGeometry) · TextBoxObject · ImageObject · MathObject (no engine); 'sticker' →
/// UnknownObject with the unknown key `stickerId` and a nested map. Rectangles, text and
/// sizes are the defaults of the contract 7.6 page object test helpers.
PageObject objectFixture(String type, {String? id}) {
  final version = Hlc(kT0, 0, kNodeA);
  const pageId = 'p1';
  return switch (type) {
    'shape' => ShapeObject(
      id: id ?? 'o-shape',
      pageId: pageId,
      shapeKind: ShapeKind.rectangle,
      geometry: const PolylineGeometry([
        PagePoint(100, 100),
        PagePoint(300, 100),
        PagePoint(300, 220),
        PagePoint(100, 220),
      ], closed: true),
      style: const ShapeStyle(strokeColorArgb: 0xFF1A1A1A),
      createdAt: kT0,
      version: version,
    ),
    'text' => TextBoxObject(
      id: id ?? 'o-text',
      pageId: pageId,
      frame: const ElementFrame(PageRect(100, 300, 400, 340)),
      text: '안녕 hello',
      style: const TextBoxStyle(),
      createdAt: kT0,
      version: version,
    ),
    'image' => ImageObject(
      id: id ?? 'o-image',
      pageId: pageId,
      frame: const ElementFrame(PageRect(100, 400, 300, 550)),
      assetId: kImageAssetId,
      pixelWidth: 400,
      pixelHeight: 300,
      createdAt: kT0,
      version: version,
    ),
    'math' => MathObject(
      id: id ?? 'o-math',
      pageId: pageId,
      frame: const ElementFrame(PageRect(100, 600, 200, 650)),
      latex: r'\frac{a}{b}',
      style: const MathStyle(),
      createdAt: kT0,
      version: version,
    ),
    'sticker' => UnknownObject({
      'id': id ?? 'o-sticker',
      'pageId': pageId,
      'type': 'sticker',
      'frame': [400.0, 100.0, 450.0, 150.0, 0.0],
      'stickerId': 'cat-01',
      'tint': {
        'argb': 4294940672,
        'stops': [0.0, 0.5, 1.0],
      },
      'createdAt': kT0,
      'updatedAt': kT0,
      'deletedAt': null,
      'version': version.toString(),
    }),
    _ => throw ArgumentError.value(type, 'type', 'no object fixture'),
  };
}

/// The handwriting result fixture of page 'p1' in note 'n1': two lines, one with
/// alternatives, one confirmed by the user. Its id is always `hw_<pageId>`
/// (HandwritingText.idFor); an [id] must have that form and names the page.
/// (v2.17-md) An MD 문서 body (BOM, CRLF, Korean) of note n1 (id `md_<noteId>`).
MarkdownText markdownFixture({String? id}) {
  final String noteId;
  if (id == null) {
    noteId = 'n1';
  } else if (id.startsWith('md_') && id.length > 3) {
    noteId = id.substring(3);
  } else {
    throw ArgumentError.value(id, 'id', 'a markdown body id is md_<noteId>');
  }
  return MarkdownText(
    noteId: noteId,
    text: '\uFEFF# 강의 요약\r\n\r\n- [ ] 복습\r\n',
    createdAt: kT0,
    version: Hlc.parse(hlcText(kT0)),
  );
}

HandwritingText handwritingFixture({String? id}) {
  final String pageId;
  if (id == null) {
    pageId = 'p1';
  } else if (id.startsWith('hw_') && id.length > 3) {
    pageId = id.substring(3);
  } else {
    throw ArgumentError.value(id, 'id', 'a handwriting id is hw_<pageId>');
  }
  return HandwritingText(
    noteId: 'n1',
    pageId: pageId,
    engineId: 'mlkit-digital-ink/19.0.0:ko',
    sourceRev: '0123456789abcdef',
    lines: const [
      HandwritingLine(
        text: '미분 방정식',
        alternatives: ['미분 방정석', '미분방정식'],
        rect: PageRect(40, 80, 320, 120),
        strokeIds: ['s1', 's2'],
      ),
      HandwritingLine(
        text: 'hello 2학기',
        rect: PageRect(40, 140, 300, 182),
        strokeIds: ['s3'],
        userConfirmed: true,
      ),
    ],
    createdAt: kT0,
    version: Hlc(kT0, 0, kNodeA),
  );
}

Map<String, Object?> _style({double width = 2.2, double opacity = 0.9}) => {
  'tool': 'fountain',
  'color': 4279970411,
  'width': width,
  'opacity': opacity,
  'pressureSensitivity': 0.8,
  'pressureCurve': [0.25, 0.25, 0.75, 0.75],
  'smoothing': 0.55,
  'extras': <String, Object?>{},
};

/// CORE G1 points (CORE 6.2.4), base64.
const String kG1PointsBase64 = 'AQED0A9klgGgHzIA9AMyMgBUUg==';

/// Fresh JSON of one entity of [kind] (version at [kT0] on [kNodeA]).
Map<String, Object?> fixtureJson(EntityKind kind, {String? id}) {
  final v = hlcText(kT0);
  return switch (kind) {
    EntityKind.folder => {
      'id': id ?? 'f1',
      'ownerId': 'local',
      'parentId': null,
      'name': '수업',
      'color': 4281944491,
      'icon': 'school',
      'sortKey': 'a0',
      'createdAt': kT0,
      'updatedAt': kT0,
      'deletedAt': null,
      'trashRootId': null,
      'version': v,
    },
    EntityKind.note => {
      'id': id ?? 'n1',
      'ownerId': 'local',
      'folderId': 'f1',
      'title': '강의노트',
      'cover': {'type': 'color', 'color': 4294960640},
      'tags': ['math', '2학기'],
      'isFavorite': true,
      'sortKey': 'a1',
      'schemaVersion': 1,
      'createdAt': kT0,
      'updatedAt': kT0,
      'deletedAt': null,
      'trashRootId': null,
      'version': v,
    },
    EntityKind.page => {
      'id': id ?? 'p1',
      'noteId': 'n1',
      'sortKey': 'a1',
      'size': [540.5, 960.5],
      'background': {
        'type': 'template',
        'paperColor': 4280295716,
        'template': {
          'kind': 'cornell',
          'spacing': 24.5,
          'lineColor': null,
          'lineWidth': null,
          'extras': {'cueColumnWidth': 150, 'showMarginLine': true},
        },
      },
      'createdAt': kT0,
      'updatedAt': kT0,
      'deletedAt': null,
      'version': v,
    },
    EntityKind.stroke => {
      'id': id ?? 's1',
      'pageId': 'p1',
      'style': _style(),
      'points': kG1PointsBase64,
      'recordingId': null,
      'recordingOffsetMs': null,
      'createdAt': kT0,
      'updatedAt': kT0,
      'deletedAt': null,
      'version': v,
    },
    EntityKind.penPreset => {
      'id': id ?? 'preset-1',
      'ownerId': 'local',
      'name': '만년필',
      'style': _style(),
      'group': null,
      'pinned': true,
      'sortKey': 'a2',
      'createdAt': kT0,
      'updatedAt': kT0,
      'deletedAt': null,
      'version': v,
    },
    EntityKind.asset => {
      'id':
          id ??
          'efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37',
      'ownerId': 'local',
      'type': 'pdf',
      'mimeType': 'application/pdf',
      'size': 758619,
      'fileName': '강의자료.pdf',
      'storagePath': null,
      'createdAt': kT0,
      'deletedAt': null,
      'version': v,
    },
    EntityKind.recording => {
      'id': id ?? 'r1',
      'noteId': 'n1',
      'assetId':
          'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a',
      'durationMs': 61000,
      'startedAt': kT0 - 61000,
      'title': '1교시 녹음',
      'createdAt': kT0,
      'updatedAt': kT0,
      'deletedAt': null,
      'version': v,
    },
    EntityKind.setting => {
      'key': id ?? 'editor.theme',
      'valueJson': '"dark"',
      'updatedAt': kT0,
      'deletedAt': null,
      'version': v,
    },
    EntityKind.pageObject => objectFixture('shape', id: id).toJson(),
    EntityKind.handwriting => handwritingFixture(id: id).toJson(),
    EntityKind.markdown => markdownFixture(id: id).toJson(),
  };
}

/// [fixtureJson] decoded by CORE.
SyncEntity fixtureEntity(EntityKind kind, {String? id}) =>
    EntityJson.decode(kind, fixtureJson(kind, id: id));

/// The id of a fixture JSON map (setting: its key).
String fixtureId(Map<String, Object?> json) =>
    (json['id'] ?? json['key'])! as String;
