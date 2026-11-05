// CORE 6.3 JSON for FakeLocalStore.localWrite in engine tests (test/ only).
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/testing/synthetic_points.dart';
import 'package:sync_engine/testing.dart';

FakeLocalWrite noteWrite(
  String id, {
  String owner = 'user-1',
  String title = 'note',
  String? folderId,
  Set<String> fields = const {kAllFields},
}) => FakeLocalWrite(EntityKind.note, {
  'id': id,
  'ownerId': owner,
  'folderId': folderId,
  'title': title,
  'cover': {'type': 'firstPage'},
  'tags': <String>[],
  'isFavorite': false,
  'sortKey': 'a0',
  'schemaVersion': 1,
  'createdAt': 1,
  'deletedAt': null,
  'trashRootId': null,
}, changedFields: fields);

FakeLocalWrite pageWrite(String id, String noteId, {String sortKey = 'a0'}) =>
    FakeLocalWrite(
      EntityKind.page,
      {
        'id': id,
        'noteId': noteId,
        'sortKey': sortKey,
        'size': [595.2756, 841.8898],
        'background': {'type': 'blank', 'paperColor': 4294967295},
        'createdAt': 1,
        'deletedAt': null,
      },
      changedFields: const {kAllFields},
    );

FakeLocalWrite strokeWrite(
  String id,
  String pageId, {
  int seed = 0,
  int points = 20,
}) => FakeLocalWrite(
  EntityKind.stroke,
  {
    'id': id,
    'pageId': pageId,
    'style': StrokeStyle.defaultsFor(PenTool.ballpoint).toJson(),
    'points': syntheticPointsBase64(seed: seed, count: points),
    'recordingId': null,
    'recordingOffsetMs': null,
    'createdAt': 1,
    'deletedAt': null,
  },
  changedFields: const {kAllFields},
);
