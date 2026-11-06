// T16-v2 (integration stage 3 — 07-sync 6.7.2, 6.2.8, C-12): a page object of a type this app
// does not know (a newer app's "sticker": nested map, list, keys of its own) on real CORE —
// UnknownObject keeps every key. U1 a newer app's record (FakeSyncServer.commitRaw) → A
// receives it (UnknownObject) → A removes only that object (RemoveElements) → B receives
// both: on A, B and the server's merged state the object has the original key set and every
// original value; only deletedAt (and the stored updatedAt / version) change. U2 A copies the
// note (LibraryRepository.copyItems): the copy's object keeps the original keys and values
// (new id and page; the store's own meta keys aside).
//
// CORE milestones (6.7.2 table): U1 T28 (+ T27 for the removal), U2 T29.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/core_sync_device.dart';

/// Keys the store stamps on every write (C-11) — their values move with the delete.
const Set<String> _stamped = {'deletedAt', 'updatedAt', 'version'};

const String _stickerId = 'sticker-1';

/// The sticker JSON of [pageId], as a newer app writes it.
Map<String, Object?> _sticker(PageId pageId) => {
  'id': _stickerId,
  'pageId': pageId,
  'type': 'sticker',
  'frame': [400.0, 100.0, 450.0, 150.0, 0.0],
  'stickerId': 'cat-01',
  'tint': {
    'argb': 4294940672,
    'stops': [0.0, 0.5, 1.0],
  },
  'animation': {
    'loop': true,
    'frames': [
      {'at': 0, 'scale': 1.5},
      {'at': 250, 'scale': 1.25},
    ],
  },
  'createdAt': 1,
  'deletedAt': null,
};

/// A, B and a note with one page on both; then the newer app's sticker on that page,
/// received by A and B. Returns the note, the page and the sticker's JSON on A.
Future<(NoteId, PageId, Map<String, Object?>)> _stickerOnBoth(
  CoreScenario s,
  CoreSyncDevice a,
  CoreSyncDevice b,
  String title,
) async {
  final note = (await a.store.library.createNote(title: title)).id;
  final page = (await a.pageIdsOf(note)).single;
  await s.converge([a, b], [note]);

  const ref = EntityRef(EntityKind.pageObject, _stickerId);
  final writer = newerAppStore()
    ..localWrite([
      FakeLocalWrite(
        EntityKind.pageObject,
        _sticker(page),
        changedFields: const {kAllFields},
      ),
    ]);
  final record = upsertOf(writer, ref);
  s.server.commitRaw(kT16Uid, [
    newerAppChunk(
      [ChunkCodec.encodeRecord(record)],
      scope: note,
      maxHlc: record.versions.max,
    ),
  ]);
  await s.until('the sticker on A and B', () async {
    for (final d in [a, b]) {
      if (await d.read(ref.kind, ref.id) == null) return false;
    }
    return true;
  });
  await s.converge([a, b], [note]);
  final original = (await a.jsonOf(ref.kind, ref.id))!;
  expect(original.keys, containsAll(['stickerId', 'tint', 'animation']));
  expect((await a.read(ref.kind, ref.id))!.entity, isA<UnknownObject>());
  expect(await a.objectIdsOf(page), [_stickerId]);
  return (note, page, original);
}

void main() {
  coreScenario('U1 an unknown object type: keys and values survive receive, '
      'delete and a second receive', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final (note, page, original) = await _stickerOnBoth(s, a, b, 'U1');

    await a.core.removeElements(page, [_stickerId]);
    const ref = EntityRef(EntityKind.pageObject, _stickerId);
    await s.converge([a, b], [note], extra: [ref]);

    final sides = {
      'A': (await a.jsonOf(ref.kind, ref.id))!,
      'B': (await b.jsonOf(ref.kind, ref.id))!,
      'server': s.server.mergedState(kT16Uid)[ref]!.doc.json,
    };
    for (final MapEntry(key: name, value: json) in sides.entries) {
      expect(json.keys.toSet(), original.keys.toSet(), reason: name);
      expect(json['deletedAt'], isNotNull, reason: name);
      for (final key in original.keys) {
        if (_stamped.contains(key)) continue;
        expect(json[key], original[key], reason: '$name: $key');
      }
    }
    for (final d in [a, b]) {
      expect(await d.objectIdsOf(page), isEmpty, reason: d.name);
    }
  });

  coreScenario('U2 A copies the note: the copy\'s unknown object keeps the '
      'original keys and values', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final (note, _, original) = await _stickerOnBoth(s, a, b, 'U2');

    final copied = await a.store.library.copyItems([
      NoteRef(note),
    ], targetFolderId: null);
    final copy = copied.single.id;
    await s.converge([a, b], [note, copy]);

    for (final d in [a, b]) {
      final copyPage = (await d.pageIdsOf(copy)).single;
      final objects = await d.core.objectsOf(copyPage);
      expect(objects, hasLength(1), reason: d.name);
      final object = objects.single;
      expect(object, isA<UnknownObject>(), reason: d.name);
      expect(object.id, isNot(_stickerId), reason: d.name);
      final json = object.toJson();
      expect(json.keys.toSet(), original.keys.toSet(), reason: d.name);
      expect(json['pageId'], copyPage, reason: d.name);
      for (final key in original.keys) {
        // id is new, pageId the copy's page; the meta keys are the store's own.
        if (FieldUnits.metaKeys.contains(key) || key == 'pageId') continue;
        expect(json[key], original[key], reason: '${d.name}: $key');
      }
    }
  });
}
