// One CORE entity per kind in the sync/backup wire format (CORE 6.3 key table), shared by
// the model, codec and merge tests. Every map decodes with CORE EntityJson.decode.
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
    'id', 'noteId', 'assetId', 'durationMs', 'startedAt', 'createdAt', //
    'updatedAt', 'deletedAt', 'version',
  },
  EntityKind.setting: {'key', 'valueJson', 'updatedAt', 'deletedAt', 'version'},
};

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
  };
}

/// [fixtureJson] decoded by CORE.
SyncEntity fixtureEntity(EntityKind kind, {String? id}) =>
    EntityJson.decode(kind, fixtureJson(kind, id: id));

/// The id of a fixture JSON map (setting: its key).
String fixtureId(Map<String, Object?> json) =>
    (json['id'] ?? json['key'])! as String;
